import { VercelRequest, VercelResponse } from '@vercel/node';
import { connectToDatabase } from '../../../lib/mongoClient';
import { getDeviceById } from '../../../lib/deviceRepository';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Vercel tự động bóc tách [deviceId] từ URL
  const { deviceId } = req.query;

  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  try {
    const { db } = await connectToDatabase();
    const device = await getDeviceById(db, deviceId);
    
    // Tìm bản ghi telemetry mới nhất của thiết bị này
    // Lưu ý: userId trong DB chính là deviceId của ESP32
    const latestTelemetry = await db.collection('telemetry')
      .find({ userId: deviceId })
      .sort({ timestamp: -1 })
      .limit(1)
      .toArray();

    if (!device && latestTelemetry.length === 0) {
      return res.status(404).json({ error: 'No data found for this device' });
    }

    return res.status(200).json({
      device,
      telemetry: latestTelemetry[0] ?? null
    });
  } catch (error) {
    return res.status(500).json({ error: 'Database connection failed' });
  }
}
