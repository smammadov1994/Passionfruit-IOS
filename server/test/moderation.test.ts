import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { ExplicitTextClassifier, normalizeToTokens } from '../src/moderation/textClassifier.js';
import {
  HttpModerationProvider,
  type FrameVerdict,
  type ModerationProvider,
  type TextVerdictResult,
} from '../src/moderation/ModerationProvider.js';
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

describe('built-in sexual language classifier', () => {
  const classifier = ExplicitTextClassifier.fromFile();
  const flagged = (text: string): boolean => classifier.classify(text).explicit;

  it('normalises case, accents, leetspeak, spacing and stretching', () => {
    expect(normalizeToTokens('Héllo, WORLD!')).toEqual(['hello', 'world']);
    expect(normalizeToTokens('h0rny b00bs')).toEqual(['horny', 'boobs']);
    expect(normalizeToTokens('n u d e s please')).toEqual(['nudes', 'please']);
    expect(normalizeToTokens("let's go")).toEqual(['lets', 'go']);
    expect(normalizeToTokens('room 101 at 9')).toEqual(['room', '101', 'at', '9']);
  });

  it.each([
    'send nudes',
    'Send me some NUDES',
    'show me your tits',
    'I want to fuck you',
    'wanna f u c k',
    "you're making me so h0rny",
    'are you hoooorny',
    'take off your shirt for me',
    'take your top off',
    'do you like blowjobs',
    'give me a blow job',
    'I am going to jerk off',
    'let me see you naked',
    'suck my d1ck',
    'get naked',
    'what is your bra size',
    'talk dirty to me',
    'want to have sex with me?',
    'c.u.m for me',
  ])('flags: %s', (text) => {
    expect(flagged(text)).toBe(true);
  });

  it.each([
    'What is the best meal you have had this year?',
    'I grew up in Scunthorpe and studied in Essex',
    'We had cocktails at the Dickens pub with my friend Dick',
    'I was so tired I could not come to the party',
    'That exam was hard, I got really wet in the rain',
    'My cat is called Pussy Willow',
    'I work in analytics and assess class sizes',
    'I love a big breakfast, especially sausages',
    'That was fucking hilarious',
    'Honestly work has been shit this week',
    'I blow glass as a hobby, it blows me away',
    'Can you send me pics of your dog?',
    'I had to take off my shoes at the airport',
    'She came down on the idea pretty hard',
    'I like to ride my bike to the beach',
    'Do you want kids? I am looking for something long term',
    'The head of my department gave me great advice',
    'I get up at 6, hit the gym, then get dressed',
    '',
  ])('does not flag: %s', (text) => {
    expect(flagged(text)).toBe(false);
  });

  it('reports references into the list, never the words', () => {
    const verdict = classifier.classify('send nudes you slut');
    expect(verdict.matchCount).toBeGreaterThanOrEqual(2);
    for (const ref of verdict.matches) expect(ref).toMatch(/^(term|phrase):\d+$/);
  });
});

describe('HTTP provider adapter', () => {
  it('sends the frame with the API key and maps the vendor score', async () => {
    const calls: Array<{ url: string; auth: string | null; image: string }> = [];
    const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      const body = JSON.parse(String(init?.body)) as { image: string };
      calls.push({ url: String(input), auth: headers.get('authorization'), image: body.image });
      return new Response(JSON.stringify({ nudity: 0.97 }), { status: 200 });
    }) as typeof fetch;
    const provider = new HttpModerationProvider(
      { apiUrl: 'https://moderation.example/v1/check', apiKey: 'k-123', timeoutMs: 1000, fetchImpl },
      ExplicitTextClassifier.fromFile(),
    );
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 1, 2, 3]);
    expect(await provider.classifyFrame(jpeg)).toEqual({ nudityScore: 0.97 });
    expect(calls).toEqual([
      { url: 'https://moderation.example/v1/check', auth: 'Bearer k-123', image: jpeg.toString('base64') },
    ]);
    expect((await provider.classifyText('send nudes')).sexualLanguage).toBe(true);
  });

  it('surfaces vendor failures as errors', async () => {
    const fetchImpl = (async () => new Response('nope', { status: 503 })) as typeof fetch;
    const provider = new HttpModerationProvider(
      { apiUrl: 'https://moderation.example', apiKey: 'k', timeoutMs: 1000, fetchImpl },
      ExplicitTextClassifier.fromFile(),
    );
    await expect(provider.classifyFrame(Buffer.from([0xff, 0xd8, 0xff]))).rejects.toThrow('HTTP 503');
  });
});

describe('enforcement ladder', () => {
  let server: TestServer;
  const clients: TestClient[] = [];
  beforeEach(async () => {
    // Long dates so nothing ends on the timer mid-test; no cooldown so the same two can be re-paired.
    server = await startServer({ dateDurationSec: 30, turnDurationSec: 10, repairCooldownHours: 0 });
  });
  afterEach(async () => {
    await Promise.all(clients.splice(0).map((c) => c.close()));
    await server.close();
  });

  async function liveDate(a: TestUser, b: TestUser): Promise<{ ca: TestClient; cb: TestClient; dateId: string }> {
    const paired = await pairUp(server, a, b);
    clients.push(paired.ca, paired.cb);
    paired.ca.send({ type: 'date.ready', dateId: paired.dateId });
    paired.cb.send({ type: 'date.ready', dateId: paired.dateId });
    await paired.ca.next('date.started');
    await paired.cb.next('date.started');
    return paired;
  }
  const frame = (user: TestUser, dateId: string, nudity: boolean) =>
    server.api<{ action: string }>('POST', '/v1/moderation/frame', user.token, {
      dateId,
      imageBase64: fakeJpegBase64(nudity),
    });
  const transcript = (user: TestUser, dateId: string, text: string) =>
    server.api<{ action: string }>('POST', '/v1/moderation/transcript', user.token, { dateId, text });
  const me = (user: TestUser) =>
    server.api<{ strikes: number; suspendedUntil?: string }>('GET', '/v1/me', user.token);

  it('clean frames and clean speech do nothing', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, dateId } = await liveDate(a, b);
    expect((await frame(a, dateId, false)).body).toEqual({ action: 'none' });
    expect((await transcript(a, dateId, 'So what do you do for fun?')).body).toEqual({ action: 'none' });
    await ca.expectNone('moderation.action', 150);
    expect((await me(a)).body.strikes).toBe(0);
    expect(await server.ctx.store.listAudit({ userId: a.id })).toEqual([]);
  });

  it('nudity ends the date at once for both and gives the offender a strike', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = await liveDate(a, b);
    const res = await frame(a, dateId, true);
    expect(res.body).toEqual({ action: 'end' });

    expect(await ca.next('moderation.action')).toMatchObject({ dateId, action: 'end', category: 'nudity' });
    expect(await ca.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'moderation' });
    expect(await cb.next('date.ended')).toEqual({ type: 'date.ended', dateId, reason: 'moderation' });
    expect(cb.count('moderation.action')).toBe(0); // the partner is not told what the offender did
    await sleep(100);
    expect(ca.count('date.result') + cb.count('date.result')).toBe(0); // no decision screen

    expect((await me(a)).body.strikes).toBe(1);
    expect((await me(b)).body.strikes).toBe(0);

    const audit = await server.ctx.store.listAudit({ userId: a.id });
    expect(audit.map((e) => e.type)).toEqual(['moderation.frame', 'strike']);
    expect(audit[0]).toMatchObject({ category: 'nudity', action: 'end', dateId, targetUserId: b.id });
    // Verdicts only: no image data anywhere in the audit trail.
    expect(JSON.stringify(audit)).not.toContain(fakeJpegBase64(true).slice(0, 12));

    // A late sample for the ended date is a no-op, not a second strike.
    expect((await frame(a, dateId, true)).body).toEqual({ action: 'none' });
    expect((await me(a)).body.strikes).toBe(1);
  });

  it('sexual language: warning first, second offence in the same date ends it with a strike', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, cb, dateId } = await liveDate(a, b);

    expect((await transcript(a, dateId, 'come on, send nudes')).body).toEqual({ action: 'warn' });
    const warn = await ca.next('moderation.action');
    expect(warn).toMatchObject({ dateId, action: 'warn', category: 'sexual_language' });
    expect(String(warn.message).length).toBeGreaterThan(10);
    await sleep(100);
    expect(ca.count('date.ended') + cb.count('date.ended')).toBe(0);
    expect(cb.count('moderation.action')).toBe(0);
    expect((await me(a)).body.strikes).toBe(0); // a warning is not a strike

    // The partner's own first offence is a warning of their own, not an escalation of A's.
    expect((await transcript(b, dateId, 'show me your tits')).body).toEqual({ action: 'warn' });

    expect((await transcript(a, dateId, 'I want to fuck you')).body).toEqual({ action: 'end' });
    expect(await ca.next('moderation.action', 2000, (m) => m.action === 'end')).toMatchObject({
      category: 'sexual_language',
    });
    expect(await ca.next('date.ended')).toMatchObject({ reason: 'moderation' });
    expect(await cb.next('date.ended')).toMatchObject({ reason: 'moderation' });
    expect((await me(a)).body.strikes).toBe(1);
    expect((await me(b)).body.strikes).toBe(0);

    const audit = await server.ctx.store.listAudit({ userId: a.id });
    expect(audit.map((e) => `${e.type}:${e.action ?? ''}`)).toEqual([
      'moderation.transcript:warn',
      'moderation.transcript:end',
      'strike:',
    ]);
    // The transcript itself is never stored.
    expect(JSON.stringify(audit)).not.toMatch(/nudes|fuck/);
  });

  it('warnings do not carry over to the next date', async () => {
    const [a, b] = await compatiblePair(server);
    const first = await liveDate(a, b);
    expect((await transcript(a, first.dateId, 'send nudes')).body.action).toBe('warn');
    first.ca.send({ type: 'date.leave', dateId: first.dateId });
    await first.cb.next('date.ended');
    await Promise.all([first.ca.close(), first.cb.close()]);

    const second = await liveDate(a, b);
    expect((await transcript(a, second.dateId, 'send nudes')).body.action).toBe('warn');
    expect((await me(a)).body.strikes).toBe(0);
  });

  it('three strikes suspend the account pending review and push account.suspended', async () => {
    const [a, b] = await compatiblePair(server);
    let last: { ca: TestClient; cb: TestClient; dateId: string } | null = null;
    for (let strike = 1; strike <= 3; strike++) {
      last = await liveDate(a, b);
      expect((await frame(a, last.dateId, true)).body.action).toBe('end');
      await last.cb.next('date.ended');
      expect((await me(a)).body.strikes).toBe(strike);
      if (strike < 3) {
        expect(last.ca.count('account.suspended')).toBe(0);
        await Promise.all([last.ca.close(), last.cb.close()]);
      }
    }
    const { ca } = last!;
    const suspended = await ca.next('account.suspended');
    expect(suspended.type).toBe('account.suspended');
    expect(suspended.until).toBeUndefined(); // null = pending review
    expect(String(suspended.reason).length).toBeGreaterThan(5);

    const stored = await server.ctx.store.getUser(a.id);
    expect(stored).toMatchObject({ strikes: 3, suspended: true, suspendedUntil: null });
    expect((await me(a)).body.suspendedUntil).toBeUndefined();
    const types = (await server.ctx.store.listAudit({ userId: a.id })).map((e) => e.type);
    expect(types.filter((t) => t === 'strike')).toHaveLength(3);
    expect(types.filter((t) => t === 'suspension')).toHaveLength(1);

    // Suspended users cannot queue, and are told again on reconnect.
    ca.send({ type: 'queue.join' });
    expect(await ca.next('account.suspended')).toBeTruthy();
    expect(server.ctx.matchmaker.isQueued(a.id)).toBe(false);
    const again = await TestClient.connect(server, a.token);
    clients.push(again);
    expect(await again.next('account.suspended')).toBeTruthy();
    // ...and no longer count as "online" for anyone else.
    expect((await server.api<{ compatibleOnline: number }>('GET', '/v1/online-count', b.token)).body.compatibleOnline).toBe(0);
  });

  it('a timed suspension lifts itself once it has passed', async () => {
    const [a] = await compatiblePair(server);
    await server.ctx.store.updateUser(a.id, { suspended: true, suspendedUntil: new Date(Date.now() + 60_000) });
    const ca = await TestClient.connect(server, a.token);
    clients.push(ca);
    const msg = await ca.next('account.suspended');
    expect(Date.parse(String(msg.until))).toBeGreaterThan(Date.now());
    expect((await me(a)).body.suspendedUntil).toBeDefined();

    await server.ctx.store.updateUser(a.id, { suspendedUntil: new Date(Date.now() - 1000) });
    ca.send({ type: 'queue.join' });
    expect(await ca.next('queue.status')).toMatchObject({ position: 1 });
    expect((await server.ctx.store.getUser(a.id))?.suspended).toBe(false);
  });

  it('only a participant of a live date can submit samples for it', async () => {
    const [a, b] = await compatiblePair(server);
    const { ca, dateId } = await liveDate(a, b);
    const outsider = await server.signUp();
    expect((await frame(outsider, dateId, true)).body).toEqual({ action: 'none' });
    expect((await transcript(outsider, dateId, 'send nudes')).body).toEqual({ action: 'none' });
    await ca.expectNone('date.ended', 150);
    expect((await me(a)).body.strikes).toBe(0);
    expect((await me(outsider)).body.strikes).toBe(0);

    expect((await server.api('POST', '/v1/moderation/frame', null, { dateId, imageBase64: fakeJpegBase64() })).status).toBe(401);
    expect((await server.api('POST', '/v1/moderation/frame', a.token, { dateId, imageBase64: 'aGVsbG8=' })).status).toBe(400);
    expect((await server.api('POST', '/v1/moderation/frame', a.token, { dateId: 'nope', imageBase64: fakeJpegBase64() })).status).toBe(400);
    expect((await server.api('POST', '/v1/moderation/transcript', a.token, { dateId })).status).toBe(400);
  });

  it('fails open when the classifier is down', async () => {
    await server.close();
    const broken: ModerationProvider = {
      name: 'broken',
      classifyFrame: async (): Promise<FrameVerdict> => {
        throw new Error('vendor down');
      },
      classifyText: async (): Promise<TextVerdictResult> => {
        throw new Error('vendor down');
      },
    };
    server = await startServer({ dateDurationSec: 30 }, { moderationProvider: broken });
    const [a, b] = await compatiblePair(server);
    const { ca, dateId } = await liveDate(a, b);
    expect((await frame(a, dateId, true)).body).toEqual({ action: 'none' });
    expect((await transcript(a, dateId, 'send nudes')).body).toEqual({ action: 'none' });
    await ca.expectNone('date.ended', 150);
  });

  it('rejects a profile photo that fails screening and records it', async () => {
    const a = await server.signUp();
    const bad = await server.api<{ error: { code: string } }>('POST', '/v1/me/photos', a.token, {
      imageBase64: fakeJpegBase64(true),
    });
    expect(bad.status).toBe(422);
    expect(bad.body.error.code).toBe('photo_rejected');
    expect((await server.ctx.store.listAudit({ userId: a.id, type: 'moderation.photo' })).length).toBe(1);
  });
});
