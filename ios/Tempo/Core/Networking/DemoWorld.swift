import Foundation

/// Tunables of demo mode. Shared by `MockAPIClient` and `MockRealtimeSocket`.
struct DemoConfig: Sendable, Equatable {
    /// Shortened so the whole flow is quick to see.
    var dateDurationSec: Int = 45
    var turnDurationSec: Int = 10
    var decisionWindowSec: Int = 20
    /// Seconds to vote at the checkpoint after the first question. 0 = no checkpoint.
    var checkpointWindowSec: Int = 10
    /// Staying to the end of the date is a match, with no yes/no vote (as on the server).
    var matchOnFullDate: Bool = true
    var freeDailyDates: Int = 5
    var frameSampleIntervalSec: Double = 3
    var pairingDelayMin: Double = 2
    var pairingDelayMax: Double = 4
    var partnerYesProbability: Double = 0.6
    var partnerLeftProbability: Double = 0.12
    /// Simulated REST latency in seconds.
    var latency: Double = 0.25
    /// When false the mock socket only records what is sent; tests and previews drive it with `emit(_:)`.
    var autoScript: Bool = true

    init() {
        #if DEBUG
        // `-slowSearch` keeps the search on screen long enough to look at it.
        if ProcessInfo.processInfo.arguments.contains("-slowSearch") {
            pairingDelayMin = 9
            pairingDelayMax = 9
        }
        #endif
    }

    var appConfig: AppConfig {
        AppConfig(
            dateDurationSec: dateDurationSec,
            turnDurationSec: turnDurationSec,
            decisionWindowSec: decisionWindowSec,
            freeDailyDates: freeDailyDates,
            frameSampleIntervalSec: frameSampleIntervalSec,
            iceServers: []
        )
    }
}

struct DemoState: Sendable {
    var user: User
    var datesToday: Int = 0
    var matches: [Match] = []
    var messages: [String: [Message]] = [:]
    var partnerCursor: Int = 0
    var blockedUserIds: [String] = []
}

/// The fake backend's memory. Thread-safe; shared by the mock API and the mock socket.
final class DemoWorld: @unchecked Sendable {
    let config: DemoConfig

    private let lock = NSLock()
    private var state: DemoState
    private var replySink: (@Sendable (Message) -> Void)?
    private let persistenceKey: String?

    static let defaultPersistenceKey: String = "tempo.demo.user"
    static let demoToken: String = "demo-token"

    init(config: DemoConfig = DemoConfig(), onboarded: Bool = true, seedMatches: Bool = true, persistenceKey: String? = nil) {
        self.config = config
        self.persistenceKey = persistenceKey
        var user: User = onboarded ? DemoWorld.onboardedUser() : DemoWorld.blankUser()
        if let persistenceKey,
           let data = UserDefaults.standard.data(forKey: persistenceKey),
           let stored = try? TempoJSON.makeDecoder().decode(User.self, from: data) {
            user = stored
        }
        var initial = DemoState(user: user)
        if seedMatches && user.onboardingComplete {
            DemoWorld.seed(&initial)
        }
        self.state = initial
    }

    func read<T>(_ body: (DemoState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(state)
    }

    func mutate<T>(_ body: (inout DemoState) -> T) -> T {
        lock.lock()
        let result = body(&state)
        let user = state.user
        lock.unlock()
        persist(user)
        return result
    }

    private func persist(_ user: User) {
        guard let persistenceKey else { return }
        if let data = try? TempoJSON.makeEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    /// Wipes the account (demo "delete account").
    func reset() {
        lock.lock()
        state = DemoState(user: DemoWorld.blankUser())
        lock.unlock()
        if let persistenceKey {
            UserDefaults.standard.removeObject(forKey: persistenceKey)
        }
    }

    // MARK: Chat replies

    func setReplySink(_ sink: (@Sendable (Message) -> Void)?) {
        lock.lock()
        replySink = sink
        lock.unlock()
    }

    /// Stores a partner's message and pushes it to the mock socket as `chat.message`.
    func deliverPartnerMessage(_ message: Message) {
        lock.lock()
        var list: [Message] = state.messages[message.matchId] ?? []
        list.append(message)
        state.messages[message.matchId] = list
        if let index = state.matches.firstIndex(where: { $0.id == message.matchId }) {
            state.matches[index].lastMessage = message
            state.matches[index].unreadCount += 1
        }
        let sink = replySink
        lock.unlock()
        sink?(message)
    }

    // MARK: Partners and matches

    func nextPartner() -> Partner {
        mutate { (state: inout DemoState) -> Partner in
            let roster = DemoWorld.roster
            var attempts: Int = 0
            var partner: Partner = roster[state.partnerCursor % roster.count]
            while attempts < roster.count {
                partner = roster[state.partnerCursor % roster.count]
                state.partnerCursor += 1
                attempts += 1
                let alreadyMatched: Bool = state.matches.contains(where: { $0.partner.id == partner.id })
                let blocked: Bool = state.blockedUserIds.contains(partner.id)
                if !alreadyMatched && !blocked {
                    break
                }
            }
            return partner
        }
    }

    func makeMatch(with partner: Partner) -> Match {
        mutate { (state: inout DemoState) -> Match in
            let match = Match(id: "demo-match-" + UUID().uuidString.lowercased(), partner: partner, matchedAt: Date(), lastMessage: nil, unreadCount: 0)
            state.matches.insert(match, at: 0)
            state.messages[match.id] = []
            return match
        }
    }

    static func nextLocalMidnight(after date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86_400)
    }

    // MARK: Fixtures

    static let demoUserId: String = "demo-me"

    static func blankUser() -> User {
        User(id: demoUserId)
    }

    static func onboardedUser() -> User {
        User(
            id: demoUserId,
            firstName: "Alex",
            birthdate: "1996-05-14",
            gender: .man,
            interestedIn: [.woman, .man, .nonbinary],
            bio: "Bad at small talk, good at long walks.",
            city: "New York",
            lat: 40.7549,
            lng: -73.9840,
            photoUrls: [],
            intention: .longTerm,
            children: .open,
            religion: nil,
            education: .bachelors,
            smoking: .never,
            drinking: .socially,
            isPremium: false,
            premiumExpiresAt: nil,
            onboardingComplete: true,
            strikes: 0,
            suspendedUntil: nil,
            preferences: Preferences(ageMin: 24, ageMax: 38, maxDistanceKm: 40, notifyOnlineSingles: false)
        )
    }

    /// Ten varied fake partners. `photoUrl` is nil so UI shows monogram placeholders.
    static let roster: [Partner] = [
        Partner(id: "demo-p-maya", firstName: "Maya", age: 29, city: "Brooklyn", distanceKm: 2, photoUrl: nil, intention: .longTerm),
        Partner(id: "demo-p-jonas", firstName: "Jonas", age: 33, city: "Manhattan", distanceKm: 4, photoUrl: nil, intention: .figuringOut),
        Partner(id: "demo-p-priya", firstName: "Priya", age: 27, city: "Jersey City", distanceKm: 7, photoUrl: nil, intention: .longTerm),
        Partner(id: "demo-p-theo", firstName: "Theo", age: 31, city: "Queens", distanceKm: 11, photoUrl: nil, intention: .shortTerm),
        Partner(id: "demo-p-camille", firstName: "Camille", age: 35, city: "Hoboken", distanceKm: 6, photoUrl: nil, intention: .marriage),
        Partner(id: "demo-p-noor", firstName: "Noor", age: 26, city: "Harlem", distanceKm: 9, photoUrl: nil, intention: .figuringOut),
        Partner(id: "demo-p-diego", firstName: "Diego", age: 30, city: "Williamsburg", distanceKm: 3, photoUrl: nil, intention: .longTerm),
        Partner(id: "demo-p-sasha", firstName: "Sasha", age: 28, city: "Astoria", distanceKm: 8, photoUrl: nil, intention: nil),
        Partner(id: "demo-p-ines", firstName: "Inès", age: 32, city: "Upper West Side", distanceKm: 5, photoUrl: nil, intention: .longTerm),
        Partner(id: "demo-p-kenji", firstName: "Kenji", age: 34, city: "Long Island City", distanceKm: 6, photoUrl: nil, intention: .marriage),
        Partner(id: "demo-p-ada", firstName: "Ada", age: 25, city: "Bushwick", distanceKm: 10, photoUrl: nil, intention: .shortTerm),
        Partner(id: "demo-p-luca", firstName: "Luca", age: 37, city: "Tribeca", distanceKm: 3, photoUrl: nil, intention: .longTerm)
    ]

    static let partnerReplies: [String] = [
        "Ha, I was hoping you'd say that.",
        "Okay, that's a strong opinion. I respect it.",
        "Same. What are you up to this weekend?",
        "You were more fun than the timer allowed.",
        "Tell me more about that.",
        "I'm free Thursday if you are.",
        "That made me laugh out loud on the subway.",
        "Deal. But you're picking the place."
    ]

    private static func seed(_ state: inout DemoState) {
        let now = Date()
        let me: String = state.user.id

        let lena = Partner(id: "demo-p-lena", firstName: "Lena", age: 30, city: "Chelsea", distanceKm: 1, photoUrl: nil, intention: .longTerm)
        let omar = Partner(id: "demo-p-omar", firstName: "Omar", age: 32, city: "Park Slope", distanceKm: 8, photoUrl: nil, intention: .marriage)
        let june = Partner(id: "demo-p-june", firstName: "June", age: 28, city: "East Village", distanceKm: 3, photoUrl: nil, intention: .figuringOut)

        let lenaMessages: [Message] = [
            Message(id: "demo-m-1", matchId: "demo-match-lena", senderId: lena.id, text: "Four minutes was not enough.", sentAt: now.addingTimeInterval(-5_400), clientId: nil),
            Message(id: "demo-m-2", matchId: "demo-match-lena", senderId: me, text: "Agreed. You never finished the story about the ferry.", sentAt: now.addingTimeInterval(-5_100), clientId: nil),
            Message(id: "demo-m-3", matchId: "demo-match-lena", senderId: lena.id, text: "It gets worse. Coffee on Saturday and I'll tell you?", sentAt: now.addingTimeInterval(-1_500), clientId: nil)
        ]
        let omarMessages: [Message] = [
            Message(id: "demo-m-4", matchId: "demo-match-omar", senderId: me, text: "So, about that controversial food opinion…", sentAt: now.addingTimeInterval(-90_000), clientId: nil),
            Message(id: "demo-m-5", matchId: "demo-match-omar", senderId: omar.id, text: "I stand by it. Pineapple belongs.", sentAt: now.addingTimeInterval(-86_000), clientId: nil)
        ]

        state.matches = [
            Match(id: "demo-match-lena", partner: lena, matchedAt: now.addingTimeInterval(-6_000), lastMessage: lenaMessages.last, unreadCount: 1),
            Match(id: "demo-match-omar", partner: omar, matchedAt: now.addingTimeInterval(-100_000), lastMessage: omarMessages.last, unreadCount: 0),
            Match(id: "demo-match-june", partner: june, matchedAt: now.addingTimeInterval(-200_000), lastMessage: nil, unreadCount: 0)
        ]
        state.messages = [
            "demo-match-lena": lenaMessages,
            "demo-match-omar": omarMessages,
            "demo-match-june": []
        ]
    }
}

/// Icebreaker questions bundled with the app (`Resources/icebreakers.json`). Used by demo mode only;
/// in live mode the server is authoritative.
enum IcebreakerFallback {
    private struct File: Decodable {
        var questions: [String]
    }

    static let builtIn: [String] = [
        "What's a small thing that made today better?",
        "What would your perfect Sunday look like?",
        "What are you unreasonably good at?",
        "What's a song you never skip?",
        "What would you do with a free year?"
    ]

    static func loadQuestions(bundle: Bundle = Bundle.main) -> [String] {
        guard let url = bundle.url(forResource: "icebreakers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              !file.questions.isEmpty else {
            return builtIn
        }
        return file.questions
    }
}
