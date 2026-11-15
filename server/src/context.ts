import type { FastifyBaseLogger, FastifyRequest } from 'fastify';
import type { AppleIdentityVerifier } from './auth/apple.js';
import type { SessionTokens } from './auth/session.js';
import type { BlobStore } from './blob/BlobStore.js';
import type { AppConfig } from './config.js';
import type { PremiumService } from './iap/premium.js';
import type { Matchmaker } from './matchmaking/Matchmaker.js';
import type { ModerationService } from './moderation/ModerationService.js';
import type { PushProvider } from './push/PushProvider.js';
import type { OnlinePushScheduler } from './push/scheduler.js';
import type { CallService } from './realtime/CallService.js';
import type { DateEngine } from './realtime/DateEngine.js';
import type { Hub } from './realtime/Hub.js';
import type { QueueService } from './realtime/QueueService.js';
import type { AccountService } from './services/accounts.js';
import type { IceService } from './services/ice.js';
import type { RateLimiter } from './services/rateLimit.js';
import type { UsageService } from './services/usage.js';
import type { Store } from './store/Store.js';
import type { UserRecord } from './types.js';
import type { Clock } from './util.js';

/** Everything routes and the WebSocket handler need, wired once in app.ts. */
export interface AppContext {
  config: AppConfig;
  clock: Clock;
  log: FastifyBaseLogger;
  store: Store;
  blobs: BlobStore;
  sessions: SessionTokens;
  apple: AppleIdentityVerifier;
  hub: Hub;
  matchmaker: Matchmaker;
  dates: DateEngine;
  calls: CallService;
  queue: QueueService;
  usage: UsageService;
  ice: IceService;
  accounts: AccountService;
  moderation: ModerationService;
  premium: PremiumService;
  push: PushProvider;
  pushScheduler: OnlinePushScheduler;
  rateLimiter: RateLimiter;
  /** Resolves the signed-in user or throws 401. */
  authenticate(request: FastifyRequest): Promise<UserRecord>;
  /** Like `authenticate` but returns null instead of throwing. */
  authenticateOptional(request: FastifyRequest): Promise<UserRecord | null>;
}
