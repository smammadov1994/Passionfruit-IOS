import XCTest
@testable import Tempo

final class ClockMathTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingNeverGoesNegative() {
        XCTAssertEqual(DateClock.remaining(until: base.addingTimeInterval(192), now: base), 192, accuracy: 0.0001)
        XCTAssertEqual(DateClock.remaining(until: base, now: base), 0, accuracy: 0.0001)
        XCTAssertEqual(DateClock.remaining(until: base.addingTimeInterval(-5), now: base), 0, accuracy: 0.0001)
    }

    func testFractions() {
        let endsAt = base.addingTimeInterval(240)
        XCTAssertEqual(DateClock.fractionRemaining(endsAt: endsAt, duration: 240, now: base), 1, accuracy: 0.0001)
        XCTAssertEqual(DateClock.fractionRemaining(endsAt: endsAt, duration: 240, now: base.addingTimeInterval(60)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(DateClock.fractionElapsed(endsAt: endsAt, duration: 240, now: base.addingTimeInterval(60)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(DateClock.fractionRemaining(endsAt: endsAt, duration: 240, now: base.addingTimeInterval(500)), 0, accuracy: 0.0001)
        // A clock that starts early is clamped to a full ring.
        XCTAssertEqual(DateClock.fractionRemaining(endsAt: endsAt, duration: 240, now: base.addingTimeInterval(-30)), 1, accuracy: 0.0001)
        XCTAssertEqual(DateClock.fractionRemaining(endsAt: endsAt, duration: 0, now: base), 0, accuracy: 0.0001)
    }

    func testClockText() {
        XCTAssertEqual(DateClock.clockText(240), "4:00")
        XCTAssertEqual(DateClock.clockText(192), "3:12")
        XCTAssertEqual(DateClock.clockText(191.2), "3:12")
        XCTAssertEqual(DateClock.clockText(59.01), "1:00")
        XCTAssertEqual(DateClock.clockText(7), "0:07")
        XCTAssertEqual(DateClock.clockText(0.4), "0:01")
        XCTAssertEqual(DateClock.clockText(0), "0:00")
        XCTAssertEqual(DateClock.clockText(-3), "0:00")
    }

    func testWholeSeconds() {
        XCTAssertEqual(DateClock.wholeSeconds(20), 20)
        XCTAssertEqual(DateClock.wholeSeconds(19.5), 20)
        XCTAssertEqual(DateClock.wholeSeconds(0.01), 1)
        XCTAssertEqual(DateClock.wholeSeconds(0), 0)
    }

    func testFinalStretch() {
        XCTAssertFalse(DateClock.isFinalStretch(remaining: 31))
        XCTAssertTrue(DateClock.isFinalStretch(remaining: 30))
        XCTAssertTrue(DateClock.isFinalStretch(remaining: 0.5))
        XCTAssertFalse(DateClock.isFinalStretch(remaining: 0))
        XCTAssertTrue(DateClock.isFinalStretch(remaining: 9, threshold: 10))
    }

    func testIcebreakerTurnDrains() {
        let turn = IcebreakerState(
            question: "What are you unreasonably good at?",
            questionIndex: 0,
            speakerId: "u_me",
            turnEndsAt: base.addingTimeInterval(30),
            turnDuration: 30,
            isMyTurn: true
        )
        XCTAssertEqual(turn.remaining(at: base), 30, accuracy: 0.0001)
        XCTAssertEqual(turn.fractionRemaining(at: base), 1, accuracy: 0.0001)
        XCTAssertEqual(turn.fractionRemaining(at: base.addingTimeInterval(15)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(turn.remaining(at: base.addingTimeInterval(31)), 0, accuracy: 0.0001)
        XCTAssertEqual(turn.fractionRemaining(at: base.addingTimeInterval(31)), 0, accuracy: 0.0001)
    }

    func testServerClockIgnoresSmallDifferences() {
        var clock = ServerClock()
        clock.observe(serverNow: base.addingTimeInterval(1.2), localNow: base)
        XCTAssertEqual(clock.offset, 0, accuracy: 0.0001)
        let serverEnd = base.addingTimeInterval(240)
        XCTAssertEqual(clock.local(serverEnd), serverEnd)
    }

    func testServerClockCorrectsALargeSkew() {
        var clock = ServerClock()
        // The device clock is 90 s behind the server.
        clock.observe(serverNow: base.addingTimeInterval(90), localNow: base)
        XCTAssertEqual(clock.offset, 90, accuracy: 0.0001)
        let serverEnd = base.addingTimeInterval(90 + 240)
        let localEnd = clock.local(serverEnd)
        XCTAssertEqual(DateClock.remaining(until: localEnd, now: base), 240, accuracy: 0.0001)

        // And 2 minutes ahead.
        clock.observe(serverNow: base.addingTimeInterval(-120), localNow: base)
        XCTAssertEqual(clock.offset, -120, accuracy: 0.0001)
        XCTAssertEqual(DateClock.remaining(until: clock.local(base.addingTimeInterval(-120 + 30)), now: base), 30, accuracy: 0.0001)
    }

    func testBackoffStaysWithinBounds() {
        for attempt in 0..<12 {
            let delay = LiveRealtimeSocket.backoffDelay(attempt: attempt, maxDelay: 30)
            let ceiling = min(30, pow(2.0, Double(min(attempt, 10))))
            XCTAssertGreaterThanOrEqual(delay, ceiling * 0.5 - 0.0001)
            XCTAssertLessThanOrEqual(delay, ceiling + 0.0001)
        }
    }

    func testOnboardingDraftGate() {
        var draft = OnboardingDraft()
        XCTAssertFalse(draft.canSubmit)
        draft.firstName = "  Alex "
        draft.gender = .man
        draft.interestedIn = [.woman]
        let calendar = Calendar(identifier: .gregorian)
        draft.birthdate = calendar.date(byAdding: .year, value: -17, to: Date())
        XCTAssertFalse(draft.isAdult)
        XCTAssertFalse(draft.canSubmit)
        XCTAssertNotNil(draft.validationMessage)
        draft.birthdate = calendar.date(byAdding: .year, value: -30, to: Date())
        XCTAssertTrue(draft.isAdult)
        XCTAssertTrue(draft.canSubmit)
        XCTAssertNil(draft.validationMessage)
        let update = draft.makeProfileUpdate()
        XCTAssertEqual(update.firstName, "Alex")
        XCTAssertEqual(update.onboardingComplete, true)
        XCTAssertEqual(update.tzOffsetMinutes, TimeZone.current.secondsFromGMT() / 60)
    }
}
