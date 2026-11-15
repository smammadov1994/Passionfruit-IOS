# NOTES-core — iOS non-UI layer (agent CORE)

Scope: `ios/project.yml`, `ios/Tempo/App`, `ios/Tempo/Core`, `ios/TempoTests`, `ios/Tempo.storekit`,
`ios/Tempo/Resources/{Localizable.xcstrings, icebreakers.json}`, `ios/README.md`, `ios/CORE-API.md`.

Nothing here has been compiled: there is no Swift toolchain in the workspace. Every `.swift` file parses
cleanly with tree-sitter-swift, which catches syntax errors only, not type errors.

## 1. Decisions the spec did not cover

Wire protocol (backend should confirm each one):
- **`PUT /v1/me` sends `onboardingComplete: true`** at the end of onboarding. If the server computes the
  flag itself it can ignore the field; if it rejects unknown fields this call fails. If the returned
  user still has `onboardingComplete == false`, the app shows an error and stays in onboarding.
- **Nil optional fields are omitted, never sent as `null`.** So clearing an advanced filter in
  `PUT /v1/me/preferences` relies on the server treating the body as a full replacement.
- **`User` decoding is lenient**: `birthdate`, `gender`, `bio`, `city`, `preferences` etc. may be null or
  missing for an account that has not onboarded. `User.gender` is therefore optional in Swift.
- **`iceServers[].urls`** is accepted as an array (spec) or a single string.
- **Unknown server frame types** decode to `.unknown(type:)` and are ignored. A known type with a
  malformed payload is dropped.
- **Socket "connected"** is declared on the first frame received (the client sends `ping` right after
  opening, so normally the `pong`). No `URLSessionWebSocketDelegate` is used.
- **Duplicate `queue.join`** can happen around a reconnect; the server should treat it as idempotent.
- **`date.matched` while not searching** (user went offline in the same instant) is answered with `date.leave`.
- **Push payloads are not in the spec.** A tapped notification with a string `matchId` in `userInfo`
  routes to that chat; anything else routes to Tonight (`AppEnvironment.pendingRoute`).
- **Post-match calls** use `config.iceServers` (there is no `iceServers` on `call.accept`). The inviter is
  the WebRTC caller and creates the offer after `call.accept`. Outgoing rings give up after 30 s with
  `call.end`. Incoming invites during a date, or during another call, are declined automatically.
  Calls are not moderated (the moderation routes take a `dateId`).
- **403 with an error code containing "suspend"** maps to `TempoError.suspended`.
- **Relative photo URLs** (e.g. `/uploads/a.jpg`) are resolved against the API base URL.

Client behaviour:
- **Auto re-queue** after a 3 s interstitial happens for `noMatch`, `partnerLeft`, `ended(.youLeft)` and
  `ended(.disconnect)` when the partner's side dropped. It does not happen after `ended(.moderation)`,
  after a match, or when this phone lost the server.
- **Leaving is optimistic**: `leaveDate()` shows `ended(.youLeft)` at once and ignores the server's echo.
- **Safety-net timers** (never the source of truth): 20 s for `date.started` after pairing (then
  `date.leave` and re-queue); 12 s after the decision deadline for `date.result` (then "no match"); 12 s
  for a dropped socket to return during a date; 8 s for failed video to recover (then `date.leave`).
  All in `DateStoreTiming`.
- **Clock skew**: at `date.started`, `startsAt` is taken as "server now". If it differs from the device
  clock by more than 5 s, all timestamps of that date are shifted by the difference. Smaller differences
  are left alone. This assumes the server sends `date.started` at `startsAt`.
- **Speech moderation is on-device only.** Where the recogniser does not support on-device recognition
  for the locale, speech is not transcribed at all (frames are still checked) rather than sending audio
  to Apple's servers. Reverse this in `SpeechTranscriber.isSupported` if coverage matters more.
- **Transcript chunks** are the newly recognised words, flushed every 4 s. Recognition requests are
  rotated every 50 s. A REST `action` of `warn`/`end` and the socket `moderation.action` for the same
  incident are shown once (3 s de-duplication per category).
- **Frame samples**: longest side 384 px, JPEG quality 0.6, skipped while the camera is toggled off and
  while a previous upload is still in flight.
- **Mic and camera toggles persist** across dates in a session (they are not reset per date). Post-match
  calls start unmuted with the camera on.
- **Demo mode** persists the demo account between launches (UserDefaults + a separate Keychain service).
  Demo dates are 45 s with 10 s turns. Demo uploads are written to the caches directory.
- **Debug builds default to demo** and offer dev sign-in in live mode; Release builds hide dev sign-in.
- **`UIBackgroundModes`**: `audio` (a date keeps its audio if the app is backgrounded briefly) and
  `remote-notification`. App Review may ask about `audio`; remove it in `project.yml` if unwanted.
- **Brand name**: Swift uses `Brand.name`; Info.plist strings use the build setting `TEMPO_BRAND_NAME`.
  Bundle ids, the Keychain service and the product id still contain "tempo".
- Added beyond the spec's list: `MediaPermissions` (camera/mic permission behind a protocol),
  `DateStore.debugSetPhase` and `MatchesStore.debugSetCallState` (previews only), `ServerClock`.

## 2. Riskiest spots (could not verify without a compiler or a device)

1. **`LiveVideoCallService.swift` against the stasel/WebRTC binary** (pinned `from: 125.0.0`). Written
   from memory of the Objective-C headers. Most likely to need a touch-up:
   - `RTCAudioSessionConfiguration.webRTC()`, `.setWebRTC(_:)`, and `RTCAudioSession.setConfiguration(_:active:)`.
   - `RTCPeerConnection.add(_:completionHandler:)` for ICE candidates, and the closure parameter types
     written out explicitly for `offer(for:)`, `answer(for:)`, `setLocalDescription`, `setRemoteDescription`.
   - `RTCVideoRotation` cases `._90/._180/._270`; `RTCCVPixelBuffer.pixelBuffer`.
   - `RTCMTLVideoView` on the Simulator.
   Demo mode never instantiates this class, so a problem here only blocks live mode at run time, but
   the file must still compile for any build.
2. **Speech recognition while WebRTC owns the microphone** (`SpeechTranscriber`). A second
   `AVAudioEngine` input tap next to WebRTC's voice-processing unit usually works but can return silence
   or fail to start on some devices; failure is handled (frames-only moderation), but it needs a
   real-device test. `installTap` can raise an Objective-C exception on a format mismatch; the format is
   taken from the input node and checked for a zero sample rate, which is the known trigger.
3. **`@Observable` + `@MainActor` + init ordering** in the stores, and `nonisolated` delegate methods on
   `@MainActor` NSObject subclasses (`LiveAuthService`, `LiveLocationService`, `AppDelegate`). The
   patterns are standard, but strict-concurrency diagnostics differ between Xcode 16.0 and later
   versions; expect warnings, possibly an error to adjust.
4. **`UNUserNotificationCenterDelegate` completion-handler signatures** in `AppDelegate`. If the SDK's
   Swift signature differs (e.g. extra attributes), the methods silently stop being the delegate
   callbacks (a "nearly matches" warning). Check for that warning.
5. **`Tempo.storekit`** was hand-written (format version 3). If Xcode refuses it, create a new StoreKit
   configuration with one auto-renewable subscription `tempo.premium.monthly`, $14.99, 1 month.
6. **XcodeGen details**: `storeKitConfiguration`, `commandLineArguments`, generated Info.plist and
   entitlements were written from memory of the XcodeGen spec, and validated only as YAML.
   `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` assumes DESIGN ships an `AppIcon` set.
7. **Timing-based unit tests** (`DateStoreTests`) use short real sleeps (50 ms timers, polling up to
   3–12 s). `testScriptedDemoRunsAWholeDate` takes about 5 s. They may be flaky on a loaded CI machine.
8. **`TempoApp.swift` references `RootView()`**, which UI agent A must create at
   `Tempo/Features/Root/RootView.swift`. Until then the app target does not compile.

## 3. Needs real credentials or infrastructure

- **Apple Developer team** (`DEVELOPMENT_TEAM` is empty in `project.yml`) for device builds.
- **Sign in with Apple**: capability on the App ID `com.tempo.app`; the server must verify the identity token.
- **Push**: APNs key on the server; `aps-environment` is `development` in the entitlements and must be
  `production` for TestFlight/App Store builds.
- **In-App Purchase**: product `tempo.premium.monthly` in App Store Connect, and the server's App Store
  Server API credentials for `/v1/iap/verify`. Local testing uses `Tempo.storekit`.
- **TURN server** in `iceServers` (config and `date.matched`). With STUN only, many mobile-network pairs
  will not connect.
- **API base URL** for Release: `TEMPO_API_BASE_URL` in `project.yml` is the placeholder
  `https://api.tempo.example`.
- **Privacy**: `PrivacyInfo.xcprivacy` and App Store privacy answers (camera frames and speech
  transcripts leave the device for moderation) are not written yet.

## 4. Reconciled with NOTES-backend.md (second pass)

- `tzOffsetMinutes` is sent on `PUT /v1/me` at sign-in, on foreground (only when changed) and with onboarding.
- `User.isSuspended` is true at `strikes >= 3` or a future `suspendedUntil`. Caveat: the server keeps a
  separate `suspended` flag it does not expose; if support lifts a suspension without resetting strikes,
  the client still shows suspended until strikes drop below 3. Exposing `suspended` in `User` would be cleaner.
- `account.suspended` (replayed on every connect) only takes over the screen when the date flow is open.
- Socket close codes 4000 (replaced), 4002 (account deleted) and 1008 (unauthorized) stop reconnecting;
  the socket reconnects on the next foreground or `goOnline()`. Read via `URLSessionWebSocketTask.closeCode.rawValue`
  (unverified that custom 4xxx codes survive the enum import; if not, the client just reconnects as before).
- Socket `error` codes: date races are silent; `in_call` / `onboarding_incomplete` / `underage` stop the
  search; call errors end the outgoing call.
- `GET /v1/config` is sent with the token when there is one and reloaded after sign-in and before each
  post-match call (TURN credentials). Post-match calls are moderated with `dateId = "call:" + matchId`.
- Purchases carry `appAccountToken` = user id (when it is a UUID).
- Photo upload no longer re-PUTs `photoUrls` (the server appends); onboarding always sends `photoUrls`.
- A replayed `date.started` for a date the app no longer knows is answered with `date.leave`.
- Not done (would need new public API): clearing optional profile fields with `null` on `PUT /v1/me`.
