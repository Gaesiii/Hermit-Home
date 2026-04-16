import { Db } from 'mongodb';
import { DeviceMode, DeviceStatePatch, DeviceStateRecord, RelayState } from '@smart-terrarium/shared-types';
import { sanitizeRelayMap } from './mistSafety';
import { toUtc7Iso } from './timezone';

const COLLECTION_NAME = 'devices';

const DEFAULT_RELAYS: RelayState = {
  heater: false,
  mist: false,
  fan: false,
  light: false
};

type DeviceDocument = {
  deviceId: string;
  mode?: DeviceMode;
  user_override?: boolean;
  relays?: Partial<RelayState>;
  lastTelemetryAt?: Date | string | null;
  lastCommandAt?: Date | string | null;
  updatedAt?: Date | string | null;
};

function toIsoString(value: Date | string | null | undefined): string | null {
  return toUtc7Iso(value);
}

function mapDeviceDocument(doc: DeviceDocument): DeviceStateRecord {
  return {
    deviceId: doc.deviceId,
    mode: doc.mode ?? 'AUTO',
    user_override: doc.user_override ?? false,
    relays: {
      ...DEFAULT_RELAYS,
      ...sanitizeRelayMap(doc.relays)
    },
    lastTelemetryAt: toIsoString(doc.lastTelemetryAt),
    lastCommandAt: toIsoString(doc.lastCommandAt),
    updatedAt: toIsoString(doc.updatedAt) ?? toUtc7Iso(new Date(0))!
  };
}

export async function listDevices(db: Db): Promise<DeviceStateRecord[]> {
  const docs = await db
    .collection<DeviceDocument>(COLLECTION_NAME)
    .find({})
    .sort({ updatedAt: -1 })
    .toArray();

  return docs.map(mapDeviceDocument);
}

export async function getDeviceById(db: Db, deviceId: string): Promise<DeviceStateRecord | null> {
  const doc = await db.collection<DeviceDocument>(COLLECTION_NAME).findOne({ deviceId });
  return doc ? mapDeviceDocument(doc) : null;
}

export async function patchDeviceById(
  db: Db,
  deviceId: string,
  patch: DeviceStatePatch
): Promise<DeviceStateRecord> {
  const now = new Date();
  const update: Record<string, unknown> = {
    updatedAt: now
  };

  if (patch.mode) {
    update.mode = patch.mode;
  }

  if (typeof patch.user_override === 'boolean') {
    update.user_override = patch.user_override;
  }

  if (patch.relays) {
    update.relays = {
      ...DEFAULT_RELAYS,
      ...sanitizeRelayMap(patch.relays)
    };
  }

  const setOnInsert: Record<string, unknown> = {
    deviceId,
    lastTelemetryAt: null,
    lastCommandAt: null
  };

  if (!('mode' in update)) {
    setOnInsert.mode = 'AUTO';
  }

  if (!('user_override' in update)) {
    setOnInsert.user_override = false;
  }

  if (!('relays' in update)) {
    setOnInsert.relays = { ...DEFAULT_RELAYS };
  }

  const result = await db.collection<DeviceDocument>(COLLECTION_NAME).findOneAndUpdate(
    { deviceId },
    {
      $set: update,
      $setOnInsert: setOnInsert
    },
    {
      upsert: true,
      returnDocument: 'after'
    }
  );

  if (!result) {
    throw new Error('Failed to update device');
  }

  return mapDeviceDocument(result);
}

export async function markCommandSent(
  db: Db,
  deviceId: string,
  patch: DeviceStatePatch
): Promise<void> {
  const now = new Date();
  const update: Record<string, unknown> = {
    updatedAt: now,
    lastCommandAt: now
  };

  if (patch.mode) {
    update.mode = patch.mode;
  }

  if (typeof patch.user_override === 'boolean') {
    update.user_override = patch.user_override;
  }

  if (patch.relays) {
    update.relays = {
      ...DEFAULT_RELAYS,
      ...sanitizeRelayMap(patch.relays)
    };
  }

  await db.collection<DeviceDocument>(COLLECTION_NAME).updateOne(
    { deviceId },
    {
      $set: update,
      $setOnInsert: {
        deviceId,
        lastTelemetryAt: null
      }
    },
    { upsert: true }
  );
}
