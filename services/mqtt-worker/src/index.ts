import express from 'express';
import dotenv from 'dotenv';
import mqtt, { IClientOptions, MqttClient } from 'mqtt';
import { connectDB } from './db/mongoClient';
import { handleTelemetry } from './handlers/telemetryHandler';
import { handleConfirm } from './handlers/confirmHandler';
import { logger } from './utils/logger';

dotenv.config();

const DEVICE_ID_REGEX = /^[a-f\d]{24}$/i;

function parseAllowedDeviceIds(): string[] {
  const raw = process.env.ALLOWED_DEVICE_IDS || process.env.DEVICE_ID || '';
  const ids = raw
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);

  if (ids.length === 0) {
    throw new Error(
      'Missing ALLOWED_DEVICE_IDS (or DEVICE_ID). Configure at least one authorized device id.'
    );
  }

  const uniqueIds = [...new Set(ids)];
  for (const id of uniqueIds) {
    if (!DEVICE_ID_REGEX.test(id)) {
      throw new Error(`Invalid device id in ALLOWED_DEVICE_IDS: "${id}"`);
    }
  }

  return uniqueIds;
}

function buildMqttOptions(): IClientOptions {
  const username = process.env.MQTT_USER || '';
  const password = process.env.MQTT_PASS || '';
  const caCert = process.env.MQTT_CA_CERT?.replace(/\\n/g, '\n');

  if (!username || !password) {
    throw new Error('Missing MQTT credentials. Check MQTT_USER and MQTT_PASS.');
  }

  const options: IClientOptions = {
    username,
    password,
    clientId: `mqtt-worker-${Math.random().toString(16).slice(2, 10)}`,
    rejectUnauthorized: true,
    reconnectPeriod: 2000,
    connectTimeout: 5000,
  };

  if (caCert) {
    options.ca = caCert;
  }

  return options;
}

async function bootstrap(): Promise<void> {
  await connectDB();

  const host = process.env.MQTT_BROKER || '';
  const port = Number.parseInt(process.env.MQTT_PORT || '8883', 10);
  if (!host) {
    throw new Error('Missing MQTT_BROKER environment variable.');
  }

  const allowedDeviceIds = parseAllowedDeviceIds();
  const authorizedTopics = allowedDeviceIds.map((deviceId) => `terrarium/telemetry/${deviceId}`);
  const authorizedConfirmTopics = allowedDeviceIds.map((deviceId) => `terrarium/confirm/${deviceId}`);
  const allowedDeviceIdSet = new Set(allowedDeviceIds);
  const brokerUrl = `mqtts://${host}:${port}`;

  logger.info({ brokerUrl, allowedDeviceIds }, 'Connecting to MQTT broker');

  const mqttClient = mqtt.connect(brokerUrl, buildMqttOptions());

  mqttClient.on('connect', () => {
    const topicsToSubscribe = [...authorizedTopics, ...authorizedConfirmTopics];

    mqttClient.subscribe(topicsToSubscribe, { qos: 1 }, (err, granted) => {
      if (err) {
        logger.error({ err, topicsToSubscribe }, 'Failed to subscribe to MQTT topics');
        return;
      }

      logger.info({ granted }, 'Subscribed to authorized telemetry and confirm topics');
    });
  });

  mqttClient.on('error', (err: Error) => {
    logger.error({ err }, 'MQTT client error');
  });

  mqttClient.on('message', (topic: string, message: Buffer) => {
    if (!topic.startsWith('terrarium/telemetry/')) {
      if (topic.startsWith('terrarium/confirm/')) {
        handleConfirm(topic, message, allowedDeviceIdSet);
      }
      return;
    }

    void handleTelemetry(topic, message, allowedDeviceIdSet);
  });

  registerShutdownHandlers(mqttClient);
}

function registerShutdownHandlers(mqttClient: MqttClient): void {
  const shutdown = (signal: string) => {
    logger.info({ signal }, 'Shutting down mqtt-worker');
    mqttClient.end(false, () => {
      logger.info('MQTT client disconnected');
      process.exit(0);
    });

    setTimeout(() => {
      logger.error('Forced shutdown after timeout');
      process.exit(1);
    }, 5000);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

function startHealthServer(): void {
  const app = express();
  const port = Number.parseInt(process.env.PORT || '10000', 10);

  app.get('/ping', (_req, res) => {
    res.status(200).send('MQTT Worker is running');
  });

  app.listen(port, () => {
    logger.info({ port }, 'Health server started');
  });
}

startHealthServer();
bootstrap().catch((err: unknown) => {
  logger.fatal({ err }, 'Failed to bootstrap mqtt-worker');
  process.exit(1);
});
