import SwiftUI

/// The Verdict and its sealed state: a white bottom sheet over the blurred, white-veiled video
/// (`CallVideoBackdrop` draws the blur and the veil). One view for `.deciding` and
/// `.awaitingResult`, so the pad seals in place instead of being replaced.
/// `deadline` is the server's decision deadline; nil once the answer is sealed.
struct DateVerdictView: View {
    let partner: Partner
    let deadline: Date?
    let onReport: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(ConfigStore.self) private var configStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: VerdictChoice? = nil
    @State private var lastDeadline: Date? = nil

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: TempoSpacing.xs)
            verdictSheet
        }
        .padding(.top, TempoSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: isSealed)
        .onAppear {
            sync()
        }
        .onChange(of: deadline) { _, _ in
            sync()
        }
    }

    /// Eyebrow, the pad, the privacy line and the "last one" control, left-aligned on white.
    private var verdictSheet: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Eyebrow(isSealed ? "Answer in" : "Time's up")
                .tempoScreenPadding()
            pad
            footnote
            DateLastOneButton()
                .tempoScreenPadding()
        }
        .padding(.top, TempoSpacing.xl)
        .padding(.bottom, TempoSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoBottomSheet()
    }

    private var isSealed: Bool {
        deadline == nil
    }

    private var pad: some View {
        VerdictPad(
            partnerName: partner.firstName,
            deadline: deadline ?? lastDeadline ?? Date(),
            totalWindow: configStore.decisionWindow,
            selection: $selection,
            onChoose: { choice in
                choose(choice)
            }
        )
    }

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            IconCircleButton(
                systemImage: "flag",
                accessibilityLabel: "Report \(partner.firstName)",
                kind: IconCircleButtonKind.floating,
                size: TempoSize.hitTarget,
                action: onReport
            )
        }
        .tempoScreenPadding()
    }

    private var footnote: some View {
        Text(footnoteText)
            .tempoText(.secondary)
            .foregroundStyle(Color.tempo.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tempoScreenPadding()
            .contentTransition(.opacity)
    }

    private var footnoteText: String {
        if isSealed && dateStore.myDecision == nil {
            return "Time ran out, so this one counts as a no."
        }
        return "\(partner.firstName) only finds out if it's mutual."
    }

    // MARK: Behaviour

    private func choose(_ choice: VerdictChoice) {
        switch choice {
        case .yes:
            dateStore.decide(DateDecision.yes)
        case .no:
            dateStore.decide(DateDecision.no)
        }
    }

    /// Keeps the pad in step with the store: remembers the deadline while deciding, and seals
    /// the pad when the store sealed without a tap here (the window closed, or a preview).
    private func sync() {
        if let deadline {
            lastDeadline = deadline
            return
        }
        guard selection == nil else { return }
        if let decision = dateStore.myDecision, decision == DateDecision.yes {
            selection = VerdictChoice.yes
        } else {
            selection = VerdictChoice.no
        }
    }
}

// MARK: - Last one tonight

/// "Stop for tonight", asked ahead of time: the store finishes this date and then closes the
/// flow instead of looking for the next person.
private struct DateLastOneButton: View {
    @Environment(DateStore.self) private var dateStore

    var body: some View {
        if dateStore.willStopAfterThis {
            Chip("Last one tonight", systemImage: "checkmark")
                .frame(minHeight: TempoSize.hitTarget)
        } else {
            TempoTextButton("Make this my last one tonight", color: Color.tempo.textSecondary) {
                dateStore.stopAfterThis()
            }
        }
    }
}
