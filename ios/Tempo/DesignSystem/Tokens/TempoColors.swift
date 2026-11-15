import SwiftUI

// MARK: - Color tokens
//
// "Daylight": light only. Every named color is backed by a color set in
// Resources/Assets.xcassets (see ios/Tools/generate_assets.py for the source values).
// The v1 surface/text names (`ink`, `plum`, `plumHi`, `ivory`, `ember`) are kept so screens
// keep compiling; each has a role alias (`background`, `surface`, `surface2`, `textPrimary`,
// `accent`) that new code should prefer.

/// The palette, reached through `Color.tempo`.
struct TempoColors: Sendable {
    // Surfaces
    /// App background, white. `#FFFFFF`. Also the text/glyph color on black and accent fills.
    let ink: Color = Color("ink")
    /// Surface: cards, fields, grouped rows. Warm off-white. `#F7F5F2`
    let plum: Color = Color("plum")
    /// Surface 2: pressed states, their chat bubble, tracks. `#EFEBE6`
    let plumHi: Color = Color("plumHi")
    /// 1 pt dividers and card borders. `#E6E1DB`
    let hairline: Color = Color("hairline")

    // Text
    /// Primary text and the primary button fill, near-black. `#1B1719`
    let ivory: Color = Color("ivory")
    /// Secondary text. `#6A6367`
    let textSecondary: Color = Color("textSecondary")
    /// Tertiary text; non-essential captions and placeholders only. `#A19A9E`
    let textTertiary: Color = Color("textTertiary")

    // Accent
    /// The one flat accent, warm vermilion. Fills, icons, rings and large text only. `#E4532F`
    let ember: Color = Color("ember")
    /// The accent for small text (4.5:1 on white). `#C8431F`
    let accentText: Color = Color("accentText")
    /// Tinted background for accent chips. `#FCE9E3`
    let accentSoft: Color = Color("accentSoft")

    // Semantic
    /// Yes. `#1F8A5B`
    let mint: Color = Color("mint")
    /// Soft tint of yes. `#E0F0E7`
    let mintSoft: Color = Color("mintSoft")
    /// No. `#6A6367`
    let ash: Color = Color("ash")
    /// Warning. `#B86E00`
    let amber: Color = Color("amber")
    /// Soft tint of warning. `#FBEFD6`
    let amberSoft: Color = Color("amberSoft")
    /// Danger / destructive. `#C9372C`
    let danger: Color = Color("danger")
    /// Premium, ochre. `#A8792A`
    let gold: Color = Color("gold")
    /// Soft tint of premium, cream. `#FAF1DC`
    let goldSoft: Color = Color("goldSoft")

    // Pastels, for icon tiles and photo-less avatars
    /// `#FBE4DE`
    let pastelBlush: Color = Color("pastelBlush")
    /// `#E1EFE6`
    let pastelSage: Color = Color("pastelSage")
    /// `#FBF0D2`
    let pastelButter: Color = Color("pastelButter")
    /// `#E2ECF7`
    let pastelSky: Color = Color("pastelSky")
    /// `#ECE6F5`
    let pastelLilac: Color = Color("pastelLilac")

    // Role aliases
    /// Screen background (white).
    var background: Color { ink }
    /// Cards, fields, grouped rows.
    var surface: Color { plum }
    /// Pressed states, tracks, their chat bubble.
    var surface2: Color { plumHi }
    /// Primary text (near-black).
    var textPrimary: Color { ivory }
    /// The flat accent.
    var accent: Color { ember }
    /// Text and glyphs on black, accent, mint and danger fills (white).
    var onAccent: Color { ink }
    /// A stronger outline for unselected chips and focused fields: near-black at 24%.
    var hairlineStrong: Color { ivory.opacity(0.24) }
    /// Alias of `mint`.
    var yes: Color { mint }
    /// Alias of `mintSoft`.
    var yesSoft: Color { mintSoft }
    /// Alias of `ash`.
    var no: Color { ash }
    /// Soft tint of no (surface 2).
    var noSoft: Color { plumHi }
    /// Alias of `amber`.
    var warning: Color { amber }
    /// Alias of `amberSoft`.
    var warningSoft: Color { amberSoft }
    /// Soft tint of danger: danger at 10% over white.
    var dangerSoft: Color { danger.opacity(0.10) }
    /// Alias of `gold`.
    var premium: Color { gold }
    /// Alias of `goldSoft`.
    var premiumSoft: Color { goldSoft }
}

extension Color {
    /// The design-system palette: `Color.tempo.ink`, `Color.tempo.ivory`, ...
    static let tempo: TempoColors = TempoColors()
}

// MARK: - Tone

/// A semantic tint shared by chips, rows, toasts and banners.
enum TempoTone: Hashable {
    case neutral
    case ember
    case mint
    case amber
    case danger
    case gold

    /// The color for icons, fills and large text in this tone.
    var color: Color {
        switch self {
        case .neutral: return Color.tempo.ivory
        case .ember: return Color.tempo.ember
        case .mint: return Color.tempo.mint
        case .amber: return Color.tempo.amber
        case .danger: return Color.tempo.danger
        case .gold: return Color.tempo.gold
        }
    }

    /// The color for small text in this tone on white. Only accent (darkened) and danger reach
    /// 4.5:1; mint, amber and ochre do not, so their small text stays near-black and the tone is
    /// carried by an icon or a soft tint instead.
    var textColor: Color {
        switch self {
        case .neutral, .mint, .amber, .gold: return Color.tempo.ivory
        case .ember: return Color.tempo.accentText
        case .danger: return Color.tempo.danger
        }
    }

    /// The soft background tint that pairs with `color`.
    var soft: Color {
        switch self {
        case .neutral: return Color.tempo.plum
        case .ember: return Color.tempo.accentSoft
        case .mint: return Color.tempo.mintSoft
        case .amber: return Color.tempo.amberSoft
        case .danger: return Color.tempo.dangerSoft
        case .gold: return Color.tempo.goldSoft
        }
    }
}

// MARK: - Pastels

/// The five pastel tints behind outlined icons (`IconTile`) and photo-less avatars.
/// Give each subject one pastel and keep it wherever that subject appears (a dealbreaker has the
/// same tile in You, in its locked row and in Edit profile). Conventions: sage = safety and
/// rules, butter = notifications and "unlimited", lilac = restore and legal, sky = account and
/// filters, blush = people, and the tile behind a destructive (danger-colored) icon.
enum TempoPastel: Hashable, CaseIterable {
    case blush
    case sage
    case butter
    case sky
    case lilac

    var color: Color {
        switch self {
        case .blush: return Color.tempo.pastelBlush
        case .sage: return Color.tempo.pastelSage
        case .butter: return Color.tempo.pastelButter
        case .sky: return Color.tempo.pastelSky
        case .lilac: return Color.tempo.pastelLilac
        }
    }

    /// The same pastel for the same string, forever (avatars without photos).
    static func deterministic(for string: String) -> TempoPastel {
        let all: [TempoPastel] = [TempoPastel.blush, TempoPastel.sage, TempoPastel.butter, TempoPastel.sky, TempoPastel.lilac]
        let index: Int = Int(TempoSeededGenerator.hash(string) % UInt64(all.count))
        return all[index]
    }
}

// MARK: - Raw components (for color math and Canvas drawing)

/// sRGB components used where colors have to be mixed in code (the clock warming from accent to amber).
struct TempoRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `TempoRGB(hex: 0xE4532F)`
    init(hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255.0
        self.green = Double((hex >> 8) & 0xFF) / 255.0
        self.blue = Double(hex & 0xFF) / 255.0
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Linear mix toward `other`; `amount` is clamped to 0...1.
    func mixed(with other: TempoRGB, amount: Double) -> TempoRGB {
        let t: Double = min(max(amount, 0.0), 1.0)
        return TempoRGB(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

/// The same values as the asset catalog, as raw components.
enum TempoPalette {
    static let ink: TempoRGB = TempoRGB(hex: 0xFFFFFF)
    static let plum: TempoRGB = TempoRGB(hex: 0xF7F5F2)
    static let plumHi: TempoRGB = TempoRGB(hex: 0xEFEBE6)
    static let hairline: TempoRGB = TempoRGB(hex: 0xE6E1DB)
    static let ivory: TempoRGB = TempoRGB(hex: 0x1B1719)
    static let ember: TempoRGB = TempoRGB(hex: 0xE4532F)
    static let mint: TempoRGB = TempoRGB(hex: 0x1F8A5B)
    static let ash: TempoRGB = TempoRGB(hex: 0x6A6367)
    static let amber: TempoRGB = TempoRGB(hex: 0xB86E00)
    static let danger: TempoRGB = TempoRGB(hex: 0xC9372C)
    static let gold: TempoRGB = TempoRGB(hex: 0xA8792A)
}
