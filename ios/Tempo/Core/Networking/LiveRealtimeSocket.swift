import Foundation

@MainActor
final class LiveRealtimeSocket: RealtimeSocket {
    private(set) var state: SocketConnectionState = .disconnected

    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String?
    private let session: URLSession
    private let messageHub = Broadcaster<ServerMessage>()
    private let stateHub = Broadcaster<SocketConnectionState>()

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var generation: Int = 0
    private var wantsConnection: Bool = false
    private var attempt: Int = 0
    private var lastReceivedAt: Date = Date()

    private let pingInterval: TimeInterval = 20
    private let silenceTimeout: TimeInterval = 45
    private let maxBackoff: TimeInterval = 30

    init(baseURL: URL, tokenProvider: @escaping @Sendable () -> String?, session: URLSession = URLSession(configuration: .default)) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func connect() {
        wantsConnection = true
        if task == nil && reconnectTask == nil {
            open(isReconnect: false)
        }
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        closeCurrent()
        attempt = 0
        setState(.disconnected)
    }

    func send(_ message: ClientMessage) {
        guard let task else { return }
        guard let text = try? message.jsonString() else { return }
        task.send(URLSessionWebSocketTask.Message.string(text)) { _ in }
    }

    func messages() -> AsyncStream<ServerMessage> {
        messageHub.stream()
    }

    func states() -> AsyncStream<SocketConnectionState> {
        stateHub.stream()
    }

    // MARK: Connection lifecycle

    private func makeURL(token: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scheme: String = (components.scheme ?? "https").lowercased()
        components.scheme = (scheme == "http" || scheme == "ws") ? "ws" : "wss"
        var basePath: String = components.path
        if basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + "/v1/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func open(isReconnect: Bool) {
        guard wantsConnection else { return }
        guard let token = tokenProvider(), !token.isEmpty, let url = makeURL(token: token) else {
            setState(.disconnected)
            return
        }
        closeCurrent()
        generation += 1
        let currentGeneration: Int = generation
        setState(isReconnect ? .reconnecting : .connecting)

        let newTask = session.webSocketTask(with: url)
        task = newTask
        lastReceivedAt = Date()
        newTask.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: newTask, generation: currentGeneration)
        }
        pingTask = Task { [weak self] in
            await self?.pingLoop(generation: currentGeneration)
        }
        // The first frame back (the pong to this ping) marks the socket as connected.
        send(.ping)
    }

    private func closeCurrent() {
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        if let task {
            task.cancel(with: .goingAway, reason: nil)
        }
        task = nil
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation: Int) async {
        while !Task.isCancelled {
            do {
                let frame = try await task.receive()
                guard generation == self.generation else { return }
                switch frame {
                case .string(let text):
                    handleFrame(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleFrame(text: text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                let closeCode: Int = task.closeCode.rawValue
                // The server refuses a bad token with a plain HTTP 401 before the upgrade, so
                // there is no close code to read: look at the handshake response instead.
                let handshakeStatus: Int? = (task.response as? HTTPURLResponse)?.statusCode
                if LiveRealtimeSocket.isFinalCloseCode(closeCode) || LiveRealtimeSocket.isFinalHandshakeStatus(handshakeStatus) {
                    // Replaced by a newer connection, account deleted, or token refused:
                    // reconnecting would fight the other device or fail again.
                    closeCurrent()
                    wantsConnection = false
                    attempt = 0
                    setState(.disconnected)
                } else {
                    connectionLost()
                }
                return
            }
        }
    }

    private func handleFrame(text: String) {
        lastReceivedAt = Date()
        if state != .connected {
            attempt = 0
            setState(.connected)
        }
        guard let message = try? ServerMessage.decode(from: text) else {
            return
        }
        if case .pong = message {
            return
        }
        messageHub.yield(message)
    }

    private func pingLoop(generation: Int) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))
            } catch {
                return
            }
            guard generation == self.generation, !Task.isCancelled else { return }
            if Date().timeIntervalSince(lastReceivedAt) > silenceTimeout {
                connectionLost()
                return
            }
            send(.ping)
        }
    }

    private func connectionLost() {
        closeCurrent()
        guard wantsConnection else {
            setState(.disconnected)
            return
        }
        setState(.reconnecting)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay: TimeInterval = LiveRealtimeSocket.backoffDelay(attempt: attempt, maxDelay: maxBackoff)
        attempt += 1
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.open(isReconnect: true)
        }
    }

    /// Server close codes after which the client must not reconnect by itself:
    /// 4000 replaced by a newer connection, 4002 account deleted, 1008 unauthorized.
    /// (4001 idle, 4003 flood and 1001 shutting down reconnect with backoff.)
    nonisolated static func isFinalCloseCode(_ code: Int) -> Bool {
        code == 4000 || code == 4002 || code == 1008
    }

    /// HTTP answers to the WebSocket handshake after which reconnecting cannot help
    /// (401 token refused, 403 forbidden). nil = the handshake got no HTTP answer.
    nonisolated static func isFinalHandshakeStatus(_ status: Int?) -> Bool {
        status == 401 || status == 403
    }

    /// Exponential backoff with jitter: 1 s, 2 s, 4 s … capped at `maxDelay`, each scaled by 0.5–1.0.
    nonisolated static func backoffDelay(attempt: Int, maxDelay: TimeInterval) -> TimeInterval {
        let exponent: Double = Double(min(max(attempt, 0), 10))
        let ceiling: Double = min(maxDelay, pow(2.0, exponent))
        return ceiling * Double.random(in: 0.5...1.0)
    }

    private func setState(_ newState: SocketConnectionState) {
        guard state != newState else { return }
        state = newState
        stateHub.yield(newState)
    }
}
