# Tempo server

Backend for Tempo, live 1:1 video speed dating. REST + WebSocket API exactly as defined in `../SPEC.md` section 3.

- Node 22, TypeScript (strict), Fastify 5, `@fastify/websocket`, zod, pino, vitest
- Postgres for durable data (in-memory store when `DATABASE_URL` is unset)
- Video never touches this server: it relays WebRTC signalling only. Media is peer to peer (or via your TURN server).

The product name lives in one constant: `src/appName.ts`.

## Run it

```bash
cd server
npm install
cp .env.example .env          # set JWT_SECRET (>= 32 chars); dev flags are already on
set -a; . ./.env; set +a
npm run dev                   # http://localhost:8080, in-memory store
```

Other commands:

| Command | What it does |
|---|---|
| `npm test` | Full vitest suite (no external services needed) |
| `npm run typecheck` | `tsc --noEmit` over src, tests and scripts |
| `npm run build` / `npm start` | Compile to `dist/` and run the compiled server |
| `npm run migrate` | Apply `migrations/*.sql` to `DATABASE_URL` (also runs automatically at startup) |
| `npm run sim -- --url http://localhost:8080 --clients 8 --seconds 40` | N fake clients sign in, queue, date, pass turns, decide and re-queue. Exits non-zero on any protocol error. Needs `ALLOW_DEV_AUTH=1` on the server. |

For a quick end-to-end run, start the server with short dates and point the simulator at it:

```bash
ALLOW_DEV_AUTH=1 DATE_DURATION_SEC=6 TURN_DURATION_SEC=2 DECISION_WINDOW_SEC=3 READY_TIMEOUT_SEC=1 npm run dev
npm run sim -- --clients 8 --seconds 40
```

Testing from a phone on your LAN: set `PUBLIC_BASE_URL=http://<your-mac-ip>:8080` so photo URLs resolve on the device.

## Deploy

1. **Postgres.** Create a database and set `DATABASE_URL` (and `DATABASE_SSL=1` for managed Postgres). Migrations run at startup; each file runs once, in a transaction, tracked in `schema_migrations`.
2. **Secrets.** `JWT_SECRET` (`openssl rand -base64 48`). Mount `AppleRootCA-G3.cer` and the APNs `.p8` key as read-only files (see `certs/README.md`).
3. **Build and run the image.**
   ```bash
   docker build -t tempo-server .
   docker run -p 8080:8080 --env-file .env.production \
     -v /secure/certs:/app/certs:ro -v tempo-uploads:/app/uploads tempo-server
   ```
4. **Put TLS in front** (load balancer or reverse proxy), allow WebSocket upgrades on `/v1/ws`, set an idle timeout above 45 s, and set `TRUST_PROXY=1` so rate limits see real client IPs.
5. **Health check:** `GET /health` returns `{"ok":true}`. The image has a `HEALTHCHECK`.
6. **App Store Connect:** set the Server Notifications V2 URL (production and sandbox) to `https://<host>/v1/iap/notifications`.
7. **TURN:** run coturn with `use-auth-secret` and set `TURN_URLS` + `TURN_SECRET`. Without TURN, a meaningful share of mobile users behind symmetric NAT will fail to connect.

Shutdown is graceful: on `SIGTERM` the server stops timers, closes every WebSocket with code `1001`, flushes pending date writes, closes the pool and exits (forced after 15 s). One instance only for now, see "Scaling beyond one instance".

`NODE_ENV=production` refuses to start with `ALLOW_DEV_AUTH`, `ALLOW_DEV_IAP`, or without `APPLE_ROOT_CA_PATH`.

## Environment

All variables are validated at startup (`src/config.ts`); a bad value stops the process with a readable message.

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | `development` | `production` enables the safety checks above |
| `HOST`, `PORT` | `0.0.0.0`, `8080` | Listen address |
| `LOG_LEVEL` | `info` | pino level (`silent` in tests) |
| `PUBLIC_BASE_URL` | `http://localhost:<port>` | Origin used in photo URLs (local blob store) |
| `TRUST_PROXY` | `0` | `1` behind a proxy/load balancer |
| `CORS_ORIGIN` | unset | CORS is **off** unless set (comma-separated origins) |
| `JWT_SECRET` | **required** | HS256 key for session tokens, >= 32 chars. Also keys the deleted-identity hash |
| `SESSION_TTL_DAYS` | `30` | Session token lifetime |
| `APPLE_BUNDLE_ID` | `com.tempo.app` | Expected `aud` of Apple identity tokens, IAP `bundleId`, APNs topic |
| `ALLOW_DEV_AUTH` | `0` | Enables `POST /v1/auth/dev` (otherwise 404) |
| `ALLOW_DEV_IAP` | `0` | Accept unsigned test payloads on `/v1/iap/verify` |
| `APPLE_ROOT_CA_PATH` | unset | Apple Root CA - G3 file (DER or PEM). Required in production |
| `APPLE_ROOT_CA_SHA256` | unset | If set, the root file must have this SHA-256 fingerprint |
| `DATABASE_URL` | unset | Postgres connection string. Unset = in-memory store |
| `DATABASE_SSL`, `DATABASE_POOL_MAX` | `0`, `10` | Pool options |
| `BLOB_STORE` | `local` | `local` or `s3` |
| `UPLOAD_DIR` | `./uploads` | Photo directory for the local blob store |
| `S3_BUCKET`, `S3_PUBLIC_BASE_URL`, `S3_REGION`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | unset | S3-compatible storage (see below) |
| `DATE_DURATION_SEC` | `120` | Date length |
| `MATCH_ON_FULL_DATE` | `1` | Both staying to the end of the date is a match, no yes/no vote. `0` brings the vote back |
| `QUESTIONS_PER_DATE` | `0` | Optional cap on questions; `0` = no cap |
| `TURN_DURATION_SEC` | `30` | Icebreaker turn length |
| `DECISION_WINDOW_SEC` | `20` | Yes/No window |
| `FREE_DAILY_DATES` | `5` | Free daily cap |
| `FRAME_SAMPLE_INTERVAL_SEC` | `3` | Told to clients via `/v1/config` |
| `READY_TIMEOUT_SEC` | `8` | Date starts this long after pairing if not both ready |
| `RECONNECT_GRACE_SEC` | `6` | Grace after a socket drop during a live date |
| `DECISION_GRACE_MS` | `1000` | Extra wait after the advertised decision deadline (network latency) |
| `QUEUE_STATUS_INTERVAL_SEC` | `5` | `queue.status` broadcast and pairing tick |
| `REPAIR_COOLDOWN_HOURS` | `24` | Same two people are not re-paired within this window |
| `MATCH_EXPLORE_RATE` | `0.1` | Share of pairings that pick a random eligible partner instead of the best-scoring one |
| `WS_IDLE_TIMEOUT_SEC` | `45` | Silent sockets are dropped |
| `STRIKES_TO_SUSPEND` | `3` | Strikes before suspension |
| `STUN_URLS` | Google public STUN | Comma-separated |
| `TURN_URLS`, `TURN_SECRET`, `TURN_TTL_SEC` | unset, unset, `3600` | coturn shared-secret credentials, minted per user |
| `MODERATION_PROVIDER` | `mock` | `mock` or `http` |
| `MODERATION_API_URL`, `MODERATION_API_KEY` | unset | Required for `http` |
| `MODERATION_NUDITY_THRESHOLD` | `0.85` | Score at or above which a frame is nudity |
| `MODERATION_TIMEOUT_MS` | `4000` | Vendor call timeout |
| `PUSH_PROVIDER` | `noop` | `noop` or `apns` |
| `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID` | unset | Token-based APNs auth (.p8). Required for `apns` |
| `APNS_PRODUCTION` | `0` | `1` = production APNs host, `0` = sandbox |
| `PUSH_SCHEDULER_INTERVAL_SEC` | `300` | How often the "singles online" pass runs |
| `PUSH_MIN_INTERVAL_HOURS` | `4` | Minimum gap between those pushes per user |
| `PUSH_MIN_COMPATIBLE` | `3` | Minimum N to send |
| `PUSH_LOCAL_HOUR_START`, `PUSH_LOCAL_HOUR_END` | `9`, `23` | Only push inside these user-local hours |

## Layout

```
src/
  appName.ts            product name + product id (single source)
  config.ts             zod-validated environment
  app.ts                wiring: builds every service, routes, error envelope, shutdown
  index.ts              process entry: store selection, migrations, signals
  auth/                 Apple identity token verification (JWKS cache), session JWTs
  store/                Store interface, MemoryStore, PgStore, pg pool adapter, migration runner
  blob/                 BlobStore interface, local disk, S3-compatible
  matchmaking/          compat.ts (pure matching rules), score.ts (pure ranking), Matchmaker interface + in-memory impl
  realtime/             ws.ts (socket handler), Hub, QueueService, DateEngine, CallService, protocol.ts
  moderation/           provider interface, mock + HTTP providers, text classifier, enforcement
  iap/                  App Store JWS chain verification, premium state, notifications
  push/                 PushProvider, APNs HTTP/2, "singles online" scheduler
  services/             accounts (strikes, block, delete), usage (daily cap), ICE, rate limiting, serializers
  routes/               REST handlers
data/                   icebreakers.json (72 questions), explicit-terms.json (moderation word list)
migrations/             SQL
scripts/sim.ts          fake-client simulator
test/                   vitest suites
```

## How the pieces behave

**Matching** (`matchmaking/compat.ts`). Two queued people are paired when each satisfies the other's preferences: age (computed from birthdate), gender in the other's `interestedIn`, haversine distance within both limits when both have coordinates, and advanced filters, which count only when the owner of the filter is premium. A set advanced filter is a dealbreaker (someone who left that field blank does not pass). Never paired: blocked in either direction, currently matched, paired within 24 h, anyone under 18. Queue order is premium first, then longest wait.

**Ranking** (`matchmaking/score.ts`). The filters above decide who *can* be paired; the score decides who *is*. People are served in queue order, and each gets the eligible partner with the highest `mutualScore`: the estimated chance that both say yes. It combines how readily each person says yes, how often partners say yes to them (both smoothed toward 0.4 until there is history), and a fit from stated fields (intention, children, age gap, distance, religion, smoking, drinking). Each strike lowers a person's score by 15%. A partner's wait adds up to 0.1 (full after 60 s) so nobody is starved. `MATCH_EXPLORE_RATE` of pairings pick a random eligible partner so new people get dates and the data stays unbiased. Weights are hand-set; the private answers stored in `dates.decision_a/_b` (migration `002`) are the training data for fitting them later. Photos are never scored.

**Date lifecycle** (`realtime/DateEngine.ts`). `date.matched` (the person ahead in the queue is `caller`) -> both `date.ready` or 8 s -> `date.started` with server timestamps -> authoritative icebreaker turns -> timer -> `date.ended{timer, decisionDeadline}` -> `date.decide` from each (missing = no) -> `date.result`. Every timer belongs to its session and is cleared when the session ends.

**Daily cap.** A date counts when `date.started` fires. The "day" is the user's local day from `tzOffsetMinutes` (minutes east of UTC).

**Safety.** Nudity ends the date at once for both and strikes the offender. Sexual language warns once per date, then ends with a strike. Three strikes suspend the account pending review (`suspendedUntil` null). Suspended users cannot queue, call or send messages. If a classifier is unreachable, moderation fails open and logs at `error` (alert on `frame moderation failed`).

**Lifting a suspension** is a manual review step; there is no admin API. After review:
```sql
UPDATE users SET suspended = false, suspended_until = NULL, strikes = 0 WHERE id = '<user id>';
```
Setting `suspended_until` to a future time makes it a timed suspension that lifts itself.

## Privacy: what is stored, and how frames are handled

- **Video and audio** never reach this server. WebRTC media is peer to peer or relayed by TURN, which cannot decrypt it.
- **Moderation frames** arrive on `POST /v1/moderation/frame`, are held in request memory, passed to the classifier, and discarded. They are never written to disk, the database, or logs. With `MODERATION_PROVIDER=http` the frame is sent to your vendor for classification, so the vendor's retention terms apply; choose a zero-retention plan and disclose the vendor in the privacy policy.
- **Transcripts** are classified in memory and discarded. The audit log records that a rule fired and which list entries matched (as indices such as `phrase:12`), never the words said.
- **Audit log** (`audit_log`): one row per moderation action (warn/end), strike, suspension, report, block, photo rejection, premium change and account deletion. Verdicts and ids only.
- **Stored per user:** profile fields, preferences, photo URLs, coarse location (lat/lng as sent by the client), APNs token, timezone offset, strike count, premium state, and the Sign in with Apple subject identifier. No email, no Apple name beyond the first name the user gives.
- **Messages** are stored until the match is removed or either account is deleted.
- **Account deletion** (`DELETE /v1/me`) hard-deletes the user row, photos (blob store), matches, all messages in those matches (both sides), blocks, push token and purchase binding. What remains: date rows with that participant nulled (so the other person's daily count stays right), reports about the account, and audit rows, all keyed by an internal id that no longer resolves to anyone. If the account had strikes or a suspension, a keyed hash of the identity subject is kept with the strike count so a ban cannot be cleared by deleting and signing up again. State this retention in the privacy policy.
- **Logs** never include tokens (query strings and `Authorization` are stripped), frames, transcripts or message text.

## Sign in with Apple

`POST /v1/auth/apple` verifies the identity token: RS256 signature against Apple's JWKS (`https://appleid.apple.com/auth/keys`), `iss`, `aud` = `APPLE_BUNDLE_ID`, `exp`. Keys are cached for an hour, refetched on an unknown `kid` at most once a minute, and served stale if Apple is briefly unreachable.

## In-app purchase verification

`POST /v1/iap/verify` takes a StoreKit 2 signed transaction (`Transaction.jwsRepresentation`). The server validates the `x5c` chain with `node:crypto` (`src/iap/appstore.ts`): each certificate is inside its validity period and signed by the next, the chain ends at the pinned **Apple Root CA - G3**, the leaf and intermediate carry Apple's App Store marker OIDs, then the ES256 signature is checked with the leaf key. Then `bundleId` and `productId` (`tempo.premium.monthly`) are checked and `isPremium` / `premiumExpiresAt` set.

Setup:
1. Download "Apple Root CA - G3 Root" from https://www.apple.com/certificateauthority/ (`AppleRootCA-G3.cer`).
2. Check it: `openssl x509 -inform der -in AppleRootCA-G3.cer -noout -fingerprint -sha256` must match the fingerprint Apple publishes on that page.
3. Set `APPLE_ROOT_CA_PATH` to the file and `APPLE_ROOT_CA_SHA256` to that fingerprint (the server then refuses any other file).

`POST /v1/iap/notifications` handles App Store Server Notifications V2 (`{signedPayload}`), verified the same way: `SUBSCRIBED`, `DID_RENEW`, `OFFER_REDEEMED`, `RENEWAL_EXTENDED`, `REFUND_REVERSED` grant or extend; `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `REFUND`, `REVOKE` remove premium. Premium is always evaluated against `premiumExpiresAt`, so a missed notification cannot leave someone premium forever. Notifications are matched to an account by `originalTransactionId` (bound at verify time) or by `appAccountToken` when the client sets it to the user id.

Dev: with `ALLOW_DEV_IAP=1`, `/v1/iap/verify` also accepts an unsigned payload, either plain JSON or a JWS without `x5c`:
```json
{"jwsTransaction":"{\"bundleId\":\"com.tempo.app\",\"productId\":\"tempo.premium.monthly\",\"transactionId\":\"1\",\"originalTransactionId\":\"1\",\"expiresDate\":4102444800000}"}
```

## Moderation vendor

`ModerationProvider` (`src/moderation/ModerationProvider.ts`) has two implementations:

- `mock` (default): deterministic. A frame is nudity when its bytes contain the ASCII marker `TEMPO_TEST_NUDITY`. Text uses the real built-in classifier.
- `http`: frames go to a vision-moderation API. Everything is implemented (auth header, timeout, error handling, threshold) **except the vendor's request/response shape**, isolated in two functions between the `VENDOR-SPECIFIC MAPPING` banners: `buildVendorFrameRequest` and `parseVendorFrameResponse`. As shipped they speak a neutral contract (`POST {image: base64}` -> `{nudity: 0..1}`); replace the two bodies for Hive, Sightengine, or a Rekognition gateway.

Text moderation works without any vendor: `src/moderation/textClassifier.ts` normalises (case, accents, leetspeak, symbols as letters, spaced-out and stretched letters) and matches whole words and phrases from `data/explicit-terms.json`. Ordinary profanity is deliberately not on the list; ambiguous words appear only inside phrases. Edit the JSON to tune it; no code change needed. It is English only.

## Photo storage on S3

Default is local disk (`UPLOAD_DIR`), served at `/uploads/<uuid>.jpg`. Use that only on a single instance with a persistent volume.

`S3BlobStore` implements keys, public URLs and delete-by-URL. The two network calls go through a small `S3Transport` interface that is intentionally not bundled, so the server carries no cloud SDK. To enable: `npm i @aws-sdk/client-s3`, then pass a transport in `src/index.ts`:

```ts
import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { S3BlobStore, type S3Transport } from './blob/BlobStore.js';

const s3 = new S3Client({ region: config.s3.region, endpoint: config.s3.endpoint });
const transport: S3Transport = {
  putObject: async ({ bucket, key, body, contentType }) => {
    await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: contentType }));
  },
  deleteObject: async ({ bucket, key }) => {
    await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
  },
};
const blobs = new S3BlobStore({ ...config.s3, bucket: config.s3.bucket!, publicBaseUrl: config.s3.publicBaseUrl! }, transport);
const { app } = await buildApp({ config, store, blobs });
```
`S3_PUBLIC_BASE_URL` is the CDN or bucket origin that serves `photos/<key>`. With `BLOB_STORE=s3` and no transport, the first upload throws rather than silently writing to disk.

## Push

`PushProvider` has `noop` (default; records sends in memory) and `apns` (HTTP/2, token auth with the `.p8` key, provider token reused for 50 minutes, dead device tokens forgotten on `410`/`BadDeviceToken`).

The scheduler sends "N compatible singles are online now" only when all hold: the user opted in (`notifyOnlineSingles`) with push enabled and a token, is not online, has not had this push in the last 4 h, N >= 3 computed with the real matching rules, and it is between 09:00 and 23:00 in their local time. The send is recorded before the APNs call, so a slow or failed call can never cause a second push inside the window. A chat message to someone who is offline also sends a push ("Maya sent you a message"; the text is not included).

## Rate limits and request limits

Per user (per IP for unauthenticated routes), fixed window, in memory:

| Route | Limit |
|---|---|
| `/v1/auth/*` | 10 / minute / IP |
| `/v1/reports` | 10 / hour |
| `/v1/blocks` | 30 / hour |
| `/v1/moderation/frame` | 40 / minute |
| `/v1/moderation/transcript` | 90 / minute |
| `/v1/matches/:id/messages` (POST) | 60 / minute |
| `/v1/me/photos` | 20 / hour |
| `/v1/iap/verify` | 20 / minute |
| `/v1/iap/notifications` | 300 / minute / IP |

Body limits: 256 KB by default; photos 8 MB request (5 MB decoded JPEG); frames 2 MB request (1 MB decoded); notifications 512 KB. WebSocket frames 256 KB; more than 300 frames in 10 s closes the socket (`4003`).

## Scaling beyond one instance

Today a single process holds live state. That is deliberate and contained: durable data is already in Postgres, and everything live sits behind four seams. Moving to several instances is a change to these four places only.

| Seam | Today | With Redis |
|---|---|---|
| `Matchmaker` interface (`matchmaking/Matchmaker.ts`) | `InMemoryMatchmaker`: a map of online candidates, some queued | `RedisMatchmaker`: candidate snapshot as a hash `online:{userId}` with a TTL refreshed by heartbeats; queue as a sorted set scored `(premium ? 0 : 1e13) + queuedAt`; exclusions as a set per user. `takePairs` runs as one Lua script (or under a short `SET NX PX` lock) so two instances can never claim the same person. `compat.ts` stays as is: it is pure. |
| `Hub.send` (`realtime/Hub.ts`) | Looks up the local socket | Deliver locally if the socket is here, otherwise `PUBLISH user:{id}`. Each instance subscribes for the users connected to it. Every call site already goes through `hub.send`. |
| `DateEngine` / `CallService` sessions | In-memory maps and `setTimeout` | Simplest correct option: pin both participants' date to one instance. The instance that forms the pair owns the session and its timers; the other user's messages reach it through a `date:{id}` channel, and its sends go out through the pub/sub Hub. Store `user:{id}:date -> {dateId, ownerInstance}` in Redis with a TTL so reconnects land correctly. If the owner dies, the TTL expires and both clients see `date.ended{disconnect}` from their own instance. |
| `RateLimiter.hit` (`services/rateLimit.ts`) | In-memory fixed window | `INCR` + `PEXPIRE` on the same key |

Also needed with several instances: sticky sessions are **not** required once the Hub is pub/sub; run the push scheduler on one instance only (or take a Postgres advisory lock around `runOnce`); switch the blob store to S3.

Capacity note for the single instance: the queue tick is O(queued x online) compatibility checks every 5 s, which is fine into the low thousands of concurrent users.

## WebSocket reference (beyond the spec)

Close codes: `4000` replaced by a newer socket for the same user, `4001` idle timeout, `4002` account deleted, `4003` flood, `1001` server shutting down (reconnect).

`error.code` values: `bad_message`, `not_in_date`, `not_your_turn`, `onboarding_incomplete`, `underage`, `already_in_date`, `in_call`, `busy`, `partner_offline`, `partner_busy`, `match_not_found`, `call_not_found`, `account_suspended`, `internal`.

See `../NOTES-backend.md` for every decision the spec left open.

## Tests

`npm test` runs everything in-process: real HTTP and real WebSockets against the real server with shortened timings, PgStore's SQL and migrations against PGlite (Postgres compiled to WASM), APNs against a local HTTP/2 server, and App Store chain validation against a throwaway CA built with `openssl` (must be on `PATH`).
