import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config.js';
import type { Candidate } from '../matchmaking/compat.js';
import type { Matchmaker, QueuedPair } from '../matchmaking/Matchmaker.js';
import type { IceService } from '../services/ice.js';
import { toPartner, toWireMatch, type PartnerSource } from '../services/serialize.js';
import type { Store } from '../store/Store.js';
import type { DateEndReason, ModerationCategory } from '../types.js';
import { errMessage, iso, newId, shuffled, type Clock } from '../util.js';
import { COPY } from './copy.js';
import type { Hub } from './Hub.js';
import type { ServerMessage, SignalPayload } from './protocol.js';

type State = 'connecting' | 'live' | 'deciding' | 'done';
type Decision = 'yes' | 'no';

interface Participant {
  userId: string;
  candidate: Candidate;
  role: 'caller' | 'callee';
}

interface Session {
  id: string;
  caller: Participant;
  callee: Participant;
  state: State;
  ready: Set<string>;
  startsAt: number;
  endsAt: number;
  decisionDeadline: number;
  decisions: Map<string, Decision>;
  /** Participants who walked away during the decision window; they get nothing further. */
  released: Set<string>;
  questions: string[];
  questionIndex: number;
  /** 0 = first speaker answering, 1 = second speaker answering the same question. */
  turnPhase: 0 | 1;
  currentTurn: Extract<ServerMessage, { type: 'icebreaker.turn' }> | null;
  /**
   * The checkpoint after the first question. While it is open the date is still `live` but paused:
   * no turn runs and the end timer is stopped, with `checkpointRemainingMs` of the date left.
   */
  checkpoint: 'pending' | 'open' | 'passed';
  checkpointDeadline: number;
  checkpointRemainingMs: number;
  checkpointVotes: Map<string, 'continue' | 'end'>;
  checkpointTimer: NodeJS.Timeout | null;
  sexualWarnings: Map<string, number>;
  readyTimer: NodeJS.Timeout | null;
  endTimer: NodeJS.Timeout | null;
  turnTimer: NodeJS.Timeout | null;
  decisionTimer: NodeJS.Timeout | null;
  graceTimers: Map<string, NodeJS.Timeout>;
  /** Serialises this date's writes so `started` can never land before `created`. */
  writes: Promise<void>;
}

export interface DateEngineDeps {
  config: Pick<
    AppConfig,
    | 'dateDurationSec'
    | 'turnDurationSec'
    | 'decisionWindowSec'
    | 'checkpointWindowSec'
    | 'questionsPerDate'
    | 'matchOnFullDate'
    | 'readyTimeoutSec'
    | 'reconnectGraceSec'
    | 'decisionGraceMs'
  >;
  clock: Clock;
  hub: Hub;
  store: Store;
  matchmaker: Matchmaker;
  ice: IceService;
  log: FastifyBaseLogger;
  questions: readonly string[];
  rng?: () => number;
}

/** What moderation needs to know about a live date. */
export interface LiveDateView {
  dateId: string;
  partnerId: string;
}

const AWAY_NOTICE_TTL_MS = 120_000;

/**
 * Authoritative state machine for speed dates:
 * connecting -> live (clock + icebreaker turns) -> deciding -> done.
 * All state is in memory; every timer is owned by its session and cleared when the session ends.
 */
export class DateEngine {
  private readonly byId = new Map<string, Session>();
  private readonly byUser = new Map<string, Session>();
  /** Dates that ended while a participant was disconnected, so their client can leave the call UI. */
  private readonly endedWhileAway = new Map<string, { dateId: string; at: number }>();
  private readonly rng: () => number;

  constructor(private readonly deps: DateEngineDeps) {
    this.rng = deps.rng ?? Math.random;
  }

  // ------------------------------------------------------------------ queries
  isBusy(userId: string): boolean {
    return this.byUser.has(userId);
  }

  activeCount(): number {
    return this.byId.size;
  }

  /** The caller's date if `dateId` is theirs and video may still be flowing. */
  liveDateFor(userId: string, dateId: string): LiveDateView | null {
    const session = this.byUser.get(userId);
    if (!session || session.id !== dateId || session.state === 'done') return null;
    return { dateId, partnerId: this.other(session, userId).userId };
  }

  /** Dates in progress between two specific people (used when one blocks the other). */
  dateBetween(a: string, b: string): string | null {
    const session = this.byUser.get(a);
    return session && this.other(session, a).userId === b ? session.id : null;
  }

  // ------------------------------------------------------------------ lifecycle
  /** Synchronously registers the date so both people are immediately "busy", then notifies them. */
  begin(pair: QueuedPair): string {
    const { deps } = this;
    const now = deps.clock.now();
    const session: Session = {
      id: newId(),
      caller: { userId: pair.first.userId, candidate: pair.first, role: 'caller' },
      callee: { userId: pair.second.userId, candidate: pair.second, role: 'callee' },
      state: 'connecting',
      ready: new Set(),
      startsAt: 0,
      endsAt: 0,
      decisionDeadline: 0,
      decisions: new Map(),
      released: new Set(),
      questions: shuffled(deps.questions, this.rng),
      questionIndex: 0,
      turnPhase: 0,
      currentTurn: null,
      checkpoint: deps.config.checkpointWindowSec > 0 ? 'pending' : 'passed',
      checkpointDeadline: 0,
      checkpointRemainingMs: 0,
      checkpointVotes: new Map(),
      checkpointTimer: null,
      sexualWarnings: new Map(),
      readyTimer: null,
      endTimer: null,
      turnTimer: null,
      decisionTimer: null,
      graceTimers: new Map(),
      writes: Promise.resolve(),
    };
    this.byId.set(session.id, session);
    this.byUser.set(session.caller.userId, session);
    this.byUser.set(session.callee.userId, session);
    this.endedWhileAway.delete(session.caller.userId);
    this.endedWhileAway.delete(session.callee.userId);
    // 24 h re-pair cooldown, effective immediately for anyone still holding a snapshot.
    deps.matchmaker.addExclusion(session.caller.userId, session.callee.userId);

    this.persist(session, () =>
      deps.store.createDate({
        id: session.id,
        userA: session.caller.userId,
        userB: session.callee.userId,
        createdAt: new Date(now),
      }),
    );

    this.sendMatched(session, session.caller);
    this.sendMatched(session, session.callee);
    session.readyTimer = setTimeout(() => this.start(session), deps.config.readyTimeoutSec * 1000);
    return session.id;
  }

  handleReady(userId: string, dateId: string): void {
    const session = this.sessionFor(userId, dateId);
    if (!session) return this.notInDate(userId);
    if (session.state !== 'connecting') return; // late or duplicate ready is harmless
    session.ready.add(userId);
    if (session.ready.size === 2) this.start(session);
  }

  handleSignal(userId: string, dateId: string, payload: SignalPayload): void {
    const session = this.sessionFor(userId, dateId);
    if (!session || (session.state !== 'connecting' && session.state !== 'live')) return this.notInDate(userId);
    this.deps.hub.send(this.other(session, userId).userId, { type: 'rtc.signal', dateId, payload });
  }

  handlePass(userId: string, dateId: string): void {
    const session = this.sessionFor(userId, dateId);
    if (!session || session.state !== 'live') return this.notInDate(userId);
    if (session.currentTurn === null || session.currentTurn.speakerId !== userId) {
      this.deps.hub.send(userId, { type: 'error', code: 'not_your_turn', message: COPY.notYourTurn });
      return;
    }
    this.advanceTurn(session);
  }

  handleLeave(userId: string, dateId: string): void {
    const session = this.sessionFor(userId, dateId);
    if (!session) return this.notInDate(userId);
    this.leave(session, userId, 'you_left', 'partner_left');
  }

  handleDecide(userId: string, dateId: string, decision: Decision): void {
    const session = this.sessionFor(userId, dateId);
    if (!session || session.state !== 'deciding') return this.notInDate(userId);
    if (session.decisions.has(userId)) return; // first answer stands
    session.decisions.set(userId, decision);
    if (session.decisions.size === 2) this.finalize(session);
  }

  /** A private vote at the checkpoint. The first answer stands; one "end" settles it at once. */
  handleContinue(userId: string, dateId: string, choice: 'continue' | 'end'): void {
    const session = this.sessionFor(userId, dateId);
    if (!session || session.state !== 'live' || session.checkpoint !== 'open') return this.notInDate(userId);
    if (session.checkpointVotes.has(userId)) return;
    session.checkpointVotes.set(userId, choice);
    if (choice === 'end' || session.checkpointVotes.size === 2) this.resolveCheckpoint(session);
  }

  /** The user's socket closed (and was not replaced by a newer one). */
  handleDisconnect(userId: string): void {
    const session = this.byUser.get(userId);
    if (!session) return;
    if (session.state === 'connecting') {
      this.leave(session, userId, null, 'disconnect');
    } else if (session.state === 'live') {
      const existing = session.graceTimers.get(userId);
      if (existing) clearTimeout(existing);
      session.graceTimers.set(
        userId,
        setTimeout(() => {
          session.graceTimers.delete(userId);
          if (session.state !== 'live') return;
          this.noteEndedWhileAway(userId, session.id);
          this.leave(session, userId, null, 'disconnect');
        }, this.deps.config.reconnectGraceSec * 1000),
      );
    }
    // deciding: nothing to do; a missing decision counts as "no" at the deadline.
  }

  /** The user has a (new) socket: resume their date or tell them it ended while they were away. */
  handleReconnect(userId: string): void {
    const now = this.deps.clock.now();
    const session = this.byUser.get(userId);
    if (!session) {
      const away = this.endedWhileAway.get(userId);
      if (away) {
        this.endedWhileAway.delete(userId);
        if (now - away.at < AWAY_NOTICE_TTL_MS) {
          this.deps.hub.send(userId, { type: 'date.ended', dateId: away.dateId, reason: 'disconnect' });
        }
      }
      return;
    }
    const grace = session.graceTimers.get(userId);
    if (grace) {
      clearTimeout(grace);
      session.graceTimers.delete(userId);
    }
    const me = this.participant(session, userId);
    if (session.state === 'connecting') {
      this.sendMatched(session, me);
    } else if (session.state === 'live') {
      this.deps.hub.send(userId, this.startedMessage(session));
      if (session.currentTurn) this.deps.hub.send(userId, session.currentTurn);
      if (session.checkpoint === 'open') this.deps.hub.send(userId, this.checkpointMessage(session));
    } else if (session.state === 'deciding') {
      this.deps.hub.send(userId, {
        type: 'date.ended',
        dateId: session.id,
        reason: 'timer',
        decisionDeadline: iso(session.decisionDeadline),
      });
    }
  }

  /** Ends a date for a safety violation: both sides stop, the offender is told why. */
  endForModeration(userId: string, dateId: string, category: ModerationCategory): boolean {
    const session = this.sessionFor(userId, dateId);
    if (!session) return false;
    const partnerId = this.other(session, userId).userId;
    this.deps.hub.send(userId, {
      type: 'moderation.action',
      dateId,
      action: 'end',
      category,
      message: category === 'nudity' ? COPY.moderationEndNudity : COPY.moderationEndSexual,
    });
    for (const id of [userId, partnerId]) {
      if (!session.released.has(id)) {
        this.deps.hub.send(id, { type: 'date.ended', dateId, reason: 'moderation' });
      }
    }
    this.close(session, 'moderation', 'no_match');
    return true;
  }

  /** Counts a sexual-language offence in this date and returns the running total for the user. */
  recordSexualLanguage(userId: string, dateId: string): number {
    const session = this.sessionFor(userId, dateId);
    if (!session) return 0;
    const n = (session.sexualWarnings.get(userId) ?? 0) + 1;
    session.sexualWarnings.set(userId, n);
    return n;
  }

  /** Removes a user from whatever date they are in (block, suspension, account deletion). */
  forceLeave(userId: string): void {
    const session = this.byUser.get(userId);
    if (session) this.leave(session, userId, 'you_left', 'partner_left');
    this.endedWhileAway.delete(userId);
  }

  /** Clears every timer. Called on shutdown. */
  shutdown(): void {
    for (const session of [...this.byId.values()]) {
      session.state = 'done';
      this.clearTimers(session);
    }
    this.byId.clear();
    this.byUser.clear();
    this.endedWhileAway.clear();
  }

  /** Resolves when every pending date write has been flushed (shutdown and tests). */
  async flush(): Promise<void> {
    await Promise.all([...this.pendingWrites]);
  }

  // ------------------------------------------------------------------ internals
  private noteEndedWhileAway(userId: string, dateId: string): void {
    const now = this.deps.clock.now();
    // People who never come back must not accumulate here.
    for (const [id, entry] of this.endedWhileAway) {
      if (now - entry.at >= AWAY_NOTICE_TTL_MS) this.endedWhileAway.delete(id);
    }
    this.endedWhileAway.set(userId, { dateId, at: now });
  }

  private readonly pendingWrites = new Set<Promise<void>>();

  private persist(session: Session, op: () => Promise<unknown>): void {
    const next = session.writes
      .then(op)
      .then(() => undefined)
      .catch((err: unknown) => {
        this.deps.log.error({ dateId: session.id, err: errMessage(err) }, 'date persistence failed');
      });
    session.writes = next;
    this.pendingWrites.add(next);
    void next.finally(() => this.pendingWrites.delete(next));
  }

  private sessionFor(userId: string, dateId: string): Session | null {
    const session = this.byUser.get(userId);
    return session && session.id === dateId && session.state !== 'done' ? session : null;
  }

  private participant(session: Session, userId: string): Participant {
    return session.caller.userId === userId ? session.caller : session.callee;
  }

  private other(session: Session, userId: string): Participant {
    return session.caller.userId === userId ? session.callee : session.caller;
  }

  private notInDate(userId: string): void {
    this.deps.hub.send(userId, { type: 'error', code: 'not_in_date', message: COPY.notInDate });
  }

  private partnerSource(c: Candidate): PartnerSource {
    return {
      id: c.userId,
      firstName: c.display.firstName,
      birthdate: c.birthdate,
      city: c.display.city,
      lat: c.lat,
      lng: c.lng,
      photoUrl: c.display.photoUrl,
      intention: c.intention,
    };
  }

  private sendMatched(session: Session, to: Participant): void {
    const partner = this.other(session, to.userId);
    this.deps.hub.send(to.userId, {
      type: 'date.matched',
      dateId: session.id,
      partner: toPartner(this.partnerSource(partner.candidate), to.candidate, this.deps.clock.now()),
      role: to.role,
      iceServers: this.deps.ice.serversFor(to.userId),
    });
  }

  private startedMessage(session: Session): ServerMessage {
    return {
      type: 'date.started',
      dateId: session.id,
      startsAt: iso(session.startsAt),
      endsAt: iso(session.endsAt),
    };
  }

  private both(session: Session, message: ServerMessage): void {
    this.deps.hub.send(session.caller.userId, message);
    this.deps.hub.send(session.callee.userId, message);
  }

  private start(session: Session): void {
    if (session.state !== 'connecting') return;
    const { config, clock, store } = this.deps;
    if (session.readyTimer) clearTimeout(session.readyTimer);
    session.readyTimer = null;
    const now = clock.now();
    session.state = 'live';
    session.startsAt = now;
    session.endsAt = now + config.dateDurationSec * 1000;
    // This is the moment the date counts toward the daily cap.
    this.persist(session, () => store.markDateStarted(session.id, new Date(now)));
    this.both(session, this.startedMessage(session));
    session.endTimer = setTimeout(() => this.timerEnded(session), config.dateDurationSec * 1000);
    this.beginTurn(session);
  }

  private beginTurn(session: Session): void {
    if (session.state !== 'live') return;
    const question = session.questions[session.questionIndex];
    const now = this.deps.clock.now();
    if (question === undefined || now >= session.endsAt) {
      session.currentTurn = null; // bank exhausted (only possible with relentless passing) or time is up
      return;
    }
    // Who answers first alternates per question; the caller opens question 0.
    const first = session.questionIndex % 2 === 0 ? session.caller : session.callee;
    const speaker = session.turnPhase === 0 ? first : this.other(session, first.userId);
    const turnMs = this.deps.config.turnDurationSec * 1000;
    const turnEndsAt = Math.min(now + turnMs, session.endsAt);
    session.currentTurn = {
      type: 'icebreaker.turn',
      dateId: session.id,
      question,
      questionIndex: session.questionIndex,
      speakerId: speaker.userId,
      turnEndsAt: iso(turnEndsAt),
      turnDurationSec: this.deps.config.turnDurationSec,
    };
    this.both(session, session.currentTurn);
    session.turnTimer = setTimeout(() => this.advanceTurn(session), turnEndsAt - now);
  }

  private advanceTurn(session: Session): void {
    if (session.state !== 'live') return;
    if (session.turnTimer) clearTimeout(session.turnTimer);
    session.turnTimer = null;
    if (session.turnPhase === 0) {
      session.turnPhase = 1;
    } else {
      session.turnPhase = 0;
      session.questionIndex += 1;
      // An optional cap on questions ends the date the same way the clock does.
      const limit = this.deps.config.questionsPerDate;
      if (limit > 0 && session.questionIndex >= limit) {
        this.timerEnded(session);
        return;
      }
      // Both have answered the first question: pause and let each decide whether to carry on.
      if (session.checkpoint === 'pending') {
        this.openCheckpoint(session);
        return;
      }
    }
    this.beginTurn(session);
  }

  private checkpointMessage(session: Session): ServerMessage {
    return { type: 'date.checkpoint', dateId: session.id, deadline: iso(session.checkpointDeadline) };
  }

  /** Pauses the date clock and the icebreaker, and opens the vote. */
  private openCheckpoint(session: Session): void {
    const { config, clock } = this.deps;
    const now = clock.now();
    const remaining = session.endsAt - now;
    if (remaining <= 0) {
      session.checkpoint = 'passed';
      return; // the date timer is about to fire anyway
    }
    if (session.endTimer) clearTimeout(session.endTimer);
    session.endTimer = null;
    session.currentTurn = null;
    session.checkpoint = 'open';
    session.checkpointRemainingMs = remaining;
    session.checkpointDeadline = now + config.checkpointWindowSec * 1000;
    this.both(session, this.checkpointMessage(session));
    session.checkpointTimer = setTimeout(
      () => this.resolveCheckpoint(session),
      config.checkpointWindowSec * 1000 + config.decisionGraceMs,
    );
  }

  /**
   * Both said continue: the date picks up where it stopped. Anything else (an "end", or no answer
   * by the deadline) ends it for both, without saying who chose what.
   */
  private resolveCheckpoint(session: Session): void {
    if (session.state !== 'live' || session.checkpoint !== 'open') return;
    if (session.checkpointTimer) clearTimeout(session.checkpointTimer);
    session.checkpointTimer = null;
    const a = session.checkpointVotes.get(session.caller.userId);
    const b = session.checkpointVotes.get(session.callee.userId);
    if (a === 'continue' && b === 'continue') {
      const now = this.deps.clock.now();
      session.checkpoint = 'passed';
      session.endsAt = now + session.checkpointRemainingMs;
      this.both(session, { type: 'date.resumed', dateId: session.id, endsAt: iso(session.endsAt) });
      session.endTimer = setTimeout(() => this.timerEnded(session), session.checkpointRemainingMs);
      this.beginTurn(session);
      return;
    }
    this.both(session, { type: 'date.ended', dateId: session.id, reason: 'checkpoint' });
    this.close(session, 'checkpoint', 'no_match');
  }

  /**
   * The two stayed for the whole date and neither left: they match at once. Sent as a timer end
   * flagged `matched` (so the app skips the decision screen), followed by the result.
   */
  private completeAsMatch(session: Session): void {
    if (session.state !== 'live') return;
    this.clearTimers(session);
    session.state = 'deciding';
    session.currentTurn = null;
    session.decisionDeadline = this.deps.clock.now();
    session.decisions.set(session.caller.userId, 'yes');
    session.decisions.set(session.callee.userId, 'yes');
    this.both(session, {
      type: 'date.ended',
      dateId: session.id,
      reason: 'timer',
      decisionDeadline: iso(session.decisionDeadline),
      matched: true,
    });
    this.finalize(session);
  }

  private timerEnded(session: Session): void {
    if (session.state !== 'live') return;
    if (this.deps.config.matchOnFullDate) {
      this.completeAsMatch(session);
      return;
    }
    const { config, clock } = this.deps;
    this.clearTimers(session);
    session.state = 'deciding';
    session.currentTurn = null;
    session.decisionDeadline = clock.now() + config.decisionWindowSec * 1000;
    this.both(session, {
      type: 'date.ended',
      dateId: session.id,
      reason: 'timer',
      decisionDeadline: iso(session.decisionDeadline),
    });
    // A short grace after the advertised deadline absorbs network latency on a last-second tap.
    session.decisionTimer = setTimeout(
      () => this.finalize(session),
      config.decisionWindowSec * 1000 + config.decisionGraceMs,
    );
  }

  /**
   * `userId` walks away. Before the decision screen that ends the date for both; during it the
   * leaver is recorded as "no" and released while the partner keeps their private decision window.
   */
  private leave(
    session: Session,
    userId: string,
    leaverReason: DateEndReason | null,
    partnerReason: DateEndReason,
  ): void {
    if (session.state === 'done') return;
    const partner = this.other(session, userId);
    if (session.state === 'deciding') {
      if (session.released.has(userId)) return;
      session.decisions.set(userId, 'no');
      session.released.add(userId);
      this.byUser.delete(userId);
      this.deps.hub.send(userId, { type: 'date.result', dateId: session.id, outcome: 'no_match' });
      if (session.decisions.has(partner.userId) || session.released.has(partner.userId)) this.finalize(session);
      return;
    }
    if (leaverReason !== null) {
      this.deps.hub.send(userId, { type: 'date.ended', dateId: session.id, reason: leaverReason });
    }
    this.deps.hub.send(partner.userId, { type: 'date.ended', dateId: session.id, reason: partnerReason });
    this.close(session, partnerReason === 'disconnect' ? 'disconnect' : 'left', 'no_match');
  }

  private finalize(session: Session): void {
    if (session.state !== 'deciding') return;
    const a = session.caller.userId;
    const b = session.callee.userId;
    const mutual = session.decisions.get(a) === 'yes' && session.decisions.get(b) === 'yes';
    const recipients = [a, b].filter((id) => !session.released.has(id));
    // No answer by the deadline counts as no (SPEC "Product rules").
    const decisions = {
      a: session.decisions.get(a) ?? ('no' as const),
      b: session.decisions.get(b) ?? ('no' as const),
    };
    this.close(session, 'timer', mutual ? 'match' : 'no_match', decisions);

    if (!mutual) {
      for (const id of recipients) {
        this.deps.hub.send(id, { type: 'date.result', dateId: session.id, outcome: 'no_match' });
      }
      return;
    }
    void this.createMatch(session, a, b).catch((err: unknown) => {
      this.deps.log.error({ dateId: session.id, err: errMessage(err) }, 'match creation failed');
      for (const id of recipients) {
        this.deps.hub.send(id, { type: 'error', code: 'internal', message: COPY.internal });
        this.deps.hub.send(id, { type: 'date.result', dateId: session.id, outcome: 'no_match' });
      }
    });
  }

  private async createMatch(session: Session, a: string, b: string): Promise<void> {
    const { store, hub, clock } = this.deps;
    const now = clock.now();
    const [userA, userB] = await Promise.all([store.getUser(a), store.getUser(b)]);
    if (!userA || !userB || (await store.isBlockedEither(a, b))) {
      // Someone deleted their account or blocked the other during the decision window.
      for (const id of [a, b]) hub.send(id, { type: 'date.result', dateId: session.id, outcome: 'no_match' });
      return;
    }
    const match = await store.createMatch({ userA: a, userB: b, dateId: session.id, matchedAt: new Date(now) });
    for (const [me, partner] of [
      [userA, userB],
      [userB, userA],
    ] as const) {
      hub.send(me.id, {
        type: 'date.result',
        dateId: session.id,
        outcome: 'match',
        match: toWireMatch({ match, partner, lastMessage: null, unreadCount: 0 }, me, now),
      });
    }
  }

  /** Ends the session: timers cleared, both users free again, final state persisted. */
  private close(
    session: Session,
    endReason: string,
    outcome: 'match' | 'no_match',
    decisions?: { a: Decision; b: Decision },
  ): void {
    if (session.state === 'done') return;
    session.state = 'done';
    this.clearTimers(session);
    this.byId.delete(session.id);
    for (const id of [session.caller.userId, session.callee.userId]) {
      if (this.byUser.get(id) === session) this.byUser.delete(id);
    }
    const endedAt = new Date(this.deps.clock.now());
    const result = { endedAt, endReason, outcome, ...(decisions ? { decisions } : {}) };
    this.persist(session, () => this.deps.store.finishDate(session.id, result));
  }

  private clearTimers(session: Session): void {
    for (const key of ['readyTimer', 'endTimer', 'turnTimer', 'decisionTimer', 'checkpointTimer'] as const) {
      const timer = session[key];
      if (timer) clearTimeout(timer);
      session[key] = null;
    }
    for (const timer of session.graceTimers.values()) clearTimeout(timer);
    session.graceTimers.clear();
  }
}
