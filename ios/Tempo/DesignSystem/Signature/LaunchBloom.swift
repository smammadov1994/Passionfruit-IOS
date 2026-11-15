import SwiftUI

/// The opening moment: washes of colour bloom from the middle of white paper until they fill the
/// screen, the wordmark sits on top, then the paint thins out to reveal the app underneath.
/// Runs once, about 2.4 s, and calls `onFinished`. Under Reduce Motion it is a short fade.
///
///     content.overlay { if showsBloom { LaunchBloom(title: Brand.name) { showsBloom = false } } }
struct LaunchBloom: View {
    private let title: String
    private let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date = Date()
    @State private var isLeaving: Bool = false

    private static let bloomDuration: Double = 1.7
    private static let holdDuration: Double = 0.25
    private static let leaveDuration: Double = 0.55

    init(title: String, onFinished: @escaping () -> Void) {
        self.title = title
        self.onFinished = onFinished
    }

    /// Where each wash starts (fractions of the screen), how big it gets and when it begins.
    private struct Bloom {
        let hue: Blot.Hue
        let x: CGFloat
        let y: CGFloat
        let reach: CGFloat
        let delay: Double
        let turn: Double
    }

    /// Spread toward the corners so each hue keeps its own region and they only mix at the seams;
    /// stacked on one spot, multiplied pastels turn to mud.
    private static let blooms: [Bloom] = [
        Bloom(hue: .blush, x: 0.2, y: 0.22, reach: 1.15, delay: 0.0, turn: -20),
        Bloom(hue: .butter, x: 0.82, y: 0.3, reach: 1.05, delay: 0.14, turn: 30),
        Bloom(hue: .sage, x: 0.18, y: 0.78, reach: 1.1, delay: 0.26, turn: -40),
        Bloom(hue: .lilac, x: 0.82, y: 0.76, reach: 1.05, delay: 0.38, turn: 24),
        Bloom(hue: .sky, x: 0.5, y: 0.5, reach: 0.7, delay: 0.5, turn: -14),
        Bloom(hue: .accent, x: 0.5, y: 0.47, reach: 0.4, delay: 0.62, turn: 50)
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                let elapsed: Double = reduceMotion ? LaunchBloom.bloomDuration : context.date.timeIntervalSince(start)
                Canvas(opaque: true) { canvas, size in
                    canvas.fill(Path(CGRect(origin: CGPoint.zero, size: size)), with: GraphicsContext.Shading.color(Color.tempo.background))
                    canvas.blendMode = GraphicsContext.BlendMode.multiply
                    for bloom in LaunchBloom.blooms {
                        draw(bloom, in: &canvas, size: size, elapsed: elapsed)
                    }
                }
            }
            Text(title)
                .tempoText(.displayL)
                .foregroundStyle(Color.tempo.textPrimary)
                .opacity(isLeaving ? 0 : 1)
        }
        .ignoresSafeArea()
        .opacity(isLeaving ? 0 : 1)
        .scaleEffect(isLeaving && !reduceMotion ? 1.12 : 1)
        .allowsHitTesting(!isLeaving)
        .accessibilityHidden(true)
        .task {
            start = Date()
            let wait: Double = reduceMotion ? 0.5 : LaunchBloom.bloomDuration + LaunchBloom.holdDuration
            try? await Task.sleep(for: Duration.seconds(wait))
            withAnimation(Animation.easeInOut(duration: LaunchBloom.leaveDuration)) {
                isLeaving = true
            }
            try? await Task.sleep(for: Duration.seconds(LaunchBloom.leaveDuration))
            onFinished()
        }
    }

    private func draw(_ bloom: Bloom, in canvas: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let raw: Double = (elapsed - bloom.delay) / (LaunchBloom.bloomDuration - bloom.delay)
        let t: Double = min(1, max(0, raw))
        guard t > 0 else { return }
        // Ease out: paint spreads fast, then settles.
        let eased: Double = 1 - pow(1 - t, 3)
        let side: CGFloat = max(size.width, size.height) * bloom.reach * CGFloat(0.08 + 0.92 * eased)
        var layer: GraphicsContext = canvas
        layer.opacity = min(1, t * 4)
        layer.translateBy(x: bloom.x * size.width, y: bloom.y * size.height)
        layer.rotate(by: Angle.degrees(bloom.turn * eased))
        layer.draw(layer.resolve(Image(bloom.hue.rawValue)), in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
    }
}

#Preview("Launch bloom") {
    LaunchBloom(title: "Passionfruit") {}
}
