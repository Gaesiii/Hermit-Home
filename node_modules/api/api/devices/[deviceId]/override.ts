import { VercelRequest, VercelResponse } from '@vercel/node';
import { CommandPayload } from '@smart-terrarium/shared-types';
import { publishCommand } from '../../../lib/mqttPublisher';
import { connectToDatabase } from '../../../lib/mongoClient';
import { markCommandSent } from '../../../lib/deviceRepository';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { deviceId } = req.query;
  const command = req.body as CommandPayload;

  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  try {
    // Gửi lệnh xuống ESP32 qua HiveMQ
    await publishCommand(deviceId, command);
    const { db } = await connectToDatabase();
    await markCommandSent(db, deviceId, {
      mode: command.user_override ? 'MANUAL' : 'AUTO',
      user_override: command.user_override,
      relays: command.devices
    });

    return res.status(200).json({
      success: true,
      device: deviceId,
      message: 'Override command sent'
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to communicate with device' });
  }
}
