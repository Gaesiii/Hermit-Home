import type { VercelRequest, VercelResponse } from '@vercel/node';

const DEFAULT_ALLOWED_HEADERS = [
  'Content-Type',
  'Authorization',
  'Accept',
  'X-API-Key',
];

const DEFAULT_ALLOWED_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'];

function formatAllowedMethods(allowedMethods: readonly string[]): string {
  return allowedMethods.join(', ');
}

export function applyDefaultApiHeaders(
  res: VercelResponse,
  allowedMethods: readonly string[] = DEFAULT_ALLOWED_METHODS,
): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', formatAllowedMethods(allowedMethods));
  res.setHeader('Access-Control-Allow-Headers', DEFAULT_ALLOWED_HEADERS.join(', '));
  res.setHeader('Access-Control-Max-Age', '86400');
}

export function handleApiPreflight(
  req: VercelRequest,
  res: VercelResponse,
  allowedMethods: readonly string[],
): boolean {
  applyDefaultApiHeaders(res, [...allowedMethods, 'OPTIONS']);
  res.setHeader('Allow', formatAllowedMethods([...allowedMethods, 'OPTIONS']));

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }

  return false;
}

export function methodNotAllowed(
  req: VercelRequest,
  res: VercelResponse,
  allowedMethods: readonly string[],
): void {
  applyDefaultApiHeaders(res, [...allowedMethods, 'OPTIONS']);
  res.setHeader('Allow', formatAllowedMethods([...allowedMethods, 'OPTIONS']));
  res.status(405).json({
    error: `Method '${req.method}' is not allowed.`,
  });
}
