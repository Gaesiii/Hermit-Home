#!/usr/bin/env node
/* eslint-disable no-console */

const crypto = require('crypto');
const { performance } = require('perf_hooks');

const BASE_URL = (process.env.BENCH_BASE_URL || 'https://hermit-home.vercel.app')
  .trim()
  .replace(/\/+$/, '');
const DEVICE_ID = (process.env.DEVICE_ID || '').trim();
const SERVICE_API_KEY = (process.env.SERVICE_API_KEY || '').trim();

const REQUEST_TIMEOUT_MS = Number.parseInt(process.env.FLOW_TIMEOUT_MS || '15000', 10);
const STABILITY_ROUNDS = Number.parseInt(process.env.FLOW_STABILITY_ROUNDS || '20', 10);
const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

function nowUtc7Iso() {
  const utc7 = new Date(Date.now() + 7 * 60 * 60 * 1000);
  return utc7.toISOString().replace('Z', '+07:00');
}

function toUtc7Iso(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  const utc7 = new Date(date.getTime() + 7 * 60 * 60 * 1000);
  return utc7.toISOString().replace('Z', '+07:00');
}

function convertTimesToUtc7(value) {
  if (value === null || value === undefined) {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(convertTimesToUtc7);
  }

  if (value instanceof Date) {
    return toUtc7Iso(value);
  }

  if (typeof value === 'object') {
    const output = {};
    for (const [key, nested] of Object.entries(value)) {
      output[key] = convertTimesToUtc7(nested);
    }
    return output;
  }

  if (typeof value === 'string' && ISO_UTC_RE.test(value)) {
    return toUtc7Iso(value);
  }

  return value;
}

function percentileFromSorted(sorted, p) {
  if (sorted.length === 0) return 0;
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(sorted.length - 1, index))];
}

function summarizeDurations(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const avg = values.length > 0 ? values.reduce((a, b) => a + b, 0) / values.length : 0;
  return {
    min: sorted[0] || 0,
    avg,
    p50: percentileFromSorted(sorted, 50),
    p95: percentileFromSorted(sorted, 95),
    p99: percentileFromSorted(sorted, 99),
    max: sorted[sorted.length - 1] || 0,
  };
}

function safeJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function request(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const url = `${BASE_URL}${path}`;
  const headers = { ...(options.headers || {}) };

  if (options.body && !Object.keys(headers).some((key) => key.toLowerCase() === 'content-type')) {
    headers['content-type'] = 'application/json';
  }

  const started = performance.now();
  try {
    const response = await fetch(url, {
      method: options.method || 'GET',
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: controller.signal,
    });
    const text = await response.text();
    const durationMs = performance.now() - started;
    return {
      ok: response.ok,
      status: response.status,
      durationMs,
      json: convertTimesToUtc7(safeJson(text)),
      text,
      timeout: false,
      fetchError: null,
    };
  } catch (error) {
    const durationMs = performance.now() - started;
    return {
      ok: false,
      status: null,
      durationMs,
      json: null,
      text: '',
      timeout: error && typeof error === 'object' && error.name === 'AbortError',
      fetchError: error instanceof Error ? error.message : String(error),
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function expectStatus(stepName, result, expectedStatuses) {
  const pass = result.status !== null && expectedStatuses.includes(result.status);
  return {
    step: stepName,
    pass,
    expectedStatuses,
    status: result.status,
    timeout: result.timeout,
    durationMs: result.durationMs,
    body: result.json || result.text,
    error: result.fetchError,
  };
}

async function runStabilityCase(name, config) {
  const durations = [];
  const statusCounts = {};
  let timeouts = 0;
  let fetchErrors = 0;
  const failures = [];

  for (let index = 0; index < STABILITY_ROUNDS; index += 1) {
    const result = await request(config.path, {
      method: config.method,
      headers: config.headers,
      body: typeof config.bodyFactory === 'function' ? config.bodyFactory(index) : config.body,
    });

    durations.push(result.durationMs);

    if (result.timeout) {
      timeouts += 1;
    }

    if (result.fetchError) {
      fetchErrors += 1;
    }

    if (result.status !== null) {
      statusCounts[result.status] = (statusCounts[result.status] || 0) + 1;
    } else {
      statusCounts.FETCH_ERROR = (statusCounts.FETCH_ERROR || 0) + 1;
    }

    if (!(result.status !== null && config.acceptStatuses.includes(result.status))) {
      if (failures.length < 6) {
        failures.push({
          round: index + 1,
          status: result.status,
          timeout: result.timeout,
          error: result.fetchError,
          body: result.json || result.text,
        });
      }
    }
  }

  const total = durations.length;
  const successCount = Object.entries(statusCounts).reduce((acc, [key, count]) => {
    if (config.acceptStatuses.includes(Number(key))) {
      return acc + count;
    }
    return acc;
  }, 0);
  const successRate = total > 0 ? successCount / total : 0;

  return {
    name,
    method: config.method,
    path: config.path,
    rounds: STABILITY_ROUNDS,
    acceptStatuses: config.acceptStatuses,
    successRate,
    timeoutCount: timeouts,
    fetchErrorCount: fetchErrors,
    statusCounts,
    latencyMs: summarizeDurations(durations),
    failures,
  };
}

async function main() {
  if (!DEVICE_ID || !SERVICE_API_KEY) {
    throw new Error('Missing DEVICE_ID or SERVICE_API_KEY in environment.');
  }

  const apiKeyHeaders = {
    'x-api-key': SERVICE_API_KEY,
  };

  const now = Date.now();
  const registerEmail = `flow-test-${now}-${crypto.randomBytes(3).toString('hex')}@example.com`;
  const registerPassword = `Flow!${crypto.randomBytes(4).toString('hex')}aA1`;

  const smoke = [];

  const s1 = await request('/api/devices');
  smoke.push(await expectStatus('GET /api/devices', s1, [200]));

  const s2 = await request('/api/devices/schedules');
  smoke.push(await expectStatus('GET /api/devices/schedules', s2, [200]));

  const s3 = await request('/api/users/register', {
    method: 'POST',
    body: { email: registerEmail, password: registerPassword },
  });
  smoke.push(await expectStatus('POST /api/users/register', s3, [201]));

  const s4 = await request('/api/users/login', {
    method: 'POST',
    body: { email: registerEmail, password: registerPassword },
  });
  smoke.push(await expectStatus('POST /api/users/login', s4, [200]));

  const s5 = await request(`/api/devices/${DEVICE_ID}/status`, {
    headers: apiKeyHeaders,
  });
  smoke.push(await expectStatus('GET /api/devices/{deviceId}/status', s5, [200]));

  const s6 = await request(`/api/devices/${DEVICE_ID}/telemetry?limit=10`, {
    headers: apiKeyHeaders,
  });
  smoke.push(await expectStatus('GET /api/devices/{deviceId}/telemetry', s6, [200]));

  const s7 = await request(`/api/devices/${DEVICE_ID}`, {
    headers: apiKeyHeaders,
  });
  smoke.push(await expectStatus('GET /api/devices/{deviceId}', s7, [200, 404]));

  const s8 = await request(`/api/devices/${DEVICE_ID}`, {
    method: 'PATCH',
    headers: apiKeyHeaders,
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
  });
  smoke.push(await expectStatus('PATCH /api/devices/{deviceId}', s8, [200]));

  const s9 = await request(`/api/devices/${DEVICE_ID}/control?limit=10`, {
    headers: apiKeyHeaders,
  });
  smoke.push(await expectStatus('GET /api/devices/{deviceId}/control', s9, [200]));

  const s10 = await request(`/api/devices/${DEVICE_ID}/override`, {
    method: 'POST',
    headers: apiKeyHeaders,
    body: {
      user_override: true,
      devices: {
        fan: false,
        heater: false,
        mist: true,
        light: true,
      },
    },
  });
  smoke.push(await expectStatus('POST /api/devices/{deviceId}/override', s10, [200]));

  const s11 = await request(`/api/devices/${DEVICE_ID}/control`, {
    method: 'POST',
    headers: apiKeyHeaders,
    body: {
      light: true,
      fan: false,
    },
  });
  smoke.push(await expectStatus('POST /api/devices/{deviceId}/control', s11, [200, 207]));

  const stabilityCases = [
    {
      name: 'status_get',
      method: 'GET',
      path: `/api/devices/${DEVICE_ID}/status`,
      headers: apiKeyHeaders,
      acceptStatuses: [200],
    },
    {
      name: 'telemetry_get',
      method: 'GET',
      path: `/api/devices/${DEVICE_ID}/telemetry?limit=10`,
      headers: apiKeyHeaders,
      acceptStatuses: [200],
    },
    {
      name: 'control_get',
      method: 'GET',
      path: `/api/devices/${DEVICE_ID}/control?limit=10`,
      headers: apiKeyHeaders,
      acceptStatuses: [200],
    },
    {
      name: 'override_post',
      method: 'POST',
      path: `/api/devices/${DEVICE_ID}/override`,
      headers: apiKeyHeaders,
      acceptStatuses: [200],
      bodyFactory: (index) => ({
        user_override: true,
        devices: {
          light: index % 2 === 0,
          fan: index % 2 !== 0,
        },
      }),
    },
    {
      name: 'control_post',
      method: 'POST',
      path: `/api/devices/${DEVICE_ID}/control`,
      headers: apiKeyHeaders,
      acceptStatuses: [200, 207],
      bodyFactory: (index) => ({
        light: index % 2 === 0,
        fan: index % 2 !== 0,
      }),
    },
    {
      name: 'login_post',
      method: 'POST',
      path: '/api/users/login',
      acceptStatuses: [200],
      body: {
        email: registerEmail,
        password: registerPassword,
      },
    },
  ];

  const stability = [];
  for (const testCase of stabilityCases) {
    stability.push(await runStabilityCase(testCase.name, testCase));
  }

  const smokePass = smoke.every((item) => item.pass);
  const unstableCases = stability.filter(
    (item) => item.successRate < 0.95 || item.timeoutCount > 0 || item.fetchErrorCount > 0,
  );

  const result = {
    generatedAt: nowUtc7Iso(),
    baseUrl: BASE_URL,
    deviceId: DEVICE_ID,
    config: {
      timeoutMs: REQUEST_TIMEOUT_MS,
      stabilityRounds: STABILITY_ROUNDS,
    },
    smoke,
    smokePass,
    stability,
    unstableCases: unstableCases.map((item) => ({
      name: item.name,
      successRate: item.successRate,
      timeoutCount: item.timeoutCount,
      fetchErrorCount: item.fetchErrorCount,
    })),
  };

  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error('[test-server-flows] Fatal error:', error);
  process.exitCode = 1;
});
