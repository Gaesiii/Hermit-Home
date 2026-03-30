import mqtt from 'mqtt';
import dotenv from 'dotenv';
import { logger } from './utils/logger';
import { connectDB } from './db/mongoClient';
import { handleTelemetry } from './handlers/telemetryHandler';

dotenv.config();

async function bootstrap() {
  // 1. Connect to MongoDB
  await connectDB();

  // 2. Setup MQTT Connection Options
  const protocol = 'mqtts'; // Using secure MQTT for HiveMQ
  const host = process.env.MQTT_BROKER || '';
  const port = process.env.MQTT_PORT ? parseInt(process.env.MQTT_PORT, 10) : 8883;
  const username = process.env.MQTT_USER || '';
  const password = process.env.MQTT_PASS || '';

  const brokerUrl = `${protocol}://${host}:${port}`;

  logger.info(`Connecting to MQTT broker at ${brokerUrl}...`);

  const mqttClient = mqtt.connect(brokerUrl, {
    username,
    password,
    clientId: `mqtt-worker-${Math.random().toString(16).substring(2, 10)}`,
    rejectUnauthorized: false // Required for some HiveMQ configurations matching the ESP32 setup
  });

  // 3. Handle Connection Events
  mqttClient.on('connect', () => {
    logger.info('✅ Connected to HiveMQ MQTT Broker');
    
    const telemetryTopic = 'terrarium/telemetry/+';
    mqttClient.subscribe(telemetryTopic, (err) => {
      if (err) {
        logger.error({ err }, `Failed to subscribe to ${telemetryTopic}`);
      } else {
        logger.info(`📡 Subscribed to topic: ${telemetryTopic}`);
      }
    });
  });

  mqttClient.on('error', (err) => {
    logger.error({ err }, 'MQTT Client Error');
  });

  // 4. Message Router
  mqttClient.on('message', (topic: string, message: Buffer) => {
    if (topic.startsWith('terrarium/telemetry/')) {
      handleTelemetry(topic, message);
    }
  });

  // 5. Graceful Shutdown
  const shutdown = async (signal: string) => {
    logger.info(`\n${signal} received. Shutting down gracefully...`);
    
    mqttClient.end(false, () => {
      logger.info('MQTT client disconnected.');
      process.exit(0);
    });

    // Fallback force exit if it hangs
    setTimeout(() => {
      logger.error('Forcing shutdown due to timeout');
      process.exit(1);
    }, 5000);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

bootstrap().catch((err) => {
  logger.fatal({ err }, 'Failed to bootstrap mqtt-worker');
  process.exit(1);
});