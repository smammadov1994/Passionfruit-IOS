import Foundation

struct Partner: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var firstName: String
    var age: Int
    var city: String
    var distanceKm: Double?
    var photoUrl: String?
    var intention: Intention?

    init(
        id: String,
        firstName: String,
        age: Int,
        city: String,
        distanceKm: Double? = nil,
        photoUrl: String? = nil,
        intention: Intention? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.age = age
        self.city = city
        self.distanceKm = distanceKm
        self.photoUrl = photoUrl
        self.intention = intention
    }

    enum CodingKeys: String, CodingKey {
        case id, firstName, age, city, distanceKm, photoUrl, intention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        firstName = try container.decode(String.self, forKey: .firstName)
        age = try container.decode(Int.self, forKey: .age)
        city = (try? container.decodeIfPresent(String.self, forKey: .city)) ?? ""
        distanceKm = try? container.decodeIfPresent(Double.self, forKey: .distanceKm)
        photoUrl = try? container.decodeIfPresent(String.self, forKey: .photoUrl)
        intention = container.lossyEnum(Intention.self, forKey: .intention)
    }

    /// First letter of the first name, for monogram placeholders.
    var monogram: String {
        guard let first = firstName.first else { return "?" }
        return String(first).uppercased()
    }

    /// "Maya, 29"
    var nameAndAge: String {
        "\(firstName), \(age)"
    }

    /// "2 km away", or the city when the distance is unknown, or nil when neither is known.
    var locationLine: String? {
        if let distanceKm {
            let rounded = max(1, Int(distanceKm.rounded()))
            return String(localized: "\(rounded) km away")
        }
        if !city.isEmpty {
            return city
        }
        return nil
    }

    /// "Maya, 29 · 2 km away"
    var summaryLine: String {
        if let locationLine {
            return "\(nameAndAge) · \(locationLine)"
        }
        return nameAndAge
    }
}

struct Message: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var matchId: String
    var senderId: String
    var text: String
    var sentAt: Date
    var clientId: String?

    init(id: String, matchId: String, senderId: String, text: String, sentAt: Date, clientId: String? = nil) {
        self.id = id
        self.matchId = matchId
        self.senderId = senderId
        self.text = text
        self.sentAt = sentAt
        self.clientId = clientId
    }
}

struct Match: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var partner: Partner
    var matchedAt: Date
    var lastMessage: Message?
    var unreadCount: Int

    init(id: String, partner: Partner, matchedAt: Date, lastMessage: Message? = nil, unreadCount: Int = 0) {
        self.id = id
        self.partner = partner
        self.matchedAt = matchedAt
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }

    enum CodingKeys: String, CodingKey {
        case id, partner, matchedAt, lastMessage, unreadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        partner = try container.decode(Partner.self, forKey: .partner)
        matchedAt = try container.decode(Date.self, forKey: .matchedAt)
        lastMessage = try container.decodeIfPresent(Message.self, forKey: .lastMessage)
        unreadCount = (try? container.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? 0
    }

    /// Most recent activity, used for sorting the matches list.
    var lastActivityAt: Date {
        lastMessage?.sentAt ?? matchedAt
    }
}
