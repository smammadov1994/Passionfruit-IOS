import SwiftUI

/// The search, in paint. Two large washes circle each other around the middle of the screen,
/// drawing close and drifting apart; pale washes
/// wander behind them and small drops seep in and out around the edges. When `gather` goes to 1
/// (someone was found) the circling washes fall into the centre and swell into a single bloom,
/// which sits behind whatever the screen puts there.
/// Full-bleed and opaque; still under Reduce Motion.
struct SearchingPaint: View, Animatable {
    /// 0 = searching, 1 = found.
    var gather: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: CGFloat {
        get { gather }
        set { gather = newValue }
    }

    init(gather: CGFloat = 0) {
        self.gather = gather
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time: Double = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, rendersAsynchronously: true) { canvas, size in
                canvas.fill(Path(CGRect(origin: CGPoint.zero, size: size)), with: GraphicsContext.Shading.color(Color.tempo.background))
                canvas.blendMode = GraphicsContext.BlendMode.multiply
                drawBackdrop(&canvas, size: size, time: time)
                drawDrops(&canvas, size: size, time: time)
                drawPair(&canvas, size: size, time: time)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: Layers

    /// Pale washes wandering far behind everything; they fade as the pair gathers.
    private func drawBackdrop(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let unit: CGFloat = min(size.width, size.height)
        let washes: [(String, CGFloat, CGFloat, CGFloat, Double)] = [
            ("BlotButter", 0.82, 0.16, 0.95, 23),
            ("BlotLilac", 0.14, 0.2, 0.8, 29),
            ("BlotSky", 0.2, 0.86, 0.9, 26),
            ("BlotButter", 0.86, 0.84, 0.7, 31)
        ]
        for (index, wash) in washes.enumerated() {
            let phase: Double = time / wash.4 * 2 * Double.pi + Double(index) * 1.3
            let x: CGFloat = wash.1 * size.width + CGFloat(sin(phase)) * unit * 0.07
            let y: CGFloat = wash.2 * size.height + CGFloat(cos(phase * 0.8)) * unit * 0.06
            draw(wash.0, in: &canvas, at: CGPoint(x: x, y: y), side: unit * wash.3,
                 turn: 10 * sin(phase * 0.5), opacity: 0.5 * Double(1 - gather * 0.5))
        }
    }

    /// Small drops that soak in, travel a little and soak away, each life somewhere new.
    private func drawDrops(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let unit: CGFloat = min(size.width, size.height)
        // Few and faint: they should be noticed only in passing.
        let hues: [String] = ["BlotSage", "BlotLilac", "BlotSky"]
        for (index, hue) in hues.enumerated() {
            let period: Double = 5.5 + Double(index) * 1.1
            let lives: Double = time / period + Double(index) * 0.41
            let life: Double = floor(lives)
            let age: Double = lives - life
            let spotX: CGFloat = CGFloat(SearchingPaint.hash(life * 2 + Double(index)))
            let spotY: CGFloat = CGFloat(SearchingPaint.hash(life * 2 + 1 + Double(index) * 3))
            let heading: Double = SearchingPaint.hash(life * 3 + Double(index) * 7) * 2 * Double.pi
            let x: CGFloat = (0.08 + 0.84 * spotX) * size.width + CGFloat(cos(heading) * age) * unit * 0.22
            let y: CGFloat = (0.08 + 0.84 * spotY) * size.height + CGFloat(sin(heading) * age) * unit * 0.22
            let side: CGFloat = unit * (0.16 + 0.05 * CGFloat(index % 3)) * CGFloat(0.7 + 0.3 * age)
            draw(hue, in: &canvas, at: CGPoint(x: x, y: y), side: side, turn: 40 * age,
                 opacity: sin(age * Double.pi) * 0.3 * Double(1 - gather))
        }
    }

    /// The two who are looking for each other, and the spot of vermilion between them.
    private func drawPair(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let unit: CGFloat = min(size.width, size.height)
        // Above the middle while searching (the words sit below); it settles toward the middle,
        // behind the person's photo, when someone is found.
        let center = CGPoint(x: size.width / 2, y: size.height * (0.34 + 0.1 * gather))
        // They draw close and drift apart on a slow breath while circling.
        let breath: CGFloat = 0.72 + 0.28 * CGFloat(sin(time * 0.55))
        let orbit: CGFloat = unit * 0.24 * breath * (1 - gather)
        let angle: Double = time * 0.5
        let side: CGFloat = unit * (0.74 + 0.5 * gather)
        let first = CGPoint(x: center.x + CGFloat(cos(angle)) * orbit, y: center.y + CGFloat(sin(angle)) * orbit * 0.8)
        let second = CGPoint(x: center.x - CGFloat(cos(angle)) * orbit, y: center.y - CGFloat(sin(angle)) * orbit * 0.8)
        draw("BlotBlush", in: &canvas, at: first, side: side, turn: angle * 20, opacity: 1)
        draw("BlotSage", in: &canvas, at: second, side: side * 0.94, turn: -angle * 16 + 40, opacity: 1)
    }

    private func draw(_ name: String, in canvas: inout GraphicsContext, at point: CGPoint, side: CGFloat, turn: Double, opacity: Double) {
        guard opacity > 0.01 else { return }
        var layer: GraphicsContext = canvas
        layer.opacity = opacity
        layer.translateBy(x: point.x, y: point.y)
        layer.rotate(by: Angle.degrees(turn))
        layer.draw(layer.resolve(Image(name)), in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
    }

    private static func hash(_ seed: Double) -> Double {
        let value: Double = sin(seed * 12.9898 + 4.1414) * 43758.5453
        return value - floor(value)
    }
}

#Preview("Searching paint") {
    SearchingPaint()
}
