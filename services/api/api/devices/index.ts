import { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse): void {
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  res.status(200).json({
    success: true,
    message:
      'Use /api/devices/{deviceId}/status, /api/devices/{deviceId}/override, /api/devices/{deviceId}/control, or /api/devices/{deviceId}',
  });
}
