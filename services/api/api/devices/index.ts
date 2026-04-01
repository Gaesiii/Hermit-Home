import { VercelRequest, VercelResponse } from '@vercel/node';
import { connectToDatabase } from '../../lib/mongoClient';
import { listDevices } from '../../lib/deviceRepository';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { db } = await connectToDatabase();
    const devices = await listDevices(db);
    return res.status(200).json(devices);
  } catch (error) {
    return res.status(500).json({ error: (error as Error).message });
  }
}
