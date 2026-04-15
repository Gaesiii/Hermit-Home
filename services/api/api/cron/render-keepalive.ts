import type { VercelRequest, VercelResponse } from '@vercel/node';
import { handleApiPreflight, methodNotAllowed } from '../../lib/http';

const DEFAULT_TIMEOUT_MS = 10_000;
const USER_AGENT = 'hermit-home-keepalive/1.0';

function readHeaderValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0] ?? null;
  }

  return null;
}

function parseTimeoutMs(rawValue: string | undefined): number {
  if (!rawValue) {
    return DEFAULT_TIMEOUT_MS;
  }

  const parsed = Number.parseInt(rawValue, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_TIMEOUT_MS;
  }

  return parsed;
}

export default async function handler(
  req: VercelRequest,
  res: VercelResponse
): Promise<void> {
  const allowedMethods = ['GET'] as const;
  if (handleApiPreflight(req, res, allowedMethods)) {
    return;
  }

  if (req.method !== 'GET') {
    methodNotAllowed(req, res, allowedMethods);
    return;
  }

  const cronSecret = process.env.CRON_SECRET || '';
  if (cronSecret) {
    const authHeader = readHeaderValue(req.headers.authorization);
    if (authHeader !== `Bearer ${cronSecret}`) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
  }

  const targetUrl = (process.env.RENDER_KEEPALIVE_URL || '').trim();
  if (!targetUrl) {
    res.status(500).json({
      error: 'Missing required environment variable: RENDER_KEEPALIVE_URL',
    });
    return;
  }

  try {
    new URL(targetUrl);
  } catch {
    res.status(500).json({
      error: 'RENDER_KEEPALIVE_URL must be a valid absolute URL.',
    });
    return;
  }

  const timeoutMs = parseTimeoutMs(process.env.RENDER_KEEPALIVE_TIMEOUT_MS);
  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), timeoutMs);

  const startedAt = Date.now();
  try {
    const response = await fetch(targetUrl, {
      method: 'GET',
      headers: { 'User-Agent': USER_AGENT },
      redirect: 'follow',
      signal: controller.signal,
    });

    const durationMs = Date.now() - startedAt;
    clearTimeout(timeoutHandle);

    if (!response.ok) {
      res.status(502).json({
        success: false,
        status: response.status,
        target: targetUrl,
        durationMs,
      });
      return;
    }

    res.status(200).json({
      success: true,
      status: response.status,
      target: targetUrl,
      durationMs,
      timestamp: new Date().toISOString(),
    });
  } catch (error: unknown) {
    clearTimeout(timeoutHandle);
    const message =
      error instanceof Error ? error.message : 'Unknown keepalive failure';

    res.status(502).json({
      success: false,
      error: 'Failed to ping Render keepalive endpoint.',
      message,
      target: targetUrl,
    });
  }
}
