import SwiftUI

// MARK: - Chip

/// A small static label: "2 km away", "Long-term", "Premium".
///
///     Chip("Long-term", systemImage: "heart")
struct Chip: View {
    private let text: String
    private let systemImage: String?
    private let tone: TempoTone

    init(_ text: String, systemImage: String? = nil, tone: TempoTone = TempoTone.neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(Image.Scale.small)
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
        }
        .tempoText(.secondaryEmphasis)
        .foregroundStyle(Color.tempo.textPrimary)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 7)
        .background { shape.fill(fill) }
        .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.chip, style: .continuous)
    }

    /// Neutral chips are outlined on white; toned chips sit on their soft tint with no border.
    /// Text is always near-black (the tones do not reach 4.5:1 on their tints); the icon carries the tone.
    private var fill: Color {
        tone == TempoTone.neutral ? Color.tempo.background : tone.soft
    }

    private var stroke: Color {
        tone == TempoTone.neutral ? Color.tempo.hairline : Color.clear
    }
}

// MARK: - SelectableChip

/// A tappable capsule chip for single or multiple choice: outlined on white, filled black with
/// white text when selected.
///
///     SelectableChip("Marriage", isSelected: picked.contains(.marriage)) { toggle(.marriage) }
struct SelectableChip: View {
    private let text: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    init(_ text: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(Image.Scale.small)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .lineLimit(1)
            }
            .tempoText(.secondaryEmphasis)
            .foregroundStyle(isSelected ? Color.tempo.onAccent : Color.tempo.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: TempoSize.hitTarget)
            .background { Capsule().fill(isSelected ? Color.tempo.textPrimary : Color.tempo.background) }
            .overlay { Capsule().strokeBorder(isSelected ? Color.tempo.textPrimary : Color.tempo.hairlineStrong, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(TempoPressStyle(scale: 0.95))
        .animation(Animation.tempo.snappy, value: isSelected)
        .sensoryFeedback(SensoryFeedback.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

// MARK: - Flow layout

/// Lays children out left to right and wraps onto new lines. Use for chip groups.
///
///     FlowLayout(spacing: 8, lineSpacing: 8) { ForEach(options, id: \.self) { SelectableChip(...) } }
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = TempoSpacing.xs, lineSpacing: CGFloat = TempoSpacing.xs) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth: CGFloat = proposal.width ?? CGFloat.infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(ProposedViewSize.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width
            widest = max(widest, x)
            x += spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(ProposedViewSize.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: UnitPoint.topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: TempoSpacing.lg) {
        FlowLayout {
            Chip("2 km away", systemImage: "location")
            Chip("Long-term", tone: TempoTone.ember)
            Chip("Premium", tone: TempoTone.gold)
            Chip("Online", tone: TempoTone.mint)
            Chip("1 strike", tone: TempoTone.amber)
        }
        FlowLayout {
            SelectableChip("Long-term", isSelected: true, action: {})
            SelectableChip("Short-term", isSelected: false, action: {})
            SelectableChip("Marriage", isSelected: false, action: {})
            SelectableChip("Figuring it out", isSelected: true, action: {})
        }
    }
    .tempoScreenPadding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .inkBackground()
}
