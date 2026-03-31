import { VercelRequest, VercelResponse } from '@vercel/node';
import { connectToDatabase } from '../../../lib/mongoClient';
import { verifyAuth } from '../../../lib/authMiddleware';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') return res.status(405).end();

  // ----------------------------------------------------------------
  //  Auth gate — SEV-2 fix
  //  Same pattern as override.ts: return immediately on null so
  //  the database is never touched by an unauthenticated request.
  // ----------------------------------------------------------------
  const uid = await verifyAuth(req, res);
  if (uid === null) return;

  const { deviceId } = req.query;

  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  // ----------------------------------------------------------------
  //  NoSQL injection guard — SEV-5 fix
  //  deviceId comes from the URL and goes directly into a MongoDB
  //  filter. MongoDB accepts operator objects ({ $gt: "" }) as filter
  //  values, so an unvalidated deviceId can match unintended documents.
  //  A MongoDB ObjectId is exactly 24 lowercase hex characters.
  //  Anything else is rejected before it touches the database.
  // ----------------------------------------------------------------
  const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
  if (!OBJECT_ID_REGEX.test(deviceId)) {
    return res.status(400).json({
      error: 'Invalid device ID format',
      message: 'Device ID must be a 24-character hex string.',
    });
  }

  // ----------------------------------------------------------------
  //  Ownership check — same rationale as override.ts
  //  A valid token for user A must not be able to read
  //  telemetry belonging to user B's device.
  // ----------------------------------------------------------------
  if (uid !== deviceId) {
    return res.status(403).json({
      error: 'Forbidden',
      message: 'You do not have permission to read this device.',
    });
  }

  try {
    const { db } = await connectToDatabase();

    // deviceId is now guaranteed to be a 24-hex string —
    // safe to use directly in the filter.
    const latest = await db
      .collection('telemetry')
      .find({ userId: deviceId })
      .sort({ timestamp: -1 })
      .limit(1)
      .toArray();

    if (latest.length === 0) {
      return res.status(404).json({ error: 'No data found for this device' });
    }

    return res.status(200).json(latest[0]);
  } catch (error) {
    return res.status(500).json({ error: 'Database connection failed' });
  }
}