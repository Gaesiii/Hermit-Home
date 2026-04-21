import { VercelRequest, VercelResponse } from '@vercel/node';
import { publishCommand } from '../../../lib/mqttPublisher';
import { CommandPayload } from '@smart-terrarium/shared-types';
import { verifyAuth } from '../../../lib/authMiddleware';
import { MIST_SAFETY_LOCK_ENABLED, sanitizeCommandPayload } from '../../../lib/mistSafety';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { insertCommandPendingLogs, insertDiagnosticLog } from '../../../lib/diagnosticLogRepo';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const allowedMethods = ['POST'] as const;
  if (handleApiPreflight(req, res, allowedMethods)) {
    return;
  }

  if (req.method !== 'POST') {
    methodNotAllowed(req, res, allowedMethods);
    return;
  }

  // ----------------------------------------------------------------
  //  Auth gate — SEV-1 fix
  //  verifyAuth() returns null and writes the 401 response itself.
  //  We must return immediately on null so the rest of the handler
  //  never executes with an unauthenticated request.
  // ----------------------------------------------------------------
  const uid = await verifyAuth(req, res);
  if (uid === null) return;

  const { deviceId } = req.query;
  const command = req.body as CommandPayload;
  const isServiceCall = typeof req.headers['x-api-key'] === 'string';

  if (!command || typeof command !== 'object' || Array.isArray(command)) {
    return res.status(400).json({ error: 'Request body must be a JSON object' });
  }

  const safeCommand = sanitizeCommandPayload(command);
  const requestedMistOn = command?.devices?.mist === true;

  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'Device ID is required' });
  }

  // ----------------------------------------------------------------
  //  Ownership check
  //  The authenticated uid must match the deviceId being commanded.
  //  This prevents a legitimate user from sending relay commands
  //  to another user's device — even with a valid token.
  // ----------------------------------------------------------------
  if (uid !== deviceId) {
    return res.status(403).json({
      error: 'Forbidden',
      message: 'You do not have permission to control this device.',
    });
  }

  try {
    await publishCommand(deviceId, safeCommand);

    if (safeCommand.devices && Object.keys(safeCommand.devices).length > 0) {
      await insertCommandPendingLogs({
        deviceId,
        userId: uid,
        source: isServiceCall ? 'ai-agent' : 'api',
        stateUpdate: safeCommand.devices as Record<string, boolean>,
        metadata: {
          endpoint: '/api/devices/[deviceId]/override',
          method: 'POST',
          userOverride: safeCommand.user_override,
          byServiceKey: isServiceCall,
        },
      });
    } else {
      await insertDiagnosticLog({
        deviceId,
        userId: uid,
        source: isServiceCall ? 'ai-agent' : 'api',
        category: isServiceCall ? 'AI' : 'COMMAND',
        status: 'INFO',
        message: safeCommand.user_override
          ? '[INFO] Override command accepted.'
          : '[INFO] Threshold update accepted by API.',
        metadata: {
          endpoint: '/api/devices/[deviceId]/override',
          method: 'POST',
          command: safeCommand,
          byServiceKey: isServiceCall,
        },
      });
    }

    return res.status(200).json({
      success: true,
      device: deviceId,
      message: 'Override command sent',
      mist_locked_off: MIST_SAFETY_LOCK_ENABLED && requestedMistOn,
    });
  } catch (error) {
    console.error('MQTT Error:', error);
    await insertDiagnosticLog({
      deviceId,
      userId: uid,
      source: isServiceCall ? 'ai-agent' : 'api',
      category: isServiceCall ? 'AI' : 'COMMAND',
      status: 'FAIL',
      message: '[FAIL] Override publish to Edge Device failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/override',
        method: 'POST',
        command: safeCommand,
        byServiceKey: isServiceCall,
        error: (error as Error).message,
      },
    });
    return res.status(500).json({ error: 'Failed to communicate with device' });
  }
}
