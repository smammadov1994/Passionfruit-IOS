import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { compatiblePair, pairUp, sleep, startServer, TestClient, type Msg, type TestServer } from './helpers.js';

let server: TestServer;
const clients: TestClient[] = [];
const track = <T extends { ca: TestClient; cb: TestClient }>(x: T): T => {
  clients.push(x.ca, x.cb);
  return x;
};

beforeEach(async () => {
  server = await startServer();
});
afterEach(async () => {
  await Promise.all(clients.splice(0).map((c) => c.close()));
  await server.close();
});

describe('full speed date over real WebSockets', () => {
  it('pairs, starts on ready, relays signals, runs turns, ends on the timer and matches on mutual yes', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId, matchedA, matchedB } = track(await pairUp(server, a, b));

    // date.matched: roles, partner card, ice servers.
    expect(matchedB.dateId).toBe(dateId);
    expect(matchedA.role).toBe('caller'); // waited longest
    expect(matchedB.role).toBe('callee');
    expect(matchedA.partner).toMatchObject({ id: b.id, firstName: 'Leo', age: expect.any(Number), city: 'New York' });
    expect((matchedA.partner as { distanceKm: number }).distanceKm).toBeGreaterThanOrEqual(1);
    expect(matchedB.partner).toMatchObject({ id: a.id, firstName: 'Maya' });
    expect(Array.isArray(matchedA.iceServers)).toBe(true);

    // Signalling is relayed verbatim, only to the partner.
    const offer = { kind: 'offer', sdp: 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n' };
    ca.send({ type: 'rtc.signal', dateId, payload: offer });
    expect(await cb.next('rtc.signal')).toEqual({ type: 'rtc.signal', dateId, payload: offer });
    const ice = { kind: 'ice', candidate: 'candidate:1 1 udp 1 1.2.3.4 5 typ host', sdpMid: '0', sdpMLineIndex: 0 };
    cb.send({ type: 'rtc.signal', dateId, payload: ice });
    expect(await ca.next('rtc.signal')).toEqual({ type: 'rtc.signal', dateId, payload: ice });
    expect(cb.count('rtc.signal')).toBe(1);

    // Both ready -> the clock starts right away (well before the ready timeout).
    const t0 = Date.now();
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    const startedA = await ca.next('date.started');
    const startedB = await cb.next('date.started');
    expect(Date.now() - t0).toBeLessThan(300);
    expect(startedA).toEqual(startedB);
    const startsAt = Date.parse(String(startedA.startsAt));
    const endsAt = Date.parse(String(startedA.endsAt));
    expect(String(startedA.startsAt)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    expect(endsAt - startsAt).toBe(server.ctx.config.dateDurationSec * 1000);

    // Turn 1: question 0, caller speaks first. Both clients see the identical frame.
    const turn1 = await ca.next('icebreaker.turn');
    expect(await cb.next('icebreaker.turn')).toEqual(turn1);
    expect(turn1).toMatchObject({ dateId, questionIndex: 0, speakerId: a.id, turnDurationSec: 0.25 });
    expect(typeof turn1.question).toBe('string');

    // Only the current speaker may pass.
    cb.send({ type: 'turn.pass', dateId });
    expect(await cb.next('error')).toMatchObject({ code: 'not_your_turn' });

    // Speaker passes -> same question, other person.
    ca.send({ type: 'turn.pass', dateId });
    const turn2 = await ca.next('icebreaker.turn');
    expect(turn2).toMatchObject({ questionIndex: 0, speakerId: b.id, question: turn1.question });
    expect(Date.parse(String(turn2.turnEndsAt)) - Date.parse(String(turn1.turnEndsAt))).toBeLessThan(250);

    // Turn 2 expires on its own -> new question, and the callee now goes first (alternation).
    const turn3 = await ca.next('icebreaker.turn');
    expect(turn3).toMatchObject({ questionIndex: 1, speakerId: b.id });
    expect(turn3.question).not.toBe(turn1.question);
    const turn4 = await ca.next('icebreaker.turn');
    expect(turn4).toMatchObject({ questionIndex: 1, speakerId: a.id, question: turn3.question });

    // Timer end -> decision window.
    const endedA = await ca.next('date.ended');
    const endedB = await cb.next('date.ended');
    expect(endedA).toMatchObject({ dateId, reason: 'timer' });
    expect(endedB).toEqual(endedA);
    const deadline = Date.parse(String(endedA.decisionDeadline));
    expect(deadline - Date.now()).toBeGreaterThan(300);
    expect(deadline - Date.now()).toBeLessThanOrEqual(600);
    expect(Math.abs(Date.now() - endsAt)).toBeLessThan(200);

    // No turn is ever repeated within a date, and turns stop when the date ends.
    const questions = ca.received.filter((m) => m.type === 'icebreaker.turn');
    const perIndex = new Map<number, string>();
    for (const q of questions) perIndex.set(Number(q.questionIndex), String(q.question));
    expect(new Set(perIndex.values()).size).toBe(perIndex.size);
    for (const q of questions) expect(Date.parse(String(q.turnEndsAt))).toBeLessThanOrEqual(endsAt);
    const turnsAtEnd = ca.count('icebreaker.turn');

    // The first yes is private: nothing is revealed until both have answered.
    ca.send({ type: 'date.decide', dateId, decision: 'yes' });
    await ca.expectNone('date.result', 120);
    cb.send({ type: 'date.decide', dateId, decision: 'yes' });
    const resultA = await ca.next('date.result');
    const resultB = await cb.next('date.result');
    expect(resultA).toMatchObject({ dateId, outcome: 'match' });
    expect(resultB).toMatchObject({ dateId, outcome: 'match' });
    const matchA = resultA.match as { id: string; partner: { id: string }; unreadCount: number; matchedAt: string };
    const matchB = resultB.match as { id: string; partner: { id: string } };
    expect(matchA.id).toBe(matchB.id);
    expect(matchA.partner.id).toBe(b.id);
    expect(matchB.partner.id).toBe(a.id);
    expect(matchA.unreadCount).toBe(0);
    expect(ca.count('icebreaker.turn')).toBe(turnsAtEnd);

    // The match is durable and visible to both over REST.
    const listA = await server.api<{ matches: Array<{ id: string }> }>('GET', '/v1/matches', a.token);
    expect(listA.body.matches.map((m) => m.id)).toEqual([matchA.id]);
    await server.ctx.dates.flush();
    const stored = await server.ctx.store.getDate(dateId);
    expect(stored).toMatchObject({ endReason: 'timer', outcome: 'match', decisionA: 'yes', decisionB: 'yes' });
    expect(stored?.startedAt).not.toBeNull();
    expect(server.ctx.dates.activeCount()).toBe(0);

    // Matched people are never put in a speed date together again.
    ca.send({ type: 'queue.join' });
    cb.send({ type: 'queue.join' });
    await ca.next('queue.status');
    await ca.expectNone('date.matched', 400);
  });

  it('starts after the ready timeout when a client never says ready', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    const t0 = Date.now();
    ca.send({ type: 'date.ready', dateId }); // only one side
    await cb.next('date.started');
    const waited = Date.now() - t0;
    expect(waited).toBeGreaterThanOrEqual(350);
    expect(waited).toBeLessThan(900);
  });

  it('yes + no is no match; a missing answer counts as no', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    await ca.next('date.ended', 4000);
    ca.send({ type: 'date.decide', dateId, decision: 'yes' });
    cb.send({ type: 'date.decide', dateId, decision: 'no' });
    expect(await ca.next('date.result')).toEqual({ type: 'date.result', dateId, outcome: 'no_match' });
    expect(await cb.next('date.result')).toEqual({ type: 'date.result', dateId, outcome: 'no_match' });
    expect((await server.api<{ matches: unknown[] }>('GET', '/v1/matches', a.token)).body.matches).toEqual([]);

    // Second date with different people: one says yes, the other never answers.
    const [c, d] = await compatiblePair(server);
    const second = track(await pairUp(server, c, d));
    const ended = await second.ca.next('date.ended', 4000);
    second.ca.send({ type: 'date.decide', dateId: second.dateId, decision: 'yes' });
    const result = await second.cb.next('date.result', 2000);
    expect(result).toMatchObject({ outcome: 'no_match' });
    expect(Date.now()).toBeGreaterThanOrEqual(Date.parse(String(ended.decisionDeadline)));
    expect(await second.ca.next('date.result')).toMatchObject({ outcome: 'no_match' });

    // Private answers are stored for ranking; the missing one is stored as no.
    await server.ctx.dates.flush();
    const answers = (await server.ctx.store.getDate(second.dateId)) ?? null;
    expect([answers?.decisionA, answers?.decisionB].sort()).toEqual(['no', 'yes']);
    expect(await server.ctx.store.getDateStats(c.id)).toEqual({ answered: 1, yesGiven: 1, rated: 1, yesReceived: 0 });
    expect(await server.ctx.store.getDateStats(d.id)).toEqual({ answered: 1, yesGiven: 0, rated: 1, yesReceived: 1 });
  });

  it('a decision cannot be changed and cannot be sent for someone else', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    await ca.next('date.ended', 4000);
    ca.send({ type: 'date.decide', dateId, decision: 'no' });
    ca.send({ type: 'date.decide', dateId, decision: 'yes' }); // ignored
    cb.send({ type: 'date.decide', dateId, decision: 'yes' });
    expect(await cb.next('date.result')).toMatchObject({ outcome: 'no_match' });
  });

  it('leaving early ends it for both with no decision screen', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    await ca.next('date.started');
    cb.send({ type: 'date.leave', dateId });
    expect(await cb.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'you_left' });
    expect(await ca.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'partner_left' });
    // No timer end, no result, no more turns: every timer for the date is gone.
    const turns = ca.count('icebreaker.turn');
    await sleep(1500);
    expect(ca.count('date.ended')).toBe(1);
    expect(ca.count('date.result')).toBe(0);
    expect(ca.count('icebreaker.turn')).toBe(turns);
    expect(server.ctx.dates.activeCount()).toBe(0);
    await server.ctx.dates.flush();
    expect(await server.ctx.store.getDate(dateId)).toMatchObject({ endReason: 'left', outcome: 'no_match' });
    // The person who was left can go straight back into the queue.
    ca.send({ type: 'queue.join' });
    expect(await ca.next('queue.status', 2000, (m) => m.position === 1)).toBeTruthy();
  });

  it('leaving before the date starts also ends it', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.leave', dateId });
    expect(await cb.next('date.ended')).toMatchObject({ reason: 'partner_left' });
    await cb.expectNone('date.started', 600);
    // A date that never started does not count toward the daily cap.
    expect((await server.api<{ datesToday: number }>('GET', '/v1/usage', a.token)).body.datesToday).toBe(0);
  });

  it('leaving during the decision window is a no for the leaver; the partner still gets a result', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    await ca.next('date.ended', 4000);
    ca.send({ type: 'date.leave', dateId });
    expect(await ca.next('date.result')).toMatchObject({ outcome: 'no_match' });
    await cb.expectNone('date.result', 100); // partner's window stays private
    cb.send({ type: 'date.decide', dateId, decision: 'yes' });
    expect(await cb.next('date.result')).toMatchObject({ outcome: 'no_match' });
  });

  it('a disconnect that outlasts the grace window ends the date for the partner', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    await ca.next('date.started');
    const t0 = Date.now();
    await cb.close();
    expect(await ca.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'disconnect' });
    expect(Date.now() - t0).toBeGreaterThanOrEqual(280); // not before the grace window
    expect(server.ctx.dates.activeCount()).toBe(0);

    // When the dropped client comes back it is told the date is over.
    const back = await TestClient.connect(server, b.token);
    clients.push(back);
    expect(await back.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'disconnect' });
  });

  it('reconnecting inside the grace window resumes the same date', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    const started = await cb.next('date.started');
    await cb.close();
    await sleep(100);
    const back = await TestClient.connect(server, b.token);
    clients.push(back);
    // The server replays where the date is: same clock, current turn.
    expect(await back.next('date.started')).toEqual(started);
    expect(await back.next('icebreaker.turn')).toMatchObject({ dateId });
    await sleep(400);
    expect(ca.count('date.ended')).toBe(0);
    // And the date carries on to its normal end for both.
    expect(await ca.next('date.ended', 3000)).toMatchObject({ reason: 'timer' });
    expect(await back.next('date.ended', 3000)).toMatchObject({ reason: 'timer' });
  });

  it('a disconnect while connecting ends the date immediately', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    await cb.close();
    expect(await ca.next('date.ended', 250)).toEqual({ type: 'date.ended', dateId, reason: 'disconnect' });
  });

  it('a newer socket replaces the old one without ending the date', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    await ca.next('date.started');
    const second = await TestClient.connect(server, b.token);
    clients.push(second);
    await second.next('date.started');
    await sleep(100);
    expect(cb.closed?.code).toBe(4000);
    await sleep(450); // longer than the grace window
    expect(ca.count('date.ended')).toBe(0);
  });

  it('only the two participants can act on a date', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    const outsider = await server.signUp({ gender: 'man', interestedIn: ['man'] });
    const co = await TestClient.connect(server, outsider.token);
    clients.push(co);
    for (const msg of [
      { type: 'rtc.signal', dateId, payload: { kind: 'offer', sdp: 'evil' } },
      { type: 'date.ready', dateId },
      { type: 'turn.pass', dateId },
      { type: 'date.leave', dateId },
      { type: 'date.decide', dateId, decision: 'yes' },
    ] satisfies Msg[]) {
      co.send(msg);
      expect(await co.next('error')).toMatchObject({ code: 'not_in_date' });
    }
    await sleep(100);
    expect(ca.count('rtc.signal') + cb.count('rtc.signal')).toBe(0);
    expect(ca.count('date.ended') + cb.count('date.ended')).toBe(0);
    expect(ca.count('date.started')).toBe(0); // outsider's "ready" did not start the clock early
  });

  it('rejects malformed frames without dropping the connection', async () => {
    const a = await server.signUp();
    const ca = await TestClient.connect(server, a.token);
    clients.push(ca);
    ca.socket.send('not json');
    expect(await ca.next('error')).toMatchObject({ code: 'bad_message' });
    ca.send({ type: 'no.such.type' });
    expect(await ca.next('error')).toMatchObject({ code: 'bad_message' });
    ca.send({ type: 'date.decide', dateId: 'not-a-uuid', decision: 'maybe' });
    expect(await ca.next('error')).toMatchObject({ code: 'bad_message' });
    ca.send({ type: 'ping' });
    expect(await ca.next('pong')).toEqual({ type: 'pong' });
  });
});

describe('queue', () => {
  it('sends queue.status on join and periodically, and stops after queue.leave', async () => {
    const a = await server.signUp();
    const ca = await TestClient.connect(server, a.token);
    clients.push(ca);
    ca.send({ type: 'queue.join' });
    expect(await ca.next('queue.status')).toEqual({ type: 'queue.status', compatibleOnline: 0, position: 1 });
    await ca.next('queue.status');
    await ca.next('queue.status');
    ca.send({ type: 'queue.leave' });
    await sleep(200);
    const n = ca.count('queue.status');
    await sleep(400);
    expect(ca.count('queue.status')).toBe(n);
  });

  it('reports compatible people online and pairs premium users first', async () => {
    const w1 = await server.signUp({ gender: 'woman', interestedIn: ['man'] });
    const wp = await server.signUp({ gender: 'woman', interestedIn: ['man'] });
    await server.ctx.store.updateUser(wp.id, { isPremium: true, premiumExpiresAt: new Date(Date.now() + 86_400_000) });
    const m = await server.signUp({ gender: 'man', interestedIn: ['woman'] });
    const c1 = await TestClient.connect(server, w1.token);
    const cp = await TestClient.connect(server, wp.token);
    const cm = await TestClient.connect(server, m.token);
    clients.push(c1, cp, cm);
    c1.send({ type: 'queue.join' });
    expect(await c1.next('queue.status')).toMatchObject({ position: 1 });
    cp.send({ type: 'queue.join' });
    expect(await cp.next('queue.status')).toMatchObject({ position: 1 }); // premium jumps ahead
    expect(await c1.next('queue.status', 2000, (s) => s.position === 2)).toBeTruthy();
    // The man is connected but not queued: he already counts as online for both women.
    expect(await c1.next('queue.status', 2000, (s) => s.compatibleOnline === 1)).toBeTruthy();
    const count = await server.api<{ compatibleOnline: number }>('GET', '/v1/online-count', m.token);
    expect(count.body.compatibleOnline).toBe(2);

    cm.send({ type: 'queue.join' });
    const matched = await cm.next('date.matched');
    expect((matched.partner as { id: string }).id).toBe(wp.id);
    await cp.next('date.matched');
    await c1.expectNone('date.matched', 300);
  });

  it('refuses the queue until onboarding is complete', async () => {
    const auth = await server.api<{ token: string }>('POST', '/v1/auth/dev', null, { deviceId: 'fresh-device' });
    const c = await TestClient.connect(server, auth.body.token);
    clients.push(c);
    c.send({ type: 'queue.join' });
    expect(await c.next('error')).toMatchObject({ code: 'onboarding_incomplete' });
  });

  it('rejects a WebSocket without a valid token before upgrading', async () => {
    await expect(TestClient.connect(server, 'garbage')).rejects.toThrow('HTTP 401');
    await expect(TestClient.connect(server, '')).rejects.toThrow('HTTP 401');
  });

  it('tells connected clients the server is going away on shutdown and stops every date timer', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = track(await pairUp(server, a, b));
    ca.send({ type: 'date.ready', dateId });
    cb.send({ type: 'date.ready', dateId });
    await ca.next('date.started');
    await server.close();
    await sleep(100);
    expect(ca.closed).toEqual({ code: 1001, reason: 'server shutting down' });
    expect(cb.closed?.code).toBe(1001);
    expect(server.ctx.dates.activeCount()).toBe(0);
    server = await startServer(); // afterEach closes this one
  });

  it('drops a silent connection after the idle timeout', async () => {
    await server.close();
    server = await startServer({ wsIdleTimeoutSec: 0.4 });
    const a = await server.signUp();
    const quiet = await TestClient.connect(server, a.token);
    const b = await server.signUp();
    const chatty = await TestClient.connect(server, b.token);
    clients.push(quiet, chatty);
    for (let i = 0; i < 8; i++) {
      chatty.send({ type: 'ping' });
      await sleep(100);
    }
    expect(quiet.closed?.code).toBe(4001);
    expect(chatty.closed).toBeNull();
  });
});
