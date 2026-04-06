import { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(_req: VercelRequest, res: VercelResponse): void {
  res.status(501).json({
    error: 'Not implemented',
    message: 'Device schedule endpoints are not available yet.',
  });
}
