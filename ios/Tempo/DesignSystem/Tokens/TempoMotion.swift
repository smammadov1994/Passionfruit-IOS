import SwiftUI

// MARK: - Animations

/// Springs and curves, reached through `Animation.tempo`.
struct TempoAnimations {
    /// The default spring (response 0.38, damping 0.86). Use for almost everything.
    var standard: Animation { Animation.spring(response: 0.38, dampingFraction: 0.86) }
    /// Quick spring for selection changes and small controls.
    var snappy: Animation { Animation.spring(response: 0.3, dampingFraction: 0.82) }
    /// Slow, settled spring for large surfaces and phase changes.
    var gentle: Animation { Animation.spring(response: 0.55, dampingFraction: 0.92) }
    /// The settle for key moments (found, match): a single soft scale-in, no overshoot to speak of.
    var settle: Animation { Animation.spring(response: 0.5, dampingFraction: 0.86) }
    /// Press feedback: fast, with a touch of bounce on release.
    var press: Animation { Animation.spring(response: 0.16, dampingFraction: 0.62) }
    /// The Reduce Motion replacement: a plain cross-fade.
    var fade: Animation { Animation.easeInOut(duration: 0.25) }

    /// Returns `animation`, or `fade` when Reduce Motion is on.
    func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// `standard`, or `fade` when Reduce Motion is on.
    func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : standard
    }
}

extension Animation {
    /// The design-system motion set: `Animation.tempo.standard`, ...
    static var tempo: TempoAnimations { TempoAnimations() }
}

// MARK: - Transitions

extension AnyTransition {
    /// A fade with a small slide for phase changes; falls back to opacity under Reduce Motion.
    static func tempoReplace(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: AnyTransition.offset(x: 0, y: 8))
    }

    /// Rise from below with a fade; falls back to opacity under Reduce Motion.
    static func tempoRise(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity)
    }

    /// Scale up from slightly small with a fade; falls back to opacity under Reduce Motion.
    static func tempoPop(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.scale(scale: 0.94).combined(with: AnyTransition.opacity)
    }
}

// MARK: - Shadow and surfaces

/// A shadow recipe. Daylight has exactly one: cards are defined by hairline borders, and only
/// things that float over video, and sheets, lift off the page.
struct TempoShadow {
    var color: Color
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat

    /// No shadow. For call sites that float only some of the time.
    static var none: TempoShadow {
        TempoShadow(color: Color.clear, radius: 0, x: 0, y: 0)
    }

    /// The one soft shadow: y 8, blur 24, black 8%.
    static var floating: TempoShadow {
        TempoShadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

extension View {
    /// Applies a shadow recipe: `.tempoShadow(.floating)`. Only for chrome over video and sheets.
    func tempoShadow(_ shadow: TempoShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

/// A white surface with a hairline border behind any insettable shape. `isFloating` adds the one
/// soft shadow, for chrome that sits over video.
struct TempoSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let isFloating: Bool
    let showsBorder: Bool

    func body(content: Content) -> some View {
        content
            .background { surface }
            .overlay { border }
    }

    @ViewBuilder
    private var surface: some View {
        if isFloating {
            shape.fill(fill).tempoShadow(TempoShadow.floating)
        } else {
            shape.fill(fill)
        }
    }

    @ViewBuilder
    private var border: some View {
        if showsBorder {
            shape
                .strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// A white, hairline-bordered surface clipped to `shape`: `.tempoSurface(in: Capsule())`.
    /// Pass `isFloating: true` over video to add the one soft shadow.
    func tempoSurface<S: InsettableShape>(
        in shape: S,
        fill: Color = Color.tempo.ink,
        isFloating: Bool = false,
        showsBorder: Bool = true
    ) -> some View {
        modifier(TempoSurfaceModifier<S>(shape: shape, fill: fill, isFloating: isFloating, showsBorder: showsBorder))
    }
}

// MARK: - Visibility tracking

/// Tracks whether a view is on screen so continuous animation can pause when it is not.
/// (The system already stops `TimelineView` animation schedules while the app is in the background.)
struct TempoActivityModifier: ViewModifier {
    @Binding var isActive: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                isActive = true
            }
            .onDisappear {
                isActive = false
            }
    }
}

extension View {
    /// Writes `true` to `isActive` only while the view is on screen.
    func tempoTracksActivity(_ isActive: Binding<Bool>) -> some View {
        modifier(TempoActivityModifier(isActive: isActive))
    }
}

// MARK: - Countdown math

/// Shared helpers for views that count down to a server timestamp.
enum TempoCountdown {
    /// Seconds left until `endsAt`, never negative.
    static func remaining(until endsAt: Date, now: Date) -> TimeInterval {
        max(0.0, endsAt.timeIntervalSince(now))
    }

    /// Remaining share of `total`, clamped to 0...1.
    static func fraction(until endsAt: Date, now: Date, total: TimeInterval) -> Double {
        guard total > 0 else { return 0.0 }
        return min(1.0, max(0.0, endsAt.timeIntervalSince(now) / total))
    }

    /// Whole seconds to show (rounds up, so "3" is shown until two seconds remain).
    static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        Int(max(0.0, remaining).rounded(.up))
    }

    /// "3:12"
    static func clockString(_ seconds: Int) -> String {
        let clamped: Int = max(0, seconds)
        let minutes: Int = clamped / 60
        let secs: Int = clamped % 60
        let padded: String = secs < 10 ? "0\(secs)" : "\(secs)"
        return "\(minutes):\(padded)"
    }

    /// "3 minutes 12 seconds", for VoiceOver.
    static func spokenString(_ seconds: Int) -> String {
        let clamped: Int = max(0, seconds)
        let minutes: Int = clamped / 60
        let secs: Int = clamped % 60
        let minutePart: String = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondPart: String = secs == 1 ? "1 second" : "\(secs) seconds"
        if minutes == 0 {
            return secondPart
        }
        if secs == 0 {
            return minutePart
        }
        return "\(minutePart) \(secondPart)"
    }
}
