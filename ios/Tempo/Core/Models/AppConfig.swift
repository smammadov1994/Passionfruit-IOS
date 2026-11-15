import Foundation

struct IceServer: Codable, Sendable, Equatable, Hashable {
    var urls: [String]
    var username: String?
    var credential: String?

    init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }

    enum CodingKeys: String, CodingKey {
        case urls, username, credential
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([String].self, forKey: .urls) {
            urls = list
        } else if let single = try? container.decode(String.self, forKey: .urls) {
            urls = [single]
        } else {
            urls = []
        }
        username = try? container.decodeIfPresent(String.self, forKey: .username)
        credential = try? container.decodeIfPresent(String.self, forKey: .credential)
    }
}

/// `GET /v1/config`. Every tunable the UI needs comes from here (via `ConfigStore`).
struct AppConfig: Codable, Sendable, Equatable {
    var dateDurationSec: Int
    var turnDurationSec: Int
    var decisionWindowSec: Int
    var freeDailyDates: Int
    var frameSampleIntervalSec: Double
    var iceServers: [IceServer]

    init(
        dateDurationSec: Int,
        turnDurationSec: Int,
        decisionWindowSec: Int,
        freeDailyDates: Int,
        frameSampleIntervalSec: Double,
        iceServers: [IceServer]
    ) {
        self.dateDurationSec = dateDurationSec
        self.turnDurationSec = turnDurationSec
        self.decisionWindowSec = decisionWindowSec
        self.freeDailyDates = freeDailyDates
        self.frameSampleIntervalSec = frameSampleIntervalSec
        self.iceServers = iceServers
    }

    /// Used only until the first successful `GET /v1/config` (values from SPEC section 1).
    static let fallback = AppConfig(
        dateDurationSec: 240,
        turnDurationSec: 30,
        decisionWindowSec: 20,
        freeDailyDates: 5,
        frameSampleIntervalSec: 3,
        iceServers: [IceServer(urls: ["stun:stun.l.google.com:19302"])]
    )
}

/// `GET /v1/usage`.
struct Usage: Codable, Sendable, Equatable {
    var datesToday: Int
    /// nil = unlimited (Premium).
    var limit: Int?
    var resetsAt: Date

    init(datesToday: Int, limit: Int?, resetsAt: Date) {
        self.datesToday = datesToday
        self.limit = limit
        self.resetsAt = resetsAt
    }

    /// nil = unlimited.
    var remaining: Int? {
        guard let limit else { return nil }
        return max(0, limit - datesToday)
    }
}

// MARK: - REST payloads

struct AuthResponse: Codable, Sendable, Equatable {
    var token: String
    var user: User
}

struct AppleAuthRequest: Codable, Sendable, Equatable {
    var identityToken: String
    var firstName: String?
}

struct DevAuthRequest: Codable, Sendable, Equatable {
    var deviceId: String
}

struct PhotoUploadRequest: Codable, Sendable, Equatable {
    var imageBase64: String
}

struct PhotoUploadResponse: Codable, Sendable, Equatable {
    var url: String
}

struct PushTokenRequest: Codable, Sendable, Equatable {
    var apnsToken: String
    var tzOffsetMinutes: Int
    var enabled: Bool
}

struct OnlineCountResponse: Codable, Sendable, Equatable {
    var compatibleOnline: Int
}

struct MatchesResponse: Codable, Sendable, Equatable {
    var matches: [Match]
}

struct MessagesResponse: Codable, Sendable, Equatable {
    var messages: [Message]
}

struct SendMessageRequest: Codable, Sendable, Equatable {
    var text: String
    var clientId: String
}

struct ReportRequest: Codable, Sendable, Equatable {
    var userId: String
    var dateId: String?
    var matchId: String?
    var reason: ReportReason
    var details: String?

    init(userId: String, dateId: String? = nil, matchId: String? = nil, reason: ReportReason, details: String? = nil) {
        self.userId = userId
        self.dateId = dateId
        self.matchId = matchId
        self.reason = reason
        self.details = details
    }
}

struct BlockRequest: Codable, Sendable, Equatable {
    var userId: String
}

struct ModerationFrameRequest: Codable, Sendable, Equatable {
    var dateId: String
    var imageBase64: String
}

struct ModerationTranscriptRequest: Codable, Sendable, Equatable {
    var dateId: String
    var text: String
}

struct ModerationResponse: Codable, Sendable, Equatable {
    var action: ModerationAction
}

struct VerifyPurchaseRequest: Codable, Sendable, Equatable {
    var jwsTransaction: String
}

/// Response of `POST /v1/iap/verify`.
struct PremiumStatus: Codable, Sendable, Equatable {
    var isPremium: Bool
    var premiumExpiresAt: Date?
}

struct HealthResponse: Codable, Sendable, Equatable {
    var ok: Bool
}

struct APIErrorEnvelope: Codable, Sendable, Equatable {
    struct Body: Codable, Sendable, Equatable {
        var code: String
        var message: String
    }
    var error: Body
}
