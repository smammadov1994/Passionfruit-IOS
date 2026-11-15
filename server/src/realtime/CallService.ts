import type { Store } from '../store/Store.js';
import type { ModerationCategory } from '../types.js';
import { COPY } from './copy.js';
import type { Hub } from './Hub.js';
import { CALL_PREFIX, type SignalPayload } from './protocol.js';

interface Call {
  matchId: string;
  inviter: string;
  invitee: string;
  state: 'ringing' | 'active';
  sexualWarnings: Map<string, number>;
  ringTimer: NodeJS.Timeout | null;
}

export interface CallDeps {
  hub: Hub;
  store: Store;
  /** True when the user is in a speed date or waiting in the queue's pairing. */
  isBusyElsewhere: (userId: string) => boolean;
  /** Called so the queue can drop someone who starts or accepts a call. */
  onCallStarted: (userId: string) => void;
  ringTimeoutMs?: number;
}

type CallSignalType = 'call.invite' | 'call.accept' | 'call.decline' | 'call.end';

/**
 * Post-match "video call again". The server only relays: invite/accept/decline/end plus
 * `rtc.signal` addressed to `call:<matchId>`, and only between the two people in that match.
 * Convention: the inviter creates the WebRTC offer once `call.accept` arrives.
 */
export class CallService {
  private readonly byMatch = new Map<string, Call>();
  private readonly byUser = new Map<string, Call>();
  private readonly ringTimeoutMs: number;

  constructor(private readonly deps: CallDeps) {
    this.ringTimeoutMs = deps.ringTimeoutMs ?? 45_000;
  }

  inCall(userId: string): boolean {
    return this.byUser.has(userId);
  }

  /** The active call `userId` is part of for this `call:<matchId>` target, if any. */
  activeCallFor(userId: string, target: string): { matchId: string; partnerId: string } | null {
    if (!target.startsWith(CALL_PREFIX)) return null;
    const call = this.byMatch.get(target.slice(CALL_PREFIX.length));
    if (!call || call.state !== 'active' || (call.inviter !== userId && call.invitee !== userId)) return null;
    return { matchId: call.matchId, partnerId: this.other(call, userId) };
  }

  async invite(userId: string, matchId: string): Promise<void> {
    const { hub, store } = this.deps;
    const match = await store.getMatch(matchId);
    if (!match || (match.userA !== userId && match.userB !== userId)) {
      return this.error(userId, 'match_not_found', COPY.matchNotFound);
    }
    const partnerId = match.userA === userId ? match.userB : match.userA;
    const me = await store.getUser(userId);
    if (!me || me.suspended) return this.error(userId, 'account_suspended', COPY.suspendedPendingReview);
    if (this.byUser.has(userId) || this.deps.isBusyElsewhere(userId)) {
      return this.error(userId, 'busy', COPY.alreadyInDate);
    }
    if (!hub.isConnected(partnerId)) return this.error(userId, 'partner_offline', COPY.partnerOffline);
    if (this.byUser.has(partnerId) || this.deps.isBusyElsewhere(partnerId)) {
      return this.error(userId, 'partner_busy', COPY.partnerBusy);
    }
    const call: Call = {
      matchId,
      inviter: userId,
      invitee: partnerId,
      state: 'ringing',
      sexualWarnings: new Map(),
      ringTimer: null,
    };
    call.ringTimer = setTimeout(() => {
      if (call.state !== 'ringing') return;
      // Nobody picked up: both sides are told the call is over.
      hub.send(call.inviter, { type: 'call.end', matchId, fromUserId: call.invitee });
      hub.send(call.invitee, { type: 'call.end', matchId, fromUserId: call.inviter });
      this.remove(call);
    }, this.ringTimeoutMs);
    this.byMatch.set(matchId, call);
    this.byUser.set(userId, call);
    this.byUser.set(partnerId, call);
    this.deps.onCallStarted(userId);
    this.deps.onCallStarted(partnerId);
    hub.send(partnerId, { type: 'call.invite', matchId, fromUserId: userId });
  }

  accept(userId: string, matchId: string): void {
    const call = this.byMatch.get(matchId);
    if (!call || call.state !== 'ringing' || call.invitee !== userId) {
      return this.error(userId, 'call_not_found', COPY.callNotFound);
    }
    call.state = 'active';
    if (call.ringTimer) clearTimeout(call.ringTimer);
    call.ringTimer = null;
    this.deps.hub.send(call.inviter, { type: 'call.accept', matchId, fromUserId: userId });
  }

  decline(userId: string, matchId: string): void {
    this.finish(userId, matchId, 'call.decline');
  }

  end(userId: string, matchId: string): void {
    this.finish(userId, matchId, 'call.end');
  }

  signal(userId: string, target: string, payload: SignalPayload): void {
    const call = this.byMatch.get(target.slice(CALL_PREFIX.length));
    if (!call || (call.inviter !== userId && call.invitee !== userId)) {
      return this.error(userId, 'call_not_found', COPY.callNotFound);
    }
    this.deps.hub.send(this.other(call, userId), { type: 'rtc.signal', dateId: target, payload });
  }

  /** Ends whatever call the user is in (socket closed, account deleted or suspended). */
  handleDisconnect(userId: string): void {
    const call = this.byUser.get(userId);
    if (!call) return;
    this.deps.hub.send(this.other(call, userId), { type: 'call.end', matchId: call.matchId, fromUserId: userId });
    this.remove(call);
  }

  /** The match is gone (unmatch, block, deletion): tear down any call on it. */
  handleMatchRemoved(matchId: string): void {
    const call = this.byMatch.get(matchId);
    if (call) this.remove(call);
  }

  recordSexualLanguage(userId: string, matchId: string): number {
    const call = this.byMatch.get(matchId);
    if (!call) return 0;
    const n = (call.sexualWarnings.get(userId) ?? 0) + 1;
    call.sexualWarnings.set(userId, n);
    return n;
  }

  endForModeration(userId: string, matchId: string, category: ModerationCategory): boolean {
    const call = this.byMatch.get(matchId);
    if (!call || (call.inviter !== userId && call.invitee !== userId)) return false;
    const { hub } = this.deps;
    hub.send(userId, {
      type: 'moderation.action',
      dateId: `${CALL_PREFIX}${matchId}`,
      action: 'end',
      category,
      message: category === 'nudity' ? COPY.moderationEndNudity : COPY.moderationEndSexual,
    });
    hub.send(userId, { type: 'call.end', matchId, fromUserId: this.other(call, userId) });
    hub.send(this.other(call, userId), { type: 'call.end', matchId, fromUserId: userId });
    this.remove(call);
    return true;
  }

  shutdown(): void {
    for (const call of [...this.byMatch.values()]) this.remove(call);
  }

  private finish(userId: string, matchId: string, type: CallSignalType): void {
    const call = this.byMatch.get(matchId);
    if (!call || (call.inviter !== userId && call.invitee !== userId)) {
      return this.error(userId, 'call_not_found', COPY.callNotFound);
    }
    this.deps.hub.send(this.other(call, userId), { type, matchId, fromUserId: userId });
    this.remove(call);
  }

  private other(call: Call, userId: string): string {
    return call.inviter === userId ? call.invitee : call.inviter;
  }

  private remove(call: Call): void {
    if (call.ringTimer) clearTimeout(call.ringTimer);
    call.ringTimer = null;
    this.byMatch.delete(call.matchId);
    for (const id of [call.inviter, call.invitee]) {
      if (this.byUser.get(id) === call) this.byUser.delete(id);
    }
  }

  private error(userId: string, code: string, message: string): void {
    this.deps.hub.send(userId, { type: 'error', code, message });
  }
}
