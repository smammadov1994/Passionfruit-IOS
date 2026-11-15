# NOTES — integration pass

Scope: everything under `ios/`. The server was read, not changed. Nothing here has been compiled
(no Swift toolchain); see "Verification" for what was checked instead.

## What changed, by gap

1. **Verdict backdrop (Core).** The video connection now outlives the date by one screen.
   - `VideoCallService` gained `isCallAudioSilenced` and `setCallAudioSilenced(_:)`: both directions
     of audio off (local mic track and every remote audio track disabled), connection and video kept.
     `startCall` and `endCall` clear it. It never touches `isMicMuted`, the user's own toggle.
   - `DateStore`: on `date.ended{timer}` it calls the new `quietCallMedia()` (stop frame sampling,
     stop moderation and speech transcription, silence audio) instead of `finishCallMedia()`. The
     connection closes on `date.result`, on the result timeout, on `goOffline()`, on suspension and
     when the socket is lost for good. All other endings still close it at once.
   - `rtc.signal` is relayed for all of `isInDate` (was `isInCall`), so ICE keeps working while deciding.
   - `MockVideoCallService` mirrors it (stays `.connected`, tracks the flag). Two new tests:
     `testVideoStaysUpSilencedThroughTheDecision`, `testLeavingWhileDecidingClosesTheVideo`.
   - Features needed no change: `DateFlowStage.mountsVideo` already covered the Verdict.
2. **Permission issue while idle.** One presentation: `PermissionIssueCard` on Tonight (title,
   reason, Open Settings, Not now), now with a warning haptic and a VoiceOver announcement when it
   appears. Removed `DatePermissionNotice` and the "asking for access" dots from `DateFlowView`: the
   cover is closed whenever `permissionIssue` can be set, because only Tonight calls `goOnline()`.
3. **Clearing an answered basic.** The server accepts explicit `null` for `intention`, `children`,
   `religion`, `education`, `smoking`, `drinking` (`server/src/routes/me.ts`). `ProfileUpdate` gained
   `clearing: Set<ClearableProfileField>` with a hand-written `encode(to:)` that sends `null` for those;
   `MockAPIClient` does the same. Edit profile now lets every basic be deselected. Test:
   `testProfileUpdateSendsNullForClearedFields`.
4. **"Check again".** `SessionStore.refreshUser()` now returns whether the request succeeded and
   clears `suspension` when `GET /v1/me` shows the account in good standing. `isSuspended` ignores a
   pushed timed suspension whose `until` has passed. `SuspendedView` tells "couldn't check" apart
   from "still under review". Two new tests.
5. **Onboarding priming.** New `DateStore.requestMediaAccess()` (same permission service and order
   as `goOnline()`, no queue, does not set `permissionIssue`). `OnboardingFlow` calls it instead of
   `environment.permissions`.
6. **`ReportSheet`.** One initializer: `init(partnerName:onSubmit:onBlock:onLeave:)` with
   `onLeave: (() -> Void)? = nil`. Call sites: `DateFlowView` (passes `onLeave` only for a report
   opened during the live date), `ChatView`, `MatchCallView`, two previews.
7. **Welcome.** Sign in with Apple is now Apple's own `ASAuthorizationAppleIDButton` (white style,
   capsule radius, 56 pt) in a small `UIViewRepresentable`; Core still runs the authorization. In demo
   mode a "Demo mode" chip and the ember **Try the demo** button come first. Debug + live shows
   **Continue with a dev account** as a secondary button. Release shows Apple only.
8. **Blocked people list.** Skipped: the server only has `POST /v1/blocks`. See follow-ups.
9. **Routing contract.** Read end to end; no break found.
   - `TempoApp` → `RootView().tempoEnvironment(...)` → splash / welcome / suspended / onboarding / `TabShell`.
   - `DateStore.isActive` → `fullScreenCover { DateFlowView() }` on `TabShell`.
   - "Say hello" → `goOffline()` + `pendingRoute = .chat(matchId:)` → `TabShell.handleRoute` → `AppRouter.openChat`.
   - Incoming call → `IncomingCallBanner` → accept opens the chat → `MatchCallView` cover on that chat.
   - `limitReached` → `DateLimitView` → `PaywallView` sheet inside the cover.
   - Push tap → `AppDelegate` → `handleNotificationTap(matchId:)` → `pendingRoute`. The server puts
     `matchId` at the top level of the APNs payload (`server/src/push/apns.ts`), which is what the app reads.
10. **`project.yml`.** The single `Tempo` source path covers every folder; StoreKit and entitlements
    paths are right. Added `DESIGN-API.md` to `fileGroups`, and
    `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: NO` (the `mint` color set would
    otherwise collide with SwiftUI's `Color.mint`). New `ios/Tools/check_project.py`: 0 duplicate
    file names, 0 duplicate top-level type names, all paths exist.
11. **`ios/README.md`** rewritten: numbered steps, and a "First compile" table of the likeliest fixes.

`CORE-API.md` is updated for all of the above. `DESIGN-API.md` needed no change (the design system
was not touched).

## Verification

| Check | Result |
|---|---|
| tree-sitter parse, `ios/Tempo` + `ios/TempoTests` (101 files) | 0 parse errors |
| `uib_verify.py` (DateFlow, Call) | 0 problems |
| `verify.js` (the other eight feature folders) | 0 problems; 33 switches exhaustive |
| `builders.js` | 149 declarations, 0 problems |
| `verify.js` + `builders.js` widened to all ten feature folders | builders 221 declarations, 0 problems; verify 2 findings, both false: `ScenePhase` cases `.background` / `.inactive` in `DateFlowView.swift` are SDK cases it does not know |
| `uib_verify.py` widened to all ten feature folders | 15 findings, all false: SDK methods that share a name with a project method (`.move(edge:)`, `.accessibilityValue(_:)`, `Array.insert(_:at:)`, `Task.cancel()`, `Double.rounded()`), `.some` optional patterns, and `if let match = store.match(id:)` |
| `calls.py` | 3 findings, all false: `SegmentedPicker(selection:labels:)` is declared in a constrained extension |
| `check_project.py` | 0 problems |
| `project.yml`, `Tempo.storekit`, `Localizable.xcstrings`, `icebreakers.json` | parse as YAML / JSON |

The new unit tests were written but, like everything else, not run.

## Server follow-ups (not done; the server was read-only)

- **Blocked people.** Add `GET /v1/blocks` (list with first name and photo) and
  `DELETE /v1/blocks/:userId`. Until then the app cannot show or undo blocks.
- **Expose `suspended` in `User`.** The client infers "pending review" from `strikes >= 3`
  (`User.strikesToSuspend`), but the server's threshold is the env var `STRIKES_TO_SUSPEND`. If it is
  not 3, the two disagree. With the flag exposed, "Check again" would be exact.
- **Clearing location.** `lat`/`lng` accept `null` on the server, but the app has no "remove my
  location" control and `ProfileUpdate.clearing` does not cover them.

## Left open

- **Unmoderated video during the decision.** By request, frame sampling stops when the timer ends
  while both cameras keep sending for up to the decision window plus the result grace (about 20 s,
  at most 32 s). The partner sees it blurred (radius 24) under 55% ink. If that is not acceptable,
  keep `video.startFrameSampling` running in `quietCallMedia()`; it is a two-line change.
- **Microphone indicator.** The audio session stays active while deciding (tracks are disabled, so
  silence is sent and nothing is played), so iOS keeps showing the orange dot until the result.
- **Partner leaves during the decision.** Their video freezes or goes dark behind the Verdict until
  the result arrives; nothing tells the user why. Cosmetic.
- **Incoming-call banner under a sheet.** If the paywall sheet is open on the shell when a match
  calls, the banner is behind it until the sheet is closed.
- **`MatchCallView.permissionLayer`** can only show when "call again" is tapped from the ended
  screen; the idle case is the shell's alert. The two cannot show together. Left as is.
- **Moderation start race (already there).** `moderation.start` runs in a detached task from
  `handleStarted`; a date that ends in the same run-loop turn could start it after `stop()`. Not
  reachable with real date lengths.
- **Local StoreKit against the dev server** has not been tried; whether `/v1/iap/verify` accepts an
  Xcode-signed test transaction depends on `ALLOW_DEV_IAP`.
- **Date-flow strings are plain literals**, not `String(localized:)` (agent B's choice). They still
  land in the string catalog through `Text`, but strings passed as `String` do not.
- Everything in `NOTES-core.md` section 3 (team, APNs, TURN, privacy manifest, real API URL) still stands.
