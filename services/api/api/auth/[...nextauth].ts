import { VercelRequest, VercelResponse } from '@vercel/node';
import { handleApiPreflight } from '../../lib/http';

export default function handler(req: VercelRequest, res: VercelResponse): void {
  if (handleApiPreflight(req, res, ['GET', 'POST'])) {
    return;
  }

  res.status(501).json({
    error: 'Not implemented',
    message: 'Authentication route is not configured yet.',
  });
}
