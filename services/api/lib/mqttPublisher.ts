import mqtt, { IClientOptions } from 'mqtt';
import { CommandPayload } from '@smart-terrarium/shared-types';
import dotenv from 'dotenv';
import { sanitizeCommandPayload } from './mistSafety';

dotenv.config();

function buildMqttOptions(
  username: string,
  password: string,
  caCert: string | undefined
): IClientOptions {
  const options: IClientOptions = {
    username,
    password,
    clientId: `api-publisher-${Math.random().toString(16).slice(2, 8)}`,
    rejectUnauthorized: true,
    reconnectPeriod: 0,
    connectTimeout: 5000,
  };

  if (caCert) {
    options.ca = caCert;
  }

  return options;
}

export async function publishCommand(deviceId: string, payload: CommandPayload): Promise<void> {
  const host = process.env.MQTT_BROKER || '';
  const port = process.env.MQTT_PORT || '8883';
  const username = process.env.MQTT_USER || '';
  const password = process.env.MQTT_PASS || '';
  const caCert = process.env.MQTT_CA_CERT?.replace(/\\n/g, '\n');

  if (!host || !username || !password) {
    throw new Error('Missing MQTT configuration. Check MQTT_BROKER, MQTT_USER, and MQTT_PASS.');
  }

  const client = mqtt.connect(
    `mqtts://${host}:${port}`,
    buildMqttOptions(username, password, caCert)
  );

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      client.end(true);
      reject(new Error('MQTT publish timeout'));
    }, 5000);

    client.on('connect', () => {
      const topic = `terrarium/commands/${deviceId}`;
      const message = JSON.stringify(sanitizeCommandPayload(payload));

      client.publish(topic, message, { qos: 1 }, (err) => {
        clearTimeout(timeout);
        client.end();
        if (err) {
          reject(err);
          return;
        }
        resolve();
      });
    });

    client.on('error', (err) => {
      clearTimeout(timeout);
      client.end(true);
      reject(err);
    });
  });
}
