import { VercelRequest, VercelResponse } from '@vercel/node';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';

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
    message:
      'Use /api/devices/{deviceId}/data?type=latest|history, /api/devices/{deviceId}/action?type=control|override|alert, /api/logs, or /api/devices/{deviceId}',
  });
}
