import { describe, expect, it } from 'vitest';
import type { FastifyBaseLogger } from 'fastify';
import { candidateFromUser } from '../src/matchmaking/compat.js';
import { InMemoryMatchmaker } from '../src/matchmaking/Matchmaker.js';
import { NoopPushProvider, type PushProvider } from '../src/push/PushProvider.js';
import { OnlinePushScheduler } from '../src/push/scheduler.js';
import { MemoryStore } from '../src/store/MemoryStore.js';
import type { UserRecord } from '../src/types.js';

const HOUR = 3_600_000;
const noopLog = { error() {}, warn() {}, info() {}, debug() {} } as unknown as FastifyBaseLogger;

async function setup(pushOverride?: PushProvider) {
  const store = new MemoryStore();
  const matchmaker = new InMemoryMatchmaker();
  const push = new NoopPushProvider();
  const clock = { t: Date.UTC(2026, 10, 14, 17, 0, 0), now: () => clock.t }; // 12:00 in New York
  const scheduler = new OnlinePushScheduler({
    config: {
      provider: 'noop',
      apnsKeyPath: undefined,
      apnsKeyId: undefined,
      apnsTeamId: undefined,
      apnsProduction: false,
      schedulerIntervalSec: 300,
      minIntervalHours: 4,
      minCompatible: 3,
      localHourStart: 9,
      localHourEnd: 23,
      repairCooldownHours: 24,
    },
    clock,
    store,
    matchmaker,
    push: pushOverride ?? push,
    log: noopLog,
  });

  let n = 0;
  const person = async (gender: 'woman' | 'man', patch: Partial<UserRecord> = {}): Promise<UserRecord> => {
    const u = await store.createUser({ appleSub: `s${++n}`, firstName: `P${n}` });
    return (await store.updateUser(u.id, {
      birthdate: '1995-01-01',
      gender,
      interestedIn: [gender === 'woman' ? 'man' : 'woman'],
      onboardingComplete: true,
      tzOffsetMinutes: -300,
      ...patch,
    })) as UserRecord;
  };
  const online = async (user: UserRecord): Promise<void> => {
    const c = candidateFromUser(user, [], clock.now());
    if (c) matchmaker.setOnline(c);
  };
  const subscriber = (patch: Partial<UserRecord> = {}) =>
    person('woman', {
      apnsToken: 'ab'.repeat(32),
      pushEnabled: true,
      preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: true },
      ...patch,
    });
  const menOnline = async (count: number): Promise<UserRecord[]> => {
    const men: UserRecord[] = [];
    for (let i = 0; i < count; i++) {
      const m = await person('man');
      await online(m);
      men.push(m);
    }
    return men;
  };
  return { store, matchmaker, push, clock, scheduler, person, online, subscriber, menOnline };
}

describe('"N compatible singles are online now" push', () => {
  it('sends when N >= 3 with the real count, then at most once per 4 hours', async () => {
    const t = await setup();
    const me = await t.subscriber();
    await t.menOnline(4);
    expect(await t.scheduler.runOnce()).toBe(1);
    expect(t.push.sent).toHaveLength(1);
    expect(t.push.sent[0]).toMatchObject({
      deviceToken: 'ab'.repeat(32),
      message: { body: '4 compatible singles are online now', collapseId: 'online-singles' },
    });
    expect((await t.store.getUser(me.id))?.lastOnlinePushAt?.getTime()).toBe(t.clock.now());

    // Every later pass inside the window is silent, right up to the last millisecond.
    for (const dt of [1000, HOUR, 2 * HOUR, 4 * HOUR - 1001]) {
      t.clock.t += dt === 1000 ? 1000 : dt - (t.clock.t - Date.UTC(2026, 10, 14, 17, 0, 0));
      expect(await t.scheduler.runOnce()).toBe(0);
    }
    expect(t.push.sent).toHaveLength(1);
    t.clock.t = Date.UTC(2026, 10, 14, 17, 0, 0) + 4 * HOUR + 1;
    expect(await t.scheduler.runOnce()).toBe(1);
    expect(t.push.sent).toHaveLength(2);
  });

  it('does not send when fewer than 3 compatible people are online', async () => {
    const t = await setup();
    await t.subscriber();
    await t.menOnline(2);
    // Plenty of people online, but not compatible ones.
    for (let i = 0; i < 5; i++) await t.online(await t.person('woman'));
    expect(await t.scheduler.runOnce()).toBe(0);
    await t.menOnline(1);
    expect(await t.scheduler.runOnce()).toBe(1);
    expect(t.push.sent[0]?.message.body).toBe('3 compatible singles are online now');
  });

  it('counts only people the user could actually be paired with', async () => {
    const t = await setup();
    const me = await t.subscriber();
    const men = await t.menOnline(3);
    await t.store.addBlock(me.id, (men[0] as UserRecord).id, new Date());
    expect(await t.scheduler.runOnce()).toBe(0); // one of the three is blocked
    await t.menOnline(1);
    expect(await t.scheduler.runOnce()).toBe(1);
  });

  it('never sends to people who have not opted in, have no token, are suspended, or are online themselves', async () => {
    const t = await setup();
    await t.subscriber({ preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: false } });
    await t.subscriber({ pushEnabled: false });
    await t.subscriber({ apnsToken: null });
    await t.subscriber({ suspended: true });
    const here = await t.subscriber({ apnsToken: 'cd'.repeat(32) });
    await t.online(here);
    await t.menOnline(5);
    expect(await t.scheduler.runOnce()).toBe(0);
    expect(t.push.sent).toEqual([]);
    // The moment she goes offline she becomes eligible.
    t.matchmaker.setOffline(here.id);
    expect(await t.scheduler.runOnce()).toBe(1);
    expect(t.push.sent[0]?.deviceToken).toBe('cd'.repeat(32));
  });

  it('stays quiet at night in the user local time', async () => {
    const t = await setup();
    await t.subscriber({ tzOffsetMinutes: 540 }); // Tokyo: 02:00 local
    await t.menOnline(3);
    expect(await t.scheduler.runOnce()).toBe(0);
    t.clock.t += 8 * HOUR; // 10:00 in Tokyo
    expect(await t.scheduler.runOnce()).toBe(1);
  });

  it('forgets a device token APNs says is gone, and a failed send still respects the 4 hour window', async () => {
    let mode: 'gone' | 'error' = 'error';
    let calls = 0;
    const flaky: PushProvider = {
      send: async () => {
        calls += 1;
        return mode === 'gone' ? { ok: false, unregistered: true, reason: 'Unregistered' } : { ok: false, reason: 'timeout' };
      },
      close: async () => {},
    };
    const t = await setup(flaky);
    const me = await t.subscriber();
    await t.menOnline(3);
    expect(await t.scheduler.runOnce()).toBe(0);
    expect(await t.scheduler.runOnce()).toBe(0);
    expect(calls).toBe(1); // not retried inside the window
    t.clock.t += 5 * HOUR;
    mode = 'gone';
    await t.scheduler.runOnce();
    expect(await t.store.getUser(me.id)).toMatchObject({ apnsToken: null, pushEnabled: false });
  });
});
