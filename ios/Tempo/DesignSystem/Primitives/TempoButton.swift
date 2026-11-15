import SwiftUI

// MARK: - Variants

/// Which button to use:
/// - `primary`: the one main action on a screen (Continue, Say hello, Save). A BLACK capsule with white text.
/// - `secondary`: white with a 1 pt black border; the alternative next to a primary.
/// - `ghost`: text only; quiet exits (Stop for tonight, Not now, Restore purchases).
/// - `destructive`: delete account, unmatch, block. White with a danger border and danger text.
/// - `premium`: the purchase action and upsell entry points. Black like primary; an icon passed
///   to `TempoButton` is tinted ochre.
enum TempoButtonVariant: Hashable {
    case primary
    case secondary
    case ghost
    case destructive
    case premium
}

enum TempoButtonSize: Hashable {
    /// 54 pt. Screen-level calls to action.
    case large
    /// 48 pt. Inside cards and sheets.
    case regular
    /// 36 pt visual height (44 pt hit area). Inline pills.
    case compact

    var minHeight: CGFloat {
        switch self {
        case .large: return TempoSize.buttonLarge
        case .regular: return TempoSize.buttonRegular
        case .compact: return TempoSize.buttonCompact
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .large: return TempoSpacing.lg
        case .regular: return 20
        case .compact: return TempoSpacing.md
        }
    }

    var textStyle: TempoTextStyle {
        switch self {
        case .large, .regular: return TempoTextStyle.button
        case .compact: return TempoTextStyle.secondaryEmphasis
        }
    }
}

// MARK: - Button style

/// The capsule button style. `Button("Go online") { }.buttonStyle(.tempoPrimary)`
struct TempoButtonStyle: ButtonStyle {
    let variant: TempoButtonVariant
    let size: TempoButtonSize
    let fullWidth: Bool

    init(_ variant: TempoButtonVariant = TempoButtonVariant.primary, size: TempoButtonSize = TempoButtonSize.large, fullWidth: Bool = true) {
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        TempoButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            variant: variant,
            size: size,
            fullWidth: fullWidth
        )
    }
}

extension ButtonStyle where Self == TempoButtonStyle {
    /// Black capsule, large, full width.
    static var tempoPrimary: TempoButtonStyle { TempoButtonStyle(TempoButtonVariant.primary) }
    /// White capsule with a black border, large, full width.
    static var tempoSecondary: TempoButtonStyle { TempoButtonStyle(TempoButtonVariant.secondary) }
    /// Text only, large, full width.
    static var tempoGhost: TempoButtonStyle { TempoButtonStyle(TempoButtonVariant.ghost) }
    /// Danger-outlined capsule, large, full width.
    static var tempoDestructive: TempoButtonStyle { TempoButtonStyle(TempoButtonVariant.destructive) }
    /// Black capsule for purchases, large, full width.
    static var tempoPremium: TempoButtonStyle { TempoButtonStyle(TempoButtonVariant.premium) }

    /// Any variant at any size: `.buttonStyle(.tempo(.secondary, size: .compact, fullWidth: false))`.
    static func tempo(_ variant: TempoButtonVariant, size: TempoButtonSize = TempoButtonSize.large, fullWidth: Bool = true) -> TempoButtonStyle {
        TempoButtonStyle(variant, size: size, fullWidth: fullWidth)
    }
}

private struct TempoButtonStyleBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let variant: TempoButtonVariant
    let size: TempoButtonSize
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .tempoText(size.textStyle)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil, minHeight: size.minHeight)
            .background { surface }
            .frame(minHeight: max(size.minHeight, TempoSize.hitTarget))
            .contentShape(Rectangle())
            .scaleEffect(pressScale)
            .opacity(isEnabled ? 1.0 : 0.35)
            .animation(Animation.tempo.press, value: isPressed)
            .tempoPressClick(isPressed: isPressed)
    }

    private var pressScale: CGFloat {
        if reduceMotion {
            return 1.0
        }
        return isPressed ? 0.96 : 1.0
    }

    private var foreground: Color {
        switch variant {
        case .primary, .premium: return Color.tempo.onAccent
        case .secondary, .ghost: return Color.tempo.textPrimary
        case .destructive: return Color.tempo.danger
        }
    }

    @ViewBuilder
    private var surface: some View {
        switch variant {
        case .primary, .premium:
            Capsule()
                .fill(Color.tempo.textPrimary)
                .opacity(isPressed ? 0.82 : 1.0)
        case .secondary:
            Capsule()
                .fill(isPressed ? Color.tempo.surface2 : Color.tempo.background)
                .overlay { Capsule().strokeBorder(Color.tempo.textPrimary, lineWidth: 1) }
        case .ghost:
            Capsule().fill(isPressed ? Color.tempo.surface2 : Color.clear)
        case .destructive:
            Capsule()
                .fill(isPressed ? Color.tempo.dangerSoft : Color.tempo.background)
                .overlay { Capsule().strokeBorder(Color.tempo.danger, lineWidth: 1) }
        }
    }
}

// MARK: - Convenience button

/// A ready-made button with title, optional SF Symbol, loading state and a light haptic.
///
///     TempoButton("Go online", variant: .primary) { store.goOnline() }
struct TempoButton: View {
    private let title: String
    private let systemImage: String?
    private let variant: TempoButtonVariant
    private let size: TempoButtonSize
    private let fullWidth: Bool
    private let isLoading: Bool
    private let action: () -> Void

    @State private var tapCount: Int = 0

    init(
        _ title: String,
        systemImage: String? = nil,
        variant: TempoButtonVariant = TempoButtonVariant.primary,
        size: TempoButtonSize = TempoButtonSize.large,
        fullWidth: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                labelRow.opacity(isLoading ? 0.0 : 1.0)
                if isLoading {
                    LoadingDots(color: dotsColor, dotSize: 6)
                }
            }
        }
        .buttonStyle(TempoButtonStyle(variant, size: size, fullWidth: fullWidth))
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isLoading ? "Loading" : ""))
    }

    private var labelRow: some View {
        HStack(spacing: TempoSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
    }

    private var dotsColor: Color {
        switch variant {
        case .primary, .premium: return Color.tempo.onAccent
        case .secondary, .ghost: return Color.tempo.textPrimary
        case .destructive: return Color.tempo.danger
        }
    }

    /// Premium keeps the black capsule and marks itself with a cream icon; other variants match the label.
    private var iconColor: Color {
        switch variant {
        case .primary: return Color.tempo.onAccent
        case .premium: return Color.tempo.premiumSoft
        case .secondary, .ghost: return Color.tempo.textPrimary
        case .destructive: return Color.tempo.danger
        }
    }

    private func handleTap() {
        tapCount += 1
        action()
    }
}

// MARK: - Text button

/// An inline, underlined text button that sits on the text margin (no padding of its own beyond
/// the 44 pt hit height). For quiet exits in left-aligned layouts: "Stop for tonight", "Keep dating".
///
///     TempoTextButton("Keep dating") { store.keepDating() }
struct TempoTextButton: View {
    private let title: String
    private let color: Color
    private let action: () -> Void

    init(_ title: String, color: Color = Color.tempo.textPrimary, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .tempoText(.bodyEmphasis)
                .underline()
                .foregroundStyle(color)
                .frame(minHeight: TempoSize.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.98))
    }
}

// MARK: - Press style

/// A bare press-scale style for custom-shaped controls.
struct TempoPressStyle: ButtonStyle {
    let scale: CGFloat

    init(scale: CGFloat = 0.94) {
        self.scale = scale
    }

    func makeBody(configuration: Configuration) -> some View {
        TempoPressStyleBody(label: configuration.label, isPressed: configuration.isPressed, scale: scale)
    }
}

private struct TempoPressStyleBody: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let scale: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .scaleEffect(isPressed && !reduceMotion ? scale : 1.0)
            .opacity(isEnabled ? (isPressed ? 0.82 : 1.0) : 0.35)
            .animation(Animation.tempo.press, value: isPressed)
            .tempoPressClick(isPressed: isPressed)
    }
}

// MARK: - Press click

extension View {
    /// A firm click the moment a control is pressed down and a softer one on release, like a key
    /// with travel. Built into `TempoButtonStyle` and `TempoPressStyle`; do not add another on tap.
    func tempoPressClick(isPressed: Bool) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed {
                TempoHaptics.shared.pressDown()
            } else {
                TempoHaptics.shared.pressUp()
            }
        }
    }
}

// MARK: - Preview

#Preview("Buttons") {
    ScrollView {
        VStack(spacing: TempoSpacing.md) {
            TempoButton("Go online", action: {})
            TempoButton("Keep dating", variant: TempoButtonVariant.secondary, action: {})
            TempoButton("Stop for tonight", variant: TempoButtonVariant.ghost, action: {})
            TempoButton("Delete account", variant: TempoButtonVariant.destructive, action: {})
            TempoButton("Continue", variant: TempoButtonVariant.premium, action: {})
            TempoTextButton("Keep dating", action: {})
            TempoButton("Saving", isLoading: true, action: {})
            TempoButton("Pass", variant: TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false, action: {})
            Button("Disabled") {}
                .buttonStyle(.tempoPrimary)
                .disabled(true)
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.xl)
    }
    .inkBackground()
}
