import SwiftUI

/// The top of the app: splash while the session is restored, sign-in, onboarding, then the tab shell.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    private enum Stage: Hashable {
        case splash
        case welcome
        case suspended
        case onboarding
        case shell
    }

    private var stage: Stage {
        switch session.authState {
        case .loading:
            return Stage.splash
        case .signedOut:
            return Stage.welcome
        case .signedIn:
            // While a date is on screen its own flow shows the suspension notice first.
            if session.isSuspended && !dateStore.isActive {
                return Stage.suspended
            }
            if !session.isOnboardingComplete {
                return Stage.onboarding
            }
            return Stage.shell
        }
    }

    var body: some View {
        ZStack {
            InkBackground()
            stageView
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: stage)
        .tint(Color.tempo.accent)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .splash:
            SplashView()
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .welcome:
            WelcomeView()
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .suspended:
            SuspendedView()
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .onboarding:
            OnboardingFlow()
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        case .shell:
            TabShell()
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
    }
}

#Preview("Root, signed in") {
    RootView()
        .tempoEnvironment(AppEnvironment.demo())
}

#Preview("Root, signed out") {
    RootView()
        .tempoEnvironment(AppEnvironment.demo(signedIn: false, onboarded: false))
}

#Preview("Root, onboarding") {
    RootView()
        .tempoEnvironment(AppEnvironment.demo(signedIn: true, onboarded: false))
}
