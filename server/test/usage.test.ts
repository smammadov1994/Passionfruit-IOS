import { afterEach, describe, expect, it } from 'vitest';
import { UsageService } from '../src/services/usage.js';
import { MemoryStore } from '../src/store/MemoryStore.js';
import { localDayBounds } from '../src/util.js';
import { compatiblePair, pairUp, startServer, TestClient, type TestServer } from './helpers.js';

describe('daily cap arithmetic', () => {
  it('finds local midnight for offsets east and west of UTC', () => {
    const now = Date.UTC(2026, 10, 14, 3, 30); // 03:30 UTC
    // New York (UTC-5): local time is 22:30 on the 13th.
    expect(localDayBounds(now, -300)).toEqual({
      start: Date.UTC(2026, 10, 13, 5, 0),
      end: Date.UTC(2026, 10, 14, 5, 0),
    });
    // Tokyo (UTC+9): local time is 12:30 on the 14th.
    expect(localDayBounds(now, 540)).toEqual({
      start: Date.UTC(2026, 10, 13, 15, 0),
      end: Date.UTC(2026, 10, 14, 15, 0),
    });
    expect(localDayBounds(now, 0).start).toBe(Date.UTC(2026, 10, 14, 0, 0));
    // India (UTC+5:30) exercises a half-hour offset.
    expect(localDayBounds(now, 330).start).toBe(Date.UTC(2026, 10, 13, 18, 30));
  });

  it('counts only dates that started today (user-local), caps free users at 5 and resets at local midnight', async () => {
    const store = new MemoryStore();
    let now = Date.UTC(2026, 10, 14, 3, 30); // 22:30 on the 13th in New York
    const usage = new UsageService(store, { freeDailyDates: 5 }, { now: () => now });
    const me = await store.createUser({ appleSub: 'me', firstName: 'Me' });
    const other = await store.createUser({ appleSub: 'other', firstName: 'Other' });
    await store.updateUser(me.id, { tzOffsetMinutes: -300 });
    const user = async () => (await store.getUser(me.id))!;

    const addDate = async (startedAt: number | null) => {
      const id = crypto.randomUUID();
      await store.createDate({ id, userA: other.id, userB: me.id, createdAt: new Date(now) });
      if (startedAt !== null) await store.markDateStarted(id, new Date(startedAt));
    };

    // Yesterday (local) and a date that was paired but never started: neither counts.
    await addDate(Date.UTC(2026, 10, 13, 4, 59)); // 23:59 on the 12th local
    await addDate(null);
    expect(await usage.get(await user())).toMatchObject({ datesToday: 0, limit: 5, capped: false });

    for (let i = 0; i < 4; i++) await addDate(Date.UTC(2026, 10, 13, 6 + i, 0));
    let u = await usage.get(await user());
    expect(u).toMatchObject({ datesToday: 4, capped: false });
    expect(u.resetsAt.toISOString()).toBe('2026-11-14T05:00:00.000Z'); // midnight in New York

    await addDate(Date.UTC(2026, 10, 14, 3, 0));
    u = await usage.get(await user());
    expect(u).toMatchObject({ datesToday: 5, limit: 5, capped: true });

    // One minute before local midnight: still capped. At local midnight: reset.
    now = Date.UTC(2026, 10, 14, 4, 59);
    expect((await usage.get(await user())).capped).toBe(true);
    now = Date.UTC(2026, 10, 14, 5, 0);
    u = await usage.get(await user());
    expect(u).toMatchObject({ datesToday: 0, capped: false });
    expect(u.resetsAt.toISOString()).toBe('2026-11-15T05:00:00.000Z');

    // The same instant is still "the same day" for the same history seen from UTC.
    await store.updateUser(me.id, { tzOffsetMinutes: 0 });
    expect((await usage.get(await user())).datesToday).toBe(1);
  });

  it('premium is unlimited, and an expired subscription is free again', async () => {
    const store = new MemoryStore();
    const now = Date.UTC(2026, 10, 14, 12, 0);
    const usage = new UsageService(store, { freeDailyDates: 5 }, { now: () => now });
    const me = await store.createUser({ appleSub: 'me', firstName: 'Me' });
    for (let i = 0; i < 7; i++) {
      const id = crypto.randomUUID();
      await store.createDate({ id, userA: me.id, userB: me.id, createdAt: new Date(now) });
      await store.markDateStarted(id, new Date(now - 1000));
    }
    const active = await store.updateUser(me.id, { isPremium: true, premiumExpiresAt: new Date(now + 1000) });
    expect(await usage.get(active!)).toMatchObject({ datesToday: 7, limit: null, capped: false });
    const lapsed = await store.updateUser(me.id, { isPremium: true, premiumExpiresAt: new Date(now - 1000) });
    expect(await usage.get(lapsed!)).toMatchObject({ limit: 5, capped: true });
  });
});

describe('daily cap over the wire', () => {
  let server: TestServer;
  const clients: TestClient[] = [];
  afterEach(async () => {
    await Promise.all(clients.splice(0).map((c) => c.close()));
    await server.close();
  });

  it('a date counts when it starts; a capped free user gets queue.limit and is not queued', async () => {
    server = await startServer({ freeDailyDates: 1 });
    const [a, b] = await compatiblePair(server);
    await server.api('POST', '/v1/me/push-token', a.token, { apnsToken: '', tzOffsetMinutes: -300, enabled: false });
    await server.ctx.store.updateUser(b.id, { isPremium: true, premiumExpiresAt: null });

    const before = await server.api<{ datesToday: number; limit: number | null; resetsAt: string }>('GET', '/v1/usage', a.token);
    expect(before.body).toMatchObject({ datesToday: 0, limit: 1 });
    expect((await server.api<{ limit: number | null }>('GET', '/v1/usage', b.token)).body.limit).toBeNull();

    const { ca, cb, dateId } = await pairUp(server, a, b);
    clients.push(ca, cb);
    expect((await server.api<{ datesToday: number }>('GET', '/v1/usage', a.token)).body.datesToday).toBe(0); // matched, not started
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    await ca.next('date.started');
    await server.ctx.dates.flush();
    const after = await server.api<{ datesToday: number; resetsAt: string }>('GET', '/v1/usage', a.token);
    expect(after.body.datesToday).toBe(1);

    ca.send({ type: 'date.leave', dateId });
    await ca.next('date.ended');

    // Free user: capped. resetsAt is the next local midnight for UTC-5.
    ca.send({ type: 'queue.join' });
    const limit = await ca.next('queue.limit');
    expect(limit).toEqual({ type: 'queue.limit', limit: 1, resetsAt: after.body.resetsAt });
    expect(new Date(after.body.resetsAt).getUTCHours()).toBe(5);
    expect(new Date(after.body.resetsAt).getTime()).toBeGreaterThan(Date.now());
    await ca.expectNone('queue.status', 400);
    expect(server.ctx.matchmaker.isQueued(a.id)).toBe(false);

    // Premium partner: same history, no cap.
    cb.send({ type: 'queue.join' });
    expect(await cb.next('queue.status')).toMatchObject({ position: 1 });
  });
});
