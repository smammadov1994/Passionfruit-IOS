import Foundation
import Observation
import SwiftUI

enum AppMode: String, Sendable, Equatable {
    /// Everything mocked. Runs in the Simulator with no backend.
    case demo
    /// Real backend at `TempoAPIBaseURL`.
    case live
}

/// Where a notification tap wants to go. `RootView` reads `AppEnvironment.pendingRoute`,
/// navigates, and sets it back to nil.
enum AppRoute: Sendable, Equatable {
    case tonight
    case matches
    case chat(matchId: String)
    case you
}

/// The dependency container: every service and every store. Injected with `.tempoEnvironment(_:)`.
@MainActor
@Observable
final class AppEnvironment {
    let mode: AppMode

    // Services
    let api: any APIClient
    let socket: any RealtimeSocket
    let video: any VideoCallService
    let moderation: any ModerationService
    let purchases: any PurchaseService
    let push: any PushService
    let location: any LocationService
    let auth: any AuthService
    let permissions: any MediaPermissions
    let tokenStore: any TokenStore
    let imageCache: ImageCache

    // Stores
    let config: ConfigStore
    let session: SessionStore
    let dates: DateStore
    let matches: MatchesStore
    let premium: PremiumStore
    /// One agent per match (see `AgentStore`).
    let agents: AgentStore

    /// Set when the user taps a notification. Consume it in `RootView` and set it to nil.
    var pendingRoute: AppRoute?
    private(set) var hasStarted: Bool = false

    /// The environment the running app uses (for the app delegate).
    static weak var current: AppEnvironment?

    var isDemo: Bool { mode == .demo }

    init(
        mode: AppMode,
        api: any APIClient,
        socket: any RealtimeSocket,
        video: any VideoCallService,
        moderation: any ModerationService,
        purchases: any PurchaseService,
        push: any PushService,
        location: any LocationService,
        auth: any AuthService,
        permissions: any MediaPermissions,
        tokenStore: any TokenStore,
        imageCache: ImageCache,
        initialUser: User? = nil,
        initialConfig: AppConfig = AppConfig.fallback
    ) {
        let configStore = ConfigStore(api: api, initial: initialConfig)
        let sessionStore = SessionStore(
            api: api,
            auth: auth,
            tokenStore: tokenStore,
            socket: socket,
            location: location,
            push: push,
            initialUser: initialUser
        )
        let dateStore = DateStore(
            socket: socket,
            api: api,
            video: video,
            moderation: moderation,
            permissions: permissions,
            config: configStore,
            session: sessionStore
        )
        let matchesStore = MatchesStore(
            api: api,
            socket: socket,
            video: video,
            permissions: permissions,
            config: configStore,
            session: sessionStore,
            moderation: moderation
        )
        let premiumStore = PremiumStore(purchases: purchases, api: api, session: sessionStore)

        self.mode = mode
        self.api = api
        self.socket = socket
        self.video = video
        self.moderation = moderation
        self.purchases = purchases
        self.push = push
        self.location = location
        self.auth = auth
        self.permissions = permissions
        self.tokenStore = tokenStore
        self.imageCache = imageCache
        self.config = configStore
        self.session = sessionStore
        self.dates = dateStore
        self.matches = matchesStore
        self.premium = premiumStore
        // The on-device agent in both modes for now; only the calendar differs (demo writes nothing).
        self.agents = AgentStore(
            service: LocalMatchAgentService(),
            calendar: mode == .demo ? MockCalendarService() : LiveCalendarService(),
            matches: matchesStore,
            session: sessionStore,
            config: configStore
        )

        dateStore.onMatch = { [weak matchesStore] (match: Match) in
            matchesStore?.insert(match)
        }
        dateStore.isBlockedByCall = { [weak matchesStore] () -> Bool in
            matchesStore?.callState.isPresented ?? false
        }
        matchesStore.isBlockedByDate = { [weak dateStore] () -> Bool in
            dateStore?.isActive ?? false
        }
        sessionStore.onSignedIn = { [weak self] in
            self?.loadSignedInData()
        }
        sessionStore.onSignedOut = { [weak dateStore, weak matchesStore] in
            dateStore?.reset()
            matchesStore?.reset()
        }
    }

    // MARK: Lifecycle

    /// Loads config and restores the session. Idempotent; `.tempoEnvironment(_:)` calls it for you.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        premium.start()
        let wasSignedIn: Bool = session.isSignedIn
        async let configLoad: Void = config.load()
        await session.bootstrap()
        await configLoad
        if wasSignedIn {
            // A pre-signed-in environment (previews) never fires `onSignedIn`.
            loadSignedInData()
        }
    }

    /// Refreshes what may have changed while the app was in the background.
    func didBecomeActive() {
        guard hasStarted, session.isSignedIn else { return }
        socket.connect()
        Task { [weak self] in
            guard let self else { return }
            await self.session.syncTimeZone()
            await self.session.refreshUser()
            await self.matches.resync()
            if !self.dates.isActive {
                await self.dates.refreshUsage()
                await self.dates.refreshOnlineCount()
            }
        }
    }

    /// Routes a notification tap. A `matchId` in the payload opens that chat; anything else opens Tonight.
    func handleNotificationTap(matchId: String?) {
        if let matchId, !matchId.isEmpty {
            pendingRoute = .chat(matchId: matchId)
        } else {
            pendingRoute = .tonight
        }
    }

    private func loadSignedInData() {
        Task { [weak self] in
            guard let self else { return }
            // Signed in now, so this fetch includes the user's TURN credentials.
            await self.config.load()
            await self.matches.load()
            await self.dates.refreshUsage()
            await self.dates.refreshOnlineCount()
            await self.premium.syncEntitlement()
        }
    }

    // MARK: Factories

    /// Demo mode: all services mocked. The default (`demo()`) is signed in and onboarded, with a few
    /// seeded matches, which is what previews want.
    /// - Parameters:
    ///   - signedIn: start signed in (ignored when `persist` is true; the stored session decides).
    ///   - onboarded: whether the demo account has finished onboarding.
    ///   - persist: keep the demo account between launches (used by the app, not by previews).
    ///   - config: demo tunables (date length, pairing delay, `autoScript`, …).
    static func demo(
        signedIn: Bool = true,
        onboarded: Bool = true,
        persist: Bool = false,
        config: DemoConfig = DemoConfig()
    ) -> AppEnvironment {
        let world = DemoWorld(
            config: config,
            onboarded: onboarded,
            seedMatches: true,
            persistenceKey: persist ? DemoWorld.defaultPersistenceKey : nil
        )
        let api = MockAPIClient(world: world)
        let socket = MockRealtimeSocket(world: world)
        world.setReplySink { [weak socket] (message: Message) in
            Task { @MainActor in
                socket?.emit(.chatMessage(message))
            }
        }

        let tokenStore: any TokenStore
        var initialUser: User?
        if persist {
            tokenStore = KeychainTokenStore(keychain: KeychainStore(service: "com.tempo.app.demo"))
        } else {
            tokenStore = InMemoryTokenStore(token: signedIn ? DemoWorld.demoToken : nil)
            if signedIn {
                initialUser = world.read { $0.user }
            }
        }

        let environment = AppEnvironment(
            mode: .demo,
            api: api,
            socket: socket,
            video: MockVideoCallService(),
            moderation: MockModerationService(),
            purchases: MockPurchaseService(),
            push: MockPushService(),
            location: MockLocationService(),
            auth: MockAuthService(api: api),
            permissions: MockMediaPermissions(),
            tokenStore: tokenStore,
            imageCache: ImageCache(baseURL: nil),
            initialUser: initialUser,
            initialConfig: config.appConfig
        )
        if let initialUser, initialUser.onboardingComplete {
            // Previews get their matches without waiting for `start()`.
            let seeded: [Match] = world.read { $0.matches }
            for match in seeded {
                environment.matches.insert(match)
            }
            socket.connect()
        }
        return environment
    }

    /// Live mode: real backend at the Info.plist key `TempoAPIBaseURL`.
    static func live() -> AppEnvironment {
        let baseURL: URL = apiBaseURL()
        let tokenStore = KeychainTokenStore()
        let tokenProvider: @Sendable () -> String? = {
            tokenStore.token
        }
        let api = LiveAPIClient(baseURL: baseURL, tokenProvider: tokenProvider)
        let socket = LiveRealtimeSocket(baseURL: baseURL, tokenProvider: tokenProvider)
        return AppEnvironment(
            mode: .live,
            api: api,
            socket: socket,
            video: LiveVideoCallService(),
            moderation: LiveModerationService(api: api),
            purchases: LivePurchaseService(),
            push: LivePushService(api: api, tokenStore: tokenStore),
            location: LiveLocationService(),
            auth: LiveAuthService(api: api),
            permissions: LiveMediaPermissions(),
            tokenStore: tokenStore,
            imageCache: ImageCache(baseURL: baseURL)
        )
    }

    /// Picks the mode: launch argument `-demo` or `-live` wins; otherwise Debug builds run the demo
    /// and Release builds run live.
    static func makeDefault() -> AppEnvironment {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        if arguments.contains("-live") {
            return live()
        }
        #if DEBUG
        // `-demoReady`: demo mode already signed in and onboarded, to look at screens quickly.
        if arguments.contains("-demoReady") {
            return demo(signedIn: true, onboarded: true)
        }
        #endif
        if arguments.contains("-demo") {
            return demo(signedIn: false, onboarded: false, persist: true)
        }
        #if DEBUG
        return demo(signedIn: false, onboarded: false, persist: true)
        #else
        return live()
        #endif
    }

    static func apiBaseURL(bundle: Bundle = Bundle.main) -> URL {
        let fallback: URL = URL(string: "http://localhost:8080") ?? URL(fileURLWithPath: "/")
        guard let raw = bundle.object(forInfoDictionaryKey: "TempoAPIBaseURL") as? String else {
            return fallback
        }
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return fallback
        }
        return url
    }
}

// MARK: - SwiftUI injection

private struct TempoEnvironmentModifier: ViewModifier {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(environment)
            .environment(environment.config)
            .environment(environment.session)
            .environment(environment.dates)
            .environment(environment.matches)
            .environment(environment.premium)
            .environment(environment.agents)
            .task {
                await environment.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    environment.didBecomeActive()
                }
            }
    }
}

extension View {
    /// Injects `AppEnvironment` and every store, and starts the environment.
    /// The app applies it to `RootView()`; previews apply it to the view under preview:
    /// `SomeView().tempoEnvironment(AppEnvironment.demo())`.
    @MainActor
    func tempoEnvironment(_ environment: AppEnvironment) -> some View {
        modifier(TempoEnvironmentModifier(environment: environment))
    }
}
