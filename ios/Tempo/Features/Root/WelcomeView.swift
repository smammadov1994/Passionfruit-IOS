import AuthenticationServices
import SwiftUI

/// Signed-out screen: what the app is and the ways in.
///
/// - Sign in with Apple is always there, drawn by Apple's own button.
/// - Demo mode (the Debug default) puts "Try the demo" first, as the black primary action, so the app can
///   be explored in the Simulator at once.
/// - Debug builds in live mode add "Continue with a dev account" (`POST /v1/auth/dev`).
/// - Release builds show Sign in with Apple only.
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(ConfigStore.self) private var configStore
    @State private var isDevSigningIn: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
            WelcomeEmblem()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            pitch
            actions
                .padding(.top, TempoSpacing.lg)
        }
        .tempoScreenPadding()
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkBackground()
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private var wordmark: some View {
        Text(Brand.name)
            .tempoText(.titleS)
            .foregroundStyle(Color.tempo.textPrimary)
            .accessibilityAddTraits(AccessibilityTraits.isHeader)
    }

    private var pitch: some View {
        let duration: TimeInterval = configStore.dateDuration
        let headline: String = TempoFormat.durationHeadline(duration)
        let phrase: String = TempoFormat.durationPhrase(duration)
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(headline).")
                    .tempoText(.displayL)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Face to face.")
                    .tempoText(.displayL.italic())
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(AccessibilityTraits.isHeader)
            Text("Go online and meet someone who's free right now. Talk on video for \(phrase). If you both say yes, it's a match.")
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: TempoSpacing.sm) {
            if let error = session.lastError {
                ErrorBanner(message: error.userMessage, onDismiss: { session.lastError = nil })
            }
            if environment.isDemo {
                demoEntry
                appleButton(isPrimary: false)
            } else {
                appleButton(isPrimary: true)
                if session.supportsDevSignIn {
                    devEntry
                }
            }
            footnote
        }
    }

    /// Demo mode: the obvious way in. Nothing is sent anywhere; the account lives on this device.
    private var demoEntry: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Chip(String(localized: "Demo mode · nothing leaves this device"), systemImage: "play.circle", tone: TempoTone.ember)
            TempoButton(
                String(localized: "Try the demo"),
                isLoading: isDevSigningIn,
                action: { signInDev() }
            )
            .disabled(session.isWorking)
            .accessibilityHint(Text("Signs in with a demo account on this device"))
        }
    }

    /// Debug builds against a real server: dev auth, clearly a second choice but easy to see.
    private var devEntry: some View {
        TempoButton(
            String(localized: "Continue with a dev account"),
            systemImage: "hammer",
            variant: TempoButtonVariant.secondary,
            size: TempoButtonSize.regular,
            isLoading: isDevSigningIn,
            action: { signInDev() }
        )
        .disabled(session.isWorking)
        .accessibilityHint(Text("Development sign-in. Debug builds only."))
    }

    /// Apple's own button, full width, capsule-shaped like the app's other buttons. Black when it
    /// is the main way in (it then matches the primary button); white with an outline when the
    /// demo button is the primary. Core runs the authorization; the button only starts it.
    private func appleButton(isPrimary: Bool) -> some View {
        AppleSignInButton(isPrimary: isPrimary, cornerRadius: TempoSize.buttonLarge / 2, action: { signInWithApple() })
            .frame(maxWidth: .infinity)
            .frame(height: TempoSize.buttonLarge)
            .disabled(session.isWorking)
            .opacity(session.isWorking ? 0.5 : 1.0)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("For adults \(Birthdate.minimumAge) and over.")
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
            LegalLinksRow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TempoSpacing.xxs)
    }

    private func signInWithApple() {
        tasks.run("signIn") {
            await session.signInWithApple()
        }
    }

    private func signInDev() {
        tasks.run("signIn") {
            isDevSigningIn = true
            await session.signInDev()
            isDevSigningIn = false
        }
    }
}

/// `ASAuthorizationAppleIDButton`, so the title, logo, proportions, localisation and VoiceOver
/// label are Apple's. It does not run the authorization itself: `action` does (through Core).
private struct AppleSignInButton: UIViewRepresentable {
    let isPrimary: Bool
    let cornerRadius: CGFloat
    let action: () -> Void

    func makeCoordinator() -> AppleSignInButtonTarget {
        AppleSignInButtonTarget(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let style: ASAuthorizationAppleIDButton.Style = isPrimary ? .black : .whiteOutline
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: style)
        button.cornerRadius = cornerRadius
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.addTarget(context.coordinator, action: #selector(AppleSignInButtonTarget.didTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        uiView.cornerRadius = cornerRadius
        uiView.isEnabled = context.environment.isEnabled
    }
}

/// Target of the Apple button's touch-up action.
private final class AppleSignInButtonTarget: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc func didTap() {
        action()
    }
}

/// "Terms · Privacy" as two small links.
struct LegalLinksRow: View {
    init() {}

    var body: some View {
        HStack(spacing: TempoSpacing.xs) {
            if let url = LegalLinks.termsURL {
                Link(destination: url) {
                    Text("Terms")
                        .tempoText(.caption)
                        .underline()
                }
            }
            Text("·")
                .tempoText(.caption)
                .accessibilityHidden(true)
            if let url = LegalLinks.privacyPolicyURL {
                Link(destination: url) {
                    Text("Privacy")
                        .tempoText(.caption)
                        .underline()
                }
            }
        }
        .foregroundStyle(Color.tempo.textSecondary)
        .frame(minHeight: TempoSize.hitTarget)
    }
}

/// The painting above the headline. Decorative and still; it takes the space the copy leaves
/// over, so large text sizes shrink the picture instead of clipping the words.
private struct WelcomeEmblem: View {
    var body: some View {
        GeometryReader { proxy in
            Image("ArtWelcome")
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
                // Bleed to the screen edge so the painting is not cut at the text margin.
                .offset(x: TempoSpacing.screen)
        }
        .padding(.bottom, TempoSpacing.xl)
        .accessibilityHidden(true)
    }
}

#Preview("Welcome") {
    WelcomeView()
        .tempoEnvironment(AppEnvironment.demo(signedIn: false, onboarded: false))
}
