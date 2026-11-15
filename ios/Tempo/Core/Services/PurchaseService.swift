import Foundation
import StoreKit

/// What the paywall shows. Comes from StoreKit, never hardcoded in UI.
struct PremiumProduct: Sendable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var description: String
    /// Localised price, e.g. "$14.99".
    var displayPrice: String
    /// Localised billing period, e.g. "month".
    var periodLabel: String

    /// "$14.99 / month"
    var priceLine: String {
        "\(displayPrice) / \(periodLabel)"
    }
}

enum PurchaseOutcome: Sendable, Equatable {
    /// The App Store accepted the purchase. `jws` goes to `POST /v1/iap/verify`.
    case purchased(jws: String)
    /// Waiting for approval (Ask to Buy, bank confirmation).
    case pending
    case cancelled
}

enum PremiumProductID {
    static let monthly: String = "tempo.premium.monthly"
}

@MainActor
protocol PurchaseService: AnyObject {
    /// The signed-in user's id as a UUID. Attached to purchases so a renewal can find the account.
    var appAccountToken: UUID? { get set }
    func loadProduct() async throws -> PremiumProduct
    func purchase() async throws -> PurchaseOutcome
    /// Syncs with the App Store, then returns the JWS of an active entitlement, if any.
    func restore() async throws -> String?
    /// JWS of an active entitlement already on this device, if any.
    func currentEntitlement() async -> String?
    /// JWS of every verified transaction that arrives outside a purchase (renewals, Ask to Buy approvals).
    func transactionUpdates() -> AsyncStream<String>
}

@MainActor
final class LivePurchaseService: PurchaseService {
    var appAccountToken: UUID?
    private var product: Product?
    private var updatesTask: Task<Void, Never>?
    private let hub = Broadcaster<String>()

    init() {
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handleUpdate(update)
            }
        }
    }

    func loadProduct() async throws -> PremiumProduct {
        let storeProduct: Product = try await ensureProduct()
        return LivePurchaseService.describe(storeProduct)
    }

    func purchase() async throws -> PurchaseOutcome {
        let storeProduct: Product = try await ensureProduct()
        let result: Product.PurchaseResult
        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(Product.PurchaseOption.appAccountToken(appAccountToken))
            }
            result = try await storeProduct.purchase(options: options)
        } catch {
            throw TempoError.purchaseFailed("")
        }
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let jws: String = verification.jwsRepresentation
                await transaction.finish()
                return .purchased(jws: jws)
            case .unverified:
                throw TempoError.purchaseFailed(String(localized: "The App Store couldn't verify this purchase. You haven't been charged twice. Try Restore purchases."))
            }
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws -> String? {
        do {
            try await AppStore.sync()
        } catch {
            throw TempoError.purchaseFailed(String(localized: "Couldn't reach the App Store. Try again."))
        }
        return await currentEntitlement()
    }

    func currentEntitlement() async -> String? {
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == PremiumProductID.monthly && transaction.revocationDate == nil {
                    return result.jwsRepresentation
                }
            case .unverified:
                continue
            }
        }
        return nil
    }

    func transactionUpdates() -> AsyncStream<String> {
        hub.stream()
    }

    private func ensureProduct() async throws -> Product {
        if let product {
            return product
        }
        let products: [Product]
        do {
            products = try await Product.products(for: [PremiumProductID.monthly])
        } catch {
            throw TempoError.purchaseFailed(String(localized: "Couldn't reach the App Store. Try again."))
        }
        guard let first = products.first else {
            throw TempoError.purchaseFailed(String(localized: "\(Brand.premiumName) isn't available right now."))
        }
        product = first
        return first
    }

    private func handleUpdate(_ update: VerificationResult<StoreKit.Transaction>) async {
        switch update {
        case .verified(let transaction):
            if transaction.productID == PremiumProductID.monthly {
                hub.yield(update.jwsRepresentation)
            }
            await transaction.finish()
        case .unverified:
            break
        }
    }

    private static func describe(_ product: Product) -> PremiumProduct {
        var period: String = String(localized: "month")
        if let subscription = product.subscription {
            let unit = subscription.subscriptionPeriod.unit
            let value: Int = subscription.subscriptionPeriod.value
            let unitName: String
            switch unit {
            case .day:
                unitName = value == 1 ? String(localized: "day") : String(localized: "days")
            case .week:
                unitName = value == 1 ? String(localized: "week") : String(localized: "weeks")
            case .month:
                unitName = value == 1 ? String(localized: "month") : String(localized: "months")
            case .year:
                unitName = value == 1 ? String(localized: "year") : String(localized: "years")
            @unknown default:
                unitName = String(localized: "month")
            }
            period = value == 1 ? unitName : "\(value) \(unitName)"
        }
        return PremiumProduct(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice,
            periodLabel: period
        )
    }
}

/// Demo-mode store: the product loads instantly and every purchase succeeds.
@MainActor
final class MockPurchaseService: PurchaseService {
    var appAccountToken: UUID?
    /// Set to make `purchase()` return something else (for previews of pending or cancelled states).
    var nextOutcome: PurchaseOutcome = .purchased(jws: "demo-jws-transaction")
    var hasEntitlement: Bool = false

    private let hub = Broadcaster<String>()

    init() {}

    func loadProduct() async throws -> PremiumProduct {
        try await Task.sleep(nanoseconds: 300_000_000)
        return PremiumProduct(
            id: PremiumProductID.monthly,
            displayName: Brand.premiumName,
            description: String(localized: "Unlimited dates, dealbreaker filters and priority in the queue."),
            displayPrice: "$14.99",
            periodLabel: String(localized: "month")
        )
    }

    func purchase() async throws -> PurchaseOutcome {
        try await Task.sleep(nanoseconds: 900_000_000)
        if case .purchased = nextOutcome {
            hasEntitlement = true
        }
        return nextOutcome
    }

    func restore() async throws -> String? {
        try await Task.sleep(nanoseconds: 600_000_000)
        return hasEntitlement ? "demo-jws-transaction" : nil
    }

    func currentEntitlement() async -> String? {
        hasEntitlement ? "demo-jws-transaction" : nil
    }

    func transactionUpdates() -> AsyncStream<String> {
        hub.stream()
    }
}
