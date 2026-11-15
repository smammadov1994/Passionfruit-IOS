import Foundation

/// In-memory backend for demo mode, previews and tests.
final class MockAPIClient: APIClient, @unchecked Sendable {
    let world: DemoWorld

    init(world: DemoWorld) {
        self.world = world
    }

    private func simulateLatency() async throws {
        let seconds: Double = world.config.latency
        if seconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    func signInWithApple(identityToken: String, firstName: String?) async throws -> AuthResponse {
        try await simulateLatency()
        let user: User = world.mutate { (state: inout DemoState) -> User in
            if let firstName, !firstName.isEmpty, state.user.firstName.isEmpty {
                state.user.firstName = firstName
            }
            return state.user
        }
        return AuthResponse(token: DemoWorld.demoToken, user: user)
    }

    func signInDev(deviceId: String) async throws -> AuthResponse {
        try await simulateLatency()
        let user: User = world.read { $0.user }
        return AuthResponse(token: DemoWorld.demoToken, user: user)
    }

    func fetchConfig() async throws -> AppConfig {
        try await simulateLatency()
        return world.config.appConfig
    }

    func fetchMe() async throws -> User {
        try await simulateLatency()
        return world.read { $0.user }
    }

    func updateMe(_ update: ProfileUpdate) async throws -> User {
        try await simulateLatency()
        return world.mutate { (state: inout DemoState) -> User in
            if let value = update.firstName { state.user.firstName = value }
            if let value = update.birthdate { state.user.birthdate = value }
            if let value = update.gender { state.user.gender = value }
            if let value = update.interestedIn { state.user.interestedIn = value }
            if let value = update.bio { state.user.bio = value }
            if let value = update.city { state.user.city = value }
            if let value = update.lat { state.user.lat = value }
            if let value = update.lng { state.user.lng = value }
            if let value = update.photoUrls { state.user.photoUrls = value }
            if let value = update.intention { state.user.intention = value }
            if let value = update.children { state.user.children = value }
            if let value = update.religion { state.user.religion = value }
            if let value = update.education { state.user.education = value }
            if let value = update.smoking { state.user.smoking = value }
            if let value = update.drinking { state.user.drinking = value }
            if let value = update.onboardingComplete { state.user.onboardingComplete = value }
            // Like the server: an explicit null (here, `clearing`) removes the answer.
            if update.clearing.contains(.intention) && update.intention == nil { state.user.intention = nil }
            if update.clearing.contains(.children) && update.children == nil { state.user.children = nil }
            if update.clearing.contains(.religion) && update.religion == nil { state.user.religion = nil }
            if update.clearing.contains(.education) && update.education == nil { state.user.education = nil }
            if update.clearing.contains(.smoking) && update.smoking == nil { state.user.smoking = nil }
            if update.clearing.contains(.drinking) && update.drinking == nil { state.user.drinking = nil }
            return state.user
        }
    }

    func updatePreferences(_ preferences: Preferences) async throws -> Preferences {
        try await simulateLatency()
        return world.mutate { (state: inout DemoState) -> Preferences in
            var next: Preferences = preferences
            if !state.user.isPremium {
                // Advanced fields are ignored unless premium.
                let current: Preferences = state.user.preferences
                next.intentions = current.intentions
                next.children = current.children
                next.religions = current.religions
                next.minEducation = current.minEducation
                next.smokingOk = current.smokingOk
                next.drinkingOk = current.drinkingOk
            }
            state.user.preferences = next
            return next
        }
    }

    func uploadPhoto(jpegData: Data) async throws -> String {
        try await simulateLatency()
        let directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let fileURL: URL = directory.appendingPathComponent("demo-photo-" + UUID().uuidString.lowercased() + ".jpg")
        do {
            try jpegData.write(to: fileURL, options: .atomic)
        } catch {
            throw TempoError.unknown(String(localized: "Couldn't save that photo. Try another one."))
        }
        let stored: String = fileURL.absoluteString
        // Like the server, attach the photo to the profile at once.
        world.mutate { (state: inout DemoState) -> Void in
            state.user.photoUrls.append(stored)
        }
        return stored
    }

    func registerPushToken(apnsToken: String, tzOffsetMinutes: Int, enabled: Bool) async throws {
        try await simulateLatency()
    }

    func deleteAccount() async throws {
        try await simulateLatency()
        world.reset()
    }

    func fetchUsage() async throws -> Usage {
        try await simulateLatency()
        let freeLimit: Int = world.config.freeDailyDates
        return world.read { (state: DemoState) -> Usage in
            Usage(
                datesToday: state.datesToday,
                limit: state.user.isPremium ? nil : freeLimit,
                resetsAt: DemoWorld.nextLocalMidnight()
            )
        }
    }

    func fetchOnlineCount() async throws -> Int {
        try await simulateLatency()
        return Int.random(in: 17...34)
    }

    func fetchMatches() async throws -> [Match] {
        try await simulateLatency()
        return world.read { $0.matches }
    }

    func unmatch(matchId: String) async throws {
        try await simulateLatency()
        world.mutate { (state: inout DemoState) -> Void in
            state.matches.removeAll(where: { $0.id == matchId })
            state.messages[matchId] = nil
        }
    }

    func fetchMessages(matchId: String, before: Date?, limit: Int) async throws -> [Message] {
        try await simulateLatency()
        return world.read { (state: DemoState) -> [Message] in
            var list: [Message] = state.messages[matchId] ?? []
            if let before {
                list = list.filter { $0.sentAt < before }
            }
            let count: Int = max(0, limit)
            return Array(list.suffix(count))
        }
    }

    func sendMessage(matchId: String, text: String, clientId: String) async throws -> Message {
        try await simulateLatency()
        let message: Message = world.mutate { (state: inout DemoState) -> Message in
            let message = Message(
                id: "demo-msg-" + UUID().uuidString.lowercased(),
                matchId: matchId,
                senderId: state.user.id,
                text: text,
                sentAt: Date(),
                clientId: clientId
            )
            var list: [Message] = state.messages[matchId] ?? []
            list.append(message)
            state.messages[matchId] = list
            if let index = state.matches.firstIndex(where: { $0.id == matchId }) {
                state.matches[index].lastMessage = message
            }
            return message
        }
        scheduleReply(matchId: matchId)
        return message
    }

    private func scheduleReply(matchId: String) {
        let world: DemoWorld = self.world
        Task {
            let delay: Double = Double.random(in: 2.0...4.5)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let partnerId: String? = world.read { (state: DemoState) -> String? in
                state.matches.first(where: { $0.id == matchId })?.partner.id
            }
            guard let partnerId else { return }
            let text: String = DemoWorld.partnerReplies.randomElement() ?? "Ha."
            let reply = Message(
                id: "demo-msg-" + UUID().uuidString.lowercased(),
                matchId: matchId,
                senderId: partnerId,
                text: text,
                sentAt: Date(),
                clientId: nil
            )
            world.deliverPartnerMessage(reply)
        }
    }

    func markRead(matchId: String) async throws {
        world.mutate { (state: inout DemoState) -> Void in
            if let index = state.matches.firstIndex(where: { $0.id == matchId }) {
                state.matches[index].unreadCount = 0
            }
        }
    }

    func report(_ report: ReportRequest) async throws {
        try await simulateLatency()
    }

    func block(userId: String) async throws {
        try await simulateLatency()
        world.mutate { (state: inout DemoState) -> Void in
            if !state.blockedUserIds.contains(userId) {
                state.blockedUserIds.append(userId)
            }
            let removed: [Match] = state.matches.filter { $0.partner.id == userId }
            for match in removed {
                state.messages[match.id] = nil
            }
            state.matches.removeAll(where: { $0.partner.id == userId })
        }
    }

    func moderateFrame(dateId: String, jpegData: Data) async throws -> ModerationAction {
        ModerationAction.none
    }

    func moderateTranscript(dateId: String, text: String) async throws -> ModerationAction {
        ModerationAction.none
    }

    func verifyPurchase(jwsTransaction: String) async throws -> PremiumStatus {
        try await simulateLatency()
        let expires: Date = Date().addingTimeInterval(30 * 86_400)
        world.mutate { (state: inout DemoState) -> Void in
            state.user.isPremium = true
            state.user.premiumExpiresAt = expires
        }
        return PremiumStatus(isPremium: true, premiumExpiresAt: expires)
    }

    func health() async throws -> Bool {
        true
    }
}
