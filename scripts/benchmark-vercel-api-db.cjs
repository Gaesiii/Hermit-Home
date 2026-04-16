#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');
const { MongoClient, ObjectId } = require('mongodb');

const BASE_URL = (process.env.BENCH_BASE_URL || 'https://hermit-home.vercel.app')
  .trim()
  .replace(/\/+$/, '');

const API_DURATION_SECONDS = Number.parseInt(process.env.BENCH_API_DURATION_SECONDS || '8', 10);
const API_CONNECTIONS = Number.parseInt(process.env.BENCH_API_CONNECTIONS || '10', 10);
const API_CONNECTIONS_HEAVY = Number.parseInt(
  process.env.BENCH_API_CONNECTIONS_HEAVY || '5',
  10,
);
const API_REGISTER_REQUESTS = Number.parseInt(process.env.BENCH_REGISTER_REQUESTS || '20', 10);
const API_REGISTER_CONCURRENCY = Number.parseInt(
  process.env.BENCH_REGISTER_CONCURRENCY || '2',
  10,
);
const DB_ITERATIONS = Number.parseInt(process.env.BENCH_DB_ITERATIONS || '80', 10);
const DB_WARMUP = 5;

function nowIso() {
  const utc7 = new Date(Date.now() + 7 * 60 * 60 * 1000);
  return utc7.toISOString().replace('Z', '+07:00');
}

function randomSuffix(size = 8) {
  return crypto.randomBytes(Math.ceil(size / 2)).toString('hex').slice(0, size);
}

function normalizeUserId(value) {
  if (typeof value === 'string') {
    return value;
  }

  if (value && typeof value === 'object') {
    if (typeof value.$oid === 'string') {
      return value.$oid;
    }

    if (typeof value.toString === 'function') {
      const text = value.toString();
      if (text && text !== '[object Object]') {
        return text;
      }
    }
  }

  return null;
}

function percentileFromSorted(sortedDurations, percentileValue) {
  if (sortedDurations.length === 0) return 0;

  const position = Math.ceil((percentileValue / 100) * sortedDurations.length) - 1;
  const safeIndex = Math.max(0, Math.min(sortedDurations.length - 1, position));
  return sortedDurations[safeIndex];
}

function summarizeDurations(durations) {
  const sorted = [...durations].sort((a, b) => a - b);
  const total = durations.reduce((acc, value) => acc + value, 0);
  const average = durations.length > 0 ? total / durations.length : 0;

  return {
    samples: durations.length,
    minMs: sorted.length > 0 ? sorted[0] : 0,
    maxMs: sorted.length > 0 ? sorted[sorted.length - 1] : 0,
    avgMs: average,
    p50Ms: percentileFromSorted(sorted, 50),
    p95Ms: percentileFromSorted(sorted, 95),
    p99Ms: percentileFromSorted(sorted, 99),
  };
}

function round(value, decimals = 2) {
  return Number.parseFloat(value.toFixed(decimals));
}

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function requestJson(url, options = {}) {
  const headers = {
    ...(options.headers || {}),
  };

  const hasBody = options.body !== undefined;
  if (hasBody && !headers['content-type']) {
    headers['content-type'] = 'application/json';
  }

  const start = performance.now();
  const response = await fetch(url, {
    method: options.method || 'GET',
    headers,
    body: hasBody ? JSON.stringify(options.body) : undefined,
  });
  const durationMs = performance.now() - start;
  const responseText = await response.text();
  const json = safeJsonParse(responseText);

  return {
    status: response.status,
    ok: response.ok,
    durationMs,
    headers: Object.fromEntries(response.headers.entries()),
    text: responseText,
    json,
  };
}

async function runTimedLoadCase(testCase) {
  const url = `${BASE_URL}${testCase.path}`;
  const durationSeconds = testCase.durationSeconds ?? API_DURATION_SECONDS;
  const connections = testCase.connections ?? API_CONNECTIONS;
  const durationMs = durationSeconds * 1000;
  const headers = { ...(testCase.headers || {}) };
  if (testCase.body !== undefined) {
    const headerKeys = Object.keys(headers).map((key) => key.toLowerCase());
    if (!headerKeys.includes('content-type')) {
      headers['content-type'] = 'application/json';
    }
  }
  const statusCodeStats = {};
  const durations = [];
  const failedSamples = [];
  let totalRequests = 0;
  let non2xx = 0;
  let errors = 0;
  let timeouts = 0;
  let throughputBytes = 0;
  let stopWorkers = false;

  const stopTimer = setTimeout(() => {
    stopWorkers = true;
  }, durationMs);

  async function workerLoop() {
    while (!stopWorkers) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15_000);

      const start = performance.now();
      try {
        const response = await fetch(url, {
          method: testCase.method,
          headers,
          body:
            testCase.body !== undefined
              ? JSON.stringify(testCase.body)
              : undefined,
          signal: controller.signal,
        });
        const text = await response.text();
        const elapsed = performance.now() - start;

        durations.push(elapsed);
        totalRequests += 1;
        throughputBytes += Buffer.byteLength(text, 'utf8');

        const status = String(response.status);
        if (!statusCodeStats[status]) {
          statusCodeStats[status] = { count: 0 };
        }
        statusCodeStats[status].count += 1;

        if (!response.ok) {
          non2xx += 1;
          if (failedSamples.length < 5) {
            failedSamples.push({
              status: response.status,
              body: safeJsonParse(text) || text,
            });
          }
        }
      } catch (error) {
        const elapsed = performance.now() - start;
        durations.push(elapsed);
        totalRequests += 1;
        errors += 1;

        if (error && typeof error === 'object' && error.name === 'AbortError') {
          timeouts += 1;
        }

        if (failedSamples.length < 5) {
          failedSamples.push({
            status: 'FETCH_ERROR',
            body:
              error && typeof error === 'object' && 'message' in error
                ? String(error.message)
                : String(error),
          });
        }
      } finally {
        clearTimeout(timeout);
      }
    }
  }

  const startedAt = nowIso();
  await Promise.all(
    Array.from({ length: connections }, () => workerLoop()),
  );
  clearTimeout(stopTimer);
  const finishedAt = nowIso();
  const elapsedSeconds =
    (new Date(finishedAt).getTime() - new Date(startedAt).getTime()) / 1000;
  const latency = summarizeDurations(durations);
  const non2xxRate = totalRequests > 0 ? non2xx / totalRequests : 0;

  return {
    kind: 'manual-load',
    name: testCase.name,
    method: testCase.method,
    path: testCase.path,
    url,
    startedAt,
    finishedAt,
    config: {
      durationSeconds,
      connections,
    },
    result: {
      totalRequests,
      requestsPerSecAvg: elapsedSeconds > 0 ? totalRequests / elapsedSeconds : 0,
      throughputBytesPerSecAvg: elapsedSeconds > 0 ? throughputBytes / elapsedSeconds : 0,
      latencyMs: {
        min: latency.minMs,
        avg: latency.avgMs,
        p50: latency.p50Ms,
        p95: latency.p95Ms,
        p99: latency.p99Ms,
        max: latency.maxMs,
      },
      errors,
      timeouts,
      non2xx,
      non2xxRate,
      statusCodeStats,
      failedSamples,
    },
  };
}

async function runDynamicRegisterBenchmark(password) {
  const durations = [];
  const statusCounts = {};
  const failedSamples = [];
  let sequence = 0;

  async function workerRun() {
    while (true) {
      const current = sequence;
      sequence += 1;
      if (current >= API_REGISTER_REQUESTS) {
        return;
      }

      const email = `bench-register-${Date.now()}-${randomSuffix(6)}-${current}@example.com`;
      const response = await requestJson(`${BASE_URL}/api/users/register`, {
        method: 'POST',
        body: { email, password },
      });

      durations.push(response.durationMs);
      statusCounts[response.status] = (statusCounts[response.status] || 0) + 1;

      if (response.status !== 201) {
        failedSamples.push({
          status: response.status,
          body: response.json || response.text,
          email,
        });
      }
    }
  }

  const startedAt = nowIso();
  await Promise.all(
    Array.from({ length: API_REGISTER_CONCURRENCY }, () => workerRun()),
  );
  const finishedAt = nowIso();

  const summary = summarizeDurations(durations);

  return {
    kind: 'manual',
    name: 'users_register_post_dynamic',
    method: 'POST',
    path: '/api/users/register',
    url: `${BASE_URL}/api/users/register`,
    startedAt,
    finishedAt,
    config: {
      requests: API_REGISTER_REQUESTS,
      concurrency: API_REGISTER_CONCURRENCY,
    },
    result: {
      totalRequests: durations.length,
      requestsPerSecAvg:
        durations.length > 0
          ? durations.length /
            ((new Date(finishedAt).getTime() - new Date(startedAt).getTime()) / 1000)
          : 0,
      throughputBytesPerSecAvg: 0,
      latencyMs: {
        min: summary.minMs,
        avg: summary.avgMs,
        p50: summary.p50Ms,
        p95: summary.p95Ms,
        p99: summary.p99Ms,
        max: summary.maxMs,
      },
      errors: 0,
      timeouts: 0,
      non2xx: durations.length - (statusCounts[201] || 0),
      non2xxRate:
        durations.length > 0
          ? (durations.length - (statusCounts[201] || 0)) / durations.length
          : 0,
      statusCodeStats: Object.fromEntries(
        Object.entries(statusCounts).map(([status, count]) => [
          status,
          { count },
        ]),
      ),
      failedSamples,
    },
  };
}

async function createBenchmarkUser() {
  const password = `Bench!${randomSuffix(10)}aA1`;
  let attempt = 0;
  let email = '';
  let registered = null;

  while (attempt < 6) {
    email = `bench-api-${Date.now()}-${randomSuffix(6)}@example.com`;
    registered = await requestJson(`${BASE_URL}/api/users/register`, {
      method: 'POST',
      body: { email, password },
    });

    if (registered.status === 201) {
      break;
    }

    attempt += 1;
  }

  if (!registered || registered.status !== 201) {
    throw new Error(
      `Failed to create benchmark user. Last status: ${registered?.status}, body: ${registered?.text}`,
    );
  }

  const login = await requestJson(`${BASE_URL}/api/users/login`, {
    method: 'POST',
    body: { email, password },
  });

  if (login.status !== 200 || !login.json || typeof login.json.token !== 'string') {
    throw new Error(
      `Failed to login benchmark user. Status: ${login.status}, body: ${login.text}`,
    );
  }

  const userId = normalizeUserId(login.json.user?._id);
  if (!userId) {
    throw new Error(`Unable to read userId from login response: ${login.text}`);
  }

  return {
    email,
    password,
    token: login.json.token,
    userId,
    registerResponse: registered,
    loginResponse: login,
  };
}

function summarizeExplain(explain) {
  const executionStats = explain.executionStats || {};
  const queryPlanner = explain.queryPlanner || {};

  const stageNames = [];
  const indexNames = [];

  function walk(node) {
    if (!node || typeof node !== 'object') return;

    if (typeof node.stage === 'string') {
      stageNames.push(node.stage);
    }

    if (typeof node.indexName === 'string') {
      indexNames.push(node.indexName);
    }

    for (const value of Object.values(node)) {
      if (Array.isArray(value)) {
        for (const child of value) {
          walk(child);
        }
      } else if (value && typeof value === 'object') {
        walk(value);
      }
    }
  }

  walk(queryPlanner.winningPlan || queryPlanner);

  return {
    executionTimeMillis: executionStats.executionTimeMillis || 0,
    nReturned: executionStats.nReturned || 0,
    totalKeysExamined: executionStats.totalKeysExamined || 0,
    totalDocsExamined: executionStats.totalDocsExamined || 0,
    stages: [...new Set(stageNames)],
    indexes: [...new Set(indexNames)],
  };
}

async function runDbOperationBenchmark(name, iterations, operationFn) {
  for (let index = 0; index < DB_WARMUP; index += 1) {
    await operationFn();
  }

  const durations = [];
  for (let index = 0; index < iterations; index += 1) {
    const start = performance.now();
    await operationFn();
    durations.push(performance.now() - start);
  }

  const summary = summarizeDurations(durations);
  return {
    name,
    iterations,
    latencyMs: {
      min: summary.minMs,
      avg: summary.avgMs,
      p50: summary.p50Ms,
      p95: summary.p95Ms,
      p99: summary.p99Ms,
      max: summary.maxMs,
    },
  };
}

async function runDbBenchmarks(context) {
  const mongoUri = process.env.MONGODB_URI;
  const mongoDbName = process.env.MONGODB_DB_NAME || 'hermit-home';

  if (!mongoUri) {
    return {
      skipped: true,
      reason: 'MONGODB_URI is missing from environment.',
      operations: [],
      explain: {},
      indexes: {},
    };
  }

  const client = new MongoClient(mongoUri, { maxPoolSize: 20 });
  const benchmarkTag = `bench-${Date.now()}-${randomSuffix(6)}`;
  const telemetryLuxBase = 900000;
  const stateSeedStart = new Date('2099-01-01T00:00:00.000Z');
  const stateSeedEnd = new Date('2099-01-02T00:00:00.000Z');
  const resetUserAgentMarker = `benchmark-script-${benchmarkTag}`;
  const benchmarkUserObjectId = new ObjectId(context.userId);
  const insertedUserIds = [];
  const insertedDeviceStateIds = [];
  const insertedResetTokenIds = [];
  let db = null;

  try {
    await client.connect();
    db = client.db(mongoDbName);

    const users = db.collection('users');
    const devices = db.collection('devices');
    const telemetry = db.collection('telemetry');
    const deviceStates = db.collection('device_states');
    const passwordResetTokens = db.collection('password_reset_tokens');

    await devices.updateOne(
      { deviceId: context.userId },
      {
        $setOnInsert: {
          deviceId: context.userId,
          mode: 'AUTO',
          user_override: false,
          relays: { fan: false, heater: false, mist: false, light: false },
          lastTelemetryAt: new Date(),
          lastCommandAt: new Date(),
          updatedAt: new Date(),
        },
      },
      { upsert: true },
    );

    const telemetrySeedDocs = [];
    const seedNow = Date.now();
    for (let index = 0; index < 250; index += 1) {
      telemetrySeedDocs.push({
        userId: context.userId,
        timestamp: new Date(seedNow - index * 30_000),
        temperature: 27 + ((index % 5) * 0.1),
        humidity: 72 + ((index % 7) * 0.2),
        lux: telemetryLuxBase + index,
        sensor_fault: false,
        user_override: false,
        relays: { fan: false, heater: false, mist: false, light: false },
      });
    }
    if (telemetrySeedDocs.length > 0) {
      await telemetry.insertMany(telemetrySeedDocs, { ordered: false });
    }

    const stateSeedDocs = [];
    for (let index = 0; index < 180; index += 1) {
      stateSeedDocs.push({
        deviceId: context.userId,
        userId: context.userId,
        state: { fan: index % 2 === 0 },
        source: 'user',
        createdAt: new Date(stateSeedStart.getTime() + index * 10_000),
      });
    }
    if (stateSeedDocs.length > 0) {
      await deviceStates.insertMany(stateSeedDocs, { ordered: false });
    }

    const existingResetTokenRaw = `existing-reset-${benchmarkTag}`;
    const existingResetTokenHash = crypto
      .createHash('sha256')
      .update(existingResetTokenRaw)
      .digest('hex');
    const resetTokenInsert = await passwordResetTokens.insertOne({
      userId: benchmarkUserObjectId,
      email: context.email,
      tokenHash: existingResetTokenHash,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      usedAt: null,
      requestedIp: null,
      requestedUserAgent: resetUserAgentMarker,
    });
    insertedResetTokenIds.push(resetTokenInsert.insertedId);

    let insertCounter = 0;

    const operations = [];
    operations.push(
      await runDbOperationBenchmark('users_findOne_email_existing', DB_ITERATIONS, async () => {
        await users.findOne({ email: context.email });
      }),
    );

    operations.push(
      await runDbOperationBenchmark('users_findOne_email_missing', DB_ITERATIONS, async () => {
        await users.findOne({ email: `missing-${benchmarkTag}@example.com` });
      }),
    );

    operations.push(
      await runDbOperationBenchmark('users_insertOne_unique', DB_ITERATIONS, async () => {
        const result = await users.insertOne({
          email: `bench-write-${benchmarkTag}-${insertCounter}@example.com`,
          passwordHash: 'benchmark-only',
          createdAt: new Date(),
          updatedAt: new Date(),
        });
        insertedUserIds.push(result.insertedId);
        insertCounter += 1;
      }),
    );

    operations.push(
      await runDbOperationBenchmark('devices_findOne_deviceId', DB_ITERATIONS, async () => {
        await devices.findOne({ deviceId: context.userId });
      }),
    );

    operations.push(
      await runDbOperationBenchmark('devices_findOneAndUpdate', DB_ITERATIONS, async () => {
        await devices.findOneAndUpdate(
          { deviceId: context.userId },
          { $set: { updatedAt: new Date() } },
          { upsert: true, returnDocument: 'after' },
        );
      }),
    );

    operations.push(
      await runDbOperationBenchmark('telemetry_find_latest', DB_ITERATIONS, async () => {
        await telemetry
          .find({ userId: context.userId })
          .sort({ timestamp: -1 })
          .limit(1)
          .toArray();
      }),
    );

    operations.push(
      await runDbOperationBenchmark('telemetry_find_limit_30', DB_ITERATIONS, async () => {
        await telemetry
          .find({ userId: context.userId })
          .sort({ timestamp: -1 })
          .limit(30)
          .toArray();
      }),
    );

    operations.push(
      await runDbOperationBenchmark('device_states_find_recent_20', DB_ITERATIONS, async () => {
        await deviceStates
          .find({ deviceId: context.userId, userId: context.userId })
          .sort({ createdAt: -1 })
          .limit(20)
          .toArray();
      }),
    );

    operations.push(
      await runDbOperationBenchmark('device_states_insertOne', DB_ITERATIONS, async () => {
        const result = await deviceStates.insertOne({
          deviceId: context.userId,
          userId: context.userId,
          state: { fan: true, light: false },
          source: 'user',
          createdAt: new Date(),
        });
        insertedDeviceStateIds.push(result.insertedId);
      }),
    );

    operations.push(
      await runDbOperationBenchmark(
        'password_reset_findOne_tokenHash_existing',
        DB_ITERATIONS,
        async () => {
          await passwordResetTokens.findOne({ tokenHash: existingResetTokenHash });
        },
      ),
    );

    operations.push(
      await runDbOperationBenchmark(
        'password_reset_findOneAndUpdate_no_match',
        DB_ITERATIONS,
        async () => {
          await passwordResetTokens.findOneAndUpdate(
            {
              tokenHash: `missing-${benchmarkTag}`,
              usedAt: null,
              expiresAt: { $gt: new Date() },
            },
            {
              $set: { usedAt: new Date() },
            },
            {
              returnDocument: 'before',
            },
          );
        },
      ),
    );

    const explain = {
      users_findOne_email: summarizeExplain(
        await users.find({ email: context.email }).limit(1).explain('executionStats'),
      ),
      telemetry_find_limit_30: summarizeExplain(
        await telemetry
          .find({ userId: context.userId })
          .sort({ timestamp: -1 })
          .limit(30)
          .explain('executionStats'),
      ),
      device_states_find_recent_20: summarizeExplain(
        await deviceStates
          .find({ deviceId: context.userId, userId: context.userId })
          .sort({ createdAt: -1 })
          .limit(20)
          .explain('executionStats'),
      ),
      password_reset_findOne_tokenHash: summarizeExplain(
        await passwordResetTokens
          .find({ tokenHash: existingResetTokenHash })
          .limit(1)
          .explain('executionStats'),
      ),
    };

    const indexes = {
      users: await users.indexes(),
      devices: await devices.indexes(),
      telemetry: await telemetry.indexes(),
      device_states: await deviceStates.indexes(),
      password_reset_tokens: await passwordResetTokens.indexes(),
    };

    return {
      skipped: false,
      reason: null,
      benchmarkTag,
      operations,
      explain,
      indexes,
    };
  } finally {
    if (db) {
      const users = db.collection('users');
      const telemetry = db.collection('telemetry');
      const deviceStates = db.collection('device_states');
      const passwordResetTokens = db.collection('password_reset_tokens');

      if (insertedUserIds.length > 0) {
        await users.deleteMany({ _id: { $in: insertedUserIds } });
      }

      await users.deleteMany({ email: context.email });
      await telemetry.deleteMany({
        userId: context.userId,
        lux: { $gte: telemetryLuxBase, $lt: telemetryLuxBase + 1000 },
      });

      if (insertedDeviceStateIds.length > 0) {
        await deviceStates.deleteMany({ _id: { $in: insertedDeviceStateIds } });
      }
      await deviceStates.deleteMany({
        deviceId: context.userId,
        userId: context.userId,
        createdAt: { $gte: stateSeedStart, $lt: stateSeedEnd },
      });

      if (insertedResetTokenIds.length > 0) {
        await passwordResetTokens.deleteMany({ _id: { $in: insertedResetTokenIds } });
      }
      await passwordResetTokens.deleteMany({
        requestedUserAgent: resetUserAgentMarker,
      });
    }

    await client.close();
  }
}

function detectApiBottlenecks(apiResults) {
  const findings = [];

  for (const item of apiResults) {
    const p95 = item.result.latencyMs.p95;
    const errorRate = item.result.non2xxRate;
    const reqPerSec = item.result.requestsPerSecAvg;

    if (p95 > 1200) {
      findings.push(
        `[API] ${item.name} p95=${round(p95)}ms (>1200ms)`,
      );
    }

    if (errorRate > 0.05) {
      findings.push(
        `[API] ${item.name} non2xx=${round(errorRate * 100)}% (>5%)`,
      );
    }

    if (reqPerSec < 2 && (item.config.connections || 0) >= 5) {
      findings.push(
        `[API] ${item.name} throughput=${round(reqPerSec)} req/s (<2 req/s)`,
      );
    }
  }

  return findings;
}

function detectDbBottlenecks(dbResults) {
  const findings = [];

  if (!dbResults || dbResults.skipped) {
    return findings;
  }

  for (const operation of dbResults.operations) {
    const p95 = operation.latencyMs.p95;
    if (p95 > 80) {
      findings.push(`[DB] ${operation.name} p95=${round(p95)}ms (>80ms)`);
    }
  }

  for (const [queryName, explain] of Object.entries(dbResults.explain || {})) {
    const docs = explain.totalDocsExamined || 0;
    const returned = explain.nReturned || 1;
    const hasCollectionScan = (explain.stages || []).includes('COLLSCAN');
    const ratio = docs / Math.max(1, returned);

    if (hasCollectionScan) {
      findings.push(`[DB] ${queryName} uses COLLSCAN`);
    }

    if (ratio > 100) {
      findings.push(
        `[DB] ${queryName} docsExamined/nReturned=${round(ratio)} (high scan ratio)`,
      );
    }
  }

  return findings;
}

function toMarkdown(report) {
  const lines = [];
  lines.push(`# Vercel API + DB Benchmark`);
  lines.push('');
  lines.push(`- Generated at: ${report.generatedAt}`);
  lines.push(`- Base URL: ${report.baseUrl}`);
  lines.push(`- Benchmark user/deviceId: ${report.benchmarkContext.userId}`);
  lines.push('');
  lines.push(`## API Runtime`);
  lines.push('');
  lines.push(
    '| Name | Method | Path | p50 (ms) | p95 (ms) | p99 (ms) | Avg (ms) | Req/s | non2xx | Status |',
  );
  lines.push('|---|---|---|---:|---:|---:|---:|---:|---:|---|');
  for (const item of report.apiResults) {
    const statuses = Object.entries(item.result.statusCodeStats || {})
      .map(([status, value]) => `${status}:${value.count}`)
      .join(', ');
    lines.push(
      `| ${item.name} | ${item.method} | ${item.path} | ${round(item.result.latencyMs.p50)} | ${round(item.result.latencyMs.p95)} | ${round(item.result.latencyMs.p99)} | ${round(item.result.latencyMs.avg)} | ${round(item.result.requestsPerSecAvg)} | ${round(item.result.non2xxRate * 100)}% | ${statuses || '-'} |`,
    );
  }
  lines.push('');

  lines.push(`## DB Runtime`);
  lines.push('');
  if (report.dbResults.skipped) {
    lines.push(`- Skipped: ${report.dbResults.reason}`);
  } else {
    lines.push('| Operation | Iterations | p50 (ms) | p95 (ms) | p99 (ms) | Avg (ms) |');
    lines.push('|---|---:|---:|---:|---:|---:|');
    for (const operation of report.dbResults.operations) {
      lines.push(
        `| ${operation.name} | ${operation.iterations} | ${round(operation.latencyMs.p50)} | ${round(operation.latencyMs.p95)} | ${round(operation.latencyMs.p99)} | ${round(operation.latencyMs.avg)} |`,
      );
    }

    lines.push('');
    lines.push('### Query Explain (executionStats)');
    lines.push('');
    lines.push('| Query | executionTimeMillis | docsExamined | keysExamined | nReturned | stages | indexes |');
    lines.push('|---|---:|---:|---:|---:|---|---|');
    for (const [queryName, explain] of Object.entries(report.dbResults.explain || {})) {
      lines.push(
        `| ${queryName} | ${explain.executionTimeMillis} | ${explain.totalDocsExamined} | ${explain.totalKeysExamined} | ${explain.nReturned} | ${(explain.stages || []).join(', ') || '-'} | ${(explain.indexes || []).join(', ') || '-'} |`,
      );
    }
  }
  lines.push('');

  lines.push('## Bottleneck Findings');
  lines.push('');
  if (report.bottlenecks.length === 0) {
    lines.push('- No obvious bottleneck detected with current test profile.');
  } else {
    for (const finding of report.bottlenecks) {
      lines.push(`- ${finding}`);
    }
  }
  lines.push('');

  return lines.join('\n');
}

async function run() {
  const startedAt = nowIso();
  console.error(`[benchmark] Base URL: ${BASE_URL}`);
  console.error('[benchmark] Creating benchmark user and auth token...');
  const benchmarkContext = await createBenchmarkUser();

  const authHeaders = {
    Authorization: `Bearer ${benchmarkContext.token}`,
  };

  const apiCases = [
    { name: 'devices_index_get', method: 'GET', path: '/api/devices' },
    {
      name: 'devices_schedules_get',
      method: 'GET',
      path: '/api/devices/schedules',
    },
    {
      name: 'device_get',
      method: 'GET',
      path: `/api/devices/${benchmarkContext.userId}`,
      headers: authHeaders,
    },
    {
      name: 'device_status_get',
      method: 'GET',
      path: `/api/devices/${benchmarkContext.userId}/status`,
      headers: authHeaders,
    },
    {
      name: 'device_telemetry_get',
      method: 'GET',
      path: `/api/devices/${benchmarkContext.userId}/telemetry?limit=30`,
      headers: authHeaders,
    },
    {
      name: 'device_control_get',
      method: 'GET',
      path: `/api/devices/${benchmarkContext.userId}/control?limit=20`,
      headers: authHeaders,
    },
    {
      name: 'device_patch',
      method: 'PATCH',
      path: `/api/devices/${benchmarkContext.userId}`,
      headers: authHeaders,
      body: {
        mode: 'AUTO',
        user_override: false,
        relays: {
          fan: false,
          heater: false,
          mist: false,
          light: false,
        },
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'device_override_post',
      method: 'POST',
      path: `/api/devices/${benchmarkContext.userId}/override`,
      headers: authHeaders,
      body: {
        user_override: true,
        devices: {
          fan: false,
          heater: false,
          mist: true,
          light: true,
        },
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'device_control_post',
      method: 'POST',
      path: `/api/devices/${benchmarkContext.userId}/control`,
      headers: authHeaders,
      body: {
        fan: true,
        light: false,
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'users_login_post',
      method: 'POST',
      path: '/api/users/login',
      body: {
        email: benchmarkContext.email,
        password: benchmarkContext.password,
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'users_forgot_password_post',
      method: 'POST',
      path: '/api/users/forgot-password',
      body: {
        email: `missing-${Date.now()}-${randomSuffix(5)}@example.com`,
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'users_reset_password_invalid_post',
      method: 'POST',
      path: '/api/users/reset-password',
      body: {
        token: 'x'.repeat(32),
        password: 'AnyPass123!',
      },
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'reset_password_link_get',
      method: 'GET',
      path: `/reset-password?token=${'x'.repeat(32)}`,
      connections: API_CONNECTIONS_HEAVY,
    },
    {
      name: 'auth_placeholder_get',
      method: 'GET',
      path: '/api/auth/session',
      connections: API_CONNECTIONS_HEAVY,
    },
  ];

  const apiResults = [];
  for (const apiCase of apiCases) {
    console.error(
      `[benchmark] API case: ${apiCase.name} (${apiCase.method} ${apiCase.path})`,
    );
    apiResults.push(await runTimedLoadCase(apiCase));
  }
  console.error('[benchmark] API case: users_register_post_dynamic (manual)');
  apiResults.push(await runDynamicRegisterBenchmark(benchmarkContext.password));

  console.error('[benchmark] Running direct MongoDB query benchmarks...');
  const dbResults = await runDbBenchmarks({
    email: benchmarkContext.email,
    userId: benchmarkContext.userId,
  });

  const bottlenecks = [
    ...detectApiBottlenecks(apiResults),
    ...detectDbBottlenecks(dbResults),
  ];

  const report = {
    generatedAt: nowIso(),
    startedAt,
    finishedAt: nowIso(),
    baseUrl: BASE_URL,
    benchmarkContext: {
      email: benchmarkContext.email,
      userId: benchmarkContext.userId,
    },
    config: {
      api: {
        durationSeconds: API_DURATION_SECONDS,
        connectionsDefault: API_CONNECTIONS,
        connectionsHeavy: API_CONNECTIONS_HEAVY,
        dynamicRegisterRequests: API_REGISTER_REQUESTS,
        dynamicRegisterConcurrency: API_REGISTER_CONCURRENCY,
      },
      db: {
        iterationsPerOperation: DB_ITERATIONS,
        warmupRounds: DB_WARMUP,
      },
    },
    apiResults,
    dbResults,
    bottlenecks,
  };

  const outDir = path.join(process.cwd(), 'benchmarks');
  fs.mkdirSync(outDir, { recursive: true });
  const stamp = nowIso().replace(/[+:.]/g, '-');
  const jsonPath = path.join(outDir, `vercel-runtime-benchmark-${stamp}.json`);
  const markdownPath = path.join(outDir, `vercel-runtime-benchmark-${stamp}.md`);

  fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2), 'utf8');
  fs.writeFileSync(markdownPath, toMarkdown(report), 'utf8');

  const apiSortedByP95 = [...apiResults].sort(
    (left, right) => right.result.latencyMs.p95 - left.result.latencyMs.p95,
  );
  const dbSortedByP95 = dbResults.skipped
    ? []
    : [...dbResults.operations].sort(
        (left, right) => right.latencyMs.p95 - left.latencyMs.p95,
      );

  const summary = {
    outputJson: jsonPath,
    outputMarkdown: markdownPath,
    topApiP95: apiSortedByP95.slice(0, 5).map((item) => ({
      name: item.name,
      p95Ms: round(item.result.latencyMs.p95),
      avgReqPerSec: round(item.result.requestsPerSecAvg),
      non2xxRatePct: round(item.result.non2xxRate * 100),
    })),
    topDbP95: dbSortedByP95.slice(0, 5).map((item) => ({
      name: item.name,
      p95Ms: round(item.latencyMs.p95),
      avgMs: round(item.latencyMs.avg),
    })),
    bottlenecks,
  };

  console.log(JSON.stringify(summary, null, 2));
}

run().catch((error) => {
  console.error('[benchmark-vercel-api-db] Fatal error:', error);
  process.exitCode = 1;
});
