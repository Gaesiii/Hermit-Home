import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getUsersCollection, hashPassword, toPublicUser } from '../../lib/userModel';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validate(body: unknown): { email: string; password: string } | string {
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

    console.error('[POST /api/users/register]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}
