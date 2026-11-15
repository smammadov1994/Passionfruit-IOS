import SwiftUI

/// The post-match 1:1 video call, rendered from `MatchesStore.callState`: ringing (outgoing or
/// incoming), connecting, live, ended. Present it full screen while `callState.isPresented`.
/// It uses the same chrome as a speed date, without the clock or the icebreaker.
struct MatchCallView: View {
    private let match: Match

    @Environment(MatchesStore.self) private var matchesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isReportPresented: Bool = false
    @State private var toast: TempoToastItem? = nil

    init(match: Match) {
        self.match = match
    }

    var body: some View {
        let stage: MatchCallStage = MatchCallStage(state: matchesStore.callState)
        return ZStack {
            InkBackground()
            if stage.showsVideo {
                CallVideoBackdrop(isVideoVisible: true, isDimmed: false)
                    .transition(AnyTransition.opacity)
                CallSelfView(isCameraOff: matchesStore.isCallCameraOff, topInset: 56, bottomInset: 96)
                    .transition(AnyTransition.opacity)
            }
            stageContent(stage)
            permissionLayer
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: stage)
        .tempoToast(item: $toast)
        .keepsScreenAwake(stage.keepsScreenAwake)
        // Dark status-bar text is unreadable over live video; hide it there.
        .statusBarHidden(stage.showsVideo)
        .sheet(isPresented: $isReportPresented) {
            ReportSheet(
                partnerName: partner.firstName,
                onSubmit: { reason, details in
                    sendReport(reason: reason, details: details)
                },
                onBlock: {
                    blockPartner()
                }
            )
        }
        .onChange(of: stage) { _, newStage in
            announce(newStage)
        }
    }

    // MARK: Stages

    private var partner: Partner {
        matchesStore.callPartner ?? match.partner
    }

    @ViewBuilder
    private func stageContent(_ stage: MatchCallStage) -> some View {
        switch stage {
        case .closed:
            Color.clear
        case .outgoing:
            MatchCallRingingView(partner: partner, isIncoming: false)
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .incoming:
            MatchCallRingingView(partner: partner, isIncoming: true)
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .connecting:
            MatchCallLiveView(partner: partner, isConnecting: true, onReport: presentReport)
                .transition(AnyTransition.opacity)
        case .active:
            MatchCallLiveView(partner: partner, isConnecting: false, onReport: presentReport)
                .transition(AnyTransition.opacity)
        case .ended(let reason):
            MatchCallEndedView(partner: partner, reason: reason)
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var permissionLayer: some View {
        if let issue = matchesStore.callPermissionIssue {
            CallPermissionView(
                issue: issue,
                dismissTitle: "Not now",
                onOpenSettings: { matchesStore.openSettings() },
                onDismiss: { matchesStore.dismissCallPermissionIssue() }
            )
            .background { InkBackground() }
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
    }

    // MARK: Behaviour

    private func presentReport() {
        isReportPresented = true
    }

    private func sendReport(reason: ReportReason, details: String?) {
        let matchId: String = match.id
        let store: MatchesStore = matchesStore
        Task { @MainActor in
            await store.report(matchId: matchId, reason: reason, details: details)
        }
    }

    private func blockPartner() {
        let matchId: String = match.id
        let name: String = partner.firstName
        let store: MatchesStore = matchesStore
        store.endCall()
        Task { @MainActor in
            let blocked: Bool = await store.block(matchId: matchId)
            if blocked {
                toast = TempoToastItem("\(name) is blocked.", systemImage: "hand.raised")
            }
        }
    }

    private func announce(_ stage: MatchCallStage) {
        let name: String = partner.firstName
        switch stage {
        case .closed:
            break
        case .outgoing:
            CallAnnouncer.announce("Calling \(name).")
        case .incoming:
            CallAnnouncer.announce("\(name) is calling.")
        case .connecting:
            CallAnnouncer.announce("Connecting to \(name).")
        case .active:
            CallAnnouncer.announce("You're on a call with \(name).")
        case .ended(let reason):
            CallAnnouncer.announce(reason.displayName)
        }
    }
}

// MARK: - Stage

/// `CallState` without the match id, so views can switch and animate on it.
enum MatchCallStage: Hashable {
    case closed
    case outgoing
    case incoming
    case connecting
    case active
    case ended(reason: CallEndReason)

    init(state: CallState) {
        switch state {
        case .idle:
            self = .closed
        case .outgoing:
            self = .outgoing
        case .incoming:
            self = .incoming
        case .connecting:
            self = .connecting
        case .active:
            self = .active
        case .ended(_, let reason):
            self = .ended(reason: reason)
        }
    }

    var showsVideo: Bool {
        switch self {
        case .connecting, .active:
            return true
        case .closed, .outgoing, .incoming, .ended:
            return false
        }
    }

    var keepsScreenAwake: Bool {
        switch self {
        case .outgoing, .incoming, .connecting, .active:
            return true
        case .closed, .ended:
            return false
        }
    }
}

// MARK: - Ringing

private struct MatchCallRingingView: View {
    let partner: Partner
    let isIncoming: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(MatchesStore.self) private var matchesStore

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            AvatarView(
                url: environment.imageCache.resolve(partner.photoUrl),
                name: partner.firstName,
                size: 124,
                ring: AvatarRing.ember
            )
            .padding(.leading, 5)
            titles
            Spacer(minLength: TempoSpacing.lg)
            Spacer(minLength: 0)
            actions
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Eyebrow(isIncoming ? "Video call" : "Calling")
            Text(partner.firstName)
                .tempoText(.displayM)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            if isIncoming {
                Text("\(partner.firstName) would like to see you again.")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: TempoSpacing.xs) {
                    Text("Ringing")
                        .tempoText(.body)
                        .foregroundStyle(Color.tempo.textSecondary)
                    LoadingDots(color: Color.tempo.textSecondary, dotSize: 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        if isIncoming {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton("Answer", systemImage: "video") {
                    accept()
                }
                TempoButton("Not right now", variant: TempoButtonVariant.ghost) {
                    matchesStore.declineCall()
                }
            }
        } else {
            TempoButton("Cancel", variant: TempoButtonVariant.secondary) {
                matchesStore.endCall()
            }
        }
    }

    private func accept() {
        let store: MatchesStore = matchesStore
        Task { @MainActor in
            await store.acceptCall()
        }
    }
}

// MARK: - Live

private struct MatchCallLiveView: View {
    let partner: Partner
    let isConnecting: Bool
    let onReport: () -> Void

    @Environment(MatchesStore.self) private var matchesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                CallPartnerLabel(title: partner.nameAndAge, subtitle: partner.locationLine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Leaves the top-trailing corner to the self view.
                Color.clear
                    .frame(width: TempoSize.pip.width, height: 1)
            }
            statusRow
            Spacer(minLength: 0)
            CallControlBar(
                isMicMuted: matchesStore.isCallMicMuted,
                isCameraOff: matchesStore.isCallCameraOff,
                onToggleMic: { matchesStore.toggleCallMic() },
                onToggleCamera: { matchesStore.toggleCallCamera() },
                onFlip: { matchesStore.flipCallCamera() },
                onReport: onReport,
                onLeave: { matchesStore.endCall() }
            )
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xs)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: isConnecting)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: matchesStore.isCallMicMuted)
    }

    private var statusRow: some View {
        HStack(spacing: TempoSpacing.xs) {
            if isConnecting {
                CallStatusPill(text: VideoConnectionState.connecting.displayName, showsActivity: true)
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
            if matchesStore.isCallMicMuted {
                CallStatusPill(text: "You're muted", systemImage: "mic.slash")
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Ended

private struct MatchCallEndedView: View {
    let partner: Partner
    let reason: CallEndReason

    @Environment(MatchesStore.self) private var matchesStore

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(reason.displayName)
                    .tempoText(.displayM)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(detail)
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: TempoSpacing.lg)
            Spacer(minLength: 0)
            TempoButton("Back to chat", variant: TempoButtonVariant.secondary) {
                matchesStore.dismissCall()
            }
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task {
            await closeSoon()
        }
    }

    private var detail: String {
        switch reason {
        case .ended:
            return "Good to see \(partner.firstName) again."
        case .declined:
            return "\(partner.firstName) can't talk at the moment. A message might land better."
        case .noAnswer:
            return "\(partner.firstName) didn't pick up. Try again a little later."
        case .failed:
            return "The video wouldn't connect. Check your connection and try again."
        }
    }

    /// The ended state is a brief note, not a destination: it closes by itself.
    @MainActor
    private func closeSoon() async {
        do {
            try await Task.sleep(for: Duration.seconds(2.5))
        } catch {
            return
        }
        matchesStore.dismissCall()
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum MatchCallPreview {
    static let fallback: Match = Match(
        id: "demo-match-lena",
        partner: Partner(id: "preview-partner", firstName: "Lena", age: 30, city: "Brooklyn"),
        matchedAt: Date()
    )

    static func screen(_ make: (String) -> CallState) -> some View {
        let seeded: AppEnvironment = AppEnvironment.demo()
        let match: Match = seeded.matches.matches.first ?? fallback
        seeded.matches.debugSetCallState(make(match.id))
        return MatchCallView(match: match)
            .tempoEnvironment(seeded)
            .preferredColorScheme(.light)
    }
}

#Preview("Call · outgoing") {
    MatchCallPreview.screen { id in CallState.outgoing(matchId: id) }
}

#Preview("Call · incoming") {
    MatchCallPreview.screen { id in CallState.incoming(matchId: id) }
}

#Preview("Call · connecting") {
    MatchCallPreview.screen { id in CallState.connecting(matchId: id) }
}

#Preview("Call · live") {
    MatchCallPreview.screen { id in CallState.active(matchId: id) }
}

#Preview("Call · no answer") {
    MatchCallPreview.screen { id in CallState.ended(matchId: id, reason: CallEndReason.noAnswer) }
}
#endif
