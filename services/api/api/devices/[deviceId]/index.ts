import { VercelRequest, VercelResponse } from '@vercel/node';
import { DeviceStatePatch } from '@smart-terrarium/shared-types';
import { connectToDatabase } from '../../../lib/mongoClient';
import { getDeviceById, patchDeviceById } from '../../../lib/deviceRepository';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const { deviceId } = req.query;

  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
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

    if (req.method === 'PATCH') {
      const patch = req.body as DeviceStatePatch;
      const updated = await patchDeviceById(db, deviceId, patch);
      return res.status(200).json(updated);
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    return res.status(500).json({ error: (error as Error).message });
  }
}
