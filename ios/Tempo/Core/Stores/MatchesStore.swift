import Foundation
import Observation

/// One row in a chat. `id` is stable from the optimistic send through server confirmation.
struct ChatMessage: Sendable, Equatable, Identifiable {
    enum Delivery: String, Sendable, Equatable {
        case sending
        case sent
        case failed
    }

    let id: String
    var message: Message
    var delivery: Delivery
    var isMine: Bool

    var text: String { message.text }
    var sentAt: Date { message.sentAt }
}

/// The loaded part of one conversation.
struct ChatThread: Sendable, Equatable {
    /// Oldest first.
    var messages: [ChatMessage] = []
    var isLoading: Bool = false
    var hasLoaded: Bool = false
    /// False once the oldest page has been fetched.
    var hasMoreHistory: Bool = true
    var loadError: TempoError?

    init() {}
}

enum CallEndReason: String, Sendable, Equatable {
    /// The other person hung up.
    case ended
    case declined
    case noAnswer
    case failed

    var displayName: String {
        switch self {
        case .ended: return String(localized: "Call ended")
        case .declined: return String(localized: "Not right now")
        case .noAnswer: return String(localized: "No answer")
        case .failed: return String(localized: "Couldn't connect")
        }
    }
}

/// Post-match video call ("video call again" from a chat).
enum CallState: Sendable, Equatable {
    case idle
    /// The user is ringing a match.
    case outgoing(matchId: String)
    /// A match is ringing the user.
    case incoming(matchId: String)
    /// Accepted; video is connecting.
    case connecting(matchId: String)
    case active(matchId: String)
    /// Finished without the user hanging up. Show briefly, then call `dismissCall()`.
    case ended(matchId: String, reason: CallEndReason)

    var matchId: String? {
        switch self {
        case .idle:
            return nil
        case .outgoing(let matchId), .incoming(let matchId), .connecting(let matchId), .active(let matchId):
            return matchId
        case .ended(let matchId, _):
            return matchId
        }
    }

    /// True while the call screen should be up.
    var isPresented: Bool {
        self != .idle
    }

    /// True while the camera is owned by a call.
    var isOngoing: Bool {
        switch self {
        case .outgoing, .connecting, .active:
            return true
        case .idle, .incoming, .ended:
            return false
        }
    }
}

/// Matches, chat and post-match video calls.
@MainActor
@Observable
final class MatchesStore {
    // MARK: Observable state

    /// Most recent activity first.
    private(set) var matches: [Match] = []
    private(set) var isLoading: Bool = false
    private(set) var hasLoaded: Bool = false
    /// The latest failure, user-presentable. Set to nil to dismiss.
    var lastError: TempoError?
    private(set) var threads: [String: ChatThread] = [:]
    /// The chat currently on screen (its incoming messages are marked read at once).
    private(set) var activeChatMatchId: String?

    private(set) var callState: CallState = .idle
    private(set) var isCallMicMuted: Bool = false
    private(set) var isCallCameraOff: Bool = false
    /// Set when camera or microphone access blocks a call. Offer `openSettings()`.
    private(set) var callPermissionIssue: PermissionIssue?

    // MARK: Dependencies

    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let socket: any RealtimeSocket
    @ObservationIgnored private let video: any VideoCallService
    @ObservationIgnored private let permissions: any MediaPermissions
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let moderation: (any ModerationService)?

    /// Returns true while a speed date owns the camera. Wired by `AppEnvironment`.
    @ObservationIgnored var isBlockedByDate: (@MainActor () -> Bool)?
    @ObservationIgnored var pageSize: Int = 50
    @ObservationIgnored var ringTimeout: TimeInterval = 30

    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var socketStateTask: Task<Void, Never>?
    @ObservationIgnored private var videoStateTask: Task<Void, Never>?
    @ObservationIgnored private var ringTask: Task<Void, Never>?
    /// True once the socket has been up in this session; the next `.connected` is a reconnect.
    @ObservationIgnored private var hasBeenConnected: Bool = false

    init(
        api: any APIClient,
        socket: any RealtimeSocket,
        video: any VideoCallService,
        permissions: any MediaPermissions,
        config: ConfigStore,
        session: SessionStore,
        moderation: (any ModerationService)? = nil
    ) {
        self.api = api
        self.socket = socket
        self.video = video
        self.permissions = permissions
        self.config = config
        self.session = session
        self.moderation = moderation
        startListening()
    }

    // MARK: Derived

    var totalUnread: Int {
        var total: Int = 0
        for match in matches {
            total += match.unreadCount
        }
        return total
    }

    func match(id: String) -> Match? {
        matches.first(where: { $0.id == id })
    }

    /// The loaded messages of a chat, oldest first.
    func messages(for matchId: String) -> [ChatMessage] {
        threads[matchId]?.messages ?? []
    }

    func thread(for matchId: String) -> ChatThread {
        threads[matchId] ?? ChatThread()
    }

    /// The person on the other end of the current call.
    var callPartner: Partner? {
        guard let matchId = callState.matchId else { return nil }
        return match(id: matchId)?.partner
    }

    // MARK: Matches

    /// Loads the matches list (`GET /v1/matches`). Safe to call from `.task` and pull-to-refresh.
    func load() async {
        guard session.isSignedIn, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [Match] = try await api.fetchMatches()
            matches = MatchesStore.sorted(fetched)
            hasLoaded = true
        } catch {
            fail(TempoError.from(error))
        }
    }

    /// Adds a match made in a date. Called by `DateStore` through `AppEnvironment`.
    func insert(_ match: Match) {
        if let index = matches.firstIndex(where: { $0.id == match.id }) {
            matches[index] = match
        } else {
            matches.append(match)
        }
        matches = MatchesStore.sorted(matches)
    }

    /// Unmatches (`DELETE /v1/matches/:id`). Returns true on success.
    @discardableResult
    func unmatch(matchId: String) async -> Bool {
        do {
            try await api.unmatch(matchId: matchId)
            removeLocally(matchId: matchId)
            return true
        } catch {
            fail(TempoError.from(error))
            return false
        }
    }

    /// Reports the person in a match. Returns true when the report was sent.
    @discardableResult
    func report(matchId: String, reason: ReportReason, details: String?) async -> Bool {
        guard let target = match(id: matchId) else { return false }
        let request = ReportRequest(userId: target.partner.id, dateId: nil, matchId: matchId, reason: reason, details: details)
        do {
            try await api.report(request)
            return true
        } catch {
            fail(TempoError.from(error))
            return false
        }
    }

    /// Blocks the person in a match and removes the match. Returns true on success.
    @discardableResult
    func block(matchId: String) async -> Bool {
        guard let target = match(id: matchId) else { return false }
        do {
            try await api.block(userId: target.partner.id)
            removeLocally(matchId: matchId)
            return true
        } catch {
            fail(TempoError.from(error))
            return false
        }
    }

    private func removeLocally(matchId: String) {
        matches.removeAll(where: { $0.id == matchId })
        threads[matchId] = nil
        if activeChatMatchId == matchId {
            activeChatMatchId = nil
        }
        if callState.matchId == matchId {
            if callState.isOngoing {
                socket.send(.callEnd(matchId: matchId))
            }
            tearDownCall()
            callState = .idle
        }
    }

    private static func sorted(_ list: [Match]) -> [Match] {
        list.sorted(by: { $0.lastActivityAt > $1.lastActivityAt })
    }

    // MARK: Chat

    /// Call when a chat appears: loads the newest page and marks the chat read. The page is
    /// fetched on every open: messages that came in while the realtime connection was down
    /// (the app in the background, a push) are not in the thread kept in memory.
    func openChat(matchId: String) async {
        activeChatMatchId = matchId
        await loadMessages(matchId: matchId)
        await markRead(matchId: matchId)
    }

    /// Catches up after a gap in the realtime connection (a reconnect, or the app coming back to
    /// the foreground): the matches list, and the chat on screen if there is one.
    func resync() async {
        guard session.isSignedIn else { return }
        await load()
        if let matchId = activeChatMatchId {
            await loadMessages(matchId: matchId)
            await markRead(matchId: matchId)
        }
    }

    /// Reacts to the socket coming up. Internal so tests can drive it directly.
    func socketStateChanged(_ state: SocketConnectionState) {
        guard state == .connected else { return }
        if hasBeenConnected {
            // Frames sent while the socket was down were dropped by the server.
            Task { [weak self] in
                await self?.resync()
            }
        }
        hasBeenConnected = true
    }

    /// Call when a chat disappears.
    func closeChat(matchId: String) {
        if activeChatMatchId == matchId {
            activeChatMatchId = nil
        }
        trimThread(matchId: matchId)
    }

    /// Keeps a closed chat from holding its whole history in memory: only the newest page (and
    /// anything not delivered yet) stays; earlier pages are fetched again when the user scrolls up.
    private func trimThread(matchId: String) {
        guard var thread = threads[matchId], thread.hasLoaded, !thread.isLoading else { return }
        let limit: Int = max(1, pageSize)
        let sent: [ChatMessage] = thread.messages.filter { $0.delivery == .sent }
        guard sent.count > limit else { return }
        let unsent: [ChatMessage] = thread.messages.filter { $0.delivery != .sent }
        thread.messages = MatchesStore.ordered(Array(sent.suffix(limit)) + unsent)
        thread.hasMoreHistory = true
        threads[matchId] = thread
    }

    /// Loads (or reloads) the newest page of a chat.
    func loadMessages(matchId: String) async {
        var thread: ChatThread = self.thread(for: matchId)
        guard !thread.isLoading else { return }
        thread.isLoading = true
        thread.loadError = nil
        threads[matchId] = thread
        do {
            let page: [Message] = try await api.fetchMessages(matchId: matchId, before: nil, limit: pageSize)
            var updated: ChatThread = self.thread(for: matchId)
            // Keep messages that are still sending or failed; they are not on the server yet.
            let unsent: [ChatMessage] = updated.messages.filter { $0.delivery != .sent }
            var rows: [ChatMessage] = page.map { makeRow($0, delivery: .sent) }
            for row in unsent where !rows.contains(where: { $0.id == row.id }) {
                rows.append(row)
            }
            updated.messages = MatchesStore.ordered(rows)
            updated.isLoading = false
            updated.hasLoaded = true
            updated.hasMoreHistory = page.count >= pageSize
            threads[matchId] = updated
        } catch {
            var failed: ChatThread = self.thread(for: matchId)
            failed.isLoading = false
            let mapped: TempoError = TempoError.from(error)
            failed.loadError = mapped
            threads[matchId] = failed
            if mapped == .notAuthenticated {
                session.handle(mapped)
            }
        }
    }

    /// Loads the page before the oldest loaded message.
    func loadEarlier(matchId: String) async {
        var thread: ChatThread = self.thread(for: matchId)
        guard thread.hasLoaded, thread.hasMoreHistory, !thread.isLoading else { return }
        guard let oldest = thread.messages.first(where: { $0.delivery == .sent }) else { return }
        thread.isLoading = true
        threads[matchId] = thread
        do {
            let page: [Message] = try await api.fetchMessages(matchId: matchId, before: oldest.message.sentAt, limit: pageSize)
            var updated: ChatThread = self.thread(for: matchId)
            var rows: [ChatMessage] = updated.messages
            for message in page where !rows.contains(where: { $0.message.id == message.id }) {
                rows.append(makeRow(message, delivery: .sent))
            }
            updated.messages = MatchesStore.ordered(rows)
            updated.isLoading = false
            updated.hasMoreHistory = page.count >= pageSize
            threads[matchId] = updated
        } catch {
            var failed: ChatThread = self.thread(for: matchId)
            failed.isLoading = false
            threads[matchId] = failed
            fail(TempoError.from(error))
        }
    }

    /// Sends a message. It appears at once as `.sending`, then becomes `.sent` or `.failed`.
    func send(text: String, to matchId: String) async {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let me = session.userId else { return }
        let clientId: String = UUID().uuidString.lowercased()
        let optimistic = Message(id: "local-" + clientId, matchId: matchId, senderId: me, text: trimmed, sentAt: Date(), clientId: clientId)
        var thread: ChatThread = self.thread(for: matchId)
        thread.messages.append(ChatMessage(id: clientId, message: optimistic, delivery: .sending, isMine: true))
        threads[matchId] = thread
        updateLastMessage(optimistic)
        await deliver(clientId: clientId, matchId: matchId, text: trimmed)
    }

    /// Tries a `.failed` message again.
    func retry(messageId: String, in matchId: String) async {
        var thread: ChatThread = self.thread(for: matchId)
        guard let index = thread.messages.firstIndex(where: { $0.id == messageId && $0.delivery == .failed }) else { return }
        thread.messages[index].delivery = .sending
        let text: String = thread.messages[index].message.text
        threads[matchId] = thread
        await deliver(clientId: messageId, matchId: matchId, text: text)
    }

    /// Removes a `.failed` message the user gave up on.
    func discardFailed(messageId: String, in matchId: String) {
        var thread: ChatThread = self.thread(for: matchId)
        thread.messages.removeAll(where: { $0.id == messageId && $0.delivery == .failed })
        threads[matchId] = thread
    }

    private func deliver(clientId: String, matchId: String, text: String) async {
        do {
            let confirmed: Message = try await api.sendMessage(matchId: matchId, text: text, clientId: clientId)
            var thread: ChatThread = self.thread(for: matchId)
            // The socket echo may have arrived first under the server id: drop that copy.
            thread.messages.removeAll(where: { $0.id != clientId && $0.message.id == confirmed.id })
            if let index = thread.messages.firstIndex(where: { $0.id == clientId }) {
                thread.messages[index].message = confirmed
                thread.messages[index].delivery = .sent
            } else {
                thread.messages.append(ChatMessage(id: clientId, message: confirmed, delivery: .sent, isMine: true))
            }
            thread.messages = MatchesStore.ordered(thread.messages)
            threads[matchId] = thread
            updateLastMessage(confirmed)
        } catch {
            var thread: ChatThread = self.thread(for: matchId)
            if let index = thread.messages.firstIndex(where: { $0.id == clientId }) {
                thread.messages[index].delivery = .failed
            }
            threads[matchId] = thread
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                session.handle(mapped)
            }
        }
    }

    /// Marks a chat read (`POST /v1/matches/:id/read`).
    func markRead(matchId: String) async {
        guard let index = matches.firstIndex(where: { $0.id == matchId }) else { return }
        guard matches[index].unreadCount > 0 else { return }
        matches[index].unreadCount = 0
        do {
            try await api.markRead(matchId: matchId)
        } catch {
            // The badge stays cleared locally; the next load corrects it if the call failed.
        }
    }

    private func makeRow(_ message: Message, delivery: ChatMessage.Delivery) -> ChatMessage {
        ChatMessage(id: message.id, message: message, delivery: delivery, isMine: message.senderId == session.userId)
    }

    private static func ordered(_ rows: [ChatMessage]) -> [ChatMessage] {
        rows.sorted(by: { $0.message.sentAt < $1.message.sentAt })
    }

    private func updateLastMessage(_ message: Message) {
        guard let index = matches.firstIndex(where: { $0.id == message.matchId }) else { return }
        matches[index].lastMessage = message
        matches = MatchesStore.sorted(matches)
    }

    private func receive(_ message: Message) {
        let matchId: String = message.matchId
        let isMine: Bool = message.senderId == session.userId
        var thread: ChatThread = self.thread(for: matchId)

        // A chat that was never opened keeps no rows: opening it loads the newest page anyway.
        let keepsRows: Bool = thread.hasLoaded || !thread.messages.isEmpty
        let sameServerId: Int? = thread.messages.firstIndex(where: { $0.message.id == message.id })
        var sameClientId: Int?
        if let clientId = message.clientId {
            sameClientId = thread.messages.firstIndex(where: { $0.id == clientId || $0.message.clientId == clientId })
        }
        if let index = sameServerId ?? sameClientId {
            // Already shown (own optimistic row or a duplicate frame): refresh it in place.
            thread.messages[index].message = message
            thread.messages[index].delivery = .sent
        } else {
            thread.messages.append(ChatMessage(id: message.id, message: message, delivery: .sent, isMine: isMine))
            thread.messages = MatchesStore.ordered(thread.messages)
        }
        if keepsRows {
            threads[matchId] = thread
        }

        guard let index = matches.firstIndex(where: { $0.id == matchId }) else {
            // A match this device has not seen yet.
            Task { [weak self] in
                await self?.load()
            }
            return
        }
        let isNew: Bool = (sameServerId == nil && sameClientId == nil)
        matches[index].lastMessage = message
        if isNew && !isMine {
            if activeChatMatchId == matchId {
                Task { [weak self] in
                    guard let self else { return }
                    _ = try? await self.api.markRead(matchId: matchId)
                }
            } else {
                matches[index].unreadCount += 1
            }
        }
        matches = MatchesStore.sorted(matches)
    }

    // MARK: Video call

    /// Rings a match. Asks for camera and microphone access if needed.
    func startCall(matchId: String) async {
        switch callState {
        case .idle, .ended:
            break
        case .outgoing, .incoming, .connecting, .active:
            return
        }
        guard match(id: matchId) != nil else { return }
        if let blocked = isBlockedByDate, blocked() {
            lastError = .unknown(String(localized: "Finish your date first."))
            return
        }
        callPermissionIssue = nil
        if let issue = await permissions.requestCameraAndMicrophone() {
            callPermissionIssue = issue
            return
        }
        resetCallControls()
        callState = .outgoing(matchId: matchId)
        socket.send(.callInvite(matchId: matchId))
        scheduleRingTimeout(matchId: matchId, outgoing: true)
        await video.startLocalCapture()
    }

    /// Accepts the incoming call.
    func acceptCall() async {
        guard case .incoming(let matchId) = callState else { return }
        callPermissionIssue = nil
        if let issue = await permissions.requestCameraAndMicrophone() {
            callPermissionIssue = issue
            guard case .incoming(let stillRinging) = callState, stillRinging == matchId else { return }
            socket.send(.callDecline(matchId: matchId))
            cancelRing()
            callState = .idle
            return
        }
        guard case .incoming(let stillRinging) = callState, stillRinging == matchId else { return }
        cancelRing()
        resetCallControls()
        socket.send(.callAccept(matchId: matchId))
        await beginCallMedia(matchId: matchId, role: .callee)
    }

    /// Declines the incoming call.
    func declineCall() {
        guard case .incoming(let matchId) = callState else { return }
        socket.send(.callDecline(matchId: matchId))
        cancelRing()
        callState = .idle
    }

    /// Hangs up (or cancels an outgoing ring).
    func endCall() {
        switch callState {
        case .outgoing(let matchId), .connecting(let matchId), .active(let matchId):
            socket.send(.callEnd(matchId: matchId))
            tearDownCall()
            callState = .idle
        case .incoming:
            declineCall()
        case .ended:
            callState = .idle
        case .idle:
            break
        }
    }

    /// Clears `.ended` after it has been shown.
    func dismissCall() {
        if case .ended = callState {
            callState = .idle
        }
    }

    func toggleCallMic() {
        isCallMicMuted.toggle()
        video.setMicMuted(isCallMicMuted)
    }

    func toggleCallCamera() {
        isCallCameraOff.toggle()
        video.setCameraOff(isCallCameraOff)
    }

    func flipCallCamera() {
        let video: any VideoCallService = self.video
        Task {
            await video.flipCamera()
        }
    }

    func dismissCallPermissionIssue() {
        callPermissionIssue = nil
    }

    /// Opens this app's page in Settings (for `callPermissionIssue`).
    func openSettings() {
        SystemSettings.open()
    }

    private func resetCallControls() {
        isCallMicMuted = false
        isCallCameraOff = false
        video.setMicMuted(false)
        video.setCameraOff(false)
    }

    private func beginCallMedia(matchId: String, role: CallRole) async {
        callState = .connecting(matchId: matchId)
        let signalId: String = CallSignalID.dateId(forMatch: matchId)
        video.onSignal = { [weak self] (payload: RTCSignalPayload) in
            self?.sendCallSignal(payload, matchId: matchId, signalId: signalId)
        }
        await video.startLocalCapture()
        // TURN credentials are per user and short-lived: refresh them for this call.
        await config.load()
        guard case .connecting(let current) = callState, current == matchId else { return }
        await video.startCall(role: role, iceServers: config.iceServers)
    }

    /// Calls are moderated like dates, with `dateId = "call:" + matchId`.
    private func startCallModeration(matchId: String) {
        guard let moderation else { return }
        let signalId: String = CallSignalID.dateId(forMatch: matchId)
        video.onFrameSample = { [weak moderation] (data: Data) in
            moderation?.submitFrame(data)
        }
        video.startFrameSampling(interval: config.frameSampleInterval)
        Task {
            await moderation.start(dateId: signalId)
        }
    }

    private func sendCallSignal(_ payload: RTCSignalPayload, matchId: String, signalId: String) {
        guard callState.matchId == matchId, callState.isOngoing else { return }
        socket.send(.rtcSignal(dateId: signalId, payload: payload))
    }

    private func tearDownCall() {
        cancelRing()
        let dateOwnsCamera: Bool = isBlockedByDate?() ?? false
        if dateOwnsCamera {
            // A speed date owns the camera, the peer connection and moderation: leave them alone.
            return
        }
        video.stopFrameSampling()
        video.onFrameSample = nil
        moderation?.stop()
        video.endCall()
        video.stopLocalCapture()
    }

    private func finishCall(matchId: String, reason: CallEndReason) {
        tearDownCall()
        callState = .ended(matchId: matchId, reason: reason)
    }

    private func cancelRing() {
        ringTask?.cancel()
        ringTask = nil
    }

    private func scheduleRingTimeout(matchId: String, outgoing: Bool) {
        ringTask?.cancel()
        let duration: TimeInterval = ringTimeout
        ringTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.ringTimedOut(matchId: matchId, outgoing: outgoing)
        }
    }

    private func ringTimedOut(matchId: String, outgoing: Bool) {
        ringTask = nil
        if outgoing {
            guard case .outgoing(let current) = callState, current == matchId else { return }
            socket.send(.callEnd(matchId: matchId))
            finishCall(matchId: matchId, reason: .noAnswer)
        } else {
            guard case .incoming(let current) = callState, current == matchId else { return }
            callState = .idle
        }
    }

    // MARK: Server frames

    /// Applies one server frame. Internal so tests can drive it directly.
    func handle(_ message: ServerMessage) {
        switch message {
        case .chatMessage(let chat):
            receive(chat)
        case .matchRemoved(let matchId):
            removeLocally(matchId: matchId)
        case .callInvite(let signal):
            handleInvite(signal)
        case .callAccept(let signal):
            guard case .outgoing(let matchId) = callState, matchId == signal.matchId else { return }
            cancelRing()
            Task { [weak self] in
                await self?.beginCallMedia(matchId: matchId, role: .caller)
            }
        case .callDecline(let signal):
            guard case .outgoing(let matchId) = callState, matchId == signal.matchId else { return }
            finishCall(matchId: matchId, reason: .declined)
        case .callEnd(let signal):
            handleRemoteEnd(signal)
        case .rtcSignal(let signal):
            guard let matchId = CallSignalID.matchId(fromDateId: signal.dateId) else { return }
            guard callState.matchId == matchId else { return }
            switch callState {
            case .connecting, .active:
                video.handleRemoteSignal(signal.payload)
            case .idle, .outgoing, .incoming, .ended:
                break
            }
        case .error(let serverError):
            handleCallError(serverError)
        case .moderationAction(let action):
            guard let matchId = CallSignalID.matchId(fromDateId: action.dateId), callState.matchId == matchId else { return }
            if action.action == .end {
                lastError = .unknown(action.message)
            }
        case .queueStatus, .queueLimit, .dateMatched, .dateStarted, .icebreakerTurn, .dateCheckpoint, .dateResumed,
             .dateEnded, .dateResult,
             .accountSuspended, .pong, .unknown:
            break
        }
    }

    /// Socket errors the server sends in answer to `call.invite`.
    private func handleCallError(_ serverError: ServerErrorMessage) {
        guard case .outgoing(let matchId) = callState else { return }
        switch serverError.code {
        case "partner_offline":
            finishCall(matchId: matchId, reason: .noAnswer)
        case "partner_busy":
            finishCall(matchId: matchId, reason: .declined)
        case "busy", "match_not_found", "account_suspended":
            finishCall(matchId: matchId, reason: .failed)
        default:
            return
        }
        lastError = .server(status: 400, code: serverError.code, message: serverError.message)
    }

    private func handleInvite(_ signal: CallSignal) {
        let dateOwnsCamera: Bool = isBlockedByDate?() ?? false
        var isFree: Bool = false
        switch callState {
        case .idle, .ended:
            isFree = true
        case .outgoing, .incoming, .connecting, .active:
            isFree = false
        }
        guard isFree, !dateOwnsCamera, match(id: signal.matchId) != nil else {
            if callState.matchId != signal.matchId {
                socket.send(.callDecline(matchId: signal.matchId))
            }
            return
        }
        callState = .incoming(matchId: signal.matchId)
        scheduleRingTimeout(matchId: signal.matchId, outgoing: false)
    }

    private func handleRemoteEnd(_ signal: CallSignal) {
        guard callState.matchId == signal.matchId else { return }
        switch callState {
        case .incoming:
            cancelRing()
            callState = .idle
        case .outgoing(let matchId):
            // A refusal arrives as `call.decline`; `call.end` while ringing is the server's
            // 45 s timeout or the other person going offline.
            finishCall(matchId: matchId, reason: .noAnswer)
        case .connecting(let matchId), .active(let matchId):
            finishCall(matchId: matchId, reason: .ended)
        case .idle, .ended:
            break
        }
    }

    private func videoStateChanged(_ state: VideoConnectionState) {
        switch callState {
        case .connecting(let matchId):
            if state == .connected {
                callState = .active(matchId: matchId)
                startCallModeration(matchId: matchId)
            } else if state == .failed {
                socket.send(.callEnd(matchId: matchId))
                finishCall(matchId: matchId, reason: .failed)
            }
        case .active(let matchId):
            if state == .failed {
                socket.send(.callEnd(matchId: matchId))
                finishCall(matchId: matchId, reason: .failed)
            }
        case .idle, .outgoing, .incoming, .ended:
            break
        }
    }

    private func startListening() {
        let messages: AsyncStream<ServerMessage> = socket.messages()
        listenTask = Task { [weak self] in
            for await message in messages {
                guard let self else { return }
                self.handle(message)
            }
        }
        let socketStates: AsyncStream<SocketConnectionState> = socket.states()
        socketStateTask = Task { [weak self] in
            for await state in socketStates {
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
    }

    /// Puts the call straight into a state. For SwiftUI previews only; never call it from app code.
    func debugSetCallState(_ newState: CallState) {
        cancelRing()
        callState = newState
    }

    // MARK: Housekeeping

    /// Clears everything (sign-out).
    func reset() {
        if let matchId = callState.matchId, callState.isOngoing {
            socket.send(.callEnd(matchId: matchId))
        }
        tearDownCall()
        callState = .idle
        matches = []
        threads = [:]
        hasLoaded = false
        activeChatMatchId = nil
        lastError = nil
        callPermissionIssue = nil
        hasBeenConnected = false
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
