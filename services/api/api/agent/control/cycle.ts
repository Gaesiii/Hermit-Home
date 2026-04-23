import type { VercelRequest, VercelResponse } from '@vercel/node';
import { promises as fs } from 'fs';
import path from 'path';
import type { Db } from 'mongodb';
import type { CommandPayload, RelayState, ThresholdConfig } from '@smart-terrarium/shared-types';
import { withAuth, type AuthenticatedRequest } from '../../../lib/authMiddleware';
import { connectToDatabase } from '../../../lib/mongoClient';
import { publishCommand } from '../../../lib/mqttPublisher';
import { sanitizeCommandPayload } from '../../../lib/mistSafety';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { insertCommandPendingLogs, insertDiagnosticLog } from '../../../lib/diagnosticLogRepo';
import {
  clearUserOverrideWindow,
  getActiveUserOverrideWindow,
} from '../../../lib/userOverrideWindowRepo';

const ALLOWED_METHODS = ['POST'] as const;
const DEVICE_ID_REGEX = /^[a-f\d]{24}$/i;
const DEFAULT_RECENT_WINDOW_SIZE = 24;
const MAX_RECENT_WINDOW_SIZE = 120;
const DEFAULT_EMERGENCY_RELEASE_DELAY_MS = 2000;
const DEFAULT_MIST_SAFETY_LOCK_ENABLED = true;
const DEFAULT_CSV_SAMPLE_SIZE = 600;
const DEFAULT_AGENT_CONTROL_MAX_DEVICES = 30;
const MAX_AGENT_CONTROL_MAX_DEVICES = 200;
const DEFAULT_AGENT_CONTROL_ACTIVE_WINDOW_SECONDS = 900;
const MAX_AGENT_CONTROL_ACTIVE_WINDOW_SECONDS = 7 * 24 * 60 * 60;

const SAFETY_THRESHOLDS = {
  temperature: { min: 24.0, max: 29.0 },
  humidity: { min: 70.0, max: 85.0 },
  lux: { min: 200.0, max: 500.0 },
} as const;

const IDEAL_THRESHOLDS: ThresholdConfig = {
  temp_min: SAFETY_THRESHOLDS.temperature.min,
  temp_max: SAFETY_THRESHOLDS.temperature.max,
  hum_min: SAFETY_THRESHOLDS.humidity.min,
  hum_max: SAFETY_THRESHOLDS.humidity.max,
  lux_min: SAFETY_THRESHOLDS.lux.min,
  lux_max: SAFETY_THRESHOLDS.lux.max,
};

const SAFE_BOUNDS = {
  temp_min: { min: 20.0, max: 31.0 },
  temp_max: { min: 22.0, max: 34.0 },
  hum_min: { min: 55.0, max: 90.0 },
  hum_max: { min: 60.0, max: 95.0 },
  lux_min: { min: 80.0, max: 900.0 },
  lux_max: { min: 100.0, max: 1300.0 },
} as const;

type TelemetryDocument = {
  userId: string;
  timestamp: Date | string;
  temperature: number | null;
  humidity: number | null;
  lux: number | null;
  sensor_fault: boolean;
  user_override: boolean;
  relays?: Partial<RelayState>;
};

type DeviceAlertDocument = {
  deviceId: string;
  userId: string;
  source: 'ai-agent' | 'system' | 'user';
  level: 'info' | 'warning' | 'critical';
  title: string;
  message: string;
  danger_state: boolean;
  reason?: string;
  danger_reasons?: string[];
  telemetry?: Record<string, unknown>;
  actions?: Record<string, unknown>;
  createdAt: Date;
};

type CsvContext = {
  csvPath: string;
  csvAvailable: boolean;
  rowsConsidered: number;
  temperatureAvg: number | null;
  humidityAvg: number | null;
  luxAvg: number | null;
};

type DeviceControlResult = {
  status: number;
  payload: Record<string, unknown>;
};

function readQueryValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }
  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }
  return null;
}

function parseBooleanFlag(raw: string | undefined, fallback: boolean): boolean {
  if (!raw) return fallback;
  const normalized = raw.trim().toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
}

function parsePositiveInteger(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return parsed;
}

function parseNonNegativeInteger(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return parsed;
}

function asNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function average(values: Array<number | null>): number | null {
  const clean = values.filter((value): value is number => typeof value === 'number');
  if (clean.length === 0) return null;
  return clean.reduce((sum, value) => sum + value, 0) / clean.length;
}

function weightedAverage(items: Array<{ value: number | null; weight: number }>): number | null {
  const valid = items.filter(
    (item): item is { value: number; weight: number } =>
      item.value !== null && Number.isFinite(item.value) && item.weight > 0,
  );
  if (valid.length === 0) return null;

  const totalWeight = valid.reduce((sum, item) => sum + item.weight, 0);
  if (totalWeight <= 0) return null;

  const weightedSum = valid.reduce((sum, item) => sum + item.value * item.weight, 0);
  return weightedSum / totalWeight;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function parseAllowedDeviceIdsFromEnv(): string[] {
  const raw = process.env.ALLOWED_DEVICE_IDS || '';
  return [
    ...new Set(
      raw
        .split(',')
        .map((item) => item.trim())
        .filter((item) => item.length > 0 && isValidDeviceId(item)),
    ),
  ];
}

function parseDeviceIdList(raw: unknown): string[] {
  if (typeof raw === 'string') {
    return raw
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
  }

  if (Array.isArray(raw)) {
    return raw
      .filter((item): item is string => typeof item === 'string')
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

function dedupeDeviceIds(deviceIds: string[]): string[] {
  return [...new Set(deviceIds)];
}

function isValidDeviceId(deviceId: string): boolean {
  return DEVICE_ID_REGEX.test(deviceId);
}

function parseBodyObject(body: unknown): Record<string, unknown> {
  if (body && typeof body === 'object' && !Array.isArray(body)) {
    return body as Record<string, unknown>;
  }
  return {};
}

async function listTelemetryDeviceIds(
  db: Db,
  maxDevices: number,
  allowedDeviceIds: string[] | null,
  activeSince: Date | null,
): Promise<string[]> {
  const pipeline: Record<string, unknown>[] = [];
  const match: Record<string, unknown> = {};

  if (allowedDeviceIds && allowedDeviceIds.length > 0) {
    match.userId = { $in: allowedDeviceIds };
  }
  if (activeSince) {
    match.timestamp = { $gte: activeSince };
  }

  if (Object.keys(match).length > 0) {
    pipeline.push({
      $match: match,
    });
  }

  pipeline.push(
    {
      $group: {
        _id: '$userId',
        lastTelemetryAt: { $max: '$timestamp' },
      },
    },
    {
      $sort: { lastTelemetryAt: -1 },
    },
    {
      $limit: maxDevices,
    },
  );

  const docs = await db
    .collection<TelemetryDocument>('telemetry')
    .aggregate<{ _id: string }>(pipeline)
    .toArray();

  return docs
    .map((doc) => doc._id)
    .filter((deviceId) => typeof deviceId === 'string' && isValidDeviceId(deviceId));
}

async function resolveTargetDeviceIds(params: {
  req: AuthenticatedRequest;
  body: Record<string, unknown>;
  db: Db;
  isServiceCall: boolean;
  requesterUserId: string;
}): Promise<{ deviceIds: string[]; errorMessage: string | null }> {
  const { req, body, db, isServiceCall, requesterUserId } = params;
  const queryDeviceId = readQueryValue(req.query.deviceId)?.trim() ?? '';
  const bodyDeviceIds = parseDeviceIdList(body.deviceIds);
  const bodyDeviceId = typeof body.deviceId === 'string' ? body.deviceId.trim() : '';

  const explicitDeviceIds = dedupeDeviceIds([
    ...bodyDeviceIds,
    bodyDeviceId,
    queryDeviceId,
  ].filter(Boolean));

  const invalidExplicit = explicitDeviceIds.filter((deviceId) => !isValidDeviceId(deviceId));
  if (invalidExplicit.length > 0) {
    return {
      deviceIds: [],
      errorMessage: `Invalid deviceId format: ${invalidExplicit.join(', ')}`,
    };
  }

  const enforceAllowList = parseBooleanFlag(
    process.env.AGENT_CONTROL_ENFORCE_ALLOWED_DEVICE_IDS,
    false,
  );
  const allowedFromEnv = parseAllowedDeviceIdsFromEnv();

  if (!isServiceCall) {
    if (!isValidDeviceId(requesterUserId)) {
      return {
        deviceIds: [],
        errorMessage: 'Authenticated user cannot be mapped to a valid deviceId.',
      };
    }

    if (explicitDeviceIds.length > 0) {
      const forbidden = explicitDeviceIds.filter((deviceId) => deviceId !== requesterUserId);
      if (forbidden.length > 0) {
        return {
          deviceIds: [],
          errorMessage: 'You do not have permission to run control cycle for requested deviceId.',
        };
      }
      return { deviceIds: [requesterUserId], errorMessage: null };
    }

    return { deviceIds: [requesterUserId], errorMessage: null };
  }

  if (explicitDeviceIds.length > 0) {
    if (enforceAllowList && allowedFromEnv.length > 0) {
      const filtered = explicitDeviceIds.filter((deviceId) => allowedFromEnv.includes(deviceId));
      if (filtered.length === 0) {
        return {
          deviceIds: [],
          errorMessage: 'Requested deviceId is not permitted by ALLOWED_DEVICE_IDS.',
        };
      }
      return { deviceIds: filtered, errorMessage: null };
    }

    return { deviceIds: explicitDeviceIds, errorMessage: null };
  }

  if (enforceAllowList && allowedFromEnv.length === 0) {
    return {
      deviceIds: [],
      errorMessage:
        'AGENT_CONTROL_ENFORCE_ALLOWED_DEVICE_IDS is enabled but ALLOWED_DEVICE_IDS is empty or invalid.',
    };
  }

  const maxDevices = clamp(
    parsePositiveInteger(process.env.AGENT_CONTROL_MAX_DEVICES, DEFAULT_AGENT_CONTROL_MAX_DEVICES),
    1,
    MAX_AGENT_CONTROL_MAX_DEVICES,
  );
  const activeWindowSeconds = clamp(
    parseNonNegativeInteger(
      process.env.AGENT_CONTROL_ACTIVE_WINDOW_SECONDS,
      DEFAULT_AGENT_CONTROL_ACTIVE_WINDOW_SECONDS,
    ),
    0,
    MAX_AGENT_CONTROL_ACTIVE_WINDOW_SECONDS,
  );
  const activeSince =
    activeWindowSeconds > 0
      ? new Date(Date.now() - activeWindowSeconds * 1000)
      : null;
  const autoDetected = await listTelemetryDeviceIds(
    db,
    maxDevices,
    enforceAllowList ? allowedFromEnv : null,
    activeSince,
  );
  if (autoDetected.length === 0) {
    return {
      deviceIds: [],
      errorMessage:
        activeSince !== null
          ? `No active telemetry-backed device found within the last ${activeWindowSeconds} seconds for automatic agent control cycle.`
          : 'No telemetry-backed device found for automatic agent control cycle.',
    };
  }

  return { deviceIds: autoDetected, errorMessage: null };
}

function buildAdaptiveThresholds(params: {
  current: TelemetryDocument;
  recent: TelemetryDocument[];
  csvContext: CsvContext;
}): ThresholdConfig {
  const recentTemperatureAvg = average(params.recent.map((item) => asNumber(item.temperature)));
  const recentHumidityAvg = average(params.recent.map((item) => asNumber(item.humidity)));
  const recentLuxAvg = average(params.recent.map((item) => asNumber(item.lux)));

  const targetTemp = weightedAverage([
    { value: asNumber(params.current.temperature), weight: 0.25 },
    { value: recentTemperatureAvg, weight: 0.55 },
    { value: params.csvContext.temperatureAvg, weight: 0.20 },
  ]);
  const targetHum = weightedAverage([
    { value: asNumber(params.current.humidity), weight: 0.25 },
    { value: recentHumidityAvg, weight: 0.55 },
    { value: params.csvContext.humidityAvg, weight: 0.20 },
  ]);
  const targetLux = weightedAverage([
    { value: asNumber(params.current.lux), weight: 0.25 },
    { value: recentLuxAvg, weight: 0.55 },
    { value: params.csvContext.luxAvg, weight: 0.20 },
  ]);

  const thresholds: ThresholdConfig = { ...IDEAL_THRESHOLDS };

  if (targetTemp !== null) {
    thresholds.temp_min = targetTemp - 2.0;
    thresholds.temp_max = targetTemp + 2.0;
  }
  if (targetHum !== null) {
    thresholds.hum_min = targetHum - 7.0;
    thresholds.hum_max = targetHum + 7.0;
  }
  if (targetLux !== null) {
    thresholds.lux_min = targetLux - 150.0;
    thresholds.lux_max = targetLux + 150.0;
  }

  thresholds.temp_min = clamp(
    thresholds.temp_min,
    SAFE_BOUNDS.temp_min.min,
    SAFE_BOUNDS.temp_min.max,
  );
  thresholds.temp_max = clamp(
    thresholds.temp_max,
    SAFE_BOUNDS.temp_max.min,
    SAFE_BOUNDS.temp_max.max,
  );
  thresholds.hum_min = clamp(thresholds.hum_min, SAFE_BOUNDS.hum_min.min, SAFE_BOUNDS.hum_min.max);
  thresholds.hum_max = clamp(thresholds.hum_max, SAFE_BOUNDS.hum_max.min, SAFE_BOUNDS.hum_max.max);
  thresholds.lux_min = clamp(thresholds.lux_min, SAFE_BOUNDS.lux_min.min, SAFE_BOUNDS.lux_min.max);
  thresholds.lux_max = clamp(thresholds.lux_max, SAFE_BOUNDS.lux_max.min, SAFE_BOUNDS.lux_max.max);

  if (thresholds.temp_max <= thresholds.temp_min) {
    thresholds.temp_max = clamp(
      thresholds.temp_min + 1.0,
      SAFE_BOUNDS.temp_max.min,
      SAFE_BOUNDS.temp_max.max,
    );
  }
  if (thresholds.hum_max <= thresholds.hum_min) {
    thresholds.hum_max = clamp(
      thresholds.hum_min + 5.0,
      SAFE_BOUNDS.hum_max.min,
      SAFE_BOUNDS.hum_max.max,
    );
  }
  if (thresholds.lux_max <= thresholds.lux_min) {
    thresholds.lux_max = clamp(
      thresholds.lux_min + 50.0,
      SAFE_BOUNDS.lux_max.min,
      SAFE_BOUNDS.lux_max.max,
    );
  }

  return {
    temp_min: round(thresholds.temp_min, 1),
    temp_max: round(thresholds.temp_max, 1),
    hum_min: round(thresholds.hum_min, 1),
    hum_max: round(thresholds.hum_max, 1),
    lux_min: round(thresholds.lux_min, 0),
    lux_max: round(thresholds.lux_max, 0),
  };
}

function detectDangerReasons(telemetry: TelemetryDocument): string[] {
  const reasons: string[] = [];
  if (telemetry.sensor_fault === true) {
    reasons.push('Sensor fault flag is active.');
  }

  const temperature = asNumber(telemetry.temperature);
  const humidity = asNumber(telemetry.humidity);
  const lux = asNumber(telemetry.lux);

  if (temperature === null) {
    reasons.push('Temperature telemetry is missing.');
  } else if (temperature < SAFETY_THRESHOLDS.temperature.min) {
    reasons.push(`Temperature too low (${temperature.toFixed(1)}C).`);
  } else if (temperature > SAFETY_THRESHOLDS.temperature.max) {
    reasons.push(`Temperature too high (${temperature.toFixed(1)}C).`);
  }

  if (humidity === null) {
    reasons.push('Humidity telemetry is missing.');
  } else if (humidity < SAFETY_THRESHOLDS.humidity.min) {
    reasons.push(`Humidity too low (${humidity.toFixed(1)}%).`);
  } else if (humidity > SAFETY_THRESHOLDS.humidity.max) {
    reasons.push(`Humidity too high (${humidity.toFixed(1)}%).`);
  }

  if (lux === null) {
    reasons.push('Lux telemetry is missing.');
  } else if (lux < SAFETY_THRESHOLDS.lux.min) {
    reasons.push(`Lux too low (${lux.toFixed(0)}).`);
  } else if (lux > SAFETY_THRESHOLDS.lux.max) {
    reasons.push(`Lux too high (${lux.toFixed(0)}).`);
  }

  return reasons;
}

function buildDesiredDevices(
  telemetry: TelemetryDocument,
  thresholds: ThresholdConfig,
  mistSafetyLockEnabled: boolean,
): Partial<RelayState> {
  const devices: Partial<RelayState> = {};

  const temperature = asNumber(telemetry.temperature);
  const humidity = asNumber(telemetry.humidity);
  const lux = asNumber(telemetry.lux);

  if (temperature !== null) {
    if (temperature < thresholds.temp_min) {
      devices.heater = true;
      devices.fan = false;
    } else if (temperature > thresholds.temp_max) {
      devices.heater = false;
      devices.fan = true;
    }
  }

  if (humidity !== null) {
    if (humidity < thresholds.hum_min) {
      if (mistSafetyLockEnabled) {
        devices.mist = false;
        devices.fan = false;
      } else {
        devices.mist = true;
        if (devices.fan === undefined) {
          devices.fan = false;
        }
      }
    } else if (humidity > thresholds.hum_max) {
      devices.mist = false;
      devices.fan = true;
    }
  }

  if (lux !== null) {
    if (lux < thresholds.lux_min) {
      devices.light = true;
    } else if (lux > thresholds.lux_max) {
      devices.light = false;
    }
  }

  if (mistSafetyLockEnabled) {
    devices.mist = false;
  }

  return devices;
}

function diffRelayPatch(
  desired: Partial<RelayState>,
  current: Partial<RelayState> | undefined,
): Partial<RelayState> {
  const patch: Partial<RelayState> = {};
  const keys: Array<keyof RelayState> = ['heater', 'mist', 'fan', 'light'];

  for (const key of keys) {
    const desiredValue = desired[key];
    if (typeof desiredValue !== 'boolean') {
      continue;
    }

    const currentValue = current?.[key];
    if (typeof currentValue !== 'boolean' || currentValue !== desiredValue) {
      patch[key] = desiredValue;
    }
  }

  return patch;
}

function parseCsvLine(line: string): string[] {
  const output: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (char === '"') {
      const isEscapedQuote = inQuotes && line[index + 1] === '"';
      if (isEscapedQuote) {
        current += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === ',' && !inQuotes) {
      output.push(current);
      current = '';
      continue;
    }

    current += char;
  }

  output.push(current);
  return output;
}

async function loadCsvContext(deviceId: string): Promise<CsvContext> {
  const configuredPath = (
    process.env.AGENT_TELEMETRY_CSV_PATH ||
    process.env.TELEMETRY_CSV_PATH ||
    'exports/telemetry-export.csv'
  ).trim();
  const resolvedPath = path.resolve(process.cwd(), configuredPath);
  const sampleSize = parsePositiveInteger(process.env.AGENT_TELEMETRY_CSV_SAMPLE_SIZE, DEFAULT_CSV_SAMPLE_SIZE);

  try {
    const raw = await fs.readFile(resolvedPath, 'utf8');
    const lines = raw.split(/\r?\n/).filter((line) => line.trim().length > 0);
    if (lines.length <= 1) {
      return {
        csvPath: resolvedPath,
        csvAvailable: true,
        rowsConsidered: 0,
        temperatureAvg: null,
        humidityAvg: null,
        luxAvg: null,
      };
    }

    const header = parseCsvLine(lines[0]);
    const userIdIndex = header.indexOf('userId');
    const temperatureIndex = header.indexOf('temperature');
    const humidityIndex = header.indexOf('humidity');
    const luxIndex = header.indexOf('lux');

    if (userIdIndex === -1 || temperatureIndex === -1 || humidityIndex === -1 || luxIndex === -1) {
      return {
        csvPath: resolvedPath,
        csvAvailable: true,
        rowsConsidered: 0,
        temperatureAvg: null,
        humidityAvg: null,
        luxAvg: null,
      };
    }

    const temperatures: Array<number | null> = [];
    const humidities: Array<number | null> = [];
    const luxValues: Array<number | null> = [];
    let rows = 0;

    for (let index = lines.length - 1; index >= 1; index -= 1) {
      if (rows >= sampleSize) {
        break;
      }
      const columns = parseCsvLine(lines[index]);
      if ((columns[userIdIndex] || '').trim() !== deviceId) {
        continue;
      }

      rows += 1;
      temperatures.push(asNumber(columns[temperatureIndex]));
      humidities.push(asNumber(columns[humidityIndex]));
      luxValues.push(asNumber(columns[luxIndex]));
    }

    return {
      csvPath: resolvedPath,
      csvAvailable: true,
      rowsConsidered: rows,
      temperatureAvg: average(temperatures),
      humidityAvg: average(humidities),
      luxAvg: average(luxValues),
    };
  } catch {
    return {
      csvPath: resolvedPath,
      csvAvailable: false,
      rowsConsidered: 0,
      temperatureAvg: null,
      humidityAvg: null,
      luxAvg: null,
    };
  }
}

function summarizeCommand(command: CommandPayload): Record<string, unknown> {
  return {
    user_override: command.user_override,
    devices: command.devices || {},
    thresholds: command.thresholds || {},
  };
}

async function publishAndAuditCommand(params: {
  deviceId: string;
  userId: string;
  command: CommandPayload;
  reason: string;
  metadata?: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  const safeCommand = sanitizeCommandPayload(params.command);
  await publishCommand(params.deviceId, safeCommand);

  const hasDevicePatch = !!safeCommand.devices && Object.keys(safeCommand.devices).length > 0;
  if (hasDevicePatch) {
    await insertCommandPendingLogs({
      deviceId: params.deviceId,
      userId: params.userId,
      source: 'ai-agent',
      stateUpdate: safeCommand.devices as Record<string, boolean>,
      metadata: {
        trigger: 'agent-control-cycle',
        reason: params.reason,
        ...(params.metadata || {}),
      },
    });
  }

  await insertDiagnosticLog({
    deviceId: params.deviceId,
    userId: params.userId,
    source: 'ai-agent',
    category: 'AI',
    status: 'PASS',
    message: `[PASS] Agent control cycle published command (${safeCommand.user_override ? 'override' : 'auto'}).`,
    metadata: {
      reason: params.reason,
      command: summarizeCommand(safeCommand),
      ...(params.metadata || {}),
    },
  });

  return summarizeCommand(safeCommand);
}

async function persistDangerAlert(params: {
  db: Db;
  deviceId: string;
  userId: string;
  telemetry: TelemetryDocument;
  reason: string;
  dangerReasons: string[];
  thresholds: ThresholdConfig;
  desiredDevices: Partial<RelayState>;
  userOverrideWindowActive: boolean;
  userOverrideTakenOver: boolean;
  userOverrideWindowExpiresAt: Date | null;
}): Promise<void> {
  const alertEnabled = parseBooleanFlag(process.env.AGENT_CONTROL_ALERTS_ENABLED, true);
  if (!alertEnabled) return;

  const level: DeviceAlertDocument['level'] =
    params.dangerReasons.length >= 2 || params.telemetry.sensor_fault ? 'critical' : 'warning';
  const document: DeviceAlertDocument = {
    deviceId: params.deviceId,
    userId: params.userId,
    source: 'ai-agent',
    level,
    title: 'Hermit Home Danger State Detected',
    message: params.dangerReasons.slice(0, 3).join('; '),
    danger_state: true,
    reason: params.reason,
    danger_reasons: params.dangerReasons.slice(0, 10),
    telemetry: {
      temperature: params.telemetry.temperature,
      humidity: params.telemetry.humidity,
      lux: params.telemetry.lux,
      sensor_fault: params.telemetry.sensor_fault,
      user_override: params.telemetry.user_override,
      timestamp: params.telemetry.timestamp,
    },
    actions: {
      desired_devices: params.desiredDevices,
      thresholds: params.thresholds,
      trigger: 'agent-control-cycle',
      user_override_window_active: params.userOverrideWindowActive,
      user_override_taken_over: params.userOverrideTakenOver,
      user_override_expires_at: params.userOverrideWindowExpiresAt,
    },
    createdAt: new Date(),
  };

  await params.db.collection<DeviceAlertDocument>('device_alerts').insertOne(document);
}

async function runControlCycleForDevice(params: {
  db: Db;
  deviceId: string;
  effectiveUserId: string;
  recentWindowSize: number;
  mistSafetyLockEnabled: boolean;
  emergencyReleaseDelayMs: number;
  trigger: string;
  source: string;
}): Promise<DeviceControlResult> {
  const telemetryCollection = params.db.collection<TelemetryDocument>('telemetry');
  const latest = await telemetryCollection
    .find({ userId: params.deviceId })
    .sort({ timestamp: -1 })
    .limit(1)
    .next();

  if (!latest) {
    await insertDiagnosticLog({
      deviceId: params.deviceId,
      userId: params.effectiveUserId,
      source: 'ai-agent',
      category: 'AI',
      status: 'FAIL',
      message: '[FAIL] Agent control cycle aborted: no telemetry found.',
      metadata: {
        trigger: params.trigger,
        source: params.source,
        recentWindowSize: params.recentWindowSize,
      },
    });

    return {
      status: 404,
      payload: {
        success: false,
        error: 'No telemetry found for this device.',
        deviceId: params.deviceId,
      },
    };
  }

  const recent = await telemetryCollection
    .find({ userId: params.deviceId })
    .sort({ timestamp: -1 })
    .limit(params.recentWindowSize)
    .toArray();
  const csvContext = await loadCsvContext(params.deviceId);

  const dangerReasons = detectDangerReasons(latest);
  const dangerState = dangerReasons.length > 0;
  const thresholds = buildAdaptiveThresholds({
    current: latest,
    recent,
    csvContext,
  });
  const desiredDevices = buildDesiredDevices(latest, thresholds, params.mistSafetyLockEnabled);
  const devicePatch = diffRelayPatch(desiredDevices, latest.relays);
  const hasDevicePatch = Object.keys(devicePatch).length > 0;
  const activeUserOverrideWindow = await getActiveUserOverrideWindow(params.deviceId);
  const userOverrideWindowActive = activeUserOverrideWindow !== null;
  const userOverrideWindowExpiresAt = activeUserOverrideWindow?.expiresAt ?? null;

  const commandsToSend: CommandPayload[] = [];
  let reason = 'Environment is within adaptive operating range.';
  let userOverrideTakenOver = false;

  const clearWindowSafely = async (clearReason: string): Promise<void> => {
    try {
      await clearUserOverrideWindow(params.deviceId, clearReason);
    } catch (error: unknown) {
      await insertDiagnosticLog({
        deviceId: params.deviceId,
        userId: params.effectiveUserId,
        source: 'ai-agent',
        category: 'AI',
        status: 'INFO',
        message: '[INFO] Failed to update user override grace state in database.',
        metadata: {
          trigger: params.trigger,
          source: params.source,
          clearReason,
          error: error instanceof Error ? error.message : 'unknown error',
        },
      });
    }
  };

  if (dangerState) {
    reason = `Danger state detected: ${dangerReasons.join(' ')}`;
    if (userOverrideWindowActive) {
      userOverrideTakenOver = true;
      reason += ' Agent reclaimed control from active user override window.';
      await clearWindowSafely('danger-threshold-exceeded');
    }

    if (hasDevicePatch) {
      commandsToSend.push({
        user_override: true,
        devices: devicePatch,
      });
    }

    commandsToSend.push({
      user_override: false,
      thresholds,
    });
  } else if (userOverrideWindowActive) {
    reason = `User override grace active until ${userOverrideWindowExpiresAt?.toISOString() || 'unknown'}; skipping automated relay command.`;
  } else if (latest.user_override) {
    reason = 'User override grace expired; returning control to agent automation.';
    await clearWindowSafely('grace-expired-agent-reclaim');
    const reclaimCommand: CommandPayload = {
      user_override: false,
      thresholds,
    };
    if (hasDevicePatch) {
      reclaimCommand.devices = devicePatch;
    }
    commandsToSend.push(reclaimCommand);
  } else if (hasDevicePatch) {
    reason = 'Adjusting relays toward adaptive safe thresholds.';
    commandsToSend.push({
      user_override: false,
      devices: devicePatch,
    });
  }

  const commandResults: Array<Record<string, unknown>> = [];

  try {
    for (let index = 0; index < commandsToSend.length; index += 1) {
      const command = commandsToSend[index];
      const isReleasingOverride =
        index > 0 &&
        commandsToSend[index - 1]?.user_override === true &&
        command.user_override === false;
      if (isReleasingOverride && params.emergencyReleaseDelayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, params.emergencyReleaseDelayMs));
      }

      const result = await publishAndAuditCommand({
        deviceId: params.deviceId,
        userId: params.effectiveUserId,
        command,
        reason,
        metadata: {
          trigger: params.trigger,
          source: params.source,
          commandIndex: index + 1,
          totalCommands: commandsToSend.length,
          dangerState,
        },
      });
      commandResults.push(result);
    }
  } catch (error: unknown) {
    await insertDiagnosticLog({
      deviceId: params.deviceId,
      userId: params.effectiveUserId,
      source: 'ai-agent',
      category: 'AI',
      status: 'FAIL',
      message: '[FAIL] Agent control cycle failed to publish command.',
      metadata: {
        trigger: params.trigger,
        source: params.source,
        reason,
        error: error instanceof Error ? error.message : 'unknown error',
      },
    });

    return {
      status: 502,
      payload: {
        success: false,
        error: 'Failed to publish control command.',
        deviceId: params.deviceId,
        reason,
        dangerState,
      },
    };
  }

  if (dangerState) {
    try {
      await persistDangerAlert({
        db: params.db,
        deviceId: params.deviceId,
        userId: params.effectiveUserId,
        telemetry: latest,
        reason,
        dangerReasons,
        thresholds,
        desiredDevices: devicePatch,
        userOverrideWindowActive,
        userOverrideTakenOver,
        userOverrideWindowExpiresAt,
      });
    } catch (error: unknown) {
      await insertDiagnosticLog({
        deviceId: params.deviceId,
        userId: params.effectiveUserId,
        source: 'ai-agent',
        category: 'AI',
        status: 'INFO',
        message: '[INFO] Danger state detected but alert persistence failed.',
        metadata: {
          trigger: params.trigger,
          source: params.source,
          error: error instanceof Error ? error.message : 'unknown error',
        },
      });
    }
  }

  await insertDiagnosticLog({
    deviceId: params.deviceId,
    userId: params.effectiveUserId,
    source: 'ai-agent',
    category: 'AI',
    status: 'PASS',
    message: `[PASS] Agent control cycle completed (${dangerState ? 'danger' : 'safe'} state).`,
    metadata: {
      trigger: params.trigger,
      source: params.source,
      reason,
      dangerReasons,
      commandCount: commandResults.length,
      userOverrideWindowActive,
      userOverrideTakenOver,
      userOverrideWindowExpiresAt,
      csvAvailable: csvContext.csvAvailable,
      csvRowsConsidered: csvContext.rowsConsidered,
      thresholds,
    },
  });

  return {
    status: 200,
    payload: {
      success: true,
      deviceId: params.deviceId,
      dangerState,
      dangerReasons,
      reason,
      thresholds,
      desiredDevices: devicePatch,
      userOverrideWindowActive,
      userOverrideWindowExpiresAt,
      userOverrideTakenOver,
      commandCount: commandResults.length,
      commands: commandResults,
      csvContext: {
        csvPath: csvContext.csvPath,
        csvAvailable: csvContext.csvAvailable,
        rowsConsidered: csvContext.rowsConsidered,
        temperatureAvg: csvContext.temperatureAvg,
        humidityAvg: csvContext.humidityAvg,
        luxAvg: csvContext.luxAvg,
      },
    },
  };
}

async function runControlCycle(req: AuthenticatedRequest, res: VercelResponse): Promise<void> {
  const body = parseBodyObject(req.body);
  const { db } = await connectToDatabase();
  const apiKeyHeader = req.headers['x-api-key'];
  const isServiceCall =
    (typeof apiKeyHeader === 'string' && apiKeyHeader.trim().length > 0) ||
    (Array.isArray(apiKeyHeader) && apiKeyHeader.length > 0);
  const requesterUserId = req.user.userId;

  const { deviceIds, errorMessage } = await resolveTargetDeviceIds({
    req,
    body,
    db,
    isServiceCall,
    requesterUserId,
  });
  if (deviceIds.length === 0) {
    res.status(400).json({
      error: errorMessage || 'Unable to resolve target deviceId(s).',
    });
    return;
  }

  const recentWindowSize = clamp(
    parsePositiveInteger(process.env.AGENT_CONTROL_RECENT_WINDOW_SIZE, DEFAULT_RECENT_WINDOW_SIZE),
    1,
    MAX_RECENT_WINDOW_SIZE,
  );
  const mistSafetyLockEnabled = parseBooleanFlag(
    process.env.AGENT_MIST_SAFETY_LOCK_ENABLED || process.env.MIST_SAFETY_LOCK_ENABLED,
    DEFAULT_MIST_SAFETY_LOCK_ENABLED,
  );
  const emergencyReleaseDelayMs = clamp(
    parsePositiveInteger(
      process.env.AGENT_EMERGENCY_RELEASE_DELAY_MS,
      DEFAULT_EMERGENCY_RELEASE_DELAY_MS,
    ),
    0,
    30_000,
  );

  const trigger =
    typeof body.trigger === 'string' && body.trigger.trim().length > 0
      ? body.trigger.trim()
      : 'api';
  const source =
    typeof body.source === 'string' && body.source.trim().length > 0
      ? body.source.trim()
      : 'agent-control-cycle';

  if (deviceIds.length === 1) {
    const singleDeviceId = deviceIds[0];
    const singleResult = await runControlCycleForDevice({
      db,
      deviceId: singleDeviceId,
      effectiveUserId: isServiceCall ? singleDeviceId : requesterUserId,
      recentWindowSize,
      mistSafetyLockEnabled,
      emergencyReleaseDelayMs,
      trigger,
      source,
    });
    res.status(singleResult.status).json(singleResult.payload);
    return;
  }

  const results: Array<Record<string, unknown>> = [];
  let successCount = 0;

  for (const deviceId of deviceIds) {
    const result = await runControlCycleForDevice({
      db,
      deviceId,
      effectiveUserId: isServiceCall ? deviceId : requesterUserId,
      recentWindowSize,
      mistSafetyLockEnabled,
      emergencyReleaseDelayMs,
      trigger,
      source,
    });
    const isSuccess = result.status >= 200 && result.status < 300 && result.payload.success === true;
    if (isSuccess) {
      successCount += 1;
    }

    results.push({
      deviceId,
      status: result.status,
      ...result.payload,
    });
  }

  const failCount = results.length - successCount;
  const statusCode = failCount === 0 ? 200 : successCount > 0 ? 207 : 502;

  res.status(statusCode).json({
    success: failCount === 0,
    scope: 'multi-device',
    requestedDeviceCount: deviceIds.length,
    successCount,
    failCount,
    trigger,
    source,
    results,
  });
}

const authenticatedHandler = withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> => {
  if (req.method !== 'POST') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  await runControlCycle(req, res);
});

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (handleApiPreflight(req, res, ALLOWED_METHODS)) {
    return;
  }

  if (req.method !== 'POST') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  await authenticatedHandler(req, res);
}
