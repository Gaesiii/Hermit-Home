import { VercelRequest, VercelResponse } from '@vercel/node';
import { DeviceStatePatch } from '@smart-terrarium/shared-types';
import { connectToDatabase } from '../../../lib/mongoClient';
import { getDeviceById, patchDeviceById } from '../../../lib/deviceRepository';
import { verifyAuth } from '../../../lib/authMiddleware';
import { sanitizeDeviceStatePatch } from '../../../lib/mistSafety';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET' && req.method !== 'PATCH') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const uid = await verifyAuth(req, res);
  if (uid === null) return;

  const { deviceId } = req.query;
  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  if (!OBJECT_ID_REGEX.test(deviceId)) {
    return res.status(400).json({
      error: 'Invalid device ID format',
      message: 'Device ID must be a 24-character hex string.',
    });
  }

  if (uid !== deviceId) {
    return res.status(403).json({
      error: 'Forbidden',
      message: 'You do not have permission to access this device.',
    });
  }

  try {
    const { db } = await connectToDatabase();

    if (req.method === 'GET') {
      const device = await getDeviceById(db, deviceId);
      if (!device) {
        return res.status(404).json({ error: 'Device not found' });
      }
      return res.status(200).json(device);
    }

    const patch = sanitizeDeviceStatePatch(req.body as DeviceStatePatch);
    const updated = await patchDeviceById(db, deviceId, patch);
    return res.status(200).json(updated);
  } catch (error: unknown) {
    return res.status(500).json({ error: (error as Error).message });
  }
}
