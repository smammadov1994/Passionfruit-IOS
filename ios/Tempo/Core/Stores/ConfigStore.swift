import Foundation
import Observation

/// Server tunables (`GET /v1/config`). UI reads durations and limits from here, never from literals.
@MainActor
@Observable
final class ConfigStore {
    private(set) var config: AppConfig
    private(set) var isLoaded: Bool = false
    private(set) var lastError: TempoError?

    @ObservationIgnored private let api: any APIClient

    init(api: any APIClient, initial: AppConfig = AppConfig.fallback) {
        self.api = api
        self.config = initial
    }

    /// Fetches the config. Keeps the previous values on failure and records `lastError`.
    func load() async {
        do {
            config = try await api.fetchConfig()
            isLoaded = true
            lastError = nil
        } catch {
            lastError = TempoError.from(error)
        }
    }

    var dateDuration: TimeInterval { TimeInterval(config.dateDurationSec) }
    var turnDuration: TimeInterval { TimeInterval(config.turnDurationSec) }
    var decisionWindow: TimeInterval { TimeInterval(config.decisionWindowSec) }
    var freeDailyDates: Int { config.freeDailyDates }
    var frameSampleInterval: TimeInterval { config.frameSampleIntervalSec }
    var iceServers: [IceServer] { config.iceServers }
}
