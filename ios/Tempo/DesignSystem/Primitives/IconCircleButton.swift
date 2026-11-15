import SwiftUI

/// Look of an `IconCircleButton`.
enum IconCircleButtonKind: Hashable {
    /// White disc with a hairline border and the one soft shadow, near-black outlined glyph.
    /// For controls that sit over video or imagery.
    case floating
    /// White disc with a hairline border, no shadow. Round buttons on the page.
    case outlined
    /// Solid danger fill, white glyph. Leave.
    case danger
    /// No background, near-black glyph. Navigation-bar style buttons.
    case plain
}

/// A round control. Pass the OUTLINED symbol. When `isOn` is false it fills near-black with a
/// white glyph and shows `offSystemImage` if given, the way a muted microphone reads at a glance.
///
///     IconCircleButton(systemImage: "mic", accessibilityLabel: "Microphone",
///                      isOn: !isMuted, offSystemImage: "mic.slash") { toggleMic() }
struct IconCircleButton: View {
    private let systemImage: String
    private let label: String
    private let isOn: Bool
    private let offSystemImage: String?
    private let kind: IconCircleButtonKind
    private let size: CGFloat
    private let action: () -> Void

    @State private var tapCount: Int = 0

    init(
        systemImage: String,
        accessibilityLabel: String,
        isOn: Bool = true,
        offSystemImage: String? = nil,
        kind: IconCircleButtonKind = IconCircleButtonKind.floating,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = accessibilityLabel
        self.isOn = isOn
        self.offSystemImage = offSystemImage
        self.kind = kind
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: handleTap) {
            glyph
                .frame(width: size, height: size)
                .background { surface }
                .frame(minWidth: TempoSize.hitTarget, minHeight: TempoSize.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.9))
        .animation(Animation.tempo.snappy, value: isOn)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    private var glyph: some View {
        Image(systemName: currentImage)
            .font(Font.system(size: size * 0.42, weight: Font.Weight.regular))
            .foregroundStyle(glyphColor)
            .accessibilityHidden(true)
    }

    private var currentImage: String {
        if !isOn, let offSystemImage {
            return offSystemImage
        }
        return systemImage
    }

    private var isToggle: Bool {
        offSystemImage != nil
    }

    private var spokenValue: String {
        guard isToggle else { return "" }
        return isOn ? "On" : "Off"
    }

    private var glyphColor: Color {
        if !isOn {
            return Color.tempo.onAccent
        }
        switch kind {
        case .floating, .outlined, .plain: return Color.tempo.textPrimary
        case .danger: return Color.tempo.onAccent
        }
    }

    @ViewBuilder
    private var surface: some View {
        if !isOn {
            Circle().fill(Color.tempo.textPrimary)
        } else {
            switch kind {
            case .floating:
                Color.clear.tempoSurface(in: Circle(), isFloating: true)
            case .outlined:
                Color.clear.tempoSurface(in: Circle())
            case .danger:
                Circle().fill(Color.tempo.danger)
            case .plain:
                Color.clear
            }
        }
    }

    private func handleTap() {
        tapCount += 1
        action()
    }
}

#Preview("IconCircleButton") {
    HStack(spacing: TempoSpacing.md) {
        IconCircleButton(systemImage: "mic", accessibilityLabel: "Microphone", isOn: true, offSystemImage: "mic.slash", action: {})
        IconCircleButton(systemImage: "mic", accessibilityLabel: "Microphone", isOn: false, offSystemImage: "mic.slash", action: {})
        IconCircleButton(systemImage: "xmark", accessibilityLabel: "Close", kind: IconCircleButtonKind.outlined, action: {})
        IconCircleButton(systemImage: "phone.down", accessibilityLabel: "Leave", kind: IconCircleButtonKind.danger, action: {})
        IconCircleButton(systemImage: "gearshape", accessibilityLabel: "Settings", kind: IconCircleButtonKind.plain, action: {})
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .inkBackground()
}
