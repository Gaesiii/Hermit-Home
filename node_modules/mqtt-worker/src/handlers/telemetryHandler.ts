import { TelemetryPayload } from '@smart-terrarium/shared-types';
import { insertTelemetry } from '../db/telemetryRepo';
import { logger } from '../utils/logger';

const TELEMETRY_TOPIC_PREFIX = 'terrarium/telemetry/';
const MONGO_OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
const MAX_TELEMETRY_MESSAGE_BYTES = 8 * 1024;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isBoolean(value: unknown): value is boolean {
  return typeof value === 'boolean';
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isNullableFiniteNumber(value: unknown): value is number | null {
  return value === null || isFiniteNumber(value);
}

function isValidRelays(value: unknown): value is TelemetryPayload['relays'] {
  if (!isPlainObject(value)) {
    return false;
  }

  return (
    isBoolean(value.heater) &&
    isBoolean(value.mist) &&
    isBoolean(value.fan) &&
    isBoolean(value.light)
  );
}

function isValidTelemetryPayload(value: unknown): value is TelemetryPayload {
  if (!isPlainObject(value)) {
    return false;
  }

  if (
    !isNullableFiniteNumber(value.temperature) ||
    !isNullableFiniteNumber(value.humidity) ||
    !isFiniteNumber(value.lux) ||
    !isBoolean(value.sensor_fault) ||
    !isBoolean(value.user_override) ||
    !isValidRelays(value.relays)
  ) {
    return false;
  }

  if (value.temperature !== null && (value.temperature < -40 || value.temperature > 85)) {
    return false;
  }

  if (value.humidity !== null && (value.humidity < 0 || value.humidity > 100)) {
    return false;
  }

  if (value.lux < 0 || value.lux > 200000) {
    return false;
  }

  return true;
}

function getDeviceIdFromTopic(topic: string): string | null {
  if (!topic.startsWith(TELEMETRY_TOPIC_PREFIX)) {
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

export async function handleTelemetry(
  topic: string,
  message: Buffer,
  allowedDeviceIds: ReadonlySet<string>
): Promise<void> {
  const deviceId = getDeviceIdFromTopic(topic);
  if (!deviceId) {
    logger.warn({ topic }, 'Dropped telemetry due to invalid topic format');
    return;
  }

  if (!allowedDeviceIds.has(deviceId)) {
    logger.warn({ topic, deviceId }, 'Dropped telemetry from unauthorized device topic');
    return;
  }

  if (message.byteLength > MAX_TELEMETRY_MESSAGE_BYTES) {
    logger.warn(
      { topic, size: message.byteLength },
      'Dropped telemetry payload because it exceeds the maximum size'
    );
    return;
  }

  try {
    const parsed: unknown = JSON.parse(message.toString('utf8'));
    if (!isValidTelemetryPayload(parsed)) {
      logger.warn({ topic, deviceId }, 'Dropped telemetry with invalid schema');
      return;
    }

    await insertTelemetry(deviceId, parsed);
  } catch (error: unknown) {
    logger.error(
      { err: error, topic, payload: message.toString('utf8') },
      'Failed to parse telemetry payload'
    );
  }
}
