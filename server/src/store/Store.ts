import type {
  AuditEvent,
  AuditInput,
  AuditType,
  DateRecord,
  MatchRecord,
  MatchSummary,
  MessageRecord,
  ReportRecord,
  ReportReason,
  UserPatch,
  UserRecord,
} from '../types.js';
import type { DateStats } from '../matchmaking/score.js';

export interface CreateUserInput {
  appleSub: string;
  firstName: string;
  strikes?: number;
  suspended?: boolean;
  suspendedUntil?: Date | null;
}

export interface DeletedIdentity {
  strikes: number;
  suspended: boolean;
  suspendedUntil: Date | null;
}

export interface AddMessageInput {
  matchId: string;
  senderId: string;
  text: string;
  clientId: string | null;
  sentAt: Date;
}

export interface AddReportInput {
  reporterId: string;
  reportedUserId: string;
  dateId: string | null;
  matchId: string | null;
  reason: ReportReason;
  details: string | null;
  createdAt: Date;
}

/**
 * Durable persistence. Two implementations: `MemoryStore` (tests, local dev) and
 * `PgStore` (production, selected by DATABASE_URL). Both pass test/store.contract.test.ts.
 */
export interface Store {
  close(): Promise<void>;

  // Users
  createUser(input: CreateUserInput): Promise<UserRecord>;
  getUser(id: string): Promise<UserRecord | null>;
  getUserByAppleSub(appleSub: string): Promise<UserRecord | null>;
  updateUser(id: string, patch: UserPatch): Promise<UserRecord | null>;
  /** Atomically adds one strike and returns the new total (0 if the user is gone). */
  incrementStrikes(id: string): Promise<number>;
  /** Hard-deletes the user and everything that belongs to them (matches, messages, blocks, tokens). */
  deleteUser(id: string): Promise<void>;
  /** Users who opted in to "singles online" pushes and were last notified before `notifiedBefore`. */
  listPushCandidates(notifiedBefore: Date, limit: number): Promise<UserRecord[]>;

  // Blocks
  addBlock(blockerId: string, blockedId: string, at: Date): Promise<void>;
  isBlockedEither(a: string, b: string): Promise<boolean>;
  /**
   * Everyone `userId` must never be paired with right now: blocked in either direction,
   * currently matched, or paired (date created) at or after `pairedSince`.
   */
  listExclusions(userId: string, pairedSince: Date): Promise<string[]>;

  // Dates
  createDate(input: { id: string; userA: string; userB: string; createdAt: Date }): Promise<void>;
  markDateStarted(id: string, at: Date): Promise<void>;
  finishDate(
    id: string,
    result: {
      endedAt: Date;
      endReason: string;
      outcome: 'match' | 'no_match' | null;
      /** userA's and userB's private answers, when the date reached the yes/no screen. */
      decisions?: { a: 'yes' | 'no'; b: 'yes' | 'no' };
    },
  ): Promise<void>;
  /** The user's yes/no history over dates that reached the yes/no screen (see `matchmaking/score.ts`). */
  getDateStats(userId: string): Promise<DateStats>;
  getDate(id: string): Promise<DateRecord | null>;
  /** Dates the user took part in whose `startedAt` is at or after `since`. */
  countDatesStarted(userId: string, since: Date): Promise<number>;

  // Matches
  /** Idempotent per pair: returns the existing match if the two are already matched. */
  createMatch(input: { userA: string; userB: string; dateId: string | null; matchedAt: Date }): Promise<MatchRecord>;
  getMatch(id: string): Promise<MatchRecord | null>;
  getMatchBetween(a: string, b: string): Promise<MatchRecord | null>;
  listMatchSummaries(userId: string): Promise<MatchSummary[]>;
  deleteMatch(id: string): Promise<void>;

  // Messages
  /** Idempotent on (matchId, senderId, clientId) when clientId is present. */
  addMessage(input: AddMessageInput): Promise<{ message: MessageRecord; created: boolean }>;
  /** Up to `limit` newest messages sent strictly before `before`, returned oldest first. */
  listMessages(matchId: string, before: Date | null, limit: number): Promise<MessageRecord[]>;
  markRead(matchId: string, userId: string, at: Date): Promise<void>;

  // Safety
  addReport(input: AddReportInput): Promise<ReportRecord>;
  addAudit(input: AuditInput): Promise<AuditEvent>;
  listAudit(filter: { userId?: string; type?: AuditType }): Promise<AuditEvent[]>;

  // In-app purchase
  /** Binds an App Store original transaction to a user; returns the previous owner if it moved. */
  bindTransaction(originalTransactionId: string, userId: string): Promise<string | null>;
  getTransactionOwner(originalTransactionId: string): Promise<string | null>;

  // Strike carry-over for deleted accounts (keyed by a salted hash of the identity subject)
  putDeletedIdentity(hash: string, value: DeletedIdentity): Promise<void>;
  takeDeletedIdentity(hash: string): Promise<DeletedIdentity | null>;
}
