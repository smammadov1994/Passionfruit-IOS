import SwiftUI
import UIKit

// Shared call chrome: the pieces both the speed date (`DateFlowView`) and the post-match call
// (`MatchCallView`) are built from, so the two calls look and behave like one product.

// MARK: - CallVideoBackdrop

/// The remote video, full-bleed, with the light legibility scrim. `isDimmed` blurs it under a
/// 70% white veil (the Verdict); `isVideoVisible == false` keeps the surface mounted but transparent, so the
/// video never has to be re-created between phases.
struct CallVideoBackdrop: View {
    let isVideoVisible: Bool
    let isDimmed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            video
            VideoScrim()
                .opacity(scrimOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(Animation.tempo.resolved(Animation.tempo.gentle, reduceMotion: reduceMotion), value: isDimmed)
        .animation(Animation.tempo.resolved(Animation.tempo.gentle, reduceMotion: reduceMotion), value: isVideoVisible)
    }

    private var scrimOpacity: Double {
        if !isVideoVisible || isDimmed {
            return 0.0
        }
        return 1.0
    }

    private var video: some View {
        RemoteVideoView()
            .scaleEffect(isDimmed ? 1.08 : 1.0)
            .blur(radius: isDimmed ? 24.0 : 0.0)
            .overlay {
                Color.tempo.background
                    .opacity(isDimmed ? 0.7 : 0.0)
            }
            .opacity(isVideoVisible ? 1.0 : 0.0)
            .ignoresSafeArea()
    }
}

// MARK: - CallSelfView

/// The user's own camera as the draggable picture-in-picture. Give it the whole safe area.
struct CallSelfView: View {
    let isCameraOff: Bool
    var topInset: CGFloat = 56
    var bottomInset: CGFloat = 96

    var body: some View {
        SelfViewPiP(topInset: topInset, bottomInset: bottomInset, isCameraOff: isCameraOff) {
            LocalVideoView()
        }
    }
}

// MARK: - CallPartnerLabel

/// Who is on the other end: the name in serif with one quiet line under it, on a white card
/// with the one soft shadow so it reads over any video.
struct CallPartnerLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .tempoText(.serifBody)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let subtitle {
                Text(subtitle)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .tempoSurface(in: RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous), isFloating: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(AccessibilityTraits.isHeader)
    }
}

// MARK: - CallStatusPill

/// A small white floating pill for transient call states ("Reconnecting…", "You're muted").
struct CallStatusPill: View {
    let text: String
    var systemImage: String? = nil
    var showsActivity: Bool = false

    var body: some View {
        FloatingCapsule(horizontalPadding: TempoSpacing.sm, verticalPadding: 6) {
            HStack(spacing: TempoSpacing.xs) {
                if showsActivity {
                    LoadingDots(color: Color.tempo.textSecondary, dotSize: 4)
                        .accessibilityHidden(true)
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(Image.Scale.small)
                        .foregroundStyle(Color.tempo.amber)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CallConnectionHint

/// Resolves the subtle connection line for a call from the video and socket states.
enum CallConnectionHint {
    /// nil when everything is healthy.
    static func text(video: VideoConnectionState, socket: SocketConnectionState?) -> String? {
        switch video {
        case .connecting, .reconnecting, .failed:
            return video.displayName
        case .idle, .connected, .closed:
            break
        }
        guard let socket else { return nil }
        switch socket {
        case .reconnecting, .disconnected:
            return SocketConnectionState.reconnecting.displayName
        case .connecting, .connected:
            return nil
        }
    }
}

// MARK: - CallPermissionView

/// Camera or microphone access is blocked: say why it matters and offer Settings.
struct CallPermissionView: View {
    let issue: PermissionIssue
    let dismissTitle: String
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.lg)
            glyph
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(issue.title)
                    .tempoText(.title)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text(issue.message)
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TempoSpacing.lg)
            Spacer(minLength: 0)
            VStack(spacing: TempoSpacing.xs) {
                TempoButton("Open Settings", action: onOpenSettings)
                TempoButton(dismissTitle, variant: TempoButtonVariant.ghost, action: onDismiss)
            }
        }
        .tempoScreenPadding()
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var symbolName: String {
        switch issue {
        case .camera:
            return "video.slash"
        case .microphone:
            return "mic.slash"
        case .cameraAndMicrophone:
            return "video.slash"
        }
    }

    private var glyph: some View {
        Image(systemName: symbolName)
            .font(Font.system(size: 26, weight: Font.Weight.light))
            .foregroundStyle(Color.tempo.textPrimary)
            .frame(width: 64, height: 64)
            .background { Circle().fill(Color.tempo.warningSoft) }
            .accessibilityHidden(true)
    }
}

// MARK: - Keep the screen awake

/// Disables the idle timer while `isActive`, and puts back whatever was set before.
struct KeepScreenAwakeModifier: ViewModifier {
    let isActive: Bool

    @State private var savedValue: Bool? = nil

    func body(content: Content) -> some View {
        content
            .onAppear {
                apply(isActive)
            }
            .onChange(of: isActive) { _, newValue in
                apply(newValue)
            }
            .onDisappear {
                apply(false)
            }
    }

    @MainActor
    private func apply(_ keepAwake: Bool) {
        let application: UIApplication = UIApplication.shared
        if keepAwake {
            if savedValue == nil {
                savedValue = application.isIdleTimerDisabled
            }
            application.isIdleTimerDisabled = true
        } else if let previous = savedValue {
            application.isIdleTimerDisabled = previous
            savedValue = nil
        }
    }
}

extension View {
    /// Keeps the screen from dimming or locking while `isActive` (a call, a search).
    func keepsScreenAwake(_ isActive: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(isActive: isActive))
    }
}

// MARK: - VoiceOver

/// Speaks a line to VoiceOver users (phase changes, confirmations).
@MainActor
enum CallAnnouncer {
    static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        UIAccessibility.post(notification: UIAccessibility.Notification.announcement, argument: text)
    }
}
