# NOTES-backend

Agent BACKEND. Everything lives in `server/`. Run and deploy steps, the env table and the privacy note are in `server/README.md`.

## Final state

- `npx tsc --noEmit`: clean (0 errors) over `src/`, `test/`, `scripts/`.
- `npx vitest run`: **222 passed, 0 failed, 0 skipped, 11 files** (about 26 s). Run three times in a row, same result each time.
- `npm run build` + `npm run sim` against the compiled server: 8 clients, 16 dates, 0 protocol errors.

| File | Tests | Covers |
|---|---|---|
| `matchmaker.test.ts` | 30 | compatibility matrix (age, distance, gender, each premium filter, exclusions, under-18), queue ordering, pairing |
| `usage.test.ts` | 4 | local-midnight arithmetic, cap of 5, reset, premium unlimited, `queue.limit` over the wire |
| `dateflow.test.ts` | 19 | full date over real WebSockets: pairing, ready / 8 s fallback, signal relay, turns incl. pass, timer end, yes+yes match, yes/no, missing answer, leave early, leave before start, leave while deciding, disconnect + grace, reconnect inside grace, socket replacement, outsiders rejected, shutdown |
| `moderation.test.ts` | 51 | text classifier (flag / no-flag lists), HTTP provider adapter, nudity end + strike, warn then end, per-date warnings, 3 strikes suspension, fail-open, photo screening |
| `social.test.ts` | 20 | chat delivery, unread, read marker, idempotency, auth guard on every route, cross-user authorization, unmatch, blocks, 24 h cooldown, reports, post-match calls, account deletion |
| `auth.test.ts` | 21 | Apple token verification (signature, iss, aud, exp, alg confusion, JWKS cache), session tokens, auth endpoints, env validation |
| `profile.test.ts` | 25 | config, profile validation, 18+ gate, preferences (advanced ignored unless premium), photos, push token |
| `iap.test.ts` | 18 | x5c chain validation against a pinned root (forged root, spliced leaf, tampering, missing OIDs, expiry), verify endpoint, notifications |
| `store.contract.test.ts` | 24 | the same 12 contract tests against `MemoryStore` and against `PgStore` + real migrations on PGlite |
| `push.test.ts` | 6 | scheduler limits: N >= 3, 1 per 4 h, opt-in, not while online, quiet hours, dead tokens |
| `apns.test.ts` | 4 | APNs provider against a local HTTP/2 server |

### What was not verified here (be aware)

- **No real Postgres server was available.** `PgStore` and the migration were run against PGlite (real Postgres compiled to WASM) through the same `Queryable` interface. The thin `pg` pool adapter (`src/store/pgPool.ts`, about 60 lines) is typechecked but has not executed against a live server.
- **Nothing was run against Apple.** Apple JWKS fetch, APNs and the App Store chain were tested with locally generated keys, a local HTTP/2 server and a throwaway CA shaped like Apple's. The real Apple Root CA - G3 file is not in the repo (the shell could not reach apple.com); it must be downloaded per `server/certs/README.md`.
- **The HTTP moderation provider** was tested against a fake `fetch`, not a real vendor.
- **The Dockerfile** was written but not built (no Docker in this workspace).
- **S3** is an interface plus URL/key logic; no upload has been made to a real bucket.

## What was built

REST and WebSocket exactly per SPEC section 3: every path, field name, message type and enum. Beyond the routes:

- Sign in with Apple verification with JWKS caching; dev auth behind `ALLOW_DEV_AUTH=1`; HS256 session JWTs.
- `Store` interface with `MemoryStore` and `PgStore` (`migrations/001_init.sql`), selected by `DATABASE_URL`.
- `Matchmaker` interface with an in-memory implementation; pure matching rules in `compat.ts`.
- `DateEngine`: the whole date state machine with server-owned timers and the icebreaker turn engine (72 questions in `data/icebreakers.json`).
- Post-match calls, chat, unread counts, unmatch, reports, blocks, account deletion.
- `ModerationProvider` (mock + HTTP adapter), built-in sexual-language classifier, enforcement ladder, audit log.
- App Store JWS verification with `node:crypto` chain validation, Server Notifications V2 webhook.
- `PushProvider` (no-op + APNs HTTP/2), "singles online" scheduler.
- zod env validation, pino logging with tokens stripped, rate limits, body limits, CORS off by default, graceful shutdown, `/health`, Dockerfile, simulator.

## Decisions the spec did not cover

### iOS client needs to know these

1. **`tzOffsetMinutes` is minutes EAST of UTC** (`TimeZone.current.secondsFromGMT() / 60`; New York in winter = `-300`). This matches what `PushService.swift` already sends.
2. **Gap to close on the client: the timezone only reaches the server with a push token.** `PushService.upload` returns early when there is no APNs token, so anyone who declines notifications never sends a timezone and their daily cap resets at **UTC midnight**, not local midnight. The server accepts either fix, both additive:
   - `PUT /v1/me` with `{"tzOffsetMinutes": -300}` (extra optional field), or
   - `POST /v1/me/push-token` with `{"apnsToken": "", "tzOffsetMinutes": -300, "enabled": false}` (an empty token is allowed and stores only the offset).
3. **Suspension pending review is not visible in `User`.** Per the brief, pending review is `suspendedUntil` = null, which is omitted on the wire. `User.isSuspended` in `User.swift` (true only when `suspendedUntil` is in the future) is therefore **false** for a 3-strike account. The reliable signal is the `account.suspended` WebSocket message, sent on every connect and on every `queue.join` while suspended; `strikes >= 3` is a usable fallback. Timed suspensions do set `suspendedUntil`.
4. **A new account** has `birthdate: ""` and no `gender` key (both matched the client's lenient decoder). All optional fields are **omitted**, never `null`. The only explicit nulls are `usage.limit` and `premiumExpiresAt` in the `/v1/iap/verify` response.
5. **`PUT /v1/me`**
   - `onboardingComplete: true` is accepted only once first name, birthdate, gender and a non-empty `interestedIn` exist; otherwise `400 profile_incomplete`.
   - Under 18 -> `403 underage`. After onboarding the birthdate cannot be changed -> `400 birthdate_locked` (re-sending the same value is fine).
   - `photoUrls` may only reorder or remove URLs returned by `POST /v1/me/photos` (which already appends to the profile); unknown URLs -> `400 invalid_photo`. Removed photos are deleted from storage.
   - `null` clears `intention`, `children`, `religion`, `education`, `smoking`, `drinking`, `lat`/`lng`. `lat` and `lng` must be set together.
   - `isPremium`, `strikes` and other server-owned fields in the body are ignored.
6. **`PUT /v1/me/preferences` replaces.** For a premium user, an advanced filter that is absent, null or empty is cleared. For a free user, advanced fields in the request are ignored and whatever was stored stays (unenforced). Bounds: `ageMin` 18 to 99, `ageMin <= ageMax`, `maxDistanceKm` 1 to 20000.
7. **Photos:** JPEG only, max 6 per profile (`400 too_many_photos`), 5 MB decoded, screened by the frame classifier (`422 photo_rejected`). Moderation frames: JPEG, 1 MB decoded.
8. **`Partner.distanceKm`** is a whole number, minimum 1. `Partner.age` is computed server-side.
9. **`GET /v1/config` is public.** TURN credentials appear in `iceServers` only when the request carries a valid token (they are per user and short-lived); anonymous callers get STUN. `date.matched.iceServers` always includes TURN when configured. For post-match calls, use the list from an authenticated `/v1/config`.
10. **Reconnecting.** A new socket for the same user replaces the old one (old closes with `4000`) and does not count as a disconnect. On every connect the server replays where the user is: `date.matched` if connecting; `date.started` plus the current `icebreaker.turn` (same timestamps) if live; `date.ended{timer, decisionDeadline}` if deciding. If the date ended while the user was away past the 6 s grace, they receive `date.ended{reason:"disconnect"}` on reconnect (within 2 minutes) so the call UI can exit. The partner is not told about a drop until the grace window runs out.
11. **A disconnect while still connecting** (before `date.started`) ends the date at once, no grace.
12. **Leaving during the decision window:** the leaver gets `date.result{no_match}` immediately and is free; the partner keeps their window and gets their `date.result` when they answer or at the deadline.
13. **Decisions:** the first `date.decide` stands. Results are sent when both have answered, or at `decisionDeadline` + 1 s grace. Nothing is revealed after only one answer.
14. **Icebreaker:** the `caller` answers question 0 first, the `callee` question 1 first, and so on. `turnEndsAt` is clamped to the date's `endsAt`. Turns stop at the timer. A `turn.pass` from the non-speaker returns `error{not_your_turn}`.
15. **Moderation messages.** Only the offender receives `moderation.action` (warn or end). On `end`, both receive `date.ended{reason:"moderation"}`; the partner is not told what happened. The REST response `{action}` carries the same verdict.
16. **Post-match calls.**
    - The **inviter creates the WebRTC offer** after receiving `call.accept` (this matches `MatchesStore.swift`).
    - `call.invite` errors: `partner_offline`, `partner_busy`, `busy`, `match_not_found`. Unanswered after 45 s: both get `call.end`.
    - A participant's socket closing sends `call.end` to the other.
    - Moderation applies with `dateId = "call:" + matchId` on the same endpoints; an `end` verdict sends `moderation.action` to the offender and `call.end` to both.
    - `queue.join` during a call returns `error{in_call}`.
17. **Chat.** `POST .../messages` returns `200` with the `Message`. `clientId` makes retries idempotent per sender. `chat.message` goes to the recipient only (the sender has the REST response). `match.removed` goes to both people. Text is trimmed, 1 to 2000 chars.
18. **Blocking** also removes an existing match (`match.removed` to both) and ends a date in progress between the two (blocker gets `you_left`, the other `partner_left`).
19. **`account.suspended.reason`** is a user-presentable sentence, not a code. `until` is present only for timed suspensions.
20. **`queue.status.compatibleOnline`** counts connected, onboarded, non-suspended people who are mutually compatible, whether or not they are queued or mid-date. `GET /v1/online-count` uses the same number.
21. **`error.code` values** on the socket: `bad_message`, `not_in_date`, `not_your_turn`, `onboarding_incomplete`, `underage`, `already_in_date`, `in_call`, `busy`, `partner_offline`, `partner_busy`, `match_not_found`, `call_not_found`, `account_suspended`, `internal`. `not_in_date` is normal when a pass/leave races the end of a date.
22. **Close codes:** `4000` replaced, `4001` idle (45 s), `4002` account deleted, `4003` flood, `1001` server shutting down (reconnect).
23. **HTTP error codes** worth handling: `unauthorized` (401), `invalid_request` (400), `rate_limited` (429), `payload_too_large` (413), `not_found` (404; also returned for someone else's match), `underage`, `account_suspended`, `forbidden` (403), `photo_rejected` (422), `invalid_identity_token` (401), IAP: `invalid_signature`, `wrong_bundle`, `wrong_product` (400), `iap_not_configured` (503). `error.message` is always written to be shown to a user.
24. **IAP:** set `appAccountToken` to the user id (it is a UUID) when purchasing. It lets a renewal notification find the account even if `/v1/iap/verify` was never called. A subscription verified on a second account moves to it.
25. **Body-less requests** with `Content-Type: application/json` (DELETE, `POST .../read`) are accepted.

### Server-side choices

- **Blank attribute vs a set premium filter:** a set filter is a dealbreaker, so a person who has not filled in that field does not pass it.
- **Distance** uses the stricter of the two people's limits and is skipped when either has no coordinates.
- **Moderation fails open** when the classifier errors, with an `error` log line to alert on. A vendor outage should not end every date.
- **Audit log** records actions (warn, end, strike, suspension, report, block, photo rejection, premium change, deletion), not every clean sample (one per 3 s per user would be noise).
- **Ban carry-over:** deleting an account with strikes keeps a keyed hash of the identity subject plus the strike count, so delete-and-recreate does not clear a suspension. Disclosed in the README privacy note; needs a line in the privacy policy.
- **Deletion keeps** date rows (participant nulled), reports about the account and audit rows, by internal id only.
- **Push quiet hours:** "singles online" pushes only go out 09:00 to 23:00 user-local (not in the spec; a 3 am ping seemed wrong). Tunable by env.
- **Message push:** a chat message to an offline recipient sends a push without the message text (not in the spec; without it offline users never learn of messages).
- **Profile photos are screened** with the same classifier as frames.
- **Lifting a suspension** is manual SQL (README); there is no admin API.
- **Text classifier is English only** and deliberately excludes ordinary profanity. The list is `server/data/explicit-terms.json`.

## Needs real credentials before production

| What | Where |
|---|---|
| `JWT_SECRET` | env |
| Postgres | `DATABASE_URL`, `DATABASE_SSL=1` |
| Apple Root CA - G3 file + fingerprint | `APPLE_ROOT_CA_PATH`, `APPLE_ROOT_CA_SHA256` (required when `NODE_ENV=production`) |
| App Store Connect notification URL | point V2 notifications at `/v1/iap/notifications` |
| APNs `.p8` key | `PUSH_PROVIDER=apns`, `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRODUCTION=1` |
| Image moderation vendor | `MODERATION_PROVIDER=http`, `MODERATION_API_URL`, `MODERATION_API_KEY`, plus the two mapping functions in `src/moderation/ModerationProvider.ts`. **Until this is done, nudity detection is the mock**: it only reacts to a test marker and will not catch real nudity. |
| TURN server | `TURN_URLS`, `TURN_SECRET` (coturn `use-auth-secret`) |
| Photo storage | S3 transport per README, or a persistent volume for `UPLOAD_DIR` |
| TLS + proxy | terminate TLS in front, allow WebSocket upgrade, `TRUST_PROXY=1`, `PUBLIC_BASE_URL` |

Single instance only as built: live queue and date state are in process memory. The README section "Scaling beyond one instance" lists the four seams to move to Redis.
