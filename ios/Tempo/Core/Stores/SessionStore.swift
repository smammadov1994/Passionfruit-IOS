import Foundation
import Observation
import UIKit

enum AuthState: String, Sendable, Equatable {
    /// Checking the stored token. If `SessionStore.lastError` is set, the check failed: offer retry (`bootstrap()`).
    case loading
    case signedOut
    case signedIn
}

/// Auth, the current user and onboarding.
@MainActor
@Observable
final class SessionStore {
    private(set) var authState: AuthState
    private(set) var user: User?
    /// Onboarding answers being edited. Bind fields directly: `$session.draft.firstName` via `@Bindable`.
    var draft: OnboardingDraft = OnboardingDraft()
    /// True while signing in, submitting onboarding, saving profile or preferences, or deleting the account.
    private(set) var isWorking: Bool = false
    private(set) var isUploadingPhoto: Bool = false
    private(set) var isLocating: Bool = false
    /// The latest failure, already user-presentable (`lastError?.userMessage`). Set to nil to dismiss.
    var lastError: TempoError?
    /// Set when the server suspends the account (`account.suspended`). Cleared when a later
    /// `GET /v1/me` (`refreshUser()`) shows the account is no longer suspended.
    private(set) var suspension: AccountSuspended?

    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let socket: any RealtimeSocket
    @ObservationIgnored private let location: any LocationService
    @ObservationIgnored private let push: any PushService
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var lastSentTimeZoneOffset: Int?

    /// Wired by `AppEnvironment`.
    @ObservationIgnored var onSignedIn: (@MainActor () -> Void)?
    @ObservationIgnored var onSignedOut: (@MainActor () -> Void)?

    init(
        api: any APIClient,
        auth: any AuthService,
        tokenStore: any TokenStore,
        socket: any RealtimeSocket,
        location: any LocationService,
        push: any PushService,
        initialUser: User? = nil
    ) {
        self.api = api
        self.auth = auth
        self.tokenStore = tokenStore
        self.socket = socket
        self.location = location
        self.push = push
        self.authState = (initialUser == nil) ? .loading : .signedIn
        self.user = initialUser
        if let initialUser {
            draft.firstName = initialUser.firstName
        }
        startListening()
    }

    // MARK: Derived

    var isSignedIn: Bool { authState == .signedIn }
    var isOnboardingComplete: Bool { user?.onboardingComplete ?? false }
    var isPremium: Bool { user?.isPremium ?? false }
    var userId: String? { user?.id }
    /// Whether to offer dev sign-in (demo mode and Debug builds).
    var supportsDevSignIn: Bool { auth.supportsDevSignIn }
    var isSuspended: Bool {
        if let suspension {
            // A timed suspension that has run out no longer counts; an open-ended one does.
            guard let until = suspension.until else { return true }
            if until > Date() { return true }
        }
        return user?.isSuspended ?? false
    }

    // MARK: Launch

    /// Restores the session from the stored token. Call once at launch, and again to retry after a failure.
    func bootstrap() async {
        if authState == .signedIn {
            socket.connect()
            return
        }
        lastError = nil
        guard let token = tokenStore.token, !token.isEmpty else {
            authState = .signedOut
            return
        }
        authState = .loading
        do {
            let fetched: User = try await api.fetchMe()
            completeSignIn(fetched)
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                tokenStore.clear()
                authState = .signedOut
            } else {
                lastError = mapped
            }
        }
    }

    // MARK: Sign in

    func signInWithApple() async {
        await signIn {
            try await self.auth.signInWithApple()
        }
    }

    /// Dev auth (`POST /v1/auth/dev`). Only offered when `supportsDevSignIn` is true.
    func signInDev() async {
        await signIn {
            try await self.auth.signInDev()
        }
    }

    private func signIn(_ operation: @MainActor () async throws -> AuthResponse) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let response: AuthResponse = try await operation()
            tokenStore.save(response.token)
            completeSignIn(response.user)
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped != .cancelled {
                lastError = mapped
            }
        }
    }

    private func completeSignIn(_ signedInUser: User) {
        user = signedInUser
        suspension = nil
        if draft.firstName.isEmpty {
            draft.firstName = signedInUser.firstName
        }
        authState = .signedIn
        socket.connect()
        onSignedIn?()
        let notify: Bool = signedInUser.preferences.notifyOnlineSingles
        let push: any PushService = self.push
        Task {
            await push.sync(enabled: notify)
        }
        Task { [weak self] in
            await self?.syncTimeZone()
        }
    }

    /// Tells the server the device's UTC offset (`PUT /v1/me {tzOffsetMinutes}`) so the free daily
    /// cap resets at local midnight even when notifications are off. Sent only when it changed.
    func syncTimeZone() async {
        guard isSignedIn else { return }
        let offset: Int = TimeZone.current.secondsFromGMT() / 60
        guard offset != lastSentTimeZoneOffset else { return }
        do {
            let updated: User = try await api.updateMe(ProfileUpdate(tzOffsetMinutes: offset))
            lastSentTimeZoneOffset = offset
            if isSignedIn {
                user = updated
            }
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                handle(mapped)
            }
        }
    }

    // MARK: Onboarding

    /// Sends the draft (profile, then preferences). Returns true when onboarding is complete.
    @discardableResult
    func submitOnboarding() async -> Bool {
        guard !isWorking else { return false }
        if let problem = draft.validationMessage {
            lastError = .unknown(problem)
            return false
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            var updated: User = try await api.updateMe(draft.makeProfileUpdate())
            let preferences: Preferences = try await api.updatePreferences(draft.makePreferences(base: updated.preferences))
            updated.preferences = preferences
            user = updated
            if draft.notifyOnlineSingles {
                let granted: Bool = await push.requestAuthorization()
                await push.sync(enabled: granted)
            }
            if !updated.onboardingComplete {
                lastError = .unknown(String(localized: "Your profile is missing something. Check your details and try again."))
                return false
            }
            return true
        } catch {
            handle(TempoError.from(error))
            return false
        }
    }

    // MARK: Profile

    /// `PUT /v1/me` with the non-nil fields of `update`.
    @discardableResult
    func updateProfile(_ update: ProfileUpdate) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let updated: User = try await api.updateMe(update)
            user = updated
            return true
        } catch {
            handle(TempoError.from(error))
            return false
        }
    }

    /// `PUT /v1/me/preferences`. Advanced filters are ignored by the server unless Premium.
    @discardableResult
    func updatePreferences(_ preferences: Preferences) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let saved: Preferences = try await api.updatePreferences(preferences)
            user?.preferences = saved
            await push.sync(enabled: saved.notifyOnlineSingles)
            return true
        } catch {
            handle(TempoError.from(error))
            return false
        }
    }

    /// Turns the "N compatible singles are online" push on or off. Asks for notification permission
    /// when turning it on; returns false (with `lastError`) when permission is denied or saving fails.
    @discardableResult
    func setNotifyOnlineSingles(_ enabled: Bool) async -> Bool {
        guard var preferences = user?.preferences else { return false }
        if enabled {
            let granted: Bool = await push.requestAuthorization()
            if !granted {
                lastError = .permissionDenied(.notifications)
                return false
            }
        }
        preferences.notifyOnlineSingles = enabled
        return await updatePreferences(preferences)
    }

    /// Uploads a JPEG. During onboarding the URL is appended to `draft.photoUrls`;
    /// afterwards it is appended to the user's photos. Returns the URL, or nil on failure.
    @discardableResult
    func uploadPhoto(jpegData: Data) async -> String? {
        guard !isUploadingPhoto else { return nil }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let url: String = try await api.uploadPhoto(jpegData: jpegData)
            if isOnboardingComplete, user != nil {
                // The server has already appended the photo to the profile.
                let refreshed: User? = try? await api.fetchMe()
                if let refreshed {
                    user = refreshed
                } else {
                    var urls: [String] = user?.photoUrls ?? []
                    if !urls.contains(url) {
                        urls.append(url)
                    }
                    user?.photoUrls = urls
                }
            } else {
                draft.photoUrls.append(url)
            }
            return url
        } catch {
            handle(TempoError.from(error))
            return nil
        }
    }

    /// Scales and encodes a picked image, then uploads it.
    @discardableResult
    func uploadPhoto(image: UIImage) async -> String? {
        guard let data = ImageEncoding.jpegData(from: image) else {
            lastError = .unknown(String(localized: "Couldn't read that photo. Try another one."))
            return nil
        }
        return await uploadPhoto(jpegData: data)
    }

    /// Removes a photo (from the draft during onboarding, from the profile afterwards).
    @discardableResult
    func removePhoto(url: String) async -> Bool {
        if isOnboardingComplete, let current = user {
            let urls: [String] = current.photoUrls.filter { $0 != url }
            return await updateProfile(ProfileUpdate(photoUrls: urls))
        }
        draft.photoUrls.removeAll(where: { $0 == url })
        return true
    }

    /// Saves a new photo order. The first photo is the one partners see.
    @discardableResult
    func setPhotoOrder(_ urls: [String]) async -> Bool {
        if isOnboardingComplete {
            return await updateProfile(ProfileUpdate(photoUrls: urls))
        }
        draft.photoUrls = urls
        return true
    }

    /// One-shot location. During onboarding it fills `draft.city/lat/lng`; afterwards it saves to the profile.
    /// Returns false (with `lastError`) when location is denied or unavailable.
    @discardableResult
    func detectLocation() async -> Bool {
        guard !isLocating else { return false }
        isLocating = true
        defer { isLocating = false }
        do {
            let resolved: ResolvedLocation = try await location.currentLocation()
            if isOnboardingComplete {
                var update = ProfileUpdate(lat: resolved.lat, lng: resolved.lng)
                if !resolved.city.isEmpty {
                    update.city = resolved.city
                }
                let updated: User = try await api.updateMe(update)
                user = updated
            } else {
                draft.lat = resolved.lat
                draft.lng = resolved.lng
                if !resolved.city.isEmpty {
                    draft.city = resolved.city
                }
            }
            return true
        } catch {
            handle(TempoError.from(error))
            return false
        }
    }

    /// Re-fetches `GET /v1/me`. Returns false when the request failed (nothing changed).
    ///
    /// The fetched user is the authority on suspension: when it is not suspended, a suspension
    /// that was pushed over the socket is lifted too, so "Check again" on the paused screen works
    /// for both kinds. If the server still considers the account suspended it says so again
    /// (`account.suspended`) on the next socket connect and on every `queue.join`.
    @discardableResult
    func refreshUser() async -> Bool {
        guard isSignedIn else { return false }
        do {
            let fetched: User = try await api.fetchMe()
            guard isSignedIn else { return false }
            user = fetched
            if !fetched.isSuspended {
                suspension = nil
            }
            return true
        } catch {
            let mapped: TempoError = TempoError.from(error)
            if mapped == .notAuthenticated {
                handle(mapped)
            }
            return false
        }
    }

    /// Applies the result of `POST /v1/iap/verify`. Called by `PremiumStore`.
    func applyPremium(_ status: PremiumStatus) {
        user?.isPremium = status.isPremium
        user?.premiumExpiresAt = status.premiumExpiresAt
    }

    // MARK: Leaving

    func signOut() async {
        await push.sync(enabled: false)
        clearSession()
    }

    /// `DELETE /v1/me`, then signs out locally. Returns false (with `lastError`) on failure.
    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            clearSession()
            return true
        } catch {
            handle(TempoError.from(error))
            return false
        }
    }

    private func clearSession() {
        tokenStore.clear()
        socket.disconnect()
        user = nil
        suspension = nil
        draft = OnboardingDraft()
        lastError = nil
        lastSentTimeZoneOffset = nil
        authState = .signedOut
        onSignedOut?()
    }

    // MARK: Errors and realtime

    /// Central place for API failures. An expired token signs the user out; everything else is surfaced.
    /// Other stores route their failures through here too.
    func handle(_ error: TempoError) {
        switch error {
        case .cancelled:
            break
        case .notAuthenticated:
            if authState == .signedIn {
                clearSession()
            }
            lastError = error
        default:
            lastError = error
        }
    }

    /// Records a suspension pushed over the socket. Called by `DateStore` as well.
    func markSuspended(_ info: AccountSuspended) {
        suspension = info
        user?.suspendedUntil = info.until ?? Date.distantFuture
    }

    private func startListening() {
        let stream: AsyncStream<ServerMessage> = socket.messages()
        listenTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                if case .accountSuspended(let info) = message {
                    self.markSuspended(info)
                }
            }
        }
    }
}
