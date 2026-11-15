import SwiftUI

/// A titled block of form content: eyebrow label above, content below. Given a symbol it shows
/// the profile-basics header instead: a pastel icon tile beside the title.
struct FieldSection<Content: View>: View {
    private let title: String
    private let footnote: String?
    private let systemImage: String?
    private let tile: TempoPastel
    private let content: Content

    init(
        _ title: String,
        footnote: String? = nil,
        systemImage: String? = nil,
        tile: TempoPastel = TempoPastel.blush,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.systemImage = systemImage
        self.tile = tile
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            header
            content
            if let footnote {
                Text(footnote)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var header: some View {
        if let systemImage {
            HStack(spacing: TempoSpacing.sm) {
                IconTile(systemName: systemImage, tint: tile)
                Text(title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
            }
        } else {
            Eyebrow(title)
        }
    }
}

/// Wrapping chips where at most one option is selected.
struct SingleChoiceChips<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option?
    private let allowsClearing: Bool
    private let label: (Option) -> String
    private let layout: FlowLayout = FlowLayout()

    init(
        options: [Option],
        selection: Binding<Option?>,
        allowsClearing: Bool = true,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        self._selection = selection
        self.allowsClearing = allowsClearing
        self.label = label
    }

    var body: some View {
        layout {
            ForEach(options, id: \.self) { option in
                chip(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(for option: Option) -> some View {
        let isSelected: Bool = selection == option
        return SelectableChip(label(option), isSelected: isSelected) {
            toggle(option)
        }
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func toggle(_ option: Option) {
        if selection == option {
            if allowsClearing {
                selection = nil
            }
        } else {
            selection = option
        }
    }
}

/// Wrapping chips where any number of options can be selected. Keeps the order of `options`.
struct MultiChoiceChips<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: [Option]
    private let label: (Option) -> String
    private let layout: FlowLayout = FlowLayout()

    init(options: [Option], selection: Binding<[Option]>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    var body: some View {
        layout {
            ForEach(options, id: \.self) { option in
                chip(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(for option: Option) -> some View {
        let isSelected: Bool = selection.contains(option)
        return SelectableChip(label(option), isSelected: isSelected) {
            toggle(option)
        }
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func toggle(_ option: Option) {
        var chosen: [Option] = selection
        if chosen.contains(option) {
            chosen.removeAll(where: { $0 == option })
        } else {
            chosen.append(option)
        }
        selection = options.filter { chosen.contains($0) }
    }
}
