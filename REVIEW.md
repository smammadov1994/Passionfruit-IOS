# REVIEW — Tempo iOS, independent compile and production-readiness pass

Scope: every Swift file under `ios/Tempo` and `ios/TempoTests` (101 files, about 24,600 lines), `project.yml`,
the asset catalog, `Tempo.storekit`, the entitlements, and the server sources for the wire protocol.
There is still no Swift compiler here: nothing below has been built or run.

**Bottom line of the "act as the compiler" pass: I found no line that I am sure `xcodebuild` rejects.**
The defects I found and fixed are runtime and App Review defects. Section (b) lists the places where a
first build is most likely to complain, with the fix to apply.

Checks after the fixes, all clean:

| Check | Result |
|---|---|
| tree-sitter parse (`.tempo-tools/check.js`, 101 files) | 0 parse errors |
| `.tempo-tools/uib_verify.py` | 0 problems (3 notes: `SwiftUI`, `Foundation`, `UIKit` are module names) |
| `.tempo-ui-a/verify.js` | 0 problems, 35 switches exhaustive |
| `.tempo-ui-a/builders.js` | 149 declarations, 0 problems |
| `builders.js` widened to all of `ios/Tempo` (my copy) | 406 declarations, 0 problems |
| `ios/Tools/check_project.py` | 0 problems |
| `project.yml`, `PrivacyInfo.xcprivacy`, all JSON resources | parse |

What was compared against a source of truth:

- **Wire protocol**: every REST route and socket frame in `server/src` (zod schemas, `ServerMessage` union,
  serializers, close codes, error codes, APNs payload) against Core's models and messages, field by field.
  **No mismatch found.** Optional and null handling, date format, enum raw values, `call:<matchId>` ids and
  the `PUT /v1/me/preferences` "absent means cleared" rule all line up.
- **WebRTC**: the Objective-C headers of `RTCPeerConnection`, `RTCPeerConnectionFactory`,
  `RTCCameraVideoCapturer`, `RTCAudioSession(+Configuration)`, `RTCIceCandidate`, `RTCIceServer`,
  `RTCMediaConstraints`, `RTCVideoRenderer`, `RTCMTLVideoView`, `RTCVideoTrack`, `RTCVideoFrame`,
  `RTCRtpTransceiver`, fetched from `webrtc-sdk/webrtc` master. Every selector used in
  `LiveVideoCallService.swift` exists with the argument types the Swift code assumes. That is the upstream
  tree, not the exact M125 binary that `stasel/WebRTC` ships.

---

## (a) Defects found and fixed

17 in total: 5 high, 7 medium, 5 low.

### High

1. **No scene manifest in the generated Info.plist.** `ios/project.yml`
   The SwiftUI `App` lifecycle is scene-based; without `UIApplicationSceneManifest` the app can launch to
   an empty window. Added `UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: false }`.
   I am not certain the missing key was fatal on iOS 18; adding it is harmless either way.

2. **Every video surface leaked and kept rendering.**
   `ios/Tempo/Core/Services/LiveVideoCallService.swift`, `ios/Tempo/Core/Services/VideoViews.swift`
   A video track holds a strong reference to each renderer added to it, and nothing ever removed one. Each
   `LocalVideoView` / `RemoteVideoView` that SwiftUI created left an `RTCMTLVideoView` attached to the
   long-lived local track, drawing every camera frame for the rest of the session.
   Fix: `VideoSurface.dismantleUIView` calls the new `ReleasableVideoSurface.releaseVideoSurface()`, and
   the service detaches the renderer from its track there.

3. **Audio session activation count went negative.**
   `ios/Tempo/Core/Services/LiveVideoCallService.swift`
   `endCall()` runs on many paths where no call was started (going offline from the search, a second
   `finishCallMedia()` after a result). Each one called `RTCAudioSession.setActive(false)`, which
   decrements WebRTC's activation count regardless. Once it is below zero the session is no longer
   deactivated after later calls, so other apps' audio stays interrupted. Confirmed against
   `RTCAudioSession.mm`. Fix: activation is a separate, counted step and deactivation only runs when this
   service activated the session.

4. **Reconnect loop on a refused token.**
   `ios/Tempo/Core/Networking/LiveRealtimeSocket.swift`
   The server answers a bad token with a plain HTTP 401 before the WebSocket upgrade, so there is no close
   code and the client retried forever. Fix: a 401 or 403 handshake response is final.

5. **Messages missed while the socket was down never appeared.**
   `ios/Tempo/Core/Stores/MatchesStore.swift`, `ios/Tempo/App/AppEnvironment.swift`
   `openChat` loaded a thread once per session and nothing listened for reconnects. A message delivered as
   a push (app in the background) updated the matches list on return but not the cached thread, so tapping
   the notification opened a chat without the new message. Fix: `openChat` always fetches the newest page;
   new `resync()` reloads matches and the open chat on socket reconnect and on foreground.

### Medium

6. **A live date with no `date.ended` was a dead end.** `ios/Tempo/Core/Stores/DateStore.swift`
   If the server lost the date (restart), the phase stayed `.live` at 0:00 until the user left. Added a
   safety net: `DateStoreTiming.liveOverrunGrace` (15 s) after the server's end time the date ends as
   `.ended(.disconnect)` with no countdown.

7. **Camera could start after the search had ended.** `ios/Tempo/Core/Stores/DateStore.swift`
   `requeue()` started capture in an unstructured task. When `queue.limit` or `goOffline()` was handled
   first, `stopLocalCapture()` was a no-op and the camera then came on and stayed on. Always the case on
   the demo's limit screen. The task now checks that the phase still wants the camera.

8. **Camera stayed on behind screens with no video.** `ios/Tempo/Core/Stores/DateStore.swift`
   On the Match screen, after a safety stop and after a lost connection the flow waits for the user
   indefinitely with the camera indicator lit. Capture is now released there; re-queueing starts it again.

9. **No privacy manifest.** `ios/Tempo/Resources/PrivacyInfo.xcprivacy` (new)
   The app uses `UserDefaults` (a required-reason API), which App Store Connect rejects without a
   declaration. The file declares `CA92.1`, no tracking, and the data types the code sends to the server.
   The data-type list is my reading of the code and needs the owner's sign-off (see section c).

10. **No way to reach support in the app.** `ios/Tempo/Features/You/YouView.swift`
    `LegalLinks.support` existed but was never shown; Guideline 1.2 expects contact information in an app
    with user-generated content. Added a "Help and support" row to Account.

11. **A paused account could not delete itself.** `ios/Tempo/Features/Root/SuspendedView.swift`
    The paused screen replaces the whole app and only offered Sign out. Added "Delete account", which
    presents the existing `DeleteAccountView`.

12. **A match made after closing the flow was dropped.** `ios/Tempo/Core/Stores/DateStore.swift`
    Sealing a Yes and then closing the flow cleared the date id, so the later `date.result{match}` was
    ignored and the match only appeared after the next reload. It is now handed to `MatchesStore`.

### Low

13. **Rejected Apple sign-in showed "Please sign in again."**
    `ios/Tempo/Core/Networking/LiveAPIClient.swift` Every 401 was mapped to `.notAuthenticated`; the
    server's `invalid_identity_token` message is now kept.

14. **Messages over 2000 characters failed forever.** `ios/Tempo/Features/Chat/ChatView.swift`
    The server limit is 2000 and the composer had none, so the row stayed "Not sent" on every retry. The
    draft is capped.

15. **Chat memory grew without bound.** `ios/Tempo/Core/Stores/MatchesStore.swift`
    A condition meant to keep rows only for opened chats was always true, and threads were never trimmed.
    Unopened chats keep no rows now, and `closeChat` trims a thread to the newest page.

16. **Broadcast streams were never finished.** `ios/Tempo/Core/Networking/RealtimeSocket.swift`
    `Broadcaster` now finishes its continuations in `deinit`, so listener tasks end with their source
    (matters for previews and tests, which create many environments).

17. **View members named like accessibility modifiers.**
    `ios/Tempo/DesignSystem/Signature/PulseOrb.swift`, `ios/Tempo/DesignSystem/Primitives/IconCircleButton.swift`,
    `ios/Tempo/Features/Matches/MatchesView.swift`, `ios/Tempo/Features/Root/TabShell.swift`
    `private var accessibilityLabel / accessibilityValue / accessibilityHint` sat next to the `View`
    modifiers of the same name. I expect that to resolve, but it is an overload set the type checker has to
    untangle; renamed to `spokenLabel / spokenValue / spokenHint`.

`ios/CORE-API.md` is updated for items 5, 6, 8 and 15.

---

## (b) Not resolved with certainty: where a first build is most likely to complain

None of these is a known error. Each is a place where I could not get to certainty without a compiler.

| # | Where | Risk | If Xcode reports it |
|---|---|---|---|
| 1 | `Tempo/DesignSystem/Tokens/TempoMotion.swift:8` and `:26` | `TempoAnimations` has a property `standard` and a method `standard(reduceMotion:)`. Same shape as `Array.first` / `first(where:)`, so it should resolve. | "Ambiguous use of 'standard'": rename the method to `standardOrFade(reduceMotion:)` and replace `.standard(reduceMotion:` across the project. |
| 2 | Feature views built with the implicit memberwise init that also have `@State private var x = …`, e.g. `Features/Chat/ChatView.swift` `ChatScreen(match:)`, `Features/You/EditProfileView.swift` `EditProfileLocation(city:)` | Relies on the rule that a private wrapped property with an initial value is left out of the memberwise init. Standard SwiftUI practice. I scanned every struct: none has a plain (unwrapped) private stored `var`. | "'X' initializer is inaccessible due to 'private' protection level": add an explicit `init` to that struct. |
| 3 | `Tempo/Core/Networking/RealtimeSocket.swift:41` | New `deinit` reads main-actor state from a nonisolated context. Allowed for Sendable state; may warn. | Delete the `deinit` (it only matters for previews and tests). |
| 4 | `Tempo/Core/Services/VideoViews.swift:48` | New `static func dismantleUIView(_:coordinator: Void)`. | If the witness does not match, write the parameter as `coordinator: ()`. |
| 5 | `Tempo/Core/Services/LiveVideoCallService.swift:558`, `:706`, `:715` | `connection.add(candidate) { }`, `RTCAudioSessionConfiguration.webRTC()`, `try session.setConfiguration(configuration)`: Swift names derived from the headers by rule, not seen in a generated interface. | Open the generated interface of `WebRTC` in Xcode (jump to definition) and use the name shown. The header selectors are `addIceCandidate:completionHandler:`, `+webRTCConfiguration`, `setConfiguration:error:`. |
| 6 | `Tempo/Core/Services/LiveVideoCallService.swift:709` | `.allowBluetooth` is deprecated in the iOS 26 SDK. | Warning only; rename to `.allowBluetoothHFP` when building with Xcode 26. |
| 7 | `Tempo/App/AppDelegate.swift:26`, `:34`; `Tempo/Core/Services/AuthService.swift:78`, `:91`, `:104`; `Tempo/Core/Services/LocationService.swift` delegate extension | `nonisolated` delegate methods on `@MainActor` classes. Diagnostics differ between Xcode 16.0, 16.x and 26. | A "nearly matches" warning means the method is not the callback: copy the signature from the fix-it. An isolation error: mark the conformance `@preconcurrency`. |
| 8 | `Tempo/Core/Networking/LiveRealtimeSocket.swift:133` | Whether custom close codes (4000, 4002) survive `closeCode.rawValue`. If not, the socket just reconnects. | Log the value on a device once. |
| 9 | `Tempo/Core/Networking/LiveRealtimeSocket.swift:136` | Whether `task.response` carries the 401 after a failed handshake. If not, behaviour is as before my fix. | Log it once against a bad token; if nil, read the status from the `URLError`'s `userInfo`. |
| 10 | `Tempo/Core/Services/PurchaseService.swift:75` | `Product.purchase(options:)` is superseded by `purchase(confirmIn:options:)` in newer SDKs. | Deprecation warning only on iOS. |
| 11 | `Tempo/Core/Services/LocationService.swift:63` | `CLGeocoder.reverseGeocodeLocation` is deprecated in the iOS 26 SDK. | Warning only. |
| 12 | `Tempo/Features/Chat/ChatMessageList.swift:47` | `NotificationCenter.default.publisher(for:)` with only `import SwiftUI`. | Add `import Combine` to the file. |
| 13 | `Tempo/DesignSystem/Primitives/AvatarView.swift:62` | `@unknown default` inside a `ViewBuilder` switch over `AsyncImagePhase` (Apple's documented pattern). | Replace with plain `default`. |
| 14 | `Tempo.storekit` | Hand-written (format 3.0). | If Xcode refuses it, create a StoreKit configuration with one auto-renewable subscription `tempo.premium.monthly`, 1 month, $14.99. |
| 15 | `Tempo/Resources/PrivacyInfo.xcprivacy` | Needs XcodeGen 2.39 or later to be treated as a resource. | If it is missing from the built app, add it under `resources` for the target in `project.yml`. |
| 16 | `Tempo/Core/Services/SpeechTranscriber.swift:76` | Run time, not compile time: a second `AVAudioEngine` input tap while WebRTC owns the microphone can raise an Objective-C exception or deliver silence. | Test on a device. If it fails, feed the recognizer from WebRTC's audio (an `RTCAudioDevice` or audio-buffer tap) instead of a second engine. |
| 17 | `Tempo/Core/Stores/DateStore.swift:992` | New `liveOverrunExpired`: with a device clock 5 to 15 s ahead of the server the net could fire while the server is still about to send `date.ended`. | Raise `DateStoreTiming.liveOverrunGrace`. |
| 18 | `TempoTests/DateStoreTests.swift` | Not run. Timing-based (50 ms timers, polling). My changes add no new waits; `testScriptedDemoRunsAWholeDate` now also exercises the camera release on a match. | Run them first; they are the fastest check of the state machine. |

Strict-concurrency warnings are certain (Swift 5 mode, `targeted`); I did not try to remove them. Do
**not** switch the target to Swift 6 language mode without revisiting `LiveVideoCallService`: closures
handed to WebRTC are formed in main-actor code and are called on WebRTC's threads, which Swift 6's
runtime isolation checks turn into a crash.

---

## (c) Production-readiness verdict

**Not ready to submit. Ready for a first build.** The code reads as careful and consistent: the state
machine has an exit from every phase, timers come from server timestamps, the wire protocol matches the
server, and report, block, account deletion, restore purchases, the age gate and the permission strings
are all present. But it has never been compiled, never run on a device and never completed a live date.
Expect a day or two of compiler fixes before anything else can be judged.

What stands between this and an App Store submission, in order:

1. **Build it.** Resolve whatever section (b) turns into. Run the unit tests.
2. **A real date on two phones.** WebRTC connect, both roles, mobile data on both sides (needs TURN; with
   STUN only many pairs will not connect), audio routing, backgrounding mid-date, reconnect mid-date.
   None of `LiveVideoCallService` has executed once.
3. **Speech moderation next to WebRTC** (item 16 in section b). The sexual-language rule depends on it,
   and it is the least certain piece of the design.
4. **Sign in with Apple token revocation on account deletion.** Guideline 5.1.1(v) requires it. The
   client sends only the identity token and the server deletes the account without revoking. Needs the
   authorization code sent at sign-in and a server call to Apple's revoke endpoint. Server work.
5. **Placeholders.** Release API URL (`https://api.tempo.example` in `project.yml`), Terms, Privacy,
   Community guidelines and Support URLs (`Features/Shared/LegalLinks.swift`). The paywall links to the
   Terms and Privacy placeholders; review will open them.
6. **Accounts and credentials.** `DEVELOPMENT_TEAM` is empty. Sign in with Apple and Push capabilities on
   the App ID, APNs key on the server, the `tempo.premium.monthly` product in App Store Connect, App Store
   Server credentials for `/v1/iap/verify`, and a TURN server.
7. **Privacy answers.** The manifest I added and the App Store privacy labels must match the privacy
   policy: camera frames and speech transcripts leave the device for moderation, and gender, "interested
   in" and religion are sensitive data. That needs the owner's and a lawyer's eyes, not mine.
8. **Purchase flow against the sandbox.** Purchase, Ask to Buy, renewal, expiry, restore, and a refund.
   Only the mock has ever run.
9. **Review notes.** Expect questions about the `audio` background mode, about how automated moderation
   works, and a request for a demo account. A moderation queue with a human behind it has to exist
   before the "a person reviews every report" copy is true.
10. **Known product gaps**, not blockers: no list of blocked people or way to unblock (needs server
    routes), English only (`Localizable.xcstrings` is empty), account deletion is not reachable during
    onboarding, and an incoming-call banner hides behind an open paywall sheet.
