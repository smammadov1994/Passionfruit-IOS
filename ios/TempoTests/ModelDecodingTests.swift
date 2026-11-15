import XCTest
@testable import Tempo

final class ModelDecodingTests: XCTestCase {
    // MARK: Dates

    func testParsesIsoDatesWithAndWithoutMilliseconds() throws {
        let withMillis = try XCTUnwrap(TempoJSON.parseDate("2026-11-14T21:04:05.123Z"))
        let without = try XCTUnwrap(TempoJSON.parseDate("2026-11-14T21:04:05Z"))
        XCTAssertEqual(withMillis.timeIntervalSince(without), 0.123, accuracy: 0.0005)
        XCTAssertNil(TempoJSON.parseDate("yesterday"))
    }

    func testFormatsDatesAsIsoUtcWithMilliseconds() throws {
        let date = try XCTUnwrap(TempoJSON.parseDate("2026-11-14T21:04:05.123Z"))
        XCTAssertEqual(TempoJSON.string(from: date), "2026-11-14T21:04:05.123Z")
    }

    func testBirthdateRoundTripAndAge() throws {
        let birth = try XCTUnwrap(Birthdate.date(from: "1996-05-14"))
        XCTAssertEqual(Birthdate.string(from: birth), "1996-05-14")
        let dayBefore = try XCTUnwrap(Birthdate.date(from: "2026-05-13"))
        let birthday = try XCTUnwrap(Birthdate.date(from: "2026-05-14"))
        XCTAssertEqual(Birthdate.age(from: birth, now: dayBefore), 29)
        XCTAssertEqual(Birthdate.age(from: birth, now: birthday), 30)
        XCTAssertNil(Birthdate.date(from: "14/05/1996"))
    }

    // MARK: Objects

    func testDecodesPartner() throws {
        let partner = try TempoJSON.decode(Partner.self, from: Fixtures.data(Fixtures.partner))
        XCTAssertEqual(partner.id, "u_maya")
        XCTAssertEqual(partner.firstName, "Maya")
        XCTAssertEqual(partner.age, 29)
        XCTAssertEqual(partner.city, "Brooklyn")
        XCTAssertEqual(partner.distanceKm ?? 0, 2.4, accuracy: 0.001)
        XCTAssertEqual(partner.photoUrl, "https://cdn.example.com/p/maya.jpg")
        XCTAssertEqual(partner.intention, .longTerm)
        XCTAssertEqual(partner.monogram, "M")
    }

    func testDecodesPartnerWithOptionalFieldsMissing() throws {
        let json = """
        {"id":"u_x","firstName":"Sam","age":31,"city":"Queens"}
        """
        let partner = try TempoJSON.decode(Partner.self, from: Fixtures.data(json))
        XCTAssertNil(partner.distanceKm)
        XCTAssertNil(partner.photoUrl)
        XCTAssertNil(partner.intention)
        XCTAssertEqual(partner.summaryLine, "Sam, 31 · Queens")
    }

    func testDecodesMessageAndMatch() throws {
        let match = try TempoJSON.decode(Match.self, from: Fixtures.data(Fixtures.match))
        XCTAssertEqual(match.id, "mt_1")
        XCTAssertEqual(match.partner.id, "u_maya")
        XCTAssertEqual(match.unreadCount, 2)
        XCTAssertEqual(match.matchedAt, Fixtures.date("2026-11-14T21:00:00.000Z"))
        let last = try XCTUnwrap(match.lastMessage)
        XCTAssertEqual(last.id, "m_1")
        XCTAssertEqual(last.matchId, "mt_1")
        XCTAssertEqual(last.senderId, "u_maya")
        XCTAssertEqual(last.text, "Hello you")
        XCTAssertEqual(last.clientId, "c-1")
        XCTAssertEqual(last.sentAt, Fixtures.date("2026-11-14T21:04:05.123Z"))
        XCTAssertEqual(match.lastActivityAt, last.sentAt)
    }

    func testDecodesFullUser() throws {
        let user = try TempoJSON.decode(User.self, from: Fixtures.data(Fixtures.user))
        XCTAssertEqual(user.id, "u_me")
        XCTAssertEqual(user.firstName, "Alex")
        XCTAssertEqual(user.birthdate, "1996-05-14")
        XCTAssertEqual(user.gender, .man)
        XCTAssertEqual(user.interestedIn, [.woman, .nonbinary])
        XCTAssertEqual(user.photoUrls.count, 1)
        XCTAssertEqual(user.intention, .longTerm)
        XCTAssertEqual(user.children, .open)
        XCTAssertEqual(user.religion, .agnostic)
        XCTAssertEqual(user.education, .masters)
        XCTAssertEqual(user.smoking, .never)
        XCTAssertEqual(user.drinking, .socially)
        XCTAssertTrue(user.isPremium)
        XCTAssertEqual(user.premiumExpiresAt, Fixtures.date("2026-12-14T00:00:00.000Z"))
        XCTAssertTrue(user.onboardingComplete)
        XCTAssertEqual(user.strikes, 1)
        XCTAssertNil(user.suspendedUntil)
        XCTAssertFalse(user.isSuspended)

        let preferences = user.preferences
        XCTAssertEqual(preferences.ageMin, 25)
        XCTAssertEqual(preferences.ageMax, 38)
        XCTAssertEqual(preferences.maxDistanceKm, 40)
        XCTAssertEqual(preferences.intentions, [.longTerm, .marriage])
        XCTAssertEqual(preferences.children, [.wants, .open])
        XCTAssertEqual(preferences.religions, [.agnostic])
        XCTAssertEqual(preferences.minEducation, .bachelors)
        XCTAssertEqual(preferences.smokingOk, [.never])
        XCTAssertEqual(preferences.drinkingOk, [.never, .socially])
        XCTAssertTrue(preferences.notifyOnlineSingles)
        XCTAssertTrue(preferences.hasAdvancedFilters)
    }

    func testDecodesFreshUserWithNullProfileFields() throws {
        let user = try TempoJSON.decode(User.self, from: Fixtures.data(Fixtures.freshUser))
        XCTAssertEqual(user.id, "u_new")
        XCTAssertEqual(user.birthdate, "")
        XCTAssertNil(user.gender)
        XCTAssertNil(user.age)
        XCTAssertFalse(user.onboardingComplete)
        XCTAssertNil(user.preferences.intentions)
        XCTAssertFalse(user.preferences.hasAdvancedFilters)
    }

    func testUserRoundTripsThroughEncoder() throws {
        let user = try TempoJSON.decode(User.self, from: Fixtures.data(Fixtures.user))
        let data = try TempoJSON.encode(user)
        let again = try TempoJSON.decode(User.self, from: data)
        XCTAssertEqual(user, again)
    }

    func testProfileUpdateOmitsNilFields() throws {
        let update = ProfileUpdate(firstName: "Alex", intention: .figuringOut)
        let data = try TempoJSON.encode(update)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.count, 2)
        XCTAssertEqual(object["firstName"] as? String, "Alex")
        XCTAssertEqual(object["intention"] as? String, "figuring_out")
    }

    func testProfileUpdateSendsNullForClearedFields() throws {
        let update = ProfileUpdate(bio: "Hi", smoking: .never, clearing: [.religion, .smoking])
        let data = try TempoJSON.encode(update)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object.count, 3)
        XCTAssertEqual(object["bio"] as? String, "Hi")
        XCTAssertTrue(object["religion"] is NSNull)
        // A field with a value is sent with its value even if it is also named in `clearing`.
        XCTAssertEqual(object["smoking"] as? String, "never")
    }

    func testDecodesConfig() throws {
        let config = try TempoJSON.decode(AppConfig.self, from: Fixtures.data(Fixtures.config))
        XCTAssertEqual(config.dateDurationSec, 240)
        XCTAssertEqual(config.turnDurationSec, 30)
        XCTAssertEqual(config.decisionWindowSec, 20)
        XCTAssertEqual(config.freeDailyDates, 5)
        XCTAssertEqual(config.frameSampleIntervalSec, 3, accuracy: 0.001)
        XCTAssertEqual(config.iceServers.count, 2)
        XCTAssertEqual(config.iceServers[0].urls, ["stun:stun.example.com:3478"])
        XCTAssertNil(config.iceServers[0].username)
        XCTAssertEqual(config.iceServers[1].username, "u")
        XCTAssertEqual(config.iceServers[1].credential, "c")
    }

    func testDecodesUsage() throws {
        let free = try TempoJSON.decode(Usage.self, from: Fixtures.data(Fixtures.usageFree))
        XCTAssertEqual(free.datesToday, 3)
        XCTAssertEqual(free.limit, 5)
        XCTAssertEqual(free.remaining, 2)
        let premium = try TempoJSON.decode(Usage.self, from: Fixtures.data(Fixtures.usagePremium))
        XCTAssertNil(premium.limit)
        XCTAssertNil(premium.remaining)
    }

    func testMapsErrorEnvelope() {
        let error = LiveAPIClient.mapError(status: 403, data: Fixtures.data(Fixtures.errorEnvelope))
        XCTAssertEqual(error, .server(status: 403, code: "limit_reached", message: "You have used your free dates for today."))
        XCTAssertEqual(error.userMessage, "You have used your free dates for today.")
        XCTAssertEqual(LiveAPIClient.mapError(status: 401, data: Data()), .notAuthenticated)
        let serverDown = LiveAPIClient.mapError(status: 503, data: Data())
        XCTAssertTrue(serverDown.isRetryable)
        XCTAssertEqual(serverDown.serverCode, "http_503")
    }

    func testEveryEnumHasADisplayNameAndSpecRawValues() {
        XCTAssertEqual(Gender.allCases.map { $0.rawValue }, ["woman", "man", "nonbinary"])
        XCTAssertEqual(Intention.allCases.map { $0.rawValue }, ["long_term", "short_term", "marriage", "figuring_out"])
        XCTAssertEqual(ChildrenStatus.allCases.map { $0.rawValue }, ["has_wants_more", "has_done", "wants", "doesnt_want", "open"])
        XCTAssertEqual(Religion.allCases.map { $0.rawValue }, ["agnostic", "atheist", "buddhist", "christian", "hindu", "jewish", "muslim", "spiritual", "other"])
        XCTAssertEqual(Education.allCases.map { $0.rawValue }, ["high_school", "some_college", "bachelors", "masters", "doctorate"])
        XCTAssertEqual(Smoking.allCases.map { $0.rawValue }, ["never", "sometimes", "regularly"])
        XCTAssertEqual(Drinking.allCases.map { $0.rawValue }, ["never", "socially", "regularly"])
        XCTAssertEqual(ReportReason.allCases.map { $0.rawValue }, ["nudity", "sexual_language", "harassment", "underage", "fake_profile", "spam", "other"])
        XCTAssertEqual(DateEndReason.allCases.map { $0.rawValue }, ["timer", "partner_left", "you_left", "moderation", "disconnect", "checkpoint"])
        for value in Gender.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in Intention.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in ChildrenStatus.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in Religion.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in Education.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in Smoking.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in Drinking.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in ReportReason.allCases { XCTAssertFalse(value.displayName.isEmpty) }
        for value in DateEndReason.allCases { XCTAssertFalse(value.displayName.isEmpty) }
    }

    // MARK: Server → Client frames

    func testDecodesQueueStatus() throws {
        let message = try ServerMessage.decode(from: Fixtures.queueStatus)
        XCTAssertEqual(message, .queueStatus(QueueStatus(compatibleOnline: 23, position: 2)))
    }

    func testDecodesQueueLimit() throws {
        let message = try ServerMessage.decode(from: Fixtures.queueLimit)
        XCTAssertEqual(message, .queueLimit(QueueLimit(limit: 5, resetsAt: Fixtures.date("2026-11-15T05:00:00.000Z"))))
    }

    func testDecodesDateMatched() throws {
        let message = try ServerMessage.decode(from: Fixtures.dateMatched)
        guard case .dateMatched(let matched) = message else {
            return XCTFail("Expected date.matched, got \(message)")
        }
        XCTAssertEqual(matched.dateId, "d_1")
        XCTAssertEqual(matched.partner.firstName, "Maya")
        XCTAssertEqual(matched.role, .caller)
        XCTAssertEqual(matched.iceServers.count, 2)
        XCTAssertEqual(matched.iceServers[1].credential, "c")
        XCTAssertEqual(message.dateId, "d_1")
    }

    func testDecodesDateStarted() throws {
        let message = try ServerMessage.decode(from: Fixtures.dateStarted)
        let expected = DateStarted(
            dateId: "d_1",
            startsAt: Fixtures.date("2026-11-14T21:00:00.000Z"),
            endsAt: Fixtures.date("2026-11-14T21:04:00.000Z")
        )
        XCTAssertEqual(message, .dateStarted(expected))
        XCTAssertEqual(expected.endsAt.timeIntervalSince(expected.startsAt), 240, accuracy: 0.001)
    }

    func testDecodesRtcSignals() throws {
        let offer = try ServerMessage.decode(from: Fixtures.rtcOffer)
        guard case .rtcSignal(let offerSignal) = offer else {
            return XCTFail("Expected rtc.signal, got \(offer)")
        }
        XCTAssertEqual(offerSignal.dateId, "d_1")
        XCTAssertEqual(offerSignal.payload.kind, .offer)
        XCTAssertEqual(offerSignal.payload.sdp, "v=0\r\no=- 1 2 IN IP4 127.0.0.1")
        XCTAssertNil(offerSignal.payload.candidate)

        let ice = try ServerMessage.decode(from: Fixtures.rtcIce)
        guard case .rtcSignal(let iceSignal) = ice else {
            return XCTFail("Expected rtc.signal, got \(ice)")
        }
        XCTAssertEqual(iceSignal.payload.kind, .ice)
        XCTAssertEqual(iceSignal.payload.sdpMid, "0")
        XCTAssertEqual(iceSignal.payload.sdpMLineIndex, 0)
        XCTAssertEqual(CallSignalID.matchId(fromDateId: iceSignal.dateId), "mt_1")
        XCTAssertNil(CallSignalID.matchId(fromDateId: "d_1"))
    }

    func testDecodesIcebreakerTurn() throws {
        let message = try ServerMessage.decode(from: Fixtures.icebreakerTurn)
        guard case .icebreakerTurn(let turn) = message else {
            return XCTFail("Expected icebreaker.turn, got \(message)")
        }
        XCTAssertEqual(turn.dateId, "d_1")
        XCTAssertEqual(turn.question, "What would your perfect Sunday look like?")
        XCTAssertEqual(turn.questionIndex, 3)
        XCTAssertEqual(turn.speakerId, "u_maya")
        XCTAssertEqual(turn.turnEndsAt, Fixtures.date("2026-11-14T21:01:30.500Z"))
        XCTAssertEqual(turn.turnDurationSec, 30, accuracy: 0.001)
    }

    func testDecodesDateEnded() throws {
        let timer = try ServerMessage.decode(from: Fixtures.dateEndedTimer)
        XCTAssertEqual(timer, .dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Fixtures.date("2026-11-14T21:04:20.000Z"))))
        let left = try ServerMessage.decode(from: Fixtures.dateEndedPartnerLeft)
        XCTAssertEqual(left, .dateEnded(DateEnded(dateId: "d_1", reason: .partnerLeft, decisionDeadline: nil)))
        for reason in ["you_left", "moderation", "disconnect"] {
            let json = "{\"type\":\"date.ended\",\"dateId\":\"d_1\",\"reason\":\"\(reason)\"}"
            let message = try ServerMessage.decode(from: json)
            guard case .dateEnded(let ended) = message else {
                return XCTFail("Expected date.ended, got \(message)")
            }
            XCTAssertEqual(ended.reason.rawValue, reason)
            XCTAssertNil(ended.decisionDeadline)
        }
    }

    func testDecodesDateResult() throws {
        let match = try ServerMessage.decode(from: Fixtures.dateResultMatch)
        guard case .dateResult(let matchResult) = match else {
            return XCTFail("Expected date.result, got \(match)")
        }
        XCTAssertEqual(matchResult.outcome, .match)
        XCTAssertEqual(matchResult.match?.id, "mt_1")
        XCTAssertEqual(matchResult.match?.partner.firstName, "Maya")

        let noMatch = try ServerMessage.decode(from: Fixtures.dateResultNoMatch)
        XCTAssertEqual(noMatch, .dateResult(DateResult(dateId: "d_1", outcome: .noMatch, match: nil)))
    }

    func testDecodesModerationAction() throws {
        let warn = try ServerMessage.decode(from: Fixtures.moderationWarn)
        XCTAssertEqual(warn, .moderationAction(ModerationActionMessage(dateId: "d_1", action: .warn, category: .sexualLanguage, message: "Keep it respectful.")))
        let end = try ServerMessage.decode(from: Fixtures.moderationEnd)
        XCTAssertEqual(end, .moderationAction(ModerationActionMessage(dateId: "d_1", action: .end, category: .nudity, message: "This date was ended.")))
    }

    func testDecodesChatMessageAndMatchRemoved() throws {
        let chat = try ServerMessage.decode(from: Fixtures.chatMessage)
        guard case .chatMessage(let message) = chat else {
            return XCTFail("Expected chat.message, got \(chat)")
        }
        XCTAssertEqual(message.id, "m_1")
        XCTAssertEqual(message.text, "Hello you")
        let removed = try ServerMessage.decode(from: Fixtures.matchRemoved)
        XCTAssertEqual(removed, .matchRemoved(matchId: "mt_1"))
    }

    func testDecodesCallFrames() throws {
        let signal = CallSignal(matchId: "mt_1", fromUserId: "u_maya")
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.callInvite), .callInvite(signal))
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.callAccept), .callAccept(signal))
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.callDecline), .callDecline(signal))
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.callEnd), .callEnd(signal))
    }

    func testDecodesAccountSuspended() throws {
        let dated = try ServerMessage.decode(from: Fixtures.accountSuspended)
        XCTAssertEqual(dated, .accountSuspended(AccountSuspended(until: Fixtures.date("2026-11-21T00:00:00.000Z"), reason: "Three strikes.")))
        let open = try ServerMessage.decode(from: Fixtures.accountSuspendedOpenEnded)
        XCTAssertEqual(open, .accountSuspended(AccountSuspended(until: nil, reason: "Pending review.")))
    }

    func testDecodesErrorPongAndUnknown() throws {
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.serverError), .error(ServerErrorMessage(code: "not_in_date", message: "You are not in that date.")))
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.pong), .pong)
        XCTAssertEqual(try ServerMessage.decode(from: Fixtures.unknownFrame), .unknown(type: "something.new"))
    }

    func testRejectsMalformedFrames() {
        XCTAssertThrowsError(try ServerMessage.decode(from: "{\"type\":\"date.started\",\"dateId\":\"d_1\"}"))
        XCTAssertThrowsError(try ServerMessage.decode(from: "{\"dateId\":\"d_1\"}"))
        XCTAssertThrowsError(try ServerMessage.decode(from: "not json"))
    }

    // MARK: Client → Server frames

    private func object(for message: ClientMessage) throws -> [String: Any] {
        let text = try message.jsonString()
        let data = Fixtures.data(text)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEncodesBareClientFrames() throws {
        let join = try object(for: .queueJoin)
        XCTAssertEqual(join["type"] as? String, "queue.join")
        XCTAssertEqual(join.count, 1)
        XCTAssertEqual(try object(for: .queueLeave)["type"] as? String, "queue.leave")
        XCTAssertEqual(try object(for: .ping)["type"] as? String, "ping")
    }

    func testEncodesDateClientFrames() throws {
        let ready = try object(for: .dateReady(dateId: "d_1"))
        XCTAssertEqual(ready["type"] as? String, "date.ready")
        XCTAssertEqual(ready["dateId"] as? String, "d_1")

        let pass = try object(for: .turnPass(dateId: "d_1"))
        XCTAssertEqual(pass["type"] as? String, "turn.pass")
        XCTAssertEqual(pass["dateId"] as? String, "d_1")

        let leave = try object(for: .dateLeave(dateId: "d_1"))
        XCTAssertEqual(leave["type"] as? String, "date.leave")

        let yes = try object(for: .dateDecide(dateId: "d_1", decision: .yes))
        XCTAssertEqual(yes["type"] as? String, "date.decide")
        XCTAssertEqual(yes["decision"] as? String, "yes")
        let no = try object(for: .dateDecide(dateId: "d_1", decision: .no))
        XCTAssertEqual(no["decision"] as? String, "no")
    }

    func testEncodesRtcSignal() throws {
        let offer = try object(for: .rtcSignal(dateId: "d_1", payload: .offer(sdp: "v=0")))
        XCTAssertEqual(offer["type"] as? String, "rtc.signal")
        XCTAssertEqual(offer["dateId"] as? String, "d_1")
        let offerPayload = try XCTUnwrap(offer["payload"] as? [String: Any])
        XCTAssertEqual(offerPayload["kind"] as? String, "offer")
        XCTAssertEqual(offerPayload["sdp"] as? String, "v=0")
        XCTAssertNil(offerPayload["candidate"])

        let ice = try object(for: .rtcSignal(dateId: CallSignalID.dateId(forMatch: "mt_1"), payload: .ice(candidate: "candidate:1", sdpMid: "0", sdpMLineIndex: 1)))
        XCTAssertEqual(ice["dateId"] as? String, "call:mt_1")
        let icePayload = try XCTUnwrap(ice["payload"] as? [String: Any])
        XCTAssertEqual(icePayload["kind"] as? String, "ice")
        XCTAssertEqual(icePayload["candidate"] as? String, "candidate:1")
        XCTAssertEqual(icePayload["sdpMid"] as? String, "0")
        XCTAssertEqual(icePayload["sdpMLineIndex"] as? Int, 1)
        XCTAssertNil(icePayload["sdp"])
    }

    func testEncodesCallClientFrames() throws {
        let frames: [(ClientMessage, String)] = [
            (.callInvite(matchId: "mt_1"), "call.invite"),
            (.callAccept(matchId: "mt_1"), "call.accept"),
            (.callDecline(matchId: "mt_1"), "call.decline"),
            (.callEnd(matchId: "mt_1"), "call.end")
        ]
        for (message, type) in frames {
            let json = try object(for: message)
            XCTAssertEqual(json["type"] as? String, type)
            XCTAssertEqual(json["matchId"] as? String, "mt_1")
            XCTAssertEqual(json.count, 2)
        }
    }

    func testReportRequestEncoding() throws {
        let request = ReportRequest(userId: "u_maya", dateId: "d_1", matchId: nil, reason: .sexualLanguage, details: nil)
        let data = try TempoJSON.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["userId"] as? String, "u_maya")
        XCTAssertEqual(json["dateId"] as? String, "d_1")
        XCTAssertEqual(json["reason"] as? String, "sexual_language")
        XCTAssertNil(json["matchId"])
        XCTAssertNil(json["details"])
    }
}
