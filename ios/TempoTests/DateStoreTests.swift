import XCTest
@testable import Tempo

@MainActor
final class DateStoreTests: XCTestCase {
    // MARK: Harness

    @MainActor
    private struct Harness {
        let environment: AppEnvironment
        let socket: MockRealtimeSocket
        var dates: DateStore { environment.dates }
    }

    /// A signed-in demo environment whose socket only records frames; the tests play the server.
    private func makeHarness() throws -> Harness {
        var config = DemoConfig()
        config.autoScript = false
        config.latency = 0
        let environment = AppEnvironment.demo(signedIn: true, onboarded: true, persist: false, config: config)
        let socket = try XCTUnwrap(environment.socket as? MockRealtimeSocket)
        var timing = DateStoreTiming()
        timing.interstitial = 0.05
        timing.connectTimeout = 5
        timing.resultGrace = 0.05
        timing.reconnectGrace = 0.05
        timing.videoFailureGrace = 0.05
        environment.dates.timing = timing
        if let video = environment.video as? MockVideoCallService {
            video.connectDelay = 0
        }
        return Harness(environment: environment, socket: socket)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func count(of message: ClientMessage, in socket: MockRealtimeSocket) -> Int {
        socket.sentMessages.filter { $0 == message }.count
    }

    private func matched(_ dateId: String = "d_1", role: CallRole = .caller) -> ServerMessage {
        .dateMatched(DateMatched(dateId: dateId, partner: Fixtures.maya, role: role, iceServers: []))
    }

    private func started(_ dateId: String = "d_1", duration: TimeInterval = 240) -> ServerMessage {
        let now = Date()
        return .dateStarted(DateStarted(dateId: dateId, startsAt: now, endsAt: now.addingTimeInterval(duration)))
    }

    /// Goes online, gets paired and starts the date.
    private func goLive(_ harness: Harness, dateId: String = "d_1") async {
        await harness.dates.startSearching()
        harness.dates.handle(matched(dateId))
        harness.dates.handle(started(dateId))
    }

    // MARK: Queue

    func testStartsIdle() throws {
        let harness = try makeHarness()
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertFalse(harness.dates.isActive)
        XCTAssertNil(harness.dates.partner)
    }

    func testGoOnlineJoinsTheQueue() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        XCTAssertEqual(harness.dates.phase, .searching)
        XCTAssertTrue(harness.dates.isActive)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 1)
        XCTAssertNil(harness.dates.permissionIssue)
    }

    func testGoOnlineIsBlockedWithoutCameraOrMicrophone() async throws {
        let harness = try makeHarness()
        let permissions = try XCTUnwrap(harness.environment.permissions as? MockMediaPermissions)
        permissions.cameraGranted = false
        await harness.dates.startSearching()
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertEqual(harness.dates.permissionIssue, .camera)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 0)

        permissions.microphoneGranted = false
        await harness.dates.startSearching()
        XCTAssertEqual(harness.dates.permissionIssue, .cameraAndMicrophone)

        permissions.cameraGranted = true
        permissions.microphoneGranted = true
        await harness.dates.startSearching()
        XCTAssertNil(harness.dates.permissionIssue)
        XCTAssertEqual(harness.dates.phase, .searching)
    }

    func testQueueStatusUpdatesTheLiveCount() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.handle(.queueStatus(QueueStatus(compatibleOnline: 23, position: 2)))
        XCTAssertEqual(harness.dates.compatibleOnline, 23)
        XCTAssertEqual(harness.dates.queuePosition, 2)
        XCTAssertEqual(harness.dates.phase, .searching)
    }

    func testQueueLimitStopsTheSearch() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        let resetsAt = Date().addingTimeInterval(3_600)
        harness.dates.handle(.queueLimit(QueueLimit(limit: 5, resetsAt: resetsAt)))
        XCTAssertEqual(harness.dates.phase, .limitReached(resetsAt: resetsAt))
        XCTAssertEqual(harness.dates.datesRemainingToday, 0)
    }

    func testGoOfflineLeavesTheQueue() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.goOffline()
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertEqual(count(of: .queueLeave, in: harness.socket), 1)
    }

    func testRejoinsTheQueueAfterAReconnect() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 1)
        harness.dates.socketStateChanged(.reconnecting)
        XCTAssertEqual(harness.dates.phase, .searching)
        harness.dates.socketStateChanged(.connected)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 2)
    }

    // MARK: Pairing and the live date

    func testPairingConnectsAndReportsReady() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.handle(matched())
        XCTAssertEqual(harness.dates.phase, .connecting(partner: Fixtures.maya))
        XCTAssertEqual(harness.dates.partner, Fixtures.maya)
        XCTAssertTrue(harness.dates.isInDate)
        let ready = await waitUntil { self.count(of: .dateReady(dateId: "d_1"), in: harness.socket) == 1 }
        XCTAssertTrue(ready)
    }

    func testPairingWhileNotSearchingIsTurnedDown() throws {
        let harness = try makeHarness()
        harness.dates.handle(matched("d_stray"))
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertEqual(count(of: .dateLeave(dateId: "d_stray"), in: harness.socket), 1)
    }

    func testDateStartedGoesLiveWithServerEndTime() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.handle(matched())
        let now = Date()
        harness.dates.handle(.dateStarted(DateStarted(dateId: "d_1", startsAt: now, endsAt: now.addingTimeInterval(240))))
        XCTAssertEqual(harness.dates.phase, .live)
        let endsAt = try XCTUnwrap(harness.dates.endsAt)
        XCTAssertEqual(endsAt.timeIntervalSince(now), 240, accuracy: 0.01)
        XCTAssertEqual(harness.dates.remaining(at: now.addingTimeInterval(48)), 192, accuracy: 0.01)
    }

    func testDateStartedCorrectsASkewedDeviceClock() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.handle(matched())
        // The server's clock is 10 minutes ahead of this device.
        let serverNow = Date().addingTimeInterval(600)
        harness.dates.handle(.dateStarted(DateStarted(dateId: "d_1", startsAt: serverNow, endsAt: serverNow.addingTimeInterval(240))))
        let remaining = harness.dates.remaining(at: Date())
        XCTAssertEqual(remaining, 240, accuracy: 1)
    }

    func testFramesForAnotherDateAreIgnored() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.dates.handle(matched("d_1"))
        harness.dates.handle(started("d_old"))
        XCTAssertEqual(harness.dates.phase, .connecting(partner: Fixtures.maya))
        harness.dates.handle(started("d_1"))
        XCTAssertEqual(harness.dates.phase, .live)

        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_old", reason: .partnerLeft, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .live)
        harness.dates.handle(.icebreakerTurn(IcebreakerTurn(dateId: "d_old", question: "Stale?", questionIndex: 0, speakerId: "u_maya", turnEndsAt: Date().addingTimeInterval(30), turnDurationSec: 30)))
        XCTAssertNil(harness.dates.icebreaker)
        harness.dates.handle(.dateResult(DateResult(dateId: "d_old", outcome: .noMatch, match: nil)))
        XCTAssertEqual(harness.dates.phase, .live)
        harness.dates.handle(.moderationAction(ModerationActionMessage(dateId: "d_old", action: .warn, category: .sexualLanguage, message: "Stale")))
        XCTAssertNil(harness.dates.moderationWarning)
    }

    func testIcebreakerTurnsAndPassing() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        let myId = try XCTUnwrap(harness.environment.session.userId)
        let turnEnd = Date().addingTimeInterval(30)

        harness.dates.handle(.icebreakerTurn(IcebreakerTurn(dateId: "d_1", question: "Perfect Sunday?", questionIndex: 0, speakerId: "u_maya", turnEndsAt: turnEnd, turnDurationSec: 30)))
        var turn = try XCTUnwrap(harness.dates.icebreaker)
        XCTAssertEqual(turn.question, "Perfect Sunday?")
        XCTAssertFalse(turn.isMyTurn)
        XCTAssertEqual(turn.turnDuration, 30, accuracy: 0.001)
        harness.dates.passTurn()
        XCTAssertEqual(count(of: .turnPass(dateId: "d_1"), in: harness.socket), 0)

        harness.dates.handle(.icebreakerTurn(IcebreakerTurn(dateId: "d_1", question: "Perfect Sunday?", questionIndex: 0, speakerId: myId, turnEndsAt: turnEnd, turnDurationSec: 30)))
        turn = try XCTUnwrap(harness.dates.icebreaker)
        XCTAssertTrue(turn.isMyTurn)
        XCTAssertEqual(turn.speakerId, myId)
        harness.dates.passTurn()
        XCTAssertEqual(count(of: .turnPass(dateId: "d_1"), in: harness.socket), 1)

        harness.dates.handle(.icebreakerTurn(IcebreakerTurn(dateId: "d_1", question: "Never-skip song?", questionIndex: 1, speakerId: myId, turnEndsAt: turnEnd, turnDurationSec: 30)))
        XCTAssertEqual(harness.dates.icebreaker?.questionIndex, 1)
    }

    func testMicAndCameraToggles() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        XCTAssertFalse(harness.dates.isMicMuted)
        harness.dates.toggleMic()
        XCTAssertTrue(harness.dates.isMicMuted)
        XCTAssertTrue(harness.environment.video.isMicMuted)
        harness.dates.toggleCamera()
        XCTAssertTrue(harness.dates.isCameraOff)
        XCTAssertTrue(harness.environment.video.isCameraOff)
        harness.dates.toggleMic()
        harness.dates.toggleCamera()
        XCTAssertFalse(harness.dates.isMicMuted)
        XCTAssertFalse(harness.dates.isCameraOff)
    }

    // MARK: Endings

    func testTimerEndLeadsToDecisionThenMatch() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        let deadline = Date().addingTimeInterval(20)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: deadline)))
        guard case .deciding(let partner, let shownDeadline) = harness.dates.phase else {
            return XCTFail("Expected deciding, got \(harness.dates.phase)")
        }
        XCTAssertEqual(partner, Fixtures.maya)
        XCTAssertEqual(shownDeadline.timeIntervalSince(deadline), 0, accuracy: 0.01)
        XCTAssertNil(harness.dates.endsAt)
        XCTAssertNil(harness.dates.icebreaker)

        harness.dates.decide(.yes)
        XCTAssertEqual(harness.dates.phase, .awaitingResult(partner: Fixtures.maya))
        XCTAssertEqual(harness.dates.myDecision, .yes)
        XCTAssertEqual(count(of: .dateDecide(dateId: "d_1", decision: .yes), in: harness.socket), 1)

        let match = Match(id: "mt_new", partner: Fixtures.maya, matchedAt: Date(), lastMessage: nil, unreadCount: 0)
        harness.dates.handle(.dateResult(DateResult(dateId: "d_1", outcome: .match, match: match)))
        XCTAssertEqual(harness.dates.phase, .matched(match: match))
        XCTAssertNil(harness.dates.nextCountdownEndsAt)
        XCTAssertNotNil(harness.environment.matches.match(id: "mt_new"))

        harness.dates.continueToNext()
        XCTAssertEqual(harness.dates.phase, .searching)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 2)
    }

    func testVideoStaysUpSilencedThroughTheDecision() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        let video: any VideoCallService = harness.environment.video
        let connected = await waitUntil { video.connectionState == .connected }
        XCTAssertTrue(connected)
        XCTAssertFalse(video.isCallAudioSilenced)

        let mockVideo = try XCTUnwrap(harness.environment.video as? MockVideoCallService)
        let moderation = try XCTUnwrap(harness.environment.moderation as? MockModerationService)
        let started = await waitUntil { moderation.activeDateId == "d_1" }
        XCTAssertTrue(started)
        XCTAssertTrue(mockVideo.isSamplingFrames)
        XCTAssertTrue(moderation.isTranscribing)

        // The timer ends: still connected (the Verdict blurs the partner) and nobody is heard,
        // so transcripts stop. The cameras are still on, so frames are still sampled and
        // checked. The user's own mic toggle is untouched.
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Date().addingTimeInterval(20))))
        XCTAssertEqual(video.connectionState, .connected)
        XCTAssertTrue(video.isCallAudioSilenced)
        XCTAssertFalse(harness.dates.isMicMuted)
        XCTAssertFalse(harness.dates.isInCall)
        XCTAssertTrue(harness.dates.isInDate)
        XCTAssertTrue(mockVideo.isSamplingFrames)
        XCTAssertEqual(moderation.activeDateId, "d_1")
        XCTAssertFalse(moderation.isTranscribing)
        let framesBefore: Int = moderation.submittedFrameCount
        mockVideo.emitFrameSample(Data([0xFF, 0xD8]))
        XCTAssertEqual(moderation.submittedFrameCount, framesBefore + 1)

        // Sealed, waiting for the result: the same.
        harness.dates.decide(.yes)
        XCTAssertEqual(video.connectionState, .connected)
        XCTAssertTrue(video.isCallAudioSilenced)
        XCTAssertTrue(mockVideo.isSamplingFrames)
        XCTAssertEqual(moderation.activeDateId, "d_1")
        mockVideo.emitFrameSample(Data([0xFF, 0xD8]))
        XCTAssertEqual(moderation.submittedFrameCount, framesBefore + 2)

        // The result closes the connection, and only then does frame moderation stop.
        harness.dates.handle(.dateResult(DateResult(dateId: "d_1", outcome: .noMatch, match: nil)))
        XCTAssertEqual(video.connectionState, .idle)
        XCTAssertFalse(video.isCallAudioSilenced)
        XCTAssertFalse(mockVideo.isSamplingFrames)
        XCTAssertNil(moderation.activeDateId)
        mockVideo.emitFrameSample(Data([0xFF, 0xD8]))
        XCTAssertEqual(moderation.submittedFrameCount, framesBefore + 2)
    }

    func testModerationCanEndTheDateWhileDeciding() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        let video: any VideoCallService = harness.environment.video
        let connected = await waitUntil { video.connectionState == .connected }
        XCTAssertTrue(connected)
        let mockVideo = try XCTUnwrap(harness.environment.video as? MockVideoCallService)
        let moderation = try XCTUnwrap(harness.environment.moderation as? MockModerationService)

        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Date().addingTimeInterval(20))))
        XCTAssertTrue(harness.dates.isInDate)

        // A frame sampled during the decision is flagged: the server ends the date for both.
        harness.dates.handle(.moderationAction(ModerationActionMessage(dateId: "d_1", action: .end, category: .nudity, message: "This date was ended.")))
        XCTAssertEqual(harness.dates.moderationWarning?.isFinal, true)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .moderation, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .ended(reason: .moderation))
        XCTAssertEqual(video.connectionState, .idle)
        XCTAssertFalse(mockVideo.isSamplingFrames)
        XCTAssertNil(moderation.activeDateId)
    }

    func testLeavingWhileDecidingClosesTheVideo() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        let video: any VideoCallService = harness.environment.video
        let connected = await waitUntil { video.connectionState == .connected }
        XCTAssertTrue(connected)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Date().addingTimeInterval(20))))
        XCTAssertEqual(video.connectionState, .connected)
        harness.dates.goOffline()
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertEqual(video.connectionState, .idle)
        XCTAssertEqual(count(of: .dateDecide(dateId: "d_1", decision: .no), in: harness.socket), 1)
    }

    func testNoMatchRequeuesAfterTheInterstitial() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Date().addingTimeInterval(20))))
        harness.dates.decide(.no)
        XCTAssertEqual(count(of: .dateDecide(dateId: "d_1", decision: .no), in: harness.socket), 1)
        harness.dates.handle(.dateResult(DateResult(dateId: "d_1", outcome: .noMatch, match: nil)))
        XCTAssertEqual(harness.dates.phase, .noMatch(partner: Fixtures.maya))
        XCTAssertNotNil(harness.dates.nextCountdownEndsAt)

        let requeued = await waitUntil { harness.dates.phase == .searching }
        XCTAssertTrue(requeued)
        XCTAssertNil(harness.dates.nextCountdownEndsAt)
        XCTAssertNil(harness.dates.partner)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 2)
    }

    func testUnansweredDecisionMovesOnAtTheDeadline() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .timer, decisionDeadline: Date().addingTimeInterval(0.05))))
        let waiting = await waitUntil { harness.dates.phase == .awaitingResult(partner: Fixtures.maya) || harness.dates.phase == .noMatch(partner: Fixtures.maya) || harness.dates.phase == .searching }
        XCTAssertTrue(waiting)
        XCTAssertNil(harness.dates.myDecision)
        // No answer is a No on the server; the client never sends a decision by itself.
        XCTAssertEqual(count(of: .dateDecide(dateId: "d_1", decision: .no), in: harness.socket), 0)
        XCTAssertEqual(count(of: .dateDecide(dateId: "d_1", decision: .yes), in: harness.socket), 0)
        // With no result from the server the store falls back to "no match" and moves on.
        let movedOn = await waitUntil { harness.dates.phase == .searching }
        XCTAssertTrue(movedOn)
    }

    func testPartnerLeftSkipsTheDecision() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .partnerLeft, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .partnerLeft(partner: Fixtures.maya))
        XCTAssertNotNil(harness.dates.nextCountdownEndsAt)
        let requeued = await waitUntil { harness.dates.phase == .searching }
        XCTAssertTrue(requeued)
    }

    func testStopAfterThisEndsTheNight() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.stopAfterThis()
        XCTAssertTrue(harness.dates.willStopAfterThis)
        XCTAssertEqual(harness.dates.phase, .live)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .partnerLeft, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .partnerLeft(partner: Fixtures.maya))
        let stopped = await waitUntil { harness.dates.phase == .idle }
        XCTAssertTrue(stopped)
        XCTAssertEqual(count(of: .queueJoin, in: harness.socket), 1)
        XCTAssertFalse(harness.dates.willStopAfterThis)
    }

    func testStopDuringTheInterstitialClosesAtOnce() async throws {
        let harness = try makeHarness()
        harness.dates.timing.interstitial = 30
        await goLive(harness)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .partnerLeft, decisionDeadline: nil)))
        harness.dates.stopAfterThis()
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertNil(harness.dates.nextCountdownEndsAt)
    }

    func testLeavingIsImmediateAndCountsAsLeft() async throws {
        let harness = try makeHarness()
        harness.dates.timing.interstitial = 30
        await goLive(harness)
        harness.dates.leaveDate()
        XCTAssertEqual(harness.dates.phase, .ended(reason: .youLeft))
        XCTAssertEqual(count(of: .dateLeave(dateId: "d_1"), in: harness.socket), 1)
        XCTAssertNotNil(harness.dates.nextCountdownEndsAt)
        // The server's echo of the same ending changes nothing.
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .youLeft, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .ended(reason: .youLeft))
        harness.dates.continueToNext()
        XCTAssertEqual(harness.dates.phase, .searching)
    }

    // MARK: Safety

    func testModerationWarningThenEnd() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.moderationAction(ModerationActionMessage(dateId: "d_1", action: .warn, category: .sexualLanguage, message: "Keep it respectful.")))
        let warning = try XCTUnwrap(harness.dates.moderationWarning)
        XCTAssertEqual(warning.category, .sexualLanguage)
        XCTAssertEqual(warning.message, "Keep it respectful.")
        XCTAssertFalse(warning.isFinal)
        XCTAssertEqual(harness.dates.phase, .live)

        harness.dates.handle(.moderationAction(ModerationActionMessage(dateId: "d_1", action: .end, category: .sexualLanguage, message: "This date was ended.")))
        XCTAssertEqual(harness.dates.moderationWarning?.isFinal, true)
        harness.dates.handle(.dateEnded(DateEnded(dateId: "d_1", reason: .moderation, decisionDeadline: nil)))
        XCTAssertEqual(harness.dates.phase, .ended(reason: .moderation))
        // No automatic re-queue after a safety stop.
        XCTAssertNil(harness.dates.nextCountdownEndsAt)
    }

    func testSuspensionClosesEverything() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.accountSuspended(AccountSuspended(until: nil, reason: "Three strikes.")))
        XCTAssertEqual(harness.dates.phase, .suspended(reason: "Three strikes."))
        XCTAssertTrue(harness.environment.session.isSuspended)
        await harness.dates.startSearching()
        XCTAssertEqual(harness.dates.phase, .suspended(reason: "Three strikes."))
    }

    func testThreeStrikesCountAsSuspended() async throws {
        var user = User(id: "u_1", strikes: 2)
        XCTAssertFalse(user.isSuspended)
        user.strikes = 3
        XCTAssertTrue(user.isSuspended)
        user.strikes = 0
        user.suspendedUntil = Date().addingTimeInterval(3_600)
        XCTAssertTrue(user.isSuspended)
        user.suspendedUntil = Date().addingTimeInterval(-3_600)
        XCTAssertFalse(user.isSuspended)
    }

    func testGoOnlineLandsInSuspendedForAThreeStrikeAccount() async throws {
        var config = DemoConfig()
        config.autoScript = false
        config.latency = 0
        let world = DemoWorld(config: config, onboarded: true, seedMatches: false, persistenceKey: nil)
        world.mutate { (state: inout DemoState) -> Void in
            state.user.strikes = 3
        }
        let api = MockAPIClient(world: world)
        let socket = MockRealtimeSocket(world: world)
        let environment = AppEnvironment(
            mode: .demo,
            api: api,
            socket: socket,
            video: MockVideoCallService(),
            moderation: MockModerationService(),
            purchases: MockPurchaseService(),
            push: MockPushService(),
            location: MockLocationService(),
            auth: MockAuthService(api: api),
            permissions: MockMediaPermissions(),
            tokenStore: InMemoryTokenStore(token: DemoWorld.demoToken),
            imageCache: ImageCache(baseURL: nil),
            initialUser: world.read { $0.user },
            initialConfig: config.appConfig
        )
        socket.connect()
        await environment.dates.startSearching()
        guard case .suspended = environment.dates.phase else {
            return XCTFail("Expected suspended, got \(environment.dates.phase)")
        }
        XCTAssertEqual(socket.sentMessages.filter { $0 == .queueJoin }.count, 0)
    }

    func testSuspensionNoticeWhileIdleDoesNotOpenTheDateFlow() throws {
        let harness = try makeHarness()
        harness.dates.handle(.accountSuspended(AccountSuspended(until: nil, reason: "Pending review.")))
        XCTAssertEqual(harness.dates.phase, .idle)
        XCTAssertTrue(harness.environment.session.isSuspended)
    }

    func testRefreshingTheUserLiftsAPushedSuspension() async throws {
        let harness = try makeHarness()
        let session: SessionStore = harness.environment.session
        harness.dates.handle(.accountSuspended(AccountSuspended(until: nil, reason: "Pending review.")))
        XCTAssertTrue(session.isSuspended)
        // GET /v1/me shows an account in good standing (support lifted the suspension).
        let reached = await session.refreshUser()
        XCTAssertTrue(reached)
        XCTAssertNil(session.suspension)
        XCTAssertFalse(session.isSuspended)
    }

    func testAnExpiredTimedSuspensionNoLongerCounts() throws {
        let harness = try makeHarness()
        let session: SessionStore = harness.environment.session
        session.markSuspended(AccountSuspended(until: Date().addingTimeInterval(-60), reason: "Paused."))
        XCTAssertFalse(session.isSuspended)
        session.markSuspended(AccountSuspended(until: Date().addingTimeInterval(3_600), reason: "Paused."))
        XCTAssertTrue(session.isSuspended)
    }

    func testEndOfDateRaceErrorsAreSilent() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.dates.handle(.error(ServerErrorMessage(code: "not_in_date", message: "You are not in that date.")))
        XCTAssertNil(harness.dates.lastError)
        XCTAssertEqual(harness.dates.phase, .live)
    }

    func testFinalCloseCodes() {
        XCTAssertTrue(LiveRealtimeSocket.isFinalCloseCode(4000))
        XCTAssertTrue(LiveRealtimeSocket.isFinalCloseCode(4002))
        XCTAssertFalse(LiveRealtimeSocket.isFinalCloseCode(4001))
        XCTAssertFalse(LiveRealtimeSocket.isFinalCloseCode(1001))
    }

    func testReportAndBlock() async throws {
        let harness = try makeHarness()
        harness.dates.timing.interstitial = 30
        await goLive(harness)
        let reported = await harness.dates.report(reason: .harassment, details: "Rude")
        XCTAssertTrue(reported)
        let blocked = await harness.dates.blockPartner()
        XCTAssertTrue(blocked)
        XCTAssertEqual(harness.dates.phase, .ended(reason: .youLeft))
        XCTAssertEqual(count(of: .dateLeave(dateId: "d_1"), in: harness.socket), 1)
    }

    // MARK: Connection loss

    func testLostSocketEndsTheDateAfterTheGracePeriod() async throws {
        let harness = try makeHarness()
        await goLive(harness)
        harness.socket.simulateState(.reconnecting)
        harness.dates.socketStateChanged(.reconnecting)
        XCTAssertEqual(harness.dates.phase, .live)
        let ended = await waitUntil { harness.dates.phase == .ended(reason: .disconnect) }
        XCTAssertTrue(ended)
        XCTAssertNil(harness.dates.nextCountdownEndsAt)
    }

    func testQuickReconnectKeepsTheDate() async throws {
        let harness = try makeHarness()
        harness.dates.timing.reconnectGrace = 0.3
        await goLive(harness)
        harness.socket.simulateState(.reconnecting)
        harness.dates.socketStateChanged(.reconnecting)
        harness.socket.simulateState(.connected)
        harness.dates.socketStateChanged(.connected)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(harness.dates.phase, .live)
    }

    // MARK: Through the socket

    func testFramesEmittedOnTheSocketReachTheStore() async throws {
        let harness = try makeHarness()
        await harness.dates.startSearching()
        harness.socket.emit(.queueStatus(QueueStatus(compatibleOnline: 31, position: 1)))
        let counted = await waitUntil { harness.dates.compatibleOnline == 31 }
        XCTAssertTrue(counted)
        harness.socket.emit(matched("d_7"))
        let connecting = await waitUntil { harness.dates.phase == .connecting(partner: Fixtures.maya) }
        XCTAssertTrue(connecting)
        harness.socket.emit(started("d_7"))
        let live = await waitUntil { harness.dates.phase == .live }
        XCTAssertTrue(live)
    }

    private func checkpointDemo() -> DateStore {
        var config = DemoConfig()
        config.autoScript = true
        config.latency = 0
        config.dateDurationSec = 4
        config.turnDurationSec = 1
        config.checkpointWindowSec = 3
        config.decisionWindowSec = 5
        config.pairingDelayMin = 0.05
        config.pairingDelayMax = 0.1
        config.partnerLeftProbability = 0
        let environment = AppEnvironment.demo(signedIn: true, onboarded: true, persist: false, config: config)
        return environment.dates
    }

    func testCheckpointPausesThenResumesWhenIKeepGoing() async throws {
        let dates = checkpointDemo()
        await dates.startSearching()
        let paused = await waitUntil(timeout: 14) { dates.checkpoint != nil }
        XCTAssertTrue(paused, "Expected the checkpoint after the first question, got \(dates.phase)")
        XCTAssertEqual(dates.phase, .live)
        XCTAssertNil(dates.endsAt, "The clock is paused during the vote")
        XCTAssertNil(dates.icebreaker)

        dates.voteAtCheckpoint(.carryOn)
        XCTAssertEqual(dates.checkpoint?.myChoice, .carryOn)
        dates.voteAtCheckpoint(.end)
        XCTAssertEqual(dates.checkpoint?.myChoice, .carryOn, "The first choice stands")

        let resumed = await waitUntil(timeout: 5) { dates.checkpoint == nil }
        XCTAssertTrue(resumed)
        XCTAssertEqual(dates.phase, .live)
        XCTAssertNotNil(dates.endsAt, "The clock runs again")
        let matched = await waitUntil(timeout: 10) {
            if case .matched = dates.phase { return true }
            return false
        }
        XCTAssertTrue(matched, "Expected the date to run to the end and match, got \(dates.phase)")
        dates.goOffline()
    }

    func testCheckpointEndsTheDateWhenIStopOrDoNotAnswer() async throws {
        let stopping = checkpointDemo()
        await stopping.startSearching()
        let paused = await waitUntil(timeout: 14) { stopping.checkpoint != nil }
        XCTAssertTrue(paused)
        stopping.voteAtCheckpoint(.end)
        let ended = await waitUntil(timeout: 5) { stopping.phase == .ended(reason: .checkpoint) }
        XCTAssertTrue(ended, "Expected the date to end at the checkpoint, got \(stopping.phase)")
        XCTAssertNil(stopping.checkpoint)
        stopping.goOffline()

        let silent = checkpointDemo()
        await silent.startSearching()
        let pausedAgain = await waitUntil(timeout: 14) { silent.checkpoint != nil }
        XCTAssertTrue(pausedAgain)
        let timedOut = await waitUntil(timeout: 8) { silent.phase == .ended(reason: .checkpoint) }
        XCTAssertTrue(timedOut, "No answer counts as stop, got \(silent.phase)")
        silent.goOffline()
    }

    func testScriptedDemoRunsAWholeDate() async throws {
        var config = DemoConfig()
        config.autoScript = true
        config.latency = 0
        config.dateDurationSec = 1
        config.turnDurationSec = 1
        config.decisionWindowSec = 5
        config.pairingDelayMin = 0.05
        config.pairingDelayMax = 0.1
        config.partnerLeftProbability = 0
        config.partnerYesProbability = 1
        config.matchOnFullDate = false
        let environment = AppEnvironment.demo(signedIn: true, onboarded: true, persist: false, config: config)
        let dates = environment.dates

        await dates.startSearching()
        XCTAssertEqual(dates.phase, .searching)
        let live = await waitUntil(timeout: 12) { dates.phase == .live }
        XCTAssertTrue(live, "Expected the scripted partner to arrive and the date to start, got \(dates.phase)")
        XCTAssertNotNil(dates.partner)
        let turn = await waitUntil(timeout: 5) { dates.icebreaker != nil || dates.phase != .live }
        XCTAssertTrue(turn)

        let deciding = await waitUntil(timeout: 8) {
            if case .deciding = dates.phase { return true }
            return false
        }
        XCTAssertTrue(deciding, "Expected the timer to end the date, got \(dates.phase)")
        dates.decide(.yes)
        let matched = await waitUntil(timeout: 8) {
            if case .matched = dates.phase { return true }
            return false
        }
        XCTAssertTrue(matched, "Expected a match when both say yes, got \(dates.phase)")
        dates.goOffline()
        XCTAssertEqual(dates.phase, .idle)
    }

    func testStayingForTheWholeDateIsAMatchWithNoVote() async throws {
        var config = DemoConfig()
        config.autoScript = true
        config.latency = 0
        config.dateDurationSec = 1
        config.turnDurationSec = 1
        config.checkpointWindowSec = 0
        config.pairingDelayMin = 0.05
        config.pairingDelayMax = 0.1
        config.partnerLeftProbability = 0
        let environment = AppEnvironment.demo(signedIn: true, onboarded: true, persist: false, config: config)
        let dates = environment.dates

        await dates.startSearching()
        var sawVote: Bool = false
        let matched = await waitUntil(timeout: 12) {
            if case .deciding = dates.phase { sawVote = true }
            if case .matched = dates.phase { return true }
            return false
        }
        XCTAssertTrue(matched, "Expected an instant match at the end of the date, got \(dates.phase)")
        XCTAssertFalse(sawVote)
        dates.goOffline()
    }
}
