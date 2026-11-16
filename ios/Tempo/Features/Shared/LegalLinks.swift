import Foundation

/// Every external link the app opens lives here. The pages are part of the launch site (`site/`).
enum LegalLinks {
    static let privacyPolicy: String = "https://passionfruitdating.com/privacy"
    static let terms: String = "https://passionfruitdating.com/terms"
    static let communityGuidelines: String = "https://passionfruitdating.com/community"
    static let support: String = "https://passionfruitdating.com/support"
    /// Apple's page for managing App Store subscriptions.
    static let manageSubscription: String = "https://apps.apple.com/account/subscriptions"

    static var privacyPolicyURL: URL? { URL(string: privacyPolicy) }
    static var termsURL: URL? { URL(string: terms) }
    static var communityGuidelinesURL: URL? { URL(string: communityGuidelines) }
    static var supportURL: URL? { URL(string: support) }
    static var manageSubscriptionURL: URL? { URL(string: manageSubscription) }
}
