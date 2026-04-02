import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getUsersCollection, hashPassword, toPublicUser } from '../../lib/userModel';

// ─── Validation ───────────────────────────────────────────────────────────────

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

// ─── Handler ──────────────────────────────────────────────────────────────────

/**
 * POST /api/users/register
 *
 * Body   : { email: string, password: string }
 * Success: 201 { user: PublicUser }
 * Errors : 400 (validation), 409 (duplicate), 500 (unexpected)
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed.' });
    return;
  }

  // ── 1. Validate input ────────────────────────────────────────────────────────
  const input = validate(req.body);
  if (typeof input === 'string') {
    res.status(400).json({ error: input });
    return;
  }

  const { email, password } = input;

  try {
    const users = await getUsersCollection();

    // ── 2. Guard against duplicate accounts ────────────────────────────────────
    const existing = await users.findOne({ email });
    if (existing) {
      // Deliberately vague — avoids leaking which emails are registered.
      res.status(409).json({ error: 'An account with that email already exists.' });
      return;
    }

    // ── 3. Hash password and persist ───────────────────────────────────────────
    const passwordHash = await hashPassword(password);
    const now          = new Date();

    const result = await users.insertOne({
      email,
      passwordHash,
      createdAt: now,
      updatedAt: now,
    });

    // ── 4. Return safe projection ─────────────────────────────────────────────
    const createdUser = await users.findOne({ _id: result.insertedId });

    res.status(201).json({
      message: 'Account created successfully.',
      user:    toPublicUser(createdUser!),
    });
  } catch (err: unknown) {
    // MongoDB duplicate-key race condition (between findOne and insertOne)
    if (
      err instanceof Error &&
      'code' in err &&
      (err as NodeJS.ErrnoException & { code: number }).code === 11000
    ) {
      res.status(409).json({ error: 'An account with that email already exists.' });
      return;
    }

    console.error('[POST /api/users/register]', err);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}