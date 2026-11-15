import { createPublicKey, generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, writeFileSync } from 'node:fs';
import http2 from 'node:http2';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { jwtVerify } from 'jose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ApnsPushProvider } from '../src/push/apns.js';

/** A local HTTP/2 server standing in for api.push.apple.com. */
interface Seen {
  path: string;
  headers: http2.IncomingHttpHeaders;
  body: string;
}

describe('APNs HTTP/2 provider', () => {
  const seen: Seen[] = [];
  let server: http2.Http2Server;
  let provider: ApnsPushProvider;
  let publicPem: string;
  const GOOD = 'a1'.repeat(32);
  const GONE = 'b2'.repeat(32);
  const BAD = 'c3'.repeat(32);

  beforeAll(async () => {
    const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    publicPem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
    const keyPath = path.join(mkdtempSync(path.join(tmpdir(), 'tempo-apns-')), 'AuthKey_TEST.p8');
    writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));

    server = http2.createServer();
    server.on('stream', (stream, headers) => {
      let body = '';
      stream.setEncoding('utf8');
      stream.on('data', (c: string) => (body += c));
      stream.on('end', () => {
        const p = String(headers[':path']);
        seen.push({ path: p, headers, body });
        if (p.endsWith(GONE)) {
          stream.respond({ ':status': 410 });
          stream.end(JSON.stringify({ reason: 'Unregistered', timestamp: 1 }));
        } else if (p.endsWith(BAD)) {
          stream.respond({ ':status': 400 });
          stream.end(JSON.stringify({ reason: 'BadDeviceToken' }));
        } else {
          stream.respond({ ':status': 200 });
          stream.end();
        }
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address() as AddressInfo;
    provider = new ApnsPushProvider({
      keyPath,
      keyId: 'KEYID12345',
      teamId: 'TEAMID1234',
      bundleId: 'com.tempo.app',
      production: false,
      origin: `http://127.0.0.1:${port}`,
    });
  });

  afterAll(async () => {
    await provider.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it('posts an alert with token auth, the bundle topic and the payload', async () => {
    const result = await provider.send(GOOD, {
      title: 'Tempo',
      body: '4 compatible singles are online now',
      collapseId: 'online-singles',
      data: { kind: 'online_singles' },
    });
    expect(result).toEqual({ ok: true });
    const req = seen[0] as Seen;
    expect(req.path).toBe(`/3/device/${GOOD}`);
    expect(req.headers[':method']).toBe('POST');
    expect(req.headers['apns-topic']).toBe('com.tempo.app');
    expect(req.headers['apns-push-type']).toBe('alert');
    expect(req.headers['apns-collapse-id']).toBe('online-singles');
    expect(JSON.parse(req.body)).toEqual({
      aps: { alert: { title: 'Tempo', body: '4 compatible singles are online now' }, sound: 'default' },
      kind: 'online_singles',
    });

    // The provider token is an ES256 JWT signed by the .p8 key with the key id and team id.
    const auth = String(req.headers.authorization);
    expect(auth.startsWith('bearer ')).toBe(true);
    const { payload, protectedHeader } = await jwtVerify(auth.slice(7), createPublicKey(publicPem), { algorithms: ['ES256'] });
    expect(protectedHeader.kid).toBe('KEYID12345');
    expect(payload.iss).toBe('TEAMID1234');
    expect(typeof payload.iat).toBe('number');
  });

  it('reuses the provider token and the connection across sends', async () => {
    await provider.send(GOOD, { body: 'again' });
    expect(seen[1]?.headers.authorization).toBe(seen[0]?.headers.authorization);
    expect(JSON.parse((seen[1] as Seen).body)).toEqual({ aps: { alert: { body: 'again' }, sound: 'default' } });
  });

  it('reports dead device tokens as unregistered and other failures as plain errors', async () => {
    expect(await provider.send(GONE, { body: 'x' })).toEqual({ ok: false, unregistered: true, reason: 'Unregistered' });
    expect(await provider.send(BAD, { body: 'x' })).toEqual({ ok: false, unregistered: true, reason: 'BadDeviceToken' });
    const before = seen.length;
    expect(await provider.send('not-a-token', { body: 'x' })).toMatchObject({ ok: false, unregistered: true });
    expect(seen.length).toBe(before); // never sent
  });

  it('returns an error instead of throwing when APNs is unreachable', async () => {
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const keyPath = path.join(mkdtempSync(path.join(tmpdir(), 'tempo-apns-')), 'k.p8');
    writeFileSync(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }));
    const errors: string[] = [];
    const dead = new ApnsPushProvider({
      keyPath,
      keyId: 'K',
      teamId: 'T',
      bundleId: 'com.tempo.app',
      production: false,
      origin: 'http://127.0.0.1:1',
      onError: (e) => errors.push(e.message),
    });
    const result = await dead.send(GOOD, { body: 'x' });
    expect(result.ok).toBe(false);
    await dead.close();
  });
});
