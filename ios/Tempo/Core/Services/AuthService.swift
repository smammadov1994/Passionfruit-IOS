import AuthenticationServices
import Foundation
import UIKit

/// Signs the user in and returns the API token plus the user. `SessionStore` stores the token.
@MainActor
protocol AuthService: AnyObject {
    /// True when dev sign-in (dev auth) should be offered: demo mode and Debug builds.
    var supportsDevSignIn: Bool { get }
    func signInWithApple() async throws -> AuthResponse
    func signInDev() async throws -> AuthResponse
}

@MainActor
final class LiveAuthService: NSObject, AuthService {
    private let api: any APIClient
    private let keychain: KeychainStore
    private var continuation: CheckedContinuation<AppleCredential, Error>?

    private struct AppleCredential: Sendable {
        var identityToken: String
        var firstName: String?
    }

    init(api: any APIClient, keychain: KeychainStore = KeychainStore()) {
        self.api = api
        self.keychain = keychain
        super.init()
    }

    var supportsDevSignIn: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func signInWithApple() async throws -> AuthResponse {
        if continuation != nil {
            throw TempoError.cancelled
        }
        let credential: AppleCredential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleCredential, Error>) in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        return try await api.signInWithApple(identityToken: credential.identityToken, firstName: credential.firstName)
    }

    func signInDev() async throws -> AuthResponse {
        let key: String = "dev.deviceId"
        var deviceId: String = keychain.string(forKey: key) ?? ""
        if deviceId.isEmpty {
            deviceId = UUID().uuidString.lowercased()
            keychain.set(deviceId, forKey: key)
        }
        return try await api.signInDev(deviceId: deviceId)
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let credential):
            continuation.resume(returning: credential)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension LiveAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        var result: Result<AppleCredential, Error> = .failure(TempoError.unknown(String(localized: "Sign in with Apple didn't return a credential. Try again.")))
        if let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
           let tokenData = apple.identityToken,
           let token = String(data: tokenData, encoding: .utf8) {
            result = .success(AppleCredential(identityToken: token, firstName: apple.fullName?.givenName))
        }
        let finalResult: Result<AppleCredential, Error> = result
        Task { @MainActor in
            self.finish(finalResult)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        var mapped: TempoError = .unknown(String(localized: "Sign in with Apple didn't work. Try again."))
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            mapped = .cancelled
        }
        let finalError: TempoError = mapped
        Task { @MainActor in
            self.finish(.failure(finalError))
        }
    }
}

extension LiveAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // AuthenticationServices calls this on the main thread.
        MainActor.assumeIsolated {
            LiveAuthService.keyWindow() ?? ASPresentationAnchor()
        }
    }

    private static func keyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return key
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene, let first = windowScene.windows.first {
                return first
            }
        }
        return nil
    }
}

/// Demo-mode auth: both buttons sign in to the in-memory backend.
@MainActor
final class MockAuthService: AuthService {
    private let api: any APIClient

    init(api: any APIClient) {
        self.api = api
    }

    var supportsDevSignIn: Bool { true }

    func signInWithApple() async throws -> AuthResponse {
        try await api.signInWithApple(identityToken: "demo-identity-token", firstName: nil)
    }

    func signInDev() async throws -> AuthResponse {
        try await api.signInDev(deviceId: "demo-device")
    }
}
