import SwiftUI
import UIKit

// MARK: - Text styles
//
// Display: New York (system serif), MEDIUM weight, near-black, tracking -0.4 to -0.8, 28-44 pt.
// UI/body: SF Pro, 17 / 15 / 13. Numerals: SF Pro (default design), monospaced digits, semibold.
//
// Apply with `.tempoText(.displayL)`; this scales with Dynamic Type (relative to a
// system text style) and caps growth so large type never clips. When a `Font` value is
// needed instead, use `Font.tempo.displayL`.

/// A complete type recipe: size, weight, design, tracking, case and Dynamic Type behaviour.
struct TempoTextStyle {
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design
    var relativeTo: Font.TextStyle
    var tracking: CGFloat
    var isItalic: Bool
    var isUppercase: Bool
    var monospacedDigits: Bool
    /// Upper bound on Dynamic Type growth, as a multiple of `size`.
    var maxScale: CGFloat
    var lineSpacing: CGFloat

    init(
        size: CGFloat,
        weight: Font.Weight = Font.Weight.regular,
        design: Font.Design = Font.Design.default,
        relativeTo: Font.TextStyle = Font.TextStyle.body,
        tracking: CGFloat = 0,
        isItalic: Bool = false,
        isUppercase: Bool = false,
        monospacedDigits: Bool = false,
        maxScale: CGFloat = 1.6,
        lineSpacing: CGFloat = 0
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.relativeTo = relativeTo
        self.tracking = tracking
        self.isItalic = isItalic
        self.isUppercase = isUppercase
        self.monospacedDigits = monospacedDigits
        self.maxScale = maxScale
        self.lineSpacing = lineSpacing
    }

    /// The same style in italic (serif italic for a single emphasised word or line).
    func italic() -> TempoTextStyle {
        var copy: TempoTextStyle = self
        copy.isItalic = true
        return copy
    }

    /// The same style at another weight.
    func weighted(_ newWeight: Font.Weight) -> TempoTextStyle {
        var copy: TempoTextStyle = self
        copy.weight = newWeight
        return copy
    }

    /// The font at an explicit point size (no Dynamic Type applied).
    func font(size resolvedSize: CGFloat) -> Font {
        var font: Font = Font.system(size: resolvedSize, weight: weight, design: design)
        if isItalic {
            font = font.italic()
        }
        if monospacedDigits {
            font = font.monospacedDigit()
        }
        return font
    }

    /// The font scaled for the current system Dynamic Type setting, capped at `maxScale`.
    var scaledFont: Font {
        let metrics: UIFontMetrics = UIFontMetrics(forTextStyle: TempoTextStyle.uiTextStyle(for: relativeTo))
        let scaled: CGFloat = metrics.scaledValue(for: size)
        return font(size: min(scaled, size * maxScale))
    }

    private static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return UIFont.TextStyle.largeTitle
        case .title: return UIFont.TextStyle.title1
        case .title2: return UIFont.TextStyle.title2
        case .title3: return UIFont.TextStyle.title3
        case .headline: return UIFont.TextStyle.headline
        case .subheadline: return UIFont.TextStyle.subheadline
        case .callout: return UIFont.TextStyle.callout
        case .footnote: return UIFont.TextStyle.footnote
        case .caption: return UIFont.TextStyle.caption1
        case .caption2: return UIFont.TextStyle.caption2
        default: return UIFont.TextStyle.body
        }
    }
}

// MARK: - The scale

extension TempoTextStyle {
    // Display serif
    /// 44 pt serif. The largest size; the match moment.
    static var displayXL: TempoTextStyle { serif(44, tracking: -0.8) }
    /// 44 pt serif. "It's mutual.", hero headlines.
    static var displayL: TempoTextStyle { serif(44, tracking: -0.8) }
    /// 40 pt serif. Partner names on full-screen moments.
    static var displayM: TempoTextStyle { serif(40, tracking: -0.8) }
    /// 34 pt serif. Standard screen title and onboarding question.
    static var displayS: TempoTextStyle { serif(34, tracking: -0.7) }
    /// 28 pt serif. Sheet and card headlines, empty states.
    static var title: TempoTextStyle { serif(28, tracking: -0.5, maxScale: 1.3) }
    /// 24 pt serif. Icebreaker questions, names in lists.
    static var titleS: TempoTextStyle { serif(24, tracking: -0.4, maxScale: 1.4) }
    /// 20 pt serif. Lines with a voice.
    static var serifBody: TempoTextStyle { serif(20, tracking: -0.3, maxScale: 1.5) }

    // UI
    /// 17 pt body.
    static var body: TempoTextStyle {
        TempoTextStyle(size: 17, relativeTo: Font.TextStyle.body, lineSpacing: 4)
    }
    /// 17 pt semibold, for emphasis and row titles.
    static var bodyEmphasis: TempoTextStyle {
        TempoTextStyle(size: 17, weight: Font.Weight.semibold, relativeTo: Font.TextStyle.body)
    }
    /// 17 pt semibold button label.
    static var button: TempoTextStyle {
        TempoTextStyle(size: 17, weight: Font.Weight.semibold, relativeTo: Font.TextStyle.body, tracking: -0.2, maxScale: 1.35)
    }
    /// 15 pt secondary text.
    static var secondary: TempoTextStyle {
        TempoTextStyle(size: 15, relativeTo: Font.TextStyle.subheadline, lineSpacing: 3)
    }
    /// 15 pt medium, for chips and compact buttons.
    static var secondaryEmphasis: TempoTextStyle {
        TempoTextStyle(size: 15, weight: Font.Weight.medium, relativeTo: Font.TextStyle.subheadline, maxScale: 1.4)
    }
    /// 13 pt caption.
    static var caption: TempoTextStyle {
        TempoTextStyle(size: 13, relativeTo: Font.TextStyle.footnote, lineSpacing: 2)
    }
    /// 11 pt medium. Tab bar labels (semibold when selected: `.tabLabel.weighted(.semibold)`).
    static var tabLabel: TempoTextStyle {
        TempoTextStyle(size: 11, weight: Font.Weight.medium, relativeTo: Font.TextStyle.caption2, tracking: 0.1, maxScale: 1.3)
    }
    /// 12 pt semibold, uppercase, +0.8 tracking. Section and screen eyebrows.
    static var eyebrow: TempoTextStyle {
        TempoTextStyle(
            size: 12,
            weight: Font.Weight.semibold,
            relativeTo: Font.TextStyle.footnote,
            tracking: 0.8,
            isUppercase: true,
            maxScale: 1.4
        )
    }

    // Numerals
    /// 44 pt monospaced numerals. Large countdowns.
    static var numeralXL: TempoTextStyle { numerals(44, maxScale: 1.2) }
    /// 28 pt monospaced numerals.
    static var numeralL: TempoTextStyle { numerals(28, maxScale: 1.3) }
    /// 17 pt monospaced numerals. The date clock.
    static var numeral: TempoTextStyle { numerals(17, maxScale: 1.3) }
    /// 13 pt monospaced numerals. Inline counts.
    static var numeralS: TempoTextStyle { numerals(13, maxScale: 1.4) }

    /// Any serif display size. Medium weight, never bold.
    static func serif(_ size: CGFloat, tracking: CGFloat = -0.6, maxScale: CGFloat = 1.25) -> TempoTextStyle {
        TempoTextStyle(
            size: size,
            weight: Font.Weight.medium,
            design: Font.Design.serif,
            relativeTo: Font.TextStyle.largeTitle,
            tracking: tracking,
            maxScale: maxScale,
            lineSpacing: size >= 28 ? 2 : 3
        )
    }

    /// Any numeral size: SF Pro, monospaced digits, semibold.
    static func numerals(_ size: CGFloat, maxScale: CGFloat = 1.3) -> TempoTextStyle {
        TempoTextStyle(
            size: size,
            weight: Font.Weight.semibold,
            design: Font.Design.default,
            relativeTo: Font.TextStyle.body,
            monospacedDigits: true,
            maxScale: maxScale
        )
    }
}

// MARK: - Font.tempo

/// `Font` values for the scale, reached through `Font.tempo`. Scaled for Dynamic Type.
struct TempoFonts {
    var displayXL: Font { TempoTextStyle.displayXL.scaledFont }
    var displayL: Font { TempoTextStyle.displayL.scaledFont }
    var displayM: Font { TempoTextStyle.displayM.scaledFont }
    var displayS: Font { TempoTextStyle.displayS.scaledFont }
    var title: Font { TempoTextStyle.title.scaledFont }
    var titleS: Font { TempoTextStyle.titleS.scaledFont }
    var serifBody: Font { TempoTextStyle.serifBody.scaledFont }
    var body: Font { TempoTextStyle.body.scaledFont }
    var bodyEmphasis: Font { TempoTextStyle.bodyEmphasis.scaledFont }
    var button: Font { TempoTextStyle.button.scaledFont }
    var secondary: Font { TempoTextStyle.secondary.scaledFont }
    var secondaryEmphasis: Font { TempoTextStyle.secondaryEmphasis.scaledFont }
    var caption: Font { TempoTextStyle.caption.scaledFont }
    var eyebrow: Font { TempoTextStyle.eyebrow.scaledFont }
    var numeralXL: Font { TempoTextStyle.numeralXL.scaledFont }
    var numeralL: Font { TempoTextStyle.numeralL.scaledFont }
    var numeral: Font { TempoTextStyle.numeral.scaledFont }
    var numeralS: Font { TempoTextStyle.numeralS.scaledFont }

    /// Serif display at any size.
    func display(_ size: CGFloat) -> Font {
        TempoTextStyle.serif(size).scaledFont
    }

    /// Serif display italic at any size.
    func displayItalic(_ size: CGFloat) -> Font {
        TempoTextStyle.serif(size).italic().scaledFont
    }

    /// Monospaced numerals at any size.
    func numerals(_ size: CGFloat) -> Font {
        TempoTextStyle.numerals(size).scaledFont
    }
}

extension Font {
    /// The design-system type scale: `Font.tempo.displayL`, `Font.tempo.body`, ...
    static var tempo: TempoFonts { TempoFonts() }
}

// MARK: - Modifier

/// Applies a `TempoTextStyle` with live Dynamic Type scaling.
struct TempoTextModifier: ViewModifier {
    private let style: TempoTextStyle
    @ScaledMetric private var scaledSize: CGFloat

    init(style: TempoTextStyle) {
        self.style = style
        self._scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font(size: min(scaledSize, style.size * style.maxScale)))
            .tracking(style.tracking)
            .textCase(style.isUppercase ? Text.Case.uppercase : nil)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Applies a text style: `Text("It's mutual.").tempoText(.displayL.italic())`.
    /// Sets font, tracking, case and line spacing; scales with Dynamic Type.
    func tempoText(_ style: TempoTextStyle) -> some View {
        modifier(TempoTextModifier(style: style))
    }

    /// Text style plus color in one call: `.tempoText(.secondary, color: Color.tempo.textSecondary)`.
    func tempoText(_ style: TempoTextStyle, color: Color) -> some View {
        modifier(TempoTextModifier(style: style)).foregroundStyle(color)
    }
}
