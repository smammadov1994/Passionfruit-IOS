import SwiftUI

// Ochre and cream are reserved for Premium. Nothing else in the app uses them.
// Ochre is for icons and details only: it does not reach 4.5:1 on white, so text stays near-black.

// MARK: - PremiumBadge

/// A small cream capsule with the brand mark, for premium members and premium-only features.
///
///     PremiumBadge()            // "Premium" capsule
///     PremiumBadge(compact: true)   // icon only
struct PremiumBadge: View {
    private let text: String
    private let compact: Bool

    init(text: String = "Premium", compact: Bool = false) {
        self.text = text
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 5) {
            BrandMark(size: 18)
            if !compact {
                Text(text)
                    .tempoText(.eyebrow)
                    .foregroundStyle(Color.tempo.textPrimary)
            }
        }
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 7 : 6)
        .background { Capsule().fill(Color.tempo.premiumSoft) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

// MARK: - PaywallHero

/// The top of the Premium screen, left-aligned: the cream badge carrying the eyebrow, then the
/// serif headline with an italic last word. Pass the eyebrow from the app-name constant.
///
///     PaywallHero(eyebrow: "\(appName) Premium")
struct PaywallHero: View {
    private let eyebrow: String
    private let headline: String
    private let emphasis: String?

    init(eyebrow: String, headline: String = "Never run out of", emphasis: String? = "evenings.") {
        self.eyebrow = eyebrow
        self.headline = headline
        self.emphasis = emphasis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            PremiumBadge(text: eyebrow)
            headlineText
                .tempoText(.displayS)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineText: Text {
        if let emphasis {
            return Text(headline) + Text(" ") + Text(emphasis).italic()
        }
        return Text(headline)
    }
}

// MARK: - BenefitRow

/// One premium benefit: a pastel icon tile, a title and a sentence.
///
///     BenefitRow(systemImage: "infinity", title: "Unlimited dates", detail: "Keep going as long as the night does.")
struct BenefitRow: View {
    private let systemImage: String
    private let title: String
    private let detail: String
    private let tint: TempoPastel

    init(systemImage: String, title: String, detail: String, tint: TempoPastel = TempoPastel.butter) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            IconTile(systemName: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(detail)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - PriceTag

/// The price on a cream card: near-black numerals, the period, an optional reassurance line.
/// Pass the localized price string from StoreKit.
///
///     PriceTag(price: "$14.99", period: "month", note: "Cancel anytime in Settings.")
struct PriceTag: View {
    private let price: String
    private let period: String
    private let note: String?

    init(price: String, period: String = "month", note: String? = nil) {
        self.price = price
        self.period = period
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(price)
                    .tempoText(.numeralXL)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ \(period)")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
            }
            if let note {
                Text(note)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous).fill(Color.tempo.premiumSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(price) per \(period)"))
        .accessibilityValue(Text(note ?? ""))
    }
}

// MARK: - LockedRow

/// A premium-only filter row shown to free members: butter icon tile, title, optional detail and
/// an ochre outlined lock. Tapping it should open the paywall.
///
///     LockedRow(title: "Religion", detail: "Any", systemImage: "book") { showPaywall = true }
struct LockedRow: View {
    private let title: String
    private let detail: String?
    private let systemImage: String?
    private let tile: TempoPastel
    private let action: () -> Void

    init(title: String, detail: String? = nil, systemImage: String? = nil, tile: TempoPastel = TempoPastel.butter, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tile = tile
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TempoSpacing.sm) {
                if let systemImage {
                    IconTile(systemName: systemImage, tint: tile)
                }
                Text(title)
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: TempoSpacing.sm)
                if let detail {
                    Text(detail)
                        .tempoText(.secondary)
                        .foregroundStyle(Color.tempo.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "lock")
                    .font(Font.system(size: 15, weight: Font.Weight.regular))
                    .foregroundStyle(Color.tempo.premium)
                    .frame(width: 28, height: 28)
                    .background { Circle().fill(Color.tempo.premiumSoft) }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("Locked"))
        .accessibilityHint(Text("Premium filter. Opens Premium."))
        .accessibilityAddTraits(AccessibilityTraits.isButton)
        .accessibilityAction {
            action()
        }
    }
}

// MARK: - Preview

#Preview("Premium") {
    ScrollView {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            PaywallHero(eyebrow: "Premium")
            VStack(spacing: TempoSpacing.md) {
                BenefitRow(systemImage: "infinity", title: "Unlimited dates", detail: "Keep going as long as the night does.")
                BenefitRow(systemImage: "slider.horizontal.3", title: "Dealbreaker filters", detail: "Intentions, children, faith, and more.", tint: TempoPastel.sage)
                BenefitRow(systemImage: "bolt", title: "Front of the line", detail: "Get paired first when it's busy.", tint: TempoPastel.sky)
            }
            PriceTag(price: "$14.99", period: "month", note: "Cancel anytime in Settings.")
            TempoButton("Continue", variant: TempoButtonVariant.premium, action: {})
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    LockedRow(title: "Religion", detail: "Any", systemImage: "book", action: {})
                    TempoDivider()
                    LockedRow(title: "Children", detail: "Any", action: {})
                }
            }
            PremiumBadge()
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xl)
    }
    .inkBackground()
}
