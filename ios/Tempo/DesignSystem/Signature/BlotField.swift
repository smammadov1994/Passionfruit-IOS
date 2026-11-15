import SwiftUI

/// One watercolor wash in a `BlotField`: which image, where, how big and how it drifts.
/// Positions are in a 354 pt wide design space and scale with the field's width; `y` and `size`
/// are in points.
struct Blot: Identifiable, Hashable {
    enum Hue: String {
        case blush = "BlotBlush"
        case butter = "BlotButter"
        case sage = "BlotSage"
        case lilac = "BlotLilac"
        case sky = "BlotSky"
        case accent = "BlotAccent"
    }

    /// How a wash moves.
    enum Motion: Hashable {
        /// Stays near its centre: a few points of wander (`drift`).
        case wander
        /// Travels in a straight line and bounces off the edges of the field. Points per second.
        case bounce(dx: CGFloat, dy: CGFloat)
        /// Soaks in, travels a little, soaks away, then comes back somewhere else. Points per second.
        case seep(dx: CGFloat, dy: CGFloat)
    }

    let id: Int
    let hue: Hue
    /// Centre, in the 354 pt design space.
    let x: CGFloat
    let y: CGFloat
    /// Diameter of the wash itself (the image carries a margin around it).
    let size: CGFloat
    /// Height / width.
    var squash: CGFloat = 1
    /// How far it wanders from its centre, in points.
    var drift: CGFloat = 9
    /// Seconds for one loop; each blot gets its own so they never move in step.
    var period: Double = 16
    /// How strongly `push` moves it (0 = not at all).
    var depth: CGFloat = 0
    var motion: Motion = Motion.wander
}

/// Layered watercolor washes in slow motion. Each wanders in place, bounces around inside the
/// field, or seeps in and away again (`Blot.Motion`), with a little turn and a little breathing. Multiply-blended on white, like wet paint over paper. `push` (0...1) sweeps the
/// washes sideways and swells them, for controls that drag through the paint.
/// Still under Reduce Motion and while `isActive` is false. Decorative; clip it to your shape.
struct BlotField: View {
    private let blots: [Blot]
    private let push: CGFloat
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The wash fills 160 of the image's 220 points.
    private static let imageScale: CGFloat = 220.0 / 160.0
    private static let designWidth: CGFloat = 354

    init(_ blots: [Blot], push: CGFloat = 0, isActive: Bool = true) {
        self.blots = blots
        self.push = push
        self.isActive = isActive
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || !isActive)) { context in
            let time: Double = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            // One Canvas pass: far cheaper than a tree of blended views redrawn every frame.
            Canvas(opaque: true, rendersAsynchronously: true) { canvas, size in
                canvas.fill(Path(CGRect(origin: CGPoint.zero, size: size)), with: GraphicsContext.Shading.color(Color.tempo.background))
                canvas.blendMode = GraphicsContext.BlendMode.multiply
                for blot in blots {
                    draw(blot, in: &canvas, time: time, size: size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ blot: Blot, in canvas: inout GraphicsContext, time: Double, size: CGSize) {
        let phase: Double = time / blot.period * 2.0 * Double.pi + Double(blot.id) * 1.7
        let unit: CGFloat = size.width / BlotField.designWidth
        let swell: CGFloat = 1.0 + 0.04 * CGFloat(sin(phase * 0.7)) + push * blot.depth * 0.3
        let frame: CGFloat = blot.size * BlotField.imageScale * swell
        var x: CGFloat = blot.x * unit
        var y: CGFloat = blot.y
        var opacity: Double = 1

        switch blot.motion {
        case .wander:
            x += blot.drift * CGFloat(sin(phase))
            y += blot.drift * 0.8 * CGFloat(cos(phase * 0.8))
        case .bounce(let dx, let dy):
            // The centre stays inside the field, inset so most of the wash stays in view.
            let inset: CGFloat = min(blot.size * 0.3, min(size.width, size.height) * 0.3)
            x = BlotField.reflect(x + dx * CGFloat(time), low: inset, high: size.width - inset)
            y = BlotField.reflect(y + dy * CGFloat(time), low: inset, high: size.height - inset)
        case .seep(let dx, let dy):
            // One life per `period`: fade in, drift, fade out; each life starts somewhere new.
            let lives: Double = time / blot.period + Double(blot.id) * 0.37
            let life: Double = floor(lives)
            let age: Double = lives - life
            let spotX: CGFloat = CGFloat(BlotField.hash(life * 2 + Double(blot.id)))
            let spotY: CGFloat = CGFloat(BlotField.hash(life * 2 + 1 + Double(blot.id) * 3))
            x = (0.1 + 0.8 * spotX) * size.width + dx * CGFloat(age * blot.period)
            y = (0.1 + 0.8 * spotY) * size.height + dy * CGFloat(age * blot.period)
            opacity = sin(age * Double.pi)
        }
        x += push * blot.depth * 46

        var layer: GraphicsContext = canvas
        layer.opacity = opacity
        layer.translateBy(x: x, y: y)
        layer.rotate(by: Angle.degrees(7.0 * sin(phase * 0.5)))
        let rect = CGRect(x: -frame / 2, y: -frame * blot.squash / 2, width: frame, height: frame * blot.squash)
        layer.draw(layer.resolve(Image(blot.hue.rawValue)), in: rect)
    }

    /// Folds an ever-growing position back and forth between two walls.
    private static func reflect(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        let range: CGFloat = max(1, high - low)
        let wrapped: CGFloat = (value - low).truncatingRemainder(dividingBy: range * 2)
        let positive: CGFloat = wrapped < 0 ? wrapped + range * 2 : wrapped
        return low + (positive <= range ? positive : range * 2 - positive)
    }

    /// A stable pseudo-random number in 0..<1 for a whole-number seed.
    private static func hash(_ seed: Double) -> Double {
        let value: Double = sin(seed * 12.9898 + 4.1414) * 43758.5453
        return value - floor(value)
    }
}

extension BlotField {
    /// The Tonight card (236 pt tall). Kept sparse so the text stays easy to read: one large wash
    /// anchored on the right, one that bounces around inside the card, one that seeps in and away.
    static let tonight: [Blot] = [
        Blot(id: 0, hue: .blush, x: 266, y: 100, size: 200, squash: 0.9, drift: 12, period: 19),
        Blot(id: 1, hue: .butter, x: 300, y: 170, size: 120, motion: .bounce(dx: -8, dy: 6)),
        Blot(id: 2, hue: .sage, x: 0, y: 0, size: 110, squash: 0.86, period: 13, motion: .seep(dx: 5, dy: -3))
    ]

    /// A brush dragged along a 64 pt track. `depth` rises to the right, so `push` fans them out.
    static let track: [Blot] = [
        Blot(id: 0, hue: .blush, x: 18, y: 30, size: 150, squash: 0.74, drift: 10, period: 12, depth: 0.2),
        Blot(id: 1, hue: .butter, x: 104, y: 36, size: 146, squash: 0.74, drift: 12, period: 10, depth: 0.45),
        Blot(id: 2, hue: .sage, x: 192, y: 28, size: 150, squash: 0.74, drift: 12, period: 13, depth: 0.7),
        Blot(id: 3, hue: .lilac, x: 280, y: 36, size: 146, squash: 0.74, drift: 12, period: 11, depth: 0.9),
        Blot(id: 4, hue: .blush, x: 360, y: 30, size: 136, squash: 0.74, drift: 10, period: 14, depth: 1.0)
    ]
}

#Preview("Blot field") {
    BlotField(BlotField.tonight)
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous))
        .padding()
}
