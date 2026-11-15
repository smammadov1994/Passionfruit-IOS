import Foundation
import SwiftUI

// MARK: - Fills
//
// Daylight has no gradients on chrome. The accent, warning, premium and ash "gradients" below
// are flat: every stop is the same color. They remain only so shapes can be filled or stroked
// with a `ShapeStyle` of one type whatever the tone. The single real gradient is the video scrim.

enum TempoGradient {
    /// The flat accent as a fill.
    static var ember: LinearGradient { flat(Color.tempo.ember) }

    /// The flat warning amber as a fill (the clock's last 30 seconds).
    static var amber: LinearGradient { flat(Color.tempo.amber) }

    /// The flat premium ochre as a fill.
    static var gold: LinearGradient { flat(Color.tempo.gold) }

    /// The flat ash as a fill.
    static var ash: LinearGradient { flat(Color.tempo.ash) }

    /// Any color wrapped as a single-color fill.
    static func flat(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color], startPoint: UnitPoint.top, endPoint: UnitPoint.bottom)
    }

    /// Black fading to clear, for legibility over video only. `fromTop` puts the dark end at the top.
    /// `strength` is the darkest opacity and is capped at 0.35.
    static func scrim(fromTop: Bool, strength: Double = 0.35) -> LinearGradient {
        let peak: Double = min(max(strength, 0.0), 0.35)
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: Color.black.opacity(peak), location: 0.0),
            Gradient.Stop(color: Color.black.opacity(peak * 0.4), location: 0.5),
            Gradient.Stop(color: Color.black.opacity(0.0), location: 1.0)
        ]
        return LinearGradient(
            stops: stops,
            startPoint: fromTop ? UnitPoint.top : UnitPoint.bottom,
            endPoint: fromTop ? UnitPoint.bottom : UnitPoint.top
        )
    }
}

// MARK: - Deterministic randomness

/// SplitMix64. Deterministic across launches, unlike `Hasher`.
struct TempoSeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    /// An index in 0..<count.
    mutating func nextIndex(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(next() % UInt64(count))
    }

    /// FNV-1a over the UTF-8 bytes; stable for the same string forever.
    static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001B3
        }
        return hash
    }
}
