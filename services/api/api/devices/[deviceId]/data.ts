import type { VercelRequest, VercelResponse } from '@vercel/node';
import type { WithId } from 'mongodb';
import { connectToDatabase } from '../../../lib/mongoClient';
import { withAuth, type AuthenticatedRequest } from '../../../lib/authMiddleware';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { toUtc7Iso } from '../../../lib/timezone';
import { insertDiagnosticLog } from '../../../lib/diagnosticLogRepo';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
const ALLOWED_METHODS = ['GET'] as const;
const TELEMETRY_DEFAULT_LIMIT = 30;
const TELEMETRY_MAX_LIMIT = 200;

type DataType = 'latest' | 'history';

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

function readQueryValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }
  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }
  return null;
}

function resolveDataType(req: AuthenticatedRequest): DataType {
  const type = readQueryValue(req.query.type)?.trim().toLowerCase();
  if (!type || type === 'latest' || type === 'status') {
    return 'latest';
  }
  if (type === 'history' || type === 'telemetry') {
    return 'history';
  }
  return 'latest';
}

function parseTelemetryLimit(rawLimit: unknown): number | null {
  if (rawLimit === undefined) {
    return TELEMETRY_DEFAULT_LIMIT;
  }

  const source = Array.isArray(rawLimit) ? rawLimit[0] : rawLimit;
  const parsed = Number(source);

  if (!Number.isInteger(parsed) || parsed < 1 || parsed > TELEMETRY_MAX_LIMIT) {
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
  return {
    id: doc._id.toString(),
    userId: doc.userId,
    timestamp: toUtc7Iso(doc.timestamp) ?? null,
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

async function handleLatest(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  try {
    const { db } = await connectToDatabase();
    const latest = await db
      .collection('telemetry')
      .find({ userId: deviceId })
      .sort({ timestamp: -1 })
      .limit(1)
      .toArray();

    if (latest.length === 0) {
      await insertDiagnosticLog({
        deviceId,
        userId: req.user.userId,
        source: 'api',
        category: 'TELEMETRY',
        status: 'FAIL',
        message: '[FAIL] Latest telemetry fetch returned no data.',
        metadata: {
          endpoint: '/api/devices/[deviceId]/data',
          method: 'GET',
          type: 'latest',
        },
      });
      res.status(404).json({ error: 'No data found for this device' });
      return;
    }

    const latestDocument = latest[0] as Record<string, unknown>;
    const normalized = {
      ...latestDocument,
      timestamp: toUtc7Iso(latestDocument.timestamp as Date | string) ?? latestDocument.timestamp,
    };

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'TELEMETRY',
      status: 'PASS',
      message: '[PASS] Latest telemetry fetched successfully.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/data',
        method: 'GET',
        type: 'latest',
      },
    });

    res.status(200).json(normalized);
  } catch (error: unknown) {
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'TELEMETRY',
      status: 'FAIL',
      message: '[FAIL] Latest telemetry fetch failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/data',
        method: 'GET',
        type: 'latest',
        error: (error as Error).message,
      },
    });
    res.status(500).json({ error: 'Database connection failed' });
  }
}

async function handleHistory(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const limit = parseTelemetryLimit(req.query.limit);
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

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'SYNC',
      status: 'PASS',
      message: `[PASS] Telemetry sync completed (${docs.length} rows).`,
      metadata: {
        endpoint: '/api/devices/[deviceId]/data',
        method: 'GET',
        type: 'history',
        limit,
      },
    });
  } catch (error: unknown) {
    console.error('[GET /api/devices/[deviceId]/data?type=history]', error);
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'SYNC',
      status: 'FAIL',
      message: '[FAIL] Telemetry sync request failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/data',
        method: 'GET',
        type: 'history',
        error: (error as Error).message,
      },
    });
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

const authenticatedHandler = withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> => {
  if (req.method !== 'GET') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  const dataType = resolveDataType(req);
  if (dataType === 'history') {
    await handleHistory(req, res, deviceId);
    return;
  }

  await handleLatest(req, res, deviceId);
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
