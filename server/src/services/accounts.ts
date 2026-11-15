import { createHmac } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import type { BlobStore } from '../blob/BlobStore.js';
import type { AppConfig } from '../config.js';
import type { Matchmaker } from '../matchmaking/Matchmaker.js';
import type { CallService } from '../realtime/CallService.js';
import type { DateEngine } from '../realtime/DateEngine.js';
import type { Hub } from '../realtime/Hub.js';
import { CLOSE } from '../realtime/protocol.js';
import { suspendedMessage, type QueueService } from '../realtime/QueueService.js';
import type { Store } from '../store/Store.js';
import type { MatchRecord, ModerationCategory, UserRecord } from '../types.js';
import { errMessage, type Clock } from '../util.js';

export interface AccountsDeps {
  config: Pick<AppConfig, 'strikesToSuspend' | 'jwtSecret'>;
  clock: Clock;
  store: Store;
  hub: Hub;
  matchmaker: Matchmaker;
  dates: DateEngine;
  calls: CallService;
  queue: QueueService;
  blobs: BlobStore;
  log: FastifyBaseLogger;
}

/** Cross-cutting account actions that touch both durable and live state. */
export class AccountService {
  constructor(private readonly deps: AccountsDeps) {}

  /** Keyed hash of the identity subject; lets a ban survive delete-and-recreate without keeping the subject. */
  identityHash(appleSub: string): string {
    return createHmac('sha256', this.deps.config.jwtSecret).update(`identity:${appleSub}`).digest('hex');
  }

  /** Finds or creates the account for a verified identity. */
  async signIn(appleSub: string, firstName: string | undefined): Promise<UserRecord> {
    const { store } = this.deps;
    const existing = await store.getUserByAppleSub(appleSub);
    if (existing) return existing;
    const carried = await store.takeDeletedIdentity(this.identityHash(appleSub));
    return store.createUser({
      appleSub,
      firstName: firstName ?? '',
      strikes: carried?.strikes ?? 0,
      suspended: carried?.suspended ?? false,
      suspendedUntil: carried?.suspendedUntil ?? null,
    });
  }

  /** Adds a strike; at the threshold the account is suspended pending review. */
  async addStrike(
    userId: string,
    context: { category: ModerationCategory; dateId: string; partnerId: string | null },
  ): Promise<void> {
    const { store, hub, matchmaker, config } = this.deps;
    const strikes = await store.incrementStrikes(userId);
    await store.addAudit({
      type: 'strike',
      userId,
      targetUserId: context.partnerId,
      dateId: context.dateId,
      category: context.category,
      details: { strikes },
    });
    if (strikes < config.strikesToSuspend) return;
    const user = await store.updateUser(userId, { suspended: true, suspendedUntil: null });
    if (!user) return;
    await store.addAudit({
      type: 'suspension',
      userId,
      dateId: context.dateId,
      category: context.category,
      action: 'suspended_pending_review',
      details: { strikes },
    });
    matchmaker.setOffline(userId);
    hub.send(userId, suspendedMessage(user));
  }

  /** Removes a match and tells both people. */
  async removeMatch(match: MatchRecord): Promise<void> {
    const { store, hub, calls, matchmaker } = this.deps;
    calls.handleMatchRemoved(match.id);
    await store.deleteMatch(match.id);
    matchmaker.removeExclusion(match.userA, match.userB);
    hub.send(match.userA, { type: 'match.removed', matchId: match.id });
    hub.send(match.userB, { type: 'match.removed', matchId: match.id });
    // Exclusions may still apply for other reasons (24 h cooldown); rebuild from the store.
    await Promise.all([this.deps.queue.refresh(match.userA), this.deps.queue.refresh(match.userB)]);
  }

  /** Blocks `blockedId`: never paired again, any match removed, any date between them ended. */
  async block(blockerId: string, blockedId: string): Promise<void> {
    const { store, matchmaker, dates, clock } = this.deps;
    await store.addBlock(blockerId, blockedId, new Date(clock.now()));
    matchmaker.addExclusion(blockerId, blockedId);
    if (dates.dateBetween(blockerId, blockedId) !== null) dates.forceLeave(blockerId);
    const match = await store.getMatchBetween(blockerId, blockedId);
    if (match) await this.removeMatch(match);
    matchmaker.addExclusion(blockerId, blockedId);
    await store.addAudit({ type: 'block', userId: blockerId, targetUserId: blockedId });
  }

  /** Hard-deletes the account: profile, photos, matches, messages, blocks, tokens, purchases. */
  async deleteAccount(user: UserRecord): Promise<void> {
    const { store, hub, matchmaker, dates, calls, blobs, log } = this.deps;
    dates.forceLeave(user.id);
    calls.handleDisconnect(user.id);
    matchmaker.setOffline(user.id);

    const summaries = await store.listMatchSummaries(user.id);
    for (const s of summaries) calls.handleMatchRemoved(s.match.id);

    if (user.strikes > 0 || user.suspended) {
      await store.putDeletedIdentity(this.identityHash(user.appleSub), {
        strikes: user.strikes,
        suspended: user.suspended,
        suspendedUntil: user.suspendedUntil,
      });
    }
    await store.deleteUser(user.id);
    await store.addAudit({ type: 'account.deleted', userId: user.id });

    for (const s of summaries) hub.send(s.partner.id, { type: 'match.removed', matchId: s.match.id });
    hub.close(user.id, CLOSE.accountDeleted, 'account deleted');

    // Blob cleanup last and best-effort: a storage hiccup must not resurrect the account.
    for (const url of user.photoUrls) {
      await blobs.deleteByUrl(url).catch((err: unknown) => {
        log.warn({ err: errMessage(err) }, 'photo cleanup failed after account deletion');
      });
    }
  }
}
