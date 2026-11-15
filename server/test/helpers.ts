import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import type { AddressInfo } from 'node:net';
import WebSocket from 'ws';
import { buildApp, type BuildOptions, type BuiltApp } from '../src/app.js';
import { loadConfig, type AppConfig } from '../src/config.js';
import type { AppContext } from '../src/context.js';
import { MockModerationProvider } from '../src/moderation/ModerationProvider.js';

export const TEST_SECRET = 'test-secret-test-secret-test-secret-0123456789';

/** Real config loader with tiny durations so a whole date takes about a second. */
export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  const base = loadConfig({
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    PORT: '0',
    HOST: '127.0.0.1',
    JWT_SECRET: TEST_SECRET,
    // Tests use a fixed identifier of their own, independent of the shipping bundle id.
    APPLE_BUNDLE_ID: 'com.tempo.app',
    ALLOW_DEV_AUTH: '1',
    ALLOW_DEV_IAP: '1',
    UPLOAD_DIR: mkdtempSync(path.join(tmpdir(), 'tempo-uploads-')),
    DATE_DURATION_SEC: '1.2',
    TURN_DURATION_SEC: '0.25',
    DECISION_WINDOW_SEC: '0.6',
    // Off by default so existing flows run straight through; the checkpoint tests turn it on.
    CHECKPOINT_WINDOW_SEC: '0',
    READY_TIMEOUT_SEC: '0.4',
    RECONNECT_GRACE_SEC: '0.3',
    DECISION_GRACE_MS: '40',
    QUEUE_STATUS_INTERVAL_SEC: '0.15',
    REPAIR_COOLDOWN_HOURS: '24',
  });
  return { ...base, ...overrides };
}

export interface TestServer extends BuiltApp {
  url: string;
  wsUrl: string;
  ctx: AppContext;
  close(): Promise<void>;
  api<T = unknown>(method: string, route: string, token?: string | null, body?: unknown): Promise<ApiResult<T>>;
  signUp(profile?: Partial<TestProfile>): Promise<TestUser>;
}

export interface ApiResult<T> {
  status: number;
  body: T;
}

export interface TestProfile {
  firstName: string;
  birthdate: string;
  gender: 'woman' | 'man' | 'nonbinary';
  interestedIn: Array<'woman' | 'man' | 'nonbinary'>;
  city: string;
  lat: number | null;
  lng: number | null;
}

export interface TestUser {
  id: string;
  token: string;
  profile: TestProfile;
}

let deviceCounter = 0;

export async function startServer(
  configOverrides: Partial<AppConfig> = {},
  options: Partial<BuildOptions> = {},
): Promise<TestServer> {
  const built = await buildApp({ config: testConfig(configOverrides), ...options });
  await built.app.listen({ host: '127.0.0.1', port: 0 });
  const { port } = built.app.server.address() as AddressInfo;
  const url = `http://127.0.0.1:${port}`;

  const api = async <T>(method: string, route: string, token?: string | null, body?: unknown): Promise<ApiResult<T>> => {
    const headers: Record<string, string> = {};
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers['content-type'] = 'application/json';
    const res = await fetch(`${url}${route}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    return { status: res.status, body: (text.length > 0 ? JSON.parse(text) : null) as T };
  };

  const signUp = async (profile: Partial<TestProfile> = {}): Promise<TestUser> => {
    const deviceId = `device-${++deviceCounter}-${Math.random().toString(36).slice(2)}`;
    const auth = await api<{ token: string; user: { id: string } }>('POST', '/v1/auth/dev', null, { deviceId });
    if (auth.status !== 200) throw new Error(`dev auth failed: ${JSON.stringify(auth.body)}`);
    const full: TestProfile = {
      firstName: `User${deviceCounter}`,
      birthdate: '1995-06-15',
      gender: 'woman',
      interestedIn: ['man'],
      city: 'New York',
      lat: 40.75,
      lng: -73.99,
      ...profile,
    };
    const put = await api('PUT', '/v1/me', auth.body.token, { ...full, onboardingComplete: true });
    if (put.status !== 200) throw new Error(`profile failed: ${JSON.stringify(put.body)}`);
    return { id: auth.body.user.id, token: auth.body.token, profile: full };
  };

  return {
    ...built,
    url,
    wsUrl: `ws://127.0.0.1:${port}/v1/ws`,
    api,
    signUp,
    close: () => built.app.close(),
  };
}

export type Msg = { type: string } & Record<string, unknown>;

/** A WebSocket client that records every frame and lets tests await the next one of a type. */
export class TestClient {
  readonly received: Msg[] = [];
  private readonly cursors = new Map<string, number>();
  private waiters: Array<() => void> = [];
  closed: { code: number; reason: string } | null = null;

  private constructor(readonly socket: WebSocket) {
    socket.on('message', (data) => {
      this.received.push(JSON.parse(String(data)) as Msg);
      this.wake();
    });
    socket.on('close', (code, reason) => {
      this.closed = { code, reason: reason.toString() };
      this.wake();
    });
  }

  private wake(): void {
    const waiters = this.waiters;
    this.waiters = [];
    for (const w of waiters) w();
  }

  static connect(server: TestServer, token: string): Promise<TestClient> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(`${server.wsUrl}?token=${encodeURIComponent(token)}`);
      const client = new TestClient(socket);
      socket.once('open', () => resolve(client));
      socket.once('error', reject);
      socket.once('unexpected-response', (_req, res) => reject(new Error(`HTTP ${res.statusCode}`)));
    });
  }

  send(message: Msg): void {
    this.socket.send(JSON.stringify(message));
  }

  /** Next not-yet-consumed message of `type` (optionally matching `where`), waiting up to `timeoutMs`. */
  async next<T extends Msg = Msg>(type: string, timeoutMs = 4000, where?: (m: Msg) => boolean): Promise<T> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const start = this.cursors.get(type) ?? 0;
      for (let i = start; i < this.received.length; i++) {
        const m = this.received[i] as Msg;
        if (m.type === type && (!where || where(m))) {
          this.cursors.set(type, i + 1);
          return m as T;
        }
      }
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        throw new Error(
          `timed out waiting for "${type}"; received: ${this.received.map((m) => m.type).join(', ') || '(nothing)'}`,
        );
      }
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, remaining);
        this.waiters.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
  }

  /** Asserts that no message of `type` arrives within `ms`. */
  async expectNone(type: string, ms = 300): Promise<void> {
    const start = this.cursors.get(type) ?? 0;
    await sleep(ms);
    const hit = this.received.slice(start).find((m) => m.type === type);
    if (hit) throw new Error(`unexpected "${type}": ${JSON.stringify(hit)}`);
  }

  count(type: string): number {
    return this.received.filter((m) => m.type === type).length;
  }

  async close(): Promise<void> {
    if (this.socket.readyState === WebSocket.CLOSED) return;
    await new Promise<void>((resolve) => {
      this.socket.once('close', () => resolve());
      this.socket.close();
    });
  }
}

export const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** A woman and a man who each want the other, both near midtown Manhattan. */
export async function compatiblePair(server: TestServer): Promise<[TestUser, TestUser]> {
  const a = await server.signUp({ firstName: 'Maya', gender: 'woman', interestedIn: ['man'] });
  const b = await server.signUp({ firstName: 'Leo', gender: 'man', interestedIn: ['woman'], lat: 40.76, lng: -73.98 });
  return [a, b];
}

/** Connects both, queues both, and returns once each has `date.matched`. */
export async function pairUp(
  server: TestServer,
  a: TestUser,
  b: TestUser,
): Promise<{ ca: TestClient; cb: TestClient; dateId: string; matchedA: Msg; matchedB: Msg }> {
  const ca = await TestClient.connect(server, a.token);
  const cb = await TestClient.connect(server, b.token);
  ca.send({ type: 'queue.join' });
  await ca.next('queue.status');
  cb.send({ type: 'queue.join' });
  const matchedA = await ca.next('date.matched');
  const matchedB = await cb.next('date.matched');
  return { ca, cb, dateId: String(matchedA.dateId), matchedA, matchedB };
}

/** Minimal valid JPEG header followed by filler; append the mock marker to make it "nudity". */
export function fakeJpegBase64(nudity = false): string {
  const header = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00]);
  const tail = nudity ? Buffer.from(MockModerationProvider.NUDITY_MARKER) : Buffer.from('clean-frame');
  return Buffer.concat([header, tail, Buffer.from([0xff, 0xd9])]).toString('base64');
}
