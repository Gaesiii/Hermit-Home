#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require('fs');
const path = require('path');
const mqtt = require('mqtt');
const dotenv = require('dotenv');

const rootDir = path.resolve(__dirname, '..');

function loadEnvIfExists(relativePath) {
  const fullPath = path.join(rootDir, relativePath);
  if (fs.existsSync(fullPath)) {
    dotenv.config({ path: fullPath });
  }
}

function readIntArg(name, fallback) {
  const prefix = `--${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix));
  if (!raw) return fallback;
  const value = Number.parseInt(raw.slice(prefix.length), 10);
  if (!Number.isInteger(value)) {
    throw new Error(`Invalid --${name} value: ${raw.slice(prefix.length)}`);
  }
  return value;
}

function readStringArg(name) {
  const prefix = `--${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix));
  return raw ? raw.slice(prefix.length) : null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function nowIso() {
  const utc7 = new Date(Date.now() + 7 * 60 * 60 * 1000);
  return utc7.toISOString().replace('Z', '+07:00');
}

function parseConfirmPayload(buffer) {
  try {
    const data = JSON.parse(buffer.toString('utf8'));
    if (!data || typeof data !== 'object') return null;
    return data;
  } catch {
    return null;
  }
}

async function main() {
  loadEnvIfExists('services/ai-agent/.env');
  loadEnvIfExists('services/api/.env');

  const intervalSeconds = readIntArg('interval', 10);
  const cycles = readIntArg('cycles', 0);
  const ackTimeoutMs = readIntArg('ack-timeout-ms', 5000);
  const deviceId = readStringArg('device-id') || process.env.DEVICE_ID || '';

  const host = process.env.MQTT_BROKER || '';
  const port = Number.parseInt(process.env.MQTT_PORT || '8883', 10);
  const username = process.env.MQTT_USER || '';
  const password = process.env.MQTT_PASS || '';
  const caCert = process.env.MQTT_CA_CERT
    ? process.env.MQTT_CA_CERT.replace(/\\n/g, '\n')
    : undefined;

  if (intervalSeconds < 1) {
    throw new Error('--interval must be >= 1.');
  }
  if (cycles < 0) {
    throw new Error('--cycles must be >= 0.');
  }
  if (!deviceId) {
    throw new Error('Missing DEVICE_ID. Set it in services/ai-agent/.env or use --device-id=');
  }
  if (!host || !username || !password) {
    throw new Error('Missing MQTT config. Check MQTT_BROKER, MQTT_USER, MQTT_PASS.');
  }

  const commandTopic = `terrarium/commands/${deviceId}`;
  const confirmTopic = `terrarium/confirm/${deviceId}`;

  console.log(
    `[${nowIso()}] Starting light toggle stability test | device=${deviceId} | interval=${intervalSeconds}s | cycles=${
      cycles === 0 ? 'infinite' : cycles
    }`
  );

  const clientOptions = {
    username,
    password,
    clientId: `light-stability-${Math.random().toString(16).slice(2, 10)}`,
    reconnectPeriod: 2000,
    connectTimeout: 5000,
    rejectUnauthorized: true,
  };

  if (caCert) {
    clientOptions.ca = caCert;
  }

  const client = mqtt.connect(`mqtts://${host}:${port}`, clientOptions);

  let pendingAck = null;
  let cancelled = false;

  const closeClient = () =>
    new Promise((resolve) => {
      client.end(false, resolve);
    });

  process.on('SIGINT', async () => {
    cancelled = true;
    console.log(`[${nowIso()}] Received SIGINT. Closing MQTT client...`);
    await closeClient();
    process.exit(0);
  });

  client.on('message', (topic, payload) => {
    if (topic !== confirmTopic) return;
    const data = parseConfirmPayload(payload);
    if (!data) return;

    if (data.status === 'offline') {
      console.log(`[${nowIso()}] Confirm status: device offline`);
      return;
    }

    if (data.event === 'override_ack' && data.device === 'light' && typeof data.state === 'boolean') {
      console.log(`[${nowIso()}] ACK light=${data.state ? 'ON' : 'OFF'}`);

      if (pendingAck && pendingAck.expected === data.state) {
        pendingAck.resolve(true);
        pendingAck = null;
      }
    }
  });

  await new Promise((resolve, reject) => {
    client.once('connect', resolve);
    client.once('error', reject);
  });

  await new Promise((resolve, reject) => {
    client.subscribe(confirmTopic, { qos: 1 }, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

  const publishCommand = (state) =>
    new Promise((resolve, reject) => {
      const payload = JSON.stringify({
        user_override: true,
        devices: {
          light: state,
        },
      });
      client.publish(commandTopic, payload, { qos: 1 }, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });

  const waitForAck = (expectedState) =>
    new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (pendingAck && pendingAck.expected === expectedState) {
          pendingAck = null;
          resolve(false);
        }
      }, ackTimeoutMs);

      pendingAck = {
        expected: expectedState,
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
      };
    });

  let lightOn = false;
  let sent = 0;

  try {
    while (!cancelled) {
      lightOn = !lightOn;
      sent += 1;

      await publishCommand(lightOn);
      console.log(`[${nowIso()}] #${sent} SENT light=${lightOn ? 'ON' : 'OFF'}`);

      const acked = await waitForAck(lightOn);
      console.log(`[${nowIso()}] #${sent} RESULT ${acked ? 'ACK_OK' : 'ACK_TIMEOUT'}`);

      if (cycles > 0 && sent >= cycles) {
        break;
      }

      await sleep(intervalSeconds * 1000);
    }
  } finally {
    await closeClient();
    console.log(`[${nowIso()}] Test finished. Total commands sent: ${sent}`);
  }
}

main().catch((error) => {
  console.error(`[${nowIso()}] Test failed: ${error.message}`);
  process.exit(1);
});
