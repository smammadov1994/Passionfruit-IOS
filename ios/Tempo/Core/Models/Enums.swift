import Foundation

// All wire enums are String-backed and match SPEC section 3 exactly.
// Every enum has a `displayName` for UI.

enum Gender: String, Codable, Sendable, CaseIterable, Identifiable {
    case woman
    case man
    case nonbinary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woman: return String(localized: "Woman")
        case .man: return String(localized: "Man")
        case .nonbinary: return String(localized: "Nonbinary")
        }
    }

    /// Used for "interested in" pickers: "Women", "Men", "Nonbinary people".
    var pluralDisplayName: String {
        switch self {
        case .woman: return String(localized: "Women")
        case .man: return String(localized: "Men")
        case .nonbinary: return String(localized: "Nonbinary people")
        }
    }
}

enum Intention: String, Codable, Sendable, CaseIterable, Identifiable {
    case longTerm = "long_term"
    case shortTerm = "short_term"
    case marriage
    case figuringOut = "figuring_out"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .longTerm: return String(localized: "Long-term")
        case .shortTerm: return String(localized: "Short-term")
        case .marriage: return String(localized: "Marriage")
        case .figuringOut: return String(localized: "Figuring it out")
        }
    }
}

enum ChildrenStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case hasWantsMore = "has_wants_more"
    case hasDone = "has_done"
    case wants
    case doesntWant = "doesnt_want"
    case open

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hasWantsMore: return String(localized: "Has kids, wants more")
        case .hasDone: return String(localized: "Has kids, done")
        case .wants: return String(localized: "Wants kids")
        case .doesntWant: return String(localized: "Doesn't want kids")
        case .open: return String(localized: "Open to kids")
        }
    }
}

enum Religion: String, Codable, Sendable, CaseIterable, Identifiable {
    case agnostic
    case atheist
    case buddhist
    case christian
    case hindu
    case jewish
    case muslim
    case spiritual
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agnostic: return String(localized: "Agnostic")
        case .atheist: return String(localized: "Atheist")
        case .buddhist: return String(localized: "Buddhist")
        case .christian: return String(localized: "Christian")
        case .hindu: return String(localized: "Hindu")
        case .jewish: return String(localized: "Jewish")
        case .muslim: return String(localized: "Muslim")
        case .spiritual: return String(localized: "Spiritual")
        case .other: return String(localized: "Other")
        }
    }
}

enum Education: String, Codable, Sendable, CaseIterable, Identifiable {
    case highSchool = "high_school"
    case someCollege = "some_college"
    case bachelors
    case masters
    case doctorate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highSchool: return String(localized: "High school")
        case .someCollege: return String(localized: "Some college")
        case .bachelors: return String(localized: "Bachelor's")
        case .masters: return String(localized: "Master's")
        case .doctorate: return String(localized: "Doctorate")
        }
    }

    /// Ordering used by the `minEducation` filter (0 = lowest).
    var rank: Int {
        switch self {
        case .highSchool: return 0
        case .someCollege: return 1
        case .bachelors: return 2
        case .masters: return 3
        case .doctorate: return 4
        }
    }
}

enum Smoking: String, Codable, Sendable, CaseIterable, Identifiable {
    case never
    case sometimes
    case regularly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return String(localized: "Never smokes")
        case .sometimes: return String(localized: "Smokes sometimes")
        case .regularly: return String(localized: "Smokes regularly")
        }
    }
}

enum Drinking: String, Codable, Sendable, CaseIterable, Identifiable {
    case never
    case socially
    case regularly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return String(localized: "Never drinks")
        case .socially: return String(localized: "Drinks socially")
        case .regularly: return String(localized: "Drinks regularly")
        }
    }
}

enum ReportReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case nudity
    case sexualLanguage = "sexual_language"
    case harassment
    case underage
    case fakeProfile = "fake_profile"
    case spam
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nudity: return String(localized: "Nudity")
        case .sexualLanguage: return String(localized: "Sexual language")
        case .harassment: return String(localized: "Harassment")
        case .underage: return String(localized: "Seems under 18")
        case .fakeProfile: return String(localized: "Fake profile")
        case .spam: return String(localized: "Spam or scam")
        case .other: return String(localized: "Something else")
        }
    }
}

/// `action` in moderation REST responses (`none | warn | end`) and in `moderation.action` (`warn | end`).
enum ModerationAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case warn
    case end

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return String(localized: "No action")
        case .warn: return String(localized: "Warning")
        case .end: return String(localized: "Date ended")
        }
    }
}

enum ModerationCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case nudity
    case sexualLanguage = "sexual_language"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nudity: return String(localized: "Nudity")
        case .sexualLanguage: return String(localized: "Sexual language")
        }
    }
}

/// `reason` in `date.ended`.
enum DateEndReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case timer
    case partnerLeft = "partner_left"
    case youLeft = "you_left"
    case moderation
    case disconnect
    /// One of the two chose not to carry on at the checkpoint (or did not answer).
    case checkpoint

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timer: return String(localized: "Time's up")
        case .partnerLeft: return String(localized: "They left")
        case .youLeft: return String(localized: "You left")
        case .moderation: return String(localized: "Ended for safety")
        case .disconnect: return String(localized: "Connection lost")
        case .checkpoint: return String(localized: "Ended after the first question")
        }
    }
}

/// The private vote at the checkpoint after the first question.
enum CheckpointChoice: String, Codable, Sendable {
    case carryOn = "continue"
    case end
}

enum DateDecision: String, Codable, Sendable, CaseIterable, Identifiable {
    case yes
    case no

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yes: return String(localized: "Yes")
        case .no: return String(localized: "No")
        }
    }
}

enum DateOutcome: String, Codable, Sendable, CaseIterable, Identifiable {
    case match
    case noMatch = "no_match"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .match: return String(localized: "It's mutual.")
        case .noMatch: return String(localized: "Not this time.")
        }
    }
}

/// `role` in `date.matched`. The caller creates the WebRTC offer.
enum CallRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case caller
    case callee

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .caller: return String(localized: "Caller")
        case .callee: return String(localized: "Callee")
        }
    }
}

enum RTCSignalKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case offer
    case answer
    case ice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .offer: return "Offer"
        case .answer: return "Answer"
        case .ice: return "ICE candidate"
        }
    }
}

// MARK: - Lenient decoding helpers

extension KeyedDecodingContainer {
    /// Decodes an optional String-backed enum, returning nil for missing, null or unknown values.
    func lossyEnum<T: RawRepresentable>(_ type: T.Type, forKey key: Key) -> T? where T.RawValue == String {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return T(rawValue: raw)
    }

    /// Decodes an optional array of String-backed enums, dropping unknown values. Missing or null gives nil.
    func lossyEnumArray<T: RawRepresentable>(_ type: T.Type, forKey key: Key) -> [T]? where T.RawValue == String {
        guard let raws = try? decodeIfPresent([String].self, forKey: key) else { return nil }
        var result: [T] = []
        for raw in raws {
            if let value = T(rawValue: raw) {
                result.append(value)
            }
        }
        return result
    }
}
