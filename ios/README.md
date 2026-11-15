# Tempo for iOS

Live video speed dating. SwiftUI, iOS 18+, Swift 5 mode. The Xcode project is generated with XcodeGen.

**Read "First compile" below before your first build: this code has never been compiled.**

## 1. Generate the project

1. Install Xcode 16 or newer.
2. Install XcodeGen: `brew install xcodegen`
3. `cd ios`
4. `xcodegen`
5. `open Tempo.xcodeproj`
6. Wait for Swift Package Manager to fetch `WebRTC` (first time only, about 100 MB).

Run `xcodegen` again whenever you add, move or delete a file, or edit `project.yml`.

## 2. Run the demo in the Simulator (no backend)

1. Pick the **Tempo** scheme and an iPhone simulator (iOS 18+).
2. Press **Run** (Cmd-R).
3. On the first screen tap **Try the demo**.
4. Finish onboarding with any answers. The photo step needs a photo: the Simulator's photo
   library has samples.
5. On **Tonight**, tap the orb (**Go online**). A scripted partner shows up in 2–4 seconds.

What to expect:

- Everything is mocked: nothing leaves the device. The scheme passes the launch argument `-demo`.
- Demo dates last 45 seconds with 10-second icebreaker turns, then the Yes/No screen.
- The Simulator has no camera, so both videos are animated placeholders. On a real iPhone the demo
  shows your own camera.
- The demo account is kept between launches. To start over, delete the app from the simulator.

## 3. Switch to live mode (the server in `../server`)

Everything is stored in Postgres. Locally that is a Docker container; for Supabase see
`../server/DATA-MODEL.md`.

1. Start the database and the server (first time: `npm install`; `.env` already exists):
   ```bash
   cd ../server
   npm run db:up            # Postgres in Docker on 127.0.0.1:5434, data kept in a volume
   npm run dev              # http://localhost:8080; applies migrations; reads .env
   ```
2. In Xcode pick the **Tempo Live** scheme (next to the device menu) and Run.
3. Tap **Continue with a dev account** and finish onboarding.
4. Nobody else is online, so start someone to date in a second terminal:
   ```bash
   cd ../server
   npm run partner          # "Maya": always ready, says yes, answers chat. No video.
   ```
   `npm run partner -- --gender man --interested woman --name Theo` for the other way round.
5. On Tonight, slide to go online. You are paired with Maya, the date runs, you answer yes or no,
   and a match opens a chat she replies in.

Real iPhone: in `project.yml` change `TEMPO_API_BASE_URL` under `configs > Debug` to your Mac's
LAN address (for example `http://192.168.1.20:8080`) and run `xcodegen`. For real video you need
two phones, each with the app; untick `-allowNoVideo` in the scheme's arguments.

Notes for live mode:

- Real video needs real devices. Two simulators pair and run the whole flow, but have no camera.
- Sign in with Apple, push and App Store purchases need your team: select the **Tempo** target >
  **Signing & Capabilities** and choose it. The bundle id is `com.tempo.app`.
- The paywall works in the Simulator without App Store Connect: the scheme uses `Tempo.storekit`
  (product `tempo.premium.monthly`, $14.99 a month). Whether the server accepts a local StoreKit
  transaction depends on `ALLOW_DEV_IAP` (on in `.env.example`); see the IAP section of
  `../server/README.md`. This path has not been run.
- Release builds always run live against the `Release` value of `TEMPO_API_BASE_URL`.

## 4. Run the tests

1. Select the **Tempo** scheme and a simulator.
2. Press Cmd-U.

## First compile

Nothing in `ios/` has been through the Swift compiler. No toolchain was available where it was
written. Every file parses (tree-sitter), and scripts cross-checked initializers, method labels,
enum cases and duplicate names, but types, optionals, generics and actor isolation are unchecked.
Expect a short list of small fixes on the first build. The likeliest spots, most likely first:

| # | File | What to look at |
|---|---|---|
| 1 | `Tempo/Core/Services/LiveVideoCallService.swift` | Written from memory of the WebRTC headers (stasel/WebRTC, `from: 125.0.0`): `RTCAudioSessionConfiguration.webRTC()` / `setWebRTC(_:)`, `RTCAudioSession.setConfiguration(_:active:)`, `RTCPeerConnection.add(_:completionHandler:)`, the explicit closure types on `offer(for:)` / `answer(for:)` / `setLocalDescription` / `setRemoteDescription`, `RTCVideoRotation` cases `._90/._180/._270`, `RTCCVPixelBuffer.pixelBuffer`, and `transceiver.receiver.track as? RTCAudioTrack` in `applyAudioSilence()`. Demo mode never runs this class, but it must compile. |
| 2 | `Tempo/App/AppDelegate.swift` | `UNUserNotificationCenterDelegate` method signatures. A "nearly matches" warning means the method is not being called. |
| 3 | `Tempo/Core/Services/AuthService.swift`, `LocationService.swift`, `Tempo/App/AppDelegate.swift`, the stores in `Tempo/Core/Stores/` | `@MainActor` + `@Observable` init ordering, and `nonisolated` delegate methods on `@MainActor` classes. Diagnostics differ between Xcode versions. |
| 4 | `Tempo/Features/Root/WelcomeView.swift` | `AppleSignInButton`: `ASAuthorizationAppleIDButton(authorizationButtonType:authorizationButtonStyle:)` wrapped in `UIViewRepresentable`, with a target-action. Check it fills the width at 54 pt. Its style is `.black` when it is the main way in and `.whiteOutline` beside the demo button. |
| 5 | `Tempo/Features/Shared/ChoiceChips.swift` | `layout { … }`: calling a stored `FlowLayout` with a view-builder closure. |
| 6 | `Tempo/Features/Shared/PhotoGridEditor.swift` | `.photosPicker(isPresented:selection:matching:)` and `PhotosPickerItem.loadTransferable(type:)`. |
| 7 | `Tempo/Features/Chat/ChatView.swift` | `switch` over an optional enum (`.some(.block)` / `.none`) inside a `@ViewBuilder`. |
| 8 | `Tempo/Features/Root/TabShell.swift`, `Matches/MatchesView.swift`, `You/YouView.swift`, `Onboarding/OnboardingSteps.swift`, `DateFlow/DateLiveView.swift` (`DateTurnCardHost`) | `@Bindable var x = x` followed by `return …` in a `body`. |
| 9 | `Tempo/Features/Call/CallChrome.swift` | `KeepScreenAwakeModifier` and `CallAnnouncer` assume `View` is `@MainActor` (iOS 18 SDK). |
| 10 | `Tempo/Core/Models/User.swift` | `ProfileUpdate`: hand-written `encode(to:)` next to a synthesized `init(from:)`, with `CodingKeys` that leave out `clearing`. |
| 11 | `Tempo/Core/Networking/LiveRealtimeSocket.swift` | `URLSessionWebSocketTask.closeCode.rawValue` for custom close codes (4000, 4002). If they do not survive, the socket just reconnects. |
| 12 | Any `Task { @MainActor in … }` or `TaskBag.run { … }` that captures view state | Fine in Swift 5 mode; may warn about `Sendable` under stricter checking. Warnings only. |
| 13 | `project.yml` | XcodeGen keys written from memory: `storeKitConfiguration`, `commandLineArguments`, the generated `info` and `entitlements`. If the scheme has no StoreKit file or launch arguments, set them in the scheme editor. |
| 14 | `Tempo.storekit` | Hand-written. If Xcode refuses it, create a new StoreKit configuration with one auto-renewable subscription `tempo.premium.monthly`, $14.99, 1 month. |
| 15 | Daylight re-skin (`Tempo/DesignSystem/`, see `/NOTES-reskin.md`) | New after the re-skin and never compiled: `TempoBottomSheetModifier` (`UnevenRoundedRectangle` + `.ignoresSafeArea(edges:)` inside `.background`), `tempoSurface(in:fill:isFloating:showsBorder:)` (generic over `InsettableShape`), `AnyTransition.opacity.combined(with: AnyTransition.offset(x:y:))`, `Text + Text.italic()` in `MatchCelebration.headlineText`, `.underline()` on a view in `TempoTextButton`, `.statusBarHidden(_:)` on the date flow and the match call. |

Not compile errors, but check on the first run:

- SF Symbol names that could not be verified: `circle.grid.2x1`, `figure.and.child.holdinghands`,
  `person.badge.shield.checkmark`, `video.badge.checkmark`. A wrong name renders as an empty image.
- `TempoTests/DateStoreTests.swift` uses short real sleeps; it can be flaky on a loaded machine.
- On a real device: speech recognition next to WebRTC's microphone (`SpeechTranscriber.swift`),
  and whether `.blur` affects the Metal video layer behind the Yes/No screen (`CallChrome.swift`).

To re-run the static checks after a change: `python3 ios/Tools/check_project.py` (paths in
`project.yml`, duplicate file names, duplicate type names).

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen project definition |
| `Tempo/App` | App entry, `AppEnvironment`, app delegate, brand name |
| `Tempo/Core` | Models, networking, services, stores (see `CORE-API.md`) |
| `Tempo/DesignSystem` | Tokens and components (see `DESIGN-API.md`) |
| `Tempo/Features` | Screens |
| `Tempo/Resources` | Asset catalog, string catalog, bundled icebreakers |
| `TempoTests` | Unit tests |
| `Tempo.storekit` | Local StoreKit configuration |
| `Tools` | `generate_art.py` (watercolor images and the app icon; needs Google Chrome), `check_project.py` |

`Tempo/App/Info.plist` and `Tempo/App/Tempo.entitlements` are written by `xcodegen` from
`project.yml`; edit them there.

## Renaming the app

Change `Brand.name` in `Tempo/App/Brand.swift` and `TEMPO_BRAND_NAME` in `project.yml`.
