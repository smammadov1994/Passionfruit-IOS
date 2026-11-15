import SwiftUI

/// The community rules, reachable from You at any time.
struct CommunityRulesScreen: View {
    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                ScreenHeader(
                    eyebrow: String(localized: "Community rules"),
                    title: String(localized: "Keep it"),
                    emphasis: String(localized: "respectful."),
                    subtitle: String(localized: "The same rules for everyone, on every date.")
                )
                TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                    CommunityRulesContent()
                }
                if let url = LegalLinks.communityGuidelinesURL {
                    Link(destination: url) {
                        Text("Read the full guidelines")
                            .tempoText(.secondaryEmphasis)
                            .underline()
                            .foregroundStyle(Color.tempo.textPrimary)
                            .frame(minHeight: TempoSize.hitTarget)
                    }
                }
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
        }
        .inkBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Account deletion, in two steps: this screen says what goes, then a final confirmation.
/// On success Core signs the user out and the app returns to the welcome screen.
struct DeleteAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming: Bool = false
    @State private var isDeleting: Bool = false
    @State private var failure: String?

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                ScreenHeader(
                    eyebrow: String(localized: "Delete account"),
                    title: String(localized: "Leaving for"),
                    emphasis: String(localized: "good?"),
                    subtitle: String(localized: "Deleting your account is permanent. Here's what goes with it.")
                )
                TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                    VStack(alignment: .leading, spacing: 0) {
                        consequence("person.crop.circle.badge.xmark", String(localized: "Your profile and photos are deleted."))
                        TempoDivider()
                        consequence("bubble.left.and.bubble.right", String(localized: "Your matches and conversations disappear, for them too."))
                        TempoDivider()
                        consequence("creditcard", String(localized: "A \(Brand.premiumName) subscription is not cancelled by this. Cancel it in your Apple Account settings first."))
                    }
                }
                if let failure {
                    ErrorBanner(message: failure, onDismiss: { self.failure = nil })
                }
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton(
                    String(localized: "Delete my account"),
                    variant: TempoButtonVariant.destructive,
                    isLoading: isDeleting,
                    action: { isConfirming = true }
                )
                TempoButton(
                    String(localized: "Keep my account"),
                    variant: TempoButtonVariant.ghost,
                    size: TempoButtonSize.regular,
                    action: { dismiss() }
                )
                .disabled(isDeleting)
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.xs)
        }
        .inkBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDeleting)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog(
            Text("Delete your account for good?"),
            isPresented: $isConfirming,
            titleVisibility: .visible,
            actions: { confirmActions },
            message: { Text("This can't be undone.") }
        )
    }

    @ViewBuilder
    private var confirmActions: some View {
        Button(String(localized: "Delete forever"), role: .destructive) {
            deleteAccount()
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }

    private func consequence(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            IconTile(systemName: systemImage, tint: TempoPastel.sky)
            Text(text)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        failure = nil
        isDeleting = true
        let session: SessionStore = self.session
        // Deletion must not be abandoned half-way because the screen went away, so it is not
        // tied to the screen's lifetime.
        Task { @MainActor in
            let deleted: Bool = await session.deleteAccount()
            isDeleting = false
            if deleted {
                return
            }
            failure = session.lastError?.userMessage ?? String(localized: "We couldn't delete your account. Try again.")
            session.lastError = nil
        }
    }
}

#Preview("Community rules screen") {
    NavigationStack {
        CommunityRulesScreen()
    }
    .tempoEnvironment(AppEnvironment.demo())
}

#Preview("Delete account") {
    NavigationStack {
        DeleteAccountView()
    }
    .tempoEnvironment(AppEnvironment.demo())
}
