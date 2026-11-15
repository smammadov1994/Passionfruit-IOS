import SwiftUI

/// Shown instead of the app while the account is paused for review.
struct SuspendedView: View {
    @Environment(SessionStore.self) private var session
    @State private var isChecking: Bool = false
    @State private var note: String?
    @State private var isDeletePresented: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var reason: String {
        let text: String = session.suspension?.reason ?? ""
        if text.isEmpty {
            return String(localized: "Your account is paused while a person reviews a report or a safety check. We'll let you back in as soon as the review is done.")
        }
        return text
    }

    private var untilLine: String? {
        let until: Date? = session.suspension?.until ?? session.user?.suspendedUntil
        guard let until, until > Date(), until < Date.distantFuture else { return nil }
        return String(localized: "Paused until \(TempoFormat.longDate(until)).")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                ScreenHeader(
                    eyebrow: String(localized: "Account paused"),
                    title: String(localized: "We've pressed"),
                    emphasis: String(localized: "pause."),
                    subtitle: reason
                )
                if let untilLine {
                    Chip(untilLine, systemImage: "clock", tone: TempoTone.amber)
                }
                TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                    CommunityRulesContent()
                }
                if let note {
                    Text(note)
                        .tempoText(.secondary)
                        .foregroundStyle(Color.tempo.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton(
                    String(localized: "Check again"),
                    variant: TempoButtonVariant.secondary,
                    isLoading: isChecking,
                    action: { checkAgain() }
                )
                TempoButton(
                    String(localized: "Sign out"),
                    variant: TempoButtonVariant.ghost,
                    size: TempoButtonSize.regular,
                    action: { signOut() }
                )
                // A paused account must still be able to delete itself (App Review 5.1.1(v)).
                TempoTextButton(String(localized: "Delete account"), color: Color.tempo.textSecondary) {
                    isDeletePresented = true
                }
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.xs)
        }
        .inkBackground()
        .sheet(isPresented: $isDeletePresented) {
            NavigationStack {
                DeleteAccountView()
            }
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private func checkAgain() {
        tasks.run("check") {
            isChecking = true
            note = nil
            let reached: Bool = await session.refreshUser()
            isChecking = false
            if Task.isCancelled {
                return
            }
            if !reached {
                note = String(localized: "We couldn't check just now. Try again in a moment.")
            } else if session.isSuspended {
                note = String(localized: "Still under review. Thanks for your patience.")
            }
        }
    }

    private func signOut() {
        tasks.run("signOut") {
            await session.signOut()
        }
    }
}

#Preview("Suspended") {
    SuspendedView()
        .tempoEnvironment(AppEnvironment.demo())
}
