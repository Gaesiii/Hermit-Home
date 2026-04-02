import dotenv from 'dotenv';
dotenv.config();

import type { VercelRequest, VercelResponse } from '@vercel/node';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { getUsersCollection, verifyPassword, toPublicUser } from '../../lib/userModel';

// ─── Constants ────────────────────────────────────────────────────────────────

const JWT_SECRET     = process.env.JWT_SECRET ?? '';
const JWT_EXPIRES_IN = '7d';

// Sentinel used in the dummy bcrypt compare below.
// Pre-computed with bcrypt.hashSync('__dummy__', 12).
const DUMMY_HASH =
  '$2b$12$Kix4fBjlHfmFRRpSCRVLMuJN0XFdOfuBGBlfAJqvR4L.5tq5.7Dly';

if (!JWT_SECRET) {
  throw new Error('Missing required environment variable: JWT_SECRET');
}

// ─── Generic error ────────────────────────────────────────────────────────────

// Same message for "user not found" and "wrong password" to prevent
// user-enumeration through distinct error strings.
const INVALID_CREDENTIALS = 'Invalid email or password.';

// ─── Handler ──────────────────────────────────────────────────────────────────

/**
 * POST /api/users/login
 *
 * Body   : { email: string, password: string }
 * Success: 200 { token: string, user: PublicUser }
 * Errors : 400 (validation), 401 (bad credentials), 500 (unexpected)
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed.' });
    return;
  }

  // ── 1. Basic input validation ────────────────────────────────────────────────
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

    // ── 2. Look up user ──────────────────────────────────────────────────────────
    const user = await users.findOne({ email: email.toLowerCase().trim() });

    if (!user) {
      // Run a dummy compare so the response time is indistinguishable from a
      // real password mismatch — prevents timing-based user-enumeration attacks.
      await bcrypt.compare(password, DUMMY_HASH);
      res.status(401).json({ error: INVALID_CREDENTIALS });
      return;
    }

    // ── 3. Verify password ───────────────────────────────────────────────────────
    const isValid = await verifyPassword(password, user.passwordHash);
    if (!isValid) {
      res.status(401).json({ error: INVALID_CREDENTIALS });
      return;
    }

    // ── 4. Issue JWT ─────────────────────────────────────────────────────────────
    const payload = {
      userId: user._id!.toString(),
      email:  user.email,
    };

    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });

    // ── 5. Respond with token + safe user projection ─────────────────────────────
    res.status(200).json({
      token,
      user: toPublicUser(user),
    });
  } catch (err) {
    console.error('[POST /api/users/login]', err);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}