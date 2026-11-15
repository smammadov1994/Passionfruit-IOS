import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config.js';
import type { CallService } from '../realtime/CallService.js';
import { COPY } from '../realtime/copy.js';
import type { DateEngine } from '../realtime/DateEngine.js';
import type { Hub } from '../realtime/Hub.js';
import { CALL_PREFIX } from '../realtime/protocol.js';
import type { AccountService } from '../services/accounts.js';
import type { Store } from '../store/Store.js';
import type { ModerationAction, ModerationCategory } from '../types.js';
import { errMessage } from '../util.js';
import type { ModerationProvider } from './ModerationProvider.js';

export interface ModerationDeps {
  config: AppConfig['moderation'];
  provider: ModerationProvider;
  store: Store;
  hub: Hub;
  dates: DateEngine;
  calls: CallService;
  accounts: AccountService;
  log: FastifyBaseLogger;
}

/** The live session a moderation sample belongs to: a speed date or a post-match call. */
interface Target {
  kind: 'date' | 'call';
  /** As sent by the client: a date id or `call:<matchId>`. */
  dateId: string;
  matchId: string | null;
  partnerId: string;
}

/**
 * Enforcement ladder (SPEC section 1, Safety):
 *  - nudity in a frame: the date ends at once for both, the offender gets a strike;
 *  - sexual language: first offence in a date is a warning, the second ends the date with a strike;
 *  - strikes accumulate to suspension (AccountService.addStrike).
 * Frames and transcript text are inspected in memory and discarded. Only verdicts are audited.
 */
export class ModerationService {
  constructor(private readonly deps: ModerationDeps) {}

  private target(userId: string, dateId: string): Target | null {
    if (dateId.startsWith(CALL_PREFIX)) {
      const call = this.deps.calls.activeCallFor(userId, dateId);
      return call ? { kind: 'call', dateId, matchId: call.matchId, partnerId: call.partnerId } : null;
    }
    const live = this.deps.dates.liveDateFor(userId, dateId);
    return live ? { kind: 'date', dateId, matchId: null, partnerId: live.partnerId } : null;
  }

  /** Ends the session if it is still running. False means it already ended (e.g. a racing sample). */
  private end(userId: string, target: Target, category: ModerationCategory): boolean {
    return target.kind === 'call' && target.matchId !== null
      ? this.deps.calls.endForModeration(userId, target.matchId, category)
      : this.deps.dates.endForModeration(userId, target.dateId, category);
  }

  async handleFrame(userId: string, dateId: string, jpeg: Buffer): Promise<ModerationAction> {
    const { provider, config, store, accounts, log } = this.deps;
    if (!this.target(userId, dateId)) return 'none';
    let score: number;
    try {
      score = (await provider.classifyFrame(jpeg)).nudityScore;
    } catch (err) {
      // Fail open: a vendor outage must not end everyone's dates. Operators alert on this log line.
      log.error({ provider: provider.name, err: errMessage(err) }, 'frame moderation failed');
      return 'none';
    }
    if (score < config.nudityThreshold) return 'none';

    // Re-resolve: the date may have ended while the classifier was running.
    const target = this.target(userId, dateId);
    if (!target || !this.end(userId, target, 'nudity')) return 'none';
    await store.addAudit({
      type: 'moderation.frame',
      userId,
      targetUserId: target.partnerId,
      dateId,
      matchId: target.matchId,
      category: 'nudity',
      action: 'end',
      details: { provider: provider.name, score: Math.round(score * 1000) / 1000 },
    });
    await accounts.addStrike(userId, { category: 'nudity', dateId, partnerId: target.partnerId });
    return 'end';
  }

  async handleTranscript(userId: string, dateId: string, text: string): Promise<ModerationAction> {
    const { provider, store, hub, accounts, dates, calls, log } = this.deps;
    if (!this.target(userId, dateId)) return 'none';
    let verdict;
    try {
      verdict = await provider.classifyText(text);
    } catch (err) {
      log.error({ provider: provider.name, err: errMessage(err) }, 'transcript moderation failed');
      return 'none';
    }
    if (!verdict.sexualLanguage) return 'none';

    const target = this.target(userId, dateId);
    if (!target) return 'none';
    const offences =
      target.kind === 'call' && target.matchId !== null
        ? calls.recordSexualLanguage(userId, target.matchId)
        : dates.recordSexualLanguage(userId, dateId);
    if (offences === 0) return 'none';
    const action: ModerationAction = offences === 1 ? 'warn' : 'end';

    if (action === 'warn') {
      hub.send(userId, {
        type: 'moderation.action',
        dateId,
        action: 'warn',
        category: 'sexual_language',
        message: COPY.moderationWarnSexual,
      });
    } else if (!this.end(userId, target, 'sexual_language')) {
      return 'none';
    }
    await store.addAudit({
      type: 'moderation.transcript',
      userId,
      targetUserId: target.partnerId,
      dateId,
      matchId: target.matchId,
      category: 'sexual_language',
      action,
      // References into the word list, never the words or the transcript.
      details: { provider: provider.name, offences, matches: verdict.matches },
    });
    if (action === 'end') {
      await accounts.addStrike(userId, { category: 'sexual_language', dateId, partnerId: target.partnerId });
    }
    return action;
  }

  /** Profile photos are screened with the same frame classifier. Returns false when rejected. */
  async screenPhoto(userId: string, jpeg: Buffer): Promise<boolean> {
    const { provider, config, store, log } = this.deps;
    try {
      const { nudityScore } = await provider.classifyFrame(jpeg);
      if (nudityScore < config.nudityThreshold) return true;
      await store.addAudit({
        type: 'moderation.photo',
        userId,
        category: 'nudity',
        action: 'rejected',
        details: { provider: provider.name, score: Math.round(nudityScore * 1000) / 1000 },
      });
      return false;
    } catch (err) {
      log.error({ provider: provider.name, err: errMessage(err) }, 'photo moderation failed');
      return true;
    }
  }
}
