import SwiftUI

/// Shown while the stored session is checked. If the check fails it offers a retry.
struct SplashView: View {
    @Environment(SessionStore.self) private var session
    @State private var isRetrying: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: 0)
            Text(Brand.name)
                .tempoText(.displayM)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            status
            Spacer(minLength: 0)
        }
        .tempoScreenPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .inkBackground()
        .onDisappear {
            tasks.cancelAll()
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = session.lastError, !isRetrying {
            ErrorBanner(message: error.userMessage, onRetry: { retry() })
        } else {
            LoadingDots(color: Color.tempo.accent)
                .frame(height: 56)
                .accessibilityLabel(Text("Loading"))
        }
    }

    private func retry() {
        tasks.run("bootstrap") {
            isRetrying = true
            await session.bootstrap()
            isRetrying = false
        }
    }
}

#Preview("Splash") {
    SplashView()
        .tempoEnvironment(AppEnvironment.demo(signedIn: false, onboarded: false))
}
