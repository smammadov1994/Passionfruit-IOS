import { execFileSync } from 'node:child_process';
import { createPrivateKey, X509Certificate, type KeyObject } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { CompactSign } from 'jose';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { AppStoreVerifier, IapError, loadRootCertificate } from '../src/iap/appstore.js';
import { startServer, type TestServer } from './helpers.js';

/**
 * Builds a throwaway three-certificate chain shaped like Apple's (root -> WWDR intermediate ->
 * leaf, with Apple's marker extension OIDs) so the real chain-validation code runs end to end.
 */
interface Chain {
  dir: string;
  rootPath: string;
  root: X509Certificate;
  x5c: string[];
  leafKey: KeyObject;
}

const openssl = (cwd: string, args: string[]): void => {
  execFileSync('openssl', args, { cwd, stdio: 'pipe' });
};
const der64 = (file: string): string => new X509Certificate(readFileSync(file)).raw.toString('base64');

function makeChain(options: { leafOid?: boolean; intermediateOid?: boolean; leafDays?: number } = {}): Chain {
  const dir = mkdtempSync(path.join(tmpdir(), 'tempo-iap-'));
  const key = (name: string) => openssl(dir, ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${name}.key`]);
  key('root');
  openssl(dir, ['req', '-x509', '-new', '-key', 'root.key', '-sha256', '-days', '3650', '-subj', '/CN=Test Root CA G3',
    '-addext', 'basicConstraints=critical,CA:TRUE', '-out', 'root.pem']);
  key('int');
  openssl(dir, ['req', '-new', '-key', 'int.key', '-subj', '/CN=Test WWDR Intermediate', '-out', 'int.csr']);
  writeFileSync(path.join(dir, 'int.ext'),
    `basicConstraints=critical,CA:TRUE\n${options.intermediateOid === false ? '' : '1.2.840.113635.100.6.2.1=DER:0500\n'}`);
  openssl(dir, ['x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '3650',
    '-sha256', '-extfile', 'int.ext', '-out', 'int.pem']);
  key('leaf');
  openssl(dir, ['req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test Prod ECC Mac App Store and iTunes Store Receipt Signing', '-out', 'leaf.csr']);
  writeFileSync(path.join(dir, 'leaf.ext'),
    `basicConstraints=CA:FALSE\n${options.leafOid === false ? '' : '1.2.840.113635.100.6.11.1=DER:0500\n'}`);
  openssl(dir, ['x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key', '-CAcreateserial',
    '-days', String(options.leafDays ?? 365), '-sha256', '-extfile', 'leaf.ext', '-out', 'leaf.pem']);
  const rootPath = path.join(dir, 'root.pem');
  return {
    dir,
    rootPath,
    root: new X509Certificate(readFileSync(rootPath)),
    x5c: ['leaf.pem', 'int.pem', 'root.pem'].map((f) => der64(path.join(dir, f))),
    leafKey: createPrivateKey(readFileSync(path.join(dir, 'leaf.key'))),
  };
}

function sign(chain: Chain, payload: Record<string, unknown>, x5c: string[] = chain.x5c): Promise<string> {
  return new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: 'ES256', x5c })
    .sign(chain.leafKey);
}

const BUNDLE = 'com.tempo.app';
const HOUR = 3_600_000;
function transaction(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    bundleId: BUNDLE,
    productId: 'tempo.premium.monthly',
    transactionId: '2000000000000001',
    originalTransactionId: '2000000000000001',
    purchaseDate: Date.now() - HOUR,
    expiresDate: Date.now() + 30 * 24 * HOUR,
    environment: 'Sandbox',
    type: 'Auto-Renewable Subscription',
    ...over,
  };
}

let apple: Chain;
let attacker: Chain;
beforeAll(() => {
  apple = makeChain();
  attacker = makeChain();
});

describe('App Store JWS verification (x5c chain to a pinned root)', () => {
  const verifier = (chain: Chain = apple, clock = { now: () => Date.now() }) =>
    new AppStoreVerifier({ rootCert: chain.root, allowUnsigned: false, clock });

  it('accepts a transaction signed by a chain that ends at the pinned root', async () => {
    const tx = await verifier().verifyTransaction(await sign(apple, transaction()));
    expect(tx).toMatchObject({ bundleId: BUNDLE, productId: 'tempo.premium.monthly', originalTransactionId: '2000000000000001' });
  });

  it('accepts a chain that omits the root (leaf + intermediate only)', async () => {
    await expect(verifier().verifyTransaction(await sign(apple, transaction(), apple.x5c.slice(0, 2)))).resolves.toBeTruthy();
  });

  it('rejects a perfectly valid chain that ends at a different root', async () => {
    await expect(verifier().verifyTransaction(await sign(attacker, transaction()))).rejects.toMatchObject({
      code: 'invalid_signature',
    });
  });

  it('rejects an attacker leaf presented with the genuine intermediate and root', async () => {
    const spliced = [attacker.x5c[0] as string, apple.x5c[1] as string, apple.x5c[2] as string];
    await expect(verifier().verifyTransaction(await sign(attacker, transaction(), spliced))).rejects.toBeInstanceOf(IapError);
  });

  it('rejects a payload altered after signing, and a signature made with another key', async () => {
    const jws = await sign(apple, transaction());
    const [h, , s] = jws.split('.') as [string, string, string];
    const altered = `${h}.${Buffer.from(JSON.stringify(transaction({ expiresDate: Date.now() + 999 * 24 * HOUR }))).toString('base64url')}.${s}`;
    await expect(verifier().verifyTransaction(altered)).rejects.toMatchObject({ code: 'invalid_signature' });
    // Signed by the attacker's key but claiming the genuine certificate chain.
    await expect(verifier().verifyTransaction(await sign(attacker, transaction(), apple.x5c))).rejects.toMatchObject({
      code: 'invalid_signature',
    });
  });

  it('rejects certificates without the App Store marker extensions', async () => {
    const noLeafOid = makeChain({ leafOid: false });
    await expect(verifier(noLeafOid).verifyTransaction(await sign(noLeafOid, transaction()))).rejects.toMatchObject({
      code: 'invalid_signature',
    });
    const noIntOid = makeChain({ intermediateOid: false });
    await expect(verifier(noIntOid).verifyTransaction(await sign(noIntOid, transaction()))).rejects.toBeInstanceOf(IapError);
  });

  it('rejects a chain with an expired certificate', async () => {
    const later = { now: () => Date.now() + 400 * 24 * HOUR }; // leaf is valid for 365 days
    await expect(verifier(apple, later).verifyTransaction(await sign(apple, transaction()))).rejects.toMatchObject({
      code: 'invalid_signature',
    });
  });

  it('rejects unsigned data unless dev mode is on, and refuses signed data when no root is configured', async () => {
    const unsigned = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify(transaction())).toString('base64url')}.`;
    await expect(verifier().verifyTransaction(unsigned)).rejects.toMatchObject({ code: 'invalid_signature' });
    await expect(verifier().verifyTransaction(JSON.stringify(transaction()))).rejects.toBeInstanceOf(IapError);
    const dev = new AppStoreVerifier({ rootCert: null, allowUnsigned: true, clock: { now: () => Date.now() } });
    await expect(dev.verifyTransaction(unsigned)).resolves.toMatchObject({ bundleId: BUNDLE });
    await expect(dev.verifyTransaction(JSON.stringify(transaction()))).resolves.toMatchObject({ bundleId: BUNDLE });
    // Dev mode never weakens verification of data that does carry a chain.
    await expect(dev.verifyTransaction(await sign(apple, transaction()))).rejects.toMatchObject({ code: 'iap_not_configured' });
  });

  it('pins the root file by SHA-256 fingerprint when one is configured', () => {
    const fingerprint = apple.root.fingerprint256.replace(/:/g, '').toLowerCase();
    expect(loadRootCertificate(apple.rootPath, fingerprint).fingerprint256).toBe(apple.root.fingerprint256);
    expect(() => loadRootCertificate(attacker.rootPath, fingerprint)).toThrow(/expected/);
    expect(() => loadRootCertificate(path.join(apple.dir, 'leaf.pem'))).toThrow(/not a CA/);
  });
});

describe('POST /v1/iap/verify and /v1/iap/notifications', () => {
  let server: TestServer;
  afterEach(async () => {
    await server.close();
  });
  const start = (allowDevIap = false) =>
    startServer(
      { allowDevIap },
      { appStoreVerifier: new AppStoreVerifier({ rootCert: apple.root, allowUnsigned: allowDevIap, clock: { now: () => Date.now() } }) },
    );
  type Premium = { isPremium: boolean; premiumExpiresAt: string | null };
  type Err = { error: { code: string } };
  const notify = async (type: string, tx: Record<string, unknown>, extra: Record<string, unknown> = {}) =>
    server.api<{ ok?: boolean } & Partial<Err>>('POST', '/v1/iap/notifications', null, {
      signedPayload: await sign(apple, {
        notificationType: type,
        notificationUUID: crypto.randomUUID(),
        data: { bundleId: BUNDLE, environment: 'Sandbox', signedTransactionInfo: await sign(apple, tx) },
        ...extra,
      }),
    });

  it('grants premium from a verified transaction and reflects it everywhere', async () => {
    server = await start();
    const user = await server.signUp();
    const expires = Date.now() + 30 * 24 * HOUR;
    const res = await server.api<Premium>('POST', '/v1/iap/verify', user.token, {
      jwsTransaction: await sign(apple, transaction({ expiresDate: expires })),
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ isPremium: true, premiumExpiresAt: new Date(expires).toISOString() });
    const me = await server.api<Premium>('GET', '/v1/me', user.token);
    expect(me.body).toMatchObject({ isPremium: true, premiumExpiresAt: new Date(expires).toISOString() });
    expect((await server.api<{ limit: number | null }>('GET', '/v1/usage', user.token)).body.limit).toBeNull();
    expect((await server.ctx.store.listAudit({ userId: user.id, type: 'iap' }))[0]).toMatchObject({ action: 'premium_on' });
  });

  it.each([
    ['another app', { bundleId: 'com.other.app' }, 'wrong_bundle'],
    ['another product', { productId: 'tempo.premium.yearly' }, 'wrong_product'],
  ])('refuses a genuine transaction for %s', async (_name, over, code) => {
    server = await start();
    const user = await server.signUp();
    const res = await server.api<Err>('POST', '/v1/iap/verify', user.token, { jwsTransaction: await sign(apple, transaction(over)) });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe(code);
    expect((await server.api<Premium>('GET', '/v1/me', user.token)).body.isPremium).toBe(false);
  });

  it('an expired or revoked transaction verifies but does not grant premium; forgeries are rejected', async () => {
    server = await start();
    const user = await server.signUp();
    const expired = await server.api<Premium>('POST', '/v1/iap/verify', user.token, {
      jwsTransaction: await sign(apple, transaction({ expiresDate: Date.now() - HOUR })),
    });
    expect(expired.body.isPremium).toBe(false);
    const revoked = await server.api<Premium>('POST', '/v1/iap/verify', user.token, {
      jwsTransaction: await sign(apple, transaction({ revocationDate: Date.now() - HOUR })),
    });
    expect(revoked.body.isPremium).toBe(false);
    const forged = await server.api<Err>('POST', '/v1/iap/verify', user.token, { jwsTransaction: await sign(attacker, transaction()) });
    expect(forged.status).toBe(400);
    expect(forged.body.error.code).toBe('invalid_signature');
    const unsigned = await server.api<Err>('POST', '/v1/iap/verify', user.token, { jwsTransaction: JSON.stringify(transaction()) });
    expect(unsigned.status).toBe(400);
    expect((await server.api<Premium>('GET', '/v1/me', user.token)).body.isPremium).toBe(false);
  });

  it('accepts an unsigned test payload only with ALLOW_DEV_IAP=1', async () => {
    server = await start(true);
    const user = await server.signUp();
    const res = await server.api<Premium>('POST', '/v1/iap/verify', user.token, { jwsTransaction: JSON.stringify(transaction()) });
    expect(res.body.isPremium).toBe(true);
  });

  it('a subscription restored on a second account moves instead of duplicating', async () => {
    server = await start();
    const first = await server.signUp();
    const second = await server.signUp();
    const jws = await sign(apple, transaction());
    await server.api('POST', '/v1/iap/verify', first.token, { jwsTransaction: jws });
    await server.api('POST', '/v1/iap/verify', second.token, { jwsTransaction: jws });
    expect((await server.api<Premium>('GET', '/v1/me', first.token)).body.isPremium).toBe(false);
    expect((await server.api<Premium>('GET', '/v1/me', second.token)).body.isPremium).toBe(true);
  });

  it('server notifications renew, expire and refund the right account', async () => {
    server = await start();
    const user = await server.signUp();
    const bystander = await server.signUp();
    const soon = Date.now() + HOUR;
    await server.api('POST', '/v1/iap/verify', user.token, { jwsTransaction: await sign(apple, transaction({ expiresDate: soon })) });
    const premium = async () => (await server.api<Premium>('GET', '/v1/me', user.token)).body;

    // Renewal: a new transaction id under the same original transaction extends the expiry.
    const renewed = Date.now() + 31 * 24 * HOUR;
    const renew = await notify('DID_RENEW', transaction({ transactionId: '2000000000000002', expiresDate: renewed }));
    expect(renew.status).toBe(200);
    expect(renew.body).toEqual({ ok: true });
    expect(await premium()).toMatchObject({ isPremium: true, premiumExpiresAt: new Date(renewed).toISOString() });

    // A failed renewal alone changes nothing.
    await notify('DID_FAIL_TO_RENEW', transaction({ expiresDate: renewed }));
    expect((await premium()).isPremium).toBe(true);

    await notify('EXPIRED', transaction({ expiresDate: Date.now() - 1000 }), { subtype: 'VOLUNTARY' });
    expect((await premium()).isPremium).toBe(false);

    await notify('SUBSCRIBED', transaction({ expiresDate: renewed }), { subtype: 'RESUBSCRIBE' });
    expect((await premium()).isPremium).toBe(true);

    await notify('REFUND', transaction({ expiresDate: renewed, revocationDate: Date.now() }));
    expect((await premium()).isPremium).toBe(false);
    expect((await server.api<Premium>('GET', '/v1/me', bystander.token)).body.isPremium).toBe(false);
    const actions = (await server.ctx.store.listAudit({ userId: user.id, type: 'iap' })).map((e) => e.action);
    expect(actions).toEqual(['premium_on', 'premium_on', 'premium_off', 'premium_on', 'premium_off']);
  });

  it('links a first-ever notification to the account through appAccountToken', async () => {
    server = await start();
    const user = await server.signUp();
    const res = await notify('SUBSCRIBED', transaction({ originalTransactionId: '300', appAccountToken: user.id.toUpperCase() }));
    expect(res.status).toBe(200);
    expect((await server.api<Premium>('GET', '/v1/me', user.token)).body.isPremium).toBe(true);
  });

  it('acknowledges notifications it has nothing to do for, and rejects unsigned or forged ones', async () => {
    server = await start();
    const unknown = await notify('DID_RENEW', transaction({ originalTransactionId: 'never-seen' }));
    expect(unknown.status).toBe(200);
    const test = await server.api('POST', '/v1/iap/notifications', null, {
      signedPayload: await sign(apple, { notificationType: 'TEST', data: { bundleId: BUNDLE } }),
    });
    expect(test.status).toBe(200);

    const forged = await server.api<Err>('POST', '/v1/iap/notifications', null, {
      signedPayload: await sign(attacker, { notificationType: 'REFUND', data: { signedTransactionInfo: await sign(attacker, transaction()) } }),
    });
    expect(forged.status).toBe(400);
    // Outer envelope genuine, inner transaction forged.
    const mixed = await server.api<Err>('POST', '/v1/iap/notifications', null, {
      signedPayload: await sign(apple, { notificationType: 'SUBSCRIBED', data: { signedTransactionInfo: await sign(attacker, transaction()) } }),
    });
    expect(mixed.status).toBe(400);
    const plain = await server.api<Err>('POST', '/v1/iap/notifications', null, {
      signedPayload: JSON.stringify({ notificationType: 'SUBSCRIBED' }),
    });
    expect(plain.status).toBe(400);
    expect((await server.api('POST', '/v1/iap/notifications', null, {})).status).toBe(400);
  });
});
