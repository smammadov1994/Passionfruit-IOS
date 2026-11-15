import Foundation

/// Every external link the app opens lives here. The https URLs are placeholders until the real
/// pages exist; replace them in this one place.
enum LegalLinks {
    static let privacyPolicy: String = "https://tempo.example/privacy"
    static let terms: String = "https://tempo.example/terms"
    static let communityGuidelines: String = "https://tempo.example/community"
    static let support: String = "https://tempo.example/support"
    /// Apple's page for managing App Store subscriptions.
    static let manageSubscription: String = "https://apps.apple.com/account/subscriptions"

    static var privacyPolicyURL: URL? { URL(string: privacyPolicy) }
    static var termsURL: URL? { URL(string: terms) }
    static var communityGuidelinesURL: URL? { URL(string: communityGuidelines) }
    static var supportURL: URL? { URL(string: support) }
    static var manageSubscriptionURL: URL? { URL(string: manageSubscription) }
}
