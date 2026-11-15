import SwiftUI

// MARK: - LoadingDots

/// Three softly pulsing dots. Used inside buttons and wherever something is pending.
///
///     LoadingDots()
struct LoadingDots: View {
    private let color: Color
    private let dotSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    init(color: Color = Color.tempo.textPrimary, dotSize: CGFloat = 6) {
        self.color = color
        self.dotSize = dotSize
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive)) { context in
            row(time: context.date.timeIntervalSinceReferenceDate)
        }
        .tempoTracksActivity($isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }

    private func row(time: Double) -> some View {
        HStack(spacing: dotSize * 0.9) {
            dot(index: 0, time: time)
            dot(index: 1, time: time)
            dot(index: 2, time: time)
        }
    }

    private func dot(index: Int, time: Double) -> some View {
        let wave: Double = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(time * 5.2 - Double(index) * 0.9)
        return Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .opacity(0.3 + 0.7 * wave)
            .scaleEffect(0.8 + 0.2 * wave)
    }
}

// MARK: - ErrorBanner

/// An inline error with an optional retry. Every failed load or action surfaces through this.
///
///     ErrorBanner(message: "Couldn't load your matches.", onRetry: { reload() })
struct ErrorBanner: View {
    private let message: String
    private let retryTitle: String
    private let onRetry: (() -> Void)?
    private let onDismiss: (() -> Void)?

    init(message: String, retryTitle: String = "Try again", onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .center, spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(Font.system(size: 20, weight: Font.Weight.regular))
                .foregroundStyle(Color.tempo.danger)
                .accessibilityHidden(true)
            Text(message)
                .tempoText(.secondary)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(TempoButtonStyle(TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false))
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Font.system(size: 14, weight: Font.Weight.regular))
                        .foregroundStyle(Color.tempo.textSecondary)
                        .frame(width: TempoSize.hitTarget, height: TempoSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TempoPressStyle())
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .padding(.leading, TempoSpacing.md)
        .padding(.trailing, onDismiss == nil ? TempoSpacing.sm : 0)
        .padding(.vertical, TempoSpacing.xs)
        .frame(minHeight: 56)
        .background { shape.fill(Color.tempo.background) }
        .overlay { shape.strokeBorder(Color.tempo.danger, lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }
}

// MARK: - EmptyStateView

/// A quiet, left-aligned empty state: outlined icon on a pastel circle, serif title, one sentence,
/// optional action.
///
///     EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No matches yet",
///                    message: "When it's mutual, they'll be here.", actionTitle: "Go online") { goOnline() }
struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Image(systemName: systemImage)
                .font(Font.system(size: 26, weight: Font.Weight.light))
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(width: 64, height: 64)
                .background {
                    Image("ArtSpot")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 104)
                }
                .padding(.bottom, TempoSpacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .tempoText(.title)
                .foregroundStyle(Color.tempo.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                TempoButton(actionTitle, variant: TempoButtonVariant.secondary, size: TempoButtonSize.regular, fullWidth: false, action: action)
                    .padding(.top, TempoSpacing.sm)
            }
        }
        .padding(.horizontal, TempoSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Toast

/// What a toast shows. Create a new value each time so the same message can repeat.
struct TempoToastItem: Identifiable, Equatable {
    let id: UUID
    let message: String
    let systemImage: String?
    let tone: TempoTone

    init(_ message: String, systemImage: String? = nil, tone: TempoTone = TempoTone.neutral) {
        self.id = UUID()
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
    }
}

/// The toast pill itself. Usually shown through `.tempoToast(item:)`.
struct TempoToast: View {
    private let item: TempoToastItem

    init(item: TempoToastItem) {
        self.item = item
    }

    var body: some View {
        HStack(spacing: TempoSpacing.xs) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(Font.system(size: 16, weight: Font.Weight.regular))
                    .foregroundStyle(item.tone.color)
                    .accessibilityHidden(true)
            }
            Text(item.message)
                .tempoText(.secondaryEmphasis)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .tempoSurface(in: Capsule(), isFloating: true)
        .accessibilityElement(children: .combine)
    }
}

private struct TempoToastModifier: ViewModifier {
    @Binding var item: TempoToastItem?
    let duration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if let item {
                        TempoToast(item: item)
                            .padding(.top, TempoSpacing.xs)
                            .padding(.horizontal, TempoSpacing.screen)
                            .onTapGesture { dismiss() }
                            .id(item.id)
                            .transition(toastTransition)
                    }
                }
                .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: item)
            }
            .task(id: item?.id) {
                guard item != nil else { return }
                do {
                    try await Task.sleep(for: Duration.seconds(duration))
                } catch {
                    return
                }
                dismiss()
            }
            .sensoryFeedback(trigger: item) { (_: TempoToastItem?, newValue: TempoToastItem?) -> SensoryFeedback? in
                guard let newValue else { return nil }
                if newValue.tone == TempoTone.danger {
                    return SensoryFeedback.error
                }
                return SensoryFeedback.impact(weight: SensoryFeedback.Weight.light)
            }
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity)
    }

    private func dismiss() {
        item = nil
    }
}

extension View {
    /// Shows a toast at the top while `item` is non-nil; clears it after `duration` seconds or on tap.
    ///
    ///     .tempoToast(item: $toast)   // toast = TempoToastItem("Reported. Thank you.", systemImage: "checkmark")
    func tempoToast(item: Binding<TempoToastItem?>, duration: TimeInterval = 2.6) -> some View {
        modifier(TempoToastModifier(item: item, duration: duration))
    }
}

#Preview("Feedback") {
    VStack(spacing: TempoSpacing.lg) {
        LoadingDots()
        ErrorBanner(message: "Couldn't load your matches.", onRetry: {}, onDismiss: {})
        ErrorBanner(message: "You're offline.")
        EmptyStateView(
            systemImage: "bubble.left.and.bubble.right",
            title: "No matches yet",
            message: "When it's mutual, they'll be here.",
            actionTitle: "Go online",
            action: {}
        )
        TempoToast(item: TempoToastItem("Reported. Thank you.", systemImage: "checkmark.circle", tone: TempoTone.mint))
    }
    .tempoScreenPadding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .inkBackground()
}
