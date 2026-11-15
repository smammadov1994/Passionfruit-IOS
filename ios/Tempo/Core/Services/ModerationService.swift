import Foundation

/// Sends moderation samples for the current date: local camera frames and on-device transcript chunks.
@MainActor
protocol ModerationService: AnyObject {
    /// Called when the server answers a sample with `warn` or `end`.
    var onAction: (@MainActor (ModerationAction, ModerationCategory) -> Void)? { get set }
    /// True while local speech is being transcribed.
    var isTranscribing: Bool { get }
    /// Begins moderation for a date. Asks for speech recognition permission the first time;
    /// if it is denied or unsupported, frames are still checked.
    func start(dateId: String) async
    /// Stops everything: transcription and frame checks. Call when the video is torn down.
    func stop()
    /// Stops speech transcription and transcript checks only. Frames submitted afterwards are
    /// still checked, because the cameras stay on while the two people decide.
    func stopTranscription()
    /// Uploads one JPEG frame of the local camera. Dropped when a previous frame is still uploading.
    func submitFrame(_ jpegData: Data)
}

@MainActor
final class LiveModerationService: ModerationService {
    var onAction: (@MainActor (ModerationAction, ModerationCategory) -> Void)?
    private(set) var isTranscribing: Bool = false

    private let api: any APIClient
    private let transcriber = SpeechTranscriber()
    private var dateId: String?
    private var isUploadingFrame: Bool = false
    /// False once transcription was stopped for this date, so a late chunk is never sent.
    private var acceptsTranscripts: Bool = false
    private var tickTask: Task<Void, Never>?

    /// How often recognised words are sent.
    private let transcriptInterval: TimeInterval = 4

    init(api: any APIClient) {
        self.api = api
    }

    func start(dateId: String) async {
        stop()
        self.dateId = dateId
        isUploadingFrame = false

        guard transcriber.isSupported else { return }
        let authorized: Bool = await SpeechTranscriber.requestAuthorization()
        guard authorized, self.dateId == dateId else { return }

        let started: Bool = transcriber.start { [weak self] (text: String) in
            Task { @MainActor in
                self?.submitTranscript(text, dateId: dateId)
            }
        }
        isTranscribing = started
        acceptsTranscripts = started
        guard started else { return }

        let interval: TimeInterval = transcriptInterval
        let transcriber: SpeechTranscriber = self.transcriber
        tickTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                transcriber.tick()
            }
        }
    }

    func stop() {
        stopTranscription()
        dateId = nil
    }

    func stopTranscription() {
        tickTask?.cancel()
        tickTask = nil
        acceptsTranscripts = false
        if isTranscribing {
            transcriber.stop()
        }
        isTranscribing = false
    }

    func submitFrame(_ jpegData: Data) {
        guard let dateId, !isUploadingFrame else { return }
        isUploadingFrame = true
        let api: any APIClient = self.api
        Task { [weak self] in
            let action: ModerationAction? = try? await api.moderateFrame(dateId: dateId, jpegData: jpegData)
            guard let self else { return }
            self.isUploadingFrame = false
            self.deliver(action, category: .nudity, dateId: dateId)
        }
    }

    private func submitTranscript(_ text: String, dateId: String) {
        guard self.dateId == dateId, acceptsTranscripts else { return }
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let api: any APIClient = self.api
        Task { [weak self] in
            let action: ModerationAction? = try? await api.moderateTranscript(dateId: dateId, text: trimmed)
            self?.deliver(action, category: .sexualLanguage, dateId: dateId)
        }
    }

    private func deliver(_ action: ModerationAction?, category: ModerationCategory, dateId: String) {
        guard let action, self.dateId == dateId else { return }
        switch action {
        case .none:
            break
        case .warn, .end:
            onAction?(action, category)
        }
    }
}

/// Demo-mode moderation: nothing is sent. It keeps the same state as the live service
/// (which date is being moderated, whether transcripts are on, how many frames arrived) so tests
/// can observe it. `simulate` lets previews show the warning UI.
@MainActor
final class MockModerationService: ModerationService {
    var onAction: (@MainActor (ModerationAction, ModerationCategory) -> Void)?
    private(set) var isTranscribing: Bool = false
    /// The date whose frames are being accepted; nil when moderation is fully stopped.
    private(set) var activeDateId: String?
    /// Frames accepted for `activeDateId` since `start`.
    private(set) var submittedFrameCount: Int = 0

    init() {}

    func start(dateId: String) async {
        activeDateId = dateId
        submittedFrameCount = 0
        isTranscribing = true
    }

    func stop() {
        stopTranscription()
        activeDateId = nil
    }

    func stopTranscription() {
        isTranscribing = false
    }

    func submitFrame(_ jpegData: Data) {
        guard activeDateId != nil else { return }
        submittedFrameCount += 1
    }

    func simulate(_ action: ModerationAction, category: ModerationCategory) {
        onAction?(action, category)
    }
}
