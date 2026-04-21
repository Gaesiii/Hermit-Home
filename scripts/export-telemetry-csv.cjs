#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { MongoClient } = require('mongodb');
const dotenv = require('dotenv');

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;

function loadEnvFiles() {
  const cwd = process.cwd();
  const candidates = ['.env', '.env.local', '.env.vercel'];

  for (const filename of candidates) {
    const fullPath = path.join(cwd, filename);
    if (fs.existsSync(fullPath)) {
      dotenv.config({ path: fullPath, override: false });
    }
  }
}

function parseArgs(argv) {
  const options = {
    deviceId: null,
    out: null,
    limit: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];

    if (arg === '--device-id') {
      if (!value) {
        throw new Error('Missing value for --device-id');
      }
      options.deviceId = value.trim();
      index += 1;
      continue;
    }

    if (arg === '--out') {
      if (!value) {
        throw new Error('Missing value for --out');
      }
      options.out = value.trim();
      index += 1;
      continue;
    }

    if (arg === '--limit') {
      if (!value) {
        throw new Error('Missing value for --limit');
      }
      const parsed = Number.parseInt(value, 10);
      if (!Number.isFinite(parsed) || parsed < 1) {
        throw new Error('--limit must be a positive integer.');
      }
      options.limit = parsed;
      index += 1;
      continue;
    }

    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }

    throw new Error(`Unknown argument: ${arg}`);
  }

  if (options.deviceId && !OBJECT_ID_REGEX.test(options.deviceId)) {
    throw new Error('`--device-id` must be a 24-character hex string.');
  }

  return options;
}

function printUsage() {
  console.log(
    [
      'Usage:',
      '  node scripts/export-telemetry-csv.cjs [--device-id <id>] [--limit <n>] [--out <path>]',
      '',
      'Examples:',
      '  node scripts/export-telemetry-csv.cjs',
      '  node scripts/export-telemetry-csv.cjs --device-id 67f333eebf6bd60f2ac1536a',
      '  node scripts/export-telemetry-csv.cjs --limit 500 --out exports/telemetry-latest.csv',
    ].join('\n')
  );
}

function toIso(value) {
  if (!value) {
    return '';
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toISOString();
}

function csvEscape(value) {
  if (value === null || value === undefined) {
    return '';
  }

  const source = String(value);
  const escaped = source.replace(/"/g, '""');
  return /[",\n\r]/.test(escaped) ? `"${escaped}"` : escaped;
}

function buildDefaultOutputPath(deviceId) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const scope = deviceId || 'all-devices';
  return path.resolve(process.cwd(), 'exports', `telemetry-${scope}-${stamp}.csv`);
}

async function run() {
  loadEnvFiles();
  const options = parseArgs(process.argv.slice(2));

  const uri = process.env.MONGODB_URI || '';
  const dbName = process.env.MONGODB_DB_NAME || 'hermit-home';
  if (!uri) {
    throw new Error('MONGODB_URI is required. Add it to your environment or .env file.');
  }

  const outPath = options.out
    ? path.resolve(process.cwd(), options.out)
    : buildDefaultOutputPath(options.deviceId);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  const client = new MongoClient(uri, {
    maxPoolSize: 5,
    minPoolSize: 0,
    serverSelectionTimeoutMS: 10_000,
  });

  await client.connect();

  try {
    const collection = client.db(dbName).collection('telemetry');
    const filter = options.deviceId ? { userId: options.deviceId } : {};

    let cursor = collection.find(filter).sort({ timestamp: 1, _id: 1 });
    if (options.limit) {
      cursor = cursor.limit(options.limit);
    }

    const headers = [
      'id',
      'userId',
      'timestamp',
      'temperature',
      'humidity',
      'lux',
      'sensor_fault',
      'user_override',
      'relay_heater',
      'relay_mist',
      'relay_fan',
      'relay_light',
    ];

    const stream = fs.createWriteStream(outPath, { encoding: 'utf8' });
    stream.write(`${headers.join(',')}\n`);

    let count = 0;

    for await (const doc of cursor) {
      const row = [
        doc._id?.toString() || '',
        doc.userId || '',
        toIso(doc.timestamp),
        doc.temperature,
        doc.humidity,
        doc.lux,
        doc.sensor_fault,
        doc.user_override,
        doc.relays?.heater,
        doc.relays?.mist,
        doc.relays?.fan,
        doc.relays?.light,
      ];

      stream.write(`${row.map(csvEscape).join(',')}\n`);
      count += 1;
    }

    await new Promise((resolve, reject) => {
      stream.on('error', reject);
      stream.end(resolve);
    });

    console.log(`Exported ${count} telemetry rows to: ${outPath}`);
  } finally {
    await client.close();
  }
}

run().catch((error) => {
  console.error('Telemetry export failed:', error instanceof Error ? error.message : error);
  process.exit(1);
});
