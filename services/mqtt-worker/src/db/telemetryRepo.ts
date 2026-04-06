import { TelemetryPayload } from '@smart-terrarium/shared-types';
import { getDb } from './mongoClient';
import { logger } from '../utils/logger';

const COLLECTION_NAME = 'telemetry';

export async function insertTelemetry(userId: string, payload: TelemetryPayload): Promise<void> {
  try {
    const collection = getDb().collection(COLLECTION_NAME);

    // Persist only known keys to prevent operator/object injection.
    const document = {
      userId,
      timestamp: new Date(),
      temperature: payload.temperature,
      humidity: payload.humidity,
      lux: payload.lux,
      sensor_fault: payload.sensor_fault,
      user_override: payload.user_override,
      relays: {
        heater: payload.relays.heater,
        mist: payload.relays.mist,
        fan: payload.relays.fan,
        light: payload.relays.light,
      },
    };

    await collection.insertOne(document);
    logger.debug({ userId }, 'Telemetry saved to MongoDB');
  } catch (error: unknown) {
    logger.error({ err: error, userId }, 'Failed to insert telemetry into MongoDB');
  }
}
