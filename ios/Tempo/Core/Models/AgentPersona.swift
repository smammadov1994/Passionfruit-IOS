import Foundation

/// The little character that stands for a match's agent. Generated from the match id, so every
/// match gets its own and it stays the same from launch to launch.
struct AgentPersona: Sendable, Equatable {
    /// Body colour. Ten of them, so a list of matches rarely repeats one.
    enum Hue: Sendable, CaseIterable {
        case blush, butter, sage, lilac, sky, coral, mint, peach, periwinkle, rose
    }

    /// Body silhouette.
    enum Body: Sendable, CaseIterable {
        case round, squircle, bean, drop, bun, gumdrop, scallop, pebble
    }

    enum Eyes: Sendable, CaseIterable { case dots, tall, wide, sleepy, wink }
    enum Mouth: Sendable, CaseIterable { case smile, grin, flat, little, smirk }
    enum Top: Sendable, CaseIterable { case antenna, sprout, twoBuds, tuft, none }

    /// How the character talks: one of a fixed set, each with its own asides.
    enum Temper: Sendable, CaseIterable {
        case optimist, planner, romantic, realist, wit, nightOwl, gentle, bold

        var title: String {
            switch self {
            case .optimist: return String(localized: "the optimist")
            case .planner: return String(localized: "the planner")
            case .romantic: return String(localized: "the romantic")
            case .realist: return String(localized: "the realist")
            case .wit: return String(localized: "the wit")
            case .nightOwl: return String(localized: "the night owl")
            case .gentle: return String(localized: "the gentle one")
            case .bold: return String(localized: "the bold one")
            }
        }

        /// What it adds when there is something for the user to do.
        var nudge: String {
            switch self {
            case .optimist: return String(localized: "I have a good feeling about this one.")
            case .planner: return String(localized: "I've lined up the next step.")
            case .romantic: return String(localized: "Don't leave them wondering.")
            case .realist: return String(localized: "A short reply beats a perfect one.")
            case .wit: return String(localized: "I wrote you something better than \"hey\".")
            case .nightOwl: return String(localized: "Best answered before midnight. Probably.")
            case .gentle: return String(localized: "No rush. I kept your place.")
            case .bold: return String(localized: "Say the thing.")
            }
        }

        /// What it adds when the ball is in the other court.
        var patience: String {
            switch self {
            case .optimist: return String(localized: "They'll write. I'd bet a wash of yellow on it.")
            case .planner: return String(localized: "Nothing due. I'm watching the clock for you.")
            case .romantic: return String(localized: "Anticipation is half of it.")
            case .realist: return String(localized: "Could be busy. Could be nothing. We'll see.")
            case .wit: return String(localized: "Your move was good. Their turn to be clever.")
            case .nightOwl: return String(localized: "Quiet hours. I'll stay up.")
            case .gentle: return String(localized: "All calm here.")
            case .bold: return String(localized: "You did your part. Hold the line.")
            }
        }
    }

    var name: String
    var temper: Temper
    var hue: Hue
    var body: Body
    var eyes: Eyes
    var mouth: Mouth
    var top: Top
    /// A few degrees of lean, so no two sit quite the same way.
    var tilt: Double
    var hasCheeks: Bool

    /// "Pip · the planner"
    var label: String { "\(name) · \(temper.title)" }

    /// The persona for a seed (a match id). Same seed, same character.
    static func generate(seed: String) -> AgentPersona {
        var generator = SeededGenerator(seed: seed)
        let starts: [String] = ["Pi", "Mo", "Lu", "Ze", "Ko", "Bi", "Nu", "Ta", "Fi", "Jo", "Ru", "Ye", "Do", "Ki"]
        let ends: [String] = ["p", "x", "mi", "bo", "ro", "la", "zu", "n", "ko", "t", "sa", "b"]
        return AgentPersona(
            name: generator.pick(starts) + generator.pick(ends),
            temper: generator.pick(Temper.allCases),
            hue: generator.pick(Hue.allCases),
            body: generator.pick(Body.allCases),
            eyes: generator.pick(Eyes.allCases),
            mouth: generator.pick(Mouth.allCases),
            top: generator.pick(Top.allCases),
            tilt: Double(generator.next() % 17) - 8,
            hasCheeks: generator.next() % 3 == 0
        )
    }
}

extension AgentPersona {
    /// Personas for a whole list, in order. Each is generated from its own seed, then nudged so
    /// that colour, silhouette and temper do not repeat while unused ones remain: a screen of
    /// matches shows a varied cast. Stable for a given list.
    static func cast(for seeds: [String]) -> [String: AgentPersona] {
        var result: [String: AgentPersona] = [:]
        var hues: [Hue] = []
        var bodies: [Body] = []
        var tempers: [Temper] = []
        for seed in seeds {
            var persona: AgentPersona = generate(seed: seed)
            persona.hue = firstUnused(persona.hue, in: Hue.allCases, used: hues)
            persona.body = firstUnused(persona.body, in: Body.allCases, used: bodies)
            persona.temper = firstUnused(persona.temper, in: Temper.allCases, used: tempers)
            hues.append(persona.hue)
            bodies.append(persona.body)
            tempers.append(persona.temper)
            result[seed] = persona
        }
        return result
    }

    /// `preferred` if nobody has it yet, else the next one along that nobody has; once every
    /// option is taken, `preferred` again.
    private static func firstUnused<T: Equatable>(_ preferred: T, in all: [T], used: [T]) -> T {
        guard used.contains(preferred), let start = all.firstIndex(of: preferred) else { return preferred }
        for step in 1..<all.count {
            let candidate: T = all[(start + step) % all.count]
            if !used.contains(candidate) {
                return candidate
            }
        }
        return preferred
    }
}

/// A small deterministic generator (FNV-1a seed, xorshift steps). `String.hashValue` changes on
/// every launch, so it cannot be used for characters that must stay the same.
struct SeededGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        state = hash == 0 ? 0x9e37_79b9_7f4a_7c15 : hash
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func pick<T>(_ options: [T]) -> T {
        options[Int(next() % UInt64(options.count))]
    }
}
