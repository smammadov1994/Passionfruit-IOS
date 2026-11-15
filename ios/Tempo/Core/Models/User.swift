import Foundation

struct Preferences: Codable, Sendable, Equatable {
    var ageMin: Int
    var ageMax: Int
    var maxDistanceKm: Int
    /// Advanced (Premium) filters. nil = no filter.
    var intentions: [Intention]?
    var children: [ChildrenStatus]?
    var religions: [Religion]?
    var minEducation: Education?
    var smokingOk: [Smoking]?
    var drinkingOk: [Drinking]?
    var notifyOnlineSingles: Bool

    init(
        ageMin: Int = 18,
        ageMax: Int = 99,
        maxDistanceKm: Int = 100,
        intentions: [Intention]? = nil,
        children: [ChildrenStatus]? = nil,
        religions: [Religion]? = nil,
        minEducation: Education? = nil,
        smokingOk: [Smoking]? = nil,
        drinkingOk: [Drinking]? = nil,
        notifyOnlineSingles: Bool = false
    ) {
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.maxDistanceKm = maxDistanceKm
        self.intentions = intentions
        self.children = children
        self.religions = religions
        self.minEducation = minEducation
        self.smokingOk = smokingOk
        self.drinkingOk = drinkingOk
        self.notifyOnlineSingles = notifyOnlineSingles
    }

    static let `default` = Preferences()

    enum CodingKeys: String, CodingKey {
        case ageMin, ageMax, maxDistanceKm, intentions, children, religions, minEducation, smokingOk, drinkingOk, notifyOnlineSingles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ageMin = (try? container.decodeIfPresent(Int.self, forKey: .ageMin)) ?? 18
        ageMax = (try? container.decodeIfPresent(Int.self, forKey: .ageMax)) ?? 99
        if let distance = try? container.decodeIfPresent(Double.self, forKey: .maxDistanceKm) {
            maxDistanceKm = Int(distance.rounded())
        } else {
            maxDistanceKm = 100
        }
        intentions = container.lossyEnumArray(Intention.self, forKey: .intentions)
        children = container.lossyEnumArray(ChildrenStatus.self, forKey: .children)
        religions = container.lossyEnumArray(Religion.self, forKey: .religions)
        minEducation = container.lossyEnum(Education.self, forKey: .minEducation)
        smokingOk = container.lossyEnumArray(Smoking.self, forKey: .smokingOk)
        drinkingOk = container.lossyEnumArray(Drinking.self, forKey: .drinkingOk)
        notifyOnlineSingles = (try? container.decodeIfPresent(Bool.self, forKey: .notifyOnlineSingles)) ?? false
    }

    /// True when any Premium-only filter is set.
    var hasAdvancedFilters: Bool {
        let lists: [Bool] = [
            !(intentions ?? []).isEmpty,
            !(children ?? []).isEmpty,
            !(religions ?? []).isEmpty,
            minEducation != nil,
            !(smokingOk ?? []).isEmpty,
            !(drinkingOk ?? []).isEmpty
        ]
        return lists.contains(true)
    }
}

struct User: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var firstName: String
    /// `YYYY-MM-DD`. Empty until onboarding sets it.
    var birthdate: String
    /// nil until onboarding sets it.
    var gender: Gender?
    var interestedIn: [Gender]
    var bio: String
    var city: String
    var lat: Double?
    var lng: Double?
    var photoUrls: [String]
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var isPremium: Bool
    var premiumExpiresAt: Date?
    var onboardingComplete: Bool
    var strikes: Int
    var suspendedUntil: Date?
    var preferences: Preferences

    init(
        id: String,
        firstName: String = "",
        birthdate: String = "",
        gender: Gender? = nil,
        interestedIn: [Gender] = [],
        bio: String = "",
        city: String = "",
        lat: Double? = nil,
        lng: Double? = nil,
        photoUrls: [String] = [],
        intention: Intention? = nil,
        children: ChildrenStatus? = nil,
        religion: Religion? = nil,
        education: Education? = nil,
        smoking: Smoking? = nil,
        drinking: Drinking? = nil,
        isPremium: Bool = false,
        premiumExpiresAt: Date? = nil,
        onboardingComplete: Bool = false,
        strikes: Int = 0,
        suspendedUntil: Date? = nil,
        preferences: Preferences = Preferences()
    ) {
        self.id = id
        self.firstName = firstName
        self.birthdate = birthdate
        self.gender = gender
        self.interestedIn = interestedIn
        self.bio = bio
        self.city = city
        self.lat = lat
        self.lng = lng
        self.photoUrls = photoUrls
        self.intention = intention
        self.children = children
        self.religion = religion
        self.education = education
        self.smoking = smoking
        self.drinking = drinking
        self.isPremium = isPremium
        self.premiumExpiresAt = premiumExpiresAt
        self.onboardingComplete = onboardingComplete
        self.strikes = strikes
        self.suspendedUntil = suspendedUntil
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case id, firstName, birthdate, gender, interestedIn, bio, city, lat, lng, photoUrls
        case intention, children, religion, education, smoking, drinking
        case isPremium, premiumExpiresAt, onboardingComplete, strikes, suspendedUntil, preferences
    }

    /// Lenient: a freshly created account may have null or missing profile fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        firstName = (try? container.decodeIfPresent(String.self, forKey: .firstName)) ?? ""
        birthdate = (try? container.decodeIfPresent(String.self, forKey: .birthdate)) ?? ""
        gender = container.lossyEnum(Gender.self, forKey: .gender)
        interestedIn = container.lossyEnumArray(Gender.self, forKey: .interestedIn) ?? []
        bio = (try? container.decodeIfPresent(String.self, forKey: .bio)) ?? ""
        city = (try? container.decodeIfPresent(String.self, forKey: .city)) ?? ""
        lat = try? container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try? container.decodeIfPresent(Double.self, forKey: .lng)
        photoUrls = (try? container.decodeIfPresent([String].self, forKey: .photoUrls)) ?? []
        intention = container.lossyEnum(Intention.self, forKey: .intention)
        children = container.lossyEnum(ChildrenStatus.self, forKey: .children)
        religion = container.lossyEnum(Religion.self, forKey: .religion)
        education = container.lossyEnum(Education.self, forKey: .education)
        smoking = container.lossyEnum(Smoking.self, forKey: .smoking)
        drinking = container.lossyEnum(Drinking.self, forKey: .drinking)
        isPremium = (try? container.decodeIfPresent(Bool.self, forKey: .isPremium)) ?? false
        premiumExpiresAt = try? container.decodeIfPresent(Date.self, forKey: .premiumExpiresAt)
        onboardingComplete = (try? container.decodeIfPresent(Bool.self, forKey: .onboardingComplete)) ?? false
        strikes = (try? container.decodeIfPresent(Int.self, forKey: .strikes)) ?? 0
        suspendedUntil = try? container.decodeIfPresent(Date.self, forKey: .suspendedUntil)
        preferences = (try? container.decodeIfPresent(Preferences.self, forKey: .preferences)) ?? Preferences()
    }

    /// Age in whole years, nil when the birthdate is not set or unparseable.
    var age: Int? {
        guard let date = Birthdate.date(from: birthdate) else { return nil }
        return Birthdate.age(from: date)
    }

    /// Suspended when a timed suspension is running, or at three strikes (suspension pending review,
    /// which the server does not put in `suspendedUntil`).
    var isSuspended: Bool {
        if strikes >= User.strikesToSuspend {
            return true
        }
        guard let until = suspendedUntil else { return false }
        return until > Date()
    }

    static let strikesToSuspend: Int = 3

    var primaryPhotoUrl: String? { photoUrls.first }

    /// First letter of the first name, for monogram placeholders.
    var monogram: String {
        guard let first = firstName.first else { return "?" }
        return String(first).uppercased()
    }
}

/// Body of `PUT /v1/me`. Only non-nil fields are sent.
/// An optional profile answer that `PUT /v1/me` can clear with an explicit `null`.
enum ClearableProfileField: String, Sendable, Equatable, Hashable, CaseIterable {
    case intention
    case children
    case religion
    case education
    case smoking
    case drinking
}

/// The body of `PUT /v1/me`. Nil fields are left out of the request (the server keeps what it
/// has). To remove an answered basic, leave the field nil and name it in `clearing`: it is then
/// sent as an explicit `null`, which the server takes as "clear".
struct ProfileUpdate: Codable, Sendable, Equatable {
    var firstName: String?
    var birthdate: String?
    var gender: Gender?
    var interestedIn: [Gender]?
    var bio: String?
    var city: String?
    var lat: Double?
    var lng: Double?
    var photoUrls: [String]?
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var onboardingComplete: Bool?
    /// Minutes east of UTC (New York in winter = -300). Lets the server reset the daily cap at local midnight.
    var tzOffsetMinutes: Int?
    /// Answers to remove. Not a wire field: each one is encoded as `"<field>": null`.
    /// A field that also has a value here is sent with its value.
    var clearing: Set<ClearableProfileField> = []

    private enum CodingKeys: String, CodingKey {
        case firstName
        case birthdate
        case gender
        case interestedIn
        case bio
        case city
        case lat
        case lng
        case photoUrls
        case intention
        case children
        case religion
        case education
        case smoking
        case drinking
        case onboardingComplete
        case tzOffsetMinutes
    }

    init(
        firstName: String? = nil,
        birthdate: String? = nil,
        gender: Gender? = nil,
        interestedIn: [Gender]? = nil,
        bio: String? = nil,
        city: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        photoUrls: [String]? = nil,
        intention: Intention? = nil,
        children: ChildrenStatus? = nil,
        religion: Religion? = nil,
        education: Education? = nil,
        smoking: Smoking? = nil,
        drinking: Drinking? = nil,
        onboardingComplete: Bool? = nil,
        tzOffsetMinutes: Int? = nil,
        clearing: Set<ClearableProfileField> = []
    ) {
        self.firstName = firstName
        self.birthdate = birthdate
        self.gender = gender
        self.interestedIn = interestedIn
        self.bio = bio
        self.city = city
        self.lat = lat
        self.lng = lng
        self.photoUrls = photoUrls
        self.intention = intention
        self.children = children
        self.religion = religion
        self.education = education
        self.smoking = smoking
        self.drinking = drinking
        self.onboardingComplete = onboardingComplete
        self.tzOffsetMinutes = tzOffsetMinutes
        self.clearing = clearing
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(birthdate, forKey: .birthdate)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(interestedIn, forKey: .interestedIn)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lng, forKey: .lng)
        try container.encodeIfPresent(photoUrls, forKey: .photoUrls)
        try container.encodeIfPresent(intention, forKey: .intention)
        try container.encodeIfPresent(children, forKey: .children)
        try container.encodeIfPresent(religion, forKey: .religion)
        try container.encodeIfPresent(education, forKey: .education)
        try container.encodeIfPresent(smoking, forKey: .smoking)
        try container.encodeIfPresent(drinking, forKey: .drinking)
        try container.encodeIfPresent(onboardingComplete, forKey: .onboardingComplete)
        try container.encodeIfPresent(tzOffsetMinutes, forKey: .tzOffsetMinutes)
        if clearing.contains(.intention) && intention == nil {
            try container.encodeNil(forKey: .intention)
        }
        if clearing.contains(.children) && children == nil {
            try container.encodeNil(forKey: .children)
        }
        if clearing.contains(.religion) && religion == nil {
            try container.encodeNil(forKey: .religion)
        }
        if clearing.contains(.education) && education == nil {
            try container.encodeNil(forKey: .education)
        }
        if clearing.contains(.smoking) && smoking == nil {
            try container.encodeNil(forKey: .smoking)
        }
        if clearing.contains(.drinking) && drinking == nil {
            try container.encodeNil(forKey: .drinking)
        }
    }
}

/// Local, not-yet-submitted onboarding answers. Lives in `SessionStore.draft`.
struct OnboardingDraft: Sendable, Equatable {
    var firstName: String = ""
    var birthdate: Date?
    var gender: Gender?
    var interestedIn: [Gender] = []
    var bio: String = ""
    var city: String = ""
    var lat: Double?
    var lng: Double?
    /// URLs returned by `SessionStore.uploadPhoto` during onboarding.
    var photoUrls: [String] = []
    var intention: Intention?
    var children: ChildrenStatus?
    var religion: Religion?
    var education: Education?
    var smoking: Smoking?
    var drinking: Drinking?
    var ageMin: Int = 21
    var ageMax: Int = 45
    var maxDistanceKm: Int = 50
    var notifyOnlineSingles: Bool = false

    init() {}

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var age: Int? {
        guard let birthdate else { return nil }
        return Birthdate.age(from: birthdate)
    }

    /// 18+ gate.
    var isAdult: Bool {
        guard let age else { return false }
        return age >= Birthdate.minimumAge
    }

    var isNameValid: Bool {
        let count = trimmedFirstName.count
        return count >= 2 && count <= 30
    }

    /// Everything required to finish onboarding: name, 18+ birthdate, gender, at least one "interested in".
    var canSubmit: Bool {
        isNameValid && isAdult && gender != nil && !interestedIn.isEmpty
    }

    /// First problem that blocks submission, as a user-presentable sentence. nil when ready.
    var validationMessage: String? {
        if !isNameValid {
            return String(localized: "Add your first name.")
        }
        if birthdate == nil {
            return String(localized: "Add your date of birth.")
        }
        if !isAdult {
            return String(localized: "You need to be 18 or older to use \(Brand.name).")
        }
        if gender == nil {
            return String(localized: "Tell us how you identify.")
        }
        if interestedIn.isEmpty {
            return String(localized: "Choose who you'd like to meet.")
        }
        return nil
    }

    func makeProfileUpdate() -> ProfileUpdate {
        var update = ProfileUpdate()
        update.firstName = trimmedFirstName
        if let birthdate {
            update.birthdate = Birthdate.string(from: birthdate)
        }
        update.gender = gender
        update.interestedIn = interestedIn
        update.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty {
            update.city = city
        }
        update.lat = lat
        update.lng = lng
        // Always sent: uploads are attached to the profile at once, so this also applies removals and order.
        update.photoUrls = photoUrls
        update.intention = intention
        update.children = children
        update.religion = religion
        update.education = education
        update.smoking = smoking
        update.drinking = drinking
        update.onboardingComplete = true
        update.tzOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
        return update
    }

    func makePreferences(base: Preferences) -> Preferences {
        var preferences = base
        preferences.ageMin = max(Birthdate.minimumAge, min(ageMin, ageMax))
        preferences.ageMax = max(ageMin, ageMax)
        preferences.maxDistanceKm = maxDistanceKm
        preferences.notifyOnlineSingles = notifyOnlineSingles
        return preferences
    }
}
