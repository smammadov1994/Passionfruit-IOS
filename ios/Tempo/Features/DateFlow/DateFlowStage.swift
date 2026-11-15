import Foundation

/// What a finished date turned into, for the quiet screen between dates.
enum DateInterstitial: Equatable {
    case noMatch(partner: Partner)
    case partnerLeft(partner: Partner)
    case ended(reason: DateEndReason)
}

/// `DatePhase` regrouped by what is on screen. Phases that share a screen share a case, so the
/// view for that screen keeps its identity while the phase moves on underneath it:
/// searching → connecting (the ring resolves into the partner), deciding → awaitingResult (the pad seals).
enum DateFlowStage: Equatable {
    case closed
    case lobby(partner: Partner?)
    case live
    /// `deadline` is nil once the answer is sealed.
    case verdict(partner: Partner, deadline: Date?)
    case matched(match: Match)
    case interstitial(DateInterstitial)
    case limit(resetsAt: Date)
    case suspended(reason: String)

    init(phase: DatePhase) {
        switch phase {
        case .idle:
            self = .closed
        case .searching:
            self = .lobby(partner: nil)
        case .limitReached(let resetsAt):
            self = .limit(resetsAt: resetsAt)
        case .connecting(let partner):
            self = .lobby(partner: partner)
        case .live:
            self = .live
        case .deciding(let partner, let deadline):
            self = .verdict(partner: partner, deadline: deadline)
        case .awaitingResult(let partner):
            self = .verdict(partner: partner, deadline: nil)
        case .matched(let match):
            self = .matched(match: match)
        case .noMatch(let partner):
            self = .interstitial(DateInterstitial.noMatch(partner: partner))
        case .partnerLeft(let partner):
            self = .interstitial(DateInterstitial.partnerLeft(partner: partner))
        case .ended(let reason):
            self = .interstitial(DateInterstitial.ended(reason: reason))
        case .suspended(let reason):
            self = .suspended(reason: reason)
        }
    }

    /// Which screen is up. Animations key on this, so a change of payload alone does not
    /// replace the screen.
    var screen: DateFlowScreen {
        switch self {
        case .closed:
            return DateFlowScreen.closed
        case .lobby:
            return DateFlowScreen.lobby
        case .live:
            return DateFlowScreen.live
        case .verdict:
            return DateFlowScreen.verdict
        case .matched:
            return DateFlowScreen.matched
        case .interstitial(let kind):
            switch kind {
            case .noMatch:
                return DateFlowScreen.noMatch
            case .partnerLeft:
                return DateFlowScreen.partnerLeft
            case .ended:
                return DateFlowScreen.ended
            }
        case .limit:
            return DateFlowScreen.limit
        case .suspended:
            return DateFlowScreen.suspended
        }
    }

    /// The remote video surface stays mounted from pairing until the result, so it never flickers.
    var mountsVideo: Bool {
        switch self {
        case .lobby(let partner):
            return partner != nil
        case .live, .verdict:
            return true
        case .closed, .matched, .interstitial, .limit, .suspended:
            return false
        }
    }

    /// The video is actually shown (not just mounted).
    var showsVideo: Bool {
        switch self {
        case .live, .verdict:
            return true
        case .closed, .lobby, .matched, .interstitial, .limit, .suspended:
            return false
        }
    }

    /// The Verdict: video blurred and dimmed.
    var dimsVideo: Bool {
        switch self {
        case .verdict:
            return true
        case .closed, .lobby, .live, .matched, .interstitial, .limit, .suspended:
            return false
        }
    }

    /// The self view rides along from pairing through the live date.
    var showsSelfView: Bool {
        switch self {
        case .lobby(let partner):
            return partner != nil
        case .live:
            return true
        case .closed, .verdict, .matched, .interstitial, .limit, .suspended:
            return false
        }
    }

    /// The screen must not dim or lock while searching or in a date.
    var keepsScreenAwake: Bool {
        switch self {
        case .lobby, .live, .verdict:
            return true
        case .closed, .matched, .interstitial, .limit, .suspended:
            return false
        }
    }
}

/// The screens of the date flow, without payloads.
enum DateFlowScreen: Hashable {
    case closed
    case lobby
    case live
    case verdict
    case matched
    case noMatch
    case partnerLeft
    case ended
    case limit
    case suspended
}

/// One value per `DatePhase`, without payloads: what VoiceOver announcements key on.
enum DateFlowMoment: Hashable {
    case idle
    case searching
    case limitReached
    case connecting
    case live
    case deciding
    case awaitingResult
    case matched
    case noMatch
    case partnerLeft
    case ended(reason: DateEndReason)
    case suspended

    init(phase: DatePhase) {
        switch phase {
        case .idle:
            self = .idle
        case .searching:
            self = .searching
        case .limitReached:
            self = .limitReached
        case .connecting:
            self = .connecting
        case .live:
            self = .live
        case .deciding:
            self = .deciding
        case .awaitingResult:
            self = .awaitingResult
        case .matched:
            self = .matched
        case .noMatch:
            self = .noMatch
        case .partnerLeft:
            self = .partnerLeft
        case .ended(let reason):
            self = .ended(reason: reason)
        case .suspended:
            self = .suspended
        }
    }
}

/// Words for the date flow that more than one view needs.
enum DateFlowCopy {
    /// What VoiceOver hears when the flow moves to `moment`.
    static func announcement(for moment: DateFlowMoment, partnerName: String?, decisionSeconds: Int) -> String {
        let name: String = partnerName ?? "your date"
        switch moment {
        case .idle:
            return ""
        case .searching:
            return "Finding someone good."
        case .limitReached:
            return "That's your free dates for today."
        case .connecting:
            return "Found \(name). Connecting."
        case .live:
            return "You're live with \(name). The clock is running."
        case .deciding:
            return "Time's up. Would you like to see \(name) again? You have \(decisionSeconds) seconds."
        case .awaitingResult:
            return "Sealed. Waiting for \(name)."
        case .matched:
            return "It's mutual. You and \(name) both said yes."
        case .noMatch:
            return "Not this time."
        case .partnerLeft:
            return "\(name) left. Moving on."
        case .ended(let reason):
            switch reason {
            case .timer:
                return "That's time."
            case .partnerLeft:
                return "They left. Moving on."
            case .youLeft:
                return "You left. That counts as a no."
            case .moderation:
                return "This date was ended for safety."
            case .disconnect:
                return "The connection dropped and the date ended."
            case .checkpoint:
                return "The date ended after the first question."
            }
        case .suspended:
            return "Your account is paused."
        }
    }

    /// "five" for 5, falling back to digits.
    static func spelledOut(_ number: Int) -> String {
        let formatter: NumberFormatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.spellOut
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// "3 h 12 min", "12 min", "under a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes: Int = Int((max(0, seconds) / 60.0).rounded(.up))
        if totalMinutes <= 0 {
            return "under a minute"
        }
        let hours: Int = totalMinutes / 60
        let minutes: Int = totalMinutes % 60
        if hours == 0 {
            return "\(minutes) min"
        }
        if minutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(minutes) min"
    }
}
