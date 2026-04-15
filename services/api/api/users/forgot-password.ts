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

function readHeaderValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }

  return null;
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
    console.error('[POST /api/users/forgot-password]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}
