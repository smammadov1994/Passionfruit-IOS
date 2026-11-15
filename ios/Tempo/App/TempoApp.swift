import SwiftUI

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    /// The opening animation; shown once per launch (never in UI tests).
    @State private var showsBloom: Bool = !ProcessInfo.processInfo.arguments.contains("-skipBloom")

    init() {
        let environment: AppEnvironment = AppEnvironment.makeDefault()
        AppEnvironment.current = environment
        _environment = State(initialValue: environment)
    }

    var body: some Scene {
        WindowGroup {
            // `RootView` lives in Tempo/Features/Root/RootView.swift and reads the stores from the environment.
            RootView()
                .tempoEnvironment(environment)
                .overlay {
                    if showsBloom {
                        LaunchBloom(title: Brand.name) { showsBloom = false }
                    }
                }
                .preferredColorScheme(.light)
        }
    }
}
