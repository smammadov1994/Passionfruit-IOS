import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { fakeJpegBase64, startServer, type TestServer } from './helpers.js';

let server: TestServer;
beforeEach(async () => {
  server = await startServer();
});
afterEach(async () => {
  await server.close();
});

async function fresh(): Promise<string> {
  const auth = await server.api<{ token: string }>('POST', '/v1/auth/dev', null, { deviceId: `p-${Math.random()}` });
  return auth.body.token;
}
type Err = { error: { code: string; message: string } };

describe('GET /v1/config', () => {
  it('serves every tunable from the spec', async () => {
    const res = await server.api<Record<string, unknown>>('GET', '/v1/config');
    expect(res.body).toEqual({
      dateDurationSec: 1.2,
      turnDurationSec: 0.25,
      decisionWindowSec: 0.6,
      freeDailyDates: 5,
      frameSampleIntervalSec: 3,
      iceServers: [{ urls: ['stun:stun.l.google.com:19302'] }],
    });
  });

  it('issues short-lived TURN credentials only to signed-in users', async () => {
    await server.close();
    server = await startServer({ turnUrls: ['turn:turn.example.com:3478'], turnSecret: 'turn-secret' });
    type Ice = { urls: string[]; username?: string; credential?: string };
    const anon = await server.api<{ iceServers: Ice[] }>('GET', '/v1/config');
    expect(anon.body.iceServers).toHaveLength(1);
    const user = await server.signUp();
    const authed = await server.api<{ iceServers: Ice[] }>('GET', '/v1/config', user.token);
    const turn = authed.body.iceServers[1];
    expect(turn?.urls).toEqual(['turn:turn.example.com:3478']);
    expect(turn?.username).toMatch(new RegExp(`^\\d+:${user.id}$`));
    expect(Number(turn?.username?.split(':')[0])).toBeGreaterThan(Date.now() / 1000);
    expect(turn?.credential).toMatch(/^[A-Za-z0-9+/]+=*$/);
  });
});

describe('profile', () => {
  it('updates partial fields and returns the full user', async () => {
    const token = await fresh();
    const res = await server.api<Record<string, unknown>>('PUT', '/v1/me', token, {
      firstName: '  Maya ',
      birthdate: '1996-03-04',
      gender: 'woman',
      interestedIn: ['man', 'man', 'nonbinary'],
      bio: 'Hi',
      city: 'New York',
      lat: 40.7,
      lng: -74,
      intention: 'long_term',
      education: 'masters',
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      firstName: 'Maya',
      birthdate: '1996-03-04',
      gender: 'woman',
      interestedIn: ['man', 'nonbinary'],
      lat: 40.7,
      lng: -74,
      intention: 'long_term',
      education: 'masters',
      onboardingComplete: false,
    });
    // A later partial update leaves everything else alone; null clears an optional field.
    const second = await server.api<Record<string, unknown>>('PUT', '/v1/me', token, { bio: 'New bio', intention: null });
    expect(second.body).toMatchObject({ firstName: 'Maya', bio: 'New bio', education: 'masters' });
    expect(second.body).not.toHaveProperty('intention');
    const done = await server.api<Record<string, unknown>>('PUT', '/v1/me', token, { onboardingComplete: true });
    expect(done.body.onboardingComplete).toBe(true);
  });

  it('enforces 18+ at the birthdate gate and locks the birthdate after onboarding', async () => {
    const token = await fresh();
    const year = new Date().getUTCFullYear();
    const minor = await server.api<Err>('PUT', '/v1/me', token, { birthdate: `${year - 17}-01-01` });
    expect(minor.status).toBe(403);
    expect(minor.body.error.code).toBe('underage');
    expect((await server.api<{ birthdate: string }>('GET', '/v1/me', token)).body.birthdate).toBe('');

    const user = await server.signUp();
    const change = await server.api<Err>('PUT', '/v1/me', user.token, { birthdate: '1980-01-01' });
    expect(change.status).toBe(400);
    expect(change.body.error.code).toBe('birthdate_locked');
    expect((await server.api('PUT', '/v1/me', user.token, { birthdate: user.profile.birthdate })).status).toBe(200);
  });

  it('refuses to complete onboarding with required fields missing', async () => {
    const token = await fresh();
    const res = await server.api<Err>('PUT', '/v1/me', token, { firstName: 'Maya', onboardingComplete: true });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('profile_incomplete');
  });

  it.each([
    ['an impossible date', { birthdate: '1996-02-31' }],
    ['a malformed date', { birthdate: '04/03/1996' }],
    ['an unknown gender', { gender: 'robot' }],
    ['an empty interestedIn', { interestedIn: [] }],
    ['an unknown enum', { smoking: 'occasionally' }],
    ['an out-of-range latitude', { lat: 123, lng: 0 }],
    ['lat without lng', { lat: 10 }],
    ['an overlong bio', { bio: 'x'.repeat(501) }],
    ['a wrong type', { firstName: 42 }],
    ['a photo URL the user never uploaded', { photoUrls: ['https://evil.example/a.jpg'] }],
  ])('rejects %s', async (_name, body) => {
    const token = await fresh();
    const res = await server.api<Err>('PUT', '/v1/me', token, body);
    expect(res.status).toBe(400);
    expect(res.body.error.message.length).toBeGreaterThan(0);
  });

  it('cannot set server-owned fields through the profile', async () => {
    const user = await server.signUp();
    const res = await server.api<Record<string, unknown>>('PUT', '/v1/me', user.token, {
      isPremium: true,
      premiumExpiresAt: '2099-01-01T00:00:00.000Z',
      strikes: -5,
      id: 'someone-else',
      suspendedUntil: null,
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ id: user.id, isPremium: false, strikes: 0 });
  });
});

describe('preferences', () => {
  const basic = { ageMin: 25, ageMax: 40, maxDistanceKm: 30, notifyOnlineSingles: true };
  const advanced = {
    intentions: ['long_term', 'marriage'],
    children: ['wants'],
    religions: ['jewish'],
    minEducation: 'bachelors',
    smokingOk: ['never'],
    drinkingOk: ['never', 'socially'],
  };

  it('ignores advanced filters for free users and stores them for premium users', async () => {
    const user = await server.signUp();
    const free = await server.api<Record<string, unknown>>('PUT', '/v1/me/preferences', user.token, { ...basic, ...advanced });
    expect(free.status).toBe(200);
    expect(free.body).toEqual(basic);

    await server.ctx.store.updateUser(user.id, { isPremium: true, premiumExpiresAt: new Date(Date.now() + 60_000) });
    const premium = await server.api<Record<string, unknown>>('PUT', '/v1/me/preferences', user.token, { ...basic, ...advanced });
    expect(premium.body).toEqual({ ...basic, ...advanced });
    expect((await server.api<{ preferences: unknown }>('GET', '/v1/me', user.token)).body.preferences).toEqual({ ...basic, ...advanced });

    // PUT replaces: omitted advanced filters are cleared for a premium user.
    const cleared = await server.api<Record<string, unknown>>('PUT', '/v1/me/preferences', user.token, { ...basic, smokingOk: ['never'] });
    expect(cleared.body).toEqual({ ...basic, smokingOk: ['never'] });

    // After premium lapses, basic edits leave the stored advanced filters untouched (and unenforced).
    await server.ctx.store.updateUser(user.id, { premiumExpiresAt: new Date(Date.now() - 1000) });
    const lapsed = await server.api<Record<string, unknown>>('PUT', '/v1/me/preferences', user.token, { ...basic, ageMax: 45, ...advanced });
    expect(lapsed.body).toEqual({ ...basic, ageMax: 45, smokingOk: ['never'] });
  });

  it.each([
    ['ageMin under 18', { ...basic, ageMin: 16 }],
    ['ageMin above ageMax', { ...basic, ageMin: 41 }],
    ['a zero distance', { ...basic, maxDistanceKm: 0 }],
    ['a missing field', { ageMin: 20, ageMax: 30 }],
    ['an unknown filter value', { ...basic, intentions: ['casual'] }],
  ])('rejects %s', async (_name, body) => {
    const user = await server.signUp();
    expect((await server.api('PUT', '/v1/me/preferences', user.token, body)).status).toBe(400);
  });
});

describe('photos and push token', () => {
  it('stores a JPEG, serves it, and lets the profile reorder and remove photos', async () => {
    const user = await server.signUp();
    const one = await server.api<{ url: string }>('POST', '/v1/me/photos', user.token, { imageBase64: fakeJpegBase64() });
    const two = await server.api<{ url: string }>('POST', '/v1/me/photos', user.token, {
      imageBase64: `data:image/jpeg;base64,${fakeJpegBase64()}`,
    });
    expect(one.status).toBe(200);
    expect(one.body.url).toMatch(/^http:\/\/localhost:\d+\/uploads\/[0-9a-f-]{36}\.jpg$/);
    const served = await fetch(one.body.url);
    expect(served.headers.get('content-type')).toBe('image/jpeg');
    expect(Buffer.from(await served.arrayBuffer()).subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));
    expect((await server.api<{ photoUrls: string[] }>('GET', '/v1/me', user.token)).body.photoUrls).toEqual([one.body.url, two.body.url]);

    const reordered = await server.api<{ photoUrls: string[] }>('PUT', '/v1/me', user.token, { photoUrls: [two.body.url] });
    expect(reordered.body.photoUrls).toEqual([two.body.url]);
    expect((await fetch(one.body.url)).status).toBe(404); // removed photos are deleted from storage
    expect((await fetch(`${server.url}/uploads/..%2F..%2Fetc%2Fpasswd`)).status).toBe(404);
  });

  it('rejects non-JPEG data, oversized bodies and a seventh photo', async () => {
    const user = await server.signUp();
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]).toString('base64');
    expect((await server.api<Err>('POST', '/v1/me/photos', user.token, { imageBase64: png })).body.error.code).toBe('invalid_image');
    expect((await server.api('POST', '/v1/me/photos', user.token, { imageBase64: '%%%' })).status).toBe(400);
    const huge = await server.api<Err>('POST', '/v1/me/photos', user.token, { imageBase64: 'A'.repeat(9 * 1024 * 1024) });
    expect(huge.status).toBe(413);
    expect(huge.body.error.code).toBe('payload_too_large');
    // Ordinary endpoints have a much smaller body limit.
    expect((await server.api('PUT', '/v1/me', user.token, { bio: 'x'.repeat(300 * 1024) })).status).toBe(413);

    for (let i = 0; i < 6; i++) {
      expect((await server.api('POST', '/v1/me/photos', user.token, { imageBase64: fakeJpegBase64() })).status).toBe(200);
    }
    const seventh = await server.api<Err>('POST', '/v1/me/photos', user.token, { imageBase64: fakeJpegBase64() });
    expect(seventh.body.error.code).toBe('too_many_photos');
  });

  it('registers and clears the push token and stores the tz offset', async () => {
    const user = await server.signUp();
    const token = 'A1B2'.repeat(16);
    expect((await server.api('POST', '/v1/me/push-token', user.token, { apnsToken: token, tzOffsetMinutes: -300, enabled: true })).status).toBe(204);
    expect(await server.ctx.store.getUser(user.id)).toMatchObject({ apnsToken: token.toLowerCase(), pushEnabled: true, tzOffsetMinutes: -300 });
    await server.api('POST', '/v1/me/push-token', user.token, { apnsToken: token, tzOffsetMinutes: 60, enabled: false });
    expect(await server.ctx.store.getUser(user.id)).toMatchObject({ pushEnabled: false, tzOffsetMinutes: 60 });
    expect((await server.api('POST', '/v1/me/push-token', user.token, { apnsToken: 'not hex!', tzOffsetMinutes: 0, enabled: true })).status).toBe(400);
    expect((await server.api('POST', '/v1/me/push-token', user.token, { apnsToken: token, tzOffsetMinutes: 5000, enabled: true })).status).toBe(400);
  });
});
