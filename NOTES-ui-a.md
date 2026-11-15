# NOTES — UI agent A (root, onboarding, tabs, chat, paywall)

Scope: `ios/Tempo/Features/{Root,Onboarding,Tonight,Matches,Chat,You,Paywall,Shared}`. Core, App and
DesignSystem were not modified. Nothing here has been compiled (no Swift toolchain in the workspace).

## What is here

| File | Contents |
|---|---|
| `Root/RootView.swift` | `RootView()`: splash → welcome → suspended → onboarding → shell |
| `Root/SplashView.swift`, `WelcomeView.swift`, `SuspendedView.swift` | launch, sign-in (Apple + dev entry), account paused; `LegalLinksRow` |
| `Root/TabShell.swift` | `TabShell`, `TempoTabBar`, `IncomingCallBanner`, date-flow cover, paywall sheet, global error toast, `pendingRoute` |
| `Onboarding/OnboardingFlow.swift`, `OnboardingSteps.swift` | ten steps, 18+ gate (`UnderageView`), submit with retry |
| `Tonight/TonightView.swift` | the Pulse, dates-left pill, guidance, periodic refresh |
| `Matches/MatchesView.swift` | list, skeletons, empty state, pull to refresh, swipe to unmatch |
| `Chat/ChatView.swift`, `ChatMessageList.swift` | chat, toolbar actions, call cover, pagination, day separators |
| `You/YouView.swift`, `EditProfileView.swift`, `DealbreakerEditor.swift`, `AccountScreens.swift` | profile, preferences, dealbreakers, rules, delete account |
| `Paywall/PaywallView.swift` | `PaywallView()` |
| `Shared/` | `AppRouter`, `LegalLinks`, `TaskBag`, `TempoFormat`, chip pickers, profile field editors, `PhotoGridEditor`, `CommunityRulesContent` |

## Contract with agent B, as implemented

- `DateFlowView()` is a `fullScreenCover` on `TabShell`, open exactly while `dateStore.isActive`.
- "Say hello" arrives as `environment.pendingRoute = .chat(matchId:)`; `TabShell` consumes it (loads the
  matches once if the match is not in the list yet) and sets it back to nil.
- An incoming call is `IncomingCallBanner` over every tab and chat. Accept opens that match's chat and calls
  `acceptCall()`. `MatchCallView(match:)` is a `fullScreenCover` on the chat while the call state for that
  match is outgoing, connecting, active or ended (not incoming, not idle).
- `ReportSheet` is presented from the chat's overflow menu. A failed report is shown as a toast after the
  sheet closes.
- `PaywallView()` styles its own presentation (corner radius, gold background) and dismisses itself.

## Workarounds for gaps in Core / DesignSystem

1. **No store intent for asking camera and microphone permission outside `goOnline()`.** The onboarding
   priming step calls `environment.permissions.requestCameraAndMicrophone()` directly.
2. **`DateStore.refreshOnlineCount()` swallows failures**, so Tonight cannot tell a failed refresh from a
   count of zero. The offline banner is driven by `dateStore.socketState` (disconnected / reconnecting).
3. **`SessionStore.suspension` is never cleared by `refreshUser()`**, so "Check again" on the paused screen
   only lifts a suspension that came from `user.suspendedUntil`. One pushed over the socket stays until the
   next sign-in or launch.
4. **`ProfileUpdate` omits nil fields**, so an answered basic (intention, children, …) cannot be cleared.
   Edit profile lets the user change such an answer but not remove it; unanswered ones can still be toggled.
5. **`MatchesStore.callPermissionIssue` is set while the call state is idle**, when no call screen is up.
   `TabShell` shows it as a system alert (Open Settings / Not now).
6. **No tab bar in the design system.** `TempoTabBar` is built in `Features/Root` from tokens and
   `tempoFrosted`. Tabs are switched by replacing the tab's root view, so a tab's scroll position resets
   when you leave it; navigation paths are kept in `AppRouter`.
7. **`TempoButton` has no disabled look**; disabled buttons get `.disabled` plus 40% opacity.
8. **`ChatComposer` does not clear its text**; the chat clears the draft when it sends.
9. **Design-system components contain a few fixed English strings** ("Main", "Try again", "Premium",
   PulseOrb's count line). Everything passed in from Features goes through `String(localized:)`.

## Decisions the spec did not cover

- **Sign in with Apple** is an ivory capsule with the Apple logo calling `session.signInWithApple()` (Core
  runs the authorization). The preview's ember "Continue" is not used there, to follow Apple's button rules.
- **Tonight**: the orb is the only "Go online" control (it carries the label and the count line). The
  preview's separate ember button under a large numeral is not repeated.
- **18+ gate**: Continue is disabled until the date wheels have been moved. An under-18 birthdate stores
  the account id in `UserDefaults` (`tempo.onboarding.underageUserId`) and shows a dead-end screen with only
  Sign out; the server is not told. Demo mode adds "Start over (demo only)".
- **Location step** requires a city (detected or typed) before Continue.
- **Age range 18–99 and distance 1–200 km** are UI bounds; they are not in `AppConfig`. Slider changes
  save 0.6 s after the last movement.
- **Dealbreaker editors** save one filter at a time with a Save button; an empty selection is sent as nil.
- **Copy that states limits not in `AppConfig`**: "At most once every four hours", "three strikes".
  Durations (date length, frame interval) are read from `ConfigStore`.
- **Errors**: screens that show a failure inline clear the store's `lastError` right after their call.
  Anything left in `session.lastError`, `matchesStore.lastError`, or `dateStore.lastError` (while no date
  is active) becomes a toast in `TabShell`.
- **Not cancelled when the screen goes away, on purpose**: sending or retrying a message, starting a call,
  purchase and restore from the paywall, sign-out, account deletion. Everything else runs in `.task` or a
  `TaskBag` that is cancelled in `onDisappear`.
- **Omitted from the preview's You tab**: "Blocked people" (Core has no list of blocks).
- **`LegalLinks`** holds placeholder `https://tempo.example/...` URLs; replace them before release.

## Verification

- `node ~/.tempo-tools/check.js <my 8 dirs>`: 24 files, 0 parse errors (tree-sitter-swift).
- `node ~/.tempo-ui-a/verify.js`: indexes every declaration under `ios/Tempo` and checks my files against
  it: 322 initializer calls, 420 method calls, 1,139 member accesses, 190 switch patterns, 33 switches for
  exhaustiveness, duplicate type names across the module, force unwraps. 0 problems. Tested with eleven
  deliberate mistakes; it caught all of them.
- `node ~/.tempo-ui-a/builders.js`: 147 view-returning declarations checked for result-builder / `return`
  mistakes. 0 problems.
- None of this checks types, optionality, generics inference or actor isolation, and SwiftUI's own API is
  only as correct as my memory of it.

## Least sure it compiles

1. `layout { … }` in `Shared/ChoiceChips.swift`: calling a stored `FlowLayout` value with a view-builder
   closure (`Layout.callAsFunction`).
2. `.photosPicker(isPresented:selection:matching:)` and `PhotosPickerItem.loadTransferable(type:)` in
   `Shared/PhotoGridEditor.swift`.
3. `switch` over an optional enum with `.some(.block)` / `.none` inside a `@ViewBuilder` in `Chat/ChatView.swift`.
4. The `@Bindable var router = router` + `return …` bodies in `TabShell`, `MatchesView`, `YouView` and the
   onboarding steps.
5. Capturing view state in `Task { @MainActor in … }` and in `TaskBag.run` closures: fine in Swift 5 mode,
   but may produce Sendable warnings under stricter concurrency checking.
6. Symbol names are unverified at build time: `circle.grid.2x1`, `figure.and.child.holdinghands`,
   `person.badge.shield.checkmark`, `video.badge.checkmark`. A wrong name renders as an empty image.
