import { VercelRequest, VercelResponse } from '@vercel/node';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';

export default function handler(req: VercelRequest, res: VercelResponse): void {
  const allowedMethods = ['GET'] as const;
  if (handleApiPreflight(req, res, allowedMethods)) {
    return;
  }

  if (req.method !== 'GET') {
    methodNotAllowed(req, res, allowedMethods);
    return;
  }

  res.status(501).json({
    error: 'Not implemented',
    message: 'Device schedule endpoints are not available yet.',
  });
}
