import Foundation

final class LiveAPIClient: APIClient, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let maxGetAttempts: Int = 3

    init(baseURL: URL, tokenProvider: @escaping @Sendable () -> String?, session: URLSession = LiveAPIClient.makeSession()) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: Auth

    func signInWithApple(identityToken: String, firstName: String?) async throws -> AuthResponse {
        let body = try encodeBody(AppleAuthRequest(identityToken: identityToken, firstName: firstName))
        let data = try await perform(method: "POST", path: "/v1/auth/apple", query: [], body: body, authorized: false)
        return try decodeResponse(AuthResponse.self, from: data)
    }

    func signInDev(deviceId: String) async throws -> AuthResponse {
        let body = try encodeBody(DevAuthRequest(deviceId: deviceId))
        let data = try await perform(method: "POST", path: "/v1/auth/dev", query: [], body: body, authorized: false)
        return try decodeResponse(AuthResponse.self, from: data)
    }

    // MARK: Config and profile

    func fetchConfig() async throws -> AppConfig {
        // Public route, but TURN credentials are only included for a signed-in caller.
        let hasToken: Bool = !(tokenProvider() ?? "").isEmpty
        let data = try await perform(method: "GET", path: "/v1/config", query: [], body: nil, authorized: hasToken)
        return try decodeResponse(AppConfig.self, from: data)
    }

    func fetchMe() async throws -> User {
        let data = try await perform(method: "GET", path: "/v1/me", query: [], body: nil, authorized: true)
        return try decodeResponse(User.self, from: data)
    }

    func updateMe(_ update: ProfileUpdate) async throws -> User {
        let body = try encodeBody(update)
        let data = try await perform(method: "PUT", path: "/v1/me", query: [], body: body, authorized: true)
        return try decodeResponse(User.self, from: data)
    }

    func updatePreferences(_ preferences: Preferences) async throws -> Preferences {
        let body = try encodeBody(preferences)
        let data = try await perform(method: "PUT", path: "/v1/me/preferences", query: [], body: body, authorized: true)
        return try decodeResponse(Preferences.self, from: data)
    }

    func uploadPhoto(jpegData: Data) async throws -> String {
        let body = try encodeBody(PhotoUploadRequest(imageBase64: jpegData.base64EncodedString()))
        let data = try await perform(method: "POST", path: "/v1/me/photos", query: [], body: body, authorized: true)
        return try decodeResponse(PhotoUploadResponse.self, from: data).url
    }

    func registerPushToken(apnsToken: String, tzOffsetMinutes: Int, enabled: Bool) async throws {
        let body = try encodeBody(PushTokenRequest(apnsToken: apnsToken, tzOffsetMinutes: tzOffsetMinutes, enabled: enabled))
        _ = try await perform(method: "POST", path: "/v1/me/push-token", query: [], body: body, authorized: true)
    }

    func deleteAccount() async throws {
        _ = try await perform(method: "DELETE", path: "/v1/me", query: [], body: nil, authorized: true)
    }

    func fetchUsage() async throws -> Usage {
        let data = try await perform(method: "GET", path: "/v1/usage", query: [], body: nil, authorized: true)
        return try decodeResponse(Usage.self, from: data)
    }

    func fetchOnlineCount() async throws -> Int {
        let data = try await perform(method: "GET", path: "/v1/online-count", query: [], body: nil, authorized: true)
        return try decodeResponse(OnlineCountResponse.self, from: data).compatibleOnline
    }

    // MARK: Matches and chat

    func fetchMatches() async throws -> [Match] {
        let data = try await perform(method: "GET", path: "/v1/matches", query: [], body: nil, authorized: true)
        return try decodeResponse(MatchesResponse.self, from: data).matches
    }

    func unmatch(matchId: String) async throws {
        _ = try await perform(method: "DELETE", path: "/v1/matches/\(matchId)", query: [], body: nil, authorized: true)
    }

    func fetchMessages(matchId: String, before: Date?, limit: Int) async throws -> [Message] {
        var query: [URLQueryItem] = []
        if let before {
            query.append(URLQueryItem(name: "before", value: TempoJSON.string(from: before)))
        }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        let data = try await perform(method: "GET", path: "/v1/matches/\(matchId)/messages", query: query, body: nil, authorized: true)
        return try decodeResponse(MessagesResponse.self, from: data).messages
    }

    func sendMessage(matchId: String, text: String, clientId: String) async throws -> Message {
        let body = try encodeBody(SendMessageRequest(text: text, clientId: clientId))
        let data = try await perform(method: "POST", path: "/v1/matches/\(matchId)/messages", query: [], body: body, authorized: true)
        return try decodeResponse(Message.self, from: data)
    }

    func markRead(matchId: String) async throws {
        _ = try await perform(method: "POST", path: "/v1/matches/\(matchId)/read", query: [], body: nil, authorized: true)
    }

    // MARK: Safety

    func report(_ report: ReportRequest) async throws {
        let body = try encodeBody(report)
        _ = try await perform(method: "POST", path: "/v1/reports", query: [], body: body, authorized: true)
    }

    func block(userId: String) async throws {
        let body = try encodeBody(BlockRequest(userId: userId))
        _ = try await perform(method: "POST", path: "/v1/blocks", query: [], body: body, authorized: true)
    }

    func moderateFrame(dateId: String, jpegData: Data) async throws -> ModerationAction {
        let body = try encodeBody(ModerationFrameRequest(dateId: dateId, imageBase64: jpegData.base64EncodedString()))
        let data = try await perform(method: "POST", path: "/v1/moderation/frame", query: [], body: body, authorized: true)
        return try decodeResponse(ModerationResponse.self, from: data).action
    }

    func moderateTranscript(dateId: String, text: String) async throws -> ModerationAction {
        let body = try encodeBody(ModerationTranscriptRequest(dateId: dateId, text: text))
        let data = try await perform(method: "POST", path: "/v1/moderation/transcript", query: [], body: body, authorized: true)
        return try decodeResponse(ModerationResponse.self, from: data).action
    }

    // MARK: Purchases and health

    func verifyPurchase(jwsTransaction: String) async throws -> PremiumStatus {
        let body = try encodeBody(VerifyPurchaseRequest(jwsTransaction: jwsTransaction))
        let data = try await perform(method: "POST", path: "/v1/iap/verify", query: [], body: body, authorized: true)
        return try decodeResponse(PremiumStatus.self, from: data)
    }

    func health() async throws -> Bool {
        let data = try await perform(method: "GET", path: "/health", query: [], body: nil, authorized: false)
        return try decodeResponse(HealthResponse.self, from: data).ok
    }

    // MARK: Plumbing

    private func encodeBody<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try TempoJSON.makeEncoder().encode(body)
        } catch {
            throw TempoError.unknown("")
        }
    }

    private func decodeResponse<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try TempoJSON.makeDecoder().decode(type, from: data)
        } catch {
            throw TempoError.decoding
        }
    }

    private func makeRequest(method: String, path: String, query: [URLQueryItem], body: Data?, authorized: Bool) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw TempoError.unknown("")
        }
        var basePath: String = components.path
        if basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw TempoError.unknown("")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = tokenProvider(), !token.isEmpty else {
                throw TempoError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Runs the request. Idempotent GETs are retried with exponential backoff on network errors, 5xx and 429.
    private func perform(method: String, path: String, query: [URLQueryItem], body: Data?, authorized: Bool) async throws -> Data {
        let request = try makeRequest(method: method, path: path, query: query, body: body, authorized: authorized)
        let attempts: Int = (method == "GET") ? maxGetAttempts : 1
        var attempt: Int = 0
        while true {
            attempt += 1
            let outcome: Result<Data, TempoError> = await performOnce(request)
            switch outcome {
            case .success(let data):
                return data
            case .failure(let error):
                if error == .cancelled {
                    throw error
                }
                if attempt < attempts && LiveAPIClient.shouldRetry(error) {
                    try await LiveAPIClient.backoff(attempt: attempt)
                    continue
                }
                throw error
            }
        }
    }

    private func performOnce(_ request: URLRequest) async -> Result<Data, TempoError> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network)
            }
            if (200..<300).contains(http.statusCode) {
                return .success(data)
            }
            return .failure(LiveAPIClient.mapError(status: http.statusCode, data: data))
        } catch {
            return .failure(TempoError.from(error))
        }
    }

    private static func shouldRetry(_ error: TempoError) -> Bool {
        switch error {
        case .network:
            return true
        case .server(let status, _, _):
            return status >= 500 || status == 429
        default:
            return false
        }
    }

    private static func backoff(attempt: Int) async throws {
        let base: Double = 0.4 * pow(2.0, Double(attempt - 1))
        let jitter: Double = Double.random(in: 0...0.25)
        let nanoseconds = UInt64((base + jitter) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    static func mapError(status: Int, data: Data) -> TempoError {
        var code: String = "http_\(status)"
        var message: String = ""
        if let envelope = try? TempoJSON.makeDecoder().decode(APIErrorEnvelope.self, from: data) {
            code = envelope.error.code
            message = envelope.error.message
        }
        if status == 401 && code != "invalid_identity_token" {
            return .notAuthenticated
        }
        if status == 403 && code.lowercased().contains("suspend") {
            return .suspended(until: nil)
        }
        return .server(status: status, code: code, message: message)
    }
}
