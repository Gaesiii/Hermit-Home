import type { VercelRequest, VercelResponse } from '@vercel/node';
import type { WithId } from 'mongodb';
import { connectToDatabase } from '../../../lib/mongoClient';
import { withAuth, AuthenticatedRequest } from '../../../lib/authMiddleware';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { toUtc7Iso } from '../../../lib/timezone';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 200;
const ALLOWED_METHODS = ['GET'] as const;

type TelemetryRelays = {
  heater: boolean;
  mist: boolean;
  fan: boolean;
  light: boolean;
};

type TelemetryDocument = {
  userId: string;
  timestamp: Date | string;
  temperature: number | null;
  humidity: number | null;
  lux: number;
  sensor_fault: boolean;
  user_override: boolean;
  relays: TelemetryRelays;
};

function parseLimit(rawLimit: unknown): number | null {
  if (rawLimit === undefined) return DEFAULT_LIMIT;

  const source = Array.isArray(rawLimit) ? rawLimit[0] : rawLimit;
  const parsed = Number(source);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_LIMIT) {
    return null;
  }

  return parsed;
}

function resolveAuthorizedDeviceId(
  req: AuthenticatedRequest,
  res: VercelResponse,
): string | null {
  const { deviceId } = req.query;

  if (!deviceId || typeof deviceId !== 'string') {
    res.status(400).json({ error: 'deviceId route parameter is required.' });
    return null;
  }

  if (!OBJECT_ID_REGEX.test(deviceId)) {
    res.status(400).json({
      error: 'Invalid device ID format.',
      message: 'Device ID must be a 24-character hex string.',
    });
    return null;
  }

  if (req.user.userId !== deviceId) {
    res.status(403).json({
      error: 'Forbidden',
      message: 'You do not have permission to access this telemetry data.',
    });
    return null;
  }

  return deviceId;
}

function normalizeTelemetry(doc: WithId<TelemetryDocument>) {
  const timestamp = toUtc7Iso(doc.timestamp);

  return {
    id: doc._id.toString(),
    userId: doc.userId,
    timestamp: timestamp ?? null,
    temperature: doc.temperature,
    humidity: doc.humidity,
    lux: doc.lux,
    sensor_fault: doc.sensor_fault,
    user_override: doc.user_override,
    relays: {
      heater: doc.relays.heater,
      mist: doc.relays.mist,
      fan: doc.relays.fan,
      light: doc.relays.light,
    },
  };
}

async function handleGet(
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> {
  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  const limit = parseLimit(req.query.limit);
  if (limit === null) {
    res.status(400).json({
      error: '`limit` must be an integer between 1 and 200.',
    });
    return;
  }

  try {
    const { db } = await connectToDatabase();

    const docs = await db
      .collection<TelemetryDocument>('telemetry')
      .find({ userId: deviceId })
      .sort({ timestamp: -1 })
      .limit(limit)
      .toArray();

    res.status(200).json({
      deviceId,
      count: docs.length,
      telemetry: docs.map(normalizeTelemetry),
    });
  } catch (error: unknown) {
    console.error('[GET /api/devices/[deviceId]/telemetry]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

const authenticatedHandler = withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> => {
  if (req.method === 'GET') {
    await handleGet(req, res);
    return;
  }

  methodNotAllowed(req, res, ALLOWED_METHODS);
});

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (handleApiPreflight(req, res, ALLOWED_METHODS)) {
    return;
  }

  if (req.method !== 'GET') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  await authenticatedHandler(req, res);
}
