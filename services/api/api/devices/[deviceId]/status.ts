import type { VercelRequest, VercelResponse } from '@vercel/node';
import dataHandler from './data';
import { patchQuery } from '../../../lib/legacyRouteProxy';

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  patchQuery(req, { type: 'latest' });
  await dataHandler(req, res);
}
