import Foundation

enum SocketConnectionState: String, Sendable, Equatable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case reconnecting

    var displayName: String {
        switch self {
        case .disconnected: return String(localized: "Offline")
        case .connecting: return String(localized: "Connecting…")
        case .connected: return String(localized: "Connected")
        case .reconnecting: return String(localized: "Reconnecting…")
        }
    }
}

/// The realtime channel (`GET /v1/ws`). One per signed-in user.
@MainActor
protocol RealtimeSocket: AnyObject {
    var state: SocketConnectionState { get }
    /// Opens the socket and keeps it open (reconnecting as needed) until `disconnect()`.
    func connect()
    func disconnect()
    /// Sends a frame. Frames sent while the socket is down are dropped; stores re-sync on reconnect.
    func send(_ message: ClientMessage)
    /// A new stream of server frames. Every caller gets its own stream.
    func messages() -> AsyncStream<ServerMessage>
    /// A new stream of connection state changes. Every caller gets its own stream.
    func states() -> AsyncStream<SocketConnectionState>
}

/// Fans one source out to any number of `AsyncStream` consumers.
@MainActor
final class Broadcaster<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    init() {}

    deinit {
        // End every consumer's `for await` loop with the source, so their tasks do not wait forever.
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    func stream() -> AsyncStream<Element> {
        let id = UUID()
        let pair = AsyncStream<Element>.makeStream()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.remove(id)
            }
        }
        return pair.stream
    }

    func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
