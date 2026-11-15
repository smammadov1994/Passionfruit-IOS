import SwiftUI

/// The signed-in app: Tonight, with Matches and You reached from header buttons, plus everything global:
/// the date-flow cover, the paywall sheet, the incoming-call banner, the error toast and
/// notification routes.
struct TabShell: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(MatchesStore.self) private var matchesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var router: AppRouter = AppRouter()
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    var body: some View {
        @Bindable var router = router
        return shell
            .tempoToast(item: $router.toast)
            .sheet(isPresented: $router.isPaywallPresented) {
                PaywallView()
            }
            .fullScreenCover(isPresented: dateFlowBinding) {
                DateFlowView()
                    .interactiveDismissDisabled(true)
            }
            .alert(
                Text(matchesStore.callPermissionIssue?.title ?? ""),
                isPresented: callPermissionBinding,
                actions: { callPermissionActions },
                message: { Text(matchesStore.callPermissionIssue?.message ?? "") }
            )
            .modifier(ShellErrorSurfacing(router: router))
            .onChange(of: environment.pendingRoute, initial: true) { _, route in
                handleRoute(route)
            }
            .environment(router)
            .onDisappear {
                tasks.cancelAll()
            }
    }

    // MARK: Layout

    /// One section at a time, no tab bar: Tonight is home, its heart button opens Matches, and the
    /// cog there opens You. Each of those has a back button in its own header.
    private var shell: some View {
        tabContent
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
            .overlay(alignment: .top) {
                incomingCall
            }
            .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: router.selectedTab)
            .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: matchesStore.callState)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.selectedTab {
        case .tonight:
            TonightView()
        case .matches:
            MatchesView()
        case .you:
            YouView()
        }
    }

    // MARK: Date flow

    /// Open exactly while the date flow is active. A full-screen cover cannot be swiped away;
    /// if the system ever dismisses it, the store is told to go offline so the two stay in step.
    private var dateFlowBinding: Binding<Bool> {
        Binding<Bool>(
            get: { dateStore.isActive },
            set: { isPresented in
                if !isPresented && dateStore.isActive {
                    dateStore.goOffline()
                }
            }
        )
    }

    // MARK: Incoming call

    @ViewBuilder
    private var incomingCall: some View {
        if case .incoming(let matchId) = matchesStore.callState {
            IncomingCallBanner(
                partner: matchesStore.callPartner,
                onAccept: { acceptCall(matchId: matchId) },
                onDecline: { matchesStore.declineCall() }
            )
            .tempoScreenPadding()
            .padding(.top, TempoSpacing.xs)
            .transition(bannerTransition)
        }
    }

    private var bannerTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity)
    }

    private func acceptCall(matchId: String) {
        // The call screen is presented by that match's chat, so go there first.
        router.isPaywallPresented = false
        router.openChat(matchId: matchId)
        tasks.run("acceptCall") {
            await matchesStore.acceptCall()
        }
    }

    private var callPermissionBinding: Binding<Bool> {
        Binding<Bool>(
            get: { matchesStore.callPermissionIssue != nil && !isCallScreenUp },
            set: { isPresented in
                if !isPresented {
                    matchesStore.dismissCallPermissionIssue()
                }
            }
        )
    }

    /// True while a chat is presenting the call screen, which explains permission problems itself.
    private var isCallScreenUp: Bool {
        switch matchesStore.callState {
        case .idle, .incoming:
            return false
        case .outgoing, .connecting, .active, .ended:
            return true
        }
    }

    @ViewBuilder
    private var callPermissionActions: some View {
        Button(String(localized: "Open Settings")) {
            matchesStore.openSettings()
            matchesStore.dismissCallPermissionIssue()
        }
        Button(String(localized: "Not now"), role: .cancel) {
            matchesStore.dismissCallPermissionIssue()
        }
    }

    // MARK: Routes

    private func handleRoute(_ route: AppRoute?) {
        guard let route else { return }
        environment.pendingRoute = nil
        router.isPaywallPresented = false
        switch route {
        case .tonight:
            router.selectedTab = AppTab.tonight
        case .matches:
            router.selectedTab = AppTab.matches
            router.popToRoot(AppTab.matches)
        case .you:
            router.selectedTab = AppTab.you
            router.popToRoot(AppTab.you)
        case .chat(let matchId):
            openChat(matchId: matchId)
        }
    }

    private func openChat(matchId: String) {
        if matchesStore.match(id: matchId) != nil {
            router.openChat(matchId: matchId)
            return
        }
        // The match may be newer than the loaded list (a push for a first message).
        router.selectedTab = AppTab.matches
        router.popToRoot(AppTab.matches)
        tasks.run("route") {
            await matchesStore.load()
            if Task.isCancelled {
                return
            }
            if matchesStore.match(id: matchId) != nil {
                router.openChat(matchId: matchId)
            } else {
                router.showMessage(String(localized: "That conversation isn't available any more."))
            }
        }
    }
}

// MARK: - Global errors

/// Turns failures nobody else handled into a toast. Screens that show an error inline clear the
/// store's `lastError` themselves right after their call, so those are not repeated here.
private struct ShellErrorSurfacing: ViewModifier {
    let router: AppRouter

    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(MatchesStore.self) private var matchesStore

    func body(content: Content) -> some View {
        content
            .onChange(of: session.lastError, initial: true) { _, error in
                guard let error else { return }
                session.lastError = nil
                show(error)
            }
            .onChange(of: matchesStore.lastError, initial: true) { _, error in
                guard let error else { return }
                matchesStore.lastError = nil
                show(error)
            }
            .onChange(of: dateStore.lastError, initial: true) { _, error in
                // While the date flow is open it presents its own errors.
                guard let error, !dateStore.isActive else { return }
                dateStore.lastError = nil
                show(error)
            }
    }

    private func show(_ error: TempoError) {
        if error == TempoError.cancelled {
            return
        }
        router.showError(error.userMessage)
    }
}

// MARK: - Incoming call banner

/// A match is ringing: who it is, Accept and Decline. Shown over every tab and over chats.
struct IncomingCallBanner: View {
    private let partner: Partner?
    private let onAccept: () -> Void
    private let onDecline: () -> Void

    @Environment(AppEnvironment.self) private var environment

    init(partner: Partner?, onAccept: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.partner = partner
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    private var name: String {
        partner?.firstName ?? String(localized: "Your match")
    }

    var body: some View {
        HStack(spacing: TempoSpacing.sm) {
            AvatarView(
                url: environment.imageCache.resolve(partner?.photoUrl),
                name: name,
                size: 44,
                ring: AvatarRing.ember
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .tempoText(.titleS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                Text("Video call")
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(name) is calling on video"))
            IconCircleButton(
                systemImage: "phone.down.fill",
                accessibilityLabel: String(localized: "Decline"),
                kind: IconCircleButtonKind.danger,
                size: 44,
                action: onDecline
            )
            Button(action: onAccept) {
                Image(systemName: "video.fill")
                    .font(Font.system(size: 17, weight: Font.Weight.regular))
                    .foregroundStyle(Color.tempo.onAccent)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(Color.tempo.yes) }
                    .contentShape(Circle())
            }
            .buttonStyle(TempoPressStyle(scale: 0.9))
            .accessibilityLabel(Text("Accept"))
        }
        .padding(.leading, TempoSpacing.sm)
        .padding(.trailing, TempoSpacing.xs)
        .padding(.vertical, TempoSpacing.xs)
        .tempoSurface(in: RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous), isFloating: true)
        .onAppear {
            Haptics.warning()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Shell") {
    TabShell()
        .tempoEnvironment(AppEnvironment.demo())
}

#Preview("Shell, incoming call") {
    let environment = AppEnvironment.demo()
    environment.matches.debugSetCallState(CallState.incoming(matchId: "demo-match-lena"))
    return TabShell()
        .tempoEnvironment(environment)
}
