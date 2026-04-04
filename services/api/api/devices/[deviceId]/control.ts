// api/devices/[deviceId]/control.ts
//
// ROUTE
//   GET  /api/devices/:deviceId/control  — history for the dashboard
//   POST /api/devices/:deviceId/control  — manual relay override
//
// AUTH
//   Both methods require a valid JWT (enforced by `withAuth`).
//   `req.user.userId` is always present inside the handler.
//
// POST EXECUTION ORDER  (must not be reordered)
//   1. Validate input.
//   2. Publish to MQTT broker  →  ESP32 physically changes relay state.
//   3. Only if (2) succeeds: insert audit record into MongoDB.
//
//   This order is intentional. MQTT is the live control path. If we wrote
//   to MongoDB first and MQTT then failed, the database would contain a
//   command that was never actually executed — false history that could
//   mislead both the dashboard and the AI agent.
// ─────────────────────────────────────────────────────────────────────────────

import type { VercelResponse } from '@vercel/node';
import { withAuth, AuthenticatedRequest } from '../../../lib/authMiddleware';
import {
  RelayStatePartial,
  VALID_DEVICE_KEYS,
  isDeviceKey,
  insertDeviceState,
  getRecentDeviceStates,
} from '../../../lib/deviceStateModel';
import { publishCommand } from '../../../lib/mqttPublisher';

// ─── GET handler — dashboard history ─────────────────────────────────────────

/**
 * Returns the most recent device state records for a device, scoped to the
 * authenticated user.
 *
 * Query params:
 *   `limit` (optional) — integer, 1–100, defaults to 20.
 *
 * Response 200:
 * ```json
 * {
 *   "deviceId": "abc123",
 *   "history": [ { ...DeviceStateDocument }, ... ]
 * }
 * ```
 */
async function handleGet(
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> {
  const { deviceId } = req.query;

  // ── Validate deviceId ────────────────────────────────────────────────────
  if (!deviceId || typeof deviceId !== 'string') {
    res.status(400).json({ error: 'deviceId route parameter is required.' });
    return;
  }

  // ── Parse optional `limit` query param ──────────────────────────────────
  let limit = 20;
  if (req.query.limit !== undefined) {
    const parsed = Number(req.query.limit);

    // Reject non-numeric, NaN, or non-integer values explicitly so the user
    // gets a clear error rather than silently falling back to the default.
    if (!Number.isInteger(parsed) || parsed < 1) {
      res.status(400).json({
        error: '`limit` must be a positive integer (1–100).',
      });
      return;
    }
    limit = parsed; // The model layer enforces the 100 ceiling.
  }

  // ── Fetch from MongoDB ───────────────────────────────────────────────────
  try {
    const history = await getRecentDeviceStates(
      deviceId,
      req.user.userId,
      limit,
    );

    res.status(200).json({ deviceId, history });
  } catch (err: unknown) {
    console.error('[GET /api/devices/[deviceId]/control]', err);
    res.status(500).json({ error: 'An unexpected error occurred. Please try again.' });
  }
}

// ─── POST handler — manual relay override ────────────────────────────────────

/**
 * Publishes a relay state update to the ESP32 via MQTT, then records the
 * command in MongoDB as a `'user'` source audit entry.
 *
 * Request body (JSON):
 * ```json
 * { "fan": true, "light": false }
 * ```
 * Only the four canonical keys (`fan`, `heater`, `mist`, `light`) are accepted.
 * At least one key must be present; any keys outside the allowed set are rejected.
 *
 * Response 200:
 * ```json
 * {
 *   "success": true,
 *   "deviceId": "abc123",
 *   "appliedState": { "fan": true, "light": false },
 *   "recordId": "<MongoDB ObjectId string>"
 * }
 * ```
 */
async function handlePost(
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> {
  const { deviceId } = req.query;

  // ── Validate deviceId ────────────────────────────────────────────────────
  if (!deviceId || typeof deviceId !== 'string') {
    res.status(400).json({ error: 'deviceId route parameter is required.' });
    return;
  }

  // ── Validate request body ────────────────────────────────────────────────
  const body = req.body;

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  // Collect only the recognised device keys from the body.
  // Reject the request if any key in the body is outside the allowed set —
  // this prevents typos (e.g. "Fan" or "heaters") from being silently ignored
  // and causing the user to believe a command was sent when it wasn't.
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

  // Build a strictly typed partial state object; reject any value that is not
  // a boolean to prevent the ESP32 from receiving malformed MQTT payloads.
  const stateUpdate: RelayStatePartial = {};

  for (const key of bodyKeys) {
    if (!isDeviceKey(key)) continue; // already caught above, belt-and-suspenders
    const value = (body as Record<string, unknown>)[key];

    if (typeof value !== 'boolean') {
      res.status(400).json({
        error: `Value for '${key}' must be a boolean (true or false).`,
      });
      return;
    }
    stateUpdate[key] = value;
  }

  // ── Step 1: Publish to MQTT ──────────────────────────────────────────────
  //
  // This is performed BEFORE the database write. The ESP32 is the physical
  // ground truth — if we cannot reach it there is nothing to record.
  // If publishCommand throws, we catch it below and return 502, leaving the
  // database unchanged so the history stays accurate.
  try {
    await publishCommand(deviceId, { ...stateUpdate, user_override: true });
  } catch (mqttErr: unknown) {
    console.error('[POST /api/devices/[deviceId]/control] MQTT publish failed', mqttErr);
    res.status(502).json({
      error: 'Failed to publish command to the device. The relay state has not changed.',
    });
    return; // Do NOT fall through to the DB write.
  }

  // ── Step 2: Insert audit record into MongoDB ─────────────────────────────
  //
  // Reached only if MQTT succeeded. `source` is hardcoded to `'user'` because
  // this handler is exclusively the User tier of the priority architecture.
  // The AI agent and local hysteresis write their own records via separate paths.
  try {
    const recordId = await insertDeviceState(
      deviceId,
      req.user.userId,
      stateUpdate,
      'user', // ← Tiered Priority: User override; never change this here.
    );

    res.status(200).json({
      success:      true,
      deviceId,
      appliedState: stateUpdate,
      recordId,
    });
  } catch (dbErr: unknown) {
    // MQTT has already fired at this point — the relay physically changed.
    // We log the DB failure but do not unwind the hardware state (we can't).
    // The client gets a 207 to signal partial success: command delivered but
    // not recorded. The dashboard should re-fetch history to verify.
    console.error('[POST /api/devices/[deviceId]/control] MongoDB insert failed', dbErr);
    res.status(207).json({
      success:      true,
      deviceId,
      appliedState: stateUpdate,
      warning:      'Command was sent to the device but could not be recorded in the database.',
    });
  }
}

// ─── Exported Vercel handler (entry point) ────────────────────────────────────

/**
 * Main handler exported to Vercel.
 *
 * Wrapped in `withAuth` — every code path (GET and POST) requires a valid JWT.
 * The outer wrapper handles 401 responses before this function is ever reached.
 */
export default withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> => {

  switch (req.method) {
    case 'GET':
      await handleGet(req, res);
      break;

    case 'POST':
      await handlePost(req, res);
      break;

    default:
      // Return the accepted methods in the Allow header — good HTTP practice
      // and required by RFC 7231 §6.5.5 for a proper 405 response.
      res.setHeader('Allow', 'GET, POST');
      res.status(405).json({
        error: `Method '${req.method}' is not allowed on this endpoint.`,
      });
  }
});