const UTC7_OFFSET_MS = 7 * 60 * 60 * 1000;

export function toUtc7Iso(
  value: Date | string | number | null | undefined,
): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  const utc7Date = new Date(date.getTime() + UTC7_OFFSET_MS);
  return utc7Date.toISOString().replace('Z', '+07:00');
}
