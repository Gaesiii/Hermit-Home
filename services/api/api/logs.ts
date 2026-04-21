import type { VercelRequest, VercelResponse } from '@vercel/node';
import { handleApiPreflight, methodNotAllowed } from '../lib/http';
import { expireTimedOutPendingCommands, listDiagnosticLogs } from '../lib/diagnosticLogRepo';
import { toUtc7Iso } from '../lib/timezone';

const ALLOWED_METHODS = ['GET'] as const;
const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;

function parseLimit(raw: unknown): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    return 120;
  }
  return Math.min(parsed, 300);
}

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (handleApiPreflight(req, res, ALLOWED_METHODS)) {
    return;
  }

  if (req.method !== 'GET') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  const limit = parseLimit(req.query.limit);
  const deviceIdRaw = Array.isArray(req.query.deviceId) ? req.query.deviceId[0] : req.query.deviceId;
  const deviceId = typeof deviceIdRaw === 'string' && OBJECT_ID_REGEX.test(deviceIdRaw)
    ? deviceIdRaw
    : undefined;

  try {
    const expired = await expireTimedOutPendingCommands();
    const logs = await listDiagnosticLogs({ limit, deviceId });
    const normalized = logs.map((entry) => ({
      id: entry._id?.toString(),
      deviceId: entry.deviceId,
      userId: entry.userId ?? null,
      source: entry.source,
      category: entry.category,
      status: entry.status,
      message: entry.message,
      relay: entry.relay ?? null,
      expectedState: typeof entry.expectedState === 'boolean' ? entry.expectedState : null,
      acknowledgedState: typeof entry.acknowledgedState === 'boolean' ? entry.acknowledgedState : null,
      commandRef: entry.commandRef ?? null,
      metadata: entry.metadata ?? {},
      ackDeadlineAt: toUtc7Iso(entry.ackDeadlineAt ?? null),
      acknowledgedAt: toUtc7Iso(entry.acknowledgedAt ?? null),
      resolvedAt: toUtc7Iso(entry.resolvedAt ?? null),
      createdAt: toUtc7Iso(entry.createdAt) ?? null,
      updatedAt: toUtc7Iso(entry.updatedAt) ?? null,
    }));

    res.status(200).json({
      count: normalized.length,
      expiredTimeouts: expired,
      logs: normalized,
    });
  } catch (error: unknown) {
    console.error('[GET /api/logs]', error);
    res.status(500).json({ error: 'Failed to load diagnostic logs.' });
  }
}
