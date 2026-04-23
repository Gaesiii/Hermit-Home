import type { VercelRequest } from '@vercel/node';

type QueryPatch = Record<string, string | string[]>;

export function patchQuery(req: VercelRequest, patch: QueryPatch): void {
  const current = req.query && typeof req.query === 'object' ? req.query : {};
  (req as VercelRequest & { query: Record<string, unknown> }).query = {
    ...current,
    ...patch,
  };
}
