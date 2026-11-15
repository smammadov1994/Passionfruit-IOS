import { generateKeyPairSync, type KeyObject } from 'node:crypto';
import { exportJWK, SignJWT } from 'jose';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { AppleAuthError, AppleIdentityVerifier, APPLE_ISSUER } from '../src/auth/apple.js';
import { SessionTokens } from '../src/auth/session.js';
import { ConfigError, loadConfig } from '../src/config.js';
import { startServer, TEST_SECRET, type TestServer } from './helpers.js';

const BUNDLE = 'com.tempo.app';

interface Signer {
  kid: string;
  privateKey: KeyObject;
  jwk: Record<string, unknown>;
}

async function makeSigner(kid: string): Promise<Signer> {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...(await exportJWK(publicKey)), kid, alg: 'RS256', use: 'sig' };
  return { kid, privateKey, jwk };
}

function identityToken(
  signer: Signer,
  claims: { sub?: string; iss?: string; aud?: string; exp?: number | string; alg?: string } = {},
): Promise<string> {
  const jwt = new SignJWT({ email: 'someone@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: signer.kid })
    .setIssuer(claims.iss ?? APPLE_ISSUER)
    .setAudience(claims.aud ?? BUNDLE)
    .setIssuedAt()
    .setExpirationTime(claims.exp ?? '10m');
  if (claims.sub !== '') jwt.setSubject(claims.sub ?? '001234.abcdef.5678');
  return jwt.sign(signer.privateKey);
}

let keyA: Signer;
let keyB: Signer;
let rogue: Signer;

beforeAll(async () => {
  [keyA, keyB, rogue] = await Promise.all([makeSigner('KEY-A'), makeSigner('KEY-B'), makeSigner('KEY-A')]);
});

describe('Sign in with Apple identity token verification', () => {
  function verifier(keys: Signer[], clock = { now: () => Date.now() }) {
    const state = { fetches: 0, keys };
    const v = new AppleIdentityVerifier(
      BUNDLE,
      async () => {
        state.fetches += 1;
        return { keys: state.keys.map((k) => k.jwk) };
      },
      clock,
    );
    return { v, state };
  }

  it('accepts a correctly signed token and returns the subject', async () => {
    const { v } = verifier([keyA, keyB]);
    expect(await v.verify(await identityToken(keyB, { sub: 'apple-user-1' }))).toEqual({ sub: 'apple-user-1' });
  });

  it.each([
    ['wrong issuer', { iss: 'https://evil.example' }],
    ['wrong audience (another app)', { aud: 'com.other.app' }],
    ['expired', { exp: Math.floor(Date.now() / 1000) - 60 }],
    ['missing subject', { sub: '' }],
  ])('rejects: %s', async (_name, claims) => {
    const { v } = verifier([keyA]);
    await expect(v.verify(await identityToken(keyA, claims))).rejects.toBeInstanceOf(AppleAuthError);
  });

  it('rejects a token signed by a different key with the same kid, a tampered token, and junk', async () => {
    const { v } = verifier([keyA]);
    await expect(v.verify(await identityToken(rogue))).rejects.toBeInstanceOf(AppleAuthError);
    const good = await identityToken(keyA);
    const [h, p, s] = good.split('.') as [string, string, string];
    const payload = JSON.parse(Buffer.from(p, 'base64url').toString()) as Record<string, unknown>;
    const forged = `${h}.${Buffer.from(JSON.stringify({ ...payload, sub: 'someone-else' })).toString('base64url')}.${s}`;
    await expect(v.verify(forged)).rejects.toBeInstanceOf(AppleAuthError);
    await expect(v.verify('not.a.jwt')).rejects.toBeInstanceOf(AppleAuthError);
    await expect(v.verify('')).rejects.toBeInstanceOf(AppleAuthError);
  });

  it('rejects alg=none and HS256 tokens (algorithm confusion)', async () => {
    const { v } = verifier([keyA]);
    const body = Buffer.from(
      JSON.stringify({ iss: APPLE_ISSUER, aud: BUNDLE, sub: 'x', exp: Math.floor(Date.now() / 1000) + 600 }),
    ).toString('base64url');
    const none = `${Buffer.from(JSON.stringify({ alg: 'none', kid: 'KEY-A' })).toString('base64url')}.${body}.`;
    await expect(v.verify(none)).rejects.toBeInstanceOf(AppleAuthError);
    const hs = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256', kid: 'KEY-A' })
      .setIssuer(APPLE_ISSUER)
      .setAudience(BUNDLE)
      .setSubject('x')
      .setExpirationTime('10m')
      .sign(new TextEncoder().encode(JSON.stringify(keyA.jwk)));
    await expect(v.verify(hs)).rejects.toBeInstanceOf(AppleAuthError);
  });

  it('caches the JWKS, refetches on an unknown kid (rate limited) and after the TTL', async () => {
    let now = 1_800_000_000_000;
    const clock = { now: () => now };
    const { v, state } = verifier([keyA], clock);
    const token = (signer: Signer) => identityToken(signer, { exp: Math.floor(now / 1000) + 86_400 * 2 });

    await v.verify(await token(keyA));
    await v.verify(await token(keyA));
    expect(state.fetches).toBe(1);

    // Apple rotates in a new key: unknown kid, but we fetched moments ago, so no refetch yet.
    state.keys = [keyA, keyB];
    now += 10_000;
    await expect(v.verify(await token(keyB))).rejects.toBeInstanceOf(AppleAuthError);
    expect(state.fetches).toBe(1);
    // A minute later the unknown kid triggers exactly one refetch and then verifies.
    now += 61_000;
    expect(await v.verify(await token(keyB))).toEqual({ sub: '001234.abcdef.5678' });
    expect(state.fetches).toBe(2);

    // After the hour-long TTL the next verification refreshes.
    now += 61 * 60_000;
    await v.verify(await token(keyA));
    expect(state.fetches).toBe(3);
  });

  it('keeps working from the cache when Apple is briefly unreachable, but fails closed with no cache', async () => {
    let now = 1_800_000_000_000;
    let down = false;
    const v = new AppleIdentityVerifier(
      BUNDLE,
      async () => {
        if (down) throw new Error('network down');
        return { keys: [keyA.jwk] };
      },
      { now: () => now },
    );
    const token = await identityToken(keyA, { exp: Math.floor(now / 1000) + 86_400 });
    await v.verify(token);
    down = true;
    now += 2 * 60 * 60_000;
    expect(await v.verify(token)).toBeTruthy();

    const cold = new AppleIdentityVerifier(BUNDLE, async () => Promise.reject(new Error('down')), { now: () => now });
    await expect(cold.verify(token)).rejects.toBeInstanceOf(AppleAuthError);
  });
});

describe('session tokens', () => {
  it('round-trips a user id and rejects forged, foreign and expired tokens', async () => {
    const sessions = new SessionTokens(TEST_SECRET, 30);
    const token = await sessions.issue('user-1');
    expect(await sessions.verify(token)).toBe('user-1');
    expect(await new SessionTokens('another-secret-another-secret-another!', 30).verify(token)).toBeNull();
    expect(await sessions.verify(`${token.slice(0, -2)}xx`)).toBeNull();
    expect(await sessions.verify('')).toBeNull();
    const expired = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject('user-1')
      .setIssuer('tempo')
      .setExpirationTime(Math.floor(Date.now() / 1000) - 10)
      .sign(new TextEncoder().encode(TEST_SECRET));
    expect(await sessions.verify(expired)).toBeNull();
  });
});

describe('auth endpoints', () => {
  let server: TestServer;
  afterEach(async () => {
    await server.close();
  });

  it('POST /v1/auth/apple creates the account once and signs the same person in afterwards', async () => {
    server = await startServer({}, { appleJwksFetcher: async () => ({ keys: [keyA.jwk] }) });
    const first = await server.api<{ token: string; user: Record<string, unknown> }>('POST', '/v1/auth/apple', null, {
      identityToken: await identityToken(keyA, { sub: 'apple-sub-1' }),
      firstName: 'Maya',
    });
    expect(first.status).toBe(200);
    expect(first.body.user).toMatchObject({
      firstName: 'Maya',
      birthdate: '',
      interestedIn: [],
      photoUrls: [],
      isPremium: false,
      onboardingComplete: false,
      strikes: 0,
      preferences: { ageMin: 18, ageMax: 99, maxDistanceKm: 100, notifyOnlineSingles: false },
    });
    expect(first.body.user).not.toHaveProperty('gender');
    expect(first.body.user).not.toHaveProperty('appleSub');
    expect(first.body.user).not.toHaveProperty('apnsToken');
    expect((await server.api<{ id: string }>('GET', '/v1/me', first.body.token)).body.id).toBe(first.body.user.id);

    const second = await server.api<{ user: { id: string; firstName: string } }>('POST', '/v1/auth/apple', null, {
      identityToken: await identityToken(keyA, { sub: 'apple-sub-1' }),
      firstName: 'Ignored',
    });
    expect(second.body.user.id).toBe(first.body.user.id);
    expect(second.body.user.firstName).toBe('Maya');

    const bad = await server.api<{ error: { code: string } }>('POST', '/v1/auth/apple', null, {
      identityToken: await identityToken(keyA, { aud: 'com.other.app' }),
    });
    expect(bad.status).toBe(401);
    expect(bad.body.error.code).toBe('invalid_identity_token');
    expect((await server.api('POST', '/v1/auth/apple', null, {})).status).toBe(400);
  });

  it('dev auth is a 404 unless ALLOW_DEV_AUTH=1, and auth endpoints are rate limited per IP', async () => {
    server = await startServer({ allowDevAuth: false });
    expect((await server.api('POST', '/v1/auth/dev', null, { deviceId: 'x' })).status).toBe(404);
    await server.close();

    server = await startServer();
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) {
      statuses.push((await server.api('POST', '/v1/auth/dev', null, { deviceId: `d-${i}` })).status);
    }
    expect(statuses.filter((s) => s === 200)).toHaveLength(10);
    expect(statuses.filter((s) => s === 429)).toHaveLength(2);
  });
});

describe('environment validation', () => {
  const base = { JWT_SECRET: TEST_SECRET };
  it('applies spec defaults', () => {
    const c = loadConfig(base);
    expect(c).toMatchObject({
      dateDurationSec: 120,
      turnDurationSec: 30,
      decisionWindowSec: 20,
      freeDailyDates: 5,
      frameSampleIntervalSec: 3,
      readyTimeoutSec: 8,
      reconnectGraceSec: 6,
      queueStatusIntervalSec: 5,
      repairCooldownHours: 24,
      wsIdleTimeoutSec: 45,
      strikesToSuspend: 3,
      allowDevAuth: false,
      allowDevIap: false,
      corsOrigin: undefined,
    });
    expect(c.push).toMatchObject({ minIntervalHours: 4, minCompatible: 3 });
  });

  it.each([
    ['a missing or short JWT secret', { JWT_SECRET: 'short' }],
    ['dev auth in production', { ...base, NODE_ENV: 'production', ALLOW_DEV_AUTH: '1', APPLE_ROOT_CA_PATH: '/x' }],
    ['dev IAP in production', { ...base, NODE_ENV: 'production', ALLOW_DEV_IAP: '1', APPLE_ROOT_CA_PATH: '/x' }],
    ['production without the Apple root certificate', { ...base, NODE_ENV: 'production' }],
    ['http moderation without a key', { ...base, MODERATION_PROVIDER: 'http', MODERATION_API_URL: 'https://x' }],
    ['apns without a key file', { ...base, PUSH_PROVIDER: 'apns' }],
    ['s3 without a bucket', { ...base, BLOB_STORE: 's3' }],
    ['a nonsense port', { ...base, PORT: 'eighty' }],
  ])('refuses to start with %s', (_name, env) => {
    expect(() => loadConfig(env)).toThrow(ConfigError);
  });
});
