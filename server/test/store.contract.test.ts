import { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MemoryStore } from '../src/store/MemoryStore.js';
import { runMigrations } from '../src/store/migrate.js';
import { PgStore, type Queryable, type Row } from '../src/store/PgStore.js';
import type { Store } from '../src/store/Store.js';

/** Runs PgStore's real SQL and the real migrations against PGlite (Postgres compiled to WASM). */
interface PgliteLike {
  query(text: string, params?: unknown[]): Promise<{ rows: unknown[] }>;
  exec(sql: string): Promise<unknown>;
}
function pgliteQueryable(db: PGlite): Queryable {
  const wrap = (x: PgliteLike, inTx: boolean): Queryable => ({
    query: async (text, params) => ({ rows: (await x.query(text, params ? [...params] : [])).rows as Row[] }),
    exec: async (sql) => {
      await x.exec(sql);
    },
    tx: (fn) => (inTx ? fn(wrap(x, true)) : db.transaction((t) => fn(wrap(t as unknown as PgliteLike, true)))),
    close: async () => {
      if (!inTx) await db.close();
    },
  });
  return wrap(db as unknown as PgliteLike, false);
}

const implementations: Array<[string, () => Promise<Store>]> = [
  ['MemoryStore', async () => new MemoryStore()],
  [
    'PgStore (PGlite)',
    async () => {
      const db = pgliteQueryable(new PGlite());
      expect(await runMigrations(db)).toEqual(['001_init.sql', '002_date_decisions.sql', '003_row_level_security.sql', '004_waitlist.sql']);
      expect(await runMigrations(db)).toEqual([]); // idempotent
      return new PgStore(db);
    },
  ],
];

describe.each(implementations)('Store contract: %s', (_name, make) => {
  let store: Store;
  beforeAll(async () => {
    store = await make();
  });
  afterAll(async () => {
    await store.close();
  });

  let n = 0;
  const user = (firstName = 'User') => store.createUser({ appleSub: `sub-${++n}-${Math.random()}`, firstName });
  const T = (ms: number) => new Date(Date.UTC(2026, 10, 14, 12, 0, 0) + ms);

  it('creates users with defaults, finds them by identity, and is idempotent per identity', async () => {
    const created = await store.createUser({ appleSub: 'apple:abc', firstName: 'Maya' });
    expect(created).toMatchObject({
      appleSub: 'apple:abc',
      firstName: 'Maya',
      birthdate: null,
      gender: null,
      interestedIn: [],
      photoUrls: [],
      isPremium: false,
      premiumExpiresAt: null,
      onboardingComplete: false,
      strikes: 0,
      suspended: false,
      suspendedUntil: null,
      apnsToken: null,
      pushEnabled: false,
      tzOffsetMinutes: 0,
      preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: false },
    });
    expect(created.createdAt).toBeInstanceOf(Date);
    expect((await store.getUserByAppleSub('apple:abc'))?.id).toBe(created.id);
    expect((await store.createUser({ appleSub: 'apple:abc', firstName: 'Other' })).id).toBe(created.id);
    expect(await store.getUser('11111111-1111-4111-8111-111111111111')).toBeNull();
    expect(await store.getUserByAppleSub('nope')).toBeNull();
    const carried = await store.createUser({ appleSub: 'apple:banned', firstName: '', strikes: 3, suspended: true });
    expect(carried).toMatchObject({ strikes: 3, suspended: true, suspendedUntil: null });
  });

  it('patches users without touching other fields and round-trips every type', async () => {
    const u = await user();
    const expires = T(86_400_000);
    const updated = await store.updateUser(u.id, {
      firstName: 'Leo',
      birthdate: '1994-02-03',
      gender: 'man',
      interestedIn: ['woman', 'nonbinary'],
      lat: 40.7128,
      lng: -74.006,
      photoUrls: ['https://x/a.jpg', 'https://x/b.jpg'],
      intention: 'marriage',
      education: 'doctorate',
      isPremium: true,
      premiumExpiresAt: expires,
      onboardingComplete: true,
      preferences: { ageMin: 25, ageMax: 35, maxDistanceKm: 12.5, notifyOnlineSingles: true, smokingOk: ['never'] },
      apnsToken: 'abcd',
      pushEnabled: true,
      tzOffsetMinutes: -300,
    });
    expect(updated).toMatchObject({
      firstName: 'Leo',
      birthdate: '1994-02-03',
      gender: 'man',
      interestedIn: ['woman', 'nonbinary'],
      lat: 40.7128,
      lng: -74.006,
      photoUrls: ['https://x/a.jpg', 'https://x/b.jpg'],
      intention: 'marriage',
      education: 'doctorate',
      isPremium: true,
      onboardingComplete: true,
      tzOffsetMinutes: -300,
      preferences: { ageMin: 25, ageMax: 35, maxDistanceKm: 12.5, notifyOnlineSingles: true, smokingOk: ['never'] },
    });
    expect(updated?.premiumExpiresAt?.getTime()).toBe(expires.getTime());
    const cleared = await store.updateUser(u.id, { intention: null, lat: null, lng: null, premiumExpiresAt: null });
    expect(cleared).toMatchObject({ intention: null, lat: null, lng: null, premiumExpiresAt: null, firstName: 'Leo', education: 'doctorate' });
    expect((await store.updateUser(u.id, {}))?.firstName).toBe('Leo');
    expect(await store.updateUser('11111111-1111-4111-8111-111111111111', { bio: 'x' })).toBeNull();
  });

  it('increments strikes atomically', async () => {
    const u = await user();
    const totals = await Promise.all([1, 2, 3, 4, 5].map(() => store.incrementStrikes(u.id)));
    expect(totals.sort()).toEqual([1, 2, 3, 4, 5]);
    expect((await store.getUser(u.id))?.strikes).toBe(5);
    expect(await store.incrementStrikes('11111111-1111-4111-8111-111111111111')).toBe(0);
  });

  it('tracks blocks in both directions', async () => {
    const [a, b, c] = [await user(), await user(), await user()];
    await store.addBlock(a.id, b.id, T(0));
    await store.addBlock(a.id, b.id, T(1)); // duplicate is fine
    expect(await store.isBlockedEither(a.id, b.id)).toBe(true);
    expect(await store.isBlockedEither(b.id, a.id)).toBe(true);
    expect(await store.isBlockedEither(a.id, c.id)).toBe(false);
  });

  it('lists exclusions: blocks either way, current matches, and pairings inside the cooldown', async () => {
    const me = await user();
    const blocked = await user();
    const blocker = await user();
    const matchedWith = await user();
    const recent = await user();
    const old = await user();
    const stranger = await user();
    await store.addBlock(me.id, blocked.id, T(0));
    await store.addBlock(blocker.id, me.id, T(0));
    const match = await store.createMatch({ userA: matchedWith.id, userB: me.id, dateId: null, matchedAt: T(0) });
    await store.createDate({ id: crypto.randomUUID(), userA: me.id, userB: recent.id, createdAt: T(-1000) });
    await store.createDate({ id: crypto.randomUUID(), userA: old.id, userB: me.id, createdAt: T(-25 * 3_600_000) });
    const since = T(-24 * 3_600_000);
    expect((await store.listExclusions(me.id, since)).sort()).toEqual([blocked.id, blocker.id, matchedWith.id, recent.id].sort());
    expect(await store.listExclusions(recent.id, since)).toEqual([me.id]);
    expect(await store.listExclusions(old.id, since)).toEqual([]);
    expect(await store.listExclusions(stranger.id, since)).toEqual([]);
    await store.deleteMatch(match.id);
    expect(await store.listExclusions(matchedWith.id, since)).toEqual([]);
  });

  it('stores private answers and reports each side\'s yes/no history', async () => {
    const [a, b, c] = [await user(), await user(), await user()];
    expect(await store.getDateStats(a.id)).toEqual({ answered: 0, yesGiven: 0, rated: 0, yesReceived: 0 });
    const date = async (userA: string, userB: string, decisions?: { a: 'yes' | 'no'; b: 'yes' | 'no' }): Promise<string> => {
      const id = crypto.randomUUID();
      await store.createDate({ id, userA, userB, createdAt: T(0) });
      await store.finishDate(id, {
        endedAt: T(9000),
        endReason: decisions ? 'timer' : 'left',
        outcome: decisions?.a === 'yes' && decisions.b === 'yes' ? 'match' : 'no_match',
        ...(decisions ? { decisions } : {}),
      });
      return id;
    };
    const first = await date(a.id, b.id, { a: 'yes', b: 'no' });
    await date(c.id, a.id, { a: 'yes', b: 'yes' });
    const leftEarly = await date(a.id, c.id); // ended before the yes/no screen: no answers

    expect(await store.getDate(first)).toMatchObject({ decisionA: 'yes', decisionB: 'no' });
    expect(await store.getDate(leftEarly)).toMatchObject({ decisionA: null, decisionB: null });
    expect(await store.getDateStats(a.id)).toEqual({ answered: 2, yesGiven: 2, rated: 2, yesReceived: 1 });
    expect(await store.getDateStats(b.id)).toEqual({ answered: 1, yesGiven: 0, rated: 1, yesReceived: 1 });
    expect(await store.getDateStats(c.id)).toEqual({ answered: 1, yesGiven: 1, rated: 1, yesReceived: 1 });
  });

  it('records the date lifecycle and counts only started dates in the window', async () => {
    const [a, b] = [await user(), await user()];
    const id = crypto.randomUUID();
    await store.createDate({ id, userA: a.id, userB: b.id, createdAt: T(0) });
    expect(await store.getDate(id)).toMatchObject({ userA: a.id, userB: b.id, startedAt: null, endedAt: null, outcome: null });
    expect(await store.countDatesStarted(a.id, T(-1000))).toBe(0);
    await store.markDateStarted(id, T(5000));
    await store.finishDate(id, { endedAt: T(9000), endReason: 'timer', outcome: 'match' });
    const stored = await store.getDate(id);
    expect(stored).toMatchObject({ endReason: 'timer', outcome: 'match' });
    expect(stored?.startedAt?.getTime()).toBe(T(5000).getTime());
    expect(await store.countDatesStarted(a.id, T(5000))).toBe(1); // inclusive lower bound
    expect(await store.countDatesStarted(b.id, T(0))).toBe(1);
    expect(await store.countDatesStarted(a.id, T(5001))).toBe(0);
    expect(await store.getDate(crypto.randomUUID())).toBeNull();
  });

  it('creates one match per pair regardless of order', async () => {
    const [a, b] = [await user(), await user()];
    const first = await store.createMatch({ userA: a.id, userB: b.id, dateId: null, matchedAt: T(0) });
    const again = await store.createMatch({ userA: b.id, userB: a.id, dateId: null, matchedAt: T(5) });
    expect(again.id).toBe(first.id);
    expect((await store.getMatchBetween(b.id, a.id))?.id).toBe(first.id);
    expect((await store.getMatch(first.id))?.matchedAt.getTime()).toBe(T(0).getTime());
    expect([first.userA, first.userB].sort()).toEqual([a.id, b.id].sort());
    expect(await store.getMatchBetween(a.id, (await user()).id)).toBeNull();
  });

  it('stores messages idempotently, pages them, and computes unread counts and summaries', async () => {
    const [a, b, c] = [await user('Ann'), await user('Bob'), await user('Cy')];
    const m = await store.createMatch({ userA: a.id, userB: b.id, dateId: null, matchedAt: T(0) });
    const quiet = await store.createMatch({ userA: a.id, userB: c.id, dateId: null, matchedAt: T(500) });
    const send = (senderId: string, text: string, at: number, clientId: string | null = null) =>
      store.addMessage({ matchId: m.id, senderId, text, clientId, sentAt: T(at) });

    const one = await send(a.id, 'one', 1000, 'k1');
    expect(one.created).toBe(true);
    const dup = await send(a.id, 'one again', 1500, 'k1');
    expect(dup).toMatchObject({ created: false, message: { id: one.message.id, text: 'one' } });
    await send(b.id, 'two', 2000, 'k1'); // same clientId, different sender
    await send(a.id, 'three', 3000);
    await send(a.id, 'four', 3000); // identical timestamp keeps insertion order

    expect((await store.listMessages(m.id, null, 50)).map((x) => x.text)).toEqual(['one', 'two', 'three', 'four']);
    expect((await store.listMessages(m.id, null, 2)).map((x) => x.text)).toEqual(['three', 'four']);
    expect((await store.listMessages(m.id, T(3000), 2)).map((x) => x.text)).toEqual(['one', 'two']);
    expect(await store.listMessages(m.id, T(1000), 50)).toEqual([]);

    let forB = await store.listMatchSummaries(b.id);
    expect(forB).toHaveLength(1);
    expect(forB[0]).toMatchObject({ unreadCount: 3, partner: { id: a.id, firstName: 'Ann' }, lastMessage: { text: 'four' } });
    expect(forB[0]?.partner.createdAt).toBeInstanceOf(Date);
    await store.markRead(m.id, b.id, T(3000));
    forB = await store.listMatchSummaries(b.id);
    expect(forB[0]?.unreadCount).toBe(0);
    await send(a.id, 'five', 4000);
    expect((await store.listMatchSummaries(b.id))[0]?.unreadCount).toBe(1);

    // Most recent activity first; a match with no messages sorts by when it was made.
    const forA = await store.listMatchSummaries(a.id);
    expect(forA.map((s) => s.match.id)).toEqual([m.id, quiet.id]);
    expect(forA[0]?.unreadCount).toBe(1);
    expect(forA[1]).toMatchObject({ lastMessage: null, unreadCount: 0, partner: { firstName: 'Cy' } });

    await store.deleteMatch(m.id);
    expect(await store.getMatch(m.id)).toBeNull();
    expect(await store.listMessages(m.id, null, 50)).toEqual([]);
    expect((await store.listMatchSummaries(a.id)).map((s) => s.match.id)).toEqual([quiet.id]);
  });

  it('keeps an audit trail and reports', async () => {
    const [a, b] = [await user(), await user()];
    await store.addAudit({ type: 'moderation.frame', userId: a.id, targetUserId: b.id, dateId: 'call:abc', category: 'nudity', action: 'end', details: { score: 0.99 } });
    await store.addAudit({ type: 'strike', userId: a.id, details: { strikes: 1 } });
    await store.addAudit({ type: 'block', userId: b.id, targetUserId: a.id });
    const mine = await store.listAudit({ userId: a.id });
    expect(mine.map((e) => e.type)).toEqual(['moderation.frame', 'strike']);
    expect(mine[0]).toMatchObject({ targetUserId: b.id, dateId: 'call:abc', category: 'nudity', action: 'end', details: { score: 0.99 } });
    expect(mine[1]).toMatchObject({ targetUserId: null, dateId: null, details: { strikes: 1 } });
    expect(await store.listAudit({ userId: a.id, type: 'strike' })).toHaveLength(1);
    expect((await store.listAudit({ type: 'block' })).some((e) => e.userId === b.id)).toBe(true);

    const report = await store.addReport({
      reporterId: a.id,
      reportedUserId: b.id,
      dateId: null,
      matchId: null,
      reason: 'harassment',
      details: 'details',
      createdAt: T(0),
    });
    expect(report.id).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('lists push candidates: opted in, with a token, onboarded, not suspended, not recently notified', async () => {
    const make = async (patch: Parameters<Store['updateUser']>[1]) => {
      const u = await user();
      await store.updateUser(u.id, {
        apnsToken: 'aa',
        pushEnabled: true,
        onboardingComplete: true,
        preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: true },
        ...patch,
      });
      return u.id;
    };
    const never = await make({});
    const longAgo = await make({ lastOnlinePushAt: T(-5 * 3_600_000) });
    const recently = await make({ lastOnlinePushAt: T(-3 * 3_600_000) });
    const optedOut = await make({ preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: false } });
    const disabled = await make({ pushEnabled: false });
    const noToken = await make({ apnsToken: null });
    const suspended = await make({ suspended: true });
    const notOnboarded = await make({ onboardingComplete: false });
    const ids = (await store.listPushCandidates(T(-4 * 3_600_000), 1000)).map((u) => u.id);
    expect(ids).toEqual(expect.arrayContaining([never, longAgo]));
    for (const id of [recently, optedOut, disabled, noToken, suspended, notOnboarded]) expect(ids).not.toContain(id);
    expect(await store.listPushCandidates(T(-4 * 3_600_000), 1)).toHaveLength(1);
  });

  it('binds purchases to one account at a time and carries strikes across deletion', async () => {
    const [a, b] = [await user(), await user()];
    expect(await store.getTransactionOwner('tx-1')).toBeNull();
    expect(await store.bindTransaction('tx-1', a.id)).toBeNull();
    expect(await store.bindTransaction('tx-1', a.id)).toBeNull();
    expect(await store.bindTransaction('tx-1', b.id)).toBe(a.id);
    expect(await store.getTransactionOwner('tx-1')).toBe(b.id);

    await store.putDeletedIdentity('hash-1', { strikes: 2, suspended: false, suspendedUntil: null });
    await store.putDeletedIdentity('hash-1', { strikes: 3, suspended: true, suspendedUntil: T(1000) });
    const taken = await store.takeDeletedIdentity('hash-1');
    expect(taken).toMatchObject({ strikes: 3, suspended: true });
    expect(taken?.suspendedUntil?.getTime()).toBe(T(1000).getTime());
    expect(await store.takeDeletedIdentity('hash-1')).toBeNull();
  });

  it('hard-deletes a user and everything that belongs to them, keeping only anonymous safety records', async () => {
    const [gone, partner, third] = [await user('Gone'), await user('Partner'), await user('Third')];
    const m = await store.createMatch({ userA: gone.id, userB: partner.id, dateId: null, matchedAt: T(0) });
    const other = await store.createMatch({ userA: partner.id, userB: third.id, dateId: null, matchedAt: T(0) });
    await store.addMessage({ matchId: m.id, senderId: gone.id, text: 'mine', clientId: 'a', sentAt: T(1) });
    await store.addMessage({ matchId: m.id, senderId: partner.id, text: 'theirs', clientId: 'a', sentAt: T(2) });
    await store.addMessage({ matchId: other.id, senderId: third.id, text: 'unrelated', clientId: 'a', sentAt: T(3) });
    await store.markRead(m.id, gone.id, T(5));
    await store.addBlock(gone.id, third.id, T(0));
    await store.addBlock(third.id, gone.id, T(0));
    const dateId = crypto.randomUUID();
    await store.createDate({ id: dateId, userA: partner.id, userB: gone.id, createdAt: T(0) });
    await store.markDateStarted(dateId, T(10));
    await store.bindTransaction('tx-gone', gone.id);
    await store.addReport({ reporterId: gone.id, reportedUserId: third.id, dateId: null, matchId: null, reason: 'spam', details: null, createdAt: T(0) });
    await store.addReport({ reporterId: partner.id, reportedUserId: gone.id, dateId, matchId: null, reason: 'harassment', details: null, createdAt: T(0) });
    await store.addAudit({ type: 'strike', userId: gone.id });

    await store.deleteUser(gone.id);
    await store.deleteUser(gone.id); // deleting twice is harmless

    expect(await store.getUser(gone.id)).toBeNull();
    expect(await store.getUserByAppleSub(gone.appleSub)).toBeNull();
    expect(await store.getMatch(m.id)).toBeNull();
    expect(await store.listMessages(m.id, null, 50)).toEqual([]);
    expect(await store.getTransactionOwner('tx-gone')).toBeNull();
    expect(await store.isBlockedEither(gone.id, third.id)).toBe(false);
    expect(await store.listExclusions(third.id, T(-1000))).toEqual([partner.id]);
    // The partner keeps their other match, their messages there, and their daily count.
    expect((await store.listMatchSummaries(partner.id)).map((s) => s.match.id)).toEqual([other.id]);
    expect((await store.listMessages(other.id, null, 50)).map((x) => x.text)).toEqual(['unrelated']);
    expect(await store.countDatesStarted(partner.id, T(0))).toBe(1);
    const date = await store.getDate(dateId);
    expect(date).toMatchObject({ userA: partner.id, userB: null });
    expect(await store.listAudit({ userId: gone.id })).toHaveLength(1);
    // A fresh account can be created for the same identity afterwards.
    const reborn = await store.createUser({ appleSub: gone.appleSub, firstName: '' });
    expect(reborn.id).not.toBe(gone.id);
    expect(await store.listMatchSummaries(reborn.id)).toEqual([]);
  });
});
