import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text for the local microphone. Emits only newly recognised words.
/// Audio never leaves the phone: recognition runs only where on-device recognition is supported.
final class SpeechTranscriber: @unchecked Sendable {
    private let lock = NSLock()
    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()

    // Guarded by `lock`.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning: Bool = false
    private var segment: Int = 0
    private var segmentStartedAt: Date = Date()
    private var latestWords: [String] = []
    private var sentWordCount: Int = 0
    private var handler: (@Sendable (String) -> Void)?

    /// Recognition requests are rotated so a single request never grows without bound.
    private let maxSegmentDuration: TimeInterval = 50

    init(locale: Locale = Locale.current) {
        if let localized = SFSpeechRecognizer(locale: locale) {
            recognizer = localized
        } else {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
    }

    /// True when speech can be transcribed entirely on this device right now.
    var isSupported: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    /// Asks for speech recognition permission when needed. Returns whether it is granted.
    static func requestAuthorization() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { (newStatus: SFSpeechRecognizerAuthorizationStatus) in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Starts listening. Returns false when transcription is not possible (unsupported, no input, engine error).
    func start(onChunk: @escaping @Sendable (String) -> Void) -> Bool {
        guard isSupported else { return false }

        lock.lock()
        let alreadyRunning: Bool = isRunning
        lock.unlock()
        if alreadyRunning {
            return true
        }

        let input: AVAudioInputNode = engine.inputNode
        let format: AVAudioFormat = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return false
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }

        lock.lock()
        isRunning = true
        handler = onChunk
        lock.unlock()
        beginSegment()
        return true
    }

    func stop() {
        lock.lock()
        let wasRunning: Bool = isRunning
        isRunning = false
        let oldRequest = request
        let oldTask = task
        request = nil
        task = nil
        segment += 1
        lock.unlock()

        guard wasRunning else { return }
        flush()
        lock.lock()
        handler = nil
        lock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        oldRequest?.endAudio()
        oldTask?.cancel()
    }

    /// Sends any words recognised since the last flush, and rotates the request when it is old.
    /// Call every few seconds.
    func tick() {
        flush()
        lock.lock()
        let shouldRotate: Bool = isRunning && Date().timeIntervalSince(segmentStartedAt) > maxSegmentDuration
        lock.unlock()
        if shouldRotate {
            beginSegment()
        }
    }

    // MARK: Internals

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }

    private func beginSegment() {
        guard let recognizer else { return }
        flush()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = true

        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        let oldRequest = request
        let oldTask = task
        segment += 1
        let currentSegment: Int = segment
        segmentStartedAt = Date()
        latestWords = []
        sentWordCount = 0
        request = newRequest
        lock.unlock()

        oldRequest?.endAudio()
        oldTask?.cancel()

        let newTask: SFSpeechRecognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] (result: SFSpeechRecognitionResult?, error: Error?) in
            self?.handle(result: result, error: error, segment: currentSegment)
        }

        lock.lock()
        if segment == currentSegment && isRunning {
            task = newTask
            lock.unlock()
        } else {
            lock.unlock()
            newTask.cancel()
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, segment resultSegment: Int) {
        var isFinal: Bool = false
        lock.lock()
        guard resultSegment == segment, isRunning else {
            lock.unlock()
            return
        }
        if let result {
            let text: String = result.bestTranscription.formattedString
            latestWords = text.split(separator: " ").map { String($0) }
            isFinal = result.isFinal
        }
        lock.unlock()

        if isFinal || error != nil {
            // The recogniser closed this request (silence, error or limit). Start a fresh one.
            beginSegment()
        }
    }

    private func flush() {
        lock.lock()
        let words: [String] = latestWords
        let alreadySent: Int = sentWordCount
        let currentHandler = handler
        if words.count > alreadySent {
            sentWordCount = words.count
        }
        lock.unlock()

        guard words.count > alreadySent, let currentHandler else { return }
        let chunk: String = words[alreadySent...].joined(separator: " ")
        if !chunk.isEmpty {
            currentHandler(chunk)
        }
    }
}
