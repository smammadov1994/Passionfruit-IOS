import SwiftUI

/// The You tab: profile, who you meet, dealbreakers, notifications, Premium and the account.
struct YouView: View {
    @Environment(AppRouter.self) private var router

    init() {}

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.youPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    IconCircleButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: String(localized: "Back to Matches"),
                        kind: IconCircleButtonKind.outlined,
                        size: 44,
                        action: { router.select(AppTab.matches) }
                    )
                    .padding(.bottom, -TempoSpacing.md)
                    YouProfileHeader()
                    YouDiscoverySection()
                    YouDealbreakersSection()
                    YouNotificationsSection()
                    YouPremiumSection()
                    YouAccountSection()
                    YouFooter()
                }
                .tempoScreenPadding()
                .padding(.top, TempoSpacing.xs)
                .padding(.bottom, TempoSpacing.lg)
            }
            .inkBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: YouDestination.self) { destination in
                YouDestinationView(destination: destination)
            }
        }
    }
}

/// Resolves a pushed destination of the You tab.
private struct YouDestinationView: View {
    let destination: YouDestination

    var body: some View {
        switch destination {
        case .editProfile:
            EditProfileView()
        case .dealbreaker(let kind):
            DealbreakerEditor(kind: kind)
        case .communityRules:
            CommunityRulesScreen()
        case .deleteAccount:
            DeleteAccountView()
        }
    }
}

// MARK: - Profile header

private struct YouProfileHeader: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private var nameLine: String {
        guard let user = session.user else { return "" }
        if let age = user.age {
            return "\(user.firstName), \(age)"
        }
        return user.firstName
    }

    private var bio: String {
        (session.user?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .center, spacing: TempoSpacing.md) {
                AvatarView(
                    url: environment.imageCache.resolve(session.user?.primaryPhotoUrl),
                    name: session.user?.firstName ?? "",
                    size: 76,
                    ring: session.isPremium ? AvatarRing.gold : AvatarRing.hairline
                )
                identity
            }
            if !bio.isEmpty {
                Text("“\(bio)”")
                    .tempoText(.serifBody)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TempoButton(
                String(localized: "Edit profile"),
                variant: TempoButtonVariant.secondary,
                size: TempoButtonSize.regular,
                action: { router.youPath.append(YouDestination.editProfile) }
            )
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(nameLine)
                .tempoText(.title)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            if let city = session.user?.city, !city.isEmpty {
                Text(city)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
            }
            if session.isPremium {
                PremiumBadge()
                    .padding(.top, TempoSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Who you meet

/// Age range and distance. Changes save by themselves a moment after the sliders stop moving.
private struct YouDiscoverySection: View {
    @Environment(SessionStore.self) private var session

    private struct Values: Equatable {
        var ageMin: Int
        var ageMax: Int
        var distanceKm: Int
    }

    private static let maximumAge: Int = 99
    private static let maximumDistanceKm: Int = 200

    @State private var values: Values = Values(ageMin: Birthdate.minimumAge, ageMax: 99, distanceKm: 100)
    /// What the save in flight carries; nil when nothing is being saved.
    @State private var lastSent: Values?

    private var savedValues: Values? {
        guard let preferences = session.user?.preferences else { return nil }
        return YouDiscoverySection.clamped(
            Values(ageMin: preferences.ageMin, ageMax: preferences.ageMax, distanceKm: preferences.maxDistanceKm)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Eyebrow(String(localized: "Who you meet"))
            TempoCard(kind: TempoCardKind.raised, padding: TempoSpacing.md) {
                VStack(spacing: TempoSpacing.sm) {
                    RangeSliderRow(
                        title: String(localized: "Age"),
                        lower: $values.ageMin,
                        upper: $values.ageMax,
                        bounds: Birthdate.minimumAge...YouDiscoverySection.maximumAge
                    )
                    TempoDivider()
                    SliderRow(
                        title: String(localized: "Maximum distance"),
                        value: $values.distanceKm,
                        bounds: 1...YouDiscoverySection.maximumDistanceKm,
                        format: TempoSliderFormat.kilometers
                    )
                }
            }
        }
        .onAppear {
            if let saved = savedValues {
                values = saved
            }
        }
        .onChange(of: savedValues) { _, saved in
            adopt(saved)
        }
        .task(id: values) {
            await saveWhenSettled()
        }
    }

    /// Takes the server's values unless the user has moved a slider since the last save was sent.
    private func adopt(_ saved: Values?) {
        guard let saved else { return }
        if lastSent == nil || lastSent == values {
            values = saved
        }
    }

    private func saveWhenSettled() async {
        guard let saved = savedValues, saved != values else { return }
        do {
            try await Task.sleep(for: Duration.milliseconds(600))
        } catch {
            return
        }
        guard var preferences = session.user?.preferences else { return }
        let sending: Values = values
        preferences.ageMin = sending.ageMin
        preferences.ageMax = sending.ageMax
        preferences.maxDistanceKm = sending.distanceKm
        lastSent = sending
        let didSave: Bool = await session.updatePreferences(preferences)
        if Task.isCancelled {
            // A newer value is waiting; its own save follows.
            return
        }
        lastSent = nil
        if let current = savedValues, current != values {
            // Failed (the shell shows why) or adjusted by the server: show what is really saved.
            values = current
        }
        if didSave {
            Haptics.light()
        }
    }

    private static func clamped(_ values: Values) -> Values {
        let low: Int = min(max(values.ageMin, Birthdate.minimumAge), maximumAge - 1)
        let high: Int = min(max(values.ageMax, low + 1), maximumAge)
        let distance: Int = min(max(values.distanceKm, 1), maximumDistanceKm)
        return Values(ageMin: low, ageMax: high, distanceKm: distance)
    }
}

// MARK: - Dealbreakers

private struct YouDealbreakersSection: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    private var caption: String {
        if session.isPremium {
            return String(localized: "You'll only be paired with people who fit. Leave a filter on Any to keep it open.")
        }
        return String(localized: "Only meet people who want what you want. Part of \(Brand.premiumName).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                Eyebrow(String(localized: "Dealbreakers"))
                if !session.isPremium {
                    PremiumBadge(compact: true)
                }
            }
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    ForEach(DealbreakerKind.allCases) { kind in
                        row(kind)
                        if kind != DealbreakerKind.allCases.last {
                            TempoDivider()
                        }
                    }
                }
            }
            Text(caption)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func row(_ kind: DealbreakerKind) -> some View {
        if session.isPremium {
            TempoRow(
                title: kind.title,
                value: DealbreakerSummary.text(for: kind, in: session.user?.preferences ?? Preferences()),
                systemImage: kind.systemImage,
                tile: kind.tile,
                action: { router.youPath.append(YouDestination.dealbreaker(kind)) }
            )
        } else {
            LockedRow(
                title: kind.title,
                systemImage: kind.systemImage,
                tile: kind.tile,
                action: { router.openPaywall() }
            )
        }
    }
}

// MARK: - Notifications

private struct YouNotificationsSection: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router

    /// The value the user just chose, shown until the save settles.
    @State private var pendingValue: Bool?
    @State private var tasks: TaskBag = TaskBag()

    private var isOn: Binding<Bool> {
        Binding<Bool>(
            get: { pendingValue ?? (session.user?.preferences.notifyOnlineSingles ?? false) },
            set: { newValue in change(to: newValue) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Eyebrow(String(localized: "Notifications"))
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                TempoToggleRow(
                    title: String(localized: "Tell me when people are online"),
                    subtitle: String(localized: "At most once every four hours."),
                    systemImage: "bell",
                    tile: TempoPastel.butter,
                    isOn: isOn
                )
                .disabled(pendingValue != nil)
            }
        }
        .onDisappear {
            tasks.cancelAll()
            pendingValue = nil
        }
    }

    private func change(to newValue: Bool) {
        guard pendingValue == nil else { return }
        pendingValue = newValue
        tasks.run("notify") {
            let saved: Bool = await session.setNotifyOnlineSingles(newValue)
            pendingValue = nil
            if Task.isCancelled || !saved {
                // On failure the switch falls back and the shell shows the reason.
                return
            }
            if newValue {
                router.showMessage(String(localized: "We'll tell you when people are online."), systemImage: "bell")
            } else {
                router.showMessage(String(localized: "Notifications are off."), systemImage: "bell.slash")
            }
        }
    }
}

// MARK: - Premium

private struct YouPremiumSection: View {
    @Environment(SessionStore.self) private var session
    @Environment(PremiumStore.self) private var premiumStore
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    private var statusLine: String {
        if let expires = premiumStore.premiumExpiresAt {
            return String(localized: "Active. Your current period runs until \(TempoFormat.longDate(expires)).")
        }
        return String(localized: "Active.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Eyebrow(String(localized: "Premium"))
            if session.isPremium {
                member
            } else {
                upsell
            }
        }
    }

    private var member: some View {
        TempoCard(kind: TempoCardKind.gold, padding: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Brand.premiumName)
                        .tempoText(.titleS)
                        .foregroundStyle(Color.tempo.textPrimary)
                    Spacer(minLength: TempoSpacing.xs)
                    PremiumBadge(compact: true)
                }
                Text(statusLine)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TempoDivider()
                TempoRow(
                    title: String(localized: "Manage subscription"),
                    action: { manageSubscription() }
                )
            }
        }
    }

    private var upsell: some View {
        TempoCard(kind: TempoCardKind.gold, padding: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                (Text("Never run out of ") + Text("evenings.").italic())
                    .tempoText(.titleS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Unlimited dates, dealbreaker filters, and the front of the line.")
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TempoButton(
                    String(localized: "See Premium"),
                    variant: TempoButtonVariant.premium,
                    size: TempoButtonSize.regular,
                    action: { router.openPaywall() }
                )
            }
        }
    }

    private func manageSubscription() {
        if let url = LegalLinks.manageSubscriptionURL {
            openURL(url)
        }
    }
}

// MARK: - Account

private struct YouAccountSection: View {
    @Environment(SessionStore.self) private var session
    @Environment(PremiumStore.self) private var premiumStore
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var isRestoring: Bool = false
    @State private var isConfirmingSignOut: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Eyebrow(String(localized: "Account"))
            TempoCard(kind: TempoCardKind.outlined, padding: TempoSpacing.md) {
                VStack(spacing: 0) {
                    infoRows
                    TempoDivider()
                    actionRows
                }
            }
        }
        .confirmationDialog(
            Text("Sign out of \(Brand.name)?"),
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible,
            actions: { signOutActions },
            message: { Text("Your profile and matches will be here when you come back.") }
        )
        .onDisappear {
            tasks.cancelAll()
        }
    }

    @ViewBuilder
    private var infoRows: some View {
        TempoRow(
            title: String(localized: "Community rules"),
            systemImage: "checkmark.shield",
            tile: TempoPastel.sage,
            action: { router.youPath.append(YouDestination.communityRules) }
        )
        TempoDivider()
        TempoRow(
            title: String(localized: "Privacy policy"),
            systemImage: "lock",
            tile: TempoPastel.sky,
            action: { open(LegalLinks.privacyPolicyURL) }
        )
        TempoDivider()
        TempoRow(
            title: String(localized: "Terms"),
            systemImage: "doc.text",
            tile: TempoPastel.lilac,
            action: { open(LegalLinks.termsURL) }
        )
        TempoDivider()
        // App Review (1.2) expects a visible way to reach the people behind a UGC app.
        TempoRow(
            title: String(localized: "Help and support"),
            systemImage: "questionmark.circle",
            tile: TempoPastel.sage,
            action: { open(LegalLinks.supportURL) }
        )
    }

    @ViewBuilder
    private var actionRows: some View {
        TempoRow(
            title: String(localized: "Restore purchases"),
            value: isRestoring ? String(localized: "Checking…") : nil,
            systemImage: "arrow.clockwise",
            tile: TempoPastel.lilac,
            showsChevron: false,
            action: { restore() }
        )
        .disabled(isRestoring || premiumStore.isBusy)
        TempoDivider()
        TempoRow(
            title: String(localized: "Sign out"),
            systemImage: "rectangle.portrait.and.arrow.right",
            tile: TempoPastel.sky,
            showsChevron: false,
            action: { isConfirmingSignOut = true }
        )
        .disabled(session.isWorking)
        TempoDivider()
        TempoRow(
            title: String(localized: "Delete account"),
            systemImage: "trash",
            tone: TempoTone.danger,
            action: { router.youPath.append(YouDestination.deleteAccount) }
        )
    }

    @ViewBuilder
    private var signOutActions: some View {
        Button(String(localized: "Sign out"), role: .destructive) {
            signOut()
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }

    private func open(_ url: URL?) {
        if let url {
            openURL(url)
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        tasks.run("restore") {
            isRestoring = true
            await premiumStore.restore()
            isRestoring = false
            if Task.isCancelled {
                return
            }
            switch premiumStore.purchaseState {
            case .success:
                router.showMessage(String(localized: "\(Brand.premiumName) is back on."), systemImage: "checkmark.circle", tone: TempoTone.gold)
            case .failed(let error):
                router.showError(error.userMessage)
            case .pending:
                router.showMessage(String(localized: "Waiting for approval. Premium turns on by itself."))
            case .idle, .purchasing, .restoring:
                break
            }
            premiumStore.resetPurchaseState()
        }
    }

    private func signOut() {
        let session: SessionStore = self.session
        // Finishing the sign-out removes this screen, so it is not tied to the screen's tasks.
        Task { @MainActor in
            await session.signOut()
        }
    }
}

// MARK: - Footer

private struct YouFooter: View {
    private var versionLine: String {
        let version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let version, !version.isEmpty {
            return "\(Brand.name) \(version)"
        }
        return Brand.name
    }

    var body: some View {
        Text(versionLine)
            .tempoText(.caption)
            .foregroundStyle(Color.tempo.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Version: \(versionLine)"))
    }
}

#Preview("You, free") {
    YouView()
        .environment(AppRouter())
        .tempoEnvironment(AppEnvironment.demo())
}
