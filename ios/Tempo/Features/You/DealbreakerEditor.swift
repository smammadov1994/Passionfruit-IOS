import SwiftUI

/// One-line summaries of the dealbreaker filters for the You tab.
enum DealbreakerSummary {
    static func text(for kind: DealbreakerKind, in preferences: Preferences) -> String {
        switch kind {
        case .intention:
            return list((preferences.intentions ?? []).map { $0.displayName })
        case .children:
            return list((preferences.children ?? []).map { $0.displayName })
        case .religion:
            return list((preferences.religions ?? []).map { $0.displayName })
        case .education:
            guard let minimum = preferences.minEducation else { return anyLabel }
            return String(localized: "\(minimum.displayName) or more")
        case .smoking:
            return list((preferences.smokingOk ?? []).map { $0.displayName })
        case .drinking:
            return list((preferences.drinkingOk ?? []).map { $0.displayName })
        }
    }

    static var anyLabel: String {
        String(localized: "Any")
    }

    private static func list(_ names: [String]) -> String {
        if names.isEmpty {
            return anyLabel
        }
        if names.count == 1 {
            return names[0]
        }
        return String(localized: "\(names.count) selected")
    }
}

/// The editor for one Premium dealbreaker filter: multi-select chips (minimum education is a
/// single choice). Nothing selected means the filter is off.
struct DealbreakerEditor: View {
    private let kind: DealbreakerKind

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Preferences = Preferences()
    @State private var hasLoaded: Bool = false
    @State private var isSaving: Bool = false
    @State private var failure: String?
    @State private var tasks: TaskBag = TaskBag()

    init(kind: DealbreakerKind) {
        self.kind = kind
    }

    private var saved: Preferences {
        session.user?.preferences ?? Preferences()
    }

    private var hasChanges: Bool {
        hasLoaded && draft != saved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                ScreenHeader(
                    eyebrow: String(localized: "Dealbreaker"),
                    title: kind.title,
                    subtitle: explanation,
                    style: TempoTextStyle.title
                )
                if let failure {
                    ErrorBanner(message: failure, onRetry: { save() }, onDismiss: { self.failure = nil })
                }
                if session.isPremium {
                    chips
                    summary
                } else {
                    lockedNotice
                }
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .inkBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            load()
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private var explanation: String {
        switch kind {
        case .intention:
            return String(localized: "Choose what you're open to. You'll only meet people looking for the same.")
        case .children:
            return String(localized: "Choose every answer that works for you.")
        case .religion:
            return String(localized: "Choose the beliefs you'd like to meet. Leave it empty to meet anyone.")
        case .education:
            return String(localized: "Choose the least you're looking for. Leave it empty to meet anyone.")
        case .smoking:
            return String(localized: "Choose what you're comfortable with.")
        case .drinking:
            return String(localized: "Choose what you're comfortable with.")
        }
    }

    // MARK: Chips

    @ViewBuilder
    private var chips: some View {
        switch kind {
        case .intention:
            MultiChoiceChips(options: Intention.allCases, selection: intentions) { (option: Intention) -> String in
                option.displayName
            }
        case .children:
            MultiChoiceChips(options: ChildrenStatus.allCases, selection: children) { (option: ChildrenStatus) -> String in
                option.displayName
            }
        case .religion:
            MultiChoiceChips(options: Religion.allCases, selection: religions) { (option: Religion) -> String in
                option.displayName
            }
        case .education:
            SingleChoiceChips(options: Education.allCases, selection: $draft.minEducation) { (option: Education) -> String in
                String(localized: "\(option.displayName) or more")
            }
        case .smoking:
            MultiChoiceChips(options: Smoking.allCases, selection: smoking) { (option: Smoking) -> String in
                option.displayName
            }
        case .drinking:
            MultiChoiceChips(options: Drinking.allCases, selection: drinking) { (option: Drinking) -> String in
                option.displayName
            }
        }
    }

    // An empty selection is stored as nil: the filter is off.

    private var intentions: Binding<[Intention]> {
        Binding<[Intention]>(
            get: { draft.intentions ?? [] },
            set: { newValue in draft.intentions = newValue.isEmpty ? nil : newValue }
        )
    }

    private var children: Binding<[ChildrenStatus]> {
        Binding<[ChildrenStatus]>(
            get: { draft.children ?? [] },
            set: { newValue in draft.children = newValue.isEmpty ? nil : newValue }
        )
    }

    private var religions: Binding<[Religion]> {
        Binding<[Religion]>(
            get: { draft.religions ?? [] },
            set: { newValue in draft.religions = newValue.isEmpty ? nil : newValue }
        )
    }

    private var smoking: Binding<[Smoking]> {
        Binding<[Smoking]>(
            get: { draft.smokingOk ?? [] },
            set: { newValue in draft.smokingOk = newValue.isEmpty ? nil : newValue }
        )
    }

    private var drinking: Binding<[Drinking]> {
        Binding<[Drinking]>(
            get: { draft.drinkingOk ?? [] },
            set: { newValue in draft.drinkingOk = newValue.isEmpty ? nil : newValue }
        )
    }

    private var summary: some View {
        HStack(spacing: TempoSpacing.xs) {
            Text("Now:")
                .tempoText(.secondary)
                .foregroundStyle(Color.tempo.textSecondary)
            Text(DealbreakerSummary.text(for: kind, in: draft))
                .tempoText(.secondaryEmphasis)
                .foregroundStyle(Color.tempo.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var lockedNotice: some View {
        TempoCard(kind: TempoCardKind.gold, padding: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("This filter is part of \(Brand.premiumName).")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TempoButton(
                    String(localized: "See Premium"),
                    variant: TempoButtonVariant.premium,
                    size: TempoButtonSize.regular,
                    action: { router.openPaywall() }
                )
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if session.isPremium {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton(String(localized: "Save"), isLoading: isSaving, action: { save() })
                    .disabled(!hasChanges)
                TempoButton(
                    String(localized: "Clear this filter"),
                    variant: TempoButtonVariant.ghost,
                    size: TempoButtonSize.regular,
                    action: { clear() }
                )
                .disabled(isSaving)
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.xs)
        }
    }

    // MARK: Actions

    private func load() {
        guard !hasLoaded else { return }
        draft = saved
        hasLoaded = true
    }

    private func clear() {
        switch kind {
        case .intention:
            draft.intentions = nil
        case .children:
            draft.children = nil
        case .religion:
            draft.religions = nil
        case .education:
            draft.minEducation = nil
        case .smoking:
            draft.smokingOk = nil
        case .drinking:
            draft.drinkingOk = nil
        }
    }

    private func save() {
        guard hasChanges, !isSaving else { return }
        failure = nil
        // Only this filter changes; everything else is taken fresh from the saved preferences.
        var updated: Preferences = saved
        switch kind {
        case .intention:
            updated.intentions = draft.intentions
        case .children:
            updated.children = draft.children
        case .religion:
            updated.religions = draft.religions
        case .education:
            updated.minEducation = draft.minEducation
        case .smoking:
            updated.smokingOk = draft.smokingOk
        case .drinking:
            updated.drinkingOk = draft.drinkingOk
        }
        tasks.run("save") {
            isSaving = true
            let didSave: Bool = await session.updatePreferences(updated)
            isSaving = false
            if Task.isCancelled {
                return
            }
            if didSave {
                router.showMessage(String(localized: "Filter saved."), systemImage: "checkmark.circle")
                dismiss()
            } else {
                failure = session.lastError?.userMessage ?? String(localized: "That didn't save. Try again.")
                session.lastError = nil
            }
        }
    }
}

#Preview("Dealbreaker") {
    NavigationStack {
        DealbreakerEditor(kind: DealbreakerKind.intention)
    }
    .environment(AppRouter())
    .tempoEnvironment(AppEnvironment.demo())
}
