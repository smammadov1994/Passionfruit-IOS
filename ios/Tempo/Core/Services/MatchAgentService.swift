import Foundation

/// What an agent is given: one match and that conversation, nothing else.
struct AgentContext: Sendable {
    var match: Match
    /// Oldest first. May be empty when only `match.lastMessage` is known.
    var messages: [Message]
    var myUserId: String?
    var now: Date
    var dateDuration: TimeInterval
}

/// Produces the brief for one match. The seam for a language-model agent: a server-backed
/// implementation can replace `LocalMatchAgentService` without touching the store or the UI.
protocol MatchAgentService: Sendable {
    func brief(for context: AgentContext) async throws -> AgentBrief
}

/// The agent that ships today: rules that run on the device. No text leaves the phone and no
/// language model is involved, so its suggestions are templates chosen from what was said
/// (who wrote last, how long ago, whether a day or a place to meet came up).
struct LocalMatchAgentService: MatchAgentService {
    init() {}

    func brief(for context: AgentContext) async throws -> AgentBrief {
        LocalMatchAgent(context: context).brief()
    }
}

/// The rules behind `LocalMatchAgentService`. Pure, so it can be tested without a store.
struct LocalMatchAgent {
    let context: AgentContext

    private var name: String { context.match.partner.firstName }
    private var matchId: String { context.match.id }

    /// The conversation, oldest first, falling back to the match's last message.
    private var messages: [Message] {
        if !context.messages.isEmpty {
            return context.messages
        }
        if let last = context.match.lastMessage {
            return [last]
        }
        return []
    }

    private func isMine(_ message: Message) -> Bool {
        guard let me = context.myUserId else { return message.senderId != context.match.partner.id }
        return message.senderId == me
    }

    func brief() -> AgentBrief {
        guard let last = messages.last else {
            return fresh()
        }
        let plan: AgentItem? = planItem()
        if isMine(last) {
            return afterMine(last, plan: plan)
        }
        return afterTheirs(last, plan: plan)
    }

    // MARK: Standings

    private func fresh() -> AgentBrief {
        let length: String = LocalMatchAgent.spokenDuration(context.dateDuration)
        return make(
            .fresh,
            status: String(localized: "You and \(name) matched \(relative(context.match.matchedAt)). Nobody has written yet."),
            items: [
                suggestion(String(localized: "\(length) went fast. What were you about to say when the timer cut us off?")),
                suggestion(String(localized: "Hi \(name). I said yes before the clock ran out, for the record.")),
                reminder(String(localized: "Say hello to \(name)"), hours: 20)
            ]
        )
    }

    private func afterTheirs(_ last: Message, plan: AgentItem?) -> AgentBrief {
        var items: [AgentItem] = []
        let text: String = last.text.lowercased()
        if plan != nil, let day = LocalMatchAgent.weekday(in: text) {
            items.append(suggestion(String(localized: "\(day.name) works for me. What time suits you?")))
            items.append(suggestion(String(localized: "I'm in. You pick the place, I'll be on time.")))
        } else if text.contains("?") {
            items.append(suggestion(String(localized: "Good question. Short answer: yes. Long answer over coffee?")))
            items.append(suggestion(String(localized: "Ha. I'll answer that if you answer one of mine first.")))
        } else {
            items.append(suggestion(String(localized: "Okay, now I need the full story.")))
            items.append(suggestion(String(localized: "That's a strong opinion. I respect it. Mostly.")))
        }
        if let plan {
            items.append(plan)
        }
        let standing: AgentBrief.Standing = plan == nil ? .yourMove : .planning
        let lead: String = plan == nil
            ? String(localized: "\(name) wrote \(relative(last.sentAt)). Your move.")
            : String(localized: "\(name) wrote \(relative(last.sentAt)) and a plan is taking shape.")
        return make(standing, status: lead, items: items)
    }

    private func afterMine(_ last: Message, plan: AgentItem?) -> AgentBrief {
        let hours: Double = context.now.timeIntervalSince(last.sentAt) / 3600
        if hours < 30 {
            var items: [AgentItem] = [note(String(localized: "Nothing to do. I'll tell you when \(name) replies."))]
            if let plan {
                items.insert(plan, at: 0)
            }
            return make(
                plan == nil ? .waiting : .planning,
                status: String(localized: "You wrote \(relative(last.sentAt)). Waiting on \(name)."),
                items: items
            )
        }
        return make(
            .quiet,
            status: String(localized: "It has been quiet since you wrote \(relative(last.sentAt))."),
            items: [
                suggestion(String(localized: "No pressure, but I'm still curious how that story ends.")),
                reminder(String(localized: "Check in with \(name)"), hours: 48),
                note(String(localized: "One light follow-up is fine. After that I'd leave it."))
            ]
        )
    }

    // MARK: Plans

    /// A calendar entry when a day and something to do both came up in the last few messages.
    private func planItem() -> AgentItem? {
        let recent: String = messages.suffix(6).map { $0.text.lowercased() }.joined(separator: " ")
        guard let day = LocalMatchAgent.weekday(in: recent), let activity = LocalMatchAgent.activity(in: recent) else {
            return nil
        }
        guard let start = LocalMatchAgent.next(weekday: day.number, hour: activity.hour, after: context.now) else {
            return nil
        }
        return AgentItem(
            id: "\(matchId)-plan-\(day.number)-\(activity.hour)",
            kind: .plan(title: String(localized: "\(activity.name) with \(name)"), start: start, duration: 90 * 60)
        )
    }

    private struct Day {
        let number: Int
        let name: String
    }

    private struct Activity {
        let name: String
        let hour: Int
    }

    /// Whole or cut-off day names ("saturday", "sat"), as people type them.
    private static func weekday(in text: String) -> Day? {
        let days: [(String, Int, String)] = [
            ("sun", 1, String(localized: "Sunday")), ("mon", 2, String(localized: "Monday")),
            ("tue", 3, String(localized: "Tuesday")), ("wed", 4, String(localized: "Wednesday")),
            ("thu", 5, String(localized: "Thursday")), ("fri", 6, String(localized: "Friday")),
            ("sat", 7, String(localized: "Saturday"))
        ]
        let words: [Substring] = text.split(whereSeparator: { !$0.isLetter })
        for (stem, number, name) in days where words.contains(where: { $0.hasPrefix(stem) && $0.count <= name.count }) {
            return Day(number: number, name: name)
        }
        return nil
    }

    private static func activity(in text: String) -> Activity? {
        if text.contains("coffee") || text.contains("brunch") || text.contains("breakfast") {
            return Activity(name: String(localized: "Coffee"), hour: 11)
        }
        if text.contains("dinner") {
            return Activity(name: String(localized: "Dinner"), hour: 19)
        }
        if text.contains("drink") || text.contains("wine") || text.contains("bar") {
            return Activity(name: String(localized: "Drinks"), hour: 19)
        }
        if text.contains("walk") || text.contains("park") {
            return Activity(name: String(localized: "A walk"), hour: 15)
        }
        return nil
    }

    private static func next(weekday: Int, hour: Int, after now: Date) -> Date? {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        return Calendar.current.nextDate(after: now, matching: components, matchingPolicy: Calendar.MatchingPolicy.nextTime)
    }

    // MARK: Pieces

    private func make(_ standing: AgentBrief.Standing, status: String, items: [AgentItem]) -> AgentBrief {
        AgentBrief(id: matchId, standing: standing, status: status, items: items, updatedAt: context.now)
    }

    private func suggestion(_ text: String) -> AgentItem {
        AgentItem(id: "\(matchId)-say-\(text.hashValue)", kind: .suggestion(text: text))
    }

    private func note(_ text: String) -> AgentItem {
        AgentItem(id: "\(matchId)-note-\(text.hashValue)", kind: .note(text: text))
    }

    private func reminder(_ title: String, hours: Double) -> AgentItem {
        AgentItem(
            id: "\(matchId)-remind-\(Int(hours))",
            kind: .reminder(title: title, at: context.now.addingTimeInterval(hours * 3600))
        )
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = RelativeDateTimeFormatter.UnitsStyle.full
        return formatter.localizedString(for: date, relativeTo: context.now)
    }

    private static func spokenDuration(_ duration: TimeInterval) -> String {
        let seconds: Int = max(0, Int(duration.rounded()))
        if seconds >= 60 && seconds % 60 == 0 {
            let minutes: Int = seconds / 60
            return minutes == 1 ? String(localized: "One minute") : String(localized: "\(minutes) minutes")
        }
        return String(localized: "\(seconds) seconds")
    }
}
