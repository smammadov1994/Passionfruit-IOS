import {
  DEFAULT_PREFERENCES,
  type AuditEvent,
  type AuditInput,
  type AuditType,
  type DateRecord,
  type MatchRecord,
  type MatchSummary,
  type MessageRecord,
  type ReportRecord,
  type UserPatch,
  type UserRecord,
} from '../types.js';
import type { DateStats } from '../matchmaking/score.js';
import { newId, pairKey } from '../util.js';
import type {
  AddMessageInput,
  AddReportInput,
  CreateUserInput,
  DeletedIdentity,
  Store,
} from './Store.js';

interface StoredMessage extends MessageRecord {
  seq: number;
}

const cloneUser = (u: UserRecord): UserRecord => ({
  ...u,
  interestedIn: [...u.interestedIn],
  photoUrls: [...u.photoUrls],
  preferences: structuredClone(u.preferences),
});

/** Process-local store used by tests and by dev runs without DATABASE_URL. */
export class MemoryStore implements Store {
  private readonly users = new Map<string, UserRecord>();
  private readonly bySub = new Map<string, string>();
  private readonly blocks = new Set<string>(); // `${blocker}>${blocked}`
  private readonly dates = new Map<string, DateRecord>();
  private readonly matches = new Map<string, MatchRecord>();
  private readonly matchByPair = new Map<string, string>();
  private readonly messages = new Map<string, StoredMessage[]>();
  private readonly reads = new Map<string, Date>(); // `${matchId}|${userId}`
  private readonly reports: ReportRecord[] = [];
  private readonly audit: AuditEvent[] = [];
  private readonly transactions = new Map<string, string>();
  private readonly deletedIdentities = new Map<string, DeletedIdentity>();
  private seq = 0;

  async close(): Promise<void> {}

  async createUser(input: CreateUserInput): Promise<UserRecord> {
    const existing = this.bySub.get(input.appleSub);
    if (existing !== undefined) {
      const found = this.users.get(existing);
      if (found) return cloneUser(found);
    }
    const user: UserRecord = {
      id: newId(),
      appleSub: input.appleSub,
      firstName: input.firstName,
      birthdate: null,
      gender: null,
      interestedIn: [],
      bio: '',
      city: '',
      lat: null,
      lng: null,
      photoUrls: [],
      intention: null,
      children: null,
      religion: null,
      education: null,
      smoking: null,
      drinking: null,
      isPremium: false,
      premiumExpiresAt: null,
      onboardingComplete: false,
      strikes: input.strikes ?? 0,
      suspended: input.suspended ?? false,
      suspendedUntil: input.suspendedUntil ?? null,
      preferences: { ...DEFAULT_PREFERENCES },
      apnsToken: null,
      pushEnabled: false,
      tzOffsetMinutes: 0,
      lastOnlinePushAt: null,
      createdAt: new Date(),
    };
    this.users.set(user.id, user);
    this.bySub.set(user.appleSub, user.id);
    return cloneUser(user);
  }

  async getUser(id: string): Promise<UserRecord | null> {
    const u = this.users.get(id);
    return u ? cloneUser(u) : null;
  }

  async getUserByAppleSub(appleSub: string): Promise<UserRecord | null> {
    const id = this.bySub.get(appleSub);
    return id === undefined ? null : this.getUser(id);
  }

  async updateUser(id: string, patch: UserPatch): Promise<UserRecord | null> {
    const u = this.users.get(id);
    if (!u) return null;
    for (const [key, value] of Object.entries(patch)) {
      if (value !== undefined) (u as unknown as Record<string, unknown>)[key] = structuredClone(value);
    }
    return cloneUser(u);
  }

  async incrementStrikes(id: string): Promise<number> {
    const u = this.users.get(id);
    if (!u) return 0;
    u.strikes += 1;
    return u.strikes;
  }

  async deleteUser(id: string): Promise<void> {
    const u = this.users.get(id);
    if (!u) return;
    this.users.delete(id);
    this.bySub.delete(u.appleSub);
    for (const key of [...this.blocks]) {
      const [a, b] = key.split('>');
      if (a === id || b === id) this.blocks.delete(key);
    }
    for (const m of [...this.matches.values()]) {
      if (m.userA === id || m.userB === id) await this.deleteMatch(m.id);
    }
    for (const d of this.dates.values()) {
      if (d.userA === id) d.userA = null;
      if (d.userB === id) d.userB = null;
    }
    for (const r of this.reports) {
      if (r.reporterId === id) r.reporterId = null;
    }
    for (const [tx, owner] of [...this.transactions]) {
      if (owner === id) this.transactions.delete(tx);
    }
  }

  async listPushCandidates(notifiedBefore: Date, limit: number): Promise<UserRecord[]> {
    const out: UserRecord[] = [];
    for (const u of this.users.values()) {
      if (out.length >= limit) break;
      if (
        u.pushEnabled &&
        u.apnsToken !== null &&
        u.onboardingComplete &&
        !u.suspended &&
        u.preferences.notifyOnlineSingles &&
        (u.lastOnlinePushAt === null || u.lastOnlinePushAt.getTime() < notifiedBefore.getTime())
      ) {
        out.push(cloneUser(u));
      }
    }
    return out;
  }

  async addBlock(blockerId: string, blockedId: string, _at: Date): Promise<void> {
    this.blocks.add(`${blockerId}>${blockedId}`);
  }

  async isBlockedEither(a: string, b: string): Promise<boolean> {
    return this.blocks.has(`${a}>${b}`) || this.blocks.has(`${b}>${a}`);
  }

  async listExclusions(userId: string, pairedSince: Date): Promise<string[]> {
    const out = new Set<string>();
    for (const key of this.blocks) {
      const [a, b] = key.split('>') as [string, string];
      if (a === userId) out.add(b);
      else if (b === userId) out.add(a);
    }
    for (const m of this.matches.values()) {
      if (m.userA === userId) out.add(m.userB);
      else if (m.userB === userId) out.add(m.userA);
    }
    for (const d of this.dates.values()) {
      if (d.createdAt.getTime() < pairedSince.getTime()) continue;
      if (d.userA === userId && d.userB !== null) out.add(d.userB);
      else if (d.userB === userId && d.userA !== null) out.add(d.userA);
    }
    return [...out];
  }

  async createDate(input: { id: string; userA: string; userB: string; createdAt: Date }): Promise<void> {
    this.dates.set(input.id, {
      id: input.id,
      userA: input.userA,
      userB: input.userB,
      createdAt: input.createdAt,
      startedAt: null,
      endedAt: null,
      endReason: null,
      outcome: null,
      decisionA: null,
      decisionB: null,
    });
  }

  async markDateStarted(id: string, at: Date): Promise<void> {
    const d = this.dates.get(id);
    if (d) d.startedAt = at;
  }

  async finishDate(
    id: string,
    result: {
      endedAt: Date;
      endReason: string;
      outcome: 'match' | 'no_match' | null;
      decisions?: { a: 'yes' | 'no'; b: 'yes' | 'no' };
    },
  ): Promise<void> {
    const d = this.dates.get(id);
    if (!d) return;
    d.endedAt = result.endedAt;
    d.endReason = result.endReason;
    d.outcome = result.outcome;
    d.decisionA = result.decisions?.a ?? null;
    d.decisionB = result.decisions?.b ?? null;
  }

  async getDateStats(userId: string): Promise<DateStats> {
    const stats: DateStats = { answered: 0, yesGiven: 0, rated: 0, yesReceived: 0 };
    for (const d of this.dates.values()) {
      const isA = d.userA === userId;
      if (!isA && d.userB !== userId) continue;
      const mine = isA ? d.decisionA : d.decisionB;
      const theirs = isA ? d.decisionB : d.decisionA;
      if (mine !== null) {
        stats.answered += 1;
        if (mine === 'yes') stats.yesGiven += 1;
      }
      if (theirs !== null) {
        stats.rated += 1;
        if (theirs === 'yes') stats.yesReceived += 1;
      }
    }
    return stats;
  }

  async getDate(id: string): Promise<DateRecord | null> {
    const d = this.dates.get(id);
    return d ? { ...d } : null;
  }

  async countDatesStarted(userId: string, since: Date): Promise<number> {
    let n = 0;
    for (const d of this.dates.values()) {
      if (
        d.startedAt !== null &&
        d.startedAt.getTime() >= since.getTime() &&
        (d.userA === userId || d.userB === userId)
      ) {
        n += 1;
      }
    }
    return n;
  }

  async createMatch(input: {
    userA: string;
    userB: string;
    dateId: string | null;
    matchedAt: Date;
  }): Promise<MatchRecord> {
    const key = pairKey(input.userA, input.userB);
    const existingId = this.matchByPair.get(key);
    if (existingId !== undefined) {
      const existing = this.matches.get(existingId);
      if (existing) return { ...existing };
    }
    const [a, b] = input.userA < input.userB ? [input.userA, input.userB] : [input.userB, input.userA];
    const match: MatchRecord = { id: newId(), userA: a, userB: b, dateId: input.dateId, matchedAt: input.matchedAt };
    this.matches.set(match.id, match);
    this.matchByPair.set(key, match.id);
    this.messages.set(match.id, []);
    return { ...match };
  }

  async getMatch(id: string): Promise<MatchRecord | null> {
    const m = this.matches.get(id);
    return m ? { ...m } : null;
  }

  async getMatchBetween(a: string, b: string): Promise<MatchRecord | null> {
    const id = this.matchByPair.get(pairKey(a, b));
    return id === undefined ? null : this.getMatch(id);
  }

  async listMatchSummaries(userId: string): Promise<MatchSummary[]> {
    const out: MatchSummary[] = [];
    for (const m of this.matches.values()) {
      if (m.userA !== userId && m.userB !== userId) continue;
      const partnerId = m.userA === userId ? m.userB : m.userA;
      const partner = this.users.get(partnerId);
      if (!partner) continue;
      const msgs = this.messages.get(m.id) ?? [];
      const last = msgs[msgs.length - 1];
      const readAt = this.reads.get(`${m.id}|${userId}`);
      const unreadCount = msgs.filter(
        (x) => x.senderId !== userId && (readAt === undefined || x.sentAt.getTime() > readAt.getTime()),
      ).length;
      out.push({
        match: { ...m },
        partner: cloneUser(partner),
        lastMessage: last ? toMessage(last) : null,
        unreadCount,
      });
    }
    out.sort((x, y) => activity(y) - activity(x));
    return out;
  }

  async deleteMatch(id: string): Promise<void> {
    const m = this.matches.get(id);
    if (!m) return;
    this.matches.delete(id);
    this.matchByPair.delete(pairKey(m.userA, m.userB));
    this.messages.delete(id);
    for (const key of [...this.reads.keys()]) {
      if (key.startsWith(`${id}|`)) this.reads.delete(key);
    }
  }

  async addMessage(input: AddMessageInput): Promise<{ message: MessageRecord; created: boolean }> {
    const list = this.messages.get(input.matchId);
    if (!list) throw new Error('match not found');
    if (input.clientId !== null) {
      const dup = list.find((m) => m.senderId === input.senderId && m.clientId === input.clientId);
      if (dup) return { message: toMessage(dup), created: false };
    }
    const msg: StoredMessage = {
      id: newId(),
      matchId: input.matchId,
      senderId: input.senderId,
      text: input.text,
      sentAt: input.sentAt,
      clientId: input.clientId,
      seq: ++this.seq,
    };
    list.push(msg);
    return { message: toMessage(msg), created: true };
  }

  async listMessages(matchId: string, before: Date | null, limit: number): Promise<MessageRecord[]> {
    const list = this.messages.get(matchId) ?? [];
    const filtered = before === null ? list : list.filter((m) => m.sentAt.getTime() < before.getTime());
    return filtered.slice(Math.max(0, filtered.length - limit)).map(toMessage);
  }

  async markRead(matchId: string, userId: string, at: Date): Promise<void> {
    if (this.matches.has(matchId)) this.reads.set(`${matchId}|${userId}`, at);
  }

  async addReport(input: AddReportInput): Promise<ReportRecord> {
    const report: ReportRecord = { id: newId(), ...input };
    this.reports.push(report);
    return { ...report };
  }

  async addAudit(input: AuditInput): Promise<AuditEvent> {
    const event: AuditEvent = {
      id: newId(),
      type: input.type,
      userId: input.userId ?? null,
      targetUserId: input.targetUserId ?? null,
      dateId: input.dateId ?? null,
      matchId: input.matchId ?? null,
      category: input.category ?? null,
      action: input.action ?? null,
      details: input.details ?? {},
      createdAt: new Date(),
    };
    this.audit.push(event);
    return { ...event };
  }

  async listAudit(filter: { userId?: string; type?: AuditType }): Promise<AuditEvent[]> {
    return this.audit
      .filter(
        (e) =>
          (filter.userId === undefined || e.userId === filter.userId) &&
          (filter.type === undefined || e.type === filter.type),
      )
      .map((e) => ({ ...e }));
  }

  async bindTransaction(originalTransactionId: string, userId: string): Promise<string | null> {
    const previous = this.transactions.get(originalTransactionId) ?? null;
    this.transactions.set(originalTransactionId, userId);
    return previous !== null && previous !== userId ? previous : null;
  }

  async getTransactionOwner(originalTransactionId: string): Promise<string | null> {
    return this.transactions.get(originalTransactionId) ?? null;
  }

  async putDeletedIdentity(hash: string, value: DeletedIdentity): Promise<void> {
    this.deletedIdentities.set(hash, { ...value });
  }

  async takeDeletedIdentity(hash: string): Promise<DeletedIdentity | null> {
    const v = this.deletedIdentities.get(hash) ?? null;
    this.deletedIdentities.delete(hash);
    return v;
  }
}

function toMessage(m: StoredMessage): MessageRecord {
  return { id: m.id, matchId: m.matchId, senderId: m.senderId, text: m.text, sentAt: m.sentAt, clientId: m.clientId };
}

function activity(s: MatchSummary): number {
  return (s.lastMessage?.sentAt ?? s.match.matchedAt).getTime();
}
