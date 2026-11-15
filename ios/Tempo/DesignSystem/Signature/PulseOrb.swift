import SwiftUI

/// What the Pulse is doing.
enum PulseOrbState: Hashable {
    /// A thin accent ring breathing on white, inviting a tap. Shows `idleTitle`.
    case idle
    /// The ring becomes a rotating accent arc; the searching line sits inside it.
    case searching
    /// The ring resolves into the partner's photo with their name underneath.
    case found
}

/// The live count line: a small green dot and "23 compatible people online now".
/// Tonight shows it under its title; the Pulse shows it as its idle caption unless told not to.
struct LiveCountLine: View {
    private let count: Int?

    init(count: Int?) {
        self.count = count
    }

    var body: some View {
        HStack(spacing: TempoSpacing.xs) {
            if let count, count > 0 {
                Circle()
                    .fill(Color.tempo.mint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(LiveCountLine.text(for: count))
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .contentTransition(.numericText())
                .animation(Animation.tempo.snappy, value: count)
        }
    }

    /// The sentence for a count; a single space while the count is unknown, so the line keeps its height.
    static func text(for count: Int?) -> String {
        guard let count else { return " " }
        if count <= 0 {
            return "Be the first one here tonight."
        }
        if count == 1 {
            return "1 compatible person online now"
        }
        return "\(count) compatible people online now"
    }
}

/// The Pulse: the circle button on the Tonight tab. One tap, no hold. Drawn on white with a
/// thin accent ring and nothing else.
///
/// The whole circle is the button. In `.idle` and `.searching` a tap calls `action`
/// (go online / stop searching); in `.found` it is inert.
///
///     PulseOrb(state: .idle, onlineCount: 23) { store.goOnline() }
struct PulseOrb: View {
    private let state: PulseOrbState
    private let onlineCount: Int?
    private let diameter: CGFloat
    private let idleTitle: String
    private let searchingTitle: String
    private let foundPhoto: URL?
    private let foundName: String?
    private let showsOnlineCount: Bool
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    init(
        state: PulseOrbState,
        onlineCount: Int?,
        diameter: CGFloat = 220,
        idleTitle: String = "Go online",
        searchingTitle: String = "Finding someone good…",
        foundPhoto: URL? = nil,
        foundName: String? = nil,
        showsOnlineCount: Bool = true,
        action: @escaping () -> Void
    ) {
        self.state = state
        self.onlineCount = onlineCount
        self.diameter = diameter
        self.idleTitle = idleTitle
        self.searchingTitle = searchingTitle
        self.foundPhoto = foundPhoto
        self.foundName = foundName
        self.showsOnlineCount = showsOnlineCount
        self.action = action
    }

    var body: some View {
        VStack(spacing: TempoSpacing.md) {
            orbButton
            caption
        }
        .tempoTracksActivity($isActive)
        .sensoryFeedback(trigger: state) { (_: PulseOrbState, newState: PulseOrbState) -> SensoryFeedback? in
            if newState == PulseOrbState.found {
                return SensoryFeedback.success
            }
            return SensoryFeedback.impact(weight: SensoryFeedback.Weight.medium)
        }
    }

    // MARK: Button

    private var orbButton: some View {
        Button(action: action) {
            timeline
        }
        .buttonStyle(TempoPressStyle(scale: 0.98))
        .allowsHitTesting(state != PulseOrbState.found)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(spokenValue))
        .accessibilityHint(Text(spokenHint))
        .accessibilityAddTraits(AccessibilityTraits.isButton)
        .accessibilityAction {
            if state != PulseOrbState.found {
                action()
            }
        }
    }

    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive)) { context in
            stage(time: reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: diameter * 1.4, height: diameter * 1.4)
        .contentShape(Circle())
    }

    private func stage(time: Double) -> some View {
        ZStack {
            driftingRings(time: time)
            disc
            breathingRing(time: time)
            searchArc(time: time)
            foundLayer
            centerLabel
        }
        .animation(Animation.tempo.resolved(Animation.tempo.settle, reduceMotion: reduceMotion), value: state)
    }

    // MARK: Layers

    /// Two faint hairline rings that drift outward from the circle and fade, half a cycle apart.
    private func driftingRings(time: Double) -> some View {
        ZStack {
            driftingRing(time: time, offset: 0.0)
            driftingRing(time: time, offset: 0.5)
        }
        .opacity(state == PulseOrbState.found ? 0.0 : 1.0)
        .allowsHitTesting(false)
    }

    private func driftingRing(time: Double, offset: Double) -> some View {
        let phase: Double = reduceMotion ? 0.35 + offset * 0.5 : (time * 0.16 + offset).truncatingRemainder(dividingBy: 1.0)
        let scale: CGFloat = 1.06 + 0.3 * CGFloat(phase)
        return Circle()
            .strokeBorder(Color.tempo.hairline, lineWidth: 1)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
            .opacity(1.0 - phase)
    }

    /// The white face of the button, so the label always sits on white.
    private var disc: some View {
        Circle()
            .fill(Color.tempo.background)
            .frame(width: diameter, height: diameter)
    }

    /// Idle: the thin accent ring, breathing 1 -> 1.04. Searching: it stays as a hairline track.
    private func breathingRing(time: Double) -> some View {
        let isIdle: Bool = state == PulseOrbState.idle
        let breath: CGFloat = isIdle ? 1.02 + 0.02 * CGFloat(sin(time * 1.3)) : 1.0
        return Circle()
            .strokeBorder(isIdle ? Color.tempo.accent : Color.tempo.hairline, lineWidth: isIdle ? 2 : 1.5)
            .frame(width: diameter, height: diameter)
            .scaleEffect(reduceMotion ? 1.0 : breath)
            .opacity(state == PulseOrbState.found ? 0.0 : 1.0)
    }

    /// The rotating accent arc that replaces the ring while searching.
    private func searchArc(time: Double) -> some View {
        Circle()
            .trim(from: 0.0, to: 0.28)
            .stroke(Color.tempo.accent, style: StrokeStyle(lineWidth: 2, lineCap: CGLineCap.round))
            .frame(width: diameter - 2.0, height: diameter - 2.0)
            .rotationEffect(Angle.degrees(time * 150.0 - 90.0))
            .opacity(state == PulseOrbState.searching ? 1.0 : 0.0)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var foundLayer: some View {
        if state == PulseOrbState.found {
            TempoRemoteImage(url: foundPhoto, name: foundName ?? "", monogramSize: diameter * 0.32)
                .frame(width: diameter - 12.0, height: diameter - 12.0)
                .clipShape(Circle())
                .padding(6)
                .overlay { Circle().strokeBorder(Color.tempo.accent, lineWidth: 2) }
                .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        switch state {
        case .idle:
            centerText(idleTitle, style: TempoTextStyle.title)
        case .searching:
            centerText(searchingTitle, style: TempoTextStyle.serifBody)
        case .found:
            EmptyView()
        }
    }

    private func centerText(_ text: String, style: TempoTextStyle) -> some View {
        Text(text)
            .tempoText(style)
            .foregroundStyle(Color.tempo.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: diameter * 0.72)
            .id(text)
            .transition(AnyTransition.opacity)
    }

    // MARK: Caption

    private var caption: some View {
        ZStack {
            captionContent
                .id(state)
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
        .frame(minHeight: 44)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: state)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var captionContent: some View {
        switch state {
        case .idle:
            if showsOnlineCount {
                LiveCountLine(count: onlineCount)
            } else {
                Text(" ").tempoText(.body)
            }
        case .searching:
            Text(" ").tempoText(.body)
        case .found:
            Text(foundName ?? "")
                .tempoText(.title)
                .foregroundStyle(Color.tempo.textPrimary)
        }
    }

    private var countLine: String {
        LiveCountLine.text(for: onlineCount)
    }

    // MARK: Accessibility

    private var spokenLabel: String {
        switch state {
        case .idle: return idleTitle
        case .searching: return "Searching"
        case .found: return "Found \(foundName ?? "someone")"
        }
    }

    private var spokenValue: String {
        switch state {
        case .idle: return onlineCount == nil ? "" : countLine
        case .searching: return searchingTitle
        case .found: return ""
        }
    }

    private var spokenHint: String {
        switch state {
        case .idle: return ""
        case .searching: return "Double tap to stop searching"
        case .found: return ""
        }
    }
}

// MARK: - Preview

private struct PulseOrbPreview: View {
    @State private var state: PulseOrbState = PulseOrbState.idle

    var body: some View {
        VStack(spacing: TempoSpacing.lg) {
            PulseOrb(state: state, onlineCount: 23, foundName: "Maya") {
                state = state == PulseOrbState.idle ? PulseOrbState.searching : PulseOrbState.idle
            }
            TempoButton("Found", variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false) {
                state = PulseOrbState.found
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkBackground()
    }
}

#Preview("PulseOrb") {
    PulseOrbPreview()
}
