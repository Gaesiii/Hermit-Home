import express from 'express';
import dotenv from 'dotenv';
import mqtt, { IClientOptions, MqttClient } from 'mqtt';
import { connectDB } from './db/mongoClient';
import { handleTelemetry } from './handlers/telemetryHandler';
import { handleConfirm } from './handlers/confirmHandler';
import { logger } from './utils/logger';

dotenv.config();

const DEVICE_ID_REGEX = /^[a-f\d]{24}$/i;
const DEFAULT_SELF_PING_INTERVAL_MS = 3 * 60 * 1000;
const DEFAULT_SELF_PING_TIMEOUT_MS = 10_000;
const DEFAULT_AGENT_CONTROL_INTERVAL_MS = 20_000;
const DEFAULT_AGENT_CONTROL_TIMEOUT_MS = 8_000;
const SELF_PING_USER_AGENT = 'mqtt-worker-self-keepalive/1.0';
const AGENT_CONTROL_USER_AGENT = 'mqtt-worker-agent-control/1.0';
const TELEMETRY_WILDCARD_TOPIC = 'terrarium/telemetry/+';
const CONFIRM_WILDCARD_TOPIC = 'terrarium/confirm/+';

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}

function resolveSelfPingUrl(): string | null {
  const explicitSelfPingUrl = process.env.SELF_PING_URL?.trim();
  if (explicitSelfPingUrl) {
    return explicitSelfPingUrl;
  }

  const renderExternalUrl = process.env.RENDER_EXTERNAL_URL?.trim();
  if (!renderExternalUrl) {
    return null;
  }

  return `${renderExternalUrl.replace(/\/+$/, '')}/`;
}

function parseAllowedDeviceIds(): string[] {
  const raw = process.env.ALLOWED_DEVICE_IDS || process.env.DEVICE_ID || '';
  const ids = raw
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);

  if (ids.length === 0) {
    return [];
  }

  const uniqueIds = [...new Set(ids)];
  for (const id of uniqueIds) {
    if (!DEVICE_ID_REGEX.test(id)) {
      throw new Error(`Invalid device id in ALLOWED_DEVICE_IDS: "${id}"`);
    }
  }

  return uniqueIds;
}

function parseBooleanFlag(value: string | undefined): boolean {
  if (!value) return false;
  const normalized = value.trim().toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
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
  const enforceAllowedDeviceIds = parseBooleanFlag(process.env.ENFORCE_ALLOWED_DEVICE_IDS);

  if (!enforceAllowedDeviceIds && allowedDeviceIds.length > 0) {
    logger.warn(
      { allowedDeviceIds },
      'Ignoring ALLOWED_DEVICE_IDS/DEVICE_ID because ENFORCE_ALLOWED_DEVICE_IDS is disabled'
    );
  }

  const effectiveAllowedDeviceIds = enforceAllowedDeviceIds ? allowedDeviceIds : [];
  const allowedDeviceIdSet =
    effectiveAllowedDeviceIds.length > 0 ? new Set(effectiveAllowedDeviceIds) : null;
  const authorizedTopics =
    effectiveAllowedDeviceIds.length > 0
      ? effectiveAllowedDeviceIds.map((deviceId) => `terrarium/telemetry/${deviceId}`)
      : [TELEMETRY_WILDCARD_TOPIC];
  const authorizedConfirmTopics =
    effectiveAllowedDeviceIds.length > 0
      ? effectiveAllowedDeviceIds.map((deviceId) => `terrarium/confirm/${deviceId}`)
      : [CONFIRM_WILDCARD_TOPIC];
  const brokerUrl = `mqtts://${host}:${port}`;

  logger.info(
    {
      brokerUrl,
      enforceAllowedDeviceIds,
      allowedDeviceIds:
        effectiveAllowedDeviceIds.length > 0
          ? effectiveAllowedDeviceIds
          : 'ALL_VALID_OBJECT_IDS',
    },
    'Connecting to MQTT broker'
  );

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
        void handleConfirm(topic, message, allowedDeviceIdSet);
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

  app.get('/', (_req, res) => {
    res.status(200).send('MQTT Worker is running');
  });

  app.listen(port, () => {
    logger.info({ port }, 'Health server started');
  });
}

function startSelfKeepalivePingLoop(): void {
  const targetUrl = resolveSelfPingUrl();
  if (!targetUrl) {
    logger.warn(
      'Self keepalive ping disabled. Configure SELF_PING_URL or RENDER_EXTERNAL_URL to enable it.'
    );
    return;
  }

  const intervalMs = parsePositiveInteger(
    process.env.SELF_PING_INTERVAL_MS,
    DEFAULT_SELF_PING_INTERVAL_MS
  );
  const timeoutMs = parsePositiveInteger(
    process.env.SELF_PING_TIMEOUT_MS,
    DEFAULT_SELF_PING_TIMEOUT_MS
  );

  let inFlight = false;
  const runPing = async (): Promise<void> => {
    if (inFlight) {
      return;
    }

    inFlight = true;
    const startedAt = Date.now();

    try {
      const response = await fetch(targetUrl, {
        method: 'GET',
        headers: { 'User-Agent': SELF_PING_USER_AGENT },
        signal: AbortSignal.timeout(timeoutMs),
      });

      const durationMs = Date.now() - startedAt;
      if (!response.ok) {
        logger.warn(
          { targetUrl, status: response.status, durationMs },
          'Self keepalive ping returned non-OK status'
        );
      } else {
        logger.info({ targetUrl, status: response.status, durationMs }, 'Self keepalive ping success');
      }
    } catch (error: unknown) {
      logger.warn({ err: error, targetUrl }, 'Self keepalive ping failed');
    } finally {
      inFlight = false;
    }
  };

  setInterval(() => {
    void runPing();
  }, intervalMs);

  logger.info({ targetUrl, intervalMs, timeoutMs }, 'Self keepalive ping loop enabled');
}

function parseAgentControlMethod(value: string | undefined): 'GET' | 'POST' {
  if (!value) return 'POST';
  const normalized = value.trim().toUpperCase();
  return normalized === 'GET' ? 'GET' : 'POST';
}

function startAgentControlTriggerLoop(): void {
  const enabled = parseBooleanFlag(process.env.AGENT_CONTROL_ENABLED);
  if (!enabled) {
    logger.info('Agent control trigger loop disabled. Set AGENT_CONTROL_ENABLED=true to enable.');
    return;
  }

  const targetUrl = process.env.AGENT_CONTROL_URL?.trim();
  if (!targetUrl) {
    logger.warn('Agent control trigger loop disabled: missing AGENT_CONTROL_URL.');
    return;
  }

  const intervalMs = parsePositiveInteger(
    process.env.AGENT_CONTROL_INTERVAL_MS,
    DEFAULT_AGENT_CONTROL_INTERVAL_MS
  );
  const timeoutMs = parsePositiveInteger(
    process.env.AGENT_CONTROL_TIMEOUT_MS,
    DEFAULT_AGENT_CONTROL_TIMEOUT_MS
  );
  const method = parseAgentControlMethod(process.env.AGENT_CONTROL_METHOD);
  const apiKey = process.env.AGENT_CONTROL_API_KEY?.trim();
  const bodyRaw = process.env.AGENT_CONTROL_BODY_JSON?.trim();
  const defaultDeviceIdCandidate = process.env.DEVICE_ID?.trim();
  const defaultAllowedDeviceIdCandidate = process.env.ALLOWED_DEVICE_IDS
    ?.split(',')
    .map((id) => id.trim())
    .find((id) => DEVICE_ID_REGEX.test(id));

  const defaultBodyPayload: Record<string, unknown> = {
    source: 'mqtt-worker',
    trigger: 'interval',
  };

  if (defaultDeviceIdCandidate && DEVICE_ID_REGEX.test(defaultDeviceIdCandidate)) {
    defaultBodyPayload.deviceId = defaultDeviceIdCandidate;
  } else if (defaultAllowedDeviceIdCandidate) {
    defaultBodyPayload.deviceId = defaultAllowedDeviceIdCandidate;
  }

  let bodyToSend = JSON.stringify(defaultBodyPayload);
  if (bodyRaw) {
    try {
      JSON.parse(bodyRaw);
      bodyToSend = bodyRaw;
    } catch {
      logger.warn('AGENT_CONTROL_BODY_JSON is not valid JSON. Fallback to default payload.');
    }
  }

  let inFlight = false;
  let consecutiveFailures = 0;

  const runTrigger = async (): Promise<void> => {
    if (inFlight) {
      logger.warn({ targetUrl }, 'Agent control trigger skipped because previous request is still in-flight');
      return;
    }

    inFlight = true;
    const startedAt = Date.now();

    try {
      const headers: Record<string, string> = {
        'User-Agent': AGENT_CONTROL_USER_AGENT,
      };

      if (apiKey) {
        headers['x-api-key'] = apiKey;
      }

      if (method === 'POST') {
        headers['Content-Type'] = 'application/json';
      }

      const response = await fetch(targetUrl, {
        method,
        headers,
        body: method === 'POST' ? bodyToSend : undefined,
        signal: AbortSignal.timeout(timeoutMs),
      });

      const durationMs = Date.now() - startedAt;
      if (!response.ok) {
        consecutiveFailures += 1;
        logger.warn(
          { targetUrl, method, status: response.status, durationMs, consecutiveFailures },
          'Agent control trigger returned non-OK status'
        );
        return;
      }

      consecutiveFailures = 0;
      logger.info({ targetUrl, method, status: response.status, durationMs }, 'Agent control trigger success');
    } catch (error: unknown) {
      consecutiveFailures += 1;
      logger.warn({ err: error, targetUrl, method, consecutiveFailures }, 'Agent control trigger failed');
    } finally {
      inFlight = false;
    }
  };

  void runTrigger();

  setInterval(() => {
    void runTrigger();
  }, intervalMs);

  logger.info(
    { targetUrl, method, intervalMs, timeoutMs },
    'Agent control trigger loop enabled'
  );
}

startHealthServer();
startSelfKeepalivePingLoop();
startAgentControlTriggerLoop();
bootstrap().catch((err: unknown) => {
  logger.fatal({ err }, 'Failed to bootstrap mqtt-worker');
  process.exit(1);
});
