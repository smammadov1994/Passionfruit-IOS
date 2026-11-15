import SwiftUI

/// A match's agent as a little character: a watercolor blot (ten colours, each torn differently,
/// stretched and turned eight ways) with a face drawn on it and something on its head, all chosen
/// by its `AgentPersona`. It bobs gently and blinks; it
/// bobs faster while `isThinking`. Still under Reduce Motion.
///
///     AgentBuddy(persona: AgentPersona.generate(seed: match.id), size: 56)
struct AgentBuddy: View {
    private let persona: AgentPersona
    private let size: CGFloat
    private let isThinking: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(persona: AgentPersona, size: CGFloat = 56, isThinking: Bool = false) {
        self.persona = persona
        self.size = size
        self.isThinking = isThinking
    }

    private static let ink = Color.tempo.textPrimary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let time: Double = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let speed: Double = isThinking ? 7 : 2.2
            let bob: CGFloat = CGFloat(sin(time * speed + persona.tilt)) * size * 0.035
            // A blink every few seconds, offset per character so a list never blinks in unison.
            let cycle: Double = (time + persona.tilt / 40).truncatingRemainder(dividingBy: 4.2)
            let isBlinking: Bool = !reduceMotion && cycle < 0.14
            figure(isBlinking: isBlinking)
                .offset(y: bob)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// How the blot is stretched and turned for this silhouette: (width, height, degrees).
    /// With ten differently torn washes this gives every character its own outline.
    private var bodyShape: (width: CGFloat, height: CGFloat, turn: Double) {
        switch persona.body {
        case .round: return (1.0, 1.0, 0)
        case .squircle: return (0.96, 0.96, 45)
        case .bean: return (0.8, 1.08, 0)
        case .drop: return (0.88, 1.04, 180)
        case .bun: return (1.14, 0.84, 0)
        case .gumdrop: return (0.98, 0.9, 90)
        case .scallop: return (1.06, 1.06, 135)
        case .pebble: return (1.12, 0.9, 20)
        }
    }

    private func figure(isBlinking: Bool) -> some View {
        let shape = bodyShape
        // The wash fills about three quarters of its image.
        let side: CGFloat = size * 1.32
        return ZStack {
            top
                .offset(y: size * (1 - shape.height) * 0.42)
            Image(AgentBuddy.asset(for: persona.hue))
                .resizable()
                .rotationEffect(Angle.degrees(shape.turn + persona.tilt))
                .frame(width: side, height: side)
                .scaleEffect(x: shape.width, y: shape.height)
            if persona.hasCheeks {
                cheeks
            }
            eyes(isBlinking: isBlinking)
                .offset(y: -size * 0.06)
            mouth
                .offset(y: size * 0.14)
        }
        .frame(width: size, height: size)
    }

    /// The flat colour that goes with a character, for tinting things that belong to it.
    static func color(for hue: AgentPersona.Hue) -> Color {
        switch hue {
        case .blush: return Color(red: 0.953, green: 0.702, blue: 0.635)
        case .butter: return Color(red: 0.949, green: 0.851, blue: 0.541)
        case .sage: return Color(red: 0.663, green: 0.824, blue: 0.722)
        case .lilac: return Color(red: 0.773, green: 0.706, blue: 0.890)
        case .sky: return Color(red: 0.663, green: 0.776, blue: 0.910)
        case .coral: return Color(red: 0.941, green: 0.561, blue: 0.478)
        case .mint: return Color(red: 0.561, green: 0.839, blue: 0.769)
        case .peach: return Color(red: 0.965, green: 0.773, blue: 0.604)
        case .periwinkle: return Color(red: 0.624, green: 0.690, blue: 0.925)
        case .rose: return Color(red: 0.922, green: 0.651, blue: 0.776)
        }
    }

    /// The watercolor body for a colour.
    static func asset(for hue: AgentPersona.Hue) -> String {
        switch hue {
        case .blush: return "BuddyBlush"
        case .butter: return "BuddyButter"
        case .sage: return "BuddySage"
        case .lilac: return "BuddyLilac"
        case .sky: return "BuddySky"
        case .coral: return "BuddyCoral"
        case .mint: return "BuddyMint"
        case .peach: return "BuddyPeach"
        case .periwinkle: return "BuddyPeriwinkle"
        case .rose: return "BuddyRose"
        }
    }

    // MARK: Face

    @ViewBuilder
    private func eyes(isBlinking: Bool) -> some View {
        let gap: CGFloat = size * 0.2
        HStack(spacing: gap) {
            eye(isLeft: true, isBlinking: isBlinking)
            eye(isLeft: false, isBlinking: isBlinking)
        }
    }

    @ViewBuilder
    private func eye(isLeft: Bool, isBlinking: Bool) -> some View {
        let dot: CGFloat = size * 0.1
        let closed = Capsule().fill(AgentBuddy.ink).frame(width: dot * 1.4, height: max(1.5, size * 0.03))
        if isBlinking {
            closed
        } else {
            switch persona.eyes {
            case .dots:
                Circle().fill(AgentBuddy.ink).frame(width: dot, height: dot)
            case .tall:
                Capsule().fill(AgentBuddy.ink).frame(width: dot * 0.8, height: dot * 1.7)
            case .wide:
                Circle()
                    .fill(Color.tempo.background)
                    .frame(width: dot * 1.9, height: dot * 1.9)
                    .overlay { Circle().fill(AgentBuddy.ink).frame(width: dot, height: dot).offset(x: dot * 0.15) }
            case .sleepy:
                closed
            case .wink:
                if isLeft {
                    Circle().fill(AgentBuddy.ink).frame(width: dot, height: dot)
                } else {
                    closed
                }
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        let width: CGFloat = size * 0.22
        let line: CGFloat = max(1.5, size * 0.035)
        switch persona.mouth {
        case .smile:
            Circle()
                .trim(from: 0.1, to: 0.4)
                .stroke(AgentBuddy.ink, style: StrokeStyle(lineWidth: line, lineCap: CGLineCap.round))
                .frame(width: width, height: width)
                .offset(y: -width * 0.3)
        case .grin:
            Circle()
                .trim(from: 0, to: 0.5)
                .fill(AgentBuddy.ink)
                .frame(width: width, height: width)
                .offset(y: -width * 0.35)
        case .flat:
            Capsule().fill(AgentBuddy.ink).frame(width: width * 0.8, height: line)
        case .little:
            Circle().stroke(AgentBuddy.ink, lineWidth: line).frame(width: width * 0.4, height: width * 0.4)
        case .smirk:
            Circle()
                .trim(from: 0.05, to: 0.28)
                .stroke(AgentBuddy.ink, style: StrokeStyle(lineWidth: line, lineCap: CGLineCap.round))
                .frame(width: width, height: width)
                .offset(x: width * 0.15, y: -width * 0.3)
        }
    }

    private var cheeks: some View {
        HStack(spacing: size * 0.4) {
            Circle().fill(Color.tempo.accent.opacity(0.28)).frame(width: size * 0.13, height: size * 0.13)
            Circle().fill(Color.tempo.accent.opacity(0.28)).frame(width: size * 0.13, height: size * 0.13)
        }
        .offset(y: size * 0.08)
    }

    // MARK: Top

    @ViewBuilder
    private var top: some View {
        let line: CGFloat = max(1.5, size * 0.035)
        switch persona.top {
        case .antenna:
            VStack(spacing: 0) {
                Circle().fill(Color.tempo.accent).frame(width: size * 0.13, height: size * 0.13)
                Capsule().fill(AgentBuddy.ink).frame(width: line, height: size * 0.2)
            }
            .offset(y: -size * 0.52)
        case .sprout:
            Image(systemName: "leaf.fill")
                .font(Font.system(size: size * 0.24))
                .foregroundStyle(Color.tempo.yes)
                .rotationEffect(Angle.degrees(-30))
                .offset(x: size * 0.04, y: -size * 0.5)
        case .twoBuds:
            HStack(spacing: size * 0.3) {
                Circle().fill(AgentBuddy.ink).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(AgentBuddy.ink).frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: -size * 0.47)
        case .tuft:
            HStack(spacing: size * 0.03) {
                Capsule().fill(AgentBuddy.ink).frame(width: line, height: size * 0.14).rotationEffect(Angle.degrees(-20))
                Capsule().fill(AgentBuddy.ink).frame(width: line, height: size * 0.18)
                Capsule().fill(AgentBuddy.ink).frame(width: line, height: size * 0.14).rotationEffect(Angle.degrees(20))
            }
            .offset(y: -size * 0.5)
        case .none:
            EmptyView()
        }
    }
}

#Preview("Agent buddies") {
    let seeds: [String] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 24) {
        ForEach(seeds, id: \.self) { seed in
            let persona = AgentPersona.generate(seed: seed)
            VStack {
                AgentBuddy(persona: persona, size: 64)
                Text(persona.label).font(.caption2)
            }
        }
    }
    .padding()
}
