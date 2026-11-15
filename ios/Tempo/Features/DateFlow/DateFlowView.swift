import SwiftUI

/// The whole speed-date experience, rendered from `DateStore.phase`.
///
/// One persistent container: the ink, the remote video and the self view sit at the bottom
/// and stay mounted while the phase-specific screen on top is replaced, so the video never
/// flickers between live, the Verdict and the sealed state.
///
/// `TabShell` presents it as a `fullScreenCover` while `dateStore.isActive`. Blocked camera or
/// microphone access never reaches this view: `goOnline()` raises `dateStore.permissionIssue`
/// while the phase is still `.idle`, so the Tonight tab (the only place that goes online) shows it.
struct DateFlowView: View {
    @Environment(DateStore.self) private var dateStore
    @Environment(PremiumStore.self) private var premiumStore
    @Environment(ConfigStore.self) private var configStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var reportRequest: DateReportRequest? = nil
    @State private var isPaywallPresented: Bool = false
    @State private var isRulesPresented: Bool = false
    @State private var toast: TempoToastItem? = nil
    @State private var wasAwayDuringDate: Bool = false

    init() {}

    var body: some View {
        let moment: DateFlowMoment = DateFlowMoment(phase: dateStore.phase)
        return presented
            .onAppear {
                announce(moment)
            }
            .onChange(of: moment) { _, newMoment in
                announce(newMoment)
            }
            .onChange(of: dateStore.partner?.id) { _, newId in
                partnerChanged(newId)
            }
            .onChange(of: premiumStore.isPremium) { _, isPremium in
                premiumChanged(isPremium)
            }
            .onChange(of: scenePhase) { _, newPhase in
                sceneChanged(newPhase)
            }
    }

    // MARK: Layers

    private var canvas: some View {
        let stage: DateFlowStage = DateFlowStage(phase: dateStore.phase)
        return DateFlowCanvas(
            stage: stage,
            onReport: presentReport,
            onShowPaywall: { isPaywallPresented = true },
            onShowRules: { isRulesPresented = true }
        )
        .tempoToast(item: $toast)
        .keepsScreenAwake(stage.keepsScreenAwake)
        // The app is light, so the status bar is dark text: unreadable over live video. It is
        // hidden there and comes back with the white screens (and the white-veiled Verdict).
        .statusBarHidden(stage.showsVideo && !stage.dimsVideo)
    }

    private var presented: some View {
        canvas
            .sheet(item: $reportRequest) { request in
                reportSheet(request)
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView()
            }
            .sheet(isPresented: $isRulesPresented) {
                CommunityRulesSheet()
            }
    }

    // MARK: Report and block

    private func reportSheet(_ request: DateReportRequest) -> some View {
        ReportSheet(
            partnerName: request.partner.firstName,
            onSubmit: { reason, details in
                sendReport(request, reason: reason, details: details)
            },
            onBlock: {
                block(request)
            },
            onLeave: leaveAction(for: request)
        )
    }

    /// "Leave this date" is offered only for a report opened while the date was running.
    private func leaveAction(for request: DateReportRequest) -> (() -> Void)? {
        guard request.offersLeave else { return nil }
        let store: DateStore = dateStore
        return {
            store.leaveDate()
        }
    }

    private func presentReport() {
        guard let partner = dateStore.partner else { return }
        reportRequest = DateReportRequest(partner: partner, offersLeave: dateStore.isInCall)
    }

    /// The store reports "the current or just-finished partner". That is still the person the
    /// sheet was opened for unless someone new has been paired in the meantime.
    private func isStillTarget(_ partner: Partner) -> Bool {
        guard let current = dateStore.partner else { return true }
        return current.id == partner.id
    }

    private func sendReport(_ request: DateReportRequest, reason: ReportReason, details: String?) {
        guard isStillTarget(request.partner) else {
            toast = TempoToastItem("That date is over, so the report wasn't sent.", systemImage: "exclamationmark.circle", tone: TempoTone.amber)
            return
        }
        let store: DateStore = dateStore
        Task { @MainActor in
            // A failure lands in `dateStore.lastError`, which the flow shows as a banner.
            await store.report(reason: reason, details: details)
        }
    }

    private func block(_ request: DateReportRequest) {
        guard isStillTarget(request.partner) else { return }
        let name: String = request.partner.firstName
        let store: DateStore = dateStore
        Task { @MainActor in
            let blocked: Bool = await store.blockPartner()
            if blocked {
                toast = TempoToastItem("\(name) is blocked. You won't be paired again.", systemImage: "hand.raised")
            }
        }
    }

    // MARK: Reactions

    private func announce(_ moment: DateFlowMoment) {
        let line: String = DateFlowCopy.announcement(
            for: moment,
            partnerName: dateStore.partner?.firstName,
            decisionSeconds: Int(configStore.decisionWindow)
        )
        CallAnnouncer.announce(line)
    }

    /// A report sheet left open across dates must never end up pointing at the next person.
    private func partnerChanged(_ newId: String?) {
        guard let request = reportRequest, let newId else { return }
        if newId != request.partner.id {
            reportRequest = nil
        }
    }

    /// Premium bought from the limit screen: straight back into the queue.
    private func premiumChanged(_ isPremium: Bool) {
        guard isPremium else { return }
        if case .limitReached = dateStore.phase {
            dateStore.continueToNext()
        }
    }

    /// Core keeps a date's audio alive in the background and reconnects on return; if the date
    /// ended while the app was away, the store is already in that phase and the flow shows it.
    /// Coming back to a date that is still running gets a short confirmation.
    private func sceneChanged(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            wasAwayDuringDate = dateStore.isInDate
        case .active:
            guard wasAwayDuringDate else { return }
            wasAwayDuringDate = false
            if dateStore.isInCall {
                toast = TempoToastItem("You're back. The date is still running.", systemImage: "checkmark.circle", tone: TempoTone.mint)
                CallAnnouncer.announce("You're back. The date is still running.")
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

/// Who a report sheet was opened for, and whether it was opened during the call.
struct DateReportRequest: Identifiable {
    let id: UUID = UUID()
    let partner: Partner
    let offersLeave: Bool
}

// MARK: - Canvas

/// The layered container: the white page, video, self view, the screen for the current stage, notices.
private struct DateFlowCanvas: View {
    let stage: DateFlowStage
    let onReport: () -> Void
    let onShowPaywall: () -> Void
    let onShowRules: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            InkBackground()
            if stage.mountsVideo {
                CallVideoBackdrop(isVideoVisible: stage.showsVideo, isDimmed: stage.dimsVideo)
                    .transition(AnyTransition.opacity)
            }
            if stage.showsSelfView {
                CallSelfView(isCameraOff: dateStore.isCameraOff, topInset: 56, bottomInset: 96)
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
            DateFlowStageView(
                stage: stage,
                onReport: onReport,
                onShowPaywall: onShowPaywall,
                onShowRules: onShowRules
            )
            DateFlowErrorBanner(topPadding: stage.showsVideo ? 64 : TempoSpacing.xs, isOverVideo: stage.showsVideo)
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: stage.screen)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: stage.mountsVideo)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: stage.showsSelfView)
    }
}

// MARK: - Stage switch

/// One screen per stage. Every `DatePhase` maps to a stage in `DateFlowStage.init(phase:)`.
private struct DateFlowStageView: View {
    let stage: DateFlowStage
    let onReport: () -> Void
    let onShowPaywall: () -> Void
    let onShowRules: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var replace: AnyTransition {
        AnyTransition.tempoReplace(reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            screen
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var screen: some View {
        switch stage {
        case .closed:
            DateFlowClosedView()
                .transition(AnyTransition.opacity)
        case .lobby(let partner):
            DateLobbyView(partner: partner)
                .transition(replace)
        case .live:
            DateLiveView(onReport: onReport)
                .transition(AnyTransition.opacity)
        case .verdict(let partner, let deadline):
            DateVerdictView(partner: partner, deadline: deadline, onReport: onReport)
                .transition(replace)
        case .matched(let match):
            DateMatchedView(match: match)
                .transition(replace)
        case .interstitial(let kind):
            DateInterstitialView(kind: kind, onReport: onReport, onShowRules: onShowRules)
                .transition(replace)
        case .limit(let resetsAt):
            DateLimitView(resetsAt: resetsAt, onShowPaywall: onShowPaywall)
                .transition(replace)
        case .suspended(let reason):
            DateSuspendedView(reason: reason, onShowRules: onShowRules)
                .transition(replace)
        }
    }
}

/// `.idle` inside the cover: the cover is closing. Nothing to show over the page.
private struct DateFlowClosedView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Notices

/// The store's latest failure, dismissible, at the top of the flow.
private struct DateFlowErrorBanner: View {
    let topPadding: CGFloat
    /// Over video the banner floats: it gets the one soft shadow.
    let isOverVideo: Bool

    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let error = dateStore.lastError {
                ErrorBanner(message: error.userMessage, onDismiss: { dateStore.lastError = nil })
                    .tempoShadow(isOverVideo ? TempoShadow.floating : TempoShadow.none)
                    .tempoScreenPadding()
                    .padding(.top, topPadding)
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.lastError)
    }
}
