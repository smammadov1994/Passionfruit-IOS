import { randomUUID } from 'node:crypto';

export interface Clock {
  now(): number;
}
export const systemClock: Clock = { now: () => Date.now() };

export const newId = (): string => randomUUID();
export const iso = (d: Date | number): string => new Date(d).toISOString();

const BIRTHDATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** True for a real calendar date in YYYY-MM-DD form. */
export function isValidBirthdate(value: string): boolean {
  const m = BIRTHDATE_RE.exec(value);
  if (!m) return false;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d && y >= 1900;
}

/** Whole years between a YYYY-MM-DD birthdate and `nowMs` (UTC calendar). Returns -1 if unparseable. */
export function ageFromBirthdate(birthdate: string, nowMs: number): number {
  const m = BIRTHDATE_RE.exec(birthdate);
  if (!m) return -1;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const now = new Date(nowMs);
  let age = now.getUTCFullYear() - y;
  const beforeBirthday =
    now.getUTCMonth() + 1 < mo || (now.getUTCMonth() + 1 === mo && now.getUTCDate() < d);
  if (beforeBirthday) age -= 1;
  return age;
}

const EARTH_RADIUS_KM = 6371.0088;
const rad = (deg: number): number => (deg * Math.PI) / 180;

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Start of the user's current local day and the next one, as UTC epoch ms. */
export function localDayBounds(nowMs: number, tzOffsetMinutes: number): { start: number; end: number } {
  const offsetMs = tzOffsetMinutes * 60_000;
  const DAY = 86_400_000;
  const start = Math.floor((nowMs + offsetMs) / DAY) * DAY - offsetMs;
  return { start, end: start + DAY };
}

export function localHour(nowMs: number, tzOffsetMinutes: number): number {
  return new Date(nowMs + tzOffsetMinutes * 60_000).getUTCHours();
}

/** Order-independent key for a pair of user ids. */
export const pairKey = (a: string, b: string): string => (a < b ? `${a}|${b}` : `${b}|${a}`);

/** Fisher-Yates shuffle using the supplied RNG; returns a new array. */
export function shuffled<T>(items: readonly T[], rng: () => number): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = out[i] as T;
    out[i] = out[j] as T;
    out[j] = tmp;
  }
  return out;
}

export function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
