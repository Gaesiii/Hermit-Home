import type { VercelRequest, VercelResponse } from '@vercel/node';
import { getUsersCollection, hashPassword } from '../../lib/userModel';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';
import {
  consumePasswordResetToken,
  invalidateAllPasswordResetTokensForUser,
} from '../../lib/passwordResetModel';

const INVALID_TOKEN_MESSAGE = 'Invalid or expired reset token.';

function validate(body: unknown): { token: string; password: string } | string {
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
    console.error('[POST /api/users/reset-password]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}
