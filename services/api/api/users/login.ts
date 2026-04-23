import type { VercelRequest, VercelResponse } from '@vercel/node';
import authHandler from '../auth/index';
import { patchQuery } from '../../lib/legacyRouteProxy';

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  patchQuery(req, { action: 'login' });
  await authHandler(req, res);
}
