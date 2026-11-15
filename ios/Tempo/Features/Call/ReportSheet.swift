import SwiftUI

/// Report (and block) someone. Sheet content: present it with `.sheet`; it styles its own
/// presentation and dismisses itself.
///
///     .sheet(isPresented: $isReporting) {
///         ReportSheet(partnerName: partner.firstName,
///                     onSubmit: { reason, details in send(reason, details) },
///                     onBlock: { block() })
///     }
///
/// `onSubmit` fires once, when the user sends the report; the sheet then shows its
/// confirmation. `onBlock` fires when the user chooses to block; the sheet closes right after.
/// Pass `onLeave` during a live date: the confirmation then offers "Leave this date" and the
/// block button reads "Block … and leave". Leave it nil everywhere else.
struct ReportSheet: View {
    private let partnerName: String
    private let onSubmit: (ReportReason, String?) -> Void
    private let onBlock: () -> Void
    private let onLeave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedReason: ReportReason? = nil
    @State private var details: String = ""
    @State private var hasSubmitted: Bool = false

    init(
        partnerName: String,
        onSubmit: @escaping (ReportReason, String?) -> Void,
        onBlock: @escaping () -> Void,
        onLeave: (() -> Void)? = nil
    ) {
        self.partnerName = partnerName
        self.onSubmit = onSubmit
        self.onBlock = onBlock
        self.onLeave = onLeave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                SheetGrabber()
                content
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: hasSubmitted)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: selectedReason)
        .presentationDetents([PresentationDetent.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TempoRadius.sheet)
        .presentationBackground {
            InkBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        if hasSubmitted {
            ReportConfirmation(
                partnerName: partnerName,
                blockTitle: blockTitle,
                showsLeave: onLeave != nil,
                onLeave: leave,
                onBlock: block,
                onDone: close
            )
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        } else {
            form
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            header
            ReportReasonList(selection: $selectedReason)
            if selectedReason != nil {
                TempoTextField(
                    "Anything to add? (optional)",
                    text: $details,
                    prompt: "What happened, in your words.",
                    axis: Axis.vertical,
                    characterLimit: 500
                )
                .transition(AnyTransition.tempoRise(reduceMotion: reduceMotion))
            }
            actions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Report \(partnerName)")
                .tempoText(.title)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            Text("This stays private. A person reviews every report.")
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: TempoSpacing.xs) {
            TempoButton("Send report", action: submit)
                .disabled(selectedReason == nil)
            TempoButton(blockTitle, variant: TempoButtonVariant.ghost, size: TempoButtonSize.regular, action: block)
        }
    }

    private var blockTitle: String {
        if onLeave != nil {
            return "Block \(partnerName) and leave"
        }
        return "Block \(partnerName)"
    }

    // MARK: Behaviour

    private func submit() {
        guard let reason = selectedReason, !hasSubmitted else { return }
        let trimmed: String = details.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let note: String? = trimmed.isEmpty ? nil : trimmed
        onSubmit(reason, note)
        hasSubmitted = true
        CallAnnouncer.announce("Report sent. Thank you.")
    }

    private func block() {
        onBlock()
        dismiss()
    }

    private func leave() {
        if let onLeave {
            onLeave()
        }
        dismiss()
    }

    private func close() {
        dismiss()
    }
}

// MARK: - Reason list

private struct ReportReasonList: View {
    @Binding var selection: ReportReason?

    var body: some View {
        TempoCard(kind: TempoCardKind.outlined, padding: 0) {
            VStack(spacing: 0) {
                ForEach(ReportReason.allCases) { reason in
                    ReportReasonRow(
                        title: reason.displayName,
                        isSelected: selection == reason,
                        showsDivider: reason != ReportReason.other
                    ) {
                        selection = reason
                    }
                }
            }
        }
    }
}

private struct ReportReasonRow: View {
    let title: String
    let isSelected: Bool
    let showsDivider: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: TempoSpacing.sm) {
                    Text(title)
                        .tempoText(.body)
                        .foregroundStyle(Color.tempo.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "checkmark")
                        .imageScale(Image.Scale.medium)
                        .foregroundStyle(Color.tempo.accent)
                        .opacity(isSelected ? 1.0 : 0.0)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.sm)
                .frame(minHeight: TempoSize.buttonRegular)
                .contentShape(Rectangle())
            }
            .buttonStyle(TempoPressStyle(scale: 0.98))
            .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits.isButton)
            if showsDivider {
                TempoDivider()
                    .padding(.leading, TempoSpacing.md)
            }
        }
    }
}

// MARK: - Confirmation

private struct ReportConfirmation: View {
    let partnerName: String
    let blockTitle: String
    let showsLeave: Bool
    let onLeave: () -> Void
    let onBlock: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Image(systemName: "checkmark")
                .font(Font.system(size: 24, weight: Font.Weight.light))
                .foregroundStyle(Color.tempo.yes)
                .frame(width: 64, height: 64)
                .background { Circle().fill(Color.tempo.yesSoft) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Report sent.")
                    .tempoText(.title)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text("Thank you for telling us. A person on our team will look at it, and \(partnerName) won't be told it was you.")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(.top, TempoSpacing.md)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: TempoSpacing.xs) {
            if showsLeave {
                TempoButton("Leave this date", variant: TempoButtonVariant.destructive, action: onLeave)
                TempoButton("Stay on the date", variant: TempoButtonVariant.secondary, action: onDone)
            } else {
                TempoButton("Done", variant: TempoButtonVariant.secondary, action: onDone)
            }
            TempoButton(blockTitle, variant: TempoButtonVariant.ghost, size: TempoButtonSize.regular, action: onBlock)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Report") {
    ReportSheet(partnerName: "Maya", onSubmit: { _, _ in }, onBlock: {})
}

#Preview("Report during a date") {
    ReportSheet(partnerName: "Maya", onSubmit: { _, _ in }, onBlock: {}, onLeave: {})
}
#endif
