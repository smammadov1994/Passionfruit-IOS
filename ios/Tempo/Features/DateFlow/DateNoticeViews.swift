import SwiftUI

// MARK: - Daily limit

/// The free daily dates are used up: when they come back, and the way to keep going.
struct DateLimitView: View {
    let resetsAt: Date
    let onShowPaywall: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(ConfigStore.self) private var configStore

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15.0)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let remaining: TimeInterval = DateClock.remaining(until: resetsAt, now: now)
        let isBack: Bool = remaining <= 0
        return VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                PremiumBadge(text: "Daily limit")
                    .padding(.bottom, TempoSpacing.xxs)
                Text(isBack ? "You're back in." : headline)
                    .tempoText(.displayM)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(isBack ? "Your free dates have reset." : message(remaining: remaining))
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TempoSpacing.lg)
            actions(isBack: isBack)
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var headline: String {
        "That's \(DateFlowCopy.spelledOut(configStore.freeDailyDates)) for today."
    }

    private func message(remaining: TimeInterval) -> String {
        let time: String = resetsAt.formatted(date: .omitted, time: .shortened)
        let wait: String = DateFlowCopy.duration(remaining)
        return "Free dates come back at \(time), in \(wait). Premium keeps the night going."
    }

    @ViewBuilder
    private func actions(isBack: Bool) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            if isBack {
                TempoButton("Go online") {
                    dateStore.continueToNext()
                }
            } else {
                TempoButton("See Premium", variant: TempoButtonVariant.premium, action: onShowPaywall)
            }
            TempoButton("Done for tonight", variant: TempoButtonVariant.ghost) {
                dateStore.goOffline()
            }
        }
    }
}

// MARK: - Suspended

/// The account is paused pending review. Plain, calm, no way around it from here.
struct DateSuspendedView: View {
    let reason: String
    let onShowRules: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                IconTile(systemName: "exclamationmark.triangle", tone: TempoTone.amber)
                    .padding(.bottom, TempoSpacing.xxs)
                Eyebrow("Account paused")
                Text("You can't go online right now.")
                    .tempoText(.displayS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(reason)
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let untilLine {
                    Chip(untilLine, systemImage: "clock", tone: TempoTone.amber)
                        .padding(.top, TempoSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: TempoSpacing.lg)
            VStack(spacing: TempoSpacing.xs) {
                TempoButton("Read the community rules", variant: TempoButtonVariant.secondary, action: onShowRules)
                TempoButton("Close", variant: TempoButtonVariant.ghost) {
                    dateStore.goOffline()
                }
            }
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// "Paused until 14 November." when the server gave an end date.
    private var untilLine: String? {
        guard let until = session.suspension?.until ?? session.user?.suspendedUntil else { return nil }
        guard until > Date(), until < Date.distantFuture else { return nil }
        let day: String = until.formatted(date: .long, time: .omitted)
        return "Paused until \(day)."
    }
}

// MARK: - Community rules

/// The rules, as a sheet. Linked from a safety stop and from a paused account. The rules
/// themselves are the shared `CommunityRulesContent` (Features/Shared), so every screen that
/// shows them says the same thing.
struct CommunityRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                SheetGrabber()
                ScreenHeader(
                    eyebrow: "Safety",
                    title: "Community",
                    emphasis: "rules.",
                    subtitle: "Short, and they apply to everyone.",
                    style: TempoTextStyle.title
                )
                TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                    CommunityRulesContent()
                }
                TempoButton("Got it", variant: TempoButtonVariant.secondary) {
                    dismiss()
                }
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.lg)
        }
        .presentationDetents([PresentationDetent.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TempoRadius.sheet)
        .presentationBackground {
            InkBackground()
        }
    }
}

#if DEBUG
#Preview("Community rules sheet") {
    CommunityRulesSheet()
        .tempoEnvironment(AppEnvironment.demo())
        .preferredColorScheme(.light)
}
#endif
