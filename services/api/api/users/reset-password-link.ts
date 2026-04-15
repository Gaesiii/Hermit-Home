import type { VercelRequest, VercelResponse } from '@vercel/node';
import { findPasswordResetToken } from '../../lib/passwordResetModel';
import { getUsersCollection } from '../../lib/userModel';

const DEFAULT_APP_DEEPLINK = 'hermithome://reset-password';

type LinkStatus =
  | 'valid'
  | 'missing_token'
  | 'invalid_token'
  | 'expired_token'
  | 'used_token'
  | 'user_not_found'
  | 'server_error';

function readQueryValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }

  return null;
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

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    res.status(405).json({ error: `Method '${req.method}' is not allowed.` });
    return;
  }

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
    const expiresAtIso = resetToken.expiresAt?.toISOString();
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
    console.error('[GET /reset-password]', error);
    redirectToApp(res, { status: 'server_error' });
  }
}
