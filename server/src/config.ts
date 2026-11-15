import { z } from 'zod';

const flag = z
  .enum(['0', '1', 'true', 'false'])
  .default('0')
  .transform((v) => v === '1' || v === 'true');

const csv = z
  .string()
  .default('')
  .transform((v) =>
    v
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  );

const optionalString = z
  .string()
  .optional()
  .transform((v) => (v !== undefined && v.trim().length > 0 ? v.trim() : undefined));

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(0).max(65535).default(8080),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  PUBLIC_BASE_URL: optionalString,
  TRUST_PROXY: flag,
  CORS_ORIGIN: optionalString,

  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  SESSION_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(30),

  APPLE_BUNDLE_ID: z.string().min(1).default('com.seymur.passionfruit'),
  ALLOW_DEV_AUTH: flag,
  ALLOW_DEV_IAP: flag,
  APPLE_ROOT_CA_PATH: optionalString,
  APPLE_ROOT_CA_SHA256: optionalString,

  DATABASE_URL: optionalString,
  DATABASE_SSL: flag,
  DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(200).default(10),

  BLOB_STORE: z.enum(['local', 's3']).default('local'),
  UPLOAD_DIR: z.string().default('./uploads'),
  S3_BUCKET: optionalString,
  S3_REGION: optionalString,
  S3_ENDPOINT: optionalString,
  S3_PUBLIC_BASE_URL: optionalString,
  S3_ACCESS_KEY_ID: optionalString,
  S3_SECRET_ACCESS_KEY: optionalString,

  DATE_DURATION_SEC: z.coerce.number().positive().default(240),
  TURN_DURATION_SEC: z.coerce.number().positive().default(30),
  DECISION_WINDOW_SEC: z.coerce.number().positive().default(20),
  CHECKPOINT_WINDOW_SEC: z.coerce.number().min(0).default(10),
  FREE_DAILY_DATES: z.coerce.number().int().min(0).default(5),
  FRAME_SAMPLE_INTERVAL_SEC: z.coerce.number().positive().default(3),
  READY_TIMEOUT_SEC: z.coerce.number().positive().default(8),
  RECONNECT_GRACE_SEC: z.coerce.number().min(0).default(6),
  DECISION_GRACE_MS: z.coerce.number().min(0).default(1000),
  QUEUE_STATUS_INTERVAL_SEC: z.coerce.number().positive().default(5),
  MATCH_EXPLORE_RATE: z.coerce.number().min(0).max(1).default(0.1),
  REPAIR_COOLDOWN_HOURS: z.coerce.number().min(0).default(24),
  WS_IDLE_TIMEOUT_SEC: z.coerce.number().positive().default(45),
  STRIKES_TO_SUSPEND: z.coerce.number().int().min(1).default(3),

  STUN_URLS: csv,
  TURN_URLS: csv,
  TURN_SECRET: optionalString,
  TURN_TTL_SEC: z.coerce.number().int().positive().default(3600),

  MODERATION_PROVIDER: z.enum(['mock', 'http']).default('mock'),
  MODERATION_API_URL: optionalString,
  MODERATION_API_KEY: optionalString,
  MODERATION_NUDITY_THRESHOLD: z.coerce.number().min(0).max(1).default(0.85),
  MODERATION_TIMEOUT_MS: z.coerce.number().int().positive().default(4000),

  PUSH_PROVIDER: z.enum(['noop', 'apns']).default('noop'),
  APNS_KEY_PATH: optionalString,
  APNS_KEY_ID: optionalString,
  APNS_TEAM_ID: optionalString,
  APNS_PRODUCTION: flag,
  PUSH_SCHEDULER_INTERVAL_SEC: z.coerce.number().positive().default(300),
  PUSH_MIN_INTERVAL_HOURS: z.coerce.number().min(0).default(4),
  PUSH_MIN_COMPATIBLE: z.coerce.number().int().min(1).default(3),
  PUSH_LOCAL_HOUR_START: z.coerce.number().int().min(0).max(23).default(9),
  PUSH_LOCAL_HOUR_END: z.coerce.number().int().min(1).max(24).default(23),
});

export type Env = z.infer<typeof EnvSchema>;

export interface AppConfig {
  env: 'development' | 'test' | 'production';
  host: string;
  port: number;
  logLevel: Env['LOG_LEVEL'];
  publicBaseUrl: string | undefined;
  trustProxy: boolean;
  corsOrigin: string | undefined;
  jwtSecret: string;
  sessionTtlDays: number;
  appleBundleId: string;
  allowDevAuth: boolean;
  allowDevIap: boolean;
  appleRootCaPath: string | undefined;
  appleRootCaSha256: string | undefined;
  databaseUrl: string | undefined;
  databaseSsl: boolean;
  databasePoolMax: number;
  blobStore: 'local' | 's3';
  uploadDir: string;
  s3: {
    bucket: string | undefined;
    region: string | undefined;
    endpoint: string | undefined;
    publicBaseUrl: string | undefined;
    accessKeyId: string | undefined;
    secretAccessKey: string | undefined;
  };
  /** Tunables. Durations may be fractional so tests can run a whole date in about a second. */
  dateDurationSec: number;
  turnDurationSec: number;
  decisionWindowSec: number;
  /** Seconds both people get, after the first question, to vote on carrying on. 0 turns the checkpoint off. */
  checkpointWindowSec: number;
  freeDailyDates: number;
  frameSampleIntervalSec: number;
  readyTimeoutSec: number;
  reconnectGraceSec: number;
  decisionGraceMs: number;
  queueStatusIntervalSec: number;
  /** Share of pairings that ignore the score and pick a random compatible partner (0..1). */
  matchExploreRate: number;
  repairCooldownHours: number;
  wsIdleTimeoutSec: number;
  strikesToSuspend: number;
  stunUrls: string[];
  turnUrls: string[];
  turnSecret: string | undefined;
  turnTtlSec: number;
  moderation: {
    provider: 'mock' | 'http';
    apiUrl: string | undefined;
    apiKey: string | undefined;
    nudityThreshold: number;
    timeoutMs: number;
  };
  push: {
    provider: 'noop' | 'apns';
    apnsKeyPath: string | undefined;
    apnsKeyId: string | undefined;
    apnsTeamId: string | undefined;
    apnsProduction: boolean;
    schedulerIntervalSec: number;
    minIntervalHours: number;
    minCompatible: number;
    localHourStart: number;
    localHourEnd: number;
  };
}

export class ConfigError extends Error {}

export function loadConfig(source: Record<string, string | undefined> = process.env): AppConfig {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  ${i.path.join('.') || '(root)'}: ${i.message}`);
    throw new ConfigError(`Invalid environment configuration:\n${lines.join('\n')}`);
  }
  const e = parsed.data;
  const problems: string[] = [];
  if (e.NODE_ENV === 'production') {
    if (e.ALLOW_DEV_AUTH) problems.push('ALLOW_DEV_AUTH must not be enabled in production');
    if (e.ALLOW_DEV_IAP) problems.push('ALLOW_DEV_IAP must not be enabled in production');
    if (e.APPLE_ROOT_CA_PATH === undefined) problems.push('APPLE_ROOT_CA_PATH is required in production');
  }
  if (e.MODERATION_PROVIDER === 'http' && (e.MODERATION_API_URL === undefined || e.MODERATION_API_KEY === undefined)) {
    problems.push('MODERATION_PROVIDER=http requires MODERATION_API_URL and MODERATION_API_KEY');
  }
  if (
    e.PUSH_PROVIDER === 'apns' &&
    (e.APNS_KEY_PATH === undefined || e.APNS_KEY_ID === undefined || e.APNS_TEAM_ID === undefined)
  ) {
    problems.push('PUSH_PROVIDER=apns requires APNS_KEY_PATH, APNS_KEY_ID and APNS_TEAM_ID');
  }
  if (e.BLOB_STORE === 's3' && (e.S3_BUCKET === undefined || e.S3_PUBLIC_BASE_URL === undefined)) {
    problems.push('BLOB_STORE=s3 requires S3_BUCKET and S3_PUBLIC_BASE_URL');
  }
  if (e.TURN_URLS.length > 0 && e.TURN_SECRET === undefined) {
    problems.push('TURN_URLS requires TURN_SECRET');
  }
  if (problems.length > 0) {
    throw new ConfigError(`Invalid environment configuration:\n${problems.map((p) => `  ${p}`).join('\n')}`);
  }
  return {
    env: e.NODE_ENV,
    host: e.HOST,
    port: e.PORT,
    logLevel: e.LOG_LEVEL,
    publicBaseUrl: e.PUBLIC_BASE_URL?.replace(/\/+$/, ''),
    trustProxy: e.TRUST_PROXY,
    corsOrigin: e.CORS_ORIGIN,
    jwtSecret: e.JWT_SECRET,
    sessionTtlDays: e.SESSION_TTL_DAYS,
    appleBundleId: e.APPLE_BUNDLE_ID,
    allowDevAuth: e.ALLOW_DEV_AUTH,
    allowDevIap: e.ALLOW_DEV_IAP,
    appleRootCaPath: e.APPLE_ROOT_CA_PATH,
    appleRootCaSha256: e.APPLE_ROOT_CA_SHA256?.replace(/[^0-9a-fA-F]/g, '').toLowerCase(),
    databaseUrl: e.DATABASE_URL,
    databaseSsl: e.DATABASE_SSL,
    databasePoolMax: e.DATABASE_POOL_MAX,
    blobStore: e.BLOB_STORE,
    uploadDir: e.UPLOAD_DIR,
    s3: {
      bucket: e.S3_BUCKET,
      region: e.S3_REGION,
      endpoint: e.S3_ENDPOINT,
      publicBaseUrl: e.S3_PUBLIC_BASE_URL,
      accessKeyId: e.S3_ACCESS_KEY_ID,
      secretAccessKey: e.S3_SECRET_ACCESS_KEY,
    },
    dateDurationSec: e.DATE_DURATION_SEC,
    turnDurationSec: e.TURN_DURATION_SEC,
    decisionWindowSec: e.DECISION_WINDOW_SEC,
    checkpointWindowSec: e.CHECKPOINT_WINDOW_SEC,
    freeDailyDates: e.FREE_DAILY_DATES,
    frameSampleIntervalSec: e.FRAME_SAMPLE_INTERVAL_SEC,
    readyTimeoutSec: e.READY_TIMEOUT_SEC,
    reconnectGraceSec: e.RECONNECT_GRACE_SEC,
    decisionGraceMs: e.DECISION_GRACE_MS,
    queueStatusIntervalSec: e.QUEUE_STATUS_INTERVAL_SEC,
    matchExploreRate: e.MATCH_EXPLORE_RATE,
    repairCooldownHours: e.REPAIR_COOLDOWN_HOURS,
    wsIdleTimeoutSec: e.WS_IDLE_TIMEOUT_SEC,
    strikesToSuspend: e.STRIKES_TO_SUSPEND,
    stunUrls: e.STUN_URLS.length > 0 ? e.STUN_URLS : ['stun:stun.l.google.com:19302'],
    turnUrls: e.TURN_URLS,
    turnSecret: e.TURN_SECRET,
    turnTtlSec: e.TURN_TTL_SEC,
    moderation: {
      provider: e.MODERATION_PROVIDER,
      apiUrl: e.MODERATION_API_URL,
      apiKey: e.MODERATION_API_KEY,
      nudityThreshold: e.MODERATION_NUDITY_THRESHOLD,
      timeoutMs: e.MODERATION_TIMEOUT_MS,
    },
    push: {
      provider: e.PUSH_PROVIDER,
      apnsKeyPath: e.APNS_KEY_PATH,
      apnsKeyId: e.APNS_KEY_ID,
      apnsTeamId: e.APNS_TEAM_ID,
      apnsProduction: e.APNS_PRODUCTION,
      schedulerIntervalSec: e.PUSH_SCHEDULER_INTERVAL_SEC,
      minIntervalHours: e.PUSH_MIN_INTERVAL_HOURS,
      minCompatible: e.PUSH_MIN_COMPATIBLE,
      localHourStart: e.PUSH_LOCAL_HOUR_START,
      localHourEnd: e.PUSH_LOCAL_HOUR_END,
    },
  };
}
