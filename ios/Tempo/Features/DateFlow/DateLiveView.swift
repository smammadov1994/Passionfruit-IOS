import SwiftUI

/// Everything that sits over the video while the date is running: who, the clock, hints and
/// warnings, the Turn Card and the controls. The video and the self view live in
/// `DateFlowView`, underneath, so they survive phase changes.
struct DateLiveView: View {
    let onReport: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            DateLiveTopBar()
            DateLiveStatusRow()
            warning
            Spacer(minLength: 0)
            DateTurnCardHost()
            controls
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xs)
        .background {
            DateFinalSecondsHaptics(endsAt: dateStore.endsAt)
        }
        .overlay {
            if let checkpoint = dateStore.checkpoint {
                DateCheckpointView(checkpoint: checkpoint)
                    .transition(AnyTransition.opacity)
            }
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.checkpoint != nil)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.moderationWarning?.id)
    }

    @ViewBuilder
    private var warning: some View {
        if let current = dateStore.moderationWarning {
            warningBanner(current)
                .id(current.id)
                .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
        }
    }

    private func warningBanner(_ current: ModerationWarning) -> some View {
        var onDismiss: (() -> Void)? = nil
        if !current.isFinal {
            let store: DateStore = dateStore
            onDismiss = {
                store.dismissModerationWarning()
            }
        }
        let title: String = current.isFinal ? "This date is ending" : "Keep it respectful"
        return ModerationWarningBanner(title: title, message: current.message, onDismiss: onDismiss)
    }

    private var controls: some View {
        CallControlBar(
            isMicMuted: dateStore.isMicMuted,
            isCameraOff: dateStore.isCameraOff,
            onToggleMic: { dateStore.toggleMic() },
            onToggleCamera: { dateStore.toggleCamera() },
            onReport: onReport,
            onLeave: { dateStore.leaveDate() }
        )
    }
}

// MARK: - Top bar

/// Partner on the left, the Clock in the centre; the right third is left to the self view.
private struct DateLiveTopBar: View {
    @Environment(DateStore.self) private var dateStore
    @Environment(ConfigStore.self) private var configStore

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.xs) {
            partnerLabel
                .frame(maxWidth: .infinity, alignment: .leading)
            clock
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var partnerLabel: some View {
        if let partner = dateStore.partner {
            CallPartnerLabel(title: partner.nameAndAge, subtitle: partner.locationLine)
        } else {
            Color.clear
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var clock: some View {
        if let endsAt = dateStore.endsAt {
            DateClockView(endsAt: endsAt, totalDuration: configStore.dateDuration)
        }
    }
}

// MARK: - Status row

/// Quiet hints under the clock: connection trouble, and a reminder when the mic is muted.
private struct DateLiveStatusRow: View {
    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hint: String? = CallConnectionHint.text(video: dateStore.videoState, socket: dateStore.socketState)
        return HStack(spacing: TempoSpacing.xs) {
            if let hint {
                CallStatusPill(text: hint, showsActivity: true)
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
            if dateStore.isMicMuted {
                CallStatusPill(text: "You're muted", systemImage: "mic.slash")
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: hint)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.isMicMuted)
    }
}

// MARK: - Turn card

/// The icebreaker, bound to the server's turn state and the store's hidden flag.
private struct DateTurnCardHost: View {
    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = dateStore
        return ZStack {
            if let turn = dateStore.icebreaker {
                TurnCard(
                    question: turn.question,
                    questionNumber: turn.questionIndex + 1,
                    myName: "You",
                    partnerName: dateStore.partner?.firstName ?? "Them",
                    isMyTurn: turn.isMyTurn,
                    turnEndsAt: turn.turnEndsAt,
                    turnDuration: turn.turnDuration,
                    onPass: { dateStore.passTurn() },
                    isCollapsed: $store.isIcebreakerHidden
                )
                .transition(AnyTransition.tempoRise(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.icebreaker == nil)
    }
}

// MARK: - Final seconds

/// A light tick for each of the last nine seconds. (The Clock itself marks ten.) Driven by the
/// server's `endsAt`; draws nothing.
private struct DateFinalSecondsHaptics: View {
    let endsAt: Date?

    var body: some View {
        if let endsAt {
            TimelineView(.periodic(from: Date(), by: 0.25)) { context in
                ticker(seconds: DateClock.wholeSeconds(DateClock.remaining(until: endsAt, now: context.date)))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func ticker(seconds: Int) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .sensoryFeedback(trigger: seconds) { (_: Int, newValue: Int) -> SensoryFeedback? in
                if newValue >= 1 && newValue <= 9 {
                    return SensoryFeedback.selection
                }
                return nil
            }
    }
}

// MARK: - Checkpoint

/// After the first question the screen goes gray: no video, no sound. Each person privately
/// chooses to keep going or to stop there. Shown over the whole call until the vote is settled.
private struct DateCheckpointView: View {
    let checkpoint: CheckpointState

    @Environment(DateStore.self) private var dateStore

    private var name: String {
        dateStore.partner?.firstName ?? String(localized: "them")
    }

    var body: some View {
        ZStack {
            Color(red: 0.84, green: 0.83, blue: 0.82)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Spacer(minLength: TempoSpacing.lg)
                Eyebrow(String(localized: "One question in"))
                Text(checkpoint.myChoice == nil ? "Keep going with \(name)?" : "Waiting for \(name)…")
                    .tempoText(.displayS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(checkpoint.myChoice == nil
                     ? "You can't see or hear each other right now. Choose privately: carry on with the rest of the date, or stop here. If either of you stops, it ends for both, and nobody is told who."
                     : "Your choice is in. The date carries on only if you both said keep going.")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CheckpointCountdown(deadline: checkpoint.deadline)
                Spacer(minLength: TempoSpacing.lg)
                if checkpoint.myChoice == nil {
                    VStack(spacing: TempoSpacing.xs) {
                        // The same slide as going online, with the same trigger feel.
                        SlideToStart(title: String(localized: "Slide to keep going"), systemImage: "arrow.right") {
                            dateStore.voteAtCheckpoint(CheckpointChoice.carryOn)
                        }
                        .padding(.bottom, TempoSpacing.xs)
                        TempoButton("Stop here", variant: TempoButtonVariant.secondary) {
                            dateStore.voteAtCheckpoint(CheckpointChoice.end)
                        }
                    }
                } else {
                    HStack(spacing: TempoSpacing.xs) {
                        LoadingDots(color: Color.tempo.textSecondary, dotSize: 5)
                        Text(checkpoint.myChoice == CheckpointChoice.carryOn ? "You chose to keep going." : "You chose to stop.")
                            .tempoText(.secondary)
                            .foregroundStyle(Color.tempo.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: TempoSize.buttonLarge)
                }
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            TempoHaptics.shared.tick()
        }
    }
}

/// "8 seconds to choose", counting down. No answer by the end counts as stop.
private struct CheckpointCountdown: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { context in
            let left: Int = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text(left == 1 ? "1 second left. No answer counts as stop." : "\(left) seconds left. No answer counts as stop.")
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .monospacedDigit()
                .contentTransition(ContentTransition.numericText())
        }
    }
}
