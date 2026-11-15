import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit
@preconcurrency import WebRTC

// MARK: - Peer connection delegate

/// Receives WebRTC callbacks on the signaling thread and forwards plain, Sendable values.
final class PeerConnectionDelegateProxy: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    private let onCandidate: @Sendable (String, Int, String?) -> Void
    private let onState: @Sendable (VideoConnectionState) -> Void
    private let onTracksChanged: @Sendable () -> Void

    init(
        onCandidate: @escaping @Sendable (String, Int, String?) -> Void,
        onState: @escaping @Sendable (VideoConnectionState) -> Void,
        onTracksChanged: @escaping @Sendable () -> Void
    ) {
        self.onCandidate = onCandidate
        self.onState = onState
        self.onTracksChanged = onTracksChanged
        super.init()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        onTracksChanged()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            onState(.connected)
            onTracksChanged()
        case .disconnected:
            onState(.reconnecting)
        case .failed:
            onState(.failed)
        case .closed:
            onState(.closed)
        case .new, .checking:
            onState(.connecting)
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onCandidate(candidate.sdp, Int(candidate.sdpMLineIndex), candidate.sdpMid)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - Frame sampler

/// A video renderer attached to the local track. Every `interval` seconds it turns one camera frame
/// into a small JPEG for moderation. Everything else is dropped untouched.
final class FrameSampler: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var interval: TimeInterval = 0
    private var lastSampleAt: CFTimeInterval = 0
    private var isEncoding: Bool = false
    private var handler: (@Sendable (Data) -> Void)?
    private let context = CIContext(options: nil)
    private let queue = DispatchQueue(label: "com.tempo.frame-sampler", qos: .utility)
    private let maxSide: CGFloat = 384

    override init() {
        super.init()
    }

    /// `interval <= 0` or a nil handler turns sampling off.
    func configure(interval: TimeInterval, handler: (@Sendable (Data) -> Void)?) {
        lock.lock()
        self.interval = interval
        self.handler = handler
        self.lastSampleAt = 0
        lock.unlock()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.lock()
        let now: CFTimeInterval = CACurrentMediaTime()
        let currentHandler = handler
        let due: Bool = interval > 0 && currentHandler != nil && !isEncoding && (now - lastSampleAt) >= interval
        if due {
            lastSampleAt = now
            isEncoding = true
        }
        lock.unlock()
        guard due, let currentHandler else { return }

        guard let buffer = frame.buffer as? RTCCVPixelBuffer else {
            finishEncoding()
            return
        }
        let pixelBuffer: CVPixelBuffer = buffer.pixelBuffer
        let rotation: RTCVideoRotation = frame.rotation
        queue.async { [weak self] in
            guard let self else { return }
            let data: Data? = self.encode(pixelBuffer: pixelBuffer, rotation: rotation)
            self.finishEncoding()
            if let data {
                currentHandler(data)
            }
        }
    }

    private func finishEncoding() {
        lock.lock()
        isEncoding = false
        lock.unlock()
    }

    private func encode(pixelBuffer: CVPixelBuffer, rotation: RTCVideoRotation) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        switch rotation {
        case ._90:
            image = image.oriented(.right)
        case ._180:
            image = image.oriented(.down)
        case ._270:
            image = image.oriented(.left)
        default:
            break
        }
        let extent: CGRect = image.extent
        let longest: CGFloat = max(extent.width, extent.height)
        guard longest > 0 else { return nil }
        let scale: CGFloat = min(1, maxSide / longest)
        let scaled: CIImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let qualityKey = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let options: [CIImageRepresentationOption: Any] = [qualityKey: 0.6]
        return context.jpegRepresentation(of: scaled, colorSpace: colorSpace, options: options)
    }
}

// MARK: - Renderer container

/// Hosts an `RTCMTLVideoView`. The inner view can be mirrored (front camera) without flipping the container.
final class LiveVideoContainerUIView: UIView {
    let renderer: RTCMTLVideoView
    /// Detaches `renderer` from the track it was added to. Set by the service that made the view
    /// and run once from `releaseVideoSurface()`. A video track keeps a strong reference to every
    /// renderer added to it, so a surface that is never detached is never freed and keeps drawing.
    var onRelease: (() -> Void)?

    override init(frame: CGRect) {
        renderer = RTCMTLVideoView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        renderer = RTCMTLVideoView(frame: .zero)
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        clipsToBounds = true
        // Surface 2 (#EFEBE6): what shows before the first frame arrives.
        backgroundColor = UIColor(red: 239 / 255, green: 235 / 255, blue: 230 / 255, alpha: 1)
        renderer.videoContentMode = .scaleAspectFill
        renderer.frame = bounds
        renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(renderer)
    }

    var isMirrored: Bool = false {
        didSet {
            renderer.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        }
    }
}

extension LiveVideoContainerUIView: ReleasableVideoSurface {
    func releaseVideoSurface() {
        let release: (() -> Void)? = onRelease
        onRelease = nil
        release?()
    }
}

// MARK: - Service

@MainActor
final class LiveVideoCallService: VideoCallService {
    private(set) var connectionState: VideoConnectionState = .idle
    private(set) var isMicMuted: Bool = false
    private(set) var isCameraOff: Bool = false
    private(set) var cameraPosition: CameraPosition = .front
    private(set) var isCapturing: Bool = false
    private(set) var isCallAudioSilenced: Bool = false

    var onSignal: (@MainActor (RTCSignalPayload) -> Void)?
    var onFrameSample: (@MainActor (Data) -> Void)?

    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer
    private let localVideoTrack: RTCVideoTrack
    private var localAudioTrack: RTCAudioTrack?
    private var peerConnection: RTCPeerConnection?
    private var delegateProxy: PeerConnectionDelegateProxy?
    private var remoteVideoTrack: RTCVideoTrack?

    private let localViews = NSHashTable<LiveVideoContainerUIView>.weakObjects()
    private let remoteViews = NSHashTable<LiveVideoContainerUIView>.weakObjects()
    private let sampler = FrameSampler()
    private let stateHub = Broadcaster<VideoConnectionState>()

    private var pendingSignals: [RTCSignalPayload] = []
    private var pendingCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription: Bool = false
    private var isDrainingSignals: Bool = false
    private var callGeneration: Int = 0
    /// True between a successful activation of the audio session and its deactivation.
    /// `RTCAudioSession` counts activations: every `setActive(false)` must match one activation.
    private var isAudioSessionActive: Bool = false

    private let streamId: String = "tempo-stream"

    init() {
        _ = RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        let createdFactory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        let source: RTCVideoSource = createdFactory.videoSource()
        factory = createdFactory
        videoSource = source
        capturer = RTCCameraVideoCapturer(delegate: source)
        localVideoTrack = createdFactory.videoTrack(with: source, trackId: "tempo-video-0")
        localVideoTrack.add(sampler)
    }

    // MARK: Local capture

    func startLocalCapture() async {
        guard !isCapturing else { return }
        guard let device = cameraDevice(for: cameraPosition) ?? RTCCameraVideoCapturer.captureDevices().first else {
            return
        }
        guard let format = bestFormat(for: device) else { return }
        isCapturing = true
        cameraPosition = (device.position == .back) ? .back : .front
        // In an async context Swift selects the completion-handler overload as `async throws`.
        try? await capturer.startCapture(with: device, format: format, fps: bestFrameRate(for: format))
        updateMirroring()
    }

    func stopLocalCapture() {
        guard isCapturing else { return }
        isCapturing = false
        capturer.stopCapture()
    }

    private func cameraDevice(for position: CameraPosition) -> AVCaptureDevice? {
        let wanted: AVCaptureDevice.Position = (position == .front) ? .front : .back
        let devices: [AVCaptureDevice] = RTCCameraVideoCapturer.captureDevices()
        return devices.first(where: { $0.position == wanted })
    }

    /// The supported format closest to 1280×720.
    private func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats: [AVCaptureDevice.Format] = RTCCameraVideoCapturer.supportedFormats(for: device)
        var best: AVCaptureDevice.Format?
        var bestScore: Int = Int.max
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let score: Int = abs(Int(dimensions.width) - 1280) + abs(Int(dimensions.height) - 720)
            if score < bestScore {
                bestScore = score
                best = format
            }
        }
        return best
    }

    private func bestFrameRate(for format: AVCaptureDevice.Format) -> Int {
        var highest: Double = 0
        for range in format.videoSupportedFrameRateRanges {
            highest = max(highest, range.maxFrameRate)
        }
        if highest <= 0 {
            return 30
        }
        return Int(min(30, highest))
    }

    private func updateMirroring() {
        let mirrored: Bool = cameraPosition == .front
        for view in localViews.allObjects {
            view.isMirrored = mirrored
        }
    }

    // MARK: Call lifecycle

    func startCall(role: CallRole, iceServers: [IceServer]) async {
        closePeerConnection()
        isCallAudioSilenced = false
        callGeneration += 1
        let generation: Int = callGeneration

        configureAudioSession()

        let configuration = RTCConfiguration()
        var servers: [RTCIceServer] = []
        for server in iceServers where !server.urls.isEmpty {
            servers.append(RTCIceServer(urlStrings: server.urls, username: server.username, credential: server.credential))
        }
        configuration.iceServers = servers
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.bundlePolicy = .maxBundle

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])

        let proxy = PeerConnectionDelegateProxy(
            onCandidate: { [weak self] (sdp: String, index: Int, mid: String?) in
                Task { @MainActor in
                    self?.localCandidateGenerated(sdp: sdp, index: index, mid: mid, generation: generation)
                }
            },
            onState: { [weak self] (state: VideoConnectionState) in
                Task { @MainActor in
                    self?.peerStateChanged(state, generation: generation)
                }
            },
            onTracksChanged: { [weak self] in
                Task { @MainActor in
                    self?.attachRemoteTrack(generation: generation)
                }
            }
        )

        let created: RTCPeerConnection? = factory.peerConnection(with: configuration, constraints: constraints, delegate: proxy)
        guard let connection = created else {
            setState(.failed)
            return
        }
        delegateProxy = proxy
        peerConnection = connection

        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "tempo-audio-0")
        audioTrack.isEnabled = !isMicMuted && !isCallAudioSilenced
        localAudioTrack = audioTrack
        localVideoTrack.isEnabled = !isCameraOff
        _ = connection.add(audioTrack, streamIds: [streamId])
        _ = connection.add(localVideoTrack, streamIds: [streamId])

        setState(.connecting)

        if role == .caller {
            do {
                let sdp: String = try await createOffer(on: connection)
                guard generation == callGeneration else { return }
                try await setLocal(RTCSessionDescription(type: .offer, sdp: sdp), on: connection)
                guard generation == callGeneration else { return }
                onSignal?(RTCSignalPayload.offer(sdp: sdp))
            } catch {
                if generation == callGeneration {
                    setState(.failed)
                }
                return
            }
        }
        drainSignalsIfNeeded()
    }

    func handleRemoteSignal(_ payload: RTCSignalPayload) {
        pendingSignals.append(payload)
        drainSignalsIfNeeded()
    }

    func endCall() {
        pendingSignals.removeAll()
        closePeerConnection()
        isCallAudioSilenced = false
        deactivateAudioSession()
        if connectionState != .idle {
            setState(.closed)
            setState(.idle)
        }
    }

    private func closePeerConnection() {
        callGeneration += 1
        sampler.configure(interval: 0, handler: nil)
        if let track = remoteVideoTrack {
            for view in remoteViews.allObjects {
                track.remove(view.renderer)
            }
        }
        remoteVideoTrack = nil
        if let connection = peerConnection {
            connection.delegate = nil
            connection.close()
        }
        peerConnection = nil
        delegateProxy = nil
        localAudioTrack = nil
        pendingCandidates.removeAll()
        hasRemoteDescription = false
    }

    // MARK: Signaling

    private func drainSignalsIfNeeded() {
        guard !isDrainingSignals, peerConnection != nil, !pendingSignals.isEmpty else { return }
        isDrainingSignals = true
        Task { [weak self] in
            await self?.drainSignals()
        }
    }

    private func drainSignals() async {
        while let connection = peerConnection, !pendingSignals.isEmpty {
            let payload: RTCSignalPayload = pendingSignals.removeFirst()
            await apply(payload, to: connection, generation: callGeneration)
        }
        isDrainingSignals = false
    }

    private func apply(_ payload: RTCSignalPayload, to connection: RTCPeerConnection, generation: Int) async {
        switch payload.kind {
        case .offer:
            guard let sdp = payload.sdp else { return }
            do {
                try await setRemote(RTCSessionDescription(type: .offer, sdp: sdp), on: connection)
                guard generation == callGeneration else { return }
                hasRemoteDescription = true
                await flushCandidates(on: connection)
                let answer: String = try await createAnswer(on: connection)
                guard generation == callGeneration else { return }
                try await setLocal(RTCSessionDescription(type: .answer, sdp: answer), on: connection)
                guard generation == callGeneration else { return }
                onSignal?(RTCSignalPayload.answer(sdp: answer))
                attachRemoteTrack(generation: generation)
            } catch {
                if generation == callGeneration {
                    setState(.failed)
                }
            }
        case .answer:
            guard let sdp = payload.sdp else { return }
            do {
                try await setRemote(RTCSessionDescription(type: .answer, sdp: sdp), on: connection)
                guard generation == callGeneration else { return }
                hasRemoteDescription = true
                await flushCandidates(on: connection)
                attachRemoteTrack(generation: generation)
            } catch {
                if generation == callGeneration {
                    setState(.failed)
                }
            }
        case .ice:
            guard let candidate = payload.candidate else { return }
            let index: Int32 = Int32(payload.sdpMLineIndex ?? 0)
            let ice = RTCIceCandidate(sdp: candidate, sdpMLineIndex: index, sdpMid: payload.sdpMid)
            if hasRemoteDescription {
                await add(ice, to: connection)
            } else {
                pendingCandidates.append(ice)
            }
        }
    }

    private func flushCandidates(on connection: RTCPeerConnection) async {
        let candidates: [RTCIceCandidate] = pendingCandidates
        pendingCandidates.removeAll()
        for candidate in candidates {
            await add(candidate, to: connection)
        }
    }

    private func offerAnswerConstraints() -> RTCMediaConstraints {
        RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
    }

    private func createOffer(on connection: RTCPeerConnection) async throws -> String {
        let constraints: RTCMediaConstraints = offerAnswerConstraints()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.offer(for: constraints) { (description: RTCSessionDescription?, error: Error?) in
                if let description {
                    continuation.resume(returning: description.sdp)
                } else {
                    continuation.resume(throwing: error ?? TempoError.unknown(""))
                }
            }
        }
    }

    private func createAnswer(on connection: RTCPeerConnection) async throws -> String {
        let constraints: RTCMediaConstraints = offerAnswerConstraints()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.answer(for: constraints) { (description: RTCSessionDescription?, error: Error?) in
                if let description {
                    continuation.resume(returning: description.sdp)
                } else {
                    continuation.resume(throwing: error ?? TempoError.unknown(""))
                }
            }
        }
    }

    private func setLocal(_ description: RTCSessionDescription, on connection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(description) { (error: Error?) in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setRemote(_ description: RTCSessionDescription, on connection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(description) { (error: Error?) in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func add(_ candidate: RTCIceCandidate, to connection: RTCPeerConnection) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.add(candidate) { (_: Error?) in
                continuation.resume()
            }
        }
    }

    // MARK: Delegate events (hopped to the main actor)

    private func localCandidateGenerated(sdp: String, index: Int, mid: String?, generation: Int) {
        guard generation == callGeneration else { return }
        onSignal?(RTCSignalPayload.ice(candidate: sdp, sdpMid: mid, sdpMLineIndex: index))
    }

    private func peerStateChanged(_ state: VideoConnectionState, generation: Int) {
        guard generation == callGeneration, peerConnection != nil else { return }
        setState(state)
    }

    private func attachRemoteTrack(generation: Int) {
        guard generation == callGeneration, let connection = peerConnection else { return }
        var found: RTCVideoTrack?
        for transceiver in connection.transceivers where transceiver.mediaType == .video {
            if let track = transceiver.receiver.track as? RTCVideoTrack {
                found = track
                break
            }
        }
        guard let track = found else { return }
        if let current = remoteVideoTrack {
            if current === track {
                return
            }
            for view in remoteViews.allObjects {
                current.remove(view.renderer)
            }
        }
        remoteVideoTrack = track
        for view in remoteViews.allObjects {
            track.add(view.renderer)
        }
        applyAudioSilence()
    }

    // MARK: Controls

    func setMicMuted(_ muted: Bool) {
        isMicMuted = muted
        localAudioTrack?.isEnabled = !muted && !isCallAudioSilenced
    }

    func setCallAudioSilenced(_ silenced: Bool) {
        guard peerConnection != nil else { return }
        isCallAudioSilenced = silenced
        applyAudioSilence()
    }

    /// Applies `isCallAudioSilenced` to the outgoing microphone track and to every incoming audio
    /// track. A disabled local track sends silence; a disabled remote track is not played.
    private func applyAudioSilence() {
        localAudioTrack?.isEnabled = !isMicMuted && !isCallAudioSilenced
        guard let connection = peerConnection else { return }
        for transceiver in connection.transceivers where transceiver.mediaType == .audio {
            if let track = transceiver.receiver.track as? RTCAudioTrack {
                track.isEnabled = !isCallAudioSilenced
            }
        }
    }

    func setCameraOff(_ off: Bool) {
        isCameraOff = off
        localVideoTrack.isEnabled = !off
    }

    func flipCamera() async {
        let next: CameraPosition = (cameraPosition == .front) ? .back : .front
        guard let device = cameraDevice(for: next), let format = bestFormat(for: device) else { return }
        cameraPosition = next
        if isCapturing {
            // In an async context Swift selects the completion-handler overload as `async throws`.
            try? await capturer.startCapture(with: device, format: format, fps: bestFrameRate(for: format))
        }
        updateMirroring()
    }

    // MARK: Frame sampling

    func startFrameSampling(interval: TimeInterval) {
        sampler.configure(interval: interval) { [weak self] (data: Data) in
            Task { @MainActor in
                guard let self, !self.isCameraOff else { return }
                self.onFrameSample?(data)
            }
        }
    }

    func stopFrameSampling() {
        sampler.configure(interval: 0, handler: nil)
    }

    // MARK: Streams and views

    func connectionStates() -> AsyncStream<VideoConnectionState> {
        stateHub.stream()
    }

    func makeLocalVideoView() -> UIView {
        let view = LiveVideoContainerUIView(frame: .zero)
        view.isMirrored = cameraPosition == .front
        localViews.add(view)
        let renderer: RTCMTLVideoView = view.renderer
        localVideoTrack.add(renderer)
        view.onRelease = { [weak self, weak view] in
            guard let self else { return }
            self.localVideoTrack.remove(renderer)
            if let view {
                self.localViews.remove(view)
            }
        }
        return view
    }

    func makeRemoteVideoView() -> UIView {
        let view = LiveVideoContainerUIView(frame: .zero)
        remoteViews.add(view)
        let renderer: RTCMTLVideoView = view.renderer
        if let track = remoteVideoTrack {
            track.add(renderer)
        }
        view.onRelease = { [weak self, weak view] in
            guard let self else { return }
            // Whichever remote track is current is the one this renderer was last added to.
            self.remoteVideoTrack?.remove(renderer)
            if let view {
                self.remoteViews.remove(view)
            }
        }
        return view
    }

    private func setState(_ newState: VideoConnectionState) {
        guard connectionState != newState else { return }
        connectionState = newState
        stateHub.yield(newState)
    }

    // MARK: Audio session

    /// Video chat through the loudspeaker, Bluetooth allowed.
    private func configureAudioSession() {
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.videoChat.rawValue
        configuration.categoryOptions = [.defaultToSpeaker, .allowBluetooth]
        RTCAudioSessionConfiguration.setWebRTC(configuration)

        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        do {
            try session.setConfiguration(configuration)
        } catch {
            // The call still works with WebRTC's default audio configuration.
        }
        // Activation is a separate step so that it is counted exactly: `setActive(true)` only
        // counts when it succeeds, and an earlier call that was replaced is not activated twice.
        if !isAudioSessionActive {
            do {
                try session.setActive(true)
                isAudioSessionActive = true
            } catch {
                // WebRTC activates the session itself when audio starts.
            }
        }
        session.unlockForConfiguration()
    }

    private func deactivateAudioSession() {
        // `endCall()` also runs when no call was ever started; an unmatched deactivation would
        // push RTCAudioSession's activation count below zero and leave the session stuck on later.
        guard isAudioSessionActive else { return }
        isAudioSessionActive = false
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        do {
            try session.setActive(false)
        } catch {
            // Another audio client may still be active; nothing to do.
        }
        session.unlockForConfiguration()
    }
}
