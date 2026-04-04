import { DeviceMode, RelayState, TelemetryPayload } from '@smart-terrarium/shared-types';
import { db } from './mongoClient';
import { logger } from '../utils/logger';

const COLLECTION_NAME = 'devices';

const DEFAULT_RELAYS: RelayState = {
  heater: false,
  mist: false,
  fan: false,
  light: false
};

export async function upsertDeviceStateFromTelemetry(
  deviceId: string,
  payload: TelemetryPayload
): Promise<void> {
  try {
    const collection = db.collection(COLLECTION_NAME);
    const now = new Date();
    const mode: DeviceMode = payload.user_override ? 'MANUAL' : 'AUTO';

    await collection.updateOne(
      { deviceId },
      {
        $set: {
          mode,
          user_override: payload.user_override,
          relays: {
            ...DEFAULT_RELAYS,
            ...payload.relays
          },
          lastTelemetryAt: now,
          updatedAt: now
        },
        $setOnInsert: {
          deviceId,
          lastCommandAt: null
        }
      },
      { upsert: true }
    );

    logger.debug(`Device snapshot updated for device: ${deviceId}`);
  } catch (error) {
    logger.error({ err: error, deviceId }, 'Failed to upsert device snapshot');
  }
}
