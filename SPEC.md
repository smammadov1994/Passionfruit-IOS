# TEMPO — live video speed dating (iOS) — shared build spec

Working name: **Tempo** (a "tempo" is a turn in chess; the icebreaker works like a chess clock). The name must live in ONE constant per codebase so it can be renamed.

Every agent reads this whole file first. Stay inside your owned directory. Do not invent wire messages or tokens that are not here; if something is missing, choose the simplest thing and record it in `NOTES-<yourname>.md` at the repo root.

## 1. Product rules (decided)
- Go online → server pairs you with a compatible person who is online right now (mutual filters: age, distance, gender; Premium adds intentions, children, religion, education, smoking, drinking).
- Date = live 1:1 video, **240 s**. Either person can leave at any moment. Leaving early = an automatic No from the leaver; the other person sees "They left" and moves on. No decision screen in that case.
- Timer ends → each privately picks Yes/No within **20 s** (no answer = No). Both Yes → match. Otherwise no match.
- After no-match / ended: 3 s interstitial, then automatically back in the queue (user can stop).
- Match → text chat, plus "video call again" from the chat.
- Icebreaker turns (optional overlay, user can hide it): a question shows; speaker A has **30 s**; turn passes automatically or by tapping "Pass"; then B answers the same question; then a new question, alternating who goes first. Video/audio are never muted or paused by this. Server is authoritative for turns.
- Free: **5 dates per day** (resets local midnight, server tracks by user tz offset). Premium **$14.99/month** (product id `tempo.premium.monthly`): unlimited dates, advanced filters, priority in queue.
- Push: "N compatible singles are online now" (max 1 per 4 h per user, only if N ≥ 3, opt-in).
- Safety: 18+ only (birthdate gate). Video frames sampled every 3 s from the LOCAL camera and sent to the server for moderation; local speech transcribed on-device and text chunks sent for moderation. Nudity/exposed body → call ends immediately for both, offender gets a strike. Sexual language → first a warning, second time in same date ends call + strike. 3 strikes → suspended pending review. Report + block available on every call and every match. Blocked pairs are never paired again. Account deletion in Settings.
- All tunables come from `GET /v1/config`, never hardcoded in UI.

## 2. Repo layout and ownership
```
tempo/
  SPEC.md
  server/                      -> agent BACKEND
  ios/
    project.yml                -> agent CORE (XcodeGen)
    Tempo/App/                 -> agent CORE (TempoApp.swift, AppEnvironment, Info.plist, entitlements)
    Tempo/Core/                -> agent CORE (Models, Networking, Services, Stores)
    Tempo/DesignSystem/        -> agent DESIGN
    Tempo/Features/            -> UI agents (phase 2)
    Tempo/Resources/           -> agent DESIGN (Assets.xcassets colors/app icon placeholder), CORE (Localizable, icebreakers fallback)
    TempoTests/                -> agent CORE
  preview/index.html           -> agent PREVIEW
```

## 3. Wire protocol (BACKEND and CORE must match exactly)
JSON everywhere, camelCase, ISO-8601 UTC timestamps with milliseconds. Auth: `Authorization: Bearer <token>`. Errors: HTTP status + `{ "error": { "code": "string", "message": "string" } }`.

### REST
| Method | Path | Body → Response |
|---|---|---|
| POST | /v1/auth/apple | `{identityToken, firstName?}` → `{token, user}` |
| POST | /v1/auth/dev | `{deviceId}` → `{token, user}` (enabled only when `ALLOW_DEV_AUTH=1`) |
| GET | /v1/config | → `{dateDurationSec, turnDurationSec, decisionWindowSec, freeDailyDates, frameSampleIntervalSec, iceServers:[{urls:[..],username?,credential?}]}` |
| GET | /v1/me | → `User` |
| PUT | /v1/me | partial `User` profile fields → `User` |
| PUT | /v1/me/preferences | `Preferences` → `Preferences` (advanced fields ignored unless premium) |
| POST | /v1/me/photos | `{imageBase64}` (jpeg) → `{url}` |
| POST | /v1/me/push-token | `{apnsToken, tzOffsetMinutes, enabled}` → 204 |
| DELETE | /v1/me | → 204 (deletes account and data) |
| GET | /v1/usage | → `{datesToday, limit|null, resetsAt}` |
| GET | /v1/online-count | → `{compatibleOnline}` |
| GET | /v1/matches | → `{matches:[Match]}` |
| DELETE | /v1/matches/:id | → 204 (unmatch) |
| GET | /v1/matches/:id/messages?before=<iso>&limit=50 | → `{messages:[Message]}` newest last |
| POST | /v1/matches/:id/messages | `{text, clientId}` → `Message` |
| POST | /v1/matches/:id/read | → 204 |
| POST | /v1/reports | `{userId, dateId?, matchId?, reason, details?}` → 204. reason ∈ `nudity, sexual_language, harassment, underage, fake_profile, spam, other` |
| POST | /v1/blocks | `{userId}` → 204 |
| POST | /v1/moderation/frame | `{dateId, imageBase64}` → `{action}` action ∈ `none, warn, end` |
| POST | /v1/moderation/transcript | `{dateId, text}` → `{action}` |
| POST | /v1/iap/verify | `{jwsTransaction}` → `{isPremium, premiumExpiresAt}` |
| GET | /health | → `{ok:true}` |

### Objects
```
User { id, firstName, birthdate(YYYY-MM-DD), gender, interestedIn:[gender], bio, city, lat?, lng?, photoUrls:[string],
       intention?, children?, religion?, education?, smoking?, drinking?,
       isPremium, premiumExpiresAt?, onboardingComplete, strikes, suspendedUntil? , preferences: Preferences }
gender ∈ woman | man | nonbinary
intention ∈ long_term | short_term | marriage | figuring_out
children ∈ has_wants_more | has_done | wants | doesnt_want | open
religion ∈ agnostic | atheist | buddhist | christian | hindu | jewish | muslim | spiritual | other
education ∈ high_school | some_college | bachelors | masters | doctorate
smoking ∈ never | sometimes | regularly
drinking ∈ never | socially | regularly
Preferences { ageMin, ageMax, maxDistanceKm, 
              intentions?:[intention], children?:[children], religions?:[religion], minEducation?:education,
              smokingOk?:[smoking], drinkingOk?:[drinking], notifyOnlineSingles:bool }
Partner { id, firstName, age, city, distanceKm?, photoUrl?, intention? }
Match { id, partner: Partner, matchedAt, lastMessage?: Message, unreadCount }
Message { id, matchId, senderId, text, sentAt, clientId? }
```

### WebSocket `GET /v1/ws?token=<token>`
Every frame: `{ "type": "...", ...fields }`. Server sends `pong` to `ping`. Client pings every 20 s; server drops after 45 s silence. One socket per user (new socket replaces old).

Client → Server
- `queue.join` `{}`
- `queue.leave` `{}`
- `date.ready` `{dateId}` (client has camera running; date clock starts when both ready or 8 s after pairing, whichever first)
- `rtc.signal` `{dateId, payload:{kind:"offer"|"answer"|"ice", sdp?, candidate?, sdpMid?, sdpMLineIndex?}}` (relayed verbatim to partner)
- `turn.pass` `{dateId}` (only valid from current speaker)
- `date.leave` `{dateId}`
- `date.decide` `{dateId, decision:"yes"|"no"}`
- `call.invite` `{matchId}` / `call.accept` `{matchId}` / `call.decline` `{matchId}` / `call.end` `{matchId}` (post-match video; uses `rtc.signal` with `dateId = "call:"+matchId`)
- `ping` `{}`

Server → Client
- `queue.status` `{compatibleOnline, position}` (on join and every 5 s while queued)
- `queue.limit` `{limit, resetsAt}` (free cap reached; user not queued)
- `date.matched` `{dateId, partner:Partner, role:"caller"|"callee", iceServers}` (caller creates the offer)
- `date.started` `{dateId, startsAt, endsAt}`
- `rtc.signal` `{dateId, payload}`
- `icebreaker.turn` `{dateId, question, questionIndex, speakerId, turnEndsAt, turnDurationSec}`
- `date.ended` `{dateId, reason, decisionDeadline?}` reason ∈ `timer | partner_left | you_left | moderation | disconnect`. `decisionDeadline` present only for `timer`.
- `date.result` `{dateId, outcome:"match"|"no_match", match?:Match}`
- `moderation.action` `{dateId, action:"warn"|"end", category:"nudity"|"sexual_language", message}`
- `chat.message` `{message:Message}`
- `match.removed` `{matchId}`
- `call.invite` / `call.accept` / `call.decline` / `call.end` `{matchId, fromUserId}`
- `account.suspended` `{until?, reason}`
- `error` `{code, message}`
- `pong` `{}`

Checkpoint: after both people have answered the first question the date pauses (`date.checkpoint {dateId, deadline}`), audio and video are hidden on both sides and the date clock stops. Each sends `date.continue {dateId, choice: "continue"|"end"}` privately; first choice stands. Both continue: `date.resumed {dateId, endsAt}` and the date carries on with the time it had left. One `end`, or no answer by the deadline: `date.ended {reason: "checkpoint"}` for both, no decision screen, nobody is told who. `CHECKPOINT_WINDOW_SEC` (default 10; 0 disables).

Matching rules: pair two queued users when each satisfies the other's preferences (age range, distance if both have coords, gender ↔ interestedIn, advanced filters only enforced for premium owners of the filter), not blocked, not currently matched with each other, and not paired with each other in the last 24 h. Queue order: premium first, then longest wait. People are served in that order; each is given the eligible partner with the highest compatibility score (estimated chance both say yes, from stated profile fields, each side's yes/no history and strikes, plus a small bonus for the partner's wait; `server/src/matchmaking/score.ts`). A configurable share of pairings (`MATCH_EXPLORE_RATE`, default 0.1) picks a random eligible partner instead. Scoring only ranks; it never overrides the rules above. Each participant's private answer is stored on the date (`decision_a`, `decision_b`) and is never sent to clients. A date counts toward the daily cap when `date.started` fires.

## 4. iOS architecture
- iOS 18.0+, Swift 6 language mode off (Swift 5 mode, strict concurrency "targeted"), SwiftUI, Observation (`@Observable`), async/await. No third-party deps except WebRTC via SPM `https://github.com/stasel/WebRTC` (product `WebRTC`).
- XcodeGen `project.yml`; bundle id `com.tempo.app`; portrait only; capabilities: Sign in with Apple, Push Notifications, In-App Purchase. Info.plist usage strings for camera, microphone, speech recognition, location when-in-use.
- `AppEnvironment` (@Observable, injected with `.environment`) holds all stores/services. Two modes chosen by build config/launch arg `-demo`: **demo** (all services mocked, runs in Simulator with no backend: fake partners, local camera preview or animated placeholder for remote video, scripted icebreakers) and **live** (real backend, base URL from Info.plist key `TempoAPIBaseURL`). Debug default = demo.
- Every service is a protocol with `Live…` and `Mock…` implementations: `APIClient`, `RealtimeSocket`, `VideoCallService` (exposes local/remote video as SwiftUI views `LocalVideoView()` / `RemoteVideoView()` that Features can drop in), `ModerationService`, `PurchaseService` (StoreKit 2), `PushService`, `LocationService`, `AuthService`.
- Stores (all `@MainActor @Observable`): `SessionStore` (auth, current user, onboarding), `DateStore` (the speed-date state machine, below), `MatchesStore` (matches, messages), `PremiumStore`, `ConfigStore`.
- `DateStore.phase` enum drives the entire date flow UI:
  `idle | searching | limitReached(resetsAt) | connecting(partner) | live | deciding(partner, deadline) | awaitingResult(partner) | matched(match) | noMatch(partner) | partnerLeft(partner) | ended(reason) | suspended(reason)`
  plus observable fields: `partner`, `endsAt`, `icebreaker` (question, speakerId, turnEndsAt, turnDuration, isMyTurn), `compatibleOnline`, `moderationWarning`, `isIcebreakerHidden`, `isMicMuted`, `isCameraOff`, `datesRemainingToday`.
  Intents: `goOnline()`, `goOffline()`, `leaveDate()`, `passTurn()`, `decide(_:)`, `continueToNext()`, `stopAfterThis()`, `toggleMic()`, `toggleCamera()`, `flipCamera()`, `report(reason:details:)`, `blockPartner()`.
- CORE must write `ios/CORE-API.md` listing every public type, property and method Features may use, with exact signatures. UI agents code ONLY against that file and the DesignSystem's `DESIGN-API.md`.
- Root navigation (`RootView` in `Tempo/Features/Root/`, owned by UI agent A): onboarding if `!onboardingComplete`; else a 3-tab shell (Tonight / Matches / You); the date flow is a `fullScreenCover` driven by `DateStore.phase != .idle`.

## 5. Design direction — "after hours"
Mood: a candle-lit bar at 11 pm, a film title sequence, a chess clock. Confident, warm, grown-up. Not bubbly, not pink-Tinder, no emoji confetti. Dark only.

### Tokens (asset catalog color names in brackets; DesignSystem exposes as `Color.tempo.*`)
- Background [ink] `#0D0A12`; raised surface [plum] `#18121F`; surface 2 [plumHi] `#231A2E`; hairline `white @ 8%`.
- Text: primary [ivory] `#F7F1E8`; secondary `ivory @ 64%`; tertiary `ivory @ 40%`.
- Ember gradient (the single brand accent, used sparingly on the primary action, the timer and key moments): `#FF4D5E → #FF7A45 → #FFC06A` at 135°.
- Yes [mint] `#63E6A9`; No [ash] `#8B8296`; warning [amber] `#FFB547`; danger `#FF4D5E`; premium [gold] `#F1C76E` with `#B8873A` shade.
- Radii: 12 (chips), 20 (cards), 32 (sheets), capsule for buttons. Spacing scale: 4, 8, 12, 16, 24, 32, 48.

### Type
- Display: system serif (New York) — `.system(size:, weight: .semibold, design: .serif)`, tight tracking (-0.5 to -1.5), used large (40–64 pt) for headlines, names, the match moment. Italic serif for single emphasized words.
- UI/body: SF Pro (default design), 17 body, 15 secondary, 13 caption with +0.6 tracking uppercase for eyebrow labels.
- Numerals (timers, counts): SF Pro Rounded, monospaced digits, medium weight.

### Signature elements
1. **The Pulse** (Tonight tab): a large breathing orb made with `MeshGradient` in ember colors over ink, slow drift; tap/hold-free single button "Go online". Around it, a faint ring with a live count: "23 compatible people online now". When searching, the orb contracts into a rotating thin ember arc and concentric ripples; partner found → orb blooms into the partner's photo, name in serif.
2. **The Clock** (in call): the date timer is a thin ember ring/arc hugging the top safe area as a capsule "3:12"; last 30 s it warms to amber and gently pulses; haptic tick at 10 s.
3. **The Turn Card** (icebreaker): frosted (ultraThinMaterial) card at the bottom third with the question in serif; a two-sided chess-clock bar: left half "You", right half partner's name; the active half fills with ember as the 30 s drains; big "Pass" pill when it is your turn; swipe down to tuck it away to a small chip, tap chip to bring back.
4. **The Verdict** (decision): video blurs and dims, partner's name in large serif, "Would you like to see Maya again?"; two large circular buttons — No (ash outline, ✕) left, Yes (ember fill, heart) right; 20 s ring countdown around the pair. Choice animates into a sealed envelope/"Sealed" state while waiting.
5. **The Match**: both photos slide together and overlap inside two interlocking ember rings, "It's mutual." in 56 pt serif italic, soft ember particle drift (Canvas/TimelineView, subtle), heavy haptic; buttons "Say hello" / "Keep dating".
6. **No match**: quiet, kind, quick: "Not this time." + "Next person in 3…" with a draining arc and "Stop for tonight".
- Video layout in call: remote video full-bleed with a soft bottom-and-top ink gradient for legibility; local video as a 96×136 rounded-20 PiP, draggable to corners; controls (mic, camera, flip, report flag, leave) in a single frosted capsule; Leave is always visible and never needs confirmation.
- Paywall: "Tempo Premium" — gold on ink, serif headline "Never run out of evenings.", three benefits with gold line icons (Unlimited dates / Dealbreaker filters / Front of the line), price, restore, terms. Tasteful, no dark patterns, easy close.
- Motion: springs (response 0.45, damping 0.82) by default; phase changes use matched geometry and blur-replace transitions; respect Reduce Motion (swap to fades) and Reduce Transparency. Haptics via `sensoryFeedback`.
- Accessibility: Dynamic Type up to accessibility2 without clipping, VoiceOver labels on every control, 4.5:1 contrast for text, 44 pt hit targets.
- Copy voice: short, warm, lightly witty, never cheesy. Sentence case. Examples: "Go online", "Finding someone good…", "Maya, 29 · 2 km away", "Not this time.", "It's mutual."

## 6. Quality bar
Production code: no TODO stubs in user-facing paths, no force unwraps on network data, errors surfaced to the user with retry, cancellation handled, no retain cycles in long-lived tasks, timers driven by server timestamps (`endsAt`), not local counters. Performance: no layout thrash in the call screen; animations with `TimelineView`/`Canvas` where continuous; images cached. Swift cannot be compiled in this workspace, so be conservative: use only APIs you are certain exist in iOS 18 SDK, keep generics simple, and double-check every initializer and call against your own definitions before finishing.
