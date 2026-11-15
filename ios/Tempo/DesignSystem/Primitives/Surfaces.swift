import SwiftUI

// MARK: - Eyebrow

/// A small uppercase label that sits above a headline or section.
///
///     Eyebrow("Tonight")
struct Eyebrow: View {
    private let text: String
    private let color: Color

    init(_ text: String, color: Color = Color.tempo.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .tempoText(.eyebrow)
            .foregroundStyle(color)
            .accessibilityAddTraits(AccessibilityTraits.isHeader)
    }
}

// MARK: - ScreenHeader

/// The standard headline block: eyebrow, serif title (with an optional italic last word), subtitle.
///
///     ScreenHeader(eyebrow: "Tonight", title: "Meet someone", emphasis: "new.", subtitle: "Four minutes, face to face.")
struct ScreenHeader: View {
    private let eyebrow: String?
    private let title: String
    private let emphasis: String?
    private let subtitle: String?
    private let alignment: HorizontalAlignment
    private let style: TempoTextStyle

    init(
        eyebrow: String? = nil,
        title: String,
        emphasis: String? = nil,
        subtitle: String? = nil,
        alignment: HorizontalAlignment = HorizontalAlignment.leading,
        style: TempoTextStyle = TempoTextStyle.displayS
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.emphasis = emphasis
        self.subtitle = subtitle
        self.alignment = alignment
        self.style = style
    }

    var body: some View {
        VStack(alignment: alignment, spacing: TempoSpacing.sm) {
            if let eyebrow {
                Eyebrow(eyebrow)
            }
            titleText
                .tempoText(style)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            if let subtitle {
                Text(subtitle)
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var titleText: Text {
        if let emphasis {
            return Text(title) + Text(" ") + Text(emphasis).italic()
        }
        return Text(title)
    }

    private var textAlignment: TextAlignment {
        alignment == HorizontalAlignment.center ? TextAlignment.center : TextAlignment.leading
    }

    private var frameAlignment: Alignment {
        alignment == HorizontalAlignment.center ? Alignment.center : Alignment.leading
    }
}

// MARK: - TempoCard

/// Look of a `TempoCard`. Cards are defined by borders, never shadows.
enum TempoCardKind: Hashable {
    /// Warm off-white surface with a hairline. Fields, notes, grouped content.
    case raised
    /// White with a hairline and the one soft shadow. Over video or imagery only.
    case floating
    /// White with a hairline. Lists of icon-tile rows.
    case outlined
    /// Cream surface. Premium content.
    case gold
}

/// A rounded-16 container.
///
///     TempoCard { Text("Hello") }
struct TempoCard<Content: View>: View {
    private let kind: TempoCardKind
    private let padding: CGFloat
    private let content: Content

    init(kind: TempoCardKind = TempoCardKind.raised, padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { surface }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }

    @ViewBuilder
    private var surface: some View {
        switch kind {
        case .raised:
            Color.clear.tempoSurface(in: shape, fill: Color.tempo.surface)
        case .floating:
            Color.clear.tempoSurface(in: shape, isFloating: true)
        case .outlined:
            Color.clear.tempoSurface(in: shape)
        case .gold:
            shape.fill(Color.tempo.premiumSoft)
        }
    }
}

// MARK: - FloatingCapsule

/// A white capsule with a hairline and the one soft shadow, for small clusters over video
/// (partner label, status pills).
///
///     FloatingCapsule { Text("Maya, 29").tempoText(.secondaryEmphasis) }
struct FloatingCapsule<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let content: Content

    init(horizontalPadding: CGFloat = TempoSpacing.md, verticalPadding: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(Color.tempo.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .tempoSurface(in: Capsule(), isFloating: true)
    }
}

// MARK: - Bottom sheet surface

/// The white sheet that rises from the bottom edge over video (the Verdict): top corners at the
/// sheet radius, the one soft shadow, white carried down through the home-indicator area.
struct TempoBottomSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: TempoRadius.sheet,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: TempoRadius.sheet,
                    style: .continuous
                )
                .fill(Color.tempo.background)
                .tempoShadow(TempoShadow.floating)
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    /// Wraps content in the white bottom-sheet surface. Give the content its own padding first.
    func tempoBottomSheet() -> some View {
        modifier(TempoBottomSheetModifier())
    }
}

// MARK: - IconTile

/// A 36 pt rounded-10 pastel tile behind an outlined icon. The row pattern for settings, profile
/// basics and paywall benefits. Pass the OUTLINED symbol name; pick one pastel per category
/// (see `TempoPastel`) and keep it.
///
///     IconTile(systemName: "bell", tint: .sky)
struct IconTile: View {
    private let systemName: String
    private let fill: Color
    private let glyph: Color

    init(systemName: String, tint: TempoPastel) {
        self.systemName = systemName
        self.fill = tint.color
        self.glyph = Color.tempo.textPrimary
    }

    /// A tile in a semantic tone: tone-colored icon on the tone's soft tint (warning, yes), or on
    /// blush for danger rows.
    init(systemName: String, tone: TempoTone) {
        self.systemName = systemName
        self.fill = tone == TempoTone.danger ? Color.tempo.pastelBlush : tone.soft
        self.glyph = tone.color
    }

    var body: some View {
        Image(systemName: systemName)
            .font(Font.system(size: 17, weight: Font.Weight.regular))
            .foregroundStyle(glyph)
            .frame(width: TempoSize.iconTile, height: TempoSize.iconTile)
            .background {
                RoundedRectangle(cornerRadius: TempoRadius.tile, style: .continuous).fill(fill)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - SheetGrabber

/// The small handle at the top of sheets and the turn card.
struct SheetGrabber: View {
    init() {}

    var body: some View {
        Capsule()
            .fill(Color.tempo.hairline)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, TempoSpacing.xs)
            .accessibilityHidden(true)
    }
}

// MARK: - TempoDivider

/// A hairline separator.
struct TempoDivider: View {
    init() {}

    var body: some View {
        Rectangle()
            .fill(Color.tempo.hairline)
            .frame(height: TempoSize.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - TempoRow

/// A tappable settings/navigation row: pastel icon tile, title, optional trailing value, chevron.
///
///     TempoRow(title: "Notifications", value: "On", systemImage: "bell", tile: .sky) { openNotifications() }
struct TempoRow: View {
    private let title: String
    private let value: String?
    private let systemImage: String?
    private let tone: TempoTone
    private let tile: TempoPastel
    private let showsChevron: Bool
    private let action: () -> Void

    init(
        title: String,
        value: String? = nil,
        systemImage: String? = nil,
        tone: TempoTone = TempoTone.neutral,
        tile: TempoPastel = TempoPastel.blush,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tone = tone
        self.tile = tile
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TempoSpacing.sm) {
                if let systemImage {
                    rowIcon(systemImage)
                }
                Text(title)
                    .tempoText(.body)
                    .foregroundStyle(tone.textColor)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: TempoSpacing.sm)
                if let value {
                    Text(value)
                        .tempoText(.secondary)
                        .foregroundStyle(Color.tempo.textSecondary)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(Font.system(size: 13, weight: Font.Weight.semibold))
                        .foregroundStyle(Color.tempo.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.99))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rowIcon(_ systemImage: String) -> some View {
        if tone == TempoTone.neutral {
            IconTile(systemName: systemImage, tint: tile)
        } else {
            IconTile(systemName: systemImage, tone: tone)
        }
    }
}

#Preview("Surfaces") {
    ScrollView {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            ScreenHeader(eyebrow: "Tonight", title: "Meet someone", emphasis: "new.", subtitle: "Four minutes, face to face.")
            TempoCard {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Eyebrow("About")
                    Text("Surface card with a hairline.").tempoText(.body, color: Color.tempo.textPrimary)
                }
            }
            TempoCard(kind: TempoCardKind.gold) {
                Text("Cream card.").tempoText(.body, color: Color.tempo.textPrimary)
            }
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    TempoRow(title: "Notifications", value: "On", systemImage: "bell", tile: TempoPastel.sky, action: {})
                    TempoDivider()
                    TempoRow(title: "Delete account", systemImage: "trash", tone: TempoTone.danger, showsChevron: false, action: {})
                }
            }
            HStack(spacing: TempoSpacing.xs) {
                IconTile(systemName: "person", tint: TempoPastel.blush)
                IconTile(systemName: "shield", tint: TempoPastel.sage)
                IconTile(systemName: "infinity", tint: TempoPastel.butter)
                IconTile(systemName: "bell", tint: TempoPastel.sky)
                IconTile(systemName: "doc.text", tint: TempoPastel.lilac)
            }
            FloatingCapsule { Text("Maya, 29").tempoText(.secondaryEmphasis) }
            SheetGrabber()
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xl)
    }
    .inkBackground()
}
