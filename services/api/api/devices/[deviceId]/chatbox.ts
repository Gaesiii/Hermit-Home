import type { VercelRequest, VercelResponse } from '@vercel/node';
import { promises as fs } from 'fs';
import path from 'path';
import type { Db } from 'mongodb';
import { connectToDatabase } from '../../../lib/mongoClient';
import { withAuth, type AuthenticatedRequest } from '../../../lib/authMiddleware';
import { handleApiPreflight, methodNotAllowed } from '../../../lib/http';
import { insertDiagnosticLog } from '../../../lib/diagnosticLogRepo';
import { toUtc7Iso } from '../../../lib/timezone';

const OBJECT_ID_REGEX = /^[a-f\d]{24}$/i;
const ALLOWED_METHODS = ['GET', 'POST'] as const;
const DEFAULT_TELEMETRY_WINDOW_SIZE = 24;
const MAX_TELEMETRY_WINDOW_SIZE = 120;
const DEFAULT_CSV_SAMPLE_SIZE = 400;
const MAX_CSV_SAMPLE_SIZE = 2000;
const DEFAULT_CHAT_HISTORY_TURNS = 8;
const MAX_CHAT_HISTORY_TURNS = 20;
const DEFAULT_MAX_SUGGESTIONS = 5;
const MAX_MAX_SUGGESTIONS = 10;
const DEFAULT_MAX_COMPLETION_TOKENS = 700;
const DEFAULT_TEMPERATURE = 0.2;

const SAFETY_THRESHOLDS = {
  temperature: { min: 24.0, max: 29.0 },
  humidity: { min: 70.0, max: 85.0 },
  lux: { min: 200.0, max: 500.0 },
} as const;

type TelemetryRelays = {
  heater: boolean;
  mist: boolean;
  fan: boolean;
  light: boolean;
};

type TelemetryDocument = {
  userId: string;
  timestamp: Date | string;
  temperature: number | null;
  humidity: number | null;
  lux: number | null;
  sensor_fault: boolean;
  user_override: boolean;
  relays: TelemetryRelays;
};

type ChatHistoryMessage = {
  role: 'user' | 'assistant';
  content: string;
};

type ChatRequestMode = 'chat' | 'context';

type ChatHistoryContext = {
  totalMessages: number;
  userTurns: number;
  assistantTurns: number;
  lastUserMessage: string | null;
  lastAssistantMessage: string | null;
  recentTranscript: ChatHistoryMessage[];
};

type CsvContext = {
  csvPath: string;
  csvAvailable: boolean;
  rowsConsidered: number;
  temperatureAvg: number | null;
  humidityAvg: number | null;
  luxAvg: number | null;
};

type TelemetrySummary = {
  latest: {
    timestamp: string | null;
    temperature: number | null;
    humidity: number | null;
    lux: number | null;
    sensor_fault: boolean;
    user_override: boolean;
    relays: TelemetryRelays;
  };
  recent: {
    count: number;
    temperatureAvg: number | null;
    humidityAvg: number | null;
    luxAvg: number | null;
    temperatureMin: number | null;
    temperatureMax: number | null;
    humidityMin: number | null;
    humidityMax: number | null;
    luxMin: number | null;
    luxMax: number | null;
  };
  csv: CsvContext;
  dangerReasons: string[];
};

type OpenRouterMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
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

function parsePositiveInteger(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return parsed;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function parseTemperature(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed)) return fallback;
  return clamp(parsed, 0, 1);
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

function minValue(values: Array<number | null>): number | null {
  const clean = values.filter((value): value is number => typeof value === 'number');
  if (clean.length === 0) return null;
  return Math.min(...clean);
}

function maxValue(values: Array<number | null>): number | null {
  const clean = values.filter((value): value is number => typeof value === 'number');
  if (clean.length === 0) return null;
  return Math.max(...clean);
}

function round(value: number | null, digits: number): number | null {
  if (value === null) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function resolveAuthorizedDeviceId(
  req: AuthenticatedRequest,
  res: VercelResponse,
): string | null {
  const { deviceId } = req.query;

  if (!deviceId || typeof deviceId !== 'string') {
    res.status(400).json({ error: 'deviceId route parameter is required.' });
    return null;
  }

  if (!OBJECT_ID_REGEX.test(deviceId)) {
    res.status(400).json({
      error: 'Invalid device ID format.',
      message: 'Device ID must be a 24-character hex string.',
    });
    return null;
  }

  if (req.user.userId !== deviceId) {
    res.status(403).json({
      error: 'Forbidden',
      message: 'You do not have permission to access this chatbox.',
    });
    return null;
  }

  return deviceId;
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
    process.env.CHATBOX_TELEMETRY_CSV_PATH ||
    process.env.AGENT_TELEMETRY_CSV_PATH ||
    process.env.TELEMETRY_CSV_PATH ||
    'exports/telemetry-export.csv'
  ).trim();
  const resolvedPath = path.resolve(process.cwd(), configuredPath);
  const sampleSize = clamp(
    parsePositiveInteger(process.env.CHATBOX_TELEMETRY_CSV_SAMPLE_SIZE, DEFAULT_CSV_SAMPLE_SIZE),
    1,
    MAX_CSV_SAMPLE_SIZE,
  );

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
      temperatureAvg: round(average(temperatures), 1),
      humidityAvg: round(average(humidities), 1),
      luxAvg: round(average(luxValues), 0),
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

function detectDangerReasons(latest: TelemetryDocument): string[] {
  const reasons: string[] = [];
  if (latest.sensor_fault) {
    reasons.push('Sensor fault flag is active.');
  }

  const temperature = asNumber(latest.temperature);
  const humidity = asNumber(latest.humidity);
  const lux = asNumber(latest.lux);

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

function buildDeterministicSuggestions(summary: TelemetrySummary, maxSuggestions: number): string[] {
  const output: string[] = [];
  const latest = summary.latest;
  const dangerReasons = summary.dangerReasons;

  for (const reason of dangerReasons) {
    if (reason.toLowerCase().includes('humidity too low')) {
      output.push('Độ ẩm đang thấp, nên kiểm tra bộ phun sương và nguồn nước ngay.');
    } else if (reason.toLowerCase().includes('humidity too high')) {
      output.push('Độ ẩm đang cao, ưu tiên tăng thông gió và giảm thời gian phun sương.');
    } else if (reason.toLowerCase().includes('temperature too low')) {
      output.push('Nhiệt độ thấp, cân nhắc tăng sưởi và giảm quạt để ổn định môi trường.');
    } else if (reason.toLowerCase().includes('temperature too high')) {
      output.push('Nhiệt độ cao, nên giảm sưởi và tăng lưu thông khí để hạ nhiệt.');
    } else if (reason.toLowerCase().includes('lux too low')) {
      output.push('Ánh sáng thấp, có thể tăng thời lượng/bật đèn theo chu kỳ an toàn.');
    } else if (reason.toLowerCase().includes('lux too high')) {
      output.push('Ánh sáng cao, nên giảm độ sáng hoặc rút ngắn thời lượng chiếu.');
    } else if (reason.toLowerCase().includes('sensor fault')) {
      output.push('Có lỗi cảm biến, nên kiểm tra kết nối cảm biến trước khi áp dụng thay đổi lớn.');
    }
  }

  if (output.length === 0 && latest.user_override) {
    output.push('Bạn đang ở chế độ user override, nên theo dõi cảnh báo an toàn trước khi giữ trạng thái thủ công quá lâu.');
  }

  if (output.length === 0) {
    output.push('Môi trường đang tương đối ổn định, tiếp tục theo dõi xu hướng nhiệt độ, độ ẩm và ánh sáng.');
    output.push('Có thể đặt lịch kiểm tra cảm biến định kỳ để tránh sai lệch dữ liệu kéo dài.');
  }

  return [...new Set(output)].slice(0, maxSuggestions);
}

async function loadTelemetrySummary(db: Db, deviceId: string): Promise<TelemetrySummary | null> {
  const windowSize = clamp(
    parsePositiveInteger(process.env.CHATBOX_TELEMETRY_WINDOW_SIZE, DEFAULT_TELEMETRY_WINDOW_SIZE),
    1,
    MAX_TELEMETRY_WINDOW_SIZE,
  );

  const latest = await db
    .collection<TelemetryDocument>('telemetry')
    .find({ userId: deviceId })
    .sort({ timestamp: -1 })
    .limit(1)
    .next();

  if (!latest) return null;

  const recent = await db
    .collection<TelemetryDocument>('telemetry')
    .find({ userId: deviceId })
    .sort({ timestamp: -1 })
    .limit(windowSize)
    .toArray();

  const csv = await loadCsvContext(deviceId);
  const dangerReasons = detectDangerReasons(latest);

  const temperatures = recent.map((item) => asNumber(item.temperature));
  const humidities = recent.map((item) => asNumber(item.humidity));
  const luxValues = recent.map((item) => asNumber(item.lux));

  return {
    latest: {
      timestamp: toUtc7Iso(latest.timestamp) ?? null,
      temperature: asNumber(latest.temperature),
      humidity: asNumber(latest.humidity),
      lux: asNumber(latest.lux),
      sensor_fault: latest.sensor_fault,
      user_override: latest.user_override,
      relays: latest.relays,
    },
    recent: {
      count: recent.length,
      temperatureAvg: round(average(temperatures), 1),
      humidityAvg: round(average(humidities), 1),
      luxAvg: round(average(luxValues), 0),
      temperatureMin: round(minValue(temperatures), 1),
      temperatureMax: round(maxValue(temperatures), 1),
      humidityMin: round(minValue(humidities), 1),
      humidityMax: round(maxValue(humidities), 1),
      luxMin: round(minValue(luxValues), 0),
      luxMax: round(maxValue(luxValues), 0),
    },
    csv,
    dangerReasons,
  };
}

function parseChatHistory(raw: unknown): ChatHistoryMessage[] {
  if (!Array.isArray(raw)) return [];
  const maxTurns = clamp(
    parsePositiveInteger(process.env.CHATBOX_MAX_HISTORY_TURNS, DEFAULT_CHAT_HISTORY_TURNS),
    1,
    MAX_CHAT_HISTORY_TURNS,
  );

  const normalized: ChatHistoryMessage[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
    const roleRaw = (item as Record<string, unknown>).role;
    const contentRaw = (item as Record<string, unknown>).content;
    const role = roleRaw === 'user' || roleRaw === 'assistant' ? roleRaw : null;
    const content = typeof contentRaw === 'string' ? contentRaw.trim() : '';
    if (!role || !content) continue;
    normalized.push({
      role,
      content: content.slice(0, 2000),
    });
  }

  const maxMessages = maxTurns * 2;
  return normalized.slice(-maxMessages);
}

function parseChatMode(raw: unknown): ChatRequestMode {
  return raw === 'context' ? 'context' : 'chat';
}

function buildChatHistoryContext(history: ChatHistoryMessage[]): ChatHistoryContext {
  let userTurns = 0;
  let assistantTurns = 0;
  let lastUserMessage: string | null = null;
  let lastAssistantMessage: string | null = null;

  for (const entry of history) {
    if (entry.role === 'user') {
      userTurns += 1;
      lastUserMessage = entry.content;
    } else if (entry.role === 'assistant') {
      assistantTurns += 1;
      lastAssistantMessage = entry.content;
    }
  }

  return {
    totalMessages: history.length,
    userTurns,
    assistantTurns,
    lastUserMessage,
    lastAssistantMessage,
    recentTranscript: history.slice(-10),
  };
}

function formatMetric(value: number | null, digits = 1): string {
  if (value === null) return 'n/a';
  return value.toFixed(digits);
}

function buildContextFallbackAnswer(summary: TelemetrySummary, historyContext: ChatHistoryContext): string {
  const latest = summary.latest;
  const danger = summary.dangerReasons.length > 0
    ? summary.dangerReasons.join(' ')
    : 'No critical danger flags from latest telemetry.';

  return [
    'Context snapshot from telemetry + chat history:',
    `Temp ${formatMetric(latest.temperature, 1)}C, humidity ${formatMetric(latest.humidity, 1)}%, lux ${formatMetric(latest.lux, 0)}.`,
    `History messages: ${historyContext.totalMessages} (user ${historyContext.userTurns}, assistant ${historyContext.assistantTurns}).`,
    `Safety note: ${danger}`,
  ].join(' ');
}

function extractJsonObject(rawText: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(rawText);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    // fallback below
  }

  const match = rawText.match(/\{[\s\S]*\}/);
  if (!match) return null;

  try {
    const parsed = JSON.parse(match[0]);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function sanitizeSuggestions(raw: unknown, fallback: string[]): string[] {
  const maxSuggestions = clamp(
    parsePositiveInteger(process.env.CHATBOX_MAX_SUGGESTIONS, DEFAULT_MAX_SUGGESTIONS),
    1,
    MAX_MAX_SUGGESTIONS,
  );

  if (!Array.isArray(raw)) {
    return fallback.slice(0, maxSuggestions);
  }

  const suggestions = raw
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
    .map((item) => item.slice(0, 220));

  if (suggestions.length === 0) {
    return fallback.slice(0, maxSuggestions);
  }

  return [...new Set(suggestions)].slice(0, maxSuggestions);
}

function sanitizeAnswer(raw: unknown, fallback: string): string {
  if (typeof raw !== 'string') return fallback;
  const trimmed = raw.trim();
  if (!trimmed) return fallback;
  return trimmed.slice(0, 2500);
}

function normalizeModelContent(content: unknown): string | null {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return null;

  const textParts: string[] = [];
  for (const part of content) {
    if (typeof part === 'string') {
      textParts.push(part);
      continue;
    }
    if (!part || typeof part !== 'object' || Array.isArray(part)) {
      continue;
    }
    const textValue = (part as Record<string, unknown>).text;
    if (typeof textValue === 'string') {
      textParts.push(textValue);
    }
  }

  const joined = textParts.join('\n').trim();
  return joined.length > 0 ? joined : null;
}

async function callOpenRouter(messages: OpenRouterMessage[]): Promise<string> {
  const apiKey = (process.env.OPENROUTER_API_KEY || '').trim();
  if (!apiKey) {
    throw new Error('OPENROUTER_API_KEY is not configured.');
  }

  const model = (process.env.OPENROUTER_CHAT_MODEL || process.env.OPENROUTER_MODEL || 'google/gemma-3-27b-it:free').trim();
  const baseUrl = (process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1').trim().replace(/\/+$/, '');
  const httpReferer = (process.env.OPENROUTER_HTTP_REFERER || '').trim();
  const appName = (process.env.OPENROUTER_APP_NAME || 'Hermit Home Chatbox').trim();
  const temperature = parseTemperature(process.env.OPENROUTER_CHAT_TEMPERATURE, DEFAULT_TEMPERATURE);
  const maxTokens = clamp(
    parsePositiveInteger(process.env.OPENROUTER_CHAT_MAX_TOKENS, DEFAULT_MAX_COMPLETION_TOKENS),
    128,
    4000,
  );

  const endpoint = `${baseUrl}/chat/completions`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
  if (httpReferer) headers['HTTP-Referer'] = httpReferer;
  if (appName) headers['X-Title'] = appName;

  const requestBody: Record<string, unknown> = {
    model,
    messages,
    temperature,
    max_tokens: maxTokens,
    response_format: { type: 'json_object' },
  };

  let response = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    requestBody.response_format = undefined;
    response = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(requestBody),
    });
  }

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenRouter request failed (${response.status}): ${errorText.slice(0, 300)}`);
  }

  const json = (await response.json()) as Record<string, unknown>;
  const choices = json.choices;
  if (!Array.isArray(choices) || choices.length === 0) {
    throw new Error('OpenRouter returned no choices.');
  }

  const firstChoice = choices[0];
  if (!firstChoice || typeof firstChoice !== 'object' || Array.isArray(firstChoice)) {
    throw new Error('OpenRouter first choice is invalid.');
  }

  const message = (firstChoice as Record<string, unknown>).message;
  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    throw new Error('OpenRouter message payload is invalid.');
  }

  const content = normalizeModelContent((message as Record<string, unknown>).content);
  if (!content) {
    throw new Error('OpenRouter content is empty.');
  }

  return content;
}

function buildSystemPrompt(): string {
  return [
    'Bạn là trợ lý Hermit Home cho nuôi ốc mượn hồn.',
    'Luôn trả lời ngắn gọn, thực tế, ưu tiên an toàn động vật.',
    'Dựa trên context telemetry được cung cấp.',
    'Nếu dữ liệu thiếu hoặc mâu thuẫn, nói rõ giới hạn.',
    'Luôn trả về JSON object hợp lệ với keys: answer, suggestions.',
    'suggestions là mảng 1-5 gợi ý hành động cụ thể cho người dùng.',
    'Không trả markdown, không thêm text ngoài JSON.',
  ].join(' ');
}

function buildUserPrompt(params: {
  mode: 'suggestions' | 'chat' | 'context';
  question: string | null;
  summary: TelemetrySummary;
  historyContext?: ChatHistoryContext | null;
  requestContext?: boolean;
  fallbackSuggestions: string[];
}): string {
  const payload: Record<string, unknown> = {
    mode: params.mode,
    question: params.question,
    telemetry_summary: params.summary,
    chat_history_context: params.historyContext ?? null,
    request_context: params.requestContext ?? false,
    safety_thresholds: SAFETY_THRESHOLDS,
    fallback_suggestions: params.fallbackSuggestions,
    output_schema: {
      answer: 'string',
      suggestions: 'string[]',
    },
  };
  return JSON.stringify(payload);
}

async function handleSuggestionGet(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  try {
    const { db } = await connectToDatabase();
    const summary = await loadTelemetrySummary(db, deviceId);
    if (!summary) {
      res.status(404).json({ error: 'No telemetry found for this device.' });
      return;
    }

    const maxSuggestions = clamp(
      parsePositiveInteger(process.env.CHATBOX_MAX_SUGGESTIONS, DEFAULT_MAX_SUGGESTIONS),
      1,
      MAX_MAX_SUGGESTIONS,
    );
    const fallbackSuggestions = buildDeterministicSuggestions(summary, maxSuggestions);

    let answer = 'Đây là các gợi ý dựa trên telemetry hiện tại.';
    let suggestions = fallbackSuggestions;

    try {
      const rawText = await callOpenRouter([
        { role: 'system', content: buildSystemPrompt() },
        {
          role: 'user',
          content: buildUserPrompt({
            mode: 'suggestions',
            question: null,
            summary,
            fallbackSuggestions,
          }),
        },
      ]);
      const parsed = extractJsonObject(rawText);
      answer = sanitizeAnswer(parsed?.answer, answer);
      suggestions = sanitizeSuggestions(parsed?.suggestions, fallbackSuggestions);
    } catch (modelError: unknown) {
      await insertDiagnosticLog({
        deviceId,
        userId: req.user.userId,
        source: 'api',
        category: 'AI',
        status: 'INFO',
        message: '[INFO] Chatbox suggestion fallback used due to model failure.',
        metadata: {
          endpoint: '/api/devices/[deviceId]/chatbox',
          method: 'GET',
          error: modelError instanceof Error ? modelError.message : 'unknown error',
        },
      });
    }

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'AI',
      status: 'PASS',
      message: '[PASS] Chatbox suggestions generated.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/chatbox',
        method: 'GET',
        suggestionCount: suggestions.length,
      },
    });

    res.status(200).json({
      success: true,
      mode: 'suggestions',
      deviceId,
      answer,
      suggestions,
      summary,
    });
  } catch (error: unknown) {
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'AI',
      status: 'FAIL',
      message: '[FAIL] Chatbox suggestions request failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/chatbox',
        method: 'GET',
        error: error instanceof Error ? error.message : 'unknown error',
      },
    });

    res.status(500).json({ error: 'Failed to generate chatbox suggestions.' });
  }
}

async function handleChatPost(
  req: AuthenticatedRequest,
  res: VercelResponse,
  deviceId: string,
): Promise<void> {
  const body = req.body;
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    res.status(400).json({ error: 'Request body must be a JSON object.' });
    return;
  }

  const bodyRecord = body as Record<string, unknown>;
  const questionRaw = bodyRecord.message;
  const question = typeof questionRaw === 'string' ? questionRaw.trim() : '';
  if (!question) {
    res.status(400).json({ error: '`message` is required and must be a non-empty string.' });
    return;
  }

  const history = parseChatHistory(bodyRecord.history);
  const chatMode = parseChatMode(bodyRecord.mode);
  const requestContext = bodyRecord.requestContext === true || chatMode === 'context';
  const historyContext = buildChatHistoryContext(history);

  try {
    const { db } = await connectToDatabase();
    const summary = await loadTelemetrySummary(db, deviceId);
    if (!summary) {
      res.status(404).json({ error: 'No telemetry found for this device.' });
      return;
    }

    const maxSuggestions = clamp(
      parsePositiveInteger(process.env.CHATBOX_MAX_SUGGESTIONS, DEFAULT_MAX_SUGGESTIONS),
      1,
      MAX_MAX_SUGGESTIONS,
    );
    const fallbackSuggestions = buildDeterministicSuggestions(summary, maxSuggestions);
    const fallbackAnswer = requestContext
      ? buildContextFallbackAnswer(summary, historyContext)
      : 'Mình chưa gọi được model, đây là gợi ý an toàn hiện tại dựa trên telemetry.';

    const messages: OpenRouterMessage[] = [
      { role: 'system', content: buildSystemPrompt() },
      ...history,
      {
        role: 'user',
        content: buildUserPrompt({
          mode: requestContext ? 'context' : 'chat',
          question: question.slice(0, 2000),
          summary,
          historyContext,
          requestContext,
          fallbackSuggestions,
        }),
      },
    ];

    let answer = fallbackAnswer;
    let suggestions = fallbackSuggestions;

    try {
      const rawText = await callOpenRouter(messages);
      const parsed = extractJsonObject(rawText);
      answer = sanitizeAnswer(parsed?.answer, fallbackAnswer);
      suggestions = sanitizeSuggestions(parsed?.suggestions, fallbackSuggestions);
    } catch (modelError: unknown) {
      await insertDiagnosticLog({
        deviceId,
        userId: req.user.userId,
        source: 'api',
        category: 'AI',
        status: 'INFO',
        message: '[INFO] Chatbox fallback answer used due to model failure.',
        metadata: {
          endpoint: '/api/devices/[deviceId]/chatbox',
          method: 'POST',
          error: modelError instanceof Error ? modelError.message : 'unknown error',
        },
      });
    }

    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'AI',
      status: 'PASS',
      message: '[PASS] Chatbox response generated.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/chatbox',
        method: 'POST',
        questionLength: question.length,
        mode: requestContext ? 'context' : 'chat',
        suggestionCount: suggestions.length,
      },
    });

    const responsePayload: Record<string, unknown> = {
      success: true,
      mode: requestContext ? 'context' : 'chat',
      deviceId,
      answer,
      suggestions,
      summary,
      historyContext,
    };

    if (requestContext) {
      responsePayload.context = {
        telemetry: summary,
        chat_history: historyContext,
      };
    }

    res.status(200).json(responsePayload);
  } catch (error: unknown) {
    await insertDiagnosticLog({
      deviceId,
      userId: req.user.userId,
      source: 'api',
      category: 'AI',
      status: 'FAIL',
      message: '[FAIL] Chatbox request failed.',
      metadata: {
        endpoint: '/api/devices/[deviceId]/chatbox',
        method: 'POST',
        error: error instanceof Error ? error.message : 'unknown error',
      },
    });

    res.status(500).json({ error: 'Failed to process chatbox request.' });
  }
}

const authenticatedHandler = withAuth(async (
  req: AuthenticatedRequest,
  res: VercelResponse,
): Promise<void> => {
  const deviceId = resolveAuthorizedDeviceId(req, res);
  if (!deviceId) return;

  if (req.method === 'GET') {
    await handleSuggestionGet(req, res, deviceId);
    return;
  }

  if (req.method === 'POST') {
    await handleChatPost(req, res, deviceId);
    return;
  }

  methodNotAllowed(req, res, ALLOWED_METHODS);
});

export default async function handler(
  req: VercelRequest,
  res: VercelResponse,
): Promise<void> {
  if (handleApiPreflight(req, res, ALLOWED_METHODS)) {
    return;
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(req, res, ALLOWED_METHODS);
    return;
  }

  await authenticatedHandler(req, res);
}
