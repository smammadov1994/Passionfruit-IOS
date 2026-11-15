import Foundation
import Observation

/// The agents, one per match: each keeps a brief on its conversation and can put things in the
/// calendar. Refresh after the matches list loads and whenever a conversation changes.
@MainActor
@Observable
final class AgentStore {
    /// Briefs keyed by match id.
    private(set) var briefs: [String: AgentBrief] = [:]
    /// Match ids whose agent is working right now.
    private(set) var thinking: Set<String> = []
    /// Items already acted on (added to the calendar), by item id.
    private(set) var done: Set<String> = []
    /// Items the user waved away, by item id.
    private(set) var dismissed: Set<String> = []
    /// Item ids being added to the calendar.
    private(set) var adding: Set<String> = []
    /// Who is writing in each chat, by match id. Missing = `.together`.
    private var voices: [String: ChatVoice] = [:]

    func voice(for matchId: String) -> ChatVoice {
        voices[matchId] ?? ChatVoice.together
    }

    func setVoice(_ voice: ChatVoice, for matchId: String) {
        voices[matchId] = voice
    }

    /// Reply suggestions the agent has for a match, in order.
    func suggestions(for matchId: String) -> [String] {
        items(for: matchId).compactMap { item in
            if case .suggestion(let text) = item.kind { return text }
            return nil
        }
    }

    private let service: any MatchAgentService
    private let calendar: any CalendarService
    private let matches: MatchesStore
    private let session: SessionStore
    private let config: ConfigStore

    init(
        service: any MatchAgentService,
        calendar: any CalendarService,
        matches: MatchesStore,
        session: SessionStore,
        config: ConfigStore
    ) {
        self.service = service
        self.calendar = calendar
        self.matches = matches
        self.session = session
        self.config = config
    }

    func brief(for matchId: String) -> AgentBrief? {
        briefs[matchId]
    }

    /// The items still worth showing for a match.
    func items(for matchId: String) -> [AgentItem] {
        (briefs[matchId]?.items ?? []).filter { !dismissed.contains($0.id) }
    }

    /// Brings every agent up to date. Briefs of matches that no longer exist are dropped.
    func refreshAll() async {
        let current: [Match] = matches.matches
        let ids: Set<String> = Set(current.map(\.id))
        briefs = briefs.filter { ids.contains($0.key) }
        for match in current {
            await refresh(matchId: match.id)
        }
    }

    /// Brings one agent up to date from what is known about that conversation.
    func refresh(matchId: String) async {
        guard let match = matches.match(id: matchId), !thinking.contains(matchId) else { return }
        thinking.insert(matchId)
        defer { thinking.remove(matchId) }
        // The agent reads the conversation; load it once if this match's chat was never opened.
        if matches.messages(for: matchId).isEmpty, match.lastMessage != nil {
            await matches.loadMessages(matchId: matchId)
        }
        let context = AgentContext(
            match: match,
            messages: matches.messages(for: matchId).filter { $0.delivery == .sent }.map(\.message),
            myUserId: session.user?.id,
            now: Date(),
            dateDuration: config.dateDuration
        )
        if let brief = try? await service.brief(for: context) {
            briefs[matchId] = brief
        }
    }

    func dismiss(_ item: AgentItem) {
        dismissed.insert(item.id)
    }

    /// Puts a plan or a reminder in the calendar. Returns nil on success, else why it failed.
    @discardableResult
    func addToCalendar(_ item: AgentItem, partnerName: String) async -> CalendarError? {
        guard !adding.contains(item.id), !done.contains(item.id) else { return nil }
        let title: String
        let start: Date
        let duration: TimeInterval
        switch item.kind {
        case .plan(let planTitle, let planStart, let planDuration):
            title = planTitle
            start = planStart
            duration = planDuration
        case .reminder(let reminderTitle, let at):
            title = reminderTitle
            start = at
            duration = 15 * 60
        case .suggestion, .note:
            return nil
        }
        adding.insert(item.id)
        defer { adding.remove(item.id) }
        do {
            try await calendar.addEvent(
                title: title,
                start: start,
                duration: duration,
                notes: String(localized: "Added by \(partnerName)'s agent in \(Brand.name).")
            )
            done.insert(item.id)
            return nil
        } catch let error as CalendarError {
            return error
        } catch {
            return CalendarError.failed
        }
    }
}
