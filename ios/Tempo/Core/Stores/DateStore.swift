import Foundation
import Observation

/// Drives the entire date flow UI.
enum DatePhase: Equatable, Sendable {
    /// Not online. The date flow cover is closed.
    case idle
    /// In the queue, waiting to be paired.
    case searching
    /// The free daily cap is used up; the user is not queued.
    case limitReached(resetsAt: Date)
    /// Paired; video is connecting. The date clock has not started.
    case connecting(partner: Partner)
    /// The date is running. See `endsAt` and `icebreaker`.
    case live
    /// Time is up; the user picks Yes or No before `deadline`.
    case deciding(partner: Partner, deadline: Date)
    /// The user's answer is sealed (or the window closed); waiting for the result.
    case awaitingResult(partner: Partner)
    case matched(match: Match)
    case noMatch(partner: Partner)
    /// The partner left early. No decision screen.
    case partnerLeft(partner: Partner)
    /// The date ended for another reason: `.youLeft`, `.moderation` or `.disconnect`.
    case ended(reason: DateEndReason)
    case suspended(reason: String)
}

/// A safety notice to show over the call.
struct ModerationWarning: Sendable, Equatable, Identifiable {
    var id: UUID
    var category: ModerationCategory
    var message: String
    /// True when the date is being ended because of this (the call closes right after).
    var isFinal: Bool
    var issuedAt: Date
}

/// The pause after the first question.
struct CheckpointState: Equatable, Sendable {
    var deadline: Date
    /// The user's own vote once cast; nil while still choosing.
    var myChoice: CheckpointChoice?
}

/// Local timings of the date flow that are not server tunables.
struct DateStoreTiming: Sendable, Equatable {
    /// Interstitial before automatically re-queueing (SPEC: 3 s).
    var interstitial: TimeInterval = 3
    /// How long to wait for `date.started` after pairing before giving up on this partner.
    var connectTimeout: TimeInterval = 20
    /// How long to wait for `date.result` after the decision deadline.
    var resultGrace: TimeInterval = 12
    /// How long a dropped socket may take to come back before the date is treated as lost.
    var reconnectGrace: TimeInterval = 12
    /// How long failed video may take to recover before the date is treated as lost.
    var videoFailureGrace: TimeInterval = 8
    /// How long after the server's end time a live date may go without `date.ended` before it
    /// is treated as lost (the server stopped answering for this date).
    var liveOverrunGrace: TimeInterval = 15
    /// How long a search may run before it stops and says nobody was found.
    var searchTimeout: TimeInterval = 90

    init() {
        #if DEBUG
        // `-allowNoVideo`: do not end a date because video never connected. For trying the flow
        // against `npm run partner` (which has no video) or between two simulators (no cameras).
        if ProcessInfo.processInfo.arguments.contains("-allowNoVideo") {
            videoFailureGrace = 3600
        }
        // `-shortSearch`: give up searching after 8 s, to look at the "nobody found" state.
        if ProcessInfo.processInfo.arguments.contains("-shortSearch") {
            searchTimeout = 8
        }
        #endif
    }
}

/// The speed-date state machine. Server frames come in through `handle(_:)`; UI calls the intents.
@MainActor
@Observable
final class DateStore {
    // MARK: Observable state

    private(set) var phase: DatePhase = .idle
    /// The current (or just-finished) partner. nil while idle or searching.
    private(set) var partner: Partner?
    /// When the running date started, on the device's clock.
    private(set) var startsAt: Date?
    /// When the running date ends, on the device's clock. Drive the Clock from this.
    private(set) var endsAt: Date?
    /// The current icebreaker turn. nil until the first `icebreaker.turn` of a date.
    private(set) var icebreaker: IcebreakerState?
    /// "N compatible people online now".
    private(set) var compatibleOnline: Int = 0
    private(set) var queuePosition: Int?
    private(set) var moderationWarning: ModerationWarning?
    /// The user tucked the Turn Card away. Persists across dates in this session.
    var isIcebreakerHidden: Bool = false
    private(set) var isMicMuted: Bool = false
    private(set) var isCameraOff: Bool = false
    private(set) var cameraPosition: CameraPosition = .front
    /// True when a search ran its full time and found nobody. The phase stays `.searching`, but
    /// the user is no longer in the queue; offer `searchAgain()` and `goOffline()`.
    private(set) var didSearchTimeOut: Bool = false
    /// Set while the date is paused at the checkpoint after the first question: both vote
    /// privately before `deadline`. The phase stays `.live`; audio is silenced both ways.
    private(set) var checkpoint: CheckpointState?
    /// Free dates left today. nil = unlimited (Premium) or not loaded yet; check `usage`.
    private(set) var datesRemainingToday: Int?
    private(set) var usage: Usage?
    /// While set, an interstitial is counting down to the next step (re-queue, or going idle
    /// when `willStopAfterThis`). nil = nothing happens until the user acts.
    private(set) var nextCountdownEndsAt: Date?
    /// Set when camera or microphone access blocks going online. Offer `openSettings()`.
    private(set) var permissionIssue: PermissionIssue?
    /// The user asked to stop after the current date.
    private(set) var willStopAfterThis: Bool = false
    /// The user's sealed answer for the date that just ended. nil = not answered.
    private(set) var myDecision: DateDecision?
    private(set) var videoState: VideoConnectionState = .idle
    private(set) var socketState: SocketConnectionState = .disconnected
    /// True while `goOnline()` is asking for permissions.
    private(set) var isStartingUp: Bool = false
    /// The latest failure, user-presentable. Set to nil to dismiss.
    var lastError: TempoError?

    // MARK: Dependencies

    @ObservationIgnored private let socket: any RealtimeSocket
    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let video: any VideoCallService
    @ObservationIgnored private let moderation: any ModerationService
    @ObservationIgnored private let permissions: any MediaPermissions
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let session: SessionStore

    @ObservationIgnored var timing: DateStoreTiming = DateStoreTiming()
    /// Called with every new match. Wired by `AppEnvironment` to `MatchesStore.insert`.
    @ObservationIgnored var onMatch: (@MainActor (Match) -> Void)?
    /// Returns true while a post-match video call owns the camera. Wired by `AppEnvironment`.
    @ObservationIgnored var isBlockedByCall: (@MainActor () -> Bool)?

    // MARK: Private state

    @ObservationIgnored private(set) var currentDateId: String?
    @ObservationIgnored private var lastDateId: String?
    @ObservationIgnored private var lastPartner: Partner?
    @ObservationIgnored private var clock: ServerClock = ServerClock()
    @ObservationIgnored private var onlineToken: Int = 0
    /// True while searching without a `queue.join` on the current socket connection.
    @ObservationIgnored private var needsQueueJoin: Bool = false

    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var socketStateTask: Task<Void, Never>?
    @ObservationIgnored private var videoStateTask: Task<Void, Never>?
    @ObservationIgnored private var goOnlineTask: Task<Void, Never>?
    @ObservationIgnored private var callSetupTask: Task<Void, Never>?
    @ObservationIgnored private var connectTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var decisionTask: Task<Void, Never>?
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectGraceTask: Task<Void, Never>?
    @ObservationIgnored private var videoFailureTask: Task<Void, Never>?
    @ObservationIgnored private var liveOverrunTask: Task<Void, Never>?
    @ObservationIgnored private var searchTimeoutTask: Task<Void, Never>?

    init(
        socket: any RealtimeSocket,
        api: any APIClient,
        video: any VideoCallService,
        moderation: any ModerationService,
        permissions: any MediaPermissions,
        config: ConfigStore,
        session: SessionStore
    ) {
        self.socket = socket
        self.api = api
        self.video = video
        self.moderation = moderation
        self.permissions = permissions
        self.config = config
        self.session = session
        self.socketState = socket.state
        self.isMicMuted = video.isMicMuted
        self.isCameraOff = video.isCameraOff
        self.cameraPosition = video.cameraPosition
        startListening()
    }

    // MARK: Derived

    /// True whenever the date flow should be on screen (`phase != .idle`).
    var isActive: Bool { phase != .idle }

    /// True while a partner is attached: connecting, live, deciding or awaiting the result.
    var isInDate: Bool {
        switch phase {
        case .connecting, .live, .deciding, .awaitingResult:
            return true
        case .idle, .searching, .limitReached, .matched, .noMatch, .partnerLeft, .ended, .suspended:
            return false
        }
    }

    /// True while the date itself is running or about to: connecting or live. Audio flows and
    /// speech is transcribed only in these phases. The video connection outlives it: both videos
    /// stay up (silenced) through `deciding` and `awaitingResult`, i.e. for all of `isInDate`,
    /// so the Verdict can blur the partner behind the question. Because the cameras are still
    /// on there, camera FRAMES keep being sampled and checked until the video is torn down.
    var isInCall: Bool {
        switch phase {
        case .connecting, .live:
            return true
        default:
            return false
        }
    }

    /// Seconds left in the running date (0 when there is none).
    func remaining(at now: Date = Date()) -> TimeInterval {
        guard let endsAt else { return 0 }
        return DateClock.remaining(until: endsAt, now: now)
    }

    // MARK: Intents

    /// Asks for camera and microphone access if needed, then joins the queue.
    func goOnline() {
        goOnlineTask?.cancel()
        goOnlineTask = Task { [weak self] in
            await self?.startSearching()
        }
    }

    /// The awaitable body of `goOnline()`.
    func startSearching() async {
        switch phase {
        case .idle, .limitReached, .matched, .noMatch, .partnerLeft, .ended:
            break
        case .searching, .connecting, .live, .deciding, .awaitingResult, .suspended:
            return
        }
        guard !isStartingUp else { return }
        if session.isSuspended {
            enterSuspended(reason: session.suspension?.reason ?? "")
            return
        }
        if let blocked = isBlockedByCall, blocked() {
            lastError = .unknown(String(localized: "Finish your call first."))
            return
        }
        isStartingUp = true
        permissionIssue = nil
        lastError = nil
        onlineToken += 1
        let token: Int = onlineToken
        let issue: PermissionIssue? = await permissions.requestCameraAndMicrophone()
        isStartingUp = false
        guard token == onlineToken else { return }
        if let issue {
            permissionIssue = issue
            return
        }
        willStopAfterThis = false
        cancelCountdown()
        requeue()
        Task { [weak self] in
            await self?.refreshUsage()
        }
    }

    /// Leaves the queue or the current date and closes the date flow.
    func goOffline() {
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        didSearchTimeOut = false
        onlineToken += 1
        goOnlineTask?.cancel()
        goOnlineTask = nil
        switch phase {
        case .searching:
            socket.send(.queueLeave)
        case .connecting, .live:
            if let dateId = currentDateId {
                socket.send(.dateLeave(dateId: dateId))
            }
        case .deciding:
            if let dateId = currentDateId {
                socket.send(.dateDecide(dateId: dateId, decision: .no))
            }
        case .idle, .limitReached, .awaitingResult, .matched, .noMatch, .partnerLeft, .ended, .suspended:
            break
        }
        cancelDateTimers()
        cancelCountdown()
        let callOwnsCamera: Bool = isBlockedByCall?() ?? false
        if !callOwnsCamera {
            finishCallMedia()
            video.stopLocalCapture()
        }
        clearDateState()
        willStopAfterThis = false
        isStartingUp = false
        phase = .idle
    }

    /// Leaves the date right now. Counts as a No. During the decision it is the same as `decide(.no)`.
    func leaveDate() {
        switch phase {
        case .connecting, .live:
            if let dateId = currentDateId {
                socket.send(.dateLeave(dateId: dateId))
            }
            finishCallMedia()
            phase = .ended(reason: .youLeft)
            beginInterstitial()
        case .deciding:
            decide(.no)
        case .idle, .searching, .limitReached, .awaitingResult, .matched, .noMatch, .partnerLeft, .ended, .suspended:
            break
        }
    }

    /// Passes the icebreaker turn. Only does something when it is the user's turn.
    func passTurn() {
        guard phase == .live, let dateId = currentDateId, let turn = icebreaker, turn.isMyTurn else { return }
        socket.send(.turnPass(dateId: dateId))
    }

    /// Seals the user's answer.
    func decide(_ decision: DateDecision) {
        guard case .deciding(let decidingPartner, let deadline) = phase, let dateId = currentDateId else { return }
        myDecision = decision
        socket.send(.dateDecide(dateId: dateId, decision: decision))
        decisionTask?.cancel()
        decisionTask = nil
        phase = .awaitingResult(partner: decidingPartner)
        scheduleResultTimeout(dateId: dateId, deadline: deadline, partner: decidingPartner)
    }

    /// Skips the interstitial (or leaves the match screen) and joins the queue again.
    func continueToNext() {
        switch phase {
        case .matched, .noMatch, .partnerLeft, .ended, .limitReached:
            break
        case .idle, .searching, .connecting, .live, .deciding, .awaitingResult, .suspended:
            return
        }
        if session.isSuspended {
            enterSuspended(reason: session.suspension?.reason ?? "")
            return
        }
        willStopAfterThis = false
        cancelCountdown()
        requeue()
        Task { [weak self] in
            await self?.refreshUsage()
        }
    }

    /// "Stop for tonight". Between dates it closes the flow at once; during a date it lets the
    /// date finish and then stops instead of re-queueing.
    func stopAfterThis() {
        switch phase {
        case .connecting, .live, .deciding, .awaitingResult:
            willStopAfterThis = true
        case .searching, .limitReached, .matched, .noMatch, .partnerLeft, .ended, .suspended:
            goOffline()
        case .idle:
            break
        }
    }

    func toggleMic() {
        isMicMuted.toggle()
        video.setMicMuted(isMicMuted)
    }

    func toggleCamera() {
        isCameraOff.toggle()
        video.setCameraOff(isCameraOff)
    }

    func flipCamera() {
        Task { [weak self] in
            guard let self else { return }
            await self.video.flipCamera()
            self.cameraPosition = self.video.cameraPosition
        }
    }

    /// Reports the current (or just-finished) partner. Returns true when the report was sent.
    @discardableResult
    func report(reason: ReportReason, details: String?) async -> Bool {
        guard let target = partner ?? lastPartner else { return false }
        let request = ReportRequest(
            userId: target.id,
            dateId: currentDateId ?? lastDateId,
            matchId: nil,
            reason: reason,
            details: details
        )
        do {
            try await api.report(request)
            return true
        } catch {
            fail(TempoError.from(error))
            return false
        }
    }

    /// Blocks the current (or just-finished) partner and leaves the date. They are never paired again.
    @discardableResult
    func blockPartner() async -> Bool {
        guard let target = partner ?? lastPartner else { return false }
        do {
            try await api.block(userId: target.id)
        } catch {
            fail(TempoError.from(error))
            return false
        }
        leaveDate()
        return true
    }

    func dismissModerationWarning() {
        moderationWarning = nil
    }

    func dismissPermissionIssue() {
        permissionIssue = nil
    }

    /// Asks for camera and microphone access ahead of time (the onboarding priming step), through
    /// the same permission service and in the same order as `goOnline()`. It does not join the
    /// queue and does not touch `permissionIssue`: the caller shows the returned issue itself
    /// (nil = both granted). Tonight raises `permissionIssue` again if the user goes online
    /// while access is still off.
    func requestMediaAccess() async -> PermissionIssue? {
        await permissions.requestCameraAndMicrophone()
    }

    /// Opens this app's page in Settings (for `permissionIssue`).
    func openSettings() {
        SystemSettings.open()
    }

    /// Reloads `usage` and `datesRemainingToday` (`GET /v1/usage`).
    func refreshUsage() async {
        guard session.isSignedIn else { return }
        do {
            let fetched: Usage = try await api.fetchUsage()
            usage = fetched
            datesRemainingToday = fetched.remaining
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                session.handle(mapped)
            }
        }
    }

    /// Reloads `compatibleOnline` (`GET /v1/online-count`) for the Tonight tab while idle.
    func refreshOnlineCount() async {
        guard session.isSignedIn else { return }
        do {
            compatibleOnline = try await api.fetchOnlineCount()
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                session.handle(mapped)
            }
        }
    }

    /// Puts the store straight into a phase. For SwiftUI previews only; never call it from app code.
    func debugSetPhase(
        _ newPhase: DatePhase,
        partner newPartner: Partner? = nil,
        endsAt newEndsAt: Date? = nil,
        icebreaker newIcebreaker: IcebreakerState? = nil,
        nextCountdownEndsAt newCountdownEndsAt: Date? = nil,
        moderationWarning newWarning: ModerationWarning? = nil
    ) {
        cancelDateTimers()
        cancelCountdown()
        phase = newPhase
        partner = newPartner
        lastPartner = newPartner
        startsAt = (newEndsAt == nil) ? nil : Date()
        endsAt = newEndsAt
        icebreaker = newIcebreaker
        nextCountdownEndsAt = newCountdownEndsAt
        moderationWarning = newWarning
    }

    /// Returns to a clean idle state (sign-out).
    func reset() {
        goOffline()
        usage = nil
        datesRemainingToday = nil
        compatibleOnline = 0
        queuePosition = nil
        lastError = nil
        permissionIssue = nil
        lastPartner = nil
        lastDateId = nil
    }

    // MARK: Server frames

    /// Applies one server frame. Frames for another `dateId` than the current one are ignored.
    func handle(_ message: ServerMessage) {
        switch message {
        case .queueStatus(let status):
            compatibleOnline = status.compatibleOnline
            queuePosition = status.position
        case .queueLimit(let limit):
            handleLimit(limit)
        case .dateMatched(let matched):
            handleMatched(matched)
        case .dateStarted(let started):
            handleStarted(started)
        case .rtcSignal(let signal):
            // The connection lives through the decision, so signaling does too.
            guard signal.dateId == currentDateId, isInDate else { return }
            video.handleRemoteSignal(signal.payload)
        case .icebreakerTurn(let turn):
            handleTurn(turn)
        case .dateCheckpoint(let message):
            handleCheckpoint(message)
        case .dateResumed(let message):
            handleResumed(message)
        case .dateEnded(let ended):
            handleEnded(ended)
        case .dateResult(let result):
            handleResult(result)
        case .moderationAction(let action):
            guard action.dateId == currentDateId else { return }
            applyModeration(action: action.action, category: action.category, message: action.message)
        case .accountSuspended(let info):
            session.markSuspended(info)
            // The server repeats this on every connect. Only take over the screen when the date
            // flow is open; otherwise `session.isSuspended` informs the Tonight tab.
            if phase != .idle {
                enterSuspended(reason: info.reason)
            }
        case .error(let serverError):
            handleServerError(serverError)
        case .chatMessage, .matchRemoved, .callInvite, .callAccept, .callDecline, .callEnd, .pong, .unknown:
            break
        }
    }

    private func handleServerError(_ serverError: ServerErrorMessage) {
        let error: TempoError = .server(status: 400, code: serverError.code, message: serverError.message)
        switch serverError.code {
        case "not_in_date", "not_your_turn", "already_in_date", "bad_message", "call_not_found",
             "busy", "partner_offline", "partner_busy", "match_not_found":
            // Races at the end of a date, or call errors that `MatchesStore` handles.
            break
        case "account_suspended":
            if phase != .idle {
                enterSuspended(reason: serverError.message)
            }
        case "in_call", "onboarding_incomplete", "underage":
            // The server refused `queue.join`.
            if phase == .searching {
                goOffline()
            }
            lastError = error
        default:
            if isActive {
                lastError = error
            }
        }
    }

    private func handleLimit(_ limit: QueueLimit) {
        guard phase == .searching else { return }
        video.stopLocalCapture()
        datesRemainingToday = 0
        phase = .limitReached(resetsAt: limit.resetsAt)
    }

    private func handleMatched(_ matched: DateMatched) {
        guard phase == .searching, !didSearchTimeOut else {
            // Not looking any more (went offline, gave up, or this is a duplicate): turn the pairing down.
            if matched.dateId != currentDateId {
                socket.send(.dateLeave(dateId: matched.dateId))
            }
            return
        }
        cancelDateTimers()
        cancelCountdown()
        searchTimeoutTask?.cancel()
        searchTimeoutTask = nil
        currentDateId = matched.dateId
        lastDateId = matched.dateId
        partner = matched.partner
        lastPartner = matched.partner
        startsAt = nil
        endsAt = nil
        icebreaker = nil
        moderationWarning = nil
        myDecision = nil
        clock = ServerClock()
        phase = .connecting(partner: matched.partner)

        let servers: [IceServer] = matched.iceServers.isEmpty ? config.iceServers : matched.iceServers
        let dateId: String = matched.dateId
        let role: CallRole = matched.role
        callSetupTask = Task { [weak self] in
            await self?.beginCall(dateId: dateId, role: role, iceServers: servers)
        }
        scheduleConnectTimeout(dateId: dateId)
    }

    private func beginCall(dateId: String, role: CallRole, iceServers: [IceServer]) async {
        video.onSignal = { [weak self] (payload: RTCSignalPayload) in
            self?.sendSignal(payload, dateId: dateId)
        }
        await video.startLocalCapture()
        guard currentDateId == dateId, isInCall else { return }
        await video.startCall(role: role, iceServers: iceServers)
        guard currentDateId == dateId, isInCall else { return }
        socket.send(.dateReady(dateId: dateId))
    }

    private func sendSignal(_ payload: RTCSignalPayload, dateId: String) {
        guard currentDateId == dateId, isInDate else { return }
        socket.send(.rtcSignal(dateId: dateId, payload: payload))
    }

    private func handleStarted(_ started: DateStarted) {
        guard started.dateId == currentDateId else {
            if currentDateId == nil && !isInDate {
                // Replayed after a reconnect for a date this app no longer knows (e.g. it was
                // restarted mid-date): release the partner.
                socket.send(.dateLeave(dateId: started.dateId))
            }
            return
        }
        switch phase {
        case .connecting:
            break
        case .live:
            // A repeat (e.g. after a reconnect): just refresh the clock.
            startsAt = clock.local(started.startsAt)
            endsAt = clock.local(started.endsAt)
            scheduleLiveOverrun(dateId: started.dateId, endsAt: clock.local(started.endsAt))
            return
        default:
            return
        }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        clock.observe(serverNow: started.startsAt, localNow: Date())
        startsAt = clock.local(started.startsAt)
        endsAt = clock.local(started.endsAt)
        phase = .live
        scheduleLiveOverrun(dateId: started.dateId, endsAt: clock.local(started.endsAt))

        // A date counts toward the daily cap when it starts.
        if var current = usage {
            current.datesToday += 1
            usage = current
            datesRemainingToday = current.remaining
        }

        let dateId: String = started.dateId
        video.onFrameSample = { [weak self] (data: Data) in
            self?.moderation.submitFrame(data)
        }
        video.startFrameSampling(interval: config.frameSampleInterval)
        let moderation: any ModerationService = self.moderation
        // The service drops a start that was overtaken by `stop()` or by a newer date.
        Task {
            await moderation.start(dateId: dateId)
        }
    }

    private func handleTurn(_ turn: IcebreakerTurn) {
        guard turn.dateId == currentDateId, phase == .live else { return }
        icebreaker = IcebreakerState(
            question: turn.question,
            questionIndex: turn.questionIndex,
            speakerId: turn.speakerId,
            turnEndsAt: clock.local(turn.turnEndsAt),
            turnDuration: turn.turnDurationSec,
            isMyTurn: turn.speakerId == session.userId
        )
    }

    /// The first question is done: pause the clock, silence the call and ask for a vote.
    private func handleCheckpoint(_ message: DateCheckpoint) {
        guard message.dateId == currentDateId, phase == .live else { return }
        liveOverrunTask?.cancel()
        liveOverrunTask = nil
        icebreaker = nil
        endsAt = nil
        video.setCallAudioSilenced(true)
        // A repeat after a reconnect keeps a vote already cast.
        checkpoint = CheckpointState(deadline: clock.local(message.deadline), myChoice: checkpoint?.myChoice)
    }

    /// Both chose to carry on: the date picks up with the time it had left.
    private func handleResumed(_ message: DateResumed) {
        guard message.dateId == currentDateId, phase == .live else { return }
        checkpoint = nil
        video.setCallAudioSilenced(false)
        endsAt = clock.local(message.endsAt)
        scheduleLiveOverrun(dateId: message.dateId, endsAt: clock.local(message.endsAt))
    }

    /// The user's private vote at the checkpoint. The first choice stands.
    func voteAtCheckpoint(_ choice: CheckpointChoice) {
        guard phase == .live, let dateId = currentDateId, var current = checkpoint, current.myChoice == nil else { return }
        current.myChoice = choice
        checkpoint = current
        socket.send(.dateContinue(dateId: dateId, choice: choice))
    }

    private func handleEnded(_ ended: DateEnded) {
        guard ended.dateId == currentDateId else { return }
        if ended.reason == .moderation {
            // Frames are still checked while the two decide, so a safety stop can arrive then too.
            guard isInDate else { return }
        } else {
            guard isInCall else { return }
        }
        // Whatever ended it, the vote (if one was open) is over.
        checkpoint = nil
        let endedPartner: Partner? = partner ?? lastPartner
        switch ended.reason {
        case .timer:
            guard let endedPartner else {
                finishCallMedia()
                phase = .ended(reason: .timer)
                beginInterstitial()
                return
            }
            // The date is over but the two stay connected, unheard, while they decide. Their
            // cameras are still on, so frames keep being checked; only audio and transcripts
            // stop. The connection closes with the result (or on leaving).
            quietCallMedia()
            if ended.matched == true {
                // Both stayed to the end: no vote. The match itself arrives in the next message.
                myDecision = .yes
                phase = .awaitingResult(partner: endedPartner)
                scheduleResultTimeout(dateId: ended.dateId, deadline: Date(), partner: endedPartner)
                return
            }
            var deadline: Date = Date().addingTimeInterval(config.decisionWindow)
            if let serverDeadline = ended.decisionDeadline {
                deadline = clock.local(serverDeadline)
            }
            myDecision = nil
            phase = .deciding(partner: endedPartner, deadline: deadline)
            scheduleDecisionDeadline(dateId: ended.dateId, deadline: deadline, partner: endedPartner)
        case .partnerLeft:
            finishCallMedia()
            if let endedPartner {
                phase = .partnerLeft(partner: endedPartner)
            } else {
                phase = .ended(reason: .partnerLeft)
            }
            beginInterstitial()
        case .youLeft:
            finishCallMedia()
            phase = .ended(reason: .youLeft)
            beginInterstitial()
        case .disconnect:
            finishCallMedia()
            phase = .ended(reason: .disconnect)
            beginInterstitial()
        case .checkpoint:
            finishCallMedia()
            phase = .ended(reason: .checkpoint)
            beginInterstitial()
        case .moderation:
            // May arrive during the decision; its timers must not fire after the stop.
            decisionTask?.cancel()
            decisionTask = nil
            resultTask?.cancel()
            resultTask = nil
            finishCallMedia()
            // No automatic re-queue after a safety stop; the user chooses what to do next.
            phase = .ended(reason: .moderation)
            releaseCameraWhileWaiting()
        }
    }

    private func handleResult(_ result: DateResult) {
        guard result.dateId == currentDateId else {
            // The flow was closed while the answer was sealed: the match still belongs in the list.
            if currentDateId == nil, result.dateId == lastDateId, result.outcome == .match, let match = result.match {
                onMatch?(match)
            }
            return
        }
        var resultPartner: Partner?
        switch phase {
        case .deciding(let decidingPartner, _):
            resultPartner = decidingPartner
        case .awaitingResult(let waitingPartner):
            resultPartner = waitingPartner
        default:
            return
        }
        decisionTask?.cancel()
        decisionTask = nil
        resultTask?.cancel()
        resultTask = nil
        guard let finalPartner = resultPartner else { return }
        // The video stayed up behind the Verdict; it ends with the result.
        finishCallMedia()

        switch result.outcome {
        case .match:
            let match: Match = result.match ?? Match(
                id: "pending-" + result.dateId,
                partner: finalPartner,
                matchedAt: Date(),
                lastMessage: nil,
                unreadCount: 0
            )
            nextCountdownEndsAt = nil
            phase = .matched(match: match)
            releaseCameraWhileWaiting()
            if result.match != nil {
                onMatch?(match)
            }
        case .noMatch:
            phase = .noMatch(partner: finalPartner)
            beginInterstitial()
        }
    }

    private func applyModeration(action: ModerationAction, category: ModerationCategory, message: String) {
        // All of `isInDate`: frames are checked until the video is torn down.
        guard isInDate else { return }
        let isFinal: Bool
        switch action {
        case .none:
            return
        case .warn:
            isFinal = false
        case .end:
            isFinal = true
        }
        if let existing = moderationWarning, existing.category == category {
            // The REST answer and the socket frame describe the same incident: show it once.
            let isRepeat: Bool = Date().timeIntervalSince(existing.issuedAt) < 3
            if isRepeat && (existing.isFinal || !isFinal) {
                return
            }
        }
        var text: String = message
        if text.isEmpty {
            text = DateStore.defaultModerationMessage(category: category, isFinal: isFinal)
        }
        moderationWarning = ModerationWarning(id: UUID(), category: category, message: text, isFinal: isFinal, issuedAt: Date())
    }

    private static func defaultModerationMessage(category: ModerationCategory, isFinal: Bool) -> String {
        switch category {
        case .nudity:
            return String(localized: "This date was ended because nudity isn't allowed on \(Brand.name).")
        case .sexualLanguage:
            if isFinal {
                return String(localized: "This date was ended because of sexual language.")
            }
            return String(localized: "Keep it respectful. Sexual language will end the date.")
        }
    }

    private func enterSuspended(reason: String) {
        onlineToken += 1
        cancelDateTimers()
        cancelCountdown()
        finishCallMedia()
        video.stopLocalCapture()
        clearDateState()
        willStopAfterThis = false
        isStartingUp = false
        let text: String = reason.isEmpty ? String(localized: "Your account is paused while we review a report.") : reason
        phase = .suspended(reason: text)
    }

    // MARK: Queue

    /// Stops a search that found nobody: leaves the queue and releases the camera, but keeps the
    /// search screen up so it can say so. `searchAgain()` or `goOffline()` follow.
    private func searchTimedOut() {
        searchTimeoutTask = nil
        guard phase == .searching, !didSearchTimeOut else { return }
        socket.send(.queueLeave)
        needsQueueJoin = false
        video.stopLocalCapture()
        didSearchTimeOut = true
    }

    /// Starts looking again after a search that found nobody.
    func searchAgain() {
        guard phase == .searching, didSearchTimeOut else { return }
        requeue()
    }

    private func requeue() {
        clearDateState()
        lastError = nil
        didSearchTimeOut = false
        searchTimeoutTask?.cancel()
        let limit: TimeInterval = timing.searchTimeout
        searchTimeoutTask = Task { [weak self] in
            guard await DateStore.wait(limit) else { return }
            self?.searchTimedOut()
        }
        phase = .searching
        if socket.state == .connected {
            needsQueueJoin = false
            socket.send(.queueJoin)
        } else {
            // `socketStateChanged` joins the queue as soon as the socket is up.
            needsQueueJoin = true
            socket.connect()
        }
        Task { [weak self] in
            // The search may already be over by the time this runs (went offline, daily limit):
            // never start the camera for a flow that no longer wants it.
            guard let self, self.wantsLocalCamera else { return }
            await self.video.startLocalCapture()
        }
    }

    /// True in the phases that show (or are about to show) the user's own camera.
    private var wantsLocalCamera: Bool {
        switch phase {
        case .searching, .connecting, .live, .deciding, .awaitingResult:
            return true
        case .idle, .limitReached, .matched, .noMatch, .partnerLeft, .ended, .suspended:
            return false
        }
    }

    private func clearDateState() {
        checkpoint = nil
        currentDateId = nil
        partner = nil
        startsAt = nil
        endsAt = nil
        icebreaker = nil
        moderationWarning = nil
        myDecision = nil
        queuePosition = nil
    }

    /// The date timer ended: silence the call in both directions and stop transcribing speech,
    /// but keep the peer connection and both videos up for the decision. The cameras are still
    /// on, so camera-frame sampling and frame moderation keep running; `finishCallMedia()` stops
    /// them when the video is torn down.
    private func quietCallMedia() {
        callSetupTask?.cancel()
        callSetupTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        videoFailureTask?.cancel()
        videoFailureTask = nil
        liveOverrunTask?.cancel()
        liveOverrunTask = nil
        moderation.stopTranscription()
        video.setCallAudioSilenced(true)
        icebreaker = nil
        startsAt = nil
        endsAt = nil
    }

    /// Stops everything tied to the call that just ended. The local camera keeps running for the next date.
    private func finishCallMedia() {
        callSetupTask?.cancel()
        callSetupTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        reconnectGraceTask?.cancel()
        reconnectGraceTask = nil
        videoFailureTask?.cancel()
        videoFailureTask = nil
        liveOverrunTask?.cancel()
        liveOverrunTask = nil
        video.stopFrameSampling()
        video.onFrameSample = nil
        moderation.stop()
        video.endCall()
        icebreaker = nil
        startsAt = nil
        endsAt = nil
    }

    // MARK: Timers (safety nets; the server stays authoritative)

    private func cancelDateTimers() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        decisionTask?.cancel()
        decisionTask = nil
        resultTask?.cancel()
        resultTask = nil
        reconnectGraceTask?.cancel()
        reconnectGraceTask = nil
        videoFailureTask?.cancel()
        videoFailureTask = nil
        liveOverrunTask?.cancel()
        liveOverrunTask = nil
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        nextCountdownEndsAt = nil
    }

    /// Sleeps for `seconds`; false when cancelled.
    private static func wait(_ seconds: TimeInterval) async -> Bool {
        let clamped: TimeInterval = max(0, seconds)
        do {
            try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    private func beginInterstitial() {
        countdownTask?.cancel()
        let duration: TimeInterval = timing.interstitial
        nextCountdownEndsAt = Date().addingTimeInterval(duration)
        countdownTask = Task { [weak self] in
            guard await DateStore.wait(duration) else { return }
            self?.interstitialFinished()
        }
    }

    private func interstitialFinished() {
        countdownTask = nil
        nextCountdownEndsAt = nil
        switch phase {
        case .noMatch, .partnerLeft, .ended:
            break
        default:
            return
        }
        if willStopAfterThis {
            goOffline()
        } else if session.isSuspended {
            enterSuspended(reason: session.suspension?.reason ?? "")
        } else {
            requeue()
        }
    }

    private func scheduleConnectTimeout(dateId: String) {
        connectTimeoutTask?.cancel()
        let duration: TimeInterval = timing.connectTimeout
        connectTimeoutTask = Task { [weak self] in
            guard await DateStore.wait(duration) else { return }
            self?.connectTimedOut(dateId: dateId)
        }
    }

    private func connectTimedOut(dateId: String) {
        connectTimeoutTask = nil
        guard currentDateId == dateId, case .connecting = phase else { return }
        // The date never started. Let this pairing go and look for the next person.
        socket.send(.dateLeave(dateId: dateId))
        finishCallMedia()
        if willStopAfterThis {
            goOffline()
        } else {
            requeue()
        }
    }

    /// Safety net for a live date whose `date.ended` never arrives (the server lost the date).
    /// The server stays authoritative: this only fires well after its own end time.
    private func scheduleLiveOverrun(dateId: String, endsAt liveEndsAt: Date) {
        liveOverrunTask?.cancel()
        let seconds: TimeInterval = max(0, liveEndsAt.timeIntervalSinceNow) + timing.liveOverrunGrace
        liveOverrunTask = Task { [weak self] in
            guard await DateStore.wait(seconds) else { return }
            self?.liveOverrunExpired(dateId: dateId)
        }
    }

    private func liveOverrunExpired(dateId: String) {
        liveOverrunTask = nil
        guard currentDateId == dateId, phase == .live else { return }
        // Time is long up and the server never said so. Release the partner and let the user choose.
        socket.send(.dateLeave(dateId: dateId))
        cancelDateTimers()
        finishCallMedia()
        phase = .ended(reason: .disconnect)
        nextCountdownEndsAt = nil
        releaseCameraWhileWaiting()
    }

    /// The flow is now waiting for the user with no video on screen (a match, a safety stop, a
    /// lost connection): turn the camera off. `requeue()` turns it back on.
    private func releaseCameraWhileWaiting() {
        let callOwnsCamera: Bool = isBlockedByCall?() ?? false
        if !callOwnsCamera {
            video.stopLocalCapture()
        }
    }

    private func scheduleDecisionDeadline(dateId: String, deadline: Date, partner decidingPartner: Partner) {
        decisionTask?.cancel()
        let seconds: TimeInterval = deadline.timeIntervalSinceNow
        decisionTask = Task { [weak self] in
            guard await DateStore.wait(seconds) else { return }
            self?.decisionDeadlinePassed(dateId: dateId, deadline: deadline, partner: decidingPartner)
        }
    }

    private func decisionDeadlinePassed(dateId: String, deadline: Date, partner decidingPartner: Partner) {
        decisionTask = nil
        guard currentDateId == dateId, case .deciding = phase else { return }
        // No answer counts as a No (the server applies it).
        myDecision = nil
        phase = .awaitingResult(partner: decidingPartner)
        scheduleResultTimeout(dateId: dateId, deadline: deadline, partner: decidingPartner)
    }

    private func scheduleResultTimeout(dateId: String, deadline: Date, partner waitingPartner: Partner) {
        resultTask?.cancel()
        let seconds: TimeInterval = max(0, deadline.timeIntervalSinceNow) + timing.resultGrace
        resultTask = Task { [weak self] in
            guard await DateStore.wait(seconds) else { return }
            self?.resultTimedOut(dateId: dateId, partner: waitingPartner)
        }
    }

    private func resultTimedOut(dateId: String, partner waitingPartner: Partner) {
        resultTask = nil
        guard currentDateId == dateId, case .awaitingResult = phase else { return }
        finishCallMedia()
        phase = .noMatch(partner: waitingPartner)
        beginInterstitial()
    }

    // MARK: Connection changes

    private func startListening() {
        let messages: AsyncStream<ServerMessage> = socket.messages()
        listenTask = Task { [weak self] in
            for await message in messages {
                guard let self else { return }
                self.handle(message)
            }
        }
        let states: AsyncStream<SocketConnectionState> = socket.states()
        socketStateTask = Task { [weak self] in
            for await state in states {
                guard let self else { return }
                self.socketStateChanged(state)
            }
        }
        let videoStates: AsyncStream<VideoConnectionState> = video.connectionStates()
        videoStateTask = Task { [weak self] in
            for await state in videoStates {
                guard let self else { return }
                self.videoStateChanged(state)
            }
        }
        moderation.onAction = { [weak self] (action: ModerationAction, category: ModerationCategory) in
            self?.applyModeration(action: action, category: category, message: "")
        }
    }

    /// Reacts to the socket going up or down. Internal so tests can drive it directly.
    func socketStateChanged(_ state: SocketConnectionState) {
        socketState = state
        switch state {
        case .connected:
            reconnectGraceTask?.cancel()
            reconnectGraceTask = nil
            if phase == .searching && needsQueueJoin {
                // The queue does not survive a new socket: join again.
                needsQueueJoin = false
                socket.send(.queueJoin)
            }
        case .reconnecting, .disconnected:
            if phase == .searching {
                needsQueueJoin = true
                if state == .disconnected && session.isSignedIn {
                    // The socket was closed for good (this account went online on another device).
                    goOffline()
                    lastError = .unknown(String(localized: "You went online on another device, so we stopped the search here."))
                    return
                }
            }
            if isInDate && reconnectGraceTask == nil {
                let duration: TimeInterval = timing.reconnectGrace
                let dateId: String? = currentDateId
                reconnectGraceTask = Task { [weak self] in
                    guard await DateStore.wait(duration) else { return }
                    self?.reconnectGraceExpired(dateId: dateId)
                }
            }
        case .connecting:
            break
        }
    }

    private func reconnectGraceExpired(dateId: String?) {
        reconnectGraceTask = nil
        guard currentDateId == dateId, isInDate, socket.state != .connected else { return }
        // The realtime connection is gone for good: the server has ended this date.
        cancelDateTimers()
        finishCallMedia()
        phase = .ended(reason: .disconnect)
        nextCountdownEndsAt = nil
        releaseCameraWhileWaiting()
    }

    private func videoStateChanged(_ state: VideoConnectionState) {
        guard isInCall else {
            videoState = isActive ? state : .idle
            return
        }
        videoState = state
        switch state {
        case .failed:
            guard videoFailureTask == nil else { return }
            let duration: TimeInterval = timing.videoFailureGrace
            let dateId: String? = currentDateId
            videoFailureTask = Task { [weak self] in
                guard await DateStore.wait(duration) else { return }
                self?.videoFailureGraceExpired(dateId: dateId)
            }
        case .connected:
            videoFailureTask?.cancel()
            videoFailureTask = nil
        case .idle, .connecting, .reconnecting, .closed:
            break
        }
    }

    private func videoFailureGraceExpired(dateId: String?) {
        videoFailureTask = nil
        guard currentDateId == dateId, isInCall, video.connectionState == .failed else { return }
        // Video could not be established or recovered. Release the partner and move on.
        if let dateId {
            socket.send(.dateLeave(dateId: dateId))
        }
        finishCallMedia()
        phase = .ended(reason: .disconnect)
        beginInterstitial()
    }

    private func fail(_ error: TempoError) {
        if error == .notAuthenticated {
            session.handle(error)
            return
        }
        if error != .cancelled {
            lastError = error
        }
    }
}
