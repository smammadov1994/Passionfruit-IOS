import SwiftUI

// MARK: - TempoTextField

/// A labelled text field on the surface color with a black focus border, optional icon, error and
/// character count.
/// Apply keyboard modifiers from outside (`.keyboardType`, `.textContentType`, `.submitLabel`, `.onSubmit`).
///
///     TempoTextField("First name", text: $firstName, prompt: "What should we call you?")
struct TempoTextField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: String
    private let systemImage: String?
    private let axis: Axis
    private let errorMessage: String?
    private let characterLimit: Int?

    @FocusState private var isFocused: Bool

    init(
        _ title: String,
        text: Binding<String>,
        prompt: String = "",
        systemImage: String? = nil,
        axis: Axis = Axis.horizontal,
        errorMessage: String? = nil,
        characterLimit: Int? = nil
    ) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.systemImage = systemImage
        self.axis = axis
        self.errorMessage = errorMessage
        self.characterLimit = characterLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            if !title.isEmpty {
                Eyebrow(title)
                    .accessibilityHidden(true)
            }
            fieldRow
            footer
        }
        .animation(Animation.tempo.snappy, value: isFocused)
        .animation(Animation.tempo.snappy, value: errorMessage)
        .onChange(of: text) { _, newValue in
            enforceLimit(newValue)
        }
    }

    private var fieldRow: some View {
        HStack(alignment: axis == Axis.vertical ? VerticalAlignment.top : VerticalAlignment.center, spacing: TempoSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Font.system(size: 18, weight: Font.Weight.regular))
                    .foregroundStyle(isFocused ? Color.tempo.textPrimary : Color.tempo.textSecondary)
                    .accessibilityHidden(true)
            }
            TextField(title, text: $text, prompt: promptText, axis: axis)
                .focused($isFocused)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textPrimary)
                .tint(Color.tempo.accent)
                .lineLimit(axis == Axis.vertical ? 1...6 : 1...1)
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .background { shape.fill(Color.tempo.surface) }
        .overlay { shape.strokeBorder(borderColor, lineWidth: 1) }
        .contentShape(shape)
        .onTapGesture {
            isFocused = true
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            Text(errorMessage)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let characterLimit {
            Text("\(text.count)/\(characterLimit)")
                .tempoText(.numeralS)
                .foregroundStyle(Color.tempo.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("\(text.count) of \(characterLimit) characters"))
        }
    }

    private var promptText: Text {
        Text(prompt).foregroundColor(Color.tempo.textTertiary)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return Color.tempo.danger
        }
        if isFocused {
            return Color.tempo.textPrimary
        }
        return Color.tempo.hairline
    }

    private func enforceLimit(_ value: String) {
        guard let characterLimit, value.count > characterLimit else { return }
        text = String(value.prefix(characterLimit))
    }
}

// MARK: - TempoSwitch

/// The switch drawn by `TempoToggleRow`: surface-2 track that fills near-black when on, white thumb. Purely visual; not interactive on its own.
struct TempoSwitch: View {
    private let isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }

    var body: some View {
        ZStack(alignment: isOn ? Alignment.trailing : Alignment.leading) {
            Capsule()
                .fill(isOn ? Color.tempo.textPrimary : Color.tempo.surface2)
            Capsule()
                .strokeBorder(isOn ? Color.tempo.textPrimary : Color.tempo.hairline, lineWidth: 1)
            Circle()
                .fill(Color.tempo.background)
                .frame(width: 25, height: 25)
                .overlay { Circle().strokeBorder(Color.tempo.hairline, lineWidth: 1) }
                .padding(3)
        }
        .frame(width: 51, height: 31)
        .animation(Animation.tempo.snappy, value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - TempoToggleRow

/// A full-width row that toggles a setting. The whole row is the hit target.
///
///     TempoToggleRow(title: "Tell me when singles are online", subtitle: "At most once every 4 hours.", isOn: $notify)
struct TempoToggleRow: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let tile: TempoPastel
    @Binding private var isOn: Bool

    init(title: String, subtitle: String? = nil, systemImage: String? = nil, tile: TempoPastel = TempoPastel.sky, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tile = tile
        self._isOn = isOn
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: TempoSpacing.sm) {
                if let systemImage {
                    IconTile(systemName: systemImage, tint: tile)
                }
                labels
                Spacer(minLength: TempoSpacing.sm)
                TempoSwitch(isOn: isOn)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.99))
        .sensoryFeedback(SensoryFeedback.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityHint(Text(subtitle ?? ""))
        .accessibilityAddTraits(AccessibilityTraits.isToggle)
        .accessibilityAction {
            toggle()
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle() {
        isOn.toggle()
    }
}

// MARK: - SegmentedPicker

/// One option of a `SegmentedPicker`.
struct SegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    init(value: Value, label: String) {
        self.value = value
        self.label = label
    }

    var id: Value { value }
}

/// A segmented control on the surface color with a sliding black pill. Two to four options.
///
///     SegmentedPicker(selection: $gender, options: [SegmentedOption(value: "woman", label: "Woman"),
///                                                   SegmentedOption(value: "man", label: "Man")])
struct SegmentedPicker<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [SegmentedOption<Value>]

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Value>, options: [SegmentedOption<Value>]) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(4)
        .background { Capsule().fill(Color.tempo.surface) }
        .overlay { Capsule().strokeBorder(Color.tempo.hairline, lineWidth: 1) }
        .sensoryFeedback(SensoryFeedback.selection, trigger: selection)
    }

    private func segment(_ option: SegmentedOption<Value>) -> some View {
        let isSelected: Bool = option.value == selection
        return Button {
            withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
                selection = option.value
            }
        } label: {
            Text(option.label)
                .tempoText(.secondaryEmphasis)
                .foregroundStyle(isSelected ? Color.tempo.onAccent : Color.tempo.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, TempoSpacing.xs)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.tempo.textPrimary)
                            .matchedGeometryEffect(id: "pill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

extension SegmentedPicker where Value == String {
    /// Shorthand for string options where label and value are the same.
    ///
    ///     SegmentedPicker(selection: $tab, labels: ["Everyone", "Women", "Men"])
    init(selection: Binding<String>, labels: [String]) {
        var built: [SegmentedOption<String>] = []
        for label in labels {
            built.append(SegmentedOption<String>(value: label, label: label))
        }
        self.init(selection: selection, options: built)
    }
}

// MARK: - Preview

private struct InputsPreview: View {
    @State private var name: String = ""
    @State private var bio: String = "Ask me about the worst film I love."
    @State private var notify: Bool = true
    @State private var gender: String = "Woman"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                TempoTextField("First name", text: $name, prompt: "What should we call you?", systemImage: "person")
                TempoTextField("About you", text: $bio, prompt: "A line or two", axis: Axis.vertical, characterLimit: 140)
                TempoTextField("City", text: $name, prompt: "Where are you?", errorMessage: "We couldn't find that city.")
                TempoToggleRow(title: "Tell me when singles are online", subtitle: "At most once every 4 hours.", systemImage: "bell", isOn: $notify)
                SegmentedPicker(selection: $gender, labels: ["Woman", "Man", "Nonbinary"])
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.xl)
        }
        .inkBackground()
    }
}

#Preview("Inputs") {
    InputsPreview()
}
