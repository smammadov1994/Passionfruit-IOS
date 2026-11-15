import CoreHaptics
import UIKit

/// Tempo's haptics, played through Core Haptics so they can be shaped: a press has a down and an
/// up, the slide control pushes back like a sprung trigger, the search has a pulse, and finding
/// someone and matching each have their own figure.
///
/// Everything is a no-op where the hardware has no haptics (the Simulator, iPad). The engine
/// plays haptics only, so it never touches the audio session a call is using.
@MainActor
final class TempoHaptics {
    static let shared = TempoHaptics()

    private var engine: CHHapticEngine?
    private let isSupported: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var triggerPlayer: (any CHHapticAdvancedPatternPlayer)?
    private var searchPlayer: (any CHHapticAdvancedPatternPlayer)?
    /// Last ratchet tooth felt while sliding, so each one clicks once.
    private var triggerTooth: Int = 0
    private var triggerBroke: Bool = false

    private init() {}

    // MARK: Engine

    /// Starts the engine if needed. Cheap to call before every pattern.
    private func ready() -> CHHapticEngine? {
        guard isSupported else { return nil }
        if engine == nil {
            guard let created = try? CHHapticEngine() else { return nil }
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.resetHandler = { [weak self] in
                Task { @MainActor in
                    // The server restarted: players are gone, the engine must be started again.
                    self?.triggerPlayer = nil
                    self?.searchPlayer = nil
                    try? self?.engine?.start()
                }
            }
            engine = created
        }
        do {
            try engine?.start()
        } catch {
            return nil
        }
        return engine
    }

    /// Warms the engine so the first press is not late. Call when a screen with controls appears.
    func prepare() {
        _ = ready()
    }

    private static func tap(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: CHHapticEvent.EventType.hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private static func hum(_ time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: CHHapticEvent.EventType.hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: CHHapticEvent.ParameterID.hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard let engine = ready(),
              let pattern = try? CHHapticPattern(events: events, parameterCurves: curves),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: Buttons

    /// Finger down on a button: a short, firm click.
    func pressDown() {
        play([TempoHaptics.tap(0, intensity: 0.7, sharpness: 0.75)])
    }

    /// Finger up: a softer, duller answer, so a press feels like a key with travel.
    func pressUp() {
        play([TempoHaptics.tap(0, intensity: 0.35, sharpness: 0.4)])
    }

    /// A selection moving one step (chips, toggles, a nudge).
    func tick() {
        play([TempoHaptics.tap(0, intensity: 0.4, sharpness: 0.9)])
    }

    // MARK: Trigger (the slide control)

    /// The finger took hold of the slide knob. Starts a low hum that `triggerUpdate` tightens.
    func triggerBegin() {
        triggerTooth = 0
        triggerBroke = false
        guard let engine = ready() else { return }
        try? triggerPlayer?.stop(atTime: CHHapticTimeImmediate)
        // One long continuous event; its strength is driven live from the drag.
        let events: [CHHapticEvent] = [TempoHaptics.hum(0, duration: 30, intensity: 1.0, sharpness: 0.35)]
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
        triggerPlayer = player
        try? player.sendParameters(TempoHaptics.triggerParameters(progress: 0, broke: false), atTime: CHHapticTimeImmediate)
        try? player.start(atTime: CHHapticTimeImmediate)
        pressDown()
    }

    /// The knob moved. `progress` 0...1 along the track; `breakAt` is where the action commits.
    ///
    /// Like a sprung trigger: resistance builds the further it is pulled, with fine teeth clicking
    /// past; at the commit point the spring gives way with a hard snap and goes slack.
    func triggerUpdate(progress: CGFloat, breakAt: CGFloat) {
        let p: Float = Float(min(1, max(0, progress)))
        let broke: Bool = progress >= breakAt
        try? triggerPlayer?.sendParameters(TempoHaptics.triggerParameters(progress: p, broke: broke), atTime: CHHapticTimeImmediate)

        // Ratchet teeth: closer together in feel as the pull tightens.
        let tooth: Int = Int(p * 24)
        if tooth != triggerTooth {
            triggerTooth = tooth
            if !broke {
                play([TempoHaptics.tap(0, intensity: 0.25 + 0.5 * p, sharpness: 0.55 + 0.4 * p)])
            }
        }
        if broke != triggerBroke {
            triggerBroke = broke
            if broke {
                // The wall gives: a hard snap.
                play([
                    TempoHaptics.tap(0, intensity: 1.0, sharpness: 1.0),
                    TempoHaptics.tap(0.035, intensity: 0.6, sharpness: 0.3)
                ])
            } else {
                // Pulled back over the edge: the spring catches again.
                play([TempoHaptics.tap(0, intensity: 0.6, sharpness: 0.7)])
            }
        }
    }

    /// The finger let go. `completed` true fires the landing; false is the spring pulling the knob home.
    func triggerEnd(completed: Bool) {
        try? triggerPlayer?.stop(atTime: CHHapticTimeImmediate)
        triggerPlayer = nil
        if completed {
            play([
                TempoHaptics.tap(0, intensity: 1.0, sharpness: 0.5),
                TempoHaptics.hum(0.02, duration: 0.22, intensity: 0.7, sharpness: 0.15),
                TempoHaptics.tap(0.26, intensity: 0.5, sharpness: 0.8)
            ], curves: [
                CHHapticParameterCurve(
                    parameterID: CHHapticDynamicParameter.ID.hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1.0),
                        CHHapticParameterCurve.ControlPoint(relativeTime: 0.24, value: 0.1)
                    ],
                    relativeTime: 0.02
                )
            ])
        } else {
            // Slack, then the stop at the start of the track.
            play([
                TempoHaptics.hum(0, duration: 0.16, intensity: 0.35, sharpness: 0.2),
                TempoHaptics.tap(0.17, intensity: 0.5, sharpness: 0.45)
            ])
        }
    }

    /// Strength and edge of the trigger hum for a point along the pull.
    private static func triggerParameters(progress p: Float, broke: Bool) -> [CHHapticDynamicParameter] {
        // Past the break the spring is slack: barely there.
        let intensity: Float = broke ? 0.12 : 0.1 + 0.85 * powf(p, 1.6)
        let sharpness: Float = broke ? -0.2 : -0.25 + 0.75 * p
        return [
            CHHapticDynamicParameter(parameterID: CHHapticDynamicParameter.ID.hapticIntensityControl, value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: CHHapticDynamicParameter.ID.hapticSharpnessControl, value: sharpness, relativeTime: 0)
        ]
    }

    // MARK: Searching

    /// A slow two-beat pulse, like a heartbeat, for as long as the search runs.
    func startSearchPulse() {
        guard searchPlayer == nil, let engine = ready() else { return }
        let events: [CHHapticEvent] = [
            TempoHaptics.tap(0, intensity: 0.45, sharpness: 0.15),
            TempoHaptics.tap(0.16, intensity: 0.28, sharpness: 0.1)
        ]
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
        player.loopEnabled = true
        player.loopEnd = 1.25
        searchPlayer = player
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    func stopSearchPulse() {
        try? searchPlayer?.stop(atTime: CHHapticTimeImmediate)
        searchPlayer = nil
    }

    // MARK: Moments

    /// Someone was found: the pulse quickens into three rising beats and a soft landing.
    func found() {
        stopSearchPulse()
        play([
            TempoHaptics.tap(0, intensity: 0.4, sharpness: 0.3),
            TempoHaptics.tap(0.11, intensity: 0.6, sharpness: 0.5),
            TempoHaptics.tap(0.2, intensity: 0.85, sharpness: 0.7),
            TempoHaptics.hum(0.24, duration: 0.3, intensity: 0.6, sharpness: 0.2)
        ], curves: [
            CHHapticParameterCurve(
                parameterID: CHHapticDynamicParameter.ID.hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1.0),
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0.3, value: 0.0)
                ],
                relativeTime: 0.24
            )
        ])
    }

    /// It's mutual: a swell that builds, two heavy beats close together, then a scatter of light
    /// ticks falling away.
    func match() {
        var events: [CHHapticEvent] = [
            TempoHaptics.hum(0, duration: 0.5, intensity: 0.9, sharpness: 0.2),
            TempoHaptics.tap(0.52, intensity: 1.0, sharpness: 0.45),
            TempoHaptics.tap(0.68, intensity: 1.0, sharpness: 0.6)
        ]
        let sparkle: [(TimeInterval, Float)] = [(0.86, 0.5), (0.95, 0.42), (1.06, 0.34), (1.2, 0.26), (1.38, 0.18)]
        for (time, intensity) in sparkle {
            events.append(TempoHaptics.tap(time, intensity: intensity, sharpness: 0.95))
        }
        play(events, curves: [
            CHHapticParameterCurve(
                parameterID: CHHapticDynamicParameter.ID.hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.1),
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0.5, value: 1.0)
                ],
                relativeTime: 0
            )
        ])
    }
}
