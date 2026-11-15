# CORE-API — what Features may use from `Tempo/App` and `Tempo/Core`

Everything is `internal` in the app module `Tempo`. Signatures below are copied from the code.
Write screens against this file and `DESIGN-API.md` only.

Contents: 1 Environment · 2 SessionStore · 3 DateStore · 4 MatchesStore · 5 PremiumStore · 6 ConfigStore ·
7 Video views · 8 Images · 9 Models · 10 Enums · 11 Errors · 12 Clock math · 13 Misc · 14 Rules

---

## 1. Environment

### Reading stores in a View (exact code)

```swift
@Environment(AppEnvironment.self) private var environment
@Environment(SessionStore.self) private var session
@Environment(DateStore.self) private var dateStore
@Environment(MatchesStore.self) private var matchesStore
@Environment(PremiumStore.self) private var premiumStore
@Environment(ConfigStore.self) private var configStore
```

All stores are `@MainActor @Observable final class`. Reading a property in `body` subscribes the view.
To bind to a settable property, make a bindable inside `body`:

```swift
var body: some View {
    @Bindable var session = session
    TextField("First name", text: $session.draft.firstName)
}
```

Call async intents from a `Task` or `.task`:

```swift
Button("Sign in") { Task { await session.signInWithApple() } }
```

### Root and previews

The app does this already (`TempoApp.swift`); `RootView` must be `struct RootView: View { init() }`
in `Tempo/Features/Root/RootView.swift`:

```swift
RootView()
    .tempoEnvironment(environment)
    .preferredColorScheme(.light)
```

`tempoEnvironment` injects `AppEnvironment` and all five stores, and starts the environment
(loads config, restores the session). Use it in every preview:

```swift
#Preview {
    SomeScreen()
        .tempoEnvironment(AppEnvironment.demo())
}
```

```swift
extension View {
    @MainActor
    func tempoEnvironment(_ environment: AppEnvironment) -> some View
}
```

### AppEnvironment

```swift
enum AppMode: String, Sendable, Equatable { case demo, live }

enum AppRoute: Sendable, Equatable {
    case tonight
    case matches
    case chat(matchId: String)
    case you
}

@MainActor @Observable
final class AppEnvironment {
    let mode: AppMode
    var isDemo: Bool { get }

    // Stores
    let config: ConfigStore
    let session: SessionStore
    let dates: DateStore
    let matches: MatchesStore
    let premium: PremiumStore

    // Services Features may touch
    let imageCache: ImageCache            // for RemoteImageLoader
    let video: any VideoCallService       // normally only through LocalVideoView / RemoteVideoView

    /// Set when the user taps a notification. RootView navigates, then sets it to nil.
    var pendingRoute: AppRoute?
    private(set) var hasStarted: Bool

    func start() async                    // called by tempoEnvironment; idempotent

    static func demo(
        signedIn: Bool = true,
        onboarded: Bool = true,
        persist: Bool = false,
        config: DemoConfig = DemoConfig()
    ) -> AppEnvironment
    static func live() -> AppEnvironment
    static func makeDefault() -> AppEnvironment   // launch arg -demo / -live, else Debug=demo, Release=live
}
```

Other properties exist (`api`, `socket`, `moderation`, `purchases`, `push`, `location`, `auth`,
`permissions`, `tokenStore`); Features should go through the stores instead.

### Demo environments for previews

| Want | Code |
|---|---|
| Signed in, onboarded, 3 seeded matches (default) | `AppEnvironment.demo()` |
| Sign-in screen | `AppEnvironment.demo(signedIn: false, onboarded: false)` |
| Onboarding | `AppEnvironment.demo(signedIn: true, onboarded: false)` |
| A date-flow phase | see below |

`AppEnvironment.demo()` is signed in synchronously (`session.user` is non-nil and
`matchesStore.matches` holds 3 matches at once). With `signedIn: false`, `session.authState` is
`.loading` for a moment and becomes `.signedOut` when `tempoEnvironment` starts the environment.

Freeze the date flow in one phase for a preview (previews only):

```swift
#Preview("Live") {
    let environment = AppEnvironment.demo()
    let partner = DemoWorld.roster[0]
    environment.dates.debugSetPhase(
        .live,
        partner: partner,
        endsAt: Date().addingTimeInterval(192),
        icebreaker: IcebreakerState(
            question: "What would your perfect Sunday look like?",
            questionIndex: 0,
            speakerId: partner.id,
            turnEndsAt: Date().addingTimeInterval(21),
            turnDuration: 30,
            isMyTurn: false
        )
    )
    return DateFlowView().tempoEnvironment(environment)
}
```

```swift
// DateStore
func debugSetPhase(
    _ newPhase: DatePhase,
    partner newPartner: Partner? = nil,
    endsAt newEndsAt: Date? = nil,
    icebreaker newIcebreaker: IcebreakerState? = nil,
    nextCountdownEndsAt newCountdownEndsAt: Date? = nil,
    moderationWarning newWarning: ModerationWarning? = nil
)
// MatchesStore
func debugSetCallState(_ newState: CallState)
```

Fixtures: `DemoWorld.roster: [Partner]` (12 partners, `photoUrl == nil`), `DemoWorld.onboardedUser() -> User`,
`environment.matches.matches` (seeded `Match` values, ids `"demo-match-lena"`, `"demo-match-omar"`, `"demo-match-june"`).

`DemoConfig` (all `var`, defaults shown): `dateDurationSec = 45`, `turnDurationSec = 10`,
`decisionWindowSec = 20`, `freeDailyDates = 5`, `frameSampleIntervalSec = 3.0`, `pairingDelayMin = 2.0`,
`pairingDelayMax = 4.0`, `partnerYesProbability = 0.6`, `partnerLeftProbability = 0.12`, `latency = 0.25`,
`autoScript = true`. Create with `var c = DemoConfig()`, then mutate.

What the demo does when the user goes online: `queue.status` at once, a partner after 2–4 s
(rotating through the roster), the date starts about 1 s later and lasts 45 s, icebreaker turns of
10 s that alternate (the fake partner passes early sometimes), about 1 in 8 partners leaves early,
then the decision; a Yes is matched about 60 % of the time. After 5 dates a free user gets
`limitReached`. Sending a chat message gets a reply in 2–4.5 s. Calling a match is accepted after 1.5–3 s (85 %).

---

## 2. SessionStore — auth, current user, onboarding

```swift
enum AuthState: String, Sendable, Equatable {
    case loading      // checking the stored token; if lastError != nil the check failed → offer retry (bootstrap())
    case signedOut
    case signedIn
}

@MainActor @Observable
final class SessionStore {
    private(set) var authState: AuthState
    private(set) var user: User?
    var draft: OnboardingDraft                 // bind fields directly
    private(set) var isWorking: Bool           // sign-in / submit / save / delete in flight
    private(set) var isUploadingPhoto: Bool
    private(set) var isLocating: Bool
    var lastError: TempoError?                 // show lastError?.userMessage; set nil to dismiss
    private(set) var suspension: AccountSuspended?

    var isSignedIn: Bool { get }
    var isOnboardingComplete: Bool { get }     // user?.onboardingComplete ?? false
    var isPremium: Bool { get }
    var userId: String? { get }
    var supportsDevSignIn: Bool { get }        // offer dev sign-in when true (demo mode, Debug builds)
    var isSuspended: Bool { get }

    func bootstrap() async                     // also the retry action when authState == .loading && lastError != nil

    func signInWithApple() async               // failure → lastError (user cancel is silent)
    func signInDev() async

    @discardableResult func submitOnboarding() async -> Bool          // true → isOnboardingComplete is now true
    @discardableResult func updateProfile(_ update: ProfileUpdate) async -> Bool
    @discardableResult func updatePreferences(_ preferences: Preferences) async -> Bool
    @discardableResult func setNotifyOnlineSingles(_ enabled: Bool) async -> Bool   // asks notification permission when enabling
    @discardableResult func uploadPhoto(jpegData: Data) async -> String?
    @discardableResult func uploadPhoto(image: UIImage) async -> String?            // scales + encodes, then uploads
    @discardableResult func removePhoto(url: String) async -> Bool
    @discardableResult func setPhotoOrder(_ urls: [String]) async -> Bool
    @discardableResult func detectLocation() async -> Bool            // one-shot location + city
    @discardableResult func refreshUser() async -> Bool  // GET /v1/me; false = request failed. Also lifts a
                                                          // socket-pushed suspension when the user is in good standing

    func signOut() async
    @discardableResult func deleteAccount() async -> Bool             // false + lastError on failure
}
```

Behaviour:
- Root: `authState == .loading` → splash (with retry if `lastError != nil`); `.signedOut` → sign-in;
  `.signedIn && !isOnboardingComplete` → onboarding; else the tab shell.
- During onboarding (`!isOnboardingComplete`) `uploadPhoto` appends to `draft.photoUrls`, `removePhoto`
  and `setPhotoOrder` edit the draft, and `detectLocation` fills `draft.city`, `draft.lat`, `draft.lng`.
  After onboarding the same calls save to the profile (`user.photoUrls`, `user.city`, …).
- `submitOnboarding()` validates first; when the draft is not ready it returns false and sets
  `lastError` to the sentence from `draft.validationMessage`.
- `updateProfile` sends only the non-nil fields of `ProfileUpdate`:
  `await session.updateProfile(ProfileUpdate(bio: "New bio"))`. To remove an answered basic, name it in
  `clearing` (sent as an explicit `null`): `ProfileUpdate(clearing: [.religion])`.
- Edit preferences by copying: `var p = session.user?.preferences ?? Preferences(); p.ageMax = 40; await session.updatePreferences(p)`.
  Advanced filters (`intentions`, `children`, `religions`, `minEducation`, `smokingOk`, `drinkingOk`) are
  ignored by the server unless Premium: gate those controls on `session.isPremium`.

---

## 3. DateStore — the speed-date state machine

```swift
enum DatePhase: Equatable, Sendable {
    case idle                                         // cover closed
    case searching
    case limitReached(resetsAt: Date)
    case connecting(partner: Partner)                 // paired, video connecting, clock not started
    case live
    case deciding(partner: Partner, deadline: Date)
    case awaitingResult(partner: Partner)             // "Sealed"
    case matched(match: Match)
    case noMatch(partner: Partner)
    case partnerLeft(partner: Partner)
    case ended(reason: DateEndReason)                 // .youLeft, .moderation or .disconnect
    case suspended(reason: String)
}

struct ModerationWarning: Sendable, Equatable, Identifiable {
    var id: UUID
    var category: ModerationCategory
    var message: String
    var isFinal: Bool        // true = the date is being ended because of this
    var issuedAt: Date
}

@MainActor @Observable
final class DateStore {
    private(set) var phase: DatePhase
    private(set) var partner: Partner?                 // current or just-finished partner; nil while idle/searching
    private(set) var startsAt: Date?
    private(set) var endsAt: Date?                     // device clock; non-nil only while .live
    private(set) var icebreaker: IcebreakerState?      // nil until the first turn of a date
    private(set) var compatibleOnline: Int
    private(set) var queuePosition: Int?
    private(set) var moderationWarning: ModerationWarning?
    var isIcebreakerHidden: Bool                       // settable; persists across dates
    private(set) var isMicMuted: Bool
    private(set) var isCameraOff: Bool
    private(set) var cameraPosition: CameraPosition
    private(set) var datesRemainingToday: Int?         // nil = unlimited (Premium) or not loaded
    private(set) var usage: Usage?
    private(set) var nextCountdownEndsAt: Date?        // non-nil = interstitial counting down
    private(set) var permissionIssue: PermissionIssue? // camera/mic blocked going online
    private(set) var willStopAfterThis: Bool
    private(set) var myDecision: DateDecision?
    private(set) var videoState: VideoConnectionState
    private(set) var socketState: SocketConnectionState
    private(set) var isStartingUp: Bool                // goOnline() is asking for permissions
    var lastError: TempoError?

    var isActive: Bool { get }                         // phase != .idle  → drives the fullScreenCover
    var isInDate: Bool { get }                         // connecting, live, deciding, awaitingResult
    var isInCall: Bool { get }                         // connecting, live (audio + transcripts run only here; frame checks run for all of isInDate)
    func remaining(at now: Date = Date()) -> TimeInterval

    // Intents
    private(set) var didSearchTimeOut: Bool            // search ran `timing.searchTimeout` (90 s) and found nobody
    func searchAgain()                                 // after a timed-out search
    func goOnline()
    func goOffline()
    func leaveDate()
    func passTurn()
    func decide(_ decision: DateDecision)
    func continueToNext()
    func stopAfterThis()
    func toggleMic()
    func toggleCamera()
    func flipCamera()
    @discardableResult func report(reason: ReportReason, details: String?) async -> Bool
    @discardableResult func blockPartner() async -> Bool

    func dismissModerationWarning()
    func dismissPermissionIssue()
    func requestMediaAccess() async -> PermissionIssue? // onboarding priming: same prompts as goOnline(), no queue,
                                                        // does not set permissionIssue; nil = both granted
    func openSettings()                                // opens the app's Settings page
    func refreshUsage() async                          // GET /v1/usage → usage, datesRemainingToday
    func refreshOnlineCount() async                    // GET /v1/online-count → compatibleOnline (Tonight tab, while idle)
}
```

### What each phase means for UI

| Phase | Show | Countdown source | Actions |
|---|---|---|---|
| `.idle` | Tonight tab (the Pulse) | – | `goOnline()` |
| `.searching` | searching orb, `compatibleOnline` | – | `goOffline()` |
| `.limitReached(resetsAt)` | "out of dates" + paywall entry | `resetsAt` | `goOffline()`; after buying Premium `continueToNext()` |
| `.connecting(partner)` | partner found state, `LocalVideoView`, `RemoteVideoView` | – | `leaveDate()` |
| `.live` | call UI; `partner`, `endsAt`, `icebreaker` | `endsAt`, total `configStore.dateDuration` | `leaveDate()`, `passTurn()`, toggles, report/block, `stopAfterThis()` |
| `.deciding(partner, deadline)` | the Verdict over the blurred `RemoteVideoView` (still live, silent) | `deadline`, total `configStore.decisionWindow` | `decide(.yes)`, `decide(.no)` |
| `.awaitingResult(partner)` | sealed state, `myDecision`; video still up | – | – |
| `.matched(match)` | the Match | – (`nextCountdownEndsAt == nil`) | "Say hello": `goOffline()` then open chat `match.id`; "Keep dating": `continueToNext()` |
| `.noMatch(partner)` | "Not this time." | `nextCountdownEndsAt`, total 3 s | `continueToNext()` (skip), `stopAfterThis()` |
| `.partnerLeft(partner)` | "They left" | `nextCountdownEndsAt` | same |
| `.ended(reason)` | by reason, see below | `nextCountdownEndsAt` (may be nil) | `continueToNext()`, `stopAfterThis()` |
| `.suspended(reason)` | suspension notice (`reason` is display text) | – | `goOffline()` |

- `nextCountdownEndsAt != nil` means the store will act by itself at that time: it re-queues (phase →
  `.searching`), or goes `.idle` when `willStopAfterThis` is true. When it is nil nothing happens until the user acts.
- `.ended(.youLeft)`: 3 s countdown then re-queue. `.ended(.disconnect)`: countdown when the partner's
  connection dropped; no countdown when this phone lost the server (offer `continueToNext()` and
  `stopAfterThis()`). `.ended(.moderation)`: never a countdown; show `moderationWarning?.message` and
  offer `continueToNext()` / `stopAfterThis()`.
- `stopAfterThis()` between dates (searching, limitReached, matched, noMatch, partnerLeft, ended,
  suspended) closes the flow at once (`.idle`). During a date it only sets `willStopAfterThis`.
- `leaveDate()` is immediate: phase becomes `.ended(reason: .youLeft)` without waiting for the server.
  During `.deciding` it is the same as `decide(.no)`.
- `goOnline()` asks for camera and microphone access first. If refused, `phase` stays `.idle` and
  `permissionIssue` is set: show `permissionIssue.title` / `.message`, a button calling `openSettings()`,
  and `dismissPermissionIssue()`. Because the phase is `.idle`, the date-flow cover is closed at that
  moment: the screen that calls `goOnline()` (Tonight) is the one that shows it.
- **Video outlives the date by one screen.** At `date.ended{timer}` the store silences the call in
  both directions and stops speech transcription (`moderation.stopTranscription()`), but keeps the peer
  connection and both videos up through `.deciding` and `.awaitingResult` (all of `isInDate`). The
  cameras are still on there, so **camera-frame sampling and frame moderation keep running until the
  video is torn down**; a `moderation.action` / `date.ended{moderation}` is honoured in those phases
  too and lands in `.ended(reason: .moderation)`. The connection closes when the result arrives
  (`.matched` / `.noMatch`), on the result timeout, on `goOffline()`, or on suspension. Every other
  ending (`partner_left`, `you_left`, `moderation`, `disconnect`) closes it at once. `isMicMuted` is
  the user's own toggle and is not changed by this.
- The camera is released whenever the flow waits for the user with no video on screen (`.matched`,
  `.ended(.moderation)`, `.ended(.disconnect)` without a countdown, `.limitReached`); re-queueing starts it again.
- Safety net: a `.live` date whose `date.ended` never arrives ends as `.ended(reason: .disconnect)`
  (no countdown) `DateStoreTiming.liveOverrunGrace` (15 s) after the server's end time.
- `partner` stays set through `.noMatch`, `.partnerLeft`, `.ended` and `.matched`, so report/block still
  work on those screens. `report` and `blockPartner` return false and set `lastError` on failure.
  `blockPartner()` also leaves the date.
- `moderationWarning`: show as a banner over the call; `isFinal == false` is a warning the user can
  dismiss with `dismissModerationWarning()`; `isFinal == true` is followed by `.ended(reason: .moderation)`.
- `videoState` while `.connecting` / `.live`: `.connecting` and `.reconnecting` deserve a small
  "Connecting…" / "Reconnecting…" hint (`videoState.displayName`).
- `datesRemainingToday`: "3 dates left today". nil with `session.isPremium` → unlimited.
- The cover: `.fullScreenCover(isPresented: Binding(get: { dateStore.isActive }, set: { if !$0 { dateStore.goOffline() } }))`.

### IcebreakerState

```swift
struct IcebreakerState: Sendable, Equatable {
    var question: String
    var questionIndex: Int
    var speakerId: String
    var turnEndsAt: Date            // device clock
    var turnDuration: TimeInterval
    var isMyTurn: Bool
    func remaining(at now: Date = Date()) -> TimeInterval
    func fractionRemaining(at now: Date = Date()) -> Double   // 1 → 0
}
```

Show "Pass" only when `dateStore.icebreaker?.isMyTurn == true`. Hide/show the card with `dateStore.isIcebreakerHidden`.

---

## 4. MatchesStore — matches, chat, post-match video call

```swift
struct ChatMessage: Sendable, Equatable, Identifiable {
    enum Delivery: String, Sendable, Equatable { case sending, sent, failed }
    let id: String                 // stable from optimistic send through confirmation
    var message: Message
    var delivery: Delivery
    var isMine: Bool
    var text: String { get }
    var sentAt: Date { get }
}

struct ChatThread: Sendable, Equatable {
    var messages: [ChatMessage]    // oldest first
    var isLoading: Bool
    var hasLoaded: Bool
    var hasMoreHistory: Bool
    var loadError: TempoError?
}

enum CallEndReason: String, Sendable, Equatable {
    case ended, declined, noAnswer, failed
    var displayName: String { get }
}

enum CallState: Sendable, Equatable {
    case idle
    case outgoing(matchId: String)                       // ringing them
    case incoming(matchId: String)                       // they ring the user
    case connecting(matchId: String)
    case active(matchId: String)
    case ended(matchId: String, reason: CallEndReason)   // show briefly, then dismissCall()
    var matchId: String? { get }
    var isPresented: Bool { get }                        // self != .idle → present the call screen
    var isOngoing: Bool { get }
}

@MainActor @Observable
final class MatchesStore {
    private(set) var matches: [Match]                    // most recent activity first
    private(set) var isLoading: Bool
    private(set) var hasLoaded: Bool
    var lastError: TempoError?
    private(set) var threads: [String: ChatThread]       // keyed by match id
    private(set) var activeChatMatchId: String?

    var totalUnread: Int { get }                         // tab badge
    func match(id: String) -> Match?
    func messages(for matchId: String) -> [ChatMessage]
    func thread(for matchId: String) -> ChatThread

    func load() async                                    // .task and pull-to-refresh
    @discardableResult func unmatch(matchId: String) async -> Bool
    @discardableResult func report(matchId: String, reason: ReportReason, details: String?) async -> Bool
    @discardableResult func block(matchId: String) async -> Bool      // also removes the match

    // Chat
    func openChat(matchId: String) async                 // call in the chat's .task: loads the newest page (every time), marks read
    func resync() async                                  // after a reconnect / on foreground: reloads matches and the open chat
    func closeChat(matchId: String)                      // call in .onDisappear
    func loadMessages(matchId: String) async             // reload (retry after thread.loadError)
    func loadEarlier(matchId: String) async              // pagination, when the user reaches the top
    func send(text: String, to matchId: String) async    // optimistic
    func retry(messageId: String, in matchId: String) async
    func discardFailed(messageId: String, in matchId: String)
    func markRead(matchId: String) async

    // Video call again
    private(set) var callState: CallState
    private(set) var isCallMicMuted: Bool
    private(set) var isCallCameraOff: Bool
    private(set) var callPermissionIssue: PermissionIssue?
    var callPartner: Partner? { get }
    func startCall(matchId: String) async
    func acceptCall() async
    func declineCall()
    func endCall()                                       // hang up / cancel ringing
    func dismissCall()                                   // clears .ended
    func toggleCallMic()
    func toggleCallCamera()
    func flipCallCamera()
    func dismissCallPermissionIssue()
    func openSettings()
}
```

Behaviour:
- `send` adds a `.sending` row at once; it becomes `.sent` or `.failed`. For `.failed` offer
  `retry(messageId:in:)` (pass `chatMessage.id`) and `discardFailed`.
- Incoming messages arrive by themselves; `match.unreadCount` and `totalUnread` update. Messages for the
  chat that is open (`openChat` … `closeChat`) are marked read automatically.
- The store re-syncs by itself when the socket reconnects (`resync()`); `closeChat` trims the thread
  kept in memory to the newest page, and messages are limited to 2000 characters by the server.
- `unmatch`, `report`, `block` return false and set `lastError` on failure. After `unmatch`/`block` the
  match is gone from `matches`: pop the chat.
- If the other person unmatches, the match disappears from `matches`; a chat screen should pop when
  `matchesStore.match(id:) == nil`.
- Call screen: present with `matchesStore.callState.isPresented` (e.g. a `fullScreenCover` at the root so
  incoming calls show anywhere). `.incoming` → Accept (`acceptCall()`) / Decline; `.outgoing` → "Calling
  Maya…" + cancel (`endCall()`); `.connecting` / `.active` → `RemoteVideoView()` + `LocalVideoView()` + controls;
  `.ended(_, reason)` → `reason.displayName`, then `dismissCall()`. Outgoing rings time out after 30 s (`.noAnswer`).
- A call cannot start while the date flow is active (`lastError` explains), and incoming calls are
  declined automatically during a date.

---

## 5. PremiumStore

```swift
enum PurchaseState: Sendable, Equatable {
    case idle
    case purchasing
    case restoring
    case pending              // Ask to Buy; unlocks by itself when approved
    case success              // show confirmation, close the paywall, then resetPurchaseState()
    case failed(TempoError)   // show error.userMessage
}

struct PremiumProduct: Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var description: String
    var displayPrice: String      // "$14.99"
    var periodLabel: String       // "month"
    var priceLine: String { get } // "$14.99 / month"
}

@MainActor @Observable
final class PremiumStore {
    private(set) var product: PremiumProduct?
    private(set) var isLoadingProduct: Bool
    private(set) var productError: TempoError?      // offer retry: loadProduct()
    private(set) var purchaseState: PurchaseState
    var isPremium: Bool { get }
    var premiumExpiresAt: Date? { get }
    var isBusy: Bool { get }                        // purchasing or restoring → disable buttons

    func loadProduct() async                        // call in the paywall's .task
    func purchase() async
    func restore() async
    func resetPurchaseState()
}
```

Never hardcode the price: use `premiumStore.product?.priceLine` (show a placeholder while nil).
The app name for the paywall is `Brand.premiumName`.

---

## 6. ConfigStore — server tunables

```swift
@MainActor @Observable
final class ConfigStore {
    private(set) var config: AppConfig
    private(set) var isLoaded: Bool
    private(set) var lastError: TempoError?
    func load() async
    var dateDuration: TimeInterval { get }       // 240 (45 in demo)
    var turnDuration: TimeInterval { get }       // 30 (10 in demo)
    var decisionWindow: TimeInterval { get }     // 20
    var freeDailyDates: Int { get }              // 5
    var frameSampleInterval: TimeInterval { get }
    var iceServers: [IceServer] { get }
}
```

Use these for every "total duration" a countdown component needs. Never write 240, 30, 20 or 5 in UI.

---

## 7. Video views

```swift
struct LocalVideoView: View { init() }    // the user's camera; front camera already mirrored
struct RemoteVideoView: View { init() }   // the other person; aspect-fill
```

They take the video service from the environment (needs `tempoEnvironment`). Size and clip them yourself:

```swift
RemoteVideoView().ignoresSafeArea()
LocalVideoView().frame(width: 96, height: 136).clipShape(RoundedRectangle(cornerRadius: 20))
```

In demo mode the remote view is an animated gradient (put the partner's monogram/photo over it if you
like) and the local view is the real camera on a device or an animated placeholder in the Simulator.
The same two views serve speed dates and post-match calls. When the camera is toggled off the local view
goes dark (live) or shows the placeholder (demo): overlay your own "camera off" state using
`dateStore.isCameraOff` / `matchesStore.isCallCameraOff`. `LocalVideoView` also works while `.searching`.

```swift
enum VideoConnectionState: String, Sendable, Equatable, CaseIterable {
    case idle, connecting, connected, reconnecting, failed, closed
    var displayName: String { get }
}
enum CameraPosition: String, Sendable, Equatable, CaseIterable {
    case front, back
    var displayName: String { get }
}
enum SocketConnectionState: String, Sendable, Equatable, CaseIterable {
    case disconnected, connecting, connected, reconnecting
    var displayName: String { get }
}
```

---

## 8. Images

```swift
final class ImageCache {
    func resolve(_ string: String?) -> URL?
    func cachedImage(for url: URL) -> UIImage?
    func image(for url: URL) async throws -> UIImage
}

@MainActor @Observable
final class RemoteImageLoader {
    enum Phase: Equatable { case empty, loading, loaded, failed }
    private(set) var image: UIImage?
    private(set) var phase: Phase
    init()
    func load(_ urlString: String?, using cache: ImageCache) async
}
```

Pattern for a photo with a monogram fallback (`photoUrl` is nil for every demo partner):

```swift
struct PhotoView: View {
    let urlString: String?
    @Environment(AppEnvironment.self) private var environment
    @State private var loader = RemoteImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear   // your monogram / gradient placeholder
            }
        }
        .task(id: urlString) { await loader.load(urlString, using: environment.imageCache) }
    }
}
```

`ImageEncoding.jpegData(from: UIImage, maxSide: CGFloat = 1440, quality: CGFloat = 0.82) -> Data?`
(`@MainActor static`) is what `session.uploadPhoto(image:)` uses.

---

## 9. Models (all `Codable, Sendable, Equatable`; `Identifiable` where they have `id`)

```swift
struct User: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var firstName: String
    var birthdate: String            // "YYYY-MM-DD"; "" until onboarding
    var gender: Gender?              // nil until onboarding
    var interestedIn: [Gender]
    var bio: String
    var city: String
    var lat: Double?
    var lng: Double?
    var photoUrls: [String]
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var isPremium: Bool
    var premiumExpiresAt: Date?
    var onboardingComplete: Bool
    var strikes: Int
    var suspendedUntil: Date?
    var preferences: Preferences

    var age: Int? { get }
    var isSuspended: Bool { get }
    var primaryPhotoUrl: String? { get }
    var monogram: String { get }      // "A"
}

struct Preferences: Codable, Sendable, Equatable {
    var ageMin: Int
    var ageMax: Int
    var maxDistanceKm: Int
    var intentions: [Intention]?       // advanced (Premium); nil = no filter
    var children: [ChildrenStatus]?    // advanced
    var religions: [Religion]?         // advanced
    var minEducation: Education?       // advanced
    var smokingOk: [Smoking]?          // advanced
    var drinkingOk: [Drinking]?        // advanced
    var notifyOnlineSingles: Bool
    init(ageMin: Int = 18, ageMax: Int = 99, maxDistanceKm: Int = 100, intentions: [Intention]? = nil,
         children: [ChildrenStatus]? = nil, religions: [Religion]? = nil, minEducation: Education? = nil,
         smokingOk: [Smoking]? = nil, drinkingOk: [Drinking]? = nil, notifyOnlineSingles: Bool = false)
    var hasAdvancedFilters: Bool { get }
}

/// Body of PUT /v1/me. Only non-nil fields are sent (plus `null` for each field named in `clearing`).
/// Every parameter of init defaults to nil (`clearing` to []).
struct ProfileUpdate: Codable, Sendable, Equatable {
    var firstName: String?
    var birthdate: String?           // Birthdate.string(from: Date)
    var gender: Gender?
    var interestedIn: [Gender]?
    var bio: String?
    var city: String?
    var lat: Double?
    var lng: Double?
    var photoUrls: [String]?
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var onboardingComplete: Bool?
    var tzOffsetMinutes: Int?
    var clearing: Set<ClearableProfileField>   // default []; answers to remove, sent as explicit null
}

struct OnboardingDraft: Sendable, Equatable {
    var firstName: String = ""
    var birthdate: Date?
    var gender: Gender?
    var interestedIn: [Gender] = []
    var bio: String = ""
    var city: String = ""
    var lat: Double?
    var lng: Double?
    var photoUrls: [String] = []          // filled by session.uploadPhoto during onboarding
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var ageMin: Int = 21
    var ageMax: Int = 45
    var maxDistanceKm: Int = 50
    var notifyOnlineSingles: Bool = false

    var trimmedFirstName: String { get }
    var age: Int? { get }
    var isAdult: Bool { get }             // 18+ gate
    var isNameValid: Bool { get }         // 2–30 characters
    var canSubmit: Bool { get }           // name, 18+, gender, at least one interestedIn
    var validationMessage: String? { get }// first blocking problem, nil when ready
}

struct Partner: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var firstName: String
    var age: Int
    var city: String
    var distanceKm: Double?
    var photoUrl: String?
    var intention: Intention?
    var monogram: String { get }          // "M"
    var nameAndAge: String { get }        // "Maya, 29"
    var locationLine: String? { get }     // "2 km away", else the city, else nil
    var summaryLine: String { get }       // "Maya, 29 · 2 km away"
}

struct Match: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var partner: Partner
    var matchedAt: Date
    var lastMessage: Message?
    var unreadCount: Int
    var lastActivityAt: Date { get }
}

struct Message: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var matchId: String
    var senderId: String
    var text: String
    var sentAt: Date
    var clientId: String?
}

struct AppConfig: Codable, Sendable, Equatable {
    var dateDurationSec: Int
    var turnDurationSec: Int
    var decisionWindowSec: Int
    var freeDailyDates: Int
    var frameSampleIntervalSec: Double
    var iceServers: [IceServer]
}

struct IceServer: Codable, Sendable, Equatable, Hashable {
    var urls: [String]
    var username: String?
    var credential: String?
}

struct Usage: Codable, Sendable, Equatable {
    var datesToday: Int
    var limit: Int?                  // nil = unlimited
    var resetsAt: Date
    var remaining: Int? { get }      // nil = unlimited
}

struct AccountSuspended: Codable, Sendable, Equatable {
    var until: Date?
    var reason: String
}

struct ResolvedLocation: Sendable, Equatable { var lat: Double; var lng: Double; var city: String }
```

Birthdates:

```swift
enum Birthdate {
    static func string(from date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String  // "1996-05-14"
    static func date(from string: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date?
    static func age(from birthdate: Date, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int
    static let minimumAge: Int   // 18
}
```

---

## 10. Enums (all `String, Codable, Sendable, CaseIterable, Identifiable`, each with `var displayName: String`)

| Type | Cases | Extras |
|---|---|---|
| `Gender` | `.woman`, `.man`, `.nonbinary` | `pluralDisplayName` ("Women", "Men", "Nonbinary people") |
| `Intention` | `.longTerm`, `.shortTerm`, `.marriage`, `.figuringOut` | |
| `ChildrenStatus` | `.hasWantsMore`, `.hasDone`, `.wants`, `.doesntWant`, `.open` | |
| `Religion` | `.agnostic`, `.atheist`, `.buddhist`, `.christian`, `.hindu`, `.jewish`, `.muslim`, `.spiritual`, `.other` | |
| `Education` | `.highSchool`, `.someCollege`, `.bachelors`, `.masters`, `.doctorate` | `rank: Int` (0…4) |
| `Smoking` | `.never`, `.sometimes`, `.regularly` | |
| `Drinking` | `.never`, `.socially`, `.regularly` | |
| `ReportReason` | `.nudity`, `.sexualLanguage`, `.harassment`, `.underage`, `.fakeProfile`, `.spam`, `.other` | |
| `DateEndReason` | `.timer`, `.partnerLeft`, `.youLeft`, `.moderation`, `.disconnect` | |
| `DateDecision` | `.yes`, `.no` | |
| `DateOutcome` | `.match`, `.noMatch` | |
| `ModerationCategory` | `.nudity`, `.sexualLanguage` | |
| `ModerationAction` | `.none`, `.warn`, `.end` | write `ModerationAction.none` in full |
| `CallRole` | `.caller`, `.callee` | |

Pickers: `ForEach(Intention.allCases) { option in Text(option.displayName) }` (`id` is the raw value).

Also with `displayName`: `VideoConnectionState`, `CameraPosition`, `SocketConnectionState`,
`CallEndReason`, `PermissionKind`.

```swift
enum PermissionIssue: String, Sendable, Equatable, Identifiable {
    case camera, microphone, cameraAndMicrophone
    var title: String { get }      // "Camera is off"
    var message: String { get }    // full sentence, mentions Settings
}
```

---

## 11. Errors

```swift
enum TempoError: Error, Equatable, Sendable {
    case notAuthenticated
    case network
    case server(status: Int, code: String, message: String)
    case decoding
    case suspended(until: Date?)
    case permissionDenied(PermissionKind)
    case purchaseFailed(String)
    case cancelled
    case unknown(String)

    var userMessage: String { get }     // always presentable
    var isRetryable: Bool { get }       // show "Try again" when true
    var serverCode: String? { get }
}

enum PermissionKind: String, Sendable, Equatable, CaseIterable, Identifiable {
    case camera, microphone, speech, location, notifications
    var displayName: String { get }
}
```

Every store exposes failures as `lastError: TempoError?` (settable: set it to nil when the alert or
toast is dismissed). `PremiumStore` uses `productError` and `purchaseState == .failed(error)`;
`ChatThread` uses `loadError`. An expired session signs the user out automatically.

---

## 12. Clock math (pure functions; drive every countdown from an end timestamp)

```swift
enum DateClock {
    static func remaining(until end: Date, now: Date = Date()) -> TimeInterval           // never negative
    static func fractionRemaining(endsAt: Date, duration: TimeInterval, now: Date = Date()) -> Double   // 1 → 0
    static func fractionElapsed(endsAt: Date, duration: TimeInterval, now: Date = Date()) -> Double     // 0 → 1
    static func wholeSeconds(_ remaining: TimeInterval) -> Int                             // rounded up
    static func clockText(_ remaining: TimeInterval) -> String                             // "3:12"
    static func isFinalStretch(remaining: TimeInterval, threshold: TimeInterval = 30) -> Bool
}
```

Inside a `TimelineView(.periodic(from: .now, by: 0.25))`:

```swift
let remaining = DateClock.remaining(until: endsAt, now: context.date)
Text(DateClock.clockText(remaining))
```

`dateStore.endsAt`, `icebreaker.turnEndsAt`, the `deadline` of `.deciding` and `nextCountdownEndsAt` are
already on the device's clock: compare them with `Date()` / `context.date` directly.

---

## 13. Misc

```swift
enum Brand {
    static let name: String          // "Tempo"; never write the name as a literal
    static let premiumName: String   // "Tempo Premium"
}

@MainActor enum Haptics {
    static func light()
    static func medium()
    static func heavy()
    static func tick()
    static func success()
    static func warning()
    static func error()
}

enum SystemSettings { @MainActor static func open() }
```

---

## 14. Rules that keep it compiling

1. Stores are `@MainActor`. Views are too, so call sync intents directly and async ones in `Task { await … }`.
2. Do not create stores or services yourself; read them from the environment.
3. `DatePhase`, `CallState`, `PurchaseState` have associated values. Match with `switch` or
   `if case .deciding(let partner, let deadline) = dateStore.phase { … }`. Plain cases compare with `==`
   (`dateStore.phase == .live`).
4. `user.gender` is optional; `user.birthdate` is a `String`. Use `user.age` for display.
5. Properties marked `private(set)` cannot be bound or assigned; use the intent next to them.
6. `ModerationAction.none` must be written in full when the value could be optional.
7. Never hold timers that count seconds. Use the end timestamps with `TimelineView`.
8. Do not call `debugSetPhase` / `debugSetCallState` outside `#Preview`.

---

## Additions (after reconciling with the backend; nothing above was renamed or removed)

```swift
// ProfileUpdate: new optional field, last parameter of init (defaults to nil)
var tzOffsetMinutes: Int?            // minutes east of UTC; Core sends it for you

// User
static let strikesToSuspend: Int     // 3
var isSuspended: Bool { get }        // now also true at strikes >= 3 (suspension pending review)

// SessionStore
func syncTimeZone() async            // called by Core at sign-in and on foreground; UI never needs it
```

## Additions (integration pass; nothing above was renamed or removed)

```swift
// ProfileUpdate: clearing answered basics. Last parameter of init, defaults to [].
enum ClearableProfileField: String, Sendable, Equatable, Hashable, CaseIterable {
    case intention, children, religion, education, smoking, drinking
}
var clearing: Set<ClearableProfileField>   // each named field that is nil is sent as `"field": null`

// SessionStore
@discardableResult func refreshUser() async -> Bool   // was `async` with no result
var isSuspended: Bool { get }        // a pushed timed suspension whose `until` has passed no longer counts

// DateStore
func requestMediaAccess() async -> PermissionIssue?

// VideoCallService (stores only; Features keep using LocalVideoView / RemoteVideoView)
var isCallAudioSilenced: Bool { get }
func setCallAudioSilenced(_ silenced: Bool)   // both directions; cleared by startCall and endCall
```

Behaviour changes UI should know (no signature changes):
- **Suspension.** `session.isSuspended` is true for a timed suspension, for 3 strikes, and after the
  server's `account.suspended` notice (`session.suspension?.reason` is a ready-to-show sentence). That
  notice arrives on every connect; it no longer opens the date flow while `dateStore.phase == .idle`.
  `refreshUser()` ("Check again", and every return to the foreground) clears `session.suspension` when
  `GET /v1/me` shows the account in good standing.
  The Tonight tab should show the suspended state from `session.isSuspended`. `goOnline()` on a
  suspended account lands in `.suspended(reason:)`.
- **Photos.** The server attaches an uploaded photo to the profile at once (max 6; the 7th fails with a
  ready-to-show `lastError`). After onboarding, `uploadPhoto` refreshes `session.user`.
- **Searching on two devices.** If the account goes online elsewhere, this device returns to `.idle`
  with `dateStore.lastError` set.
- **Calls.** Calling someone who is offline ends as `.ended(_, .noAnswer)`, busy as `.declined`; both
  also set `matchesStore.lastError` with the server's sentence. Calls are now moderated like dates; if a
  call is ended for safety, the offender gets `matchesStore.lastError`.
- **Socket errors** `not_in_date` / `not_your_turn` (normal races) no longer set `dateStore.lastError`.
- Server limits to respect in forms: bio and names are validated server-side; chat text 1–2000
  characters; `ageMin` 18–99 with `ageMin <= ageMax`; `maxDistanceKm` 1–20000; birthdate cannot change
  after onboarding (do not offer editing it).


---

## Match agents

One agent per match. It reads only that conversation and prepares a status line plus items.

```swift
struct AgentBrief: Sendable, Equatable, Identifiable {
    enum Standing { case fresh, yourMove, waiting, quiet, planning }
    let id: String                 // the match id
    var standing: Standing
    var status: String             // "Lena wrote 26 minutes ago. Your move."
    var items: [AgentItem]
    var updatedAt: Date
}
struct AgentItem: Sendable, Equatable, Identifiable {
    enum Kind {
        case suggestion(text: String)                               // a reply to send
        case plan(title: String, start: Date, duration: TimeInterval)   // for the calendar
        case reminder(title: String, at: Date)                      // for the calendar
        case note(text: String)                                     // not actionable
    }
    let id: String
    var kind: Kind
}

protocol MatchAgentService: Sendable { func brief(for context: AgentContext) async throws -> AgentBrief }
struct LocalMatchAgentService: MatchAgentService   // rules on the device; no language model, nothing leaves the phone
protocol CalendarService: Sendable { func addEvent(title: String, start: Date, duration: TimeInterval, notes: String?) async throws }
// LiveCalendarService (EventKit, write-only access) / MockCalendarService (demo: writes nothing)

@MainActor @Observable
final class AgentStore {                                   // `@Environment(AgentStore.self)`
    private(set) var briefs: [String: AgentBrief]          // by match id
    private(set) var thinking: Set<String>                 // match ids being refreshed
    private(set) var done: Set<String>                     // item ids already in the calendar
    private(set) var adding: Set<String>
    func brief(for matchId: String) -> AgentBrief?
    func items(for matchId: String) -> [AgentItem]         // minus dismissed ones
    func refreshAll() async                                // call when `matchesStore.matches` changes
    func refresh(matchId: String) async
    func dismiss(_ item: AgentItem)
    @discardableResult func addToCalendar(_ item: AgentItem, partnerName: String) async -> CalendarError?
}
```

- Suggestions are placed in the composer, never sent: `router.openChat(matchId:draft:)`.
- `LocalMatchAgentService` is the only implementation. A language-model agent needs a server endpoint
  (conversation in, `AgentBrief` out) and an implementation of `MatchAgentService` that calls it.
- `done` and `dismissed` live in memory only; they reset on relaunch.

```swift
struct AgentPersona: Sendable, Equatable {       // the agent's character, generated from the match id
    var name: String                              // "Pip"
    var temper: Temper                            // .optimist, .planner, .romantic, .realist, .wit, .nightOwl, .gentle, .bold
    var hue: Hue                                  // 10 colours
    var body: Body                                // 8 silhouettes: round, squircle, bean, drop, bun, gumdrop, scallop, pebble
    var eyes: Eyes; var mouth: Mouth; var top: Top; var tilt: Double; var hasCheeks: Bool
    var label: String { get }                     // "Pip · the planner"
    static func generate(seed: String) -> AgentPersona   // same seed, same character
    static func cast(for seeds: [String]) -> [String: AgentPersona]   // a list's personas, avoiding repeated colour, shape and temper
}
```
`temper.nudge` / `temper.patience` are the asides shown after the agent's status line.
Draw one with `AgentBuddy(persona:size:isThinking:)` (DesignSystem).

`ChatVoice` (`.me`, `.dot`, `.together`) is who is writing in a chat: `agents.voice(for:)` /
`setVoice(_:for:)` (in memory, default `.together`), `agents.suggestions(for:)`. In `.dot` the agent
drafts into the composer; nothing is ever sent without the user pressing send.

## Checkpoint (after the first question)

Wire: server sends `date.checkpoint {dateId, deadline}` when both have answered question 1; clients
answer `date.continue {dateId, choice: "continue" | "end"}`; then either `date.resumed {dateId, endsAt}`
(both continued; the clock was paused) or `date.ended {reason: "checkpoint"}` (one stopped, or no
answer by the deadline). Server setting `CHECKPOINT_WINDOW_SEC` (10; 0 turns it off).

```swift
private(set) var checkpoint: CheckpointState?      // DateStore; non-nil while the vote is open, phase stays .live
struct CheckpointState { var deadline: Date; var myChoice: CheckpointChoice? }
enum CheckpointChoice { case carryOn, end }
func voteAtCheckpoint(_ choice: CheckpointChoice)  // first choice stands
```
While it is open: `endsAt` and `icebreaker` are nil and call audio is silenced both ways.
