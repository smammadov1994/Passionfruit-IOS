import SwiftUI

/// The private answer at the end of a date.
enum VerdictChoice: String, Hashable, Sendable {
    case yes
    case no
}

/// The Verdict: the contents of the white bottom sheet at the end of a date. The question in
/// serif with a thin countdown ring beside it, then two large circles: No (white, hairline border,
/// outlined cross in text-secondary) and Yes (accent fill, white heart). Once `selection` is set
/// the pad seals: the same neutral "Sealed." for either answer, so a glance at the screen gives
/// nothing away.
///
/// Put it in a sheet with `.tempoBottomSheet()`, over the blurred video under a 70% white veil.
///
///     VerdictPad(partnerName: "Maya", deadline: deadline, totalWindow: 20, selection: $choice) { store.decide($0) }
struct VerdictPad: View {
    private let partnerName: String
    private let deadline: Date
    private let totalWindow: TimeInterval
    @Binding private var selection: VerdictChoice?
    private let onChoose: (VerdictChoice) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    private let buttonSize: CGFloat = 84

    init(
        partnerName: String,
        deadline: Date,
        totalWindow: TimeInterval,
        selection: Binding<VerdictChoice?>,
        onChoose: @escaping (VerdictChoice) -> Void
    ) {
        self.partnerName = partnerName
        self.deadline = deadline
        self.totalWindow = totalWindow
        self._selection = selection
        self.onChoose = onChoose
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if selection == nil {
                pad
                    .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
            } else {
                sealed
                    .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .tempoScreenPadding()
        .animation(Animation.tempo.resolved(Animation.tempo.gentle, reduceMotion: reduceMotion), value: selection)
        .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.medium), trigger: selection)
        .tempoTracksActivity($isActive)
    }

    // MARK: Pad

    private var pad: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                question
                Spacer(minLength: 0)
                TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0, paused: !isActive)) { context in
                    countdownRing(now: context.date)
                }
            }
            HStack(spacing: TempoSpacing.xxl) {
                choiceButton(VerdictChoice.no)
                choiceButton(VerdictChoice.yes)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var question: some View {
        Text("Would you like to see \(partnerName) again?")
            .tempoText(.title)
            .foregroundStyle(Color.tempo.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(AccessibilityTraits.isHeader)
    }

    /// A thin ring that drains against the deadline, with the seconds inside. Amber for the last five.
    private func countdownRing(now: Date) -> some View {
        let remaining: TimeInterval = TempoCountdown.remaining(until: deadline, now: now)
        let seconds: Int = TempoCountdown.wholeSeconds(remaining)
        let fraction: Double = TempoCountdown.fraction(until: deadline, now: now, total: totalWindow)
        let isUrgent: Bool = remaining <= 5.0
        let tint: Color = isUrgent ? Color.tempo.warning : Color.tempo.accent

        return ZStack {
            Circle()
                .stroke(Color.tempo.surface2, lineWidth: 2)
            Circle()
                .trim(from: 0.0, to: CGFloat(fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: CGLineCap.round))
                .rotationEffect(Angle.degrees(-90))
            Text("\(seconds)")
                .tempoText(.numeralS)
                .foregroundStyle(Color.tempo.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .animation(Animation.tempo.snappy, value: seconds)
        }
        .frame(width: 40, height: 40)
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(seconds) seconds to decide"))
        .accessibilityAddTraits(AccessibilityTraits.updatesFrequently)
    }

    private func choiceButton(_ choice: VerdictChoice) -> some View {
        let isYes: Bool = choice == VerdictChoice.yes
        return Button {
            choose(choice)
        } label: {
            VStack(spacing: TempoSpacing.xs) {
                disc(isYes: isYes)
                Text(isYes ? "Yes" : "No")
                    .tempoText(.secondaryEmphasis)
                    .foregroundStyle(isYes ? Color.tempo.textPrimary : Color.tempo.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.94))
        .accessibilityLabel(Text(isYes ? "Yes" : "No"))
        .accessibilityHint(Text(isYes ? "You'd like to see \(partnerName) again" : "You'd rather not"))
    }

    /// A see-through watercolor blot for each answer: light green with a heart for yes, light red
    /// with a cross for no.
    private func disc(isYes: Bool) -> some View {
        ZStack {
            Image(isYes ? "ChoiceYes" : "ChoiceNo")
                .resizable()
                .frame(width: buttonSize * 1.42, height: buttonSize * 1.42)
                .rotationEffect(Angle.degrees(isYes ? -12 : 20))
            Image(systemName: isYes ? "heart.fill" : "xmark")
                .font(Font.system(size: isYes ? 30 : 26, weight: isYes ? Font.Weight.regular : Font.Weight.medium))
                // On a pale, see-through wash white would vanish: the icon takes a deep shade of
                // the wash's own colour.
                .foregroundStyle(isYes ? Color(red: 0.11, green: 0.42, blue: 0.27) : Color(red: 0.66, green: 0.16, blue: 0.13))
        }
        .frame(width: buttonSize, height: buttonSize)
    }

    // MARK: Sealed

    private var sealed: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Image(systemName: "envelope")
                .font(Font.system(size: 22, weight: Font.Weight.regular))
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(width: 48, height: 48)
                .background { RoundedRectangle(cornerRadius: TempoRadius.chip, style: .continuous).fill(Color.tempo.pastelBlush) }
                .padding(.bottom, TempoSpacing.xs)
                .accessibilityHidden(true)
            Text("Sealed.")
                .tempoText(.displayS)
                .foregroundStyle(Color.tempo.textPrimary)
            Text("Your answer stays private.")
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
            HStack(spacing: TempoSpacing.xs) {
                Text("Waiting for \(partnerName)")
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                LoadingDots(color: Color.tempo.textSecondary, dotSize: 4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Behaviour

    private func choose(_ choice: VerdictChoice) {
        guard selection == nil else { return }
        selection = choice
        onChoose(choice)
    }
}

// MARK: - Preview

private struct VerdictPadPreview: View {
    @State private var selection: VerdictChoice? = nil
    @State private var deadline: Date = Date().addingTimeInterval(20)

    var body: some View {
        VStack(spacing: 0) {
            TempoButton("Reset", variant: TempoButtonVariant.ghost, size: TempoButtonSize.compact, fullWidth: false) {
                selection = nil
                deadline = Date().addingTimeInterval(20)
            }
            .frame(maxHeight: .infinity)
            VerdictPad(partnerName: "Maya", deadline: deadline, totalWindow: 20, selection: $selection) { _ in }
                .padding(.top, TempoSpacing.xl)
                .padding(.bottom, TempoSpacing.lg)
                .tempoBottomSheet()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.tempo.surface2.ignoresSafeArea() }
    }
}

#Preview("VerdictPad") {
    VerdictPadPreview()
}
