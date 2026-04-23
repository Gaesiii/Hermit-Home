import type { VercelRequest, VercelResponse } from '@vercel/node';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { getUsersCollection, hashPassword, toPublicUser, verifyPassword } from '../../lib/userModel';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';
import {
  buildPasswordResetLink,
  getPasswordResetTokenTtlMinutes,
  sendPasswordResetEmail,
} from '../../lib/passwordResetMailer';
import {
  consumePasswordResetToken,
  createPasswordResetToken,
  findPasswordResetToken,
  invalidateAllPasswordResetTokensForUser,
} from '../../lib/passwordResetModel';
import { toUtc7Iso } from '../../lib/timezone';

const AUTH_ALLOWED_METHODS = ['GET', 'POST'] as const;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const JWT_EXPIRES_IN = '7d';
const DEFAULT_APP_DEEPLINK = 'hermithome://reset-password';
const INVALID_CREDENTIALS = 'Invalid email or password.';
const FORGOT_SUCCESS_MESSAGE =
  'If an account with that email exists, a password reset link has been sent.';
const INVALID_TOKEN_MESSAGE = 'Invalid or expired reset token.';
const DUMMY_HASH =
  '$2b$12$Kix4fBjlHfmFRRpSCRVLMuJN0XFdOfuBGBlfAJqvR4L.5tq5.7Dly';

type AuthAction =
  | 'register'
  | 'login'
  | 'forgot-password'
  | 'reset-password'
  | 'validate-reset-token'
  | 'reset-link';

type LinkStatus =
  | 'valid'
  | 'missing_token'
  | 'invalid_token'
  | 'expired_token'
  | 'used_token'
  | 'user_not_found'
  | 'server_error';

type SerializableError = {
  name?: string;
  message?: string;
  code?: string | number;
  response?: string;
  responseCode?: number;
  command?: string;
};

function readHeaderValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }

  return null;
}

function readQueryValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }

  return null;
}

function normalizeAction(rawAction: string): AuthAction | null {
  const normalized = rawAction.trim().toLowerCase();
  switch (normalized) {
    case 'register':
      return 'register';
    case 'login':
      return 'login';
    case 'forgot':
    case 'forgot-password':
      return 'forgot-password';
    case 'reset':
    case 'reset-password':
      return 'reset-password';
    case 'validate-reset-token':
    case 'validate-reset':
    case 'validate-token':
      return 'validate-reset-token';
    case 'reset-link':
    case 'reset-password-link':
      return 'reset-link';
    default:
      return null;
  }
}

function detectPasswordResetMode(req: VercelRequest): 'forgot-password' | 'reset-password' | null {
  const mode = readQueryValue(req.query.mode)?.trim().toLowerCase();
  if (mode === 'forgot') {
    return 'forgot-password';
  }
  if (mode === 'reset') {
    return 'reset-password';
  }

  const body = req.body as Record<string, unknown> | undefined;
  if (!body || typeof body !== 'object') {
    return null;
  }

  if (typeof body.token === 'string' || typeof body.password === 'string') {
    return 'reset-password';
  }

  if (typeof body.email === 'string') {
    return 'forgot-password';
  }

  return null;
}

function resolveAction(req: VercelRequest): AuthAction | null {
  const queryAction = readQueryValue(req.query.action);
  if (queryAction) {
    const directAction = normalizeAction(queryAction);
    if (directAction) {
      return directAction;
    }

    if (queryAction.trim().toLowerCase() === 'password-reset') {
      return detectPasswordResetMode(req);
    }
  }

  const modeAction = detectPasswordResetMode(req);
  if (modeAction) {
    return modeAction;
  }

  if (req.method === 'GET' && readQueryValue(req.query.token)) {
    return 'reset-link';
  }

  return null;
}

function getJwtSecret(): string | null {
  const value = process.env.JWT_SECRET;
  if (!value || value.trim().length === 0) {
    return null;
  }
  return value;
}

function validateRegisterInput(body: unknown): { email: string; password: string } | string {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  const { email, password } = body as Record<string, unknown>;
  if (!email || typeof email !== 'string' || !EMAIL_RE.test(email)) {
    return 'A valid email address is required.';
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    return 'Password must be at least 8 characters.';
  }

  return { email: email.toLowerCase().trim(), password };
}

async function handleRegister(req: VercelRequest, res: VercelResponse): Promise<void> {
  const input = validateRegisterInput(req.body);
  if (typeof input === 'string') {
    res.status(400).json({ error: input });
    return;
  }

  const { email, password } = input;

  try {
    const users = await getUsersCollection();
    const existing = await users.findOne({ email });
    if (existing) {
      res.status(409).json({ error: 'An account with that email already exists.' });
      return;
    }

    const passwordHash = await hashPassword(password);
    const now = new Date();
    const result = await users.insertOne({
      email,
      passwordHash,
      createdAt: now,
      updatedAt: now,
    });

    res.status(201).json({
      message: 'Account created successfully.',
      user: toPublicUser({
        _id: result.insertedId,
        email,
        passwordHash,
        createdAt: now,
        updatedAt: now,
      }),
    });
  } catch (error: unknown) {
    const code =
      typeof error === 'object' && error !== null && 'code' in error
        ? (error as { code?: unknown }).code
        : undefined;

    if (code === 11000) {
      res.status(409).json({ error: 'An account with that email already exists.' });
      return;
    }

    console.error('[POST /api/auth?action=register]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handleLogin(req: VercelRequest, res: VercelResponse): Promise<void> {
  const jwtSecret = getJwtSecret();
  if (!jwtSecret) {
    console.error(
      '[POST /api/auth?action=login] Missing required environment variable: JWT_SECRET',
    );
    res.status(500).json({ error: 'Server authentication is not configured.' });
    return;
  }

  const { email, password } = (req.body ?? {}) as Record<string, unknown>;
  if (!email || typeof email !== 'string') {
    res.status(400).json({ error: 'Email is required.' });
    return;
  }
  if (!password || typeof password !== 'string') {
    res.status(400).json({ error: 'Password is required.' });
    return;
  }

  try {
    const users = await getUsersCollection();
    const user = await users.findOne({ email: email.toLowerCase().trim() });

    if (!user) {
      await bcrypt.compare(password, DUMMY_HASH);
      res.status(401).json({ error: INVALID_CREDENTIALS });
      return;
    }

    if (!user._id || !user.passwordHash || typeof user.passwordHash !== 'string') {
      console.error('[POST /api/auth?action=login] Invalid user record schema', {
        userId: user._id?.toString?.(),
        email: user.email,
      });
      res.status(500).json({ error: 'Server authentication is not configured.' });
      return;
    }

    const isValid = await verifyPassword(password, user.passwordHash);
    if (!isValid) {
      res.status(401).json({ error: INVALID_CREDENTIALS });
      return;
    }

    const token = jwt.sign(
      {
        userId: user._id.toString(),
        email: user.email,
      },
      jwtSecret,
      { expiresIn: JWT_EXPIRES_IN },
    );

    res.status(200).json({
      token,
      user: toPublicUser(user),
    });
  } catch (error: unknown) {
    console.error('[POST /api/auth?action=login]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

function validateForgotInput(body: unknown): { email: string } | string {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  const { email } = body as Record<string, unknown>;
  if (!email || typeof email !== 'string' || !EMAIL_RE.test(email)) {
    return 'A valid email address is required.';
  }

  return { email: email.toLowerCase().trim() };
}

function validateResetInput(body: unknown): { token: string; password: string } | string {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  const { token, password } = body as Record<string, unknown>;
  if (!token || typeof token !== 'string' || token.trim().length < 20) {
    return 'A valid reset token is required.';
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    return 'Password must be at least 8 characters.';
  }

  return {
    token: token.trim(),
    password,
  };
}

function validateResetTokenInput(body: unknown): { token: string } | string {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  const { token } = body as Record<string, unknown>;
  if (!token || typeof token !== 'string' || token.trim().length < 20) {
    return 'A valid reset token is required.';
  }

  return { token: token.trim() };
}

function buildAccountHint(email: string): string {
  const normalized = email.trim().toLowerCase();
  const atIndex = normalized.indexOf('@');
  if (atIndex <= 0) {
    return normalized;
  }

  const local = normalized.slice(0, atIndex);
  const domain = normalized.slice(atIndex + 1);
  if (!domain) {
    return normalized;
  }

  const visibleCount = Math.min(2, local.length);
  const visible = local.slice(0, visibleCount);
  const hiddenCount = Math.max(1, local.length - visibleCount);
  return `${visible}${'*'.repeat(hiddenCount)}@${domain}`;
}

function readClientIp(req: VercelRequest): string | null {
  const forwardedFor = readHeaderValue(req.headers['x-forwarded-for']);
  if (forwardedFor) {
    const firstIp = forwardedFor.split(',')[0]?.trim();
    if (firstIp) {
      return firstIp;
    }
  }

  const realIp = readHeaderValue(req.headers['x-real-ip']);
  return realIp?.trim() || null;
}

function isDebugEnabled(req: VercelRequest): boolean {
  const headerDebug = readHeaderValue(req.headers['x-debug-password-reset']);
  if (headerDebug === '1' || headerDebug?.toLowerCase() === 'true') {
    return true;
  }

  const envDebug = (process.env.PASSWORD_RESET_DEBUG || '').trim().toLowerCase();
  return envDebug === '1' || envDebug === 'true' || envDebug === 'yes' || envDebug === 'on';
}

function serializeError(error: unknown): SerializableError {
  if (typeof error !== 'object' || error === null) {
    return { message: String(error) };
  }

  const typed = error as Record<string, unknown>;
  return {
    name: typeof typed.name === 'string' ? typed.name : undefined,
    message: typeof typed.message === 'string' ? typed.message : undefined,
    code:
      typeof typed.code === 'string' || typeof typed.code === 'number'
        ? typed.code
        : undefined,
    response: typeof typed.response === 'string' ? typed.response : undefined,
    responseCode: typeof typed.responseCode === 'number' ? typed.responseCode : undefined,
    command: typeof typed.command === 'string' ? typed.command : undefined,
  };
}

async function handleForgotPassword(req: VercelRequest, res: VercelResponse): Promise<void> {
  const input = validateForgotInput(req.body);
  if (typeof input === 'string') {
    res.status(400).json({ error: input });
    return;
  }

  const { email } = input;

  try {
    const users = await getUsersCollection();
    const user = await users.findOne({ email });
    const tokenTtlMinutes = getPasswordResetTokenTtlMinutes();

    if (user && user._id) {
      const { rawToken } = await createPasswordResetToken({
        userId: user._id,
        email: user.email,
        tokenTtlMinutes,
        requestedIp: readClientIp(req),
        requestedUserAgent: readHeaderValue(req.headers['user-agent']),
      });

      const resetLink = buildPasswordResetLink(rawToken);
      await sendPasswordResetEmail({
        toEmail: user.email,
        resetLink,
        tokenTtlMinutes,
      });
    }

    res.status(200).json({ message: FORGOT_SUCCESS_MESSAGE });
  } catch (error: unknown) {
    const debugError = serializeError(error);
    console.error('[POST /api/auth?action=forgot-password]', debugError);

    if (isDebugEnabled(req)) {
      res.status(500).json({
        error: 'An unexpected error occurred. Please try again.',
        debug: debugError,
      });
      return;
    }

    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handleResetPassword(req: VercelRequest, res: VercelResponse): Promise<void> {
  const input = validateResetInput(req.body);
  if (typeof input === 'string') {
    res.status(400).json({ error: input });
    return;
  }

  const { token, password } = input;

  try {
    const resetRecord = await consumePasswordResetToken(token);
    if (!resetRecord) {
      res.status(400).json({ error: INVALID_TOKEN_MESSAGE });
      return;
    }

    const users = await getUsersCollection();
    const user = await users.findOne({
      _id: resetRecord.userId,
      email: resetRecord.email,
    });

    if (!user || !user._id) {
      res.status(400).json({ error: INVALID_TOKEN_MESSAGE });
      return;
    }

    const passwordHash = await hashPassword(password);
    const now = new Date();
    const updateResult = await users.updateOne(
      { _id: user._id },
      {
        $set: {
          passwordHash,
          updatedAt: now,
        },
      },
    );

    if (updateResult.matchedCount !== 1) {
      res.status(500).json({ error: 'Failed to reset password.' });
      return;
    }

    await invalidateAllPasswordResetTokensForUser(user._id);
    res.status(200).json({ message: 'Password reset successfully.' });
  } catch (error: unknown) {
    console.error('[POST /api/auth?action=reset-password]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handleValidateResetToken(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const input = validateResetTokenInput(req.body);
  if (typeof input === 'string') {
    res.status(400).json({ error: input });
    return;
  }

  try {
    const resetToken = await findPasswordResetToken(input.token);
    if (
      !resetToken ||
      !resetToken.userId ||
      resetToken.usedAt ||
      !resetToken.expiresAt ||
      resetToken.expiresAt.getTime() <= Date.now()
    ) {
      res.status(400).json({ error: INVALID_TOKEN_MESSAGE });
      return;
    }

    const users = await getUsersCollection();
    const user = await users.findOne({
      _id: resetToken.userId,
      email: resetToken.email,
    });

    if (!user || !user.email) {
      res.status(400).json({ error: INVALID_TOKEN_MESSAGE });
      return;
    }

    res.status(200).json({
      valid: true,
      accountHint: buildAccountHint(user.email),
      userId: resetToken.userId.toHexString(),
      expiresAt:
        toUtc7Iso(resetToken.expiresAt) ?? resetToken.expiresAt.toISOString(),
    });
  } catch (error: unknown) {
    console.error('[POST /api/auth?action=validate-reset-token]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

function readAppDeepLinkBase(): string {
  return (process.env.PASSWORD_RESET_APP_DEEP_LINK_URL || '').trim() || DEFAULT_APP_DEEPLINK;
}

function buildDeepLink(params: {
  status: LinkStatus;
  token?: string;
  userId?: string;
  expiresAt?: string;
}): string {
  const rawBase = readAppDeepLinkBase();
  let deepLink: URL;

  try {
    deepLink = new URL(rawBase);
  } catch {
    deepLink = new URL(DEFAULT_APP_DEEPLINK);
  }

  deepLink.searchParams.set('status', params.status);

  if (params.token) {
    deepLink.searchParams.set('token', params.token);
  }
  if (params.userId) {
    deepLink.searchParams.set('userId', params.userId);
  }
  if (params.expiresAt) {
    deepLink.searchParams.set('expiresAt', params.expiresAt);
  }

  return deepLink.toString();
}

function redirectToApp(res: VercelResponse, params: Parameters<typeof buildDeepLink>[0]): void {
  const location = buildDeepLink(params);
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  res.setHeader('Location', location);
  res.status(302).end();
}

async function handleResetPasswordLink(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const token = readQueryValue(req.query.token)?.trim() || '';
  if (!token) {
    redirectToApp(res, { status: 'missing_token' });
    return;
  }

  try {
    const resetToken = await findPasswordResetToken(token);
    if (!resetToken || !resetToken.userId) {
      redirectToApp(res, { status: 'invalid_token' });
      return;
    }

    const now = Date.now();
    const expiresAtIso = toUtc7Iso(resetToken.expiresAt) || undefined;
    const userId = resetToken.userId.toHexString();

    if (resetToken.usedAt) {
      redirectToApp(res, {
        status: 'used_token',
        userId,
        expiresAt: expiresAtIso,
      });
      return;
    }

    if (!resetToken.expiresAt || resetToken.expiresAt.getTime() <= now) {
      redirectToApp(res, {
        status: 'expired_token',
        userId,
        expiresAt: expiresAtIso,
      });
      return;
    }

    const users = await getUsersCollection();
    const user = await users.findOne({
      _id: resetToken.userId,
      email: resetToken.email,
    });

    if (!user || !user._id) {
      redirectToApp(res, {
        status: 'user_not_found',
        userId,
        expiresAt: expiresAtIso,
      });
      return;
    }

    redirectToApp(res, {
      status: 'valid',
      token,
      userId,
      expiresAt: expiresAtIso,
    });
  } catch (error: unknown) {
    console.error('[GET /api/auth?action=reset-link]', error);
    redirectToApp(res, { status: 'server_error' });
  }
}

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (handleApiPreflight(req, res, AUTH_ALLOWED_METHODS)) {
    return;
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(req, res, AUTH_ALLOWED_METHODS);
    return;
  }

  const action = resolveAction(req);
  if (!action) {
    res.status(400).json({
      error:
        'Missing or invalid auth action. Use action=register|login|forgot-password|reset-password|validate-reset-token|reset-link.',
    });
    return;
  }

  if (action === 'reset-link') {
    if (req.method !== 'GET') {
      methodNotAllowed(req, res, ['GET']);
      return;
    }
    await handleResetPasswordLink(req, res);
    return;
  }

  if (req.method !== 'POST') {
    methodNotAllowed(req, res, ['POST']);
    return;
  }

  switch (action) {
    case 'register':
      await handleRegister(req, res);
      return;
    case 'login':
      await handleLogin(req, res);
      return;
    case 'forgot-password':
      await handleForgotPassword(req, res);
      return;
    case 'reset-password':
      await handleResetPassword(req, res);
      return;
    case 'validate-reset-token':
      await handleValidateResetToken(req, res);
      return;
    default:
      res.status(400).json({ error: 'Unsupported auth action.' });
  }
}
