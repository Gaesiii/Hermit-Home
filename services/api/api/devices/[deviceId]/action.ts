import type { VercelRequest, VercelResponse } from '@vercel/node';
import type { WithId } from 'mongodb';
import type { CommandPayload } from '@smart-terrarium/shared-types';
import { connectToDatabase } from '../../../lib/mongoClient';
import { withAuth, type AuthenticatedRequest } from '../../../lib/authMiddleware';
import {
  type RelayStatePartial,
  VALID_DEVICE_KEYS,
  getRecentDeviceStates,
  insertDeviceState,
  isDeviceKey,
} from '../../../lib/deviceStateModel';
import { publishCommand } from '../../../lib/mqttPublisher';
import {
  MIST_SAFETY_LOCK_ENABLED,
  sanitizeCommandPayload,
  sanitizeRelayMap,
} from '../../../lib/mistSafety';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { toUtc7Iso } from '../../../lib/timezone';
import { insertCommandPendingLogs, insertDiagnosticLog } from '../../../lib/diagnosticLogRepo';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
const ALLOWED_METHODS = ['GET', 'POST'] as const;
const CONTROL_DEFAULT_LIMIT = 20;
const CONTROL_MAX_LIMIT = 100;
const ALERT_DEFAULT_LIMIT = 30;
const ALERT_MAX_LIMIT = 200;

type ActionType = 'control' | 'override' | 'alert';
type AlertLevel = 'info' | 'warning' | 'critical';

type DeviceAlertDocument = {
  deviceId: string;
  userId: string;
  source: 'ai-agent' | 'system' | 'user';
  level: AlertLevel;
  title: string;
  message: string;
  danger_state: boolean;
  reason?: string;
  danger_reasons?: string[];
  telemetry?: Record<string, unknown>;
  actions?: Record<string, unknown>;
  createdAt: Date;
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

function normalizeActionType(rawType: string): ActionType | null {
  const normalized = rawType.trim().toLowerCase();
  switch (normalized) {
    case 'control':
      return 'control';
    case 'override':
      return 'override';
    case 'alert':
    case 'alerts':
      return 'alert';
    default:
      return null;
  }
}

function inferActionTypeFromBody(body: Record<string, unknown>): ActionType | null {
  if (typeof body.type === 'string') {
    const typed = normalizeActionType(body.type);
    if (typed) return typed;
  }

  if (body.title !== undefined || body.message !== undefined || body.danger_state !== undefined) {
    return 'alert';
  }

  if (body.user_override !== undefined || body.thresholds !== undefined || body.devices !== undefined) {
    return 'override';
  }

  const stateCandidate = body.state;
  if (stateCandidate && typeof stateCandidate === 'object' && !Array.isArray(stateCandidate)) {
    const stateKeys = Object.keys(stateCandidate as Record<string, unknown>);
    if (stateKeys.some((key) => isDeviceKey(key))) {
      return 'control';
    }
  }

  const bodyKeys = Object.keys(body);
  if (bodyKeys.some((key) => isDeviceKey(key))) {
    return 'control';
  }

  return null;
}

function resolveActionType(req: AuthenticatedRequest): ActionType | null {
  const queryType = readQueryValue(req.query.type);
  if (queryType) {
    const typed = normalizeActionType(queryType);
    if (typed) {
      return typed;
    }
  }

  const body = req.body;
  if (body && typeof body === 'object' && !Array.isArray(body)) {
    return inferActionTypeFromBody(body as Record<string, unknown>);
  }

  return null;
}

function parseControlLimit(rawLimit: unknown): number | null {
  if (rawLimit === undefined) {
    return CONTROL_DEFAULT_LIMIT;
  }

  const source = Array.isArray(rawLimit) ? rawLimit[0] : rawLimit;
  const parsed = Number(source);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > CONTROL_MAX_LIMIT) {
    return null;
  }
  return parsed;
}

function parseAlertLimit(rawLimit: unknown): number | null {
  if (rawLimit === undefined) return ALERT_DEFAULT_LIMIT;

  const source = Array.isArray(rawLimit) ? rawLimit[0] : rawLimit;
  const parsed = Number(source);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > ALERT_MAX_LIMIT) {
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
      message: 'You do not have permission to access this device.',
    });
    return null;
  }

  return deviceId;
}

function levelToStatus(level: AlertLevel): 'PASS' | 'FAIL' | 'INFO' {
  if (level === 'critical') {
    return 'FAIL';
  }
  if (level === 'warning') {
    return 'INFO';
  }
  return 'PASS';
}

function sanitizeAlertLevel(value: unknown): AlertLevel {
  if (value === 'critical' || value === 'warning' || value === 'info') {
    return value;
  }
  return 'warning';
}

function normalizeAlertDoc(doc: WithId<DeviceAlertDocument>) {
  return {
    id: doc._id.toString(),
    deviceId: doc.deviceId,
    userId: doc.userId,
    source: doc.source,
    level: doc.level,
    title: doc.title,
    message: doc.message,
    danger_state: doc.danger_state,
    reason: doc.reason ?? null,
    danger_reasons: doc.danger_reasons ?? [],
    telemetry: doc.telemetry ?? {},
    actions: doc.actions ?? {},
    createdAt: toUtc7Iso(doc.createdAt) ?? null,
  };
}

function pickObjectPayload(body: Record<string, unknown>, key: string): Record<string, unknown> {
  const nested = body[key];
  if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
    return nested as Record<string, unknown>;
  }
  return body;
}

function stripMetaFields(payload: Record<string, unknown>): Record<string, unknown> {
  const next = { ...payload };
  delete next.type;
  delete next.action;
  delete next.payload;
  return next;
}

async function handleControlGet(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const limit = parseControlLimit(req.query.limit);
  if (limit === null) {
    res.status(400).json({
      error: '`limit` must be a positive integer (1-100).',
    });
    return;
  }

  try {
    const history = await getRecentDeviceStates(deviceId, req.user.userId, limit);
    const normalizedHistory = history.map((entry) => ({
      ...entry,
      _id: entry._id?.toString?.() ?? entry._id,
      createdAt: toUtc7Iso(entry.createdAt) ?? entry.createdAt,
    }));

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'SYNC',
      status: 'PASS',
      message: `[PASS] Control history sync succeeded for device ${deviceId}.`,
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'GET',
        type: 'control',
        count: normalizedHistory.length,
      },
    });

    res.status(200).json({ deviceId, history: normalizedHistory });
  } catch (error: unknown) {
    console.error('[GET /api/devices/[deviceId]/action?type=control]', error);
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'SYNC',
      status: 'FAIL',
      message: `[FAIL] Control history sync failed for device ${deviceId}.`,
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'GET',
        type: 'control',
        error: (error as Error).message,
      },
    });
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handleControlPost(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const body = req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  const source = stripMetaFields(pickObjectPayload(body as Record<string, unknown>, 'state'));
  const bodyKeys = Object.keys(source);
  if (bodyKeys.length === 0) {
    res.status(400).json({
      error: `Request body must contain at least one device key. Valid keys: ${VALID_DEVICE_KEYS.join(', ')}.`,
    });
    return;
  }

  const unknownKeys = bodyKeys.filter((key) => !isDeviceKey(key));
  if (unknownKeys.length > 0) {
    res.status(400).json({
      error: `Unknown device key(s): ${unknownKeys.join(', ')}. Valid keys: ${VALID_DEVICE_KEYS.join(', ')}.`,
    });
    return;
  }

  const stateUpdate: RelayStatePartial = {};
  for (const key of bodyKeys) {
    if (!isDeviceKey(key)) continue;

    const value = source[key];
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
    await insertCommandPendingLogs({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      stateUpdate: safeStateUpdate as Record<string, boolean>,
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'POST',
        type: 'control',
      },
    });
  } catch (error: unknown) {
    console.error('[POST /api/devices/[deviceId]/action?type=control] MQTT publish failed', error);
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'COMMAND',
      status: 'FAIL',
      message: '[FAIL] Command publish failed before reaching Edge Device.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'POST',
        type: 'control',
        stateUpdate: safeStateUpdate,
        error: (error as Error).message,
      },
    });
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
    console.error('[POST /api/devices/[deviceId]/action?type=control] MongoDB insert failed', error);
    res.status(207).json({
      success: true,
      deviceId,
      appliedState: safeStateUpdate,
      warning: 'Command was sent to the device but could not be recorded in the database.',
      mist_locked_off: MIST_SAFETY_LOCK_ENABLED && requestedMistOn,
    });
  }
}

async function handleOverridePost(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const body = req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  const source = stripMetaFields(pickObjectPayload(body as Record<string, unknown>, 'payload'));
  if (typeof source.user_override !== 'boolean') {
    res.status(400).json({ error: '`user_override` must be provided as a boolean.' });
    return;
  }

  const command = source as unknown as CommandPayload;
  const safeCommand = sanitizeCommandPayload(command);
  const requestedMistOn = command?.devices?.mist === true;
  const isServiceCall = typeof req.headers['x-api-key'] === 'string';

  try {
    await publishCommand(deviceId, safeCommand);

    if (safeCommand.devices && Object.keys(safeCommand.devices).length > 0) {
      await insertCommandPendingLogs({
        deviceId,
        userId: req.user.userId,
        source: isServiceCall ? 'ai-agent' : 'api',
        stateUpdate: safeCommand.devices as Record<string, boolean>,
        metadata: {
          endpoint: '/api/devices/[deviceId]/action',
          method: 'POST',
          type: 'override',
          userOverride: safeCommand.user_override,
          byServiceKey: isServiceCall,
        },
      });
    } else {
      await insertDiagnosticLog({
        deviceId,
        userId: req.user.userId,
        source: isServiceCall ? 'ai-agent' : 'api',
        category: isServiceCall ? 'AI' : 'COMMAND',
        status: 'INFO',
        message: safeCommand.user_override
          ? '[INFO] Override command accepted.'
          : '[INFO] Threshold update accepted by API.',
        metadata: {
          endpoint: '/api/devices/[deviceId]/action',
          method: 'POST',
          type: 'override',
          command: safeCommand,
          byServiceKey: isServiceCall,
        },
      });
    }

    res.status(200).json({
      success: true,
      device: deviceId,
      message: 'Override command sent',
      mist_locked_off: MIST_SAFETY_LOCK_ENABLED && requestedMistOn,
    });
  } catch (error: unknown) {
    console.error('[POST /api/devices/[deviceId]/action?type=override] MQTT publish failed', error);
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: isServiceCall ? 'ai-agent' : 'api',
      category: isServiceCall ? 'AI' : 'COMMAND',
      status: 'FAIL',
      message: '[FAIL] Override publish to Edge Device failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'POST',
        type: 'override',
        command: safeCommand,
        byServiceKey: isServiceCall,
        error: (error as Error).message,
      },
    });
    res.status(500).json({ error: 'Failed to communicate with device' });
  }
}

async function handleAlertGet(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const limit = parseAlertLimit(req.query.limit);
  if (limit === null) {
    res.status(400).json({
      error: '`limit` must be an integer between 1 and 200.',
    });
    return;
  }

  try {
    const { db } = await connectToDatabase();
    const docs = await db
      .collection<DeviceAlertDocument>('device_alerts')
      .find({ deviceId })
      .sort({ createdAt: -1 })
      .limit(limit)
      .toArray();

    res.status(200).json({
      deviceId,
      count: docs.length,
      alerts: docs.map(normalizeAlertDoc),
    });
  } catch (error: unknown) {
    console.error('[GET /api/devices/[deviceId]/action?type=alert]', error);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

async function handleAlertPost(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const body = req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  const sourceBody = stripMetaFields(pickObjectPayload(body as Record<string, unknown>, 'payload'));
  const title = String(sourceBody.title ?? '').trim();
  const message = String(sourceBody.message ?? '').trim();
  const reason = String(sourceBody.reason ?? '').trim();
  const dangerState = sourceBody.danger_state === true;
  const sourceRaw = String(sourceBody.source ?? 'ai-agent').trim();
  const source: DeviceAlertDocument['source'] =
    sourceRaw === 'user' || sourceRaw === 'system' ? sourceRaw : 'ai-agent';

  if (!title) {
    res.status(400).json({ error: '`title` is required.' });
    return;
  }

  if (!message) {
    res.status(400).json({ error: '`message` is required.' });
    return;
  }

  const dangerReasonsRaw = sourceBody.danger_reasons;
  const dangerReasons = Array.isArray(dangerReasonsRaw)
    ? dangerReasonsRaw.filter((item): item is string => typeof item === 'string').slice(0, 10)
    : [];

  const telemetryRaw = sourceBody.telemetry;
  const actionsRaw = sourceBody.actions;

  const telemetry =
    telemetryRaw && typeof telemetryRaw === 'object' && !Array.isArray(telemetryRaw)
      ? (telemetryRaw as Record<string, unknown>)
      : {};
  const actions =
    actionsRaw && typeof actionsRaw === 'object' && !Array.isArray(actionsRaw)
      ? (actionsRaw as Record<string, unknown>)
      : {};

  const document: DeviceAlertDocument = {
    deviceId,
    userId: req.user.userId,
    source,
    level: sanitizeAlertLevel(sourceBody.level),
    title: title.slice(0, 120),
    message: message.slice(0, 1000),
    danger_state: dangerState,
    reason: reason ? reason.slice(0, 300) : undefined,
    danger_reasons: dangerReasons,
    telemetry,
    actions,
    createdAt: new Date(),
  };

  try {
    const { db } = await connectToDatabase();
    const result = await db.collection<DeviceAlertDocument>('device_alerts').insertOne(document);

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: source === 'ai-agent' ? 'ai-agent' : 'api',
      category: source === 'ai-agent' ? 'AI' : 'SYNC',
      status: levelToStatus(document.level),
      message: `[${levelToStatus(document.level)}] Alert received: ${document.title}`,
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'POST',
        type: 'alert',
        source: document.source,
        danger_state: document.danger_state,
      },
    });

    res.status(201).json({
      success: true,
      id: result.insertedId.toString(),
      deviceId,
      createdAt: toUtc7Iso(document.createdAt) ?? null,
      notify_mobile: true,
    });
  } catch (error: unknown) {
    console.error('[POST /api/devices/[deviceId]/action?type=alert]', error);
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'AI',
      status: 'FAIL',
      message: '[FAIL] Alert persistence failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/action',
        method: 'POST',
        type: 'alert',
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
  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  const actionType = resolveActionType(req);
  if (!actionType) {
    res.status(400).json({
      error:
        "Missing or invalid action type. Use query `type=control|override|alert` or body `type`.",
    });
    return;
  }

  if (req.method === 'GET') {
    if (actionType === 'control') {
      await handleControlGet(req, res, deviceId);
      return;
    }
    if (actionType === 'alert') {
      await handleAlertGet(req, res, deviceId);
      return;
    }

    methodNotAllowed(req, res, ['POST']);
    return;
  }

  if (req.method === 'POST') {
    if (actionType === 'control') {
      await handleControlPost(req, res, deviceId);
      return;
    }
    if (actionType === 'override') {
      await handleOverridePost(req, res, deviceId);
      return;
    }
    if (actionType === 'alert') {
      await handleAlertPost(req, res, deviceId);
      return;
    }
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

  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  await authenticatedHandler(req, res);
}
