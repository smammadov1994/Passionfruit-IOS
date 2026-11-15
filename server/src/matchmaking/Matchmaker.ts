import { mutuallyCompatible, type Candidate } from './compat.js';
import { mutualScore } from './score.js';

export interface QueuedPair {
  /** Ahead in queue order (premium first, then longest wait); becomes the WebRTC caller. */
  first: Candidate;
  second: Candidate;
}

/**
 * Live presence and queue state.
 *
 * This interface is the seam for multi-instance scale: `InMemoryMatchmaker` keeps everything in
 * this process; a Redis-backed implementation can replace it without touching callers
 * (see README "Scaling beyond one instance").
 */
export interface Matchmaker {
  /** Registers or refreshes an online user's snapshot. Queue position is preserved. */
  setOnline(candidate: Candidate): void;
  setOffline(userId: string): void;
  isOnline(userId: string): boolean;
  getCandidate(userId: string): Candidate | undefined;
  onlineCount(): number;

  /** Adds an online user to the queue. No-op when already queued. Returns false if not online. */
  enqueue(userId: string, nowMs: number): boolean;
  dequeue(userId: string): void;
  isQueued(userId: string): boolean;
  queuedUserIds(): string[];
  /** 1-based position in queue order, or 0 when not queued. */
  position(userId: string): number;

  /** Marks two people as never pairable for now (block, new match, fresh pairing). */
  addExclusion(a: string, b: string): void;
  removeExclusion(a: string, b: string): void;

  /** Mutually compatible people online right now, excluding `candidate` itself. */
  compatibleOnline(candidate: Candidate, nowMs: number): number;

  /**
   * Removes and returns every pair that can be formed right now. People are served in queue order
   * (premium first, then longest wait); each gets the compatible partner with the best score.
   */
  takePairs(nowMs: number): QueuedPair[];
}

interface OnlineEntry {
  candidate: Candidate;
  queuedAt: number | null;
  /** Tie-breaker so equal timestamps keep arrival order. */
  queueSeq: number;
}

export interface MatchmakerOptions {
  /** Share of pairings (0..1) that pick a random compatible partner instead of the best-scoring one. */
  exploreRate?: number;
  /** Source of randomness for exploration; returns a number in [0, 1). */
  random?: () => number;
}

/** A partner who has waited this long gets the full wait bonus, enough to outrank a slightly better fit. */
const WAIT_BONUS_FULL_MS = 60_000;
const WAIT_BONUS_MAX = 0.1;

export class InMemoryMatchmaker implements Matchmaker {
  private readonly online = new Map<string, OnlineEntry>();
  private seq = 0;
  private readonly exploreRate: number;
  private readonly random: () => number;

  constructor(options: MatchmakerOptions = {}) {
    this.exploreRate = options.exploreRate ?? 0;
    this.random = options.random ?? Math.random;
  }

  setOnline(candidate: Candidate): void {
    const existing = this.online.get(candidate.userId);
    if (existing) existing.candidate = candidate;
    else this.online.set(candidate.userId, { candidate, queuedAt: null, queueSeq: 0 });
  }

  setOffline(userId: string): void {
    this.online.delete(userId);
  }

  isOnline(userId: string): boolean {
    return this.online.has(userId);
  }

  getCandidate(userId: string): Candidate | undefined {
    return this.online.get(userId)?.candidate;
  }

  onlineCount(): number {
    return this.online.size;
  }

  enqueue(userId: string, nowMs: number): boolean {
    const entry = this.online.get(userId);
    if (!entry) return false;
    if (entry.queuedAt === null) {
      entry.queuedAt = nowMs;
      entry.queueSeq = ++this.seq;
    }
    return true;
  }

  dequeue(userId: string): void {
    const entry = this.online.get(userId);
    if (entry) entry.queuedAt = null;
  }

  isQueued(userId: string): boolean {
    return this.online.get(userId)?.queuedAt != null;
  }

  queuedUserIds(): string[] {
    return this.ordered().map((e) => e.candidate.userId);
  }

  position(userId: string): number {
    return this.ordered().findIndex((e) => e.candidate.userId === userId) + 1;
  }

  addExclusion(a: string, b: string): void {
    this.online.get(a)?.candidate.exclusions.add(b);
    this.online.get(b)?.candidate.exclusions.add(a);
  }

  removeExclusion(a: string, b: string): void {
    this.online.get(a)?.candidate.exclusions.delete(b);
    this.online.get(b)?.candidate.exclusions.delete(a);
  }

  compatibleOnline(candidate: Candidate, nowMs: number): number {
    let n = 0;
    for (const entry of this.online.values()) {
      if (mutuallyCompatible(candidate, entry.candidate, nowMs)) n += 1;
    }
    return n;
  }

  takePairs(nowMs: number): QueuedPair[] {
    const queue = this.ordered();
    const taken = new Set<string>();
    const pairs: QueuedPair[] = [];
    for (let i = 0; i < queue.length; i++) {
      const a = queue[i] as OnlineEntry;
      if (taken.has(a.candidate.userId)) continue;
      const options: OnlineEntry[] = [];
      for (let j = i + 1; j < queue.length; j++) {
        const b = queue[j] as OnlineEntry;
        if (taken.has(b.candidate.userId)) continue;
        if (mutuallyCompatible(a.candidate, b.candidate, nowMs)) options.push(b);
      }
      const b = this.choosePartner(a, options, nowMs);
      if (b === undefined) continue;
      taken.add(a.candidate.userId);
      taken.add(b.candidate.userId);
      a.queuedAt = null;
      b.queuedAt = null;
      pairs.push({ first: a.candidate, second: b.candidate });
    }
    return pairs;
  }

  /**
   * Best-scoring partner for `a` among `options` (already in queue order). Ties keep queue order,
   * so with no profile detail or history this is the old first-compatible behaviour.
   */
  private choosePartner(a: OnlineEntry, options: OnlineEntry[], nowMs: number): OnlineEntry | undefined {
    if (options.length <= 1) return options[0];
    if (this.exploreRate > 0 && this.random() < this.exploreRate) {
      return options[Math.min(options.length - 1, Math.floor(this.random() * options.length))];
    }
    let best: OnlineEntry | undefined;
    let bestScore = -Infinity;
    for (const b of options) {
      const waitedMs = Math.max(0, nowMs - (b.queuedAt as number));
      const waitBonus = WAIT_BONUS_MAX * Math.min(1, waitedMs / WAIT_BONUS_FULL_MS);
      const score = mutualScore(a.candidate, b.candidate, nowMs) + waitBonus;
      if (score > bestScore + 1e-9) {
        best = b;
        bestScore = score;
      }
    }
    return best;
  }

  /** Queue order: premium first, then longest wait. */
  private ordered(): OnlineEntry[] {
    const queued: OnlineEntry[] = [];
    for (const entry of this.online.values()) {
      if (entry.queuedAt !== null) queued.push(entry);
    }
    queued.sort((x, y) => {
      if (x.candidate.isPremium !== y.candidate.isPremium) return x.candidate.isPremium ? -1 : 1;
      const dx = (x.queuedAt as number) - (y.queuedAt as number);
      return dx !== 0 ? dx : x.queueSeq - y.queueSeq;
    });
    return queued;
  }
}
