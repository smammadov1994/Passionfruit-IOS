import Observation
import SwiftUI

/// The three sections of the shell. There is no tab bar: Tonight is home, Matches opens from it
/// and You opens from Matches.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case tonight
    case matches
    case you

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonight: return String(localized: "Tonight")
        case .matches: return String(localized: "Matches")
        case .you: return String(localized: "You")
        }
    }

    /// The outlined symbol, shown while the tab is not selected.
    var systemImage: String {
        switch self {
        case .tonight: return "moon"
        case .matches: return "heart"
        case .you: return "person"
        }
    }

    /// The filled variant, shown for the selected tab.
    var selectedSystemImage: String {
        switch self {
        case .tonight: return "moon.fill"
        case .matches: return "heart.fill"
        case .you: return "person.fill"
        }
    }
}

/// The Premium dealbreaker filters, in the order they are listed.
enum DealbreakerKind: String, Hashable, CaseIterable, Identifiable {
    case intention
    case children
    case religion
    case education
    case smoking
    case drinking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intention: return String(localized: "Intentions")
        case .children: return String(localized: "Children")
        case .religion: return String(localized: "Religion")
        case .education: return String(localized: "Education")
        case .smoking: return String(localized: "Smoking")
        case .drinking: return String(localized: "Drinking")
        }
    }

    var systemImage: String {
        switch self {
        case .intention: return "heart"
        case .children: return "figure.and.child.holdinghands"
        case .religion: return "book"
        case .education: return "graduationcap"
        case .smoking: return "smoke"
        case .drinking: return "wineglass"
        }
    }
}

extension DealbreakerKind {
    /// The pastel behind this subject's icon, the same wherever the subject appears
    /// (You, the locked rows, the basics in Edit profile and onboarding).
    var tile: TempoPastel {
        switch self {
        case .intention: return TempoPastel.blush
        case .children: return TempoPastel.butter
        case .religion: return TempoPastel.lilac
        case .education: return TempoPastel.sky
        case .smoking: return TempoPastel.sage
        case .drinking: return TempoPastel.blush
        }
    }
}

/// Screens pushed inside the You tab.
enum YouDestination: Hashable {
    case editProfile
    case dealbreaker(DealbreakerKind)
    case communityRules
    case deleteAccount
}

/// Navigation state of the tab shell. Created by `TabShell` and injected into its subtree.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = AppTab.tonight
    /// Match ids of the chats pushed on the Matches tab.
    var matchesPath: [String] = []
    var youPath: [YouDestination] = []
    var isPaywallPresented: Bool = false
    /// Text an agent suggested, waiting to be placed in that match's composer. Keyed by match id.
    var pendingDrafts: [String: String] = [:]
    /// A transient message for the shell's toast.
    var toast: TempoToastItem?

    init() {}

    func select(_ tab: AppTab) {
        if selectedTab == tab {
            popToRoot(tab)
        } else {
            selectedTab = tab
        }
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .tonight:
            break
        case .matches:
            matchesPath = []
        case .you:
            youPath = []
        }
    }

    func openChat(matchId: String) {
        selectedTab = AppTab.matches
        if matchesPath != [matchId] {
            matchesPath = [matchId]
        }
    }

    /// Opens a chat with `text` already in the composer (not sent).
    func openChat(matchId: String, draft text: String) {
        pendingDrafts[matchId] = text
        openChat(matchId: matchId)
    }

    func closeChat(matchId: String) {
        matchesPath.removeAll(where: { $0 == matchId })
    }

    func openPaywall() {
        isPaywallPresented = true
    }

    func showMessage(_ message: String, systemImage: String? = nil, tone: TempoTone = TempoTone.neutral) {
        toast = TempoToastItem(message, systemImage: systemImage, tone: tone)
    }

    func showError(_ message: String) {
        toast = TempoToastItem(message, systemImage: "exclamationmark.circle", tone: TempoTone.danger)
    }
}
