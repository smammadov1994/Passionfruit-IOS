import SwiftUI

// MARK: - OnboardingProgress

/// One thin black line across the top that grows with each step, on a hairline track.
///
///     OnboardingProgress(step: 2, total: 6)   // step is 1-based
struct OnboardingProgress: View {
    private let step: Int
    private let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(step: Int, total: Int) {
        self.step = step
        self.total = total
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(step, 0), total)) / CGFloat(total)
    }

    var body: some View {
        Capsule()
            .fill(Color.tempo.hairline)
            .overlay {
                Rectangle()
                    .fill(Color.tempo.textPrimary)
                    .scaleEffect(x: fraction, y: 1.0, anchor: UnitPoint.leading)
            }
            .clipShape(Capsule())
            .frame(height: 2)
            .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(min(max(step, 0), total)) of \(total)"))
    }
}

// MARK: - PhotoSlot

/// A 3:4 photo tile for the profile editor. Empty: dashed outline with a plus. Filled: the
/// photo with a remove button. Shows `image` (a just-picked local photo) in preference to `url`.
///
///     PhotoSlot(url: photoURL, isPrimary: true, onTap: { pickPhoto() }, onRemove: { removePhoto() })
struct PhotoSlot: View {
    private let url: URL?
    private let image: Image?
    private let isPrimary: Bool
    private let isLoading: Bool
    private let onTap: () -> Void
    private let onRemove: (() -> Void)?

    init(
        url: URL?,
        image: Image? = nil,
        isPrimary: Bool = false,
        isLoading: Bool = false,
        onTap: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.url = url
        self.image = image
        self.isPrimary = isPrimary
        self.isLoading = isLoading
        self.onTap = onTap
        self.onRemove = onRemove
    }

    private var isFilled: Bool {
        url != nil || image != nil
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }

    var body: some View {
        Button(action: onTap) {
            tile
        }
        .buttonStyle(TempoPressStyle(scale: 0.97))
        .accessibilityLabel(Text(isFilled ? (isPrimary ? "Main photo" : "Photo") : "Add photo"))
        .accessibilityHint(Text(isFilled ? "Double tap to replace" : ""))
        .overlay(alignment: .topTrailing) { removeButton }
    }

    private var tile: some View {
        Color.tempo.surface
            .aspectRatio(3.0 / 4.0, contentMode: ContentMode.fit)
            .overlay { photo }
            .overlay { loadingVeil }
            .clipShape(shape)
            .overlay { outline }
            .overlay(alignment: .bottomLeading) { primaryTag }
            .contentShape(shape)
    }

    @ViewBuilder
    private var photo: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
        } else if url != nil {
            TempoRemoteImage(url: url, name: "", monogramSize: 36)
        } else {
            Image(systemName: "plus")
                .font(Font.system(size: 24, weight: Font.Weight.light))
                .foregroundStyle(isPrimary ? Color.tempo.accent : Color.tempo.textSecondary)
        }
    }

    @ViewBuilder
    private var loadingVeil: some View {
        if isLoading {
            ZStack {
                Color.tempo.background.opacity(0.7)
                LoadingDots()
            }
        }
    }

    @ViewBuilder
    private var outline: some View {
        if isFilled {
            shape.strokeBorder(Color.tempo.hairline, lineWidth: 1)
        } else {
            shape.strokeBorder(
                isPrimary ? Color.tempo.accent : Color.tempo.hairlineStrong,
                style: StrokeStyle(lineWidth: 1, lineCap: CGLineCap.round, dash: [5, 5])
            )
        }
    }

    @ViewBuilder
    private var primaryTag: some View {
        if isPrimary, isFilled {
            Text("Main")
                .tempoText(.eyebrow)
                .foregroundStyle(Color.tempo.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background { Capsule().fill(Color.tempo.textPrimary) }
                .padding(TempoSpacing.xs)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isFilled, let onRemove {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(Font.system(size: 12, weight: Font.Weight.regular))
                    .foregroundStyle(Color.tempo.textPrimary)
                    .frame(width: 26, height: 26)
                    .background { Circle().fill(Color.tempo.background) }
                    .overlay { Circle().strokeBorder(Color.tempo.hairline, lineWidth: 1) }
                    .frame(width: TempoSize.hitTarget, height: TempoSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TempoPressStyle(scale: 0.9))
            .accessibilityLabel(Text("Remove photo"))
        }
    }
}

// MARK: - MessageBubble

/// A chat bubble. Mine: accent with white text, right. Theirs: surface 2 with near-black text, left.
///
///     MessageBubble(text: message.text, isMine: message.senderId == me.id, timestamp: "21:04")
struct MessageBubble: View {
    private let text: String
    private let isMine: Bool
    private let timestamp: String?
    private let isPending: Bool
    private let showsTail: Bool

    init(text: String, isMine: Bool, timestamp: String? = nil, isPending: Bool = false, showsTail: Bool = true) {
        self.text = text
        self.isMine = isMine
        self.timestamp = timestamp
        self.isPending = isPending
        self.showsTail = showsTail
    }

    var body: some View {
        HStack(spacing: 0) {
            if isMine {
                Spacer(minLength: 56)
            }
            VStack(alignment: isMine ? HorizontalAlignment.trailing : HorizontalAlignment.leading, spacing: TempoSpacing.xxs) {
                bubble
                if let timestamp {
                    Text(timestamp)
                        .tempoText(.numeralS)
                        .foregroundStyle(Color.tempo.textTertiary)
                        .padding(.horizontal, TempoSpacing.xxs)
                }
            }
            if !isMine {
                Spacer(minLength: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isMine ? "You: \(text)" : text))
        .accessibilityValue(Text(accessibilityDetail))
    }

    private var accessibilityDetail: String {
        if isPending {
            return "Sending"
        }
        return timestamp ?? ""
    }

    private var shape: UnevenRoundedRectangle {
        let round: CGFloat = 20
        let tail: CGFloat = showsTail ? 6 : round
        return UnevenRoundedRectangle(
            topLeadingRadius: round,
            bottomLeadingRadius: isMine ? round : tail,
            bottomTrailingRadius: isMine ? tail : round,
            topTrailingRadius: round,
            style: RoundedCornerStyle.continuous
        )
    }

    private var bubble: some View {
        Text(text)
            .tempoText(.body)
            .foregroundStyle(Color.tempo.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background { wash }
            .opacity(isPending ? 0.6 : 1.0)
    }

    /// Mine is a rose wash, theirs a green one.
    private var tint: Color {
        isMine ? Color(red: 0.94, green: 0.58, blue: 0.52) : Color(red: 0.52, green: 0.77, blue: 0.62)
    }

    /// A thin, see-through wash: pale in the middle where the paper shows through, with the
    /// pigment pooling toward the edge and a fine darker rim, like glass.
    private var wash: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.3)],
                    startPoint: UnitPoint.topLeading,
                    endPoint: UnitPoint.bottomTrailing
                )
            )
            .overlay {
                shape
                    .strokeBorder(tint.opacity(0.22), lineWidth: 5)
                    .blur(radius: 3)
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(tint.opacity(0.6), lineWidth: 1) }
    }
}

// MARK: - ChatComposer

/// The message field (surface color) and a black circular send button, on a white bar with a top
/// hairline, pinned above the keyboard. Send is disabled while the text is blank or `isSending`.
///
///     ChatComposer(text: $draft, isSending: isSending) { send() }
struct ChatComposer: View {
    @Binding private var text: String
    private let placeholder: String
    private let isSending: Bool
    private let onSend: () -> Void

    @FocusState private var isFocused: Bool
    @State private var sendCount: Int = 0

    init(text: Binding<String>, placeholder: String = "Message", isSending: Bool = false, onSend: @escaping () -> Void) {
        self._text = text
        self.placeholder = placeholder
        self.isSending = isSending
        self.onSend = onSend
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: TempoSpacing.xs) {
            field
            sendButton
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.xs)
        .background { bar }
        .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.light), trigger: sendCount)
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var field: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(Color.tempo.textTertiary), axis: Axis.vertical)
            .focused($isFocused)
            .tempoText(.body)
            .foregroundStyle(Color.tempo.textPrimary)
            .tint(Color.tempo.accent)
            .lineLimit(1...5)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, 11)
            .frame(minHeight: TempoSize.hitTarget)
            .background { fieldShape.fill(Color.tempo.surface) }
            .overlay { fieldShape.strokeBorder(isFocused ? Color.tempo.hairlineStrong : Color.tempo.hairline, lineWidth: 1) }
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(Font.system(size: 17, weight: Font.Weight.semibold))
                .foregroundStyle(canSend ? Color.tempo.onAccent : Color.tempo.textTertiary)
                .frame(width: TempoSize.hitTarget, height: TempoSize.hitTarget)
                .background { sendFill }
                .contentShape(Circle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.9))
        .disabled(!canSend)
        .animation(Animation.tempo.snappy, value: canSend)
        .accessibilityLabel(Text("Send"))
    }

    @ViewBuilder
    private var sendFill: some View {
        if canSend {
            Circle().fill(Color.tempo.textPrimary)
        } else {
            Circle().fill(Color.tempo.surface2)
        }
    }

    private var bar: some View {
        Color.tempo.background
            .overlay(alignment: .top) { TempoDivider() }
            .ignoresSafeArea(edges: Edge.Set.bottom)
    }

    private func send() {
        guard canSend else { return }
        sendCount += 1
        onSend()
    }
}

// MARK: - Preview

private struct ChatPreview: View {
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: TempoSpacing.xs) {
                    OnboardingProgress(step: 2, total: 6)
                        .padding(.bottom, TempoSpacing.md)
                    HStack(spacing: TempoSpacing.sm) {
                        PhotoSlot(url: nil, isPrimary: true, onTap: {})
                        PhotoSlot(url: nil, onTap: {})
                        PhotoSlot(url: nil, isLoading: true, onTap: {})
                    }
                    .padding(.bottom, TempoSpacing.md)
                    MessageBubble(text: "That was the fastest four minutes of my week.", isMine: false, timestamp: "21:04")
                    MessageBubble(text: "Same. You still owe me the end of the ferry story.", isMine: true, showsTail: false)
                    MessageBubble(text: "Thursday?", isMine: true, timestamp: "21:05", isPending: true)
                }
                .tempoScreenPadding()
                .padding(.vertical, TempoSpacing.lg)
            }
            ChatComposer(text: $draft) {
                draft = ""
            }
        }
        .inkBackground()
    }
}

#Preview("Profile and chat") {
    ChatPreview()
}
