// lib/deviceStateModel.ts
//
// PURPOSE
// ─────────────────────────────────────────────────────────────────────────────
// Single source of truth for everything related to the `device_states`
// MongoDB collection:
//   • TypeScript interface that mirrors the stored document shape.
//   • A runtime validator for the four legal device keys.
//   • Two repository functions — one for writing audit records, one for
//     reading recent history.
//
// All database access goes through the project-wide singleton from
// `lib/mongoClient` to avoid opening multiple connections in Vercel's
// short-lived serverless workers.
// ─────────────────────────────────────────────────────────────────────────────

import { Collection, ObjectId } from 'mongodb';
import { connectToDatabase } from './mongoClient';

// ─── Device vocabulary ────────────────────────────────────────────────────────
//
// These four string literals are the canonical device keys used everywhere:
// ESP32 firmware (config.h relay pins), MQTT command payloads, and the API.
// Changing a name here must be accompanied by firmware + MQTT topic changes.

export const VALID_DEVICE_KEYS = ['fan', 'heater', 'mist', 'light'] as const;

/** Union of the four legal device actuator names. */
export type DeviceKey = typeof VALID_DEVICE_KEYS[number];

/**
 * Runtime guard that narrows an unknown string to `DeviceKey`.
 * Use this in handlers instead of a raw `.includes()` so TypeScript
 * understands the type after the check.
 */
export function isDeviceKey(value: unknown): value is DeviceKey {
  return typeof value === 'string' &&
    (VALID_DEVICE_KEYS as readonly string[]).includes(value);
}

// ─── Document shape ───────────────────────────────────────────────────────────

/**
 * Partial relay state sent with each command or stored as a snapshot.
 *
 * Every field is optional because:
 *   • A single POST may only toggle one device (e.g. `{ fan: true }`).
 *   • The AI agent sends only the fields it has a recommendation for.
 *
 * `true`  = device is ON (relay energised).
 * `false` = device is OFF (relay de-energised).
 */
export interface RelayStatePartial {
  fan?:    boolean;
  heater?: boolean;
  mist?:   boolean;
  light?:  boolean;
}

/**
 * The `source` discriminant records which control tier created the record.
 * Mirrors the Tiered Priority architecture: User > AI > Local.
 *
 * `'user'`  — manual override from the mobile app / dashboard.
 * `'ai'`    — recommendation from the Python AI Agent service.
 * `'local'` — autonomous hysteresis decision on the ESP32 itself.
 */
export type StateSource = 'user' | 'ai' | 'local';

/**
 * Shape of a single document in the `device_states` collection.
 *
 * One document = one atomic state-change event.
 * The collection is append-only (no updates); every change produces a new
 * record so the full history is always reconstructable.
 */
export interface DeviceStateDocument {
  _id?:      ObjectId;
  /** ESP32 device identifier — used as the MQTT topic segment. */
  deviceId:  string;
  /** UID of the user who owns the device / triggered the command. */
  userId:    string;
  /** Partial relay snapshot sent with this event. */
  state:     RelayStatePartial;
  /** Which control tier produced this record. */
  source:    StateSource;
  /** Server-assigned UTC timestamp — never trust client-supplied time. */
  createdAt: Date;
}

// ─── Collection accessor ──────────────────────────────────────────────────────

const COLLECTION_NAME = 'device_states' as const;

/**
 * Returns the typed MongoDB collection for `device_states`.
 *
 * Re-uses the singleton connection from `lib/mongoClient`.
 * Safe to call on every request — the underlying client is cached on `global`.
 */
async function getCollection(): Promise<Collection<DeviceStateDocument>> {
  const { db } = await connectToDatabase();
  return db.collection<DeviceStateDocument>(COLLECTION_NAME);
}

// ─── Repository functions ─────────────────────────────────────────────────────

/**
 * Inserts a new device state audit record.
 *
 * Called exclusively by `api/devices/[deviceId]/control.ts` **after** a
 * successful MQTT publish. Do not call this if MQTT fails — a record without
 * a corresponding hardware command would create false history.
 *
 * @param deviceId  The ESP32 device ID from the URL route parameter.
 * @param userId    The authenticated user's ID (string form from JWT, stored
 *                  as ObjectId in the DB for cross-collection join compatibility).
 * @param state     The partial relay update that was published.
 * @param source    Control tier — callers in this API always pass `'user'`.
 * @returns         The MongoDB-assigned `_id` of the new document (as a string).
 */
export async function insertDeviceState(
  deviceId: string,
  userId:   string,
  state:    RelayStatePartial,
  source:   StateSource,
): Promise<string> {
  const collection = await getCollection();

  const document: DeviceStateDocument = {
    deviceId,
    userId,
    state,
    source,
    createdAt: new Date(), // server-side timestamp — never from client body
  };

  const result = await collection.insertOne(document);
  return result.insertedId.toString();
}

/**
 * Fetches the most recent device state records for a given device + user pair,
 * ordered newest first.
 *
 * Used by the GET /control handler to populate the dashboard history panel.
 *
 * @param deviceId  The ESP32 device ID from the URL route parameter.
 * @param userId    The authenticated user's ID (string). Converted to ObjectId
 *                  internally so the query matches the stored type.
 * @param limit     Maximum number of records to return. Capped at 100 to avoid
 *                  accidentally loading unbounded history on the frontend.
 * @returns         Array of `DeviceStateDocument`, newest first.
 */
export async function getRecentDeviceStates(
  deviceId: string,
  userId:   string,
  limit     = 20,
): Promise<DeviceStateDocument[]> {
  const collection = await getCollection();

  // Enforce a hard ceiling so a malicious or buggy client cannot request
  // an arbitrarily large result set and exhaust the serverless function's
  // memory or response timeout.
  const safeLimit = Math.min(Math.max(1, limit), 100);

  return collection
    .find({
      deviceId,
      // Scope results strictly to the calling user. A user must not be able
      // to read another user's device history even if they know the deviceId.
      userId,
    })
    .sort({ createdAt: -1 }) // newest first — matches dashboard scroll direction
    .limit(safeLimit)
    .toArray();
}
