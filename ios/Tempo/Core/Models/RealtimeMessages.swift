import Foundation

/// `payload` of `rtc.signal`, relayed verbatim between the two peers.
struct RTCSignalPayload: Codable, Sendable, Equatable {
    var kind: RTCSignalKind
    var sdp: String?
    var candidate: String?
    var sdpMid: String?
    var sdpMLineIndex: Int?

    init(kind: RTCSignalKind, sdp: String? = nil, candidate: String? = nil, sdpMid: String? = nil, sdpMLineIndex: Int? = nil) {
        self.kind = kind
        self.sdp = sdp
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }

    static func offer(sdp: String) -> RTCSignalPayload {
        RTCSignalPayload(kind: .offer, sdp: sdp)
    }

    static func answer(sdp: String) -> RTCSignalPayload {
        RTCSignalPayload(kind: .answer, sdp: sdp)
    }

    static func ice(candidate: String, sdpMid: String?, sdpMLineIndex: Int) -> RTCSignalPayload {
        RTCSignalPayload(kind: .ice, candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
    }
}

/// Post-match video calls reuse `rtc.signal` with `dateId = "call:" + matchId`.
enum CallSignalID {
    static let prefix: String = "call:"

    static func dateId(forMatch matchId: String) -> String {
        prefix + matchId
    }

    static func matchId(fromDateId dateId: String) -> String? {
        guard dateId.hasPrefix(prefix) else { return nil }
        return String(dateId.dropFirst(prefix.count))
    }
}

// MARK: - Client → Server

enum ClientMessage: Sendable, Equatable, Encodable {
    case queueJoin
    case queueLeave
    case dateReady(dateId: String)
    case rtcSignal(dateId: String, payload: RTCSignalPayload)
    case turnPass(dateId: String)
    case dateLeave(dateId: String)
    case dateDecide(dateId: String, decision: DateDecision)
    case dateContinue(dateId: String, choice: CheckpointChoice)
    case callInvite(matchId: String)
    case callAccept(matchId: String)
    case callDecline(matchId: String)
    case callEnd(matchId: String)
    case ping

    var type: String {
        switch self {
        case .queueJoin: return "queue.join"
        case .queueLeave: return "queue.leave"
        case .dateReady: return "date.ready"
        case .rtcSignal: return "rtc.signal"
        case .turnPass: return "turn.pass"
        case .dateLeave: return "date.leave"
        case .dateDecide: return "date.decide"
        case .dateContinue: return "date.continue"
        case .callInvite: return "call.invite"
        case .callAccept: return "call.accept"
        case .callDecline: return "call.decline"
        case .callEnd: return "call.end"
        case .ping: return "ping"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, dateId, payload, decision, matchId, choice
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .queueJoin, .queueLeave, .ping:
            break
        case .dateReady(let dateId):
            try container.encode(dateId, forKey: .dateId)
        case .rtcSignal(let dateId, let payload):
            try container.encode(dateId, forKey: .dateId)
            try container.encode(payload, forKey: .payload)
        case .turnPass(let dateId):
            try container.encode(dateId, forKey: .dateId)
        case .dateLeave(let dateId):
            try container.encode(dateId, forKey: .dateId)
        case .dateDecide(let dateId, let decision):
            try container.encode(dateId, forKey: .dateId)
            try container.encode(decision, forKey: .decision)
        case .dateContinue(let dateId, let choice):
            try container.encode(dateId, forKey: .dateId)
            try container.encode(choice, forKey: .choice)
        case .callInvite(let matchId):
            try container.encode(matchId, forKey: .matchId)
        case .callAccept(let matchId):
            try container.encode(matchId, forKey: .matchId)
        case .callDecline(let matchId):
            try container.encode(matchId, forKey: .matchId)
        case .callEnd(let matchId):
            try container.encode(matchId, forKey: .matchId)
        }
    }

    /// The JSON text frame for this message.
    func jsonString() throws -> String {
        let data = try TempoJSON.makeEncoder().encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TempoError.decoding
        }
        return text
    }
}

// MARK: - Server → Client payloads

struct QueueStatus: Codable, Sendable, Equatable {
    var compatibleOnline: Int
    var position: Int

    init(compatibleOnline: Int, position: Int) {
        self.compatibleOnline = compatibleOnline
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case compatibleOnline, position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compatibleOnline = (try? container.decodeIfPresent(Int.self, forKey: .compatibleOnline)) ?? 0
        position = (try? container.decodeIfPresent(Int.self, forKey: .position)) ?? 0
    }
}

struct QueueLimit: Codable, Sendable, Equatable {
    var limit: Int
    var resetsAt: Date
}

struct DateMatched: Codable, Sendable, Equatable {
    var dateId: String
    var partner: Partner
    var role: CallRole
    var iceServers: [IceServer]

    init(dateId: String, partner: Partner, role: CallRole, iceServers: [IceServer]) {
        self.dateId = dateId
        self.partner = partner
        self.role = role
        self.iceServers = iceServers
    }

    enum CodingKeys: String, CodingKey {
        case dateId, partner, role, iceServers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateId = try container.decode(String.self, forKey: .dateId)
        partner = try container.decode(Partner.self, forKey: .partner)
        role = try container.decode(CallRole.self, forKey: .role)
        iceServers = (try? container.decodeIfPresent([IceServer].self, forKey: .iceServers)) ?? []
    }
}

struct DateStarted: Codable, Sendable, Equatable {
    var dateId: String
    var startsAt: Date
    var endsAt: Date
}

struct RTCSignal: Codable, Sendable, Equatable {
    var dateId: String
    var payload: RTCSignalPayload
}

struct IcebreakerTurn: Codable, Sendable, Equatable {
    var dateId: String
    var question: String
    var questionIndex: Int
    var speakerId: String
    var turnEndsAt: Date
    var turnDurationSec: Double
}

/// After the first question the date pauses and both vote privately until `deadline`.
struct DateCheckpoint: Codable, Sendable, Equatable {
    var dateId: String
    var deadline: Date
}

/// Both voted to carry on. The clock was paused; `endsAt` is the new end.
struct DateResumed: Codable, Sendable, Equatable {
    var dateId: String
    var endsAt: Date
}

struct DateEnded: Codable, Sendable, Equatable {
    var dateId: String
    var reason: DateEndReason
    /// Present only when `reason == .timer`.
    var decisionDeadline: Date?

    init(dateId: String, reason: DateEndReason, decisionDeadline: Date? = nil) {
        self.dateId = dateId
        self.reason = reason
        self.decisionDeadline = decisionDeadline
    }
}

struct DateResult: Codable, Sendable, Equatable {
    var dateId: String
    var outcome: DateOutcome
    var match: Match?

    init(dateId: String, outcome: DateOutcome, match: Match? = nil) {
        self.dateId = dateId
        self.outcome = outcome
        self.match = match
    }
}

struct ModerationActionMessage: Codable, Sendable, Equatable {
    var dateId: String
    var action: ModerationAction
    var category: ModerationCategory
    var message: String
}

struct ChatMessageEnvelope: Codable, Sendable, Equatable {
    var message: Message
}

struct MatchRemoved: Codable, Sendable, Equatable {
    var matchId: String
}

/// Payload of server `call.invite | call.accept | call.decline | call.end`.
struct CallSignal: Codable, Sendable, Equatable {
    var matchId: String
    var fromUserId: String
}

struct AccountSuspended: Codable, Sendable, Equatable {
    var until: Date?
    var reason: String

    init(until: Date? = nil, reason: String) {
        self.until = until
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case until, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        until = try? container.decodeIfPresent(Date.self, forKey: .until)
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? ""
    }
}

struct ServerErrorMessage: Codable, Sendable, Equatable {
    var code: String
    var message: String
}

// MARK: - Server → Client

enum ServerMessage: Sendable, Equatable, Decodable {
    case queueStatus(QueueStatus)
    case queueLimit(QueueLimit)
    case dateMatched(DateMatched)
    case dateStarted(DateStarted)
    case rtcSignal(RTCSignal)
    case icebreakerTurn(IcebreakerTurn)
    case dateCheckpoint(DateCheckpoint)
    case dateResumed(DateResumed)
    case dateEnded(DateEnded)
    case dateResult(DateResult)
    case moderationAction(ModerationActionMessage)
    case chatMessage(Message)
    case matchRemoved(matchId: String)
    case callInvite(CallSignal)
    case callAccept(CallSignal)
    case callDecline(CallSignal)
    case callEnd(CallSignal)
    case accountSuspended(AccountSuspended)
    case error(ServerErrorMessage)
    case pong
    /// A frame type this build does not know. Ignored by the stores.
    case unknown(type: String)

    private enum TypeKey: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "queue.status":
            self = .queueStatus(try QueueStatus(from: decoder))
        case "queue.limit":
            self = .queueLimit(try QueueLimit(from: decoder))
        case "date.matched":
            self = .dateMatched(try DateMatched(from: decoder))
        case "date.started":
            self = .dateStarted(try DateStarted(from: decoder))
        case "rtc.signal":
            self = .rtcSignal(try RTCSignal(from: decoder))
        case "icebreaker.turn":
            self = .icebreakerTurn(try IcebreakerTurn(from: decoder))
        case "date.checkpoint":
            self = .dateCheckpoint(try DateCheckpoint(from: decoder))
        case "date.resumed":
            self = .dateResumed(try DateResumed(from: decoder))
        case "date.ended":
            self = .dateEnded(try DateEnded(from: decoder))
        case "date.result":
            self = .dateResult(try DateResult(from: decoder))
        case "moderation.action":
            self = .moderationAction(try ModerationActionMessage(from: decoder))
        case "chat.message":
            let envelope = try ChatMessageEnvelope(from: decoder)
            self = .chatMessage(envelope.message)
        case "match.removed":
            let removed = try MatchRemoved(from: decoder)
            self = .matchRemoved(matchId: removed.matchId)
        case "call.invite":
            self = .callInvite(try CallSignal(from: decoder))
        case "call.accept":
            self = .callAccept(try CallSignal(from: decoder))
        case "call.decline":
            self = .callDecline(try CallSignal(from: decoder))
        case "call.end":
            self = .callEnd(try CallSignal(from: decoder))
        case "account.suspended":
            self = .accountSuspended(try AccountSuspended(from: decoder))
        case "error":
            self = .error(try ServerErrorMessage(from: decoder))
        case "pong":
            self = .pong
        default:
            self = .unknown(type: type)
        }
    }

    /// Decodes one WebSocket text frame.
    static func decode(from text: String) throws -> ServerMessage {
        guard let data = text.data(using: .utf8) else {
            throw TempoError.decoding
        }
        return try TempoJSON.makeDecoder().decode(ServerMessage.self, from: data)
    }

    static func decode(from data: Data) throws -> ServerMessage {
        try TempoJSON.makeDecoder().decode(ServerMessage.self, from: data)
    }

    /// The `dateId` this frame is about, when it has one.
    var dateId: String? {
        switch self {
        case .dateMatched(let value): return value.dateId
        case .dateStarted(let value): return value.dateId
        case .rtcSignal(let value): return value.dateId
        case .icebreakerTurn(let value): return value.dateId
        case .dateCheckpoint(let value): return value.dateId
        case .dateResumed(let value): return value.dateId
        case .dateEnded(let value): return value.dateId
        case .dateResult(let value): return value.dateId
        case .moderationAction(let value): return value.dateId
        case .queueStatus, .queueLimit, .chatMessage, .matchRemoved, .callInvite, .callAccept, .callDecline,
             .callEnd, .accountSuspended, .error, .pong, .unknown:
            return nil
        }
    }
}
