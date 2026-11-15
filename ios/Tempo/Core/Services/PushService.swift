import Foundation
import UIKit
import UserNotifications

enum PushAuthorizationStatus: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// "N compatible singles are online now" pushes: permission, APNs token, and the opt-in flag on the server.
@MainActor
protocol PushService: AnyObject {
    func authorizationStatus() async -> PushAuthorizationStatus
    /// Shows the system prompt when needed, then registers with APNs. Returns whether pushes are allowed.
    func requestAuthorization() async -> Bool
    /// Called by the app delegate with the APNs device token.
    func didRegister(deviceToken: Data) async
    /// Uploads the stored token with the given opt-in flag. No-op until a token exists and the user is signed in.
    func sync(enabled: Bool) async
}

@MainActor
final class LivePushService: PushService {
    private let api: any APIClient
    private let tokenStore: any TokenStore
    private let defaults: UserDefaults
    private let tokenKey: String = "tempo.push.apnsToken"
    private let enabledKey: String = "tempo.push.enabled"

    init(api: any APIClient, tokenStore: any TokenStore, defaults: UserDefaults = UserDefaults.standard) {
        self.api = api
        self.tokenStore = tokenStore
        self.defaults = defaults
    }

    func authorizationStatus() async -> PushAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        var granted: Bool = false
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    func didRegister(deviceToken: Data) async {
        let hex: String = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(hex, forKey: tokenKey)
        let enabled: Bool = defaults.bool(forKey: enabledKey)
        await upload(enabled: enabled)
    }

    func sync(enabled: Bool) async {
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            let status: PushAuthorizationStatus = await authorizationStatus()
            if status == .authorized {
                // Refreshes the token; the upload happens in `didRegister(deviceToken:)` too.
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        await upload(enabled: enabled)
    }

    private func upload(enabled: Bool) async {
        guard let apnsToken = defaults.string(forKey: tokenKey), !apnsToken.isEmpty else { return }
        guard let authToken = tokenStore.token, !authToken.isEmpty else { return }
        let offset: Int = TimeZone.current.secondsFromGMT() / 60
        do {
            try await api.registerPushToken(apnsToken: apnsToken, tzOffsetMinutes: offset, enabled: enabled)
        } catch {
            // Retried on the next launch, sign-in or preference change.
        }
    }
}

@MainActor
final class MockPushService: PushService {
    var status: PushAuthorizationStatus
    private(set) var lastSyncedEnabled: Bool?

    init(status: PushAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    func authorizationStatus() async -> PushAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> Bool {
        if status == .notDetermined {
            status = .authorized
        }
        return status == .authorized
    }

    func didRegister(deviceToken: Data) async {}

    func sync(enabled: Bool) async {
        lastSyncedEnabled = enabled
    }
}
