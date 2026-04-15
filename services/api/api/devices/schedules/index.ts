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

  res.status(200).json({
    success: true,
    schedules: [],
    message: 'Schedule API placeholder is active. No schedules configured yet.',
  });
}
