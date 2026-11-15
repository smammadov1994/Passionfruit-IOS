import SwiftUI

// MARK: - DateClockView

/// The Clock: a white capsule (hairline border, the one soft shadow) at the top of the video,
/// holding a small accent arc that drains with the date and the time left in monospaced digits.
/// Under `warningThreshold` seconds the arc and digits turn warning-amber and pulse softly; a
/// light haptic ticks at 10 seconds. Always computed from `endsAt` (the server timestamp), never
/// from a local counter.
///
///     DateClockView(endsAt: store.endsAt, totalDuration: 240)
struct DateClockView: View {
    private let endsAt: Date
    private let totalDuration: TimeInterval
    private let warningThreshold: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    init(endsAt: Date, totalDuration: TimeInterval, warningThreshold: TimeInterval = 30) {
        self.endsAt = endsAt
        self.totalDuration = totalDuration
        self.warningThreshold = warningThreshold
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0, paused: !isActive)) { context in
            clock(now: context.date)
        }
        .tempoTracksActivity($isActive)
    }

    private func clock(now: Date) -> some View {
        let remaining: TimeInterval = TempoCountdown.remaining(until: endsAt, now: now)
        let seconds: Int = TempoCountdown.wholeSeconds(remaining)
        let fraction: Double = TempoCountdown.fraction(until: endsAt, now: now, total: totalDuration)
        let warmth: Double = warmthLevel(remaining: remaining)
        let pulse: Double = pulseLevel(remaining: remaining)
        let tint: Color = TempoPalette.ember.mixed(with: TempoPalette.amber, amount: warmth).color

        return HStack(spacing: TempoSpacing.xs) {
            arc(fraction: fraction, tint: tint)
            digits(seconds: seconds, warmth: warmth)
        }
        .opacity(1.0 - 0.3 * pulse)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(minHeight: 40)
        .tempoSurface(in: Capsule(), isFloating: true)
        .sensoryFeedback(trigger: seconds) { (_: Int, newValue: Int) -> SensoryFeedback? in
            if newValue == 10 {
                return SensoryFeedback.impact(weight: SensoryFeedback.Weight.light)
            }
            return nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time remaining"))
        .accessibilityValue(Text(TempoCountdown.spokenString(seconds)))
        .accessibilityAddTraits(AccessibilityTraits.updatesFrequently)
    }

    private func digits(seconds: Int, warmth: Double) -> some View {
        let color: Color = TempoPalette.ivory.mixed(with: TempoPalette.amber, amount: warmth).color
        let transition: ContentTransition = reduceMotion ? ContentTransition.identity : ContentTransition.numericText(countsDown: true)
        return Text(TempoCountdown.clockString(seconds))
            .tempoText(.numeral)
            .foregroundStyle(color)
            .contentTransition(transition)
            .animation(Animation.tempo.snappy, value: seconds)
            .lineLimit(1)
    }

    private func arc(fraction: Double, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.tempo.surface2, lineWidth: 2.5)
            Circle()
                .trim(from: 0.0, to: CGFloat(fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: CGLineCap.round))
                .rotationEffect(Angle.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    /// 0 while there is plenty of time, easing to 1 over the three seconds before the threshold.
    private func warmthLevel(remaining: TimeInterval) -> Double {
        let lead: Double = 3.0
        if remaining >= warningThreshold + lead {
            return 0.0
        }
        if remaining <= warningThreshold {
            return 1.0
        }
        return 1.0 - (remaining - warningThreshold) / lead
    }

    /// A smooth once-per-second swell under the threshold; 0 otherwise and under Reduce Motion.
    private func pulseLevel(remaining: TimeInterval) -> Double {
        guard !reduceMotion, remaining > 0, remaining <= warningThreshold else { return 0.0 }
        let phase: Double = remaining - remaining.rounded(.down)
        return 0.5 - 0.5 * cos(phase * 2.0 * Double.pi)
    }
}

// MARK: - NextCountdown

/// The quiet interstitial after a date that did not match or ended early: a serif line,
/// "Next person in 3" beside a thin draining accent arc, and a text button to stop.
/// Left-aligned on white. Driven by `endsAt`.
///
///     NextCountdown(endsAt: nextAt, total: 3, title: "Not this time.") { store.stopAfterThis() }
struct NextCountdown: View {
    private let endsAt: Date
    private let total: TimeInterval
    private let title: String
    private let caption: String
    private let stopTitle: String
    private let onFinished: (() -> Void)?
    private let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    init(
        endsAt: Date,
        total: TimeInterval,
        title: String,
        caption: String = "Next person in",
        stopTitle: String = "Stop for tonight",
        onFinished: (() -> Void)? = nil,
        onStop: @escaping () -> Void
    ) {
        self.endsAt = endsAt
        self.total = total
        self.title = title
        self.caption = caption
        self.stopTitle = stopTitle
        self.onFinished = onFinished
        self.onStop = onStop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Text(title)
                .tempoText(.displayM)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0, paused: !isActive)) { context in
                countdown(now: context.date)
            }
            TempoTextButton(stopTitle, action: onStop)
        }
        .tempoScreenPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoTracksActivity($isActive)
        .task(id: endsAt) {
            await waitForEnd()
        }
    }

    private func countdown(now: Date) -> some View {
        let remaining: TimeInterval = TempoCountdown.remaining(until: endsAt, now: now)
        let seconds: Int = TempoCountdown.wholeSeconds(remaining)
        let fraction: Double = TempoCountdown.fraction(until: endsAt, now: now, total: total)

        return HStack(spacing: TempoSpacing.sm) {
            arc(fraction: fraction)
            Text("\(caption) \(seconds)")
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(Animation.tempo.snappy, value: seconds)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(caption) \(seconds) seconds"))
        .accessibilityAddTraits(AccessibilityTraits.updatesFrequently)
    }

    private func arc(fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.tempo.surface2, lineWidth: 2)
            Circle()
                .trim(from: 0.0, to: CGFloat(fraction))
                .stroke(Color.tempo.accent, style: StrokeStyle(lineWidth: 2, lineCap: CGLineCap.round))
                .rotationEffect(Angle.degrees(-90))
        }
        .frame(width: 28, height: 28)
    }

    @MainActor
    private func waitForEnd() async {
        guard let onFinished else { return }
        let delay: TimeInterval = endsAt.timeIntervalSinceNow
        if delay > 0 {
            do {
                try await Task.sleep(for: Duration.seconds(delay))
            } catch {
                return
            }
        }
        onFinished()
    }
}

// MARK: - Preview

private struct ClockPreview: View {
    @State private var endsAt: Date = Date().addingTimeInterval(36)
    @State private var nextAt: Date = Date().addingTimeInterval(3)

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            DateClockView(endsAt: endsAt, totalDuration: 240)
                .padding(TempoSpacing.lg)
                .background { Color.tempo.textSecondary }
            NextCountdown(endsAt: nextAt, total: 3, title: "Not this time.", onFinished: { nextAt = Date().addingTimeInterval(3) }, onStop: {})
            TempoButton("Restart clock at 0:36", variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false) {
                endsAt = Date().addingTimeInterval(36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkBackground()
    }
}

#Preview("DateClockView and NextCountdown") {
    ClockPreview()
}
