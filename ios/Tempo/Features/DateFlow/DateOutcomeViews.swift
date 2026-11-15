import SwiftUI

// MARK: - Matched

/// The Match. "Say hello" closes the flow and routes to the chat; "Keep dating" re-queues.
struct DateMatchedView: View {
    let match: Match

    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(MatchesStore.self) private var matchesStore

    var body: some View {
        MatchCelebration(
            myPhoto: environment.imageCache.resolve(session.user?.primaryPhotoUrl),
            myName: myName,
            partnerPhoto: environment.imageCache.resolve(match.partner.photoUrl),
            partnerName: match.partner.firstName,
            onSayHello: sayHello,
            onKeepDating: { dateStore.continueToNext() }
        )
    }

    private var myName: String {
        let name: String = session.user?.firstName ?? ""
        return name.isEmpty ? "You" : name
    }

    /// Ends the session, then hands the chat to RootView through `pendingRoute`. A match the
    /// server has not delivered in full yet has no chat to open, so that one goes to the list.
    private func sayHello() {
        let matchId: String = match.id
        let isKnown: Bool = matchesStore.match(id: matchId) != nil
        dateStore.goOffline()
        environment.pendingRoute = isKnown ? AppRoute.chat(matchId: matchId) : AppRoute.matches
    }
}

// MARK: - Interstitial

/// Between dates: no match, they left, you left, the call dropped, or a safety stop. While the
/// store counts down to the next person this is the quiet `NextCountdown`; when the store is
/// waiting for the user it is a settled screen with the choices spelled out.
struct DateInterstitialView: View {
    let kind: DateInterstitial
    let onReport: () -> Void
    let onShowRules: () -> Void

    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let copy: DateInterstitialCopy = DateInterstitialCopy(
            kind: kind,
            hasCountdown: dateStore.nextCountdownEndsAt != nil,
            moderationMessage: dateStore.moderationWarning?.message
        )
        return ZStack {
            if let endsAt = dateStore.nextCountdownEndsAt {
                DateCountdownInterstitial(copy: copy, endsAt: endsAt)
                    .transition(AnyTransition.opacity)
            } else {
                DateSettledInterstitial(
                    copy: copy,
                    reportName: reportName,
                    onReport: onReport,
                    onShowRules: onShowRules
                )
                .transition(AnyTransition.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Reporting stays possible after a safety stop: the other person sees this screen too.
    private var reportName: String? {
        guard isSafetyStop(kind) else { return nil }
        return dateStore.partner?.firstName
    }

    private func isSafetyStop(_ kind: DateInterstitial) -> Bool {
        switch kind {
        case .ended(let reason):
            return reason == DateEndReason.moderation
        case .noMatch, .partnerLeft:
            return false
        }
    }
}

// MARK: - Copy

/// The words for each way a date can end. Kind, short, never blaming.
struct DateInterstitialCopy: Equatable {
    var eyebrow: String
    var title: String
    var message: String
    var primaryTitle: String
    var isSafetyStop: Bool

    init(kind: DateInterstitial, hasCountdown: Bool, moderationMessage: String?) {
        var eyebrow: String = ""
        var title: String = ""
        var message: String = ""
        var primaryTitle: String = "Find someone new"
        var isSafetyStop: Bool = false

        switch kind {
        case .noMatch:
            eyebrow = "No hard feelings"
            title = "Not this time."
            message = "The night's still young."
        case .partnerLeft(let partner):
            eyebrow = "It happens"
            title = "They left."
            message = "\(partner.firstName) ended the date early. It's rarely about you."
        case .ended(let reason):
            switch reason {
            case .timer:
                eyebrow = "Time's up"
                title = "That's time."
                message = "On to someone new."
            case .partnerLeft:
                eyebrow = "It happens"
                title = "They left."
                message = "They ended the date early. It's rarely about you."
            case .youLeft:
                eyebrow = "That counts as a no"
                title = "You left."
                message = "On to someone new."
            case .checkpoint:
                eyebrow = "After the first question"
                title = "Not this one."
                message = "One of you chose to stop there. Nobody is told who."
            case .disconnect:
                if hasCountdown {
                    eyebrow = "Their connection dropped"
                    title = "Lost them."
                    message = "Nothing you did. On to someone new."
                } else {
                    eyebrow = "Connection lost"
                    title = "You dropped off."
                    message = "We lost the connection on your side, so that date had to end. Check your signal, then jump back in."
                    primaryTitle = "Try again"
                }
            case .moderation:
                eyebrow = "Ended for safety"
                title = "This date was ended."
                let fallback: String = "Something in that call broke the community rules, so it was ended for both of you."
                let specific: String = moderationMessage ?? ""
                message = specific.isEmpty ? fallback : specific
                isSafetyStop = true
            }
        }

        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.isSafetyStop = isSafetyStop
    }
}

// MARK: - Counting down

private struct DateCountdownInterstitial: View {
    let copy: DateInterstitialCopy
    let endsAt: Date

    @Environment(DateStore.self) private var dateStore

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Eyebrow(copy.eyebrow)
                .tempoScreenPadding()
            NextCountdown(
                endsAt: endsAt,
                total: dateStore.timing.interstitial,
                title: copy.title,
                caption: dateStore.willStopAfterThis ? "Wrapping up in" : "Next person in",
                onStop: { dateStore.stopAfterThis() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Settled

private struct DateSettledInterstitial: View {
    let copy: DateInterstitialCopy
    let reportName: String?
    let onReport: () -> Void
    let onShowRules: () -> Void

    @Environment(DateStore.self) private var dateStore

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            headline
            if copy.isSafetyStop {
                DateSafetyNote(onShowRules: onShowRules)
            }
            Spacer(minLength: TempoSpacing.lg)
            actions
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if copy.isSafetyStop {
                IconTile(systemName: "exclamationmark.triangle", tone: TempoTone.amber)
                    .padding(.bottom, TempoSpacing.xxs)
            }
            Eyebrow(copy.eyebrow)
            Text(copy.title)
                .tempoText(.displayM)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            Text(copy.message)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: TempoSpacing.xs) {
            TempoButton(copy.primaryTitle) {
                dateStore.continueToNext()
            }
            TempoButton("Stop for tonight", variant: TempoButtonVariant.ghost) {
                dateStore.stopAfterThis()
            }
            if let reportName {
                TempoButton(
                    "Report \(reportName)",
                    systemImage: "flag",
                    variant: TempoButtonVariant.ghost,
                    size: TempoButtonSize.compact,
                    fullWidth: false,
                    action: onReport
                )
            }
        }
    }
}

/// The firm part of a safety stop: what it means, without assuming whose side it was on.
private struct DateSafetyNote: View {
    let onShowRules: () -> Void

    var body: some View {
        TempoCard(kind: TempoCardKind.raised, padding: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("If it was on your side, it goes on your record, and three strikes pause an account. If it wasn't, you did nothing wrong.")
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TempoButton(
                    "Read the community rules",
                    systemImage: "book",
                    variant: TempoButtonVariant.secondary,
                    size: TempoButtonSize.regular,
                    action: onShowRules
                )
            }
        }
    }
}
