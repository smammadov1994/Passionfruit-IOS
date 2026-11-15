import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import Fastify, { type FastifyError, type FastifyInstance, type FastifyRequest } from 'fastify';
import { z } from 'zod';
import { AppleIdentityVerifier, defaultJwksFetcher, type JwksFetcher } from './auth/apple.js';
import { SessionTokens } from './auth/session.js';
import { LocalBlobStore, S3BlobStore, type BlobStore } from './blob/BlobStore.js';
import type { AppConfig } from './config.js';
import type { AppContext } from './context.js';
import { HttpError, notFound, unauthorized } from './errors.js';
import { AppStoreVerifier, loadRootCertificate } from './iap/appstore.js';
import { PremiumService } from './iap/premium.js';
import { InMemoryMatchmaker, type Matchmaker } from './matchmaking/Matchmaker.js';
import { createModerationProvider, type ModerationProvider } from './moderation/ModerationProvider.js';
import { ModerationService } from './moderation/ModerationService.js';
import { ApnsPushProvider } from './push/apns.js';
import { NoopPushProvider, type PushProvider } from './push/PushProvider.js';
import { OnlinePushScheduler } from './push/scheduler.js';
import { CallService } from './realtime/CallService.js';
import { DateEngine } from './realtime/DateEngine.js';
import { Hub } from './realtime/Hub.js';
import { CLOSE } from './realtime/protocol.js';
import { QueueService, resolveSuspension } from './realtime/QueueService.js';
import { registerWebSocket, WS_MAX_PAYLOAD_BYTES } from './realtime/ws.js';
import { registerAuthRoutes } from './routes/auth.js';
import { registerIapRoutes } from './routes/iap.js';
import { registerMatchRoutes } from './routes/matches.js';
import { registerMeRoutes } from './routes/me.js';
import { registerSafetyRoutes } from './routes/safety.js';
import { AccountService } from './services/accounts.js';
import { IceService } from './services/ice.js';
import { RateLimiter } from './services/rateLimit.js';
import { UsageService } from './services/usage.js';
import { MemoryStore } from './store/MemoryStore.js';
import type { Store } from './store/Store.js';
import { systemClock, type Clock } from './util.js';

const DATA_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../data');

export function loadIcebreakers(file: string = path.join(DATA_DIR, 'icebreakers.json')): string[] {
  const questions = z.array(z.string().min(5)).min(60).parse(JSON.parse(readFileSync(file, 'utf8')));
  return [...new Set(questions)];
}

/** Everything is injectable so tests can run the real server in-process with fakes at the edges. */
export interface BuildOptions {
  config: AppConfig;
  store?: Store;
  blobs?: BlobStore;
  matchmaker?: Matchmaker;
  moderationProvider?: ModerationProvider;
  push?: PushProvider;
  appleJwksFetcher?: JwksFetcher;
  appStoreVerifier?: AppStoreVerifier;
  clock?: Clock;
  rng?: () => number;
  questions?: readonly string[];
}

export interface BuiltApp {
  app: FastifyInstance;
  ctx: AppContext;
}

function bearer(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (typeof header !== 'string') return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  return match?.[1] ?? null;
}

export async function buildApp(options: BuildOptions): Promise<BuiltApp> {
  const { config } = options;
  const clock = options.clock ?? systemClock;

  const app = Fastify({
    logger: {
      level: config.logLevel,
      redact: ['req.headers.authorization', 'req.headers.cookie'],
      serializers: {
        // The WebSocket URL carries the session token in its query string: never log queries.
        req: (req: { method?: string; url?: string; ip?: string }) => ({
          method: req.method,
          url: typeof req.url === 'string' ? req.url.split('?')[0] : undefined,
          ip: req.ip,
        }),
      },
    },
    trustProxy: config.trustProxy,
    bodyLimit: 256 * 1024,
  });
  const log = app.log;

  const store = options.store ?? new MemoryStore();
  let listeningUrl = `http://localhost:${config.port}`;
  const blobs =
    options.blobs ??
    (config.blobStore === 's3' && config.s3.bucket !== undefined && config.s3.publicBaseUrl !== undefined
      ? new S3BlobStore({ ...config.s3, bucket: config.s3.bucket, publicBaseUrl: config.s3.publicBaseUrl })
      : new LocalBlobStore(path.resolve(config.uploadDir), () => config.publicBaseUrl ?? listeningUrl));

  const push =
    options.push ??
    (config.push.provider === 'apns' &&
    config.push.apnsKeyPath !== undefined &&
    config.push.apnsKeyId !== undefined &&
    config.push.apnsTeamId !== undefined
      ? new ApnsPushProvider({
          keyPath: config.push.apnsKeyPath,
          keyId: config.push.apnsKeyId,
          teamId: config.push.apnsTeamId,
          bundleId: config.appleBundleId,
          production: config.push.apnsProduction,
          onError: (err) => log.warn({ err: err.message }, 'apns connection error'),
        })
      : new NoopPushProvider());

  const hub = new Hub();
  const matchmaker = options.matchmaker ?? new InMemoryMatchmaker({ exploreRate: config.matchExploreRate });
  const sessions = new SessionTokens(config.jwtSecret, config.sessionTtlDays);
  const apple = new AppleIdentityVerifier(config.appleBundleId, options.appleJwksFetcher ?? defaultJwksFetcher, clock);
  const ice = new IceService(config, clock);
  const usage = new UsageService(store, config, clock);
  const rateLimiter = new RateLimiter(clock);

  const dates = new DateEngine({
    config,
    clock,
    hub,
    store,
    matchmaker,
    ice,
    log,
    questions: options.questions ?? loadIcebreakers(),
    rng: options.rng,
  });
  // CallService and QueueService each need to know about the other's "busy" state.
  const calls: CallService = new CallService({
    hub,
    store,
    isBusyElsewhere: (userId) => dates.isBusy(userId),
    onCallStarted: (userId) => matchmaker.dequeue(userId),
  });
  const queue = new QueueService({
    config,
    clock,
    hub,
    store,
    matchmaker,
    dates,
    usage,
    log,
    inCall: (userId) => calls.inCall(userId),
  });
  const accounts = new AccountService({ config, clock, store, hub, matchmaker, dates, calls, queue, blobs, log });
  const moderation = new ModerationService({
    config: config.moderation,
    provider: options.moderationProvider ?? createModerationProvider(config.moderation),
    store,
    hub,
    dates,
    calls,
    accounts,
    log,
  });
  const appStoreVerifier =
    options.appStoreVerifier ??
    new AppStoreVerifier({
      rootCert:
        config.appleRootCaPath !== undefined
          ? loadRootCertificate(config.appleRootCaPath, config.appleRootCaSha256)
          : null,
      allowUnsigned: config.allowDevIap,
      clock,
    });
  const premium = new PremiumService(store, appStoreVerifier, config.appleBundleId, clock, log, (userId) =>
    queue.refresh(userId),
  );
  const pushScheduler = new OnlinePushScheduler({
    config: { ...config.push, repairCooldownHours: config.repairCooldownHours },
    clock,
    store,
    matchmaker,
    push,
    log,
  });

  const authenticateOptional = async (request: FastifyRequest) => {
    const token = bearer(request);
    if (token === null) return null;
    const userId = await sessions.verify(token);
    if (userId === null) return null;
    const user = await store.getUser(userId);
    // A timed suspension that has run out is lifted the first time the user shows up again.
    return user ? resolveSuspension(store, user, clock.now()) : null;
  };
  const ctx: AppContext = {
    config,
    clock,
    log,
    store,
    blobs,
    sessions,
    apple,
    hub,
    matchmaker,
    dates,
    calls,
    queue,
    usage,
    ice,
    accounts,
    moderation,
    premium,
    push,
    pushScheduler,
    rateLimiter,
    authenticateOptional,
    authenticate: async (request) => {
      const user = await authenticateOptional(request);
      if (!user) throw unauthorized('Please sign in again.');
      return user;
    },
  };

  // ---- errors: always `{ error: { code, message } }` ----
  app.setErrorHandler((err: FastifyError | HttpError, request, reply) => {
    if (err instanceof HttpError) {
      return reply.code(err.statusCode).send({ error: { code: err.code, message: err.message } });
    }
    const status = typeof err.statusCode === 'number' ? err.statusCode : 500;
    if (status >= 400 && status < 500) {
      const code =
        status === 413
          ? 'payload_too_large'
          : status === 415
            ? 'unsupported_media_type'
            : status === 429
              ? 'rate_limited'
              : 'invalid_request';
      const message = status === 413 ? 'That upload is too large.' : 'The request could not be understood.';
      return reply.code(status).send({ error: { code, message } });
    }
    request.log.error({ err }, 'unhandled request error');
    return reply
      .code(500)
      .send({ error: { code: 'internal', message: 'Something went wrong on our side. Try again in a moment.' } });
  });
  // Oversized bodies: Fastify answers 413 and closes the socket without reading the body, and a
  // client still writing then sees a broken connection instead of the 413. Read and discard a
  // moderately oversized body first so the answer arrives. Anything far larger is still cut off.
  const DRAIN_FACTOR = 4;
  app.addHook('onRequest', (request, reply, done) => {
    const declared = Number(request.headers['content-length']);
    const limit = request.routeOptions.bodyLimit ?? 256 * 1024;
    if (!Number.isFinite(declared) || declared <= limit || declared > limit * DRAIN_FACTOR) {
      done();
      return;
    }
    const raw = request.raw;
    raw.on('data', () => {});
    raw.once('error', () => raw.destroy());
    raw.once('end', () => {
      void reply.code(413).send({ error: { code: 'payload_too_large', message: 'That upload is too large.' } });
    });
  });

  app.setNotFoundHandler((_request, reply) =>
    reply.code(404).send({ error: { code: 'not_found', message: 'Not found' } }),
  );

  // Lenient JSON parsing: native clients often send `Content-Type: application/json` on
  // body-less POST/DELETE requests, which Fastify's default parser rejects.
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (_request, body, done) => {
    const text = typeof body === 'string' ? body : body.toString('utf8');
    if (text.trim().length === 0) return done(null, undefined);
    try {
      done(null, JSON.parse(text));
    } catch {
      done(new HttpError(400, 'invalid_request', 'The request body is not valid JSON.'), undefined);
    }
  });

  // ---- plugins ----
  if (config.corsOrigin !== undefined) {
    // Off unless CORS_ORIGIN is set: the only first-party client is a native app.
    await app.register(cors, { origin: config.corsOrigin.split(',').map((o) => o.trim()) });
  }
  let stopSweeper: () => void = () => undefined;
  await app.register(websocket, {
    options: { maxPayload: WS_MAX_PAYLOAD_BYTES },
    // Replaces the plugin's default shutdown (which closes sockets with no status code): stop every
    // timer first, then tell each client we are going away so it reconnects to another instance.
    preClose: async () => {
      stopSweeper();
      queue.stop();
      pushScheduler.stop();
      dates.shutdown();
      calls.shutdown();
      const clients = [...app.websocketServer.clients];
      for (const client of clients) {
        try {
          client.close(CLOSE.shutdown, 'server shutting down');
        } catch {
          client.terminate();
        }
      }
      // Peers that never complete the close handshake are cut off so shutdown stays bounded.
      const reaper = setTimeout(() => {
        for (const client of clients) {
          if (client.readyState !== client.CLOSED) client.terminate();
        }
      }, 2000);
      reaper.unref();
      await new Promise<void>((resolve) => app.websocketServer.close(() => resolve()));
    },
  });

  // ---- routes ----
  app.get('/health', async () => ({ ok: true }));
  app.get('/v1/config', async (request) => {
    const user = await authenticateOptional(request);
    return {
      dateDurationSec: config.dateDurationSec,
      turnDurationSec: config.turnDurationSec,
      decisionWindowSec: config.decisionWindowSec,
      freeDailyDates: config.freeDailyDates,
      frameSampleIntervalSec: config.frameSampleIntervalSec,
      // TURN credentials are only issued to signed-in callers; anonymous callers get STUN.
      iceServers: ice.serversFor(user?.id),
    };
  });
  if (blobs instanceof LocalBlobStore) {
    app.get<{ Params: { key: string } }>(`${LocalBlobStore.ROUTE_PREFIX}:key`, async (request, reply) => {
      const data = await blobs.read(request.params.key);
      if (!data) throw notFound();
      return reply
        .header('content-type', 'image/jpeg')
        .header('cache-control', 'public, max-age=31536000, immutable')
        .header('x-content-type-options', 'nosniff')
        .send(data);
    });
  }
  registerAuthRoutes(app, ctx);
  registerMeRoutes(app, ctx);
  registerMatchRoutes(app, ctx);
  registerSafetyRoutes(app, ctx);
  registerIapRoutes(app, ctx);
  stopSweeper = registerWebSocket(app, ctx);

  // ---- lifecycle ----
  app.addHook('onListen', async () => {
    const address = app.server.address();
    if (address !== null && typeof address === 'object') listeningUrl = `http://localhost:${address.port}`;
    queue.start();
    if (config.env !== 'test') pushScheduler.start();
  });
  app.addHook('onClose', async () => {
    await dates.flush();
    await push.close();
    await store.close();
  });

  return { app, ctx };
}
