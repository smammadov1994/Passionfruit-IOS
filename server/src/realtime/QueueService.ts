import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config.js';
import { candidateFromUser, type Candidate } from '../matchmaking/compat.js';
import type { Matchmaker } from '../matchmaking/Matchmaker.js';
import type { UsageService } from '../services/usage.js';
import type { Store } from '../store/Store.js';
import type { UserRecord } from '../types.js';
import { ageFromBirthdate, errMessage, iso, type Clock } from '../util.js';
import { COPY } from './copy.js';
import type { DateEngine } from './DateEngine.js';
import type { Hub } from './Hub.js';
import type { ServerMessage } from './protocol.js';

export interface QueueDeps {
  config: Pick<AppConfig, 'queueStatusIntervalSec' | 'repairCooldownHours'>;
  clock: Clock;
  hub: Hub;
  store: Store;
  matchmaker: Matchmaker;
  dates: DateEngine;
  usage: UsageService;
  log: FastifyBaseLogger;
  /** True when the user is on a post-match call and so cannot be queued. */
  inCall: (userId: string) => boolean;
}

/** If the suspension has an end date that has passed, lifts it. Returns the up-to-date user. */
export async function resolveSuspension(store: Store, user: UserRecord, nowMs: number): Promise<UserRecord> {
  if (user.suspended && user.suspendedUntil !== null && user.suspendedUntil.getTime() <= nowMs) {
    return (await store.updateUser(user.id, { suspended: false, suspendedUntil: null })) ?? user;
  }
  return user;
}

export function suspendedMessage(user: UserRecord): ServerMessage {
  return user.suspendedUntil !== null
    ? { type: 'account.suspended', until: iso(user.suspendedUntil), reason: COPY.suspendedUntil }
    : { type: 'account.suspended', reason: COPY.suspendedPendingReview };
}

/** Presence, the waiting queue, pairing and the periodic `queue.status` broadcast. */
export class QueueService {
  private ticker: NodeJS.Timeout | null = null;

  constructor(private readonly deps: QueueDeps) {}

  start(): void {
    if (this.ticker) return;
    this.ticker = setInterval(() => this.tick(), this.deps.config.queueStatusIntervalSec * 1000);
    this.ticker.unref();
  }

  stop(): void {
    if (this.ticker) clearInterval(this.ticker);
    this.ticker = null;
  }

  /** Builds the matchmaking snapshot for a user, including who they may not be paired with. */
  async buildCandidate(user: UserRecord): Promise<Candidate | null> {
    const now = this.deps.clock.now();
    const since = new Date(now - this.deps.config.repairCooldownHours * 3_600_000);
    const [exclusions, stats] = await Promise.all([
      this.deps.store.listExclusions(user.id, since),
      this.deps.store.getDateStats(user.id),
    ]);
    return candidateFromUser(user, exclusions, now, stats);
  }

  /** Marks a freshly connected user as online so they count toward other people's "online now". */
  async handleConnect(userId: string): Promise<void> {
    await this.refresh(userId);
  }

  handleDisconnect(userId: string): void {
    this.deps.matchmaker.setOffline(userId);
  }

  /** Re-reads a connected user's profile into live state (after profile, filter or premium changes). */
  async refresh(userId: string): Promise<void> {
    const { store, hub, matchmaker } = this.deps;
    if (!hub.isConnected(userId)) return;
    const user = await store.getUser(userId);
    if (!user || user.suspended || !user.onboardingComplete) {
      matchmaker.setOffline(userId);
      return;
    }
    const candidate = await this.buildCandidate(user);
    if (!hub.isConnected(userId)) return;
    if (candidate) matchmaker.setOnline(candidate);
    else matchmaker.setOffline(userId);
  }

  async join(userId: string): Promise<void> {
    const { store, hub, matchmaker, dates, usage, clock } = this.deps;
    const found = await store.getUser(userId);
    if (!found) return;
    const user = await resolveSuspension(store, found, clock.now());
    if (user.suspended) {
      matchmaker.dequeue(userId);
      hub.send(userId, suspendedMessage(user));
      return;
    }
    if (!user.onboardingComplete || user.birthdate === null) {
      hub.send(userId, { type: 'error', code: 'onboarding_incomplete', message: COPY.onboardingIncomplete });
      return;
    }
    if (ageFromBirthdate(user.birthdate, clock.now()) < 18) {
      hub.send(userId, { type: 'error', code: 'underage', message: COPY.underage });
      return;
    }
    if (dates.isBusy(userId)) {
      hub.send(userId, { type: 'error', code: 'already_in_date', message: COPY.alreadyInDate });
      return;
    }
    if (this.deps.inCall(userId)) {
      hub.send(userId, { type: 'error', code: 'in_call', message: COPY.inCall });
      return;
    }
    const current = await usage.get(user);
    if (current.capped && current.limit !== null) {
      matchmaker.dequeue(userId);
      hub.send(userId, { type: 'queue.limit', limit: current.limit, resetsAt: iso(current.resetsAt) });
      return;
    }
    const candidate = await this.buildCandidate(user);
    if (!candidate) {
      hub.send(userId, { type: 'error', code: 'onboarding_incomplete', message: COPY.onboardingIncomplete });
      return;
    }
    // The socket may have closed, or a date may have begun, while we were reading from the store.
    if (!hub.isConnected(userId) || dates.isBusy(userId)) return;
    matchmaker.setOnline(candidate);
    matchmaker.enqueue(userId, clock.now());
    this.pair();
    if (matchmaker.isQueued(userId)) this.sendStatus(userId);
  }

  leave(userId: string): void {
    this.deps.matchmaker.dequeue(userId);
  }

  /** Forms every pair that can be formed right now. */
  pair(): void {
    const { matchmaker, dates, hub, clock } = this.deps;
    for (const pair of matchmaker.takePairs(clock.now())) {
      if (!hub.isConnected(pair.first.userId) || !hub.isConnected(pair.second.userId)) {
        // Extremely narrow race with a closing socket: put the survivor back.
        for (const c of [pair.first, pair.second]) {
          if (hub.isConnected(c.userId)) matchmaker.enqueue(c.userId, clock.now());
        }
        continue;
      }
      dates.begin(pair);
    }
  }

  private sendStatus(userId: string): void {
    const { matchmaker, hub, clock } = this.deps;
    const candidate = matchmaker.getCandidate(userId);
    if (!candidate) return;
    hub.send(userId, {
      type: 'queue.status',
      compatibleOnline: matchmaker.compatibleOnline(candidate, clock.now()),
      position: matchmaker.position(userId),
    });
  }

  private tick(): void {
    try {
      this.pair();
      for (const userId of this.deps.matchmaker.queuedUserIds()) this.sendStatus(userId);
    } catch (err) {
      this.deps.log.error({ err: errMessage(err) }, 'queue tick failed');
    }
  }
}
