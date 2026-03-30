import { TelemetryPayload } from '@smart-terrarium/shared-types';
import { logger } from '../utils/logger';
import { insertTelemetry } from '../db/telemetryRepo';

export async function handleTelemetry(topic: string, message: Buffer): Promise<void> {
  try {
    // Topic structure is expected to be: terrarium/telemetry/{userId}
    const topicParts = topic.split('/');
    if (topicParts.length < 3) {
      logger.warn({ topic }, 'Invalid topic format received for telemetry');
      return;
    }

    const userId = topicParts[2];
    
    // Parse the incoming JSON payload
    const payloadStr = message.toString();
    const payload = JSON.parse(payloadStr) as TelemetryPayload;

    // Insert into database
    await insertTelemetry(userId, payload);
    
  } catch (error) {
    logger.error({ err: error, topic, payload: message.toString() }, 'Failed to parse or process telemetry message');
  }
}