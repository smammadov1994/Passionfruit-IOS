import Foundation
import UIKit

enum VideoConnectionState: String, Sendable, Equatable, CaseIterable {
    /// No call.
    case idle
    /// Negotiating with the other phone.
    case connecting
    /// Media is flowing.
    case connected
    /// Media dropped; WebRTC is trying to recover.
    case reconnecting
    /// The connection could not be established or recovered.
    case failed
    /// The call was torn down.
    case closed

    var displayName: String {
        switch self {
        case .idle: return String(localized: "Not in a call")
        case .connecting: return String(localized: "Connecting…")
        case .connected: return String(localized: "Connected")
        case .reconnecting: return String(localized: "Reconnecting…")
        case .failed: return String(localized: "Connection failed")
        case .closed: return String(localized: "Call ended")
        }
    }
}

enum CameraPosition: String, Sendable, Equatable, CaseIterable {
    case front
    case back

    var displayName: String {
        switch self {
        case .front: return String(localized: "Front camera")
        case .back: return String(localized: "Back camera")
        }
    }
}

/// Owns the camera, the microphone and the peer connection. One instance serves speed dates and
/// post-match calls. Stores drive it; Features only use `LocalVideoView()` and `RemoteVideoView()`.
@MainActor
protocol VideoCallService: AnyObject {
    var connectionState: VideoConnectionState { get }
    var isMicMuted: Bool { get }
    var isCameraOff: Bool { get }
    var cameraPosition: CameraPosition { get }
    var isCapturing: Bool { get }
    /// True while `setCallAudioSilenced(true)` is in force for the current call.
    var isCallAudioSilenced: Bool { get }

    /// Outgoing signaling. The owner forwards each payload as `rtc.signal`.
    var onSignal: (@MainActor (RTCSignalPayload) -> Void)? { get set }
    /// A downscaled JPEG of the local camera, every `startFrameSampling(interval:)` seconds.
    var onFrameSample: (@MainActor (Data) -> Void)? { get set }

    /// Starts the local camera (720p, 30 fps, front by default). Safe to call repeatedly.
    func startLocalCapture() async
    func stopLocalCapture()

    /// Creates the peer connection. The caller creates and sends the offer.
    func startCall(role: CallRole, iceServers: [IceServer]) async
    /// Feeds one remote `rtc.signal` payload. Payloads arriving before `startCall` are queued.
    func handleRemoteSignal(_ payload: RTCSignalPayload)
    /// Closes the peer connection and drops queued signals. Local capture keeps running.
    func endCall()
    /// Silences the current call in both directions (the local microphone is not sent, the other
    /// person is not played) while the connection and both videos stay up. It does not change
    /// `isMicMuted`, the user's own toggle. `startCall` and `endCall` clear it.
    func setCallAudioSilenced(_ silenced: Bool)

    func setMicMuted(_ muted: Bool)
    func setCameraOff(_ off: Bool)
    func flipCamera() async

    func startFrameSampling(interval: TimeInterval)
    func stopFrameSampling()

    /// A new stream of connection state changes. Every caller gets its own stream.
    func connectionStates() -> AsyncStream<VideoConnectionState>

    /// UIKit surfaces behind `LocalVideoView` and `RemoteVideoView`.
    func makeLocalVideoView() -> UIView
    func makeRemoteVideoView() -> UIView
}
