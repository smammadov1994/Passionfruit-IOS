# Handoff: Tempo (live video speed dating, iOS)

You are picking up a project that was written entirely on Linux with no Swift compiler. **The iOS app has never been compiled.** Your first job is to get it building and running in the iOS Simulator in demo mode, then work down the list below.

## What this is
An iOS app where a user goes online, is paired with a compatible person who is online right now, has a timed 1:1 video date, then both privately choose yes/no. Mutual yes = match (chat + video call again). Otherwise the next person. An optional "chess clock" icebreaker card gives each person 30 s turns on a shared question. Free: 5 dates/day. Premium $14.99/month: unlimited dates, dealbreaker filters, queue priority. "Tempo" is a working name held in one constant (`Brand.name`).

## Repo map (root = `tempo/`)
| Path | What |
|---|---|
| `SPEC.md` | Product rules, REST + WebSocket wire protocol, iOS architecture. Source of truth. Section 5 (visual direction) is superseded. |
| `DESIGN-V2.md` | Current visual direction ("Daylight": white, serif headlines, outlined icons, one vermilion accent, pastel tiles). Light mode only. |
| `REVIEW.md` | Independent review: 17 defects already fixed, **18 uncertain spots with file/line and suggested fix** (read section b before the first build), production-readiness verdict. |
| `NOTES-*.md` | Per-agent decisions and risks (backend, core, design, ui-a, ui-b, integration, reskin). |
| `ios/` | SwiftUI app, iOS 18+, Swift 5 mode, XcodeGen (`project.yml`), one SPM dep: `stasel/WebRTC`. 101 Swift files, ~24.8k lines. |
| `ios/CORE-API.md`, `ios/DESIGN-API.md` | Public surface of the Core layer and the design system. Keep them accurate when you change either. |
| `ios/Tempo/App` | `TempoApp`, `AppEnvironment` (`.demo()` / `.live()`), AppDelegate. |
| `ios/Tempo/Core` | Models, Networking (`APIClient`, `RealtimeSocket`), Services (video, moderation, purchases, push, location, auth), Stores (`SessionStore`, `DateStore`, `MatchesStore`, `PremiumStore`, `ConfigStore`). Every service has a Live and a Mock implementation. |
| `ios/Tempo/DesignSystem` | Tokens and all reusable components. |
| `ios/Tempo/Features` | Screens: Root, Onboarding, Tonight, DateFlow, Call, Matches, Chat, You, Paywall, Shared. |
| `ios/TempoTests` | XCTest unit tests (never run). |
| `ios/Tools` | `check_project.py` (duplicate names / project coverage), `generate_art.py` (watercolor images and the app icon). |
| `server/` | Node 22 + TypeScript backend (Fastify, ws, zod). `npx tsc --noEmit` clean, `npx vitest run` = 222 passing. `npm run sim` drives fake clients. |
| `preview/index.html` | Single-file tappable web prototype in the current design. Use it as the visual reference for every screen. |
| `marketing/` | Remotion project with five looping watercolor animations for a landing page (GIF + MP4 in `out/`). Not part of the app. |

## Task 1 — first build (do this now)
1. `brew install xcodegen` (if missing), then `cd ios && xcodegen`.
2. Build for a simulator from the command line so errors are greppable:
   `xcodebuild -project Tempo.xcodeproj -scheme Tempo -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tee build.log` (pick any installed iOS 18+ simulator).
3. Fix compile errors in a loop until it builds. Expect a moderate number of small ones. Likeliest areas, in order: `Core/Services/LiveVideoCallService.swift` (WebRTC API names), strict-concurrency / `@MainActor` delegate conformances, SwiftUI API signatures in `DesignSystem` (transitions, gestures, `FlowLayout` call syntax), `PhotosPicker` usage in Onboarding, the hand-written `Tempo.storekit` and scheme settings in `project.yml`. `REVIEW.md` section (b) has exact files and lines.
4. Rules while fixing: keep fixes minimal and local; do not redesign; keep the wire protocol exactly as in `SPEC.md` section 3 (the server depends on it); re-run `xcodegen` after adding/moving files; keep `CORE-API.md` / `DESIGN-API.md` in sync.
5. Run in the Simulator. The scheme passes `-demo`, so everything is mocked: tap **Try the demo**, finish onboarding, tap the orb on **Tonight**. Demo dates last 45 s with 10 s turns.
6. Walk every screen and compare with `preview/index.html` and `DESIGN-V2.md`. Fix visual regressions (clipping, contrast, dark-theme leftovers, layout at small sizes and large Dynamic Type).
7. Run the unit tests (`xcodebuild test ...`) and fix failures. `DateStoreTests` use short real sleeps and may be flaky.

## Task 2 — live mode on two real devices
1. `cd server && npm install && cp .env.example .env`, set `ALLOW_DEV_AUTH=1`, `npm run dev`.
2. Point the app at it (`TempoAPIBaseURL` in `project.yml`, remove `-demo`; see `ios/README.md` section 3).
3. Run a full date between two phones on the same network: pairing, video both ways, timer, icebreaker turns and Pass, yes/no, match, chat, post-match call, leave early, report/block.
4. Specifically verify: audio session behaviour after a call ends; speech transcription (`AVAudioEngine`) coexisting with WebRTC's microphone (if it fights, fall back to frames-only moderation and note it); camera released on every exit path; reconnect after backgrounding.

## Task 3 — production gaps (not started)
- Video nudity moderation is a **mock** on the server. Choose a vendor and implement the one marked mapping function in the server's HTTP moderation provider. The text classifier for sexual language is real.
- Sign in with Apple token revocation on account deletion (App Store requirement): needs server + client work.
- Real credentials: Apple team/bundle id, Sign in with Apple, APNs `.p8`, App Store Connect product `tempo.premium.monthly`, Apple Root CA G3 file for receipt verification, TURN servers, Postgres (`DATABASE_URL`), blob storage, hosting.
- Postgres store only tested against embedded Postgres (PGlite); Dockerfile never built; live queue state is in memory (README explains the Redis move for multi-instance).
- Legal/support URLs are placeholders (`LegalLinks`). `PrivacyInfo.xcprivacy` needs owner review.
- No "blocked people" list (server has no list endpoint).
- Known small issue: if support lifts a suspension without resetting strikes, the client still shows suspended.

## Optional design follow-ups the owner mentioned
- He likes the watercolor look from `marketing/` (soft washes in blush, sage, butter, lilac, vermilion on white paper). Candidate places in the app: Welcome screen background, behind the Go online button on Tonight, the match screen. Implement natively (Canvas / blurred shapes), subtle, respecting Reduce Motion. Ask before adding.
- A landing page using the `marketing/out` MP4s does not exist yet.

## Product decisions already made (owner can change any)
4-minute dates · 30 s turns · 20 s to answer yes/no, no answer = no · leaving early = no from the leaver · after a match: text chat + video call again · free 5 dates/day, Premium $14.99/month · nudity ends the call at once + strike; sexual language warns once then ends + strike; 3 strikes suspends pending review · 18+ only · "singles online" push at most once per 4 h, 09:00–23:00 local · frame moderation keeps sampling during the yes/no screen (audio is muted there).

## Working preferences of the owner
Short, numbered, do-this-next instructions. Show him the app running as early as possible. Design taste: clean white, editorial serif, nice icons, restrained colour.
