import { db } from './mongoClient';
import { TelemetryPayload } from '@smart-terrarium/shared-types';
import { logger } from '../utils/logger';

const COLLECTION_NAME = 'telemetry';

export async function insertTelemetry(userId: string, payload: TelemetryPayload): Promise<void> {
  try {
    const collection = db.collection(COLLECTION_NAME);
    
    // Spread the payload and attach a server-side timestamp and the User ID
    const document = {
      userId,
      timestamp: new Date(), 
      ...payload
    };

    await collection.insertOne(document);
    logger.debug(`📥 Telemetry saved to DB for user: ${userId}`);
  } catch (error) {
    logger.error({ err: error, userId }, '❌ Failed to insert telemetry into DB');
  }
}