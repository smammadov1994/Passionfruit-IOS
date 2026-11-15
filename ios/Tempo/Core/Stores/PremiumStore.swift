import Foundation
import Observation

enum PurchaseState: Sendable, Equatable {
    case idle
    case purchasing
    case restoring
    /// The App Store is waiting for approval (Ask to Buy). Premium unlocks by itself when approved.
    case pending
    /// Premium is active. Show a short confirmation, then close the paywall.
    case success
    case failed(TempoError)
}

/// Tempo Premium: the product, the purchase flow and the entitlement.
@MainActor
@Observable
final class PremiumStore {
    /// The subscription as the App Store describes it. nil until `loadProduct()` succeeds.
    private(set) var product: PremiumProduct?
    private(set) var isLoadingProduct: Bool = false
    /// Why the product could not be loaded. Offer retry (`loadProduct()`).
    private(set) var productError: TempoError?
    private(set) var purchaseState: PurchaseState = .idle

    @ObservationIgnored private let purchases: any PurchaseService
    @ObservationIgnored private let api: any APIClient
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(purchases: any PurchaseService, api: any APIClient, session: SessionStore) {
        self.purchases = purchases
        self.api = api
        self.session = session
    }

    // MARK: Derived

    var isPremium: Bool { session.isPremium }
    var premiumExpiresAt: Date? { session.user?.premiumExpiresAt }
    /// True while a purchase or restore is running (disable the buttons).
    var isBusy: Bool {
        purchaseState == .purchasing || purchaseState == .restoring
    }

    // MARK: Lifecycle

    /// Starts listening for renewals and approvals. Call once at launch.
    func start() {
        guard updatesTask == nil else { return }
        let stream: AsyncStream<String> = purchases.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await jws in stream {
                guard let self else { return }
                await self.verifySilently(jws)
            }
        }
    }

    /// Re-checks an entitlement already on this device with the server. Call after sign-in.
    func syncEntitlement() async {
        guard session.isSignedIn else { return }
        if let jws = await purchases.currentEntitlement() {
            await verifySilently(jws)
        }
    }

    // MARK: Intents

    func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        productError = nil
        defer { isLoadingProduct = false }
        do {
            product = try await purchases.loadProduct()
        } catch {
            productError = TempoError.from(error)
        }
    }

    func purchase() async {
        guard !isBusy else { return }
        purchaseState = .purchasing
        purchases.appAccountToken = UUID(uuidString: session.userId ?? "")
        do {
            let outcome: PurchaseOutcome = try await purchases.purchase()
            switch outcome {
            case .purchased(let jws):
                try await verify(jws)
                if session.isPremium {
                    purchaseState = .success
                } else {
                    purchaseState = .failed(TempoError.purchaseFailed(String(localized: "We couldn't confirm your subscription yet. Tap Restore purchases in a moment.")))
                }
            case .pending:
                purchaseState = .pending
            case .cancelled:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(PremiumStore.purchaseError(from: error))
        }
    }

    func restore() async {
        guard !isBusy else { return }
        purchaseState = .restoring
        do {
            let restored: String? = try await purchases.restore()
            guard let jws = restored else {
                purchaseState = .failed(TempoError.purchaseFailed(String(localized: "No active \(Brand.premiumName) subscription was found for this Apple Account.")))
                return
            }
            try await verify(jws)
            if session.isPremium {
                purchaseState = .success
            } else {
                purchaseState = .failed(TempoError.purchaseFailed(String(localized: "That subscription has expired.")))
            }
        } catch {
            purchaseState = .failed(PremiumStore.purchaseError(from: error))
        }
    }

    /// Clears `.success`, `.pending` or `.failed` after it has been shown.
    func resetPurchaseState() {
        if !isBusy {
            purchaseState = .idle
        }
    }

    // MARK: Verification

    private func verify(_ jws: String) async throws {
        let status: PremiumStatus = try await api.verifyPurchase(jwsTransaction: jws)
        session.applyPremium(status)
    }

    private func verifySilently(_ jws: String) async {
        guard session.isSignedIn else { return }
        do {
            try await verify(jws)
            if purchaseState == .pending && session.isPremium {
                purchaseState = .success
            }
        } catch {
            // Tried again on the next launch or sign-in via `syncEntitlement()`.
        }
    }

    private static func purchaseError(from error: Error) -> TempoError {
        let mapped: TempoError = TempoError.from(error)
        switch mapped {
        case .purchaseFailed, .network, .notAuthenticated, .server:
            return mapped
        default:
            return .purchaseFailed("")
        }
    }
}
