import type { VercelRequest, VercelResponse } from '@vercel/node';
import type { CommandPayload } from '@smart-terrarium/shared-types';
import { withAuth, AuthenticatedRequest } from '../../../lib/authMiddleware';
import {
  RelayStatePartial,
  VALID_DEVICE_KEYS,
  getRecentDeviceStates,
  insertDeviceState,
  isDeviceKey,
} from '../../../lib/deviceStateModel';
import { publishCommand } from '../../../lib/mqttPublisher';
import { MIST_SAFETY_LOCK_ENABLED, sanitizeRelayMap } from '../../../lib/mistSafety';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { toUtc7Iso } from '../../../lib/timezone';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;

function resolveAuthorizedDeviceId(
  req: AuthenticatedRequest,
  res: VercelResponse
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
      message: 'You do not have permission to access this device.',
    });
    return null;
  }

  return deviceId;
}

async function handleGet(
  req: AuthenticatedRequest,
  res: VercelResponse
): Promise<void> {
  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  let limit = 20;
  if (req.query.limit !== undefined) {
    const parsed = Number(req.query.limit);
    if (!Number.isInteger(parsed) || parsed < 1) {
      res.status(400).json({
        error: '`limit` must be a positive integer (1-100).',
      });
      return;
    }
    limit = parsed;
  }

  try {
    const history = await getRecentDeviceStates(deviceId, req.user.userId, limit);
    const normalizedHistory = history.map((entry) => ({
      ...entry,
      _id: entry._id?.toString?.() ?? entry._id,
      createdAt: toUtc7Iso(entry.createdAt) ?? entry.createdAt,
    }));
    res.status(200).json({ deviceId, history: normalizedHistory });
  } catch (error: unknown) {
    console.error('[GET /api/devices/[deviceId]/control]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handlePost(
  req: AuthenticatedRequest,
  res: VercelResponse
): Promise<void> {
  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  const body = req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  const bodyKeys = Object.keys(body);
  if (bodyKeys.length === 0) {
    res.status(400).json({
      error: `Request body must contain at least one device key. Valid keys: ${VALID_DEVICE_KEYS.join(', ')}.`,
    });
    return;
  }

  const unknownKeys = bodyKeys.filter((k) => !isDeviceKey(k));
  if (unknownKeys.length > 0) {
    res.status(400).json({
      error: `Unknown device key(s): ${unknownKeys.join(', ')}. Valid keys: ${VALID_DEVICE_KEYS.join(', ')}.`,
    });
    return;
  }

  const stateUpdate: RelayStatePartial = {};
  for (const key of bodyKeys) {
    if (!isDeviceKey(key)) continue;
    const value = (body as Record<string, unknown>)[key];
    if (typeof value !== 'boolean') {
      res.status(400).json({
        error: `Value for '${key}' must be a boolean (true or false).`,
      });
      return;
    }
    stateUpdate[key] = value;
  }

  const requestedMistOn = stateUpdate.mist === true;
  const safeStateUpdate = sanitizeRelayMap(stateUpdate);

  const commandPayload: CommandPayload = {
    user_override: true,
    devices: safeStateUpdate,
  };

  try {
    await publishCommand(deviceId, commandPayload);
  } catch (error: unknown) {
    console.error('[POST /api/devices/[deviceId]/control] MQTT publish failed', error);
    res.status(502).json({
      error: 'Failed to publish command to the device. The relay state has not changed.',
    });
    return;
  }

  try {
    const recordId = await insertDeviceState(deviceId, req.user.userId, safeStateUpdate, 'user');
    res.status(200).json({
      success: true,
      deviceId,
      appliedState: safeStateUpdate,
      recordId,
      mist_locked_off: MIST_SAFETY_LOCK_ENABLED && requestedMistOn,
    });
  } catch (error: unknown) {
    console.error('[POST /api/devices/[deviceId]/control] MongoDB insert failed', error);
    res.status(207).json({
      success: true,
      deviceId,
      appliedState: safeStateUpdate,
      warning: 'Command was sent to the device but could not be recorded in the database.',
      mist_locked_off: MIST_SAFETY_LOCK_ENABLED && requestedMistOn,
    });
  }
}

const allowedMethods = ['GET', 'POST'] as const;

const authenticatedHandler = withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse
): Promise<void> => {
  switch (req.method) {
    case 'GET':
      await handleGet(req, res);
      break;
    case 'POST':
      await handlePost(req, res);
      break;
    default:
      methodNotAllowed(req, res, allowedMethods);
  }
});

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (handleApiPreflight(req, res, allowedMethods)) {
    return;
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(req, res, allowedMethods);
    return;
  }

  await authenticatedHandler(req, res);
}
