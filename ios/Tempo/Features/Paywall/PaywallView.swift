import SwiftUI

/// Tempo Premium: white, a cream price card, ochre details and a black button. Sheet content that dismisses itself; present it with `.sheet`.
/// The price always comes from the App Store product; the close button never scrolls away.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premiumStore
    @Environment(\.dismiss) private var dismiss

    init() {}

    private var isSuccess: Bool {
        premiumStore.purchaseState == PurchaseState.success
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                PaywallHero(
                    eyebrow: Brand.premiumName,
                    headline: String(localized: "Never run out of"),
                    emphasis: String(localized: "evenings.")
                )
                benefits
            }
            .tempoScreenPadding()
            .padding(.top, TempoSpacing.xxl)
            .padding(.bottom, TempoSpacing.lg)
            .background(alignment: .topTrailing) {
                Image("ArtGold")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 354)
                    .accessibilityHidden(true)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PaywallPurchasePanel(onClose: { dismiss() })
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .inkBackground()
        .presentationCornerRadius(TempoRadius.sheet)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(premiumStore.isBusy)
        .task {
            if premiumStore.product == nil {
                await premiumStore.loadProduct()
            }
        }
        .task(id: isSuccess) {
            await closeAfterSuccess()
        }
        .onDisappear {
            premiumStore.resetPurchaseState()
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            BenefitRow(
                systemImage: "infinity",
                title: String(localized: "Unlimited dates"),
                detail: String(localized: "Stay online as long as the night is good.")
            )
            BenefitRow(
                systemImage: "slider.horizontal.3",
                title: String(localized: "Dealbreaker filters"),
                detail: String(localized: "Meet people who want what you want."),
                tint: TempoPastel.sky
            )
            BenefitRow(
                systemImage: "bolt",
                title: String(localized: "Front of the line"),
                detail: String(localized: "You're paired first when it's busy."),
                tint: TempoPastel.sage
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        IconCircleButton(
            systemImage: "xmark",
            accessibilityLabel: String(localized: "Close"),
            kind: IconCircleButtonKind.plain,
            size: TempoSize.hitTarget,
            action: { dismiss() }
        )
        .padding(.top, TempoSpacing.xs)
        .padding(.trailing, TempoSpacing.xs)
    }

    /// Shows the confirmation for a moment, then closes.
    private func closeAfterSuccess() async {
        guard isSuccess else { return }
        Haptics.success()
        do {
            try await Task.sleep(for: Duration.milliseconds(1400))
        } catch {
            return
        }
        premiumStore.resetPurchaseState()
        dismiss()
    }
}

// MARK: - Purchase panel

/// Price, the purchase button with its in-flight, failed and success states, restore, and the
/// auto-renewal terms.
private struct PaywallPurchasePanel: View {
    let onClose: () -> Void

    @Environment(PremiumStore.self) private var premiumStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            status
            if premiumStore.isPremium {
                memberActions
            } else {
                price
                purchaseActions
                footnote
            }
        }
        .tempoScreenPadding()
        .padding(.top, TempoSpacing.sm)
        .padding(.bottom, TempoSpacing.xs)
        .background {
            Color.tempo.background
                .overlay(alignment: .top) { TempoDivider() }
                .ignoresSafeArea(edges: Edge.Set.bottom)
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: premiumStore.purchaseState)
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        switch premiumStore.purchaseState {
        case .idle, .purchasing, .restoring:
            EmptyView()
        case .pending:
            notice(
                systemImage: "hourglass",
                text: String(localized: "Waiting for approval. Premium turns on by itself once it's approved.")
            )
        case .success:
            notice(
                systemImage: "checkmark.circle",
                text: String(localized: "You're in. \(Brand.premiumName) is on.")
            )
        case .failed(let error):
            ErrorBanner(message: error.userMessage, onDismiss: { premiumStore.resetPurchaseState() })
        }
    }

    private func notice(systemImage: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
            Image(systemName: systemImage)
                .font(Font.tempo.body)
                .foregroundStyle(Color.tempo.premium)
                .accessibilityHidden(true)
            Text(text)
                .tempoText(.secondary)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                .fill(Color.tempo.premiumSoft)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Price

    @ViewBuilder
    private var price: some View {
        if let product = premiumStore.product {
            PriceTag(price: product.displayPrice, period: product.periodLabel)
        } else if let error = premiumStore.productError {
            ErrorBanner(message: error.userMessage, onRetry: { loadProduct() })
        } else {
            LoadingDots(color: Color.tempo.premium, dotSize: 6)
                .frame(minHeight: 56)
                .accessibilityLabel(Text("Loading the price"))
        }
    }

    // MARK: Actions

    private var canPurchase: Bool {
        premiumStore.product != nil && !premiumStore.isBusy && premiumStore.purchaseState != PurchaseState.success
    }

    private var purchaseActions: some View {
        VStack(spacing: TempoSpacing.xxs) {
            TempoButton(
                String(localized: "Start Premium"),
                variant: TempoButtonVariant.premium,
                isLoading: premiumStore.purchaseState == PurchaseState.purchasing,
                action: { purchase() }
            )
            .disabled(!canPurchase)
            TempoButton(
                String(localized: "Restore purchases"),
                variant: TempoButtonVariant.ghost,
                size: TempoButtonSize.regular,
                isLoading: premiumStore.purchaseState == PurchaseState.restoring,
                action: { restore() }
            )
            .disabled(premiumStore.isBusy)
        }
    }

    private var memberActions: some View {
        VStack(spacing: TempoSpacing.sm) {
            if premiumStore.purchaseState != PurchaseState.success {
                notice(
                    systemImage: "checkmark.circle",
                    text: String(localized: "You already have \(Brand.premiumName). Enjoy the evening.")
                )
            }
            TempoButton(String(localized: "Done"), variant: TempoButtonVariant.premium, action: onClose)
        }
    }

    private var footnote: some View {
        VStack(spacing: 0) {
            Text(termsText)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            LegalLinksRow()
        }
        .frame(maxWidth: .infinity)
    }

    private var termsText: String {
        if let product = premiumStore.product {
            return String(localized: "\(product.priceLine). Renews automatically until you cancel. Cancel anytime in your Apple Account settings, at least 24 hours before the next renewal.")
        }
        return String(localized: "Renews automatically until you cancel. Cancel anytime in your Apple Account settings, at least 24 hours before the next renewal.")
    }

    // Purchases and restores belong to the store once started: closing the paywall must not
    // abandon a payment half-way, so these are not tied to the view's lifetime.

    private func purchase() {
        guard canPurchase else { return }
        let store: PremiumStore = premiumStore
        Task { @MainActor in
            await store.purchase()
        }
    }

    private func restore() {
        guard !premiumStore.isBusy else { return }
        let store: PremiumStore = premiumStore
        Task { @MainActor in
            await store.restore()
        }
    }

    private func loadProduct() {
        let store: PremiumStore = premiumStore
        Task { @MainActor in
            await store.loadProduct()
        }
    }
}

#Preview("Paywall") {
    PaywallView()
        .tempoEnvironment(AppEnvironment.demo())
}

#Preview("Paywall in a sheet") {
    Color.clear
        .inkBackground()
        .sheet(isPresented: Binding<Bool>.constant(true)) {
            PaywallView()
        }
        .tempoEnvironment(AppEnvironment.demo())
}
