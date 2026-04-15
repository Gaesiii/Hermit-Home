import type { VercelRequest, VercelResponse } from '@vercel/node';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { getUsersCollection, verifyPassword, toPublicUser } from '../../lib/userModel';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';

const JWT_EXPIRES_IN = '7d';

const DUMMY_HASH =
  '$2b$12$Kix4fBjlHfmFRRpSCRVLMuJN0XFdOfuBGBlfAJqvR4L.5tq5.7Dly';

const INVALID_CREDENTIALS = 'Invalid email or password.';

function getJwtSecret(): string | null {
  const value = process.env.JWT_SECRET;
  if (!value || value.trim().length === 0) {
    return null;
  }

  return value;
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

  const jwtSecret = getJwtSecret();
  if (!jwtSecret) {
    console.error('[POST /api/users/login] Missing required environment variable: JWT_SECRET');
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
      console.error('[POST /api/users/login] Invalid user record schema', {
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
        userId: user._id!.toString(),
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
    console.error('[POST /api/users/login]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}
