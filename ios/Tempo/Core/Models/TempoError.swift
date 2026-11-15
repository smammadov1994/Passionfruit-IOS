import Foundation

enum PermissionKind: String, Sendable, Equatable, CaseIterable, Identifiable {
    case camera
    case microphone
    case speech
    case location
    case notifications

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera: return String(localized: "Camera")
        case .microphone: return String(localized: "Microphone")
        case .speech: return String(localized: "Speech recognition")
        case .location: return String(localized: "Location")
        case .notifications: return String(localized: "Notifications")
        }
    }
}

/// The single error type surfaced to UI. Always has a user-presentable `userMessage`.
enum TempoError: Error, Equatable, Sendable {
    /// No token, or the server rejected it (401).
    case notAuthenticated
    /// Offline, timeout, DNS, TLS: anything where the request never got an HTTP answer.
    case network
    /// HTTP error with the spec's `{error:{code,message}}` envelope (or a synthesized one).
    case server(status: Int, code: String, message: String)
    /// The response did not match the wire protocol.
    case decoding
    case suspended(until: Date?)
    case permissionDenied(PermissionKind)
    case purchaseFailed(String)
    case cancelled
    case unknown(String)

    var userMessage: String {
        switch self {
        case .notAuthenticated:
            return String(localized: "Please sign in again.")
        case .network:
            return String(localized: "Can't reach \(Brand.name). Check your connection and try again.")
        case .server(let status, _, let message):
            if status >= 500 {
                return String(localized: "Something went wrong on our side. Try again in a moment.")
            }
            if status == 429 {
                return String(localized: "Slow down a little. Try again in a moment.")
            }
            if message.isEmpty {
                return String(localized: "That didn't work. Try again.")
            }
            return message
        case .decoding:
            return String(localized: "We got an unexpected answer. Try again, or update \(Brand.name).")
        case .suspended:
            return String(localized: "Your account is paused while we review a report.")
        case .permissionDenied(let kind):
            switch kind {
            case .camera:
                return String(localized: "\(Brand.name) needs your camera for video dates. Turn it on in Settings.")
            case .microphone:
                return String(localized: "\(Brand.name) needs your microphone for video dates. Turn it on in Settings.")
            case .speech:
                return String(localized: "Speech recognition is off. You can turn it on in Settings.")
            case .location:
                return String(localized: "Location is off. Turn it on in Settings, or type your city.")
            case .notifications:
                return String(localized: "Notifications are off. Turn them on in Settings.")
            }
        case .purchaseFailed(let message):
            if message.isEmpty {
                return String(localized: "The purchase didn't go through. You haven't been charged.")
            }
            return message
        case .cancelled:
            return String(localized: "Cancelled.")
        case .unknown(let message):
            if message.isEmpty {
                return String(localized: "Something went wrong. Try again.")
            }
            return message
        }
    }

    /// Whether showing a "Try again" button makes sense.
    var isRetryable: Bool {
        switch self {
        case .network, .decoding, .unknown:
            return true
        case .server(let status, _, _):
            return status >= 500 || status == 429 || status == 408
        case .notAuthenticated, .suspended, .permissionDenied, .purchaseFailed, .cancelled:
            return false
        }
    }

    /// The server's machine-readable code, when there is one.
    var serverCode: String? {
        if case .server(_, let code, _) = self {
            return code
        }
        return nil
    }

    /// Maps anything thrown inside Core to a `TempoError`.
    static func from(_ error: Error) -> TempoError {
        if let tempo = error as? TempoError {
            return tempo
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .network
        }
        if error is DecodingError {
            return .decoding
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        return .unknown("")
    }
}

extension TempoError: LocalizedError {
    var errorDescription: String? { userMessage }
}
