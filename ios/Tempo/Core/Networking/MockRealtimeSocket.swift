import Foundation

/// Demo-mode socket. With `DemoConfig.autoScript` on, it plays a believable speed-dating session:
/// queue counts, pairing after 2–4 s with rotating partners, `date.started`, icebreaker turns that
/// advance, the timer ending, and a result that depends on the user's decision. Now and then the
/// partner leaves early. With `autoScript` off it only records `sentMessages`, and tests or previews
/// drive it with `emit(_:)`.
@MainActor
final class MockRealtimeSocket: RealtimeSocket {
    private(set) var state: SocketConnectionState = .disconnected
    /// Every frame the app sent, oldest first.
    private(set) var sentMessages: [ClientMessage] = []

    let world: DemoWorld

    private let messageHub = Broadcaster<ServerMessage>()
    private let stateHub = Broadcaster<SocketConnectionState>()
    private var script: Task<Void, Never>?
    private var callScript: Task<Void, Never>?
    private var active: ActiveDate?
    private var questions: [String]
    private var questionCursor: Int = 0

    private struct ActiveDate {
        var dateId: String
        var partner: Partner
        var isReady: Bool = false
        var passRequested: Bool = false
        var decision: DateDecision?
        var checkpointChoice: CheckpointChoice?
    }

    init(world: DemoWorld) {
        self.world = world
        self.questions = IcebreakerFallback.loadQuestions().shuffled()
    }

    // MARK: RealtimeSocket

    func connect() {
        setState(.connected)
    }

    func disconnect() {
        cancelScripts()
        setState(.disconnected)
    }

    func send(_ message: ClientMessage) {
        sentMessages.append(message)
        guard world.config.autoScript, state == .connected else { return }
        switch message {
        case .queueJoin:
            startQueue()
        case .queueLeave:
            cancelDateScript()
        case .dateReady(let dateId):
            if active?.dateId == dateId {
                active?.isReady = true
            }
        case .turnPass(let dateId):
            if active?.dateId == dateId {
                active?.passRequested = true
            }
        case .dateLeave(let dateId):
            if active?.dateId == dateId {
                cancelDateScript()
                emit(.dateEnded(DateEnded(dateId: dateId, reason: .youLeft, decisionDeadline: nil)))
            }
        case .dateDecide(let dateId, let decision):
            if active?.dateId == dateId {
                active?.decision = decision
            }
        case .dateContinue(let dateId, let choice):
            if active?.dateId == dateId {
                active?.checkpointChoice = choice
            }
        case .callInvite(let matchId):
            answerCall(matchId: matchId)
        case .callEnd, .callDecline, .callAccept:
            callScript?.cancel()
            callScript = nil
        case .rtcSignal:
            break
        case .ping:
            emit(.pong)
        }
    }

    func messages() -> AsyncStream<ServerMessage> {
        messageHub.stream()
    }

    func states() -> AsyncStream<SocketConnectionState> {
        stateHub.stream()
    }

    // MARK: Test and preview hooks

    /// Delivers a server frame to every listener, as if the server had sent it.
    func emit(_ message: ServerMessage) {
        messageHub.yield(message)
    }

    /// Forces a connection state (for reconnect tests and previews).
    func simulateState(_ newState: SocketConnectionState) {
        setState(newState)
    }

    func clearSentMessages() {
        sentMessages.removeAll()
    }

    /// Makes a matched partner ring the user (`call.invite`).
    func simulateIncomingCall(matchId: String) {
        let partnerId: String? = world.read { (state: DemoState) -> String? in
            state.matches.first(where: { $0.id == matchId })?.partner.id
        }
        guard let partnerId else { return }
        emit(.callInvite(CallSignal(matchId: matchId, fromUserId: partnerId)))
    }

    // MARK: Script

    private func setState(_ newState: SocketConnectionState) {
        guard state != newState else { return }
        state = newState
        stateHub.yield(newState)
    }

    private func cancelDateScript() {
        script?.cancel()
        script = nil
        active = nil
    }

    private func cancelScripts() {
        cancelDateScript()
        callScript?.cancel()
        callScript = nil
    }

    /// Sleeps; returns false when the script was cancelled.
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    private func startQueue() {
        cancelDateScript()
        let freeLimit: Int = world.config.freeDailyDates
        let limitReached: Bool = world.read { (state: DemoState) -> Bool in
            !state.user.isPremium && state.datesToday >= freeLimit
        }
        if limitReached {
            emit(.queueLimit(QueueLimit(limit: freeLimit, resetsAt: DemoWorld.nextLocalMidnight())))
            return
        }
        script = Task { [weak self] in
            await self?.runQueue()
        }
    }

    private func runQueue() async {
        let online: Int = Int.random(in: 14...38)
        emit(.queueStatus(QueueStatus(compatibleOnline: online, position: 1)))
        let low: Double = world.config.pairingDelayMin
        let high: Double = max(low, world.config.pairingDelayMax)
        let delay: Double = Double.random(in: low...high)
        guard await pause(delay) else { return }
        await runDate()
    }

    private func nextQuestion() -> String {
        if questions.isEmpty {
            return IcebreakerFallback.builtIn[0]
        }
        let question: String = questions[questionCursor % questions.count]
        questionCursor += 1
        return question
    }

    private func runDate() async {
        let config: DemoConfig = world.config
        let myId: String = world.read { $0.user.id }
        let partner: Partner = world.nextPartner()
        let dateId: String = "demo-date-" + UUID().uuidString.lowercased()
        active = ActiveDate(dateId: dateId, partner: partner)
        emit(.dateMatched(DateMatched(dateId: dateId, partner: partner, role: .caller, iceServers: [])))

        // The clock starts when the client is ready, or 8 s after pairing.
        let readyDeadline: Date = Date().addingTimeInterval(8)
        while Date() < readyDeadline {
            if active?.isReady == true { break }
            guard await pause(0.1) else { return }
        }
        guard await pause(0.9) else { return }

        let startsAt: Date = Date()
        let duration: Double = Double(config.dateDurationSec)
        var endsAt: Date = startsAt.addingTimeInterval(duration)
        var didCheckpoint: Bool = config.checkpointWindowSec <= 0
        world.mutate { (state: inout DemoState) -> Void in
            state.datesToday += 1
        }
        emit(.dateStarted(DateStarted(dateId: dateId, startsAt: startsAt, endsAt: endsAt)))

        var partnerLeavesAt: Date?
        if Double.random(in: 0...1) < config.partnerLeftProbability {
            partnerLeavesAt = startsAt.addingTimeInterval(duration * Double.random(in: 0.35...0.8))
        }

        // Icebreaker turns: A answers, then B answers the same question, then a new question
        // with the other person going first.
        let turnDuration: Double = Double(config.turnDurationSec)
        var questionIndex: Int = 0
        var question: String = nextQuestion()
        var firstSpeakerIsMe: Bool = Bool.random()
        var answered: Int = 0
        var speakerIsMe: Bool = firstSpeakerIsMe
        var turnEndsAt: Date = Date().addingTimeInterval(turnDuration)
        var partnerPassesAt: Date? = speakerIsMe ? nil : Date().addingTimeInterval(turnDuration * Double.random(in: 0.5...0.95))

        guard await pause(1.0) else { return }
        turnEndsAt = Date().addingTimeInterval(turnDuration)
        if !speakerIsMe {
            partnerPassesAt = Date().addingTimeInterval(turnDuration * Double.random(in: 0.5...0.95))
        }
        emit(.icebreakerTurn(IcebreakerTurn(
            dateId: dateId,
            question: question,
            questionIndex: questionIndex,
            speakerId: speakerIsMe ? myId : partner.id,
            turnEndsAt: turnEndsAt,
            turnDurationSec: turnDuration
        )))

        while true {
            guard await pause(0.1) else { return }
            let now: Date = Date()
            if let leaveAt = partnerLeavesAt, now >= leaveAt {
                active = nil
                emit(.dateEnded(DateEnded(dateId: dateId, reason: .partnerLeft, decisionDeadline: nil)))
                return
            }
            if now >= endsAt {
                break
            }
            var advance: Bool = now >= turnEndsAt
            if speakerIsMe && active?.passRequested == true {
                advance = true
            }
            if let passAt = partnerPassesAt, !speakerIsMe, now >= passAt {
                advance = true
            }
            active?.passRequested = false
            if advance {
                answered += 1
                if answered >= 2 {
                    answered = 0
                    questionIndex += 1
                    question = nextQuestion()
                    firstSpeakerIsMe.toggle()
                    speakerIsMe = firstSpeakerIsMe
                    // After the first question: pause, and let the user vote. The scripted
                    // partner always wants to carry on.
                    if !didCheckpoint {
                        didCheckpoint = true
                        let pausedAt: Date = Date()
                        let voteDeadline: Date = pausedAt.addingTimeInterval(Double(config.checkpointWindowSec))
                        emit(.dateCheckpoint(DateCheckpoint(dateId: dateId, deadline: voteDeadline)))
                        while Date() < voteDeadline && active?.checkpointChoice == nil {
                            guard await pause(0.1) else { return }
                        }
                        guard active?.checkpointChoice == CheckpointChoice.carryOn else {
                            active = nil
                            emit(.dateEnded(DateEnded(dateId: dateId, reason: .checkpoint, decisionDeadline: nil)))
                            return
                        }
                        guard await pause(0.6) else { return }
                        let paused: TimeInterval = Date().timeIntervalSince(pausedAt)
                        endsAt = endsAt.addingTimeInterval(paused)
                        if let leaveAt = partnerLeavesAt {
                            partnerLeavesAt = leaveAt.addingTimeInterval(paused)
                        }
                        emit(.dateResumed(DateResumed(dateId: dateId, endsAt: endsAt)))
                    }
                } else {
                    speakerIsMe.toggle()
                }
                let turnStart: Date = Date()
                turnEndsAt = turnStart.addingTimeInterval(turnDuration)
                partnerPassesAt = speakerIsMe ? nil : turnStart.addingTimeInterval(turnDuration * Double.random(in: 0.5...0.95))
                emit(.icebreakerTurn(IcebreakerTurn(
                    dateId: dateId,
                    question: question,
                    questionIndex: questionIndex,
                    speakerId: speakerIsMe ? myId : partner.id,
                    turnEndsAt: turnEndsAt,
                    turnDurationSec: turnDuration
                )))
            }
        }

        // Timer ended: both decide privately.
        let deadline: Date = Date().addingTimeInterval(Double(config.decisionWindowSec))
        emit(.dateEnded(DateEnded(dateId: dateId, reason: .timer, decisionDeadline: deadline)))
        while Date() < deadline {
            if active?.decision != nil { break }
            guard await pause(0.1) else { return }
        }
        let decision: DateDecision = active?.decision ?? .no
        guard await pause(Double.random(in: 0.9...2.2)) else { return }

        let partnerSaysYes: Bool = Double.random(in: 0...1) < config.partnerYesProbability
        active = nil
        if decision == .yes && partnerSaysYes {
            let match: Match = world.makeMatch(with: partner)
            emit(.dateResult(DateResult(dateId: dateId, outcome: .match, match: match)))
        } else {
            emit(.dateResult(DateResult(dateId: dateId, outcome: .noMatch, match: nil)))
        }
    }

    private func answerCall(matchId: String) {
        callScript?.cancel()
        let partnerId: String? = world.read { (state: DemoState) -> String? in
            state.matches.first(where: { $0.id == matchId })?.partner.id
        }
        guard let partnerId else { return }
        callScript = Task { [weak self] in
            guard let self else { return }
            guard await self.pause(Double.random(in: 1.5...3.0)) else { return }
            if Double.random(in: 0...1) < 0.85 {
                self.emit(.callAccept(CallSignal(matchId: matchId, fromUserId: partnerId)))
            } else {
                self.emit(.callDecline(CallSignal(matchId: matchId, fromUserId: partnerId)))
            }
        }
    }
}
