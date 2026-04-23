import type { VercelRequest, VercelResponse } from '@vercel/node';
import actionHandler from './action';
import { patchQuery } from '../../../lib/legacyRouteProxy';

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  patchQuery(req, { type: 'override' });
  await actionHandler(req, res);
}
