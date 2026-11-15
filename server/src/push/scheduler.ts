import type { FastifyBaseLogger } from 'fastify';
import { APP_NAME } from '../appName.js';
import type { AppConfig } from '../config.js';
import { candidateFromUser } from '../matchmaking/compat.js';
import type { Matchmaker } from '../matchmaking/Matchmaker.js';
import type { Store } from '../store/Store.js';
import { errMessage, localHour, type Clock } from '../util.js';
import type { PushProvider } from './PushProvider.js';

export interface PushSchedulerDeps {
  config: AppConfig['push'] & Pick<AppConfig, 'repairCooldownHours'>;
  clock: Clock;
  store: Store;
  matchmaker: Matchmaker;
  push: PushProvider;
  log: FastifyBaseLogger;
}

const BATCH = 500;

/**
 * Sends "N compatible singles are online now".
 * Limits (SPEC section 1): opt-in only, at most one per user per 4 h, only when N >= 3, and never
 * to someone who is online themselves. Additionally only between 09:00 and 23:00 user-local time.
 */
export class OnlinePushScheduler {
  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(private readonly deps: PushSchedulerDeps) {}

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => void this.runOnce(), this.deps.config.schedulerIntervalSec * 1000);
    this.timer.unref();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  /** One pass over eligible users. Returns how many notifications were sent. */
  async runOnce(): Promise<number> {
    if (this.running) return 0;
    this.running = true;
    try {
      return await this.pass();
    } catch (err) {
      this.deps.log.error({ err: errMessage(err) }, 'online push pass failed');
      return 0;
    } finally {
      this.running = false;
    }
  }

  private async pass(): Promise<number> {
    const { config, clock, store, matchmaker, push, log } = this.deps;
    // Nobody can have N compatible people online if fewer than N people are online at all.
    if (matchmaker.onlineCount() < config.minCompatible) return 0;

    const now = clock.now();
    const notifiedBefore = new Date(now - config.minIntervalHours * 3_600_000);
    const pairedSince = new Date(now - config.repairCooldownHours * 3_600_000);
    const users = await store.listPushCandidates(notifiedBefore, BATCH);
    let sent = 0;
    for (const user of users) {
      if (user.apnsToken === null || matchmaker.isOnline(user.id)) continue;
      const hour = localHour(now, user.tzOffsetMinutes);
      if (hour < config.localHourStart || hour >= config.localHourEnd) continue;
      const candidate = candidateFromUser(user, await store.listExclusions(user.id, pairedSince), now);
      if (!candidate) continue;
      const n = matchmaker.compatibleOnline(candidate, now);
      if (n < config.minCompatible) continue;

      // Record first so a crash or slow APNs call can never produce a second push inside the window.
      await store.updateUser(user.id, { lastOnlinePushAt: new Date(now) });
      const result = await push.send(user.apnsToken, {
        title: APP_NAME,
        body: `${n} compatible singles are online now`,
        collapseId: 'online-singles',
        data: { kind: 'online_singles', count: String(n) },
      });
      if (result.ok) sent += 1;
      else if (result.unregistered === true) await store.updateUser(user.id, { apnsToken: null, pushEnabled: false });
      else log.warn({ reason: result.reason }, 'online push not delivered');
    }
    return sent;
  }
}
