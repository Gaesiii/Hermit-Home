import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getUsersCollection } from '../../lib/userModel';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';
import {
  buildPasswordResetLink,
  getPasswordResetTokenTtlMinutes,
  sendPasswordResetEmail,
} from '../../lib/passwordResetMailer';
import { createPasswordResetToken } from '../../lib/passwordResetModel';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SUCCESS_MESSAGE =
  'If an account with that email exists, a password reset link has been sent.';

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

function validate(body: unknown): { email: string } | string {
  if (!body || typeof body !== 'object') {
    return 'Request body must be a JSON object.';
  }

  const { email } = body as Record<string, unknown>;
  if (!email || typeof email !== 'string' || !EMAIL_RE.test(email)) {
    return 'A valid email address is required.';
  }

  return { email: email.toLowerCase().trim() };
}

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  const allowedMethods = ['POST'] as const;
  if (handleApiPreflight(req, res, allowedMethods)) {
    return;
  }

  if (req.method !== 'POST') {
    methodNotAllowed(req, res, allowedMethods);
    return;
  }

  const input = validate(req.body);
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

    res.status(200).json({ message: SUCCESS_MESSAGE });
  } catch (error: unknown) {
    const debugError = serializeError(error);
    console.error('[POST /api/users/forgot-password]', debugError);

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
