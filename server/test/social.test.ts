import { existsSync, readdirSync } from 'node:fs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  compatiblePair,
  fakeJpegBase64,
  pairUp,
  sleep,
  startServer,
  TestClient,
  type TestServer,
  type TestUser,
} from './helpers.js';

let server: TestServer;
const clients: TestClient[] = [];
const connect = async (user: TestUser): Promise<TestClient> => {
  const c = await TestClient.connect(server, user.token);
  clients.push(c);
  return c;
};

beforeEach(async () => {
  server = await startServer({ repairCooldownHours: 0 });
});
afterEach(async () => {
  await Promise.all(clients.splice(0).map((c) => c.close()));
  await server.close();
});

/** Creates a match directly in the store (the date flow that produces one is covered elsewhere). */
async function matched(): Promise<{ a: TestUser; b: TestUser; matchId: string }> {
  const [a, b] = await compatiblePair(server);
  const match = await server.ctx.store.createMatch({ userA: a.id, userB: b.id, dateId: null, matchedAt: new Date() });
  return { a, b, matchId: match.id };
}

interface WireMessage {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  sentAt: string;
  clientId?: string;
}
interface WireMatch {
  id: string;
  partner: { id: string; firstName: string; age: number };
  unreadCount: number;
  lastMessage?: WireMessage;
}

describe('chat', () => {
  it('delivers messages over the socket, keeps history, and tracks unread counts and the read marker', async () => {
    const { a, b, matchId } = await matched();
    const cb = await connect(b);
    const ca = await connect(a);

    const sent = await server.api<WireMessage>('POST', `/v1/matches/${matchId}/messages`, a.token, {
      text: '  Hello there  ',
      clientId: 'c-1',
    });
    expect(sent.status).toBe(200);
    expect(sent.body).toMatchObject({ matchId, senderId: a.id, text: 'Hello there', clientId: 'c-1' });
    expect(sent.body.sentAt).toMatch(/\.\d{3}Z$/);

    // Pushed to the partner, not echoed to the sender.
    expect(await cb.next('chat.message')).toEqual({ type: 'chat.message', message: sent.body });
    await ca.expectNone('chat.message', 100);

    // Retrying with the same clientId is idempotent: same message, no second delivery.
    const retry = await server.api<WireMessage>('POST', `/v1/matches/${matchId}/messages`, a.token, {
      text: 'Hello there',
      clientId: 'c-1',
    });
    expect(retry.body.id).toBe(sent.body.id);
    await cb.expectNone('chat.message', 100);

    await sleep(5);
    await server.api('POST', `/v1/matches/${matchId}/messages`, a.token, { text: 'Second', clientId: 'c-2' });
    await sleep(5);
    const reply = await server.api<WireMessage>('POST', `/v1/matches/${matchId}/messages`, b.token, {
      text: 'Hi!',
      clientId: 'c-1', // same clientId from a different sender is a different message
    });
    expect(reply.body.id).not.toBe(sent.body.id);
    expect(await ca.next('chat.message')).toMatchObject({ message: { text: 'Hi!', senderId: b.id } });

    // History is oldest first; `before` and `limit` page backwards.
    const history = await server.api<{ messages: WireMessage[] }>('GET', `/v1/matches/${matchId}/messages`, b.token);
    expect(history.body.messages.map((m) => m.text)).toEqual(['Hello there', 'Second', 'Hi!']);
    const page = await server.api<{ messages: WireMessage[] }>(
      'GET',
      `/v1/matches/${matchId}/messages?before=${encodeURIComponent(reply.body.sentAt)}&limit=1`,
      b.token,
    );
    expect(page.body.messages.map((m) => m.text)).toEqual(['Second']);

    // Unread counts are per person; reading clears only your own.
    const listB = await server.api<{ matches: WireMatch[] }>('GET', '/v1/matches', b.token);
    expect(listB.body.matches).toHaveLength(1);
    expect(listB.body.matches[0]).toMatchObject({ id: matchId, unreadCount: 2, partner: { id: a.id, firstName: 'Maya' } });
    expect(listB.body.matches[0]?.lastMessage?.text).toBe('Hi!');
    const listA = await server.api<{ matches: WireMatch[] }>('GET', '/v1/matches', a.token);
    expect(listA.body.matches[0]).toMatchObject({ unreadCount: 1, partner: { id: b.id } });

    expect((await server.api('POST', `/v1/matches/${matchId}/read`, b.token)).status).toBe(204);
    expect((await server.api<{ matches: WireMatch[] }>('GET', '/v1/matches', b.token)).body.matches[0]?.unreadCount).toBe(0);
    expect((await server.api<{ matches: WireMatch[] }>('GET', '/v1/matches', a.token)).body.matches[0]?.unreadCount).toBe(1);
  });

  it('sends a push (without the message text) when the recipient is offline and opted in', async () => {
    const { a, b, matchId } = await matched();
    await server.api('POST', '/v1/me/push-token', b.token, { apnsToken: 'ab'.repeat(32), tzOffsetMinutes: 0, enabled: true });
    await server.api('POST', `/v1/matches/${matchId}/messages`, a.token, { text: 'secret words', clientId: 'x' });
    await sleep(50);
    const sent = (server.ctx.push as unknown as { sent: Array<{ deviceToken: string; message: { body: string } }> }).sent;
    expect(sent).toHaveLength(1);
    expect(sent[0]?.deviceToken).toBe('ab'.repeat(32));
    expect(sent[0]?.message.body).toBe('Maya sent you a message');
  });

  it('validates message input', async () => {
    const { a, matchId } = await matched();
    const post = (body: unknown) => server.api<{ error: { code: string } }>('POST', `/v1/matches/${matchId}/messages`, a.token, body);
    expect((await post({ text: '   ', clientId: 'x' })).status).toBe(400);
    expect((await post({ text: 'x'.repeat(2001), clientId: 'x' })).status).toBe(400);
    expect((await post({ clientId: 'x' })).body.error.code).toBe('invalid_request');
    expect((await server.api('GET', `/v1/matches/${matchId}/messages?limit=0`, a.token)).status).toBe(400);
    expect((await server.api('GET', `/v1/matches/${matchId}/messages?before=yesterday`, a.token)).status).toBe(400);
  });

  it('rate limits message sending per user', async () => {
    const { a, b, matchId } = await matched();
    let limited = 0;
    for (let i = 0; i < 65; i++) {
      const res = await server.api('POST', `/v1/matches/${matchId}/messages`, a.token, { text: `m${i}`, clientId: `r-${i}` });
      if (res.status === 429) limited += 1;
    }
    expect(limited).toBe(5);
    // The other person's budget is separate.
    expect((await server.api('POST', `/v1/matches/${matchId}/messages`, b.token, { text: 'ok', clientId: 'z' })).status).toBe(200);
  });
});

describe('authorization: a user can only touch their own matches', () => {
  it("treats someone else's match as not found on every match endpoint", async () => {
    const { a, matchId } = await matched();
    const stranger = await server.signUp();
    const cs = await connect(stranger);
    const routes: Array<[string, string, unknown?]> = [
      ['GET', `/v1/matches/${matchId}/messages`],
      ['POST', `/v1/matches/${matchId}/messages`, { text: 'hi', clientId: '1' }],
      ['POST', `/v1/matches/${matchId}/read`],
      ['DELETE', `/v1/matches/${matchId}`],
    ];
    for (const [method, route, body] of routes) {
      const res = await server.api<{ error: { code: string } }>(method, route, stranger.token, body);
      expect([method, res.status, res.body.error.code]).toEqual([method, 404, 'not_found']);
    }
    expect((await server.api<{ matches: unknown[] }>('GET', '/v1/matches', stranger.token)).body.matches).toEqual([]);
    expect((await server.api('GET', '/v1/matches/not-a-uuid/messages', a.token)).status).toBe(400);
    // The match survived the stranger's delete attempt.
    expect((await server.api<{ matches: unknown[] }>('GET', '/v1/matches', a.token)).body.matches).toHaveLength(1);

    // Nor can a stranger ring it or signal into it.
    cs.send({ type: 'call.invite', matchId });
    expect(await cs.next('error')).toMatchObject({ code: 'match_not_found' });
    cs.send({ type: 'rtc.signal', dateId: `call:${matchId}`, payload: { kind: 'offer', sdp: 'x' } });
    expect(await cs.next('error')).toMatchObject({ code: 'call_not_found' });
  });

  it('requires a valid session on every protected route', async () => {
    const id = '11111111-1111-4111-8111-111111111111';
    const routes: Array<[string, string]> = [
      ['GET', '/v1/me'],
      ['PUT', '/v1/me'],
      ['PUT', '/v1/me/preferences'],
      ['POST', '/v1/me/photos'],
      ['POST', '/v1/me/push-token'],
      ['DELETE', '/v1/me'],
      ['GET', '/v1/usage'],
      ['GET', '/v1/online-count'],
      ['GET', '/v1/matches'],
      ['DELETE', `/v1/matches/${id}`],
      ['GET', `/v1/matches/${id}/messages`],
      ['POST', `/v1/matches/${id}/messages`],
      ['POST', `/v1/matches/${id}/read`],
      ['POST', '/v1/reports'],
      ['POST', '/v1/blocks'],
      ['POST', '/v1/moderation/frame'],
      ['POST', '/v1/moderation/transcript'],
      ['POST', '/v1/iap/verify'],
    ];
    const forged =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTQxMTEtODExMS0xMTExMTExMTExMTEiLCJpc3MiOiJ0ZW1wbyJ9.c2lnbmF0dXJl';
    for (const [method, route] of routes) {
      for (const token of [null, 'garbage', forged]) {
        const body = method === 'GET' || method === 'DELETE' ? undefined : {};
        const res = await server.api<{ error: { code: string; message: string } }>(method, route, token, body);
        expect([method, route, res.status]).toEqual([method, route, 401]);
        expect(res.body.error.code).toBe('unauthorized');
        expect(typeof res.body.error.message).toBe('string');
      }
    }
    // Body-less requests that still declare a JSON content type are accepted.
    const user = await server.signUp();
    const bare = await fetch(`${server.url}/v1/usage`, {
      method: 'GET',
      headers: { authorization: `Bearer ${user.token}`, 'content-type': 'application/json' },
    });
    expect(bare.status).toBe(200);
    const malformed = await fetch(`${server.url}/v1/blocks`, {
      method: 'POST',
      headers: { authorization: `Bearer ${user.token}`, 'content-type': 'application/json' },
      body: '{not json',
    });
    expect(malformed.status).toBe(400);
    expect(((await malformed.json()) as { error: { code: string } }).error.code).toBe('invalid_request');
    // Public routes stay public.
    expect((await server.api('GET', '/health')).body).toEqual({ ok: true });
    expect((await server.api('GET', '/v1/config')).status).toBe(200);
    expect((await server.api<{ error: { code: string } }>('GET', '/v1/nope')).body.error.code).toBe('not_found');
  });

  it('a token for a deleted account stops working', async () => {
    const a = await server.signUp();
    expect((await server.api('DELETE', '/v1/me', a.token)).status).toBe(204);
    expect((await server.api('GET', '/v1/me', a.token)).status).toBe(401);
    await expect(TestClient.connect(server, a.token).then((c) => c.next('queue.status', 300))).rejects.toThrow();
  });
});

describe('unmatch', () => {
  it('removes the match and its messages and tells both people', async () => {
    const { a, b, matchId } = await matched();
    const ca = await connect(a);
    const cb = await connect(b);
    await server.api('POST', `/v1/matches/${matchId}/messages`, a.token, { text: 'hi', clientId: '1' });
    expect((await server.api('DELETE', `/v1/matches/${matchId}`, a.token)).status).toBe(204);
    expect(await cb.next('match.removed')).toEqual({ type: 'match.removed', matchId });
    expect(await ca.next('match.removed')).toEqual({ type: 'match.removed', matchId });
    expect((await server.api<{ matches: unknown[] }>('GET', '/v1/matches', b.token)).body.matches).toEqual([]);
    expect((await server.api('GET', `/v1/matches/${matchId}/messages`, b.token)).status).toBe(404);
    expect((await server.api('DELETE', `/v1/matches/${matchId}`, b.token)).status).toBe(404);
  });
});

describe('blocks', () => {
  it('blocked pairs are never paired again, in either direction, even when both are queued', async () => {
    const [a, b] = await compatiblePair(server);
    // They can be paired before the block (cooldown is disabled in this suite).
    const first = await pairUp(server, a, b);
    clients.push(first.ca, first.cb);
    first.ca.send({ type: 'date.leave', dateId: first.dateId });
    await first.cb.next('date.ended');

    expect((await server.api('POST', '/v1/blocks', a.token, { userId: b.id })).status).toBe(204);
    expect((await server.api('POST', '/v1/blocks', a.token, { userId: b.id })).status).toBe(204); // idempotent

    first.ca.send({ type: 'queue.join' });
    first.cb.send({ type: 'queue.join' });
    expect(await first.ca.next('queue.status')).toMatchObject({ compatibleOnline: 0 });
    expect(await first.cb.next('queue.status')).toMatchObject({ compatibleOnline: 0 });
    await sleep(500); // several pairing ticks
    expect(first.ca.count('date.matched')).toBe(1);
    expect(first.cb.count('date.matched')).toBe(1);

    // The blocked person is still pairable with someone else.
    const other = await server.signUp({ gender: 'woman', interestedIn: ['man'] });
    const co = await connect(other);
    co.send({ type: 'queue.join' });
    expect((await co.next('date.matched')).partner).toMatchObject({ id: b.id });
    expect(await server.ctx.store.listAudit({ userId: a.id, type: 'block' })).toHaveLength(2);
  });

  it('a block made while both are already waiting takes effect immediately', async () => {
    const a = await server.signUp({ gender: 'woman', interestedIn: ['man'] });
    const b = await server.signUp({ gender: 'man', interestedIn: ['woman'], lat: null, lng: null });
    // Make them momentarily incompatible so both sit in the queue, then block, then lift the filter.
    await server.api('PUT', '/v1/me/preferences', a.token, { ageMin: 60, ageMax: 70, maxDistanceKm: 100, notifyOnlineSingles: false });
    const ca = await connect(a);
    const cb = await connect(b);
    ca.send({ type: 'queue.join' });
    cb.send({ type: 'queue.join' });
    await ca.next('queue.status');
    await cb.next('queue.status');
    await server.api('POST', '/v1/blocks', b.token, { userId: a.id });
    await server.api('PUT', '/v1/me/preferences', a.token, { ageMin: 18, ageMax: 70, maxDistanceKm: 100, notifyOnlineSingles: false });
    await sleep(500);
    expect(ca.count('date.matched') + cb.count('date.matched')).toBe(0);
    expect(server.ctx.matchmaker.isQueued(a.id)).toBe(true); // still waiting, just not for each other
  });

  it('blocking removes an existing match and ends a date in progress', async () => {
    const { a, b, matchId } = await matched();
    const ca = await connect(a);
    const cb = await connect(b);
    await server.api('POST', '/v1/blocks', b.token, { userId: a.id });
    expect(await ca.next('match.removed')).toEqual({ type: 'match.removed', matchId });
    expect(await cb.next('match.removed')).toEqual({ type: 'match.removed', matchId });
    expect((await server.api<{ matches: unknown[] }>('GET', '/v1/matches', a.token)).body.matches).toEqual([]);

    const [c, d] = await compatiblePair(server);
    const live = await pairUp(server, c, d);
    clients.push(live.ca, live.cb);
    await server.api('POST', '/v1/blocks', c.token, { userId: d.id });
    expect(await live.ca.next('date.ended')).toMatchObject({ reason: 'you_left' });
    expect(await live.cb.next('date.ended')).toMatchObject({ reason: 'partner_left' });
  });

  it('validates the target', async () => {
    const a = await server.signUp();
    expect((await server.api('POST', '/v1/blocks', a.token, { userId: a.id })).status).toBe(400);
    expect((await server.api('POST', '/v1/blocks', a.token, { userId: 'x' })).status).toBe(400);
    expect((await server.api('POST', '/v1/blocks', a.token, { userId: '11111111-1111-4111-8111-111111111111' })).status).toBe(404);
  });
});

describe('24 hour re-pair cooldown', () => {
  it('does not pair the same two people twice within the cooldown', async () => {
    await server.close();
    server = await startServer({ repairCooldownHours: 24 });
    const [a, b] = await compatiblePair(server);
    const first = await pairUp(server, a, b);
    clients.push(first.ca, first.cb);
    first.ca.send({ type: 'date.leave', dateId: first.dateId });
    await first.cb.next('date.ended');
    first.ca.send({ type: 'queue.join' });
    first.cb.send({ type: 'queue.join' });
    await first.ca.next('queue.status');
    await sleep(500);
    expect(first.ca.count('date.matched')).toBe(1);
  });
});

describe('reports', () => {
  it('records the report and an audit entry; only shared dates and matches can be cited', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = await pairUp(server, a, b);
    clients.push(ca, cb);
    const ok = await server.api('POST', '/v1/reports', a.token, { userId: b.id, dateId, reason: 'harassment', details: 'Rude.' });
    expect(ok.status).toBe(204);
    const audit = await server.ctx.store.listAudit({ userId: b.id, type: 'report' });
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({ category: 'harassment', dateId, targetUserId: a.id });

    const outsider = await server.signUp();
    const res = await server.api<{ error: { code: string } }>('POST', '/v1/reports', outsider.token, { userId: b.id, dateId, reason: 'spam' });
    expect(res.status).toBe(403);
    const match = await server.ctx.store.createMatch({ userA: a.id, userB: b.id, dateId: null, matchedAt: new Date() });
    expect((await server.api('POST', '/v1/reports', outsider.token, { userId: b.id, matchId: match.id, reason: 'spam' })).status).toBe(403);
    expect((await server.api('POST', '/v1/reports', a.token, { userId: b.id, matchId: match.id, reason: 'fake_profile' })).status).toBe(204);

    expect((await server.api('POST', '/v1/reports', a.token, { userId: b.id, reason: 'rudeness' })).status).toBe(400);
    expect((await server.api('POST', '/v1/reports', a.token, { userId: a.id, reason: 'spam' })).status).toBe(400);
    expect((await server.api('POST', '/v1/reports', a.token, { userId: b.id, reason: 'other', details: 'x'.repeat(1001) })).status).toBe(400);
    for (const reason of ['nudity', 'sexual_language', 'harassment', 'underage', 'fake_profile', 'spam', 'other']) {
      expect((await server.api('POST', '/v1/reports', b.token, { userId: a.id, reason })).status).toBe(204);
    }
    // Rate limited: 10 per hour per reporter (b has used 7).
    let limited = 0;
    for (let i = 0; i < 5; i++) {
      if ((await server.api('POST', '/v1/reports', b.token, { userId: a.id, reason: 'spam' })).status === 429) limited++;
    }
    expect(limited).toBe(2);
  });
});

describe('post-match calls', () => {
  it('relays invite, accept, signalling and end only between the two matched people', async () => {
    const { a, b, matchId } = await matched();
    const ca = await connect(a);
    const cb = await connect(b);
    const target = `call:${matchId}`;

    ca.send({ type: 'call.invite', matchId });
    expect(await cb.next('call.invite')).toEqual({ type: 'call.invite', matchId, fromUserId: a.id });
    // Only the invitee can accept.
    ca.send({ type: 'call.accept', matchId });
    expect(await ca.next('error')).toMatchObject({ code: 'call_not_found' });
    cb.send({ type: 'call.accept', matchId });
    expect(await ca.next('call.accept')).toEqual({ type: 'call.accept', matchId, fromUserId: b.id });

    const offer = { kind: 'offer', sdp: 'call-sdp' };
    ca.send({ type: 'rtc.signal', dateId: target, payload: offer });
    expect(await cb.next('rtc.signal')).toEqual({ type: 'rtc.signal', dateId: target, payload: offer });
    cb.send({ type: 'rtc.signal', dateId: target, payload: { kind: 'answer', sdp: 'call-answer' } });
    expect(await ca.next('rtc.signal')).toMatchObject({ dateId: target, payload: { kind: 'answer' } });

    // While on a call neither can enter the queue.
    ca.send({ type: 'queue.join' });
    expect(await ca.next('error', 2000, (m) => m.code === 'in_call')).toBeTruthy();

    // Moderation applies to calls too.
    const warn = await server.api<{ action: string }>('POST', '/v1/moderation/transcript', a.token, { dateId: target, text: 'send nudes' });
    expect(warn.body.action).toBe('warn');
    expect(await ca.next('moderation.action')).toMatchObject({ dateId: target, action: 'warn' });

    cb.send({ type: 'call.end', matchId });
    expect(await ca.next('call.end')).toEqual({ type: 'call.end', matchId, fromUserId: b.id });
    // After the call is over, signalling is refused.
    ca.send({ type: 'rtc.signal', dateId: target, payload: offer });
    expect(await ca.next('error', 2000, (m) => m.code === 'call_not_found')).toBeTruthy();
    expect(cb.count('rtc.signal')).toBe(1);
  });

  it('handles decline, an offline partner, and a caller who disconnects', async () => {
    const { a, b, matchId } = await matched();
    const ca = await connect(a);
    ca.send({ type: 'call.invite', matchId });
    expect(await ca.next('error')).toMatchObject({ code: 'partner_offline' });

    const cb = await connect(b);
    ca.send({ type: 'call.invite', matchId });
    await cb.next('call.invite');
    cb.send({ type: 'call.decline', matchId });
    expect(await ca.next('call.decline')).toEqual({ type: 'call.decline', matchId, fromUserId: b.id });

    ca.send({ type: 'call.invite', matchId });
    await cb.next('call.invite');
    await ca.close();
    expect(await cb.next('call.end')).toEqual({ type: 'call.end', matchId, fromUserId: a.id });
  });

  it('nudity on a call ends the call for both and strikes the offender', async () => {
    const { a, b, matchId } = await matched();
    const ca = await connect(a);
    const cb = await connect(b);
    ca.send({ type: 'call.invite', matchId });
    await cb.next('call.invite');
    cb.send({ type: 'call.accept', matchId });
    await ca.next('call.accept');
    const res = await server.api<{ action: string }>('POST', '/v1/moderation/frame', b.token, {
      dateId: `call:${matchId}`,
      imageBase64: fakeJpegBase64(true),
    });
    expect(res.body.action).toBe('end');
    expect(await ca.next('call.end')).toMatchObject({ matchId, fromUserId: b.id });
    expect(await cb.next('call.end')).toMatchObject({ matchId });
    expect(await cb.next('moderation.action')).toMatchObject({ action: 'end', category: 'nudity' });
    expect((await server.ctx.store.getUser(b.id))?.strikes).toBe(1);
  });
});

describe('account deletion', () => {
  it('hard-deletes the user, their photos, matches and messages, and frees their partner', async () => {
    const { a, b, matchId } = await matched();
    const cb = await connect(b);
    const ca = await connect(a);
    await server.api('POST', `/v1/matches/${matchId}/messages`, a.token, { text: 'from a', clientId: '1' });
    await server.api('POST', `/v1/matches/${matchId}/messages`, b.token, { text: 'from b', clientId: '1' });
    await server.api('POST', '/v1/blocks', a.token, { userId: (await server.signUp()).id });
    const photo = await server.api<{ url: string }>('POST', '/v1/me/photos', a.token, { imageBase64: fakeJpegBase64() });
    expect(photo.status).toBe(200);
    expect((await fetch(photo.body.url)).status).toBe(200);
    const uploadDir = server.ctx.config.uploadDir;
    expect(readdirSync(uploadDir)).toHaveLength(1);
    const reportedAboutA = await server.api('POST', '/v1/reports', b.token, { userId: a.id, matchId, reason: 'spam' });
    expect(reportedAboutA.status).toBe(204);

    expect((await server.api('DELETE', '/v1/me', a.token)).status).toBe(204);

    // Live effects: partner is told, the deleted user's socket is closed.
    expect(await cb.next('match.removed')).toEqual({ type: 'match.removed', matchId });
    await sleep(100);
    expect(ca.closed?.code).toBe(4002);

    // Durable effects.
    const { store } = server.ctx;
    expect(await store.getUser(a.id)).toBeNull();
    expect(await store.getMatch(matchId)).toBeNull();
    expect(await store.listMessages(matchId, null, 100)).toEqual([]);
    expect(await store.listMatchSummaries(b.id)).toEqual([]);
    expect(await store.listExclusions(b.id, new Date(0))).toEqual([]);
    expect(existsSync(uploadDir) ? readdirSync(uploadDir) : []).toEqual([]);
    expect((await fetch(photo.body.url)).status).toBe(404);
    expect((await server.api('GET', '/v1/me', a.token)).status).toBe(401);
    // The safety trail about the deleted account survives.
    expect((await store.listAudit({ userId: a.id, type: 'report' })).length).toBe(1);
    expect((await store.listAudit({ userId: a.id, type: 'account.deleted' })).length).toBe(1);

    // Signing in again with the same identity is a brand-new, empty account.
    expect((await server.api('GET', '/v1/matches', b.token)).status).toBe(200);
  });

  it('deleting mid-date ends the date for the partner', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = await pairUp(server, a, b);
    clients.push(ca, cb);
    await server.api('DELETE', '/v1/me', a.token);
    expect(await cb.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'partner_left' });
    await server.ctx.dates.flush();
    // The partner's date history (and so their daily count) is kept; the deleted side is nulled.
    const date = await server.ctx.store.getDate(dateId);
    expect([date?.userA, date?.userB].sort()).toEqual([b.id, null].sort());
  });

  it('strikes survive delete-and-recreate of the same identity', async () => {
    const auth = await server.api<{ token: string; user: { id: string } }>('POST', '/v1/auth/dev', null, { deviceId: 'repeat-offender' });
    await server.ctx.store.updateUser(auth.body.user.id, { strikes: 2 });
    await server.api('DELETE', '/v1/me', auth.body.token);
    const again = await server.api<{ user: { id: string; strikes: number } }>('POST', '/v1/auth/dev', null, { deviceId: 'repeat-offender' });
    expect(again.body.user.id).not.toBe(auth.body.user.id);
    expect(again.body.user.strikes).toBe(2);
  });
});
