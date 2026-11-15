import { createPrivateKey, type KeyObject } from 'node:crypto';
import { readFileSync } from 'node:fs';
import http2 from 'node:http2';
import { SignJWT } from 'jose';
import type { PushMessage, PushProvider, PushResult } from './PushProvider.js';

export interface ApnsOptions {
  /** Path to the AuthKey_XXXXXXXXXX.p8 file from the Apple Developer portal. */
  keyPath: string;
  keyId: string;
  teamId: string;
  /** apns-topic: the app bundle id. */
  bundleId: string;
  production: boolean;
  /** Overrides the APNs origin. Only for tests against a local HTTP/2 server. */
  origin?: string;
  onError?: (err: Error) => void;
}

const TOKEN_TTL_MS = 50 * 60 * 1000; // Apple accepts provider tokens for up to 60 minutes.
const REQUEST_TIMEOUT_MS = 10_000;

/** APNs over HTTP/2 with token-based (.p8) authentication. */
export class ApnsPushProvider implements PushProvider {
  private readonly key: KeyObject;
  private readonly origin: string;
  private session: http2.ClientHttp2Session | null = null;
  private token: { value: string; issuedAt: number } | null = null;

  constructor(private readonly options: ApnsOptions) {
    this.key = createPrivateKey(readFileSync(options.keyPath, 'utf8'));
    this.origin =
      options.origin ?? (options.production ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com');
  }

  private async providerToken(): Promise<string> {
    const now = Date.now();
    if (this.token && now - this.token.issuedAt < TOKEN_TTL_MS) return this.token.value;
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.options.keyId })
      .setIssuer(this.options.teamId)
      .setIssuedAt(Math.floor(now / 1000))
      .sign(this.key);
    this.token = { value, issuedAt: now };
    return value;
  }

  private connect(): http2.ClientHttp2Session {
    if (this.session && !this.session.closed && !this.session.destroyed) return this.session;
    const session = http2.connect(this.origin);
    const drop = (): void => {
      if (this.session === session) this.session = null;
    };
    session.on('error', (err) => {
      this.options.onError?.(err);
      drop();
    });
    session.on('goaway', drop);
    session.on('close', drop);
    // Do not keep the process alive just for an idle APNs connection.
    session.unref();
    this.session = session;
    return session;
  }

  async send(deviceToken: string, message: PushMessage): Promise<PushResult> {
    if (!/^[0-9a-fA-F]{32,200}$/.test(deviceToken)) return { ok: false, unregistered: true, reason: 'BadDeviceToken' };
    let jwt: string;
    try {
      jwt = await this.providerToken();
    } catch (err) {
      return { ok: false, reason: `token: ${String(err)}` };
    }
    const alert = message.title !== undefined ? { title: message.title, body: message.body } : { body: message.body };
    const payload = JSON.stringify({ aps: { alert, sound: 'default' }, ...(message.data ?? {}) });

    return new Promise<PushResult>((resolve) => {
      let settled = false;
      const done = (result: PushResult): void => {
        if (!settled) {
          settled = true;
          resolve(result);
        }
      };
      let req: http2.ClientHttp2Stream;
      try {
        req = this.connect().request({
          ':method': 'POST',
          ':path': `/3/device/${deviceToken}`,
          authorization: `bearer ${jwt}`,
          'apns-topic': this.options.bundleId,
          'apns-push-type': 'alert',
          'apns-priority': '5',
          ...(message.collapseId !== undefined ? { 'apns-collapse-id': message.collapseId } : {}),
          'content-type': 'application/json',
        });
      } catch (err) {
        done({ ok: false, reason: String(err) });
        return;
      }
      let status = 0;
      let body = '';
      req.setEncoding('utf8');
      req.setTimeout(REQUEST_TIMEOUT_MS, () => {
        req.close(http2.constants.NGHTTP2_CANCEL);
        done({ ok: false, reason: 'timeout' });
      });
      req.on('response', (headers) => {
        status = Number(headers[':status'] ?? 0);
      });
      req.on('data', (chunk: string) => {
        body += chunk;
      });
      req.on('error', (err) => done({ ok: false, reason: err.message }));
      req.on('end', () => {
        if (status === 200) {
          done({ ok: true });
          return;
        }
        let reason = `HTTP ${status}`;
        try {
          const parsed: unknown = JSON.parse(body);
          if (typeof parsed === 'object' && parsed !== null && 'reason' in parsed) {
            reason = String((parsed as { reason: unknown }).reason);
          }
        } catch {
          // keep the HTTP status as the reason
        }
        if (reason === 'ExpiredProviderToken' || reason === 'InvalidProviderToken') this.token = null;
        const unregistered = status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered';
        done({ ok: false, unregistered, reason });
      });
      req.end(payload);
    });
  }

  async close(): Promise<void> {
    const session = this.session;
    this.session = null;
    if (session && !session.closed) {
      await new Promise<void>((resolve) => session.close(() => resolve()));
    }
  }
}
