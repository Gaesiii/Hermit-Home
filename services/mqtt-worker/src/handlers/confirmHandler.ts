import { logger } from '../utils/logger';

const CONFIRM_TOPIC_PREFIX = 'terrarium/confirm/';
const MONGO_OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;

function getDeviceIdFromConfirmTopic(topic: string): string | null {
  if (!topic.startsWith(CONFIRM_TOPIC_PREFIX)) {
    return null;
  }

  const parts = topic.split('/');
  if (parts.length !== 3) {
    return null;
  }

  const deviceId = parts[2];
  if (!MONGO_OBJECT_ID_REGEX.test(deviceId)) {
    return null;
  }

  return deviceId;
}

export function handleConfirm(
  topic: string,
  message: Buffer,
  allowedDeviceIds: ReadonlySet<string> | null
): void {
  const deviceId = getDeviceIdFromConfirmTopic(topic);
  if (!deviceId) {
    logger.warn({ topic }, 'Dropped confirm message due to invalid topic format');
    return;
  }

  if (allowedDeviceIds && !allowedDeviceIds.has(deviceId)) {
    logger.warn({ topic, deviceId }, 'Dropped confirm message from unauthorized topic');
    return;
  }

  const raw = message.toString('utf8');

  try {
    const parsed = JSON.parse(raw) as {
      event?: unknown;
      device?: unknown;
      state?: unknown;
      status?: unknown;
    };

    // Offline LWT from ESP32 on disconnect.
    if (parsed.status === 'offline') {
      logger.warn({ deviceId }, 'ESP32 reported offline status');
      return;
    }

    if (
      parsed.event !== 'override_ack' ||
      typeof parsed.device !== 'string' ||
      typeof parsed.state !== 'boolean'
    ) {
      logger.warn({ topic, payload: raw }, 'Dropped confirm message with invalid schema');
      return;
    }

    logger.info(
      { deviceId, device: parsed.device, state: parsed.state },
      'Received ESP32 override acknowledgement'
    );
  } catch (error: unknown) {
    logger.error({ err: error, topic, payload: raw }, 'Failed to parse confirm payload');
  }
}
