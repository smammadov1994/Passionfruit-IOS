import AVFoundation
import Foundation
import UIKit

/// Runs an `AVCaptureSession` off the main thread for the demo-mode local preview.
final class DemoCameraController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.tempo.demo-camera")
    private var currentInput: AVCaptureDeviceInput?

    init() {}

    /// Starts the session with the given camera. Returns false when no camera is available.
    func start(position: AVCaptureDevice.Position) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                let success: Bool = self.configure(position: position)
                if success && !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume(returning: success)
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configure(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }
        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
        }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        var added: Bool = false
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            added = true
        }
        session.commitConfiguration()
        return added
    }
}

/// Demo-mode video: the real local camera when one is available (never in the Simulator),
/// animated placeholders otherwise, and an animated placeholder for the remote person.
@MainActor
final class MockVideoCallService: VideoCallService {
    private(set) var connectionState: VideoConnectionState = .idle
    private(set) var isMicMuted: Bool = false
    private(set) var isCameraOff: Bool = false
    private(set) var cameraPosition: CameraPosition = .front
    private(set) var isCapturing: Bool = false
    private(set) var isCallAudioSilenced: Bool = false
    /// True between `startFrameSampling` and `stopFrameSampling`. No frames are produced by
    /// themselves in the demo; tests push one with `emitFrameSample(_:)`.
    private(set) var isSamplingFrames: Bool = false

    var onSignal: (@MainActor (RTCSignalPayload) -> Void)?
    var onFrameSample: (@MainActor (Data) -> Void)?

    /// How long the fake call takes to "connect".
    var connectDelay: TimeInterval = 0.8

    private let stateHub = Broadcaster<VideoConnectionState>()
    private let camera = DemoCameraController()
    private let localViews = NSHashTable<DemoLocalVideoUIView>.weakObjects()
    private var cameraIsLive: Bool = false
    private var connectTask: Task<Void, Never>?

    init() {}

    func startLocalCapture() async {
        guard !isCapturing else { return }
        isCapturing = true
        #if targetEnvironment(simulator)
        cameraIsLive = false
        #else
        var granted: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted, isCapturing else { return }
        let started: Bool = await camera.start(position: cameraPosition == .front ? .front : .back)
        guard isCapturing else {
            camera.stop()
            return
        }
        cameraIsLive = started
        refreshLocalViews()
        #endif
    }

    func stopLocalCapture() {
        guard isCapturing else { return }
        isCapturing = false
        if cameraIsLive {
            camera.stop()
        }
        cameraIsLive = false
        refreshLocalViews()
    }

    func startCall(role: CallRole, iceServers: [IceServer]) async {
        connectTask?.cancel()
        isCallAudioSilenced = false
        setState(.connecting)
        let delay: TimeInterval = connectDelay
        connectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            if self.connectionState == .connecting {
                self.setState(.connected)
            }
        }
    }

    func handleRemoteSignal(_ payload: RTCSignalPayload) {}

    func endCall() {
        connectTask?.cancel()
        connectTask = nil
        isCallAudioSilenced = false
        if connectionState != .idle {
            setState(.closed)
            setState(.idle)
        }
    }

    func setCallAudioSilenced(_ silenced: Bool) {
        // Nothing is sent or played in the demo; the flag keeps the mock observable in tests.
        guard connectionState != .idle else { return }
        isCallAudioSilenced = silenced
    }

    func setMicMuted(_ muted: Bool) {
        isMicMuted = muted
    }

    func setCameraOff(_ off: Bool) {
        isCameraOff = off
        refreshLocalViews()
    }

    func flipCamera() async {
        cameraPosition = (cameraPosition == .front) ? .back : .front
        guard isCapturing, cameraIsLive else { return }
        let started: Bool = await camera.start(position: cameraPosition == .front ? .front : .back)
        cameraIsLive = started
        refreshLocalViews()
    }

    func startFrameSampling(interval: TimeInterval) {
        isSamplingFrames = interval > 0
    }

    func stopFrameSampling() {
        isSamplingFrames = false
    }

    /// Delivers one frame the way the live sampler would: only while sampling and with the camera on.
    func emitFrameSample(_ data: Data) {
        guard isSamplingFrames, !isCameraOff else { return }
        onFrameSample?(data)
    }

    func connectionStates() -> AsyncStream<VideoConnectionState> {
        stateHub.stream()
    }

    func makeLocalVideoView() -> UIView {
        let view = DemoLocalVideoUIView(frame: .zero)
        localViews.add(view)
        if cameraIsLive && !isCameraOff {
            view.showCamera(session: camera.session)
        }
        return view
    }

    func makeRemoteVideoView() -> UIView {
        PlaceholderVideoUIView(style: .remote)
    }

    private func refreshLocalViews() {
        for view in localViews.allObjects {
            if cameraIsLive && !isCameraOff {
                view.showCamera(session: camera.session)
            } else {
                view.showPlaceholder()
            }
        }
    }

    private func setState(_ newState: VideoConnectionState) {
        guard connectionState != newState else { return }
        connectionState = newState
        stateHub.yield(newState)
    }
}
