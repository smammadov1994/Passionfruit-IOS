import {
  DEFAULT_PREFERENCES,
  type AuditEvent,
  type AuditInput,
  type AuditType,
  type DateRecord,
  type Gender,
  type MatchRecord,
  type MatchSummary,
  type MessageRecord,
  type Preferences,
  type ReportRecord,
  type ReportReason,
  type UserPatch,
  type UserRecord,
} from '../types.js';
import type { DateStats } from '../matchmaking/score.js';
import { newId } from '../util.js';
import type {
  AddMessageInput,
  AddReportInput,
  CreateUserInput,
  DeletedIdentity,
  Store,
} from './Store.js';

export type Row = Record<string, unknown>;

/**
 * The minimal SQL surface PgStore needs. Implemented for `pg` (see pgPool.ts) and, in tests,
 * for PGlite, so the same SQL is exercised without a running Postgres.
 */
export interface Queryable {
  query(text: string, params?: readonly unknown[]): Promise<{ rows: Row[] }>;
  /** Runs one or more statements with no parameters (used by migrations). */
  exec(sql: string): Promise<void>;
  tx<T>(fn: (q: Queryable) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

const USER_COLUMNS: Record<keyof UserPatch, { column: string; json?: boolean }> = {
  firstName: { column: 'first_name' },
  birthdate: { column: 'birthdate' },
  gender: { column: 'gender' },
  interestedIn: { column: 'interested_in', json: true },
  bio: { column: 'bio' },
  city: { column: 'city' },
  lat: { column: 'lat' },
  lng: { column: 'lng' },
  photoUrls: { column: 'photo_urls', json: true },
  intention: { column: 'intention' },
  children: { column: 'children' },
  religion: { column: 'religion' },
  education: { column: 'education' },
  smoking: { column: 'smoking' },
  drinking: { column: 'drinking' },
  isPremium: { column: 'is_premium' },
  premiumExpiresAt: { column: 'premium_expires_at' },
  onboardingComplete: { column: 'onboarding_complete' },
  strikes: { column: 'strikes' },
  suspended: { column: 'suspended' },
  suspendedUntil: { column: 'suspended_until' },
  preferences: { column: 'preferences', json: true },
  apnsToken: { column: 'apns_token' },
  pushEnabled: { column: 'push_enabled' },
  tzOffsetMinutes: { column: 'tz_offset_minutes' },
  lastOnlinePushAt: { column: 'last_online_push_at' },
};

const str = (v: unknown): string => (typeof v === 'string' ? v : String(v));
const strOrNull = (v: unknown): string | null => (v === null || v === undefined ? null : str(v));
const numOrNull = (v: unknown): number | null => (v === null || v === undefined ? null : Number(v));
const dateOrNull = (v: unknown): Date | null => {
  if (v === null || v === undefined) return null;
  return v instanceof Date ? v : new Date(str(v));
};
const toDate = (v: unknown): Date => dateOrNull(v) ?? new Date(0);
const json = <T>(v: unknown, fallback: T): T => {
  if (v === null || v === undefined) return fallback;
  if (typeof v === 'string') return JSON.parse(v) as T;
  return v as T;
};

function toUser(r: Row): UserRecord {
  return {
    id: str(r.id),
    appleSub: str(r.apple_sub),
    firstName: str(r.first_name),
    birthdate: strOrNull(r.birthdate),
    gender: strOrNull(r.gender) as UserRecord['gender'],
    interestedIn: json<Gender[]>(r.interested_in, []),
    bio: str(r.bio),
    city: str(r.city),
    lat: numOrNull(r.lat),
    lng: numOrNull(r.lng),
    photoUrls: json<string[]>(r.photo_urls, []),
    intention: strOrNull(r.intention) as UserRecord['intention'],
    children: strOrNull(r.children) as UserRecord['children'],
    religion: strOrNull(r.religion) as UserRecord['religion'],
    education: strOrNull(r.education) as UserRecord['education'],
    smoking: strOrNull(r.smoking) as UserRecord['smoking'],
    drinking: strOrNull(r.drinking) as UserRecord['drinking'],
    isPremium: r.is_premium === true,
    premiumExpiresAt: dateOrNull(r.premium_expires_at),
    onboardingComplete: r.onboarding_complete === true,
    strikes: Number(r.strikes),
    suspended: r.suspended === true,
    suspendedUntil: dateOrNull(r.suspended_until),
    preferences: json<Preferences>(r.preferences, { ...DEFAULT_PREFERENCES }),
    apnsToken: strOrNull(r.apns_token),
    pushEnabled: r.push_enabled === true,
    tzOffsetMinutes: Number(r.tz_offset_minutes),
    lastOnlinePushAt: dateOrNull(r.last_online_push_at),
    createdAt: toDate(r.created_at),
  };
}

function toMatch(r: Row): MatchRecord {
  return {
    id: str(r.id),
    userA: str(r.user_a),
    userB: str(r.user_b),
    dateId: strOrNull(r.date_id),
    matchedAt: toDate(r.matched_at),
  };
}

function toMessage(r: Row): MessageRecord {
  return {
    id: str(r.id),
    matchId: str(r.match_id),
    senderId: str(r.sender_id),
    text: str(r.text),
    sentAt: toDate(r.sent_at),
    clientId: strOrNull(r.client_id),
  };
}

function toAudit(r: Row): AuditEvent {
  return {
    id: str(r.id),
    type: str(r.type) as AuditType,
    userId: strOrNull(r.user_id),
    targetUserId: strOrNull(r.target_user_id),
    dateId: strOrNull(r.date_id),
    matchId: strOrNull(r.match_id),
    category: strOrNull(r.category),
    action: strOrNull(r.action),
    details: json<Record<string, unknown>>(r.details, {}),
    createdAt: toDate(r.created_at),
  };
}

/** Postgres-backed store. All SQL is parameterised; arrays travel as jsonb for driver portability. */
export class PgStore implements Store {
  constructor(private readonly db: Queryable) {}

  async close(): Promise<void> {
    await this.db.close();
  }

  private async one(text: string, params: readonly unknown[]): Promise<Row | null> {
    const { rows } = await this.db.query(text, params);
    return rows[0] ?? null;
  }

  async createUser(input: CreateUserInput): Promise<UserRecord> {
    const row = await this.one(
      `INSERT INTO users (id, apple_sub, first_name, strikes, suspended, suspended_until, preferences)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
       ON CONFLICT (apple_sub) DO UPDATE SET apple_sub = EXCLUDED.apple_sub
       RETURNING *`,
      [
        newId(),
        input.appleSub,
        input.firstName,
        input.strikes ?? 0,
        input.suspended ?? false,
        input.suspendedUntil ?? null,
        JSON.stringify(DEFAULT_PREFERENCES),
      ],
    );
    if (!row) throw new Error('createUser returned no row');
    return toUser(row);
  }

  async getUser(id: string): Promise<UserRecord | null> {
    const row = await this.one('SELECT * FROM users WHERE id = $1', [id]);
    return row ? toUser(row) : null;
  }

  async getUserByAppleSub(appleSub: string): Promise<UserRecord | null> {
    const row = await this.one('SELECT * FROM users WHERE apple_sub = $1', [appleSub]);
    return row ? toUser(row) : null;
  }

  async updateUser(id: string, patch: UserPatch): Promise<UserRecord | null> {
    const sets: string[] = [];
    const params: unknown[] = [id];
    for (const key of Object.keys(patch) as (keyof UserPatch)[]) {
      const value = patch[key];
      if (value === undefined) continue;
      const spec = USER_COLUMNS[key];
      if (spec === undefined) continue;
      params.push(spec.json === true ? JSON.stringify(value) : value);
      sets.push(`${spec.column} = $${params.length}${spec.json === true ? '::jsonb' : ''}`);
    }
    if (sets.length === 0) return this.getUser(id);
    const row = await this.one(`UPDATE users SET ${sets.join(', ')} WHERE id = $1 RETURNING *`, params);
    return row ? toUser(row) : null;
  }

  async incrementStrikes(id: string): Promise<number> {
    const row = await this.one('UPDATE users SET strikes = strikes + 1 WHERE id = $1 RETURNING strikes', [id]);
    return row ? Number(row.strikes) : 0;
  }

  async deleteUser(id: string): Promise<void> {
    await this.db.tx(async (q) => {
      await q.query('DELETE FROM match_reads WHERE user_id = $1', [id]);
      // Foreign keys cascade to matches (and their messages/read markers), blocks and IAP bindings;
      // dates and reports keep their row with this participant nulled.
      await q.query('DELETE FROM users WHERE id = $1', [id]);
    });
  }

  async listPushCandidates(notifiedBefore: Date, limit: number): Promise<UserRecord[]> {
    const { rows } = await this.db.query(
      `SELECT * FROM users
       WHERE push_enabled AND apns_token IS NOT NULL AND onboarding_complete AND NOT suspended
         AND (preferences->>'notifyOnlineSingles')::boolean
         AND (last_online_push_at IS NULL OR last_online_push_at < $1)
       ORDER BY last_online_push_at ASC NULLS FIRST
       LIMIT $2`,
      [notifiedBefore, limit],
    );
    return rows.map(toUser);
  }

  async addBlock(blockerId: string, blockedId: string, at: Date): Promise<void> {
    await this.db.query(
      `INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, $3)
       ON CONFLICT DO NOTHING`,
      [blockerId, blockedId, at],
    );
  }

  async isBlockedEither(a: string, b: string): Promise<boolean> {
    const row = await this.one(
      `SELECT 1 AS hit FROM blocks
       WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)
       LIMIT 1`,
      [a, b],
    );
    return row !== null;
  }

  async listExclusions(userId: string, pairedSince: Date): Promise<string[]> {
    const { rows } = await this.db.query(
      `SELECT blocked_id AS other FROM blocks WHERE blocker_id = $1
       UNION SELECT blocker_id FROM blocks WHERE blocked_id = $1
       UNION SELECT user_b FROM matches WHERE user_a = $1
       UNION SELECT user_a FROM matches WHERE user_b = $1
       UNION SELECT user_b FROM dates WHERE user_a = $1 AND created_at >= $2 AND user_b IS NOT NULL
       UNION SELECT user_a FROM dates WHERE user_b = $1 AND created_at >= $2 AND user_a IS NOT NULL`,
      [userId, pairedSince],
    );
    return rows.map((r) => str(r.other));
  }

  async createDate(input: { id: string; userA: string; userB: string; createdAt: Date }): Promise<void> {
    await this.db.query('INSERT INTO dates (id, user_a, user_b, created_at) VALUES ($1, $2, $3, $4)', [
      input.id,
      input.userA,
      input.userB,
      input.createdAt,
    ]);
  }

  async markDateStarted(id: string, at: Date): Promise<void> {
    await this.db.query('UPDATE dates SET started_at = $2 WHERE id = $1', [id, at]);
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
    await this.db.query(
      `UPDATE dates SET ended_at = $2, end_reason = $3, outcome = $4, decision_a = $5, decision_b = $6
       WHERE id = $1`,
      [id, result.endedAt, result.endReason, result.outcome, result.decisions?.a ?? null, result.decisions?.b ?? null],
    );
  }

  async getDateStats(userId: string): Promise<DateStats> {
    const r = await this.one(
      `SELECT
         count(*) FILTER (WHERE mine IS NOT NULL)::int AS answered,
         count(*) FILTER (WHERE mine = 'yes')::int AS yes_given,
         count(*) FILTER (WHERE theirs IS NOT NULL)::int AS rated,
         count(*) FILTER (WHERE theirs = 'yes')::int AS yes_received
       FROM (
         SELECT decision_a AS mine, decision_b AS theirs FROM dates WHERE user_a = $1
         UNION ALL
         SELECT decision_b AS mine, decision_a AS theirs FROM dates WHERE user_b = $1
       ) d`,
      [userId],
    );
    return {
      answered: Number(r?.answered ?? 0),
      yesGiven: Number(r?.yes_given ?? 0),
      rated: Number(r?.rated ?? 0),
      yesReceived: Number(r?.yes_received ?? 0),
    };
  }

  async getDate(id: string): Promise<DateRecord | null> {
    const r = await this.one('SELECT * FROM dates WHERE id = $1', [id]);
    if (!r) return null;
    return {
      id: str(r.id),
      userA: strOrNull(r.user_a),
      userB: strOrNull(r.user_b),
      createdAt: toDate(r.created_at),
      startedAt: dateOrNull(r.started_at),
      endedAt: dateOrNull(r.ended_at),
      endReason: strOrNull(r.end_reason),
      outcome: strOrNull(r.outcome) as DateRecord['outcome'],
      decisionA: strOrNull(r.decision_a) as DateRecord['decisionA'],
      decisionB: strOrNull(r.decision_b) as DateRecord['decisionB'],
    };
  }

  async countDatesStarted(userId: string, since: Date): Promise<number> {
    const row = await this.one(
      `SELECT count(*)::int AS n FROM dates
       WHERE (user_a = $1 OR user_b = $1) AND started_at IS NOT NULL AND started_at >= $2`,
      [userId, since],
    );
    return row ? Number(row.n) : 0;
  }

  async createMatch(input: {
    userA: string;
    userB: string;
    dateId: string | null;
    matchedAt: Date;
  }): Promise<MatchRecord> {
    const [a, b] = input.userA < input.userB ? [input.userA, input.userB] : [input.userB, input.userA];
    const row = await this.one(
      `INSERT INTO matches (id, user_a, user_b, date_id, matched_at) VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_a, user_b) DO UPDATE SET user_a = EXCLUDED.user_a
       RETURNING *`,
      [newId(), a, b, input.dateId, input.matchedAt],
    );
    if (!row) throw new Error('createMatch returned no row');
    return toMatch(row);
  }

  async getMatch(id: string): Promise<MatchRecord | null> {
    const row = await this.one('SELECT * FROM matches WHERE id = $1', [id]);
    return row ? toMatch(row) : null;
  }

  async getMatchBetween(a: string, b: string): Promise<MatchRecord | null> {
    const [x, y] = a < b ? [a, b] : [b, a];
    const row = await this.one('SELECT * FROM matches WHERE user_a = $1 AND user_b = $2', [x, y]);
    return row ? toMatch(row) : null;
  }

  async listMatchSummaries(userId: string): Promise<MatchSummary[]> {
    const { rows } = await this.db.query(
      `SELECT m.id AS m_id, m.user_a AS m_user_a, m.user_b AS m_user_b, m.date_id AS m_date_id,
              m.matched_at AS m_matched_at,
              to_jsonb(p) AS partner,
              lm.id AS lm_id, lm.sender_id AS lm_sender_id, lm.text AS lm_text, lm.sent_at AS lm_sent_at,
              lm.client_id AS lm_client_id,
              (SELECT count(*)::int FROM messages x
                 WHERE x.match_id = m.id AND x.sender_id <> $1
                   AND (r.last_read_at IS NULL OR x.sent_at > r.last_read_at)) AS unread
       FROM matches m
       JOIN users p ON p.id = CASE WHEN m.user_a = $1 THEN m.user_b ELSE m.user_a END
       LEFT JOIN match_reads r ON r.match_id = m.id AND r.user_id = $1
       LEFT JOIN LATERAL (
         SELECT * FROM messages x WHERE x.match_id = m.id ORDER BY x.seq DESC LIMIT 1
       ) lm ON true
       WHERE m.user_a = $1 OR m.user_b = $1
       ORDER BY COALESCE(lm.sent_at, m.matched_at) DESC`,
      [userId],
    );
    return rows.map((r) => ({
      match: {
        id: str(r.m_id),
        userA: str(r.m_user_a),
        userB: str(r.m_user_b),
        dateId: strOrNull(r.m_date_id),
        matchedAt: toDate(r.m_matched_at),
      },
      partner: toUser(json<Row>(r.partner, {})),
      lastMessage:
        r.lm_id === null || r.lm_id === undefined
          ? null
          : {
              id: str(r.lm_id),
              matchId: str(r.m_id),
              senderId: str(r.lm_sender_id),
              text: str(r.lm_text),
              sentAt: toDate(r.lm_sent_at),
              clientId: strOrNull(r.lm_client_id),
            },
      unreadCount: Number(r.unread),
    }));
  }

  async deleteMatch(id: string): Promise<void> {
    await this.db.query('DELETE FROM matches WHERE id = $1', [id]);
  }

  async addMessage(input: AddMessageInput): Promise<{ message: MessageRecord; created: boolean }> {
    const inserted = await this.one(
      `INSERT INTO messages (id, match_id, sender_id, text, sent_at, client_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (match_id, sender_id, client_id) WHERE client_id IS NOT NULL DO NOTHING
       RETURNING *`,
      [newId(), input.matchId, input.senderId, input.text, input.sentAt, input.clientId],
    );
    if (inserted) return { message: toMessage(inserted), created: true };
    const existing = await this.one(
      'SELECT * FROM messages WHERE match_id = $1 AND sender_id = $2 AND client_id = $3',
      [input.matchId, input.senderId, input.clientId],
    );
    if (!existing) throw new Error('addMessage conflict without an existing row');
    return { message: toMessage(existing), created: false };
  }

  async listMessages(matchId: string, before: Date | null, limit: number): Promise<MessageRecord[]> {
    const { rows } = await this.db.query(
      `SELECT * FROM (
         SELECT * FROM messages
         WHERE match_id = $1 AND ($2::timestamptz IS NULL OR sent_at < $2::timestamptz)
         ORDER BY seq DESC LIMIT $3
       ) t ORDER BY seq ASC`,
      [matchId, before, limit],
    );
    return rows.map(toMessage);
  }

  async markRead(matchId: string, userId: string, at: Date): Promise<void> {
    await this.db.query(
      `INSERT INTO match_reads (match_id, user_id, last_read_at)
       SELECT $1, $2, $3 WHERE EXISTS (SELECT 1 FROM matches WHERE id = $1)
       ON CONFLICT (match_id, user_id) DO UPDATE SET last_read_at = EXCLUDED.last_read_at`,
      [matchId, userId, at],
    );
  }

  async addReport(input: AddReportInput): Promise<ReportRecord> {
    const id = newId();
    await this.db.query(
      `INSERT INTO reports (id, reporter_id, reported_user_id, date_id, match_id, reason, details, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        id,
        input.reporterId,
        input.reportedUserId,
        input.dateId,
        input.matchId,
        input.reason satisfies ReportReason,
        input.details,
        input.createdAt,
      ],
    );
    return { id, ...input };
  }

  async addAudit(input: AuditInput): Promise<AuditEvent> {
    const row = await this.one(
      `INSERT INTO audit_log (id, type, user_id, target_user_id, date_id, match_id, category, action, details)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
       RETURNING *`,
      [
        newId(),
        input.type,
        input.userId ?? null,
        input.targetUserId ?? null,
        input.dateId ?? null,
        input.matchId ?? null,
        input.category ?? null,
        input.action ?? null,
        JSON.stringify(input.details ?? {}),
      ],
    );
    if (!row) throw new Error('addAudit returned no row');
    return toAudit(row);
  }

  async listAudit(filter: { userId?: string; type?: AuditType }): Promise<AuditEvent[]> {
    const { rows } = await this.db.query(
      `SELECT * FROM audit_log
       WHERE ($1::uuid IS NULL OR user_id = $1::uuid) AND ($2::text IS NULL OR type = $2::text)
       ORDER BY seq ASC`,
      [filter.userId ?? null, filter.type ?? null],
    );
    return rows.map(toAudit);
  }

  async bindTransaction(originalTransactionId: string, userId: string): Promise<string | null> {
    return this.db.tx(async (q) => {
      const { rows } = await q.query(
        'SELECT user_id FROM iap_transactions WHERE original_transaction_id = $1 FOR UPDATE',
        [originalTransactionId],
      );
      const previous = rows[0] ? str(rows[0].user_id) : null;
      await q.query(
        `INSERT INTO iap_transactions (original_transaction_id, user_id) VALUES ($1, $2)
         ON CONFLICT (original_transaction_id) DO UPDATE SET user_id = EXCLUDED.user_id, updated_at = now()`,
        [originalTransactionId, userId],
      );
      return previous !== null && previous !== userId ? previous : null;
    });
  }

  async getTransactionOwner(originalTransactionId: string): Promise<string | null> {
    const row = await this.one('SELECT user_id FROM iap_transactions WHERE original_transaction_id = $1', [
      originalTransactionId,
    ]);
    return row ? str(row.user_id) : null;
  }

  async putDeletedIdentity(hash: string, value: DeletedIdentity): Promise<void> {
    await this.db.query(
      `INSERT INTO deleted_identities (identity_hash, strikes, suspended, suspended_until)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (identity_hash) DO UPDATE
         SET strikes = EXCLUDED.strikes, suspended = EXCLUDED.suspended, suspended_until = EXCLUDED.suspended_until`,
      [hash, value.strikes, value.suspended, value.suspendedUntil],
    );
  }

  async takeDeletedIdentity(hash: string): Promise<DeletedIdentity | null> {
    const row = await this.one('DELETE FROM deleted_identities WHERE identity_hash = $1 RETURNING *', [hash]);
    if (!row) return null;
    return {
      strikes: Number(row.strikes),
      suspended: row.suspended === true,
      suspendedUntil: dateOrNull(row.suspended_until),
    };
  }
}
