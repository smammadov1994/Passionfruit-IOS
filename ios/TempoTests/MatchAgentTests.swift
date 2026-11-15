import XCTest
@testable import Tempo

/// The on-device agent's rules: what it says and offers for each state of a conversation.
final class MatchAgentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_700_000)
    private let me = "me"

    private func match(last: Message? = nil) -> Match {
        Match(
            id: "m1",
            partner: Partner(id: "p1", firstName: "Lena", age: 29, city: "NYC", distanceKm: 2, photoUrl: nil, intention: nil),
            matchedAt: now.addingTimeInterval(-86_400),
            lastMessage: last,
            unreadCount: 0
        )
    }

    private func message(_ text: String, mine: Bool, hoursAgo: Double) -> Message {
        Message(
            id: UUID().uuidString,
            matchId: "m1",
            senderId: mine ? me : "p1",
            text: text,
            sentAt: now.addingTimeInterval(-hoursAgo * 3600),
            clientId: nil
        )
    }

    private func brief(_ messages: [Message]) -> AgentBrief {
        let context = AgentContext(match: match(last: messages.last), messages: messages, myUserId: me, now: now, dateDuration: 240)
        return LocalMatchAgent(context: context).brief()
    }

    private func suggestions(_ brief: AgentBrief) -> [String] {
        brief.items.compactMap { item in
            if case .suggestion(let text) = item.kind { return text }
            return nil
        }
    }

    func testNewMatchGetsOpenersAndAReminder() {
        let result = brief([])
        XCTAssertEqual(result.standing, .fresh)
        XCTAssertEqual(suggestions(result).count, 2)
        XCTAssertTrue(result.items.contains { if case .reminder = $0.kind { return true } else { return false } })
    }

    func testTheirMessageMakesItYourMove() {
        let result = brief([message("I stand by it. Pineapple belongs on pizza.", mine: false, hoursAgo: 3)])
        XCTAssertEqual(result.standing, .yourMove)
        XCTAssertTrue(result.status.contains("Lena"))
        XCTAssertFalse(suggestions(result).isEmpty)
    }

    func testADayAndAPlaceBecomeACalendarPlan() throws {
        let result = brief([
            message("We should get coffee sometime", mine: true, hoursAgo: 2),
            message("It gets worse. Coffee on Saturday?", mine: false, hoursAgo: 1)
        ])
        XCTAssertEqual(result.standing, .planning)
        let plan = try XCTUnwrap(result.items.first { if case .plan = $0.kind { return true } else { return false } })
        guard case .plan(let title, let start, _) = plan.kind else { return XCTFail("not a plan") }
        XCTAssertEqual(title, "Coffee with Lena")
        XCTAssertGreaterThan(start, now)
        XCTAssertEqual(Calendar.current.component(.weekday, from: start), 7)
        XCTAssertEqual(Calendar.current.component(.hour, from: start), 11)
        XCTAssertTrue(suggestions(result).contains { $0.contains("Saturday") })
    }

    func testADayAloneIsNotAPlan() {
        let result = brief([message("Saturday was a long day", mine: false, hoursAgo: 1)])
        XCTAssertFalse(result.items.contains { if case .plan = $0.kind { return true } else { return false } })
    }

    func testMyRecentMessageMeansWaitingWithNothingToSend() {
        let result = brief([message("How was the hike?", mine: true, hoursAgo: 2)])
        XCTAssertEqual(result.standing, .waiting)
        XCTAssertTrue(suggestions(result).isEmpty)
    }

    func testMyOldMessageGoesQuietWithOneNudgeAndAReminder() {
        let result = brief([message("How was the hike?", mine: true, hoursAgo: 72)])
        XCTAssertEqual(result.standing, .quiet)
        XCTAssertEqual(suggestions(result).count, 1)
        XCTAssertTrue(result.items.contains { if case .reminder = $0.kind { return true } else { return false } })
    }
}
