import Foundation

/// Typed access to every REST route in SPEC section 3.
protocol APIClient: Sendable {
    /// POST /v1/auth/apple
    func signInWithApple(identityToken: String, firstName: String?) async throws -> AuthResponse
    /// POST /v1/auth/dev
    func signInDev(deviceId: String) async throws -> AuthResponse
    /// GET /v1/config
    func fetchConfig() async throws -> AppConfig
    /// GET /v1/me
    func fetchMe() async throws -> User
    /// PUT /v1/me
    func updateMe(_ update: ProfileUpdate) async throws -> User
    /// PUT /v1/me/preferences
    func updatePreferences(_ preferences: Preferences) async throws -> Preferences
    /// POST /v1/me/photos. Returns the photo URL.
    func uploadPhoto(jpegData: Data) async throws -> String
    /// POST /v1/me/push-token
    func registerPushToken(apnsToken: String, tzOffsetMinutes: Int, enabled: Bool) async throws
    /// DELETE /v1/me
    func deleteAccount() async throws
    /// GET /v1/usage
    func fetchUsage() async throws -> Usage
    /// GET /v1/online-count
    func fetchOnlineCount() async throws -> Int
    /// GET /v1/matches
    func fetchMatches() async throws -> [Match]
    /// DELETE /v1/matches/:id
    func unmatch(matchId: String) async throws
    /// GET /v1/matches/:id/messages?before=&limit= (newest last)
    func fetchMessages(matchId: String, before: Date?, limit: Int) async throws -> [Message]
    /// POST /v1/matches/:id/messages
    func sendMessage(matchId: String, text: String, clientId: String) async throws -> Message
    /// POST /v1/matches/:id/read
    func markRead(matchId: String) async throws
    /// POST /v1/reports
    func report(_ report: ReportRequest) async throws
    /// POST /v1/blocks
    func block(userId: String) async throws
    /// POST /v1/moderation/frame
    func moderateFrame(dateId: String, jpegData: Data) async throws -> ModerationAction
    /// POST /v1/moderation/transcript
    func moderateTranscript(dateId: String, text: String) async throws -> ModerationAction
    /// POST /v1/iap/verify
    func verifyPurchase(jwsTransaction: String) async throws -> PremiumStatus
    /// GET /health
    func health() async throws -> Bool
}
