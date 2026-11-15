import { tooMany } from '../errors.js';
import type { Clock } from '../util.js';

interface Bucket {
  windowStart: number;
  count: number;
}

export interface RateRule {
  /** Namespace so different endpoints do not share a budget. */
  name: string;
  max: number;
  windowMs: number;
}

/**
 * Fixed-window rate limiter held in process memory. For multi-instance deployments swap the
 * `hit` body for a Redis `INCR` + `PEXPIRE` on the same key (README "Scaling beyond one instance").
 */
export class RateLimiter {
  private readonly buckets = new Map<string, Bucket>();
  private lastSweep = 0;

  constructor(private readonly clock: Clock) {}

  /** Returns true when the call is allowed. */
  hit(rule: RateRule, subject: string): boolean {
    const now = this.clock.now();
    this.sweep(now);
    const key = `${rule.name}:${subject}`;
    const bucket = this.buckets.get(key);
    if (!bucket || now - bucket.windowStart >= rule.windowMs) {
      this.buckets.set(key, { windowStart: now, count: 1 });
      return true;
    }
    bucket.count += 1;
    return bucket.count <= rule.max;
  }

  enforce(rule: RateRule, subject: string): void {
    if (!this.hit(rule, subject)) throw tooMany('Slow down a little and try again in a moment.');
  }

  private sweep(now: number): void {
    if (now - this.lastSweep < 60_000) return;
    this.lastSweep = now;
    for (const [key, bucket] of this.buckets) {
      // Longest configured window is one hour.
      if (now - bucket.windowStart > 3_600_000) this.buckets.delete(key);
    }
  }
}

export const RATE_RULES = {
  auth: { name: 'auth', max: 10, windowMs: 60_000 },
  report: { name: 'report', max: 10, windowMs: 3_600_000 },
  block: { name: 'block', max: 30, windowMs: 3_600_000 },
  frame: { name: 'frame', max: 40, windowMs: 60_000 },
  transcript: { name: 'transcript', max: 90, windowMs: 60_000 },
  message: { name: 'message', max: 60, windowMs: 60_000 },
  photo: { name: 'photo', max: 20, windowMs: 3_600_000 },
  iap: { name: 'iap', max: 20, windowMs: 60_000 },
  webhook: { name: 'webhook', max: 300, windowMs: 60_000 },
} as const satisfies Record<string, RateRule>;
