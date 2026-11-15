import SwiftUI

// MARK: - SelfViewPiP

/// A corner of the call screen.
enum PiPCorner: Hashable, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// The local-video picture-in-picture: a 96 x 136 rounded-16 tile with a 2 pt white border that can be dragged and
/// snaps to the nearest corner. It fills the space it is given (lay it over the remote
/// video, inside the safe area) and only the tile itself takes touches.
///
/// Use `topInset` / `bottomInset` to keep it clear of the clock and the control bar.
///
///     SelfViewPiP(topInset: 56, bottomInset: 96, isCameraOff: store.isCameraOff) { LocalVideoView() }
struct SelfViewPiP<Content: View>: View {
    private let size: CGSize
    private let margin: CGFloat
    private let topInset: CGFloat
    private let bottomInset: CGFloat
    private let isCameraOff: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var corner: PiPCorner
    @State private var drag: CGSize = CGSize.zero
    @State private var isDragging: Bool = false

    init(
        initialCorner: PiPCorner = PiPCorner.topTrailing,
        size: CGSize = TempoSize.pip,
        margin: CGFloat = TempoSpacing.md,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isCameraOff: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self._corner = State(initialValue: initialCorner)
        self.size = size
        self.margin = margin
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isCameraOff = isCameraOff
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            tile(in: proxy.size)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }

    private func tile(in container: CGSize) -> some View {
        let home: CGPoint = center(for: corner, in: container)
        let gesture = DragGesture(minimumDistance: 4, coordinateSpace: CoordinateSpace.global)
            .onChanged { value in
                drag = value.translation
                isDragging = true
            }
            .onEnded { value in
                let projected: CGPoint = CGPoint(
                    x: home.x + value.predictedEndTranslation.width,
                    y: home.y + value.predictedEndTranslation.height
                )
                let target: PiPCorner = nearestCorner(to: projected, in: container)
                withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
                    corner = target
                    drag = CGSize.zero
                    isDragging = false
                }
            }

        return face
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.tempo.background, lineWidth: 2) }
            .tempoShadow(TempoShadow.floating)
            .scaleEffect(isDragging ? 1.04 : 1.0)
            .contentShape(shape)
            .gesture(gesture)
            .position(x: home.x + drag.width, y: home.y + drag.height)
            .animation(Animation.tempo.snappy, value: isDragging)
            .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.light), trigger: corner)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isCameraOff ? "Your camera, off" : "Your camera"))
            .accessibilityAction(named: Text("Move to next corner")) {
                moveToNextCorner()
            }
    }

    @ViewBuilder
    private var face: some View {
        if isCameraOff {
            ZStack {
                Color.tempo.surface
                Image(systemName: "video.slash")
                    .font(Font.system(size: 22, weight: Font.Weight.regular))
                    .foregroundStyle(Color.tempo.textSecondary)
            }
        } else {
            content
        }
    }

    private func center(for corner: PiPCorner, in container: CGSize) -> CGPoint {
        let left: CGFloat = margin + size.width / 2.0
        let right: CGFloat = container.width - margin - size.width / 2.0
        let top: CGFloat = margin + topInset + size.height / 2.0
        let bottom: CGFloat = container.height - margin - bottomInset - size.height / 2.0
        switch corner {
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: bottom)
        case .bottomTrailing: return CGPoint(x: right, y: bottom)
        }
    }

    private func nearestCorner(to point: CGPoint, in container: CGSize) -> PiPCorner {
        var best: PiPCorner = corner
        var bestDistance: CGFloat = CGFloat.greatestFiniteMagnitude
        for candidate in PiPCorner.allCases {
            let spot: CGPoint = center(for: candidate, in: container)
            let dx: CGFloat = spot.x - point.x
            let dy: CGFloat = spot.y - point.y
            let distance: CGFloat = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func moveToNextCorner() {
        let all: [PiPCorner] = PiPCorner.allCases
        let index: Int = all.firstIndex(of: corner) ?? 0
        withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
            corner = all[(index + 1) % all.count]
        }
    }
}

// MARK: - CallControlBar

/// The in-call controls as one white capsule (hairline, the one soft shadow) with outlined
/// near-black icons: mic, camera, flip (only when `onFlip` is given; a date stays on the selfie
/// camera), report, and Leave. A control that is off fills black.
/// Leave is a red filled circle with a white icon, always visible, and acts at once (no confirmation).
///
///     CallControlBar(isMicMuted: store.isMicMuted, isCameraOff: store.isCameraOff,
///                    onToggleMic: { store.toggleMic() }, onToggleCamera: { store.toggleCamera() },
///                    onFlip: { store.flipCamera() }, onReport: { showReport = true }, onLeave: { store.leaveDate() })
struct CallControlBar: View {
    private let isMicMuted: Bool
    private let isCameraOff: Bool
    private let onToggleMic: () -> Void
    private let onToggleCamera: () -> Void
    private let onFlip: (() -> Void)?
    private let onReport: () -> Void
    private let onLeave: () -> Void

    @State private var leaveCount: Int = 0

    private let controlSize: CGFloat = 46

    init(
        isMicMuted: Bool,
        isCameraOff: Bool,
        onToggleMic: @escaping () -> Void,
        onToggleCamera: @escaping () -> Void,
        onFlip: (() -> Void)? = nil,
        onReport: @escaping () -> Void,
        onLeave: @escaping () -> Void
    ) {
        self.isMicMuted = isMicMuted
        self.isCameraOff = isCameraOff
        self.onToggleMic = onToggleMic
        self.onToggleCamera = onToggleCamera
        self.onFlip = onFlip
        self.onReport = onReport
        self.onLeave = onLeave
    }

    var body: some View {
        HStack(spacing: TempoSpacing.xxs) {
            IconCircleButton(
                systemImage: "mic",
                accessibilityLabel: "Microphone",
                isOn: !isMicMuted,
                offSystemImage: "mic.slash",
                kind: IconCircleButtonKind.plain,
                size: controlSize,
                action: onToggleMic
            )
            IconCircleButton(
                systemImage: "video",
                accessibilityLabel: "Camera",
                isOn: !isCameraOff,
                offSystemImage: "video.slash",
                kind: IconCircleButtonKind.plain,
                size: controlSize,
                action: onToggleCamera
            )
            if let onFlip {
                IconCircleButton(
                    systemImage: "arrow.triangle.2.circlepath.camera",
                    accessibilityLabel: "Flip camera",
                    kind: IconCircleButtonKind.plain,
                    size: controlSize,
                    action: onFlip
                )
            }
            IconCircleButton(
                systemImage: "flag",
                accessibilityLabel: "Report",
                kind: IconCircleButtonKind.plain,
                size: controlSize,
                action: onReport
            )
            leaveButton
        }
        .padding(6)
        .tempoSurface(in: Capsule(), isFloating: true)
        .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.medium), trigger: leaveCount)
    }

    private var leaveButton: some View {
        Button(action: leave) {
            Image(systemName: "phone.down.fill")
                .font(Font.system(size: 18, weight: Font.Weight.regular))
                .foregroundStyle(Color.tempo.onAccent)
                .frame(width: controlSize, height: controlSize)
                .background { Circle().fill(Color.tempo.danger) }
                .contentShape(Circle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.93))
        .padding(.leading, TempoSpacing.xxs)
        .accessibilityLabel(Text("Leave date"))
    }

    private func leave() {
        leaveCount += 1
        onLeave()
    }
}

// MARK: - VideoScrim

/// Very light black gradients (35% at most) at the top and bottom of full-bleed video, only so
/// the white chrome reads against bright footage. Ignores safe areas and never takes touches. Layer it directly above the video.
///
///     ZStack { RemoteVideoView().ignoresSafeArea(); VideoScrim(); controls }
struct VideoScrim: View {
    private let topHeight: CGFloat
    private let bottomHeight: CGFloat
    private let strength: Double

    init(topHeight: CGFloat = 160, bottomHeight: CGFloat = 260, strength: Double = 0.35) {
        self.topHeight = topHeight
        self.bottomHeight = bottomHeight
        self.strength = strength
    }

    var body: some View {
        VStack(spacing: 0) {
            TempoGradient.scrim(fromTop: true, strength: strength)
                .frame(height: topHeight)
            Spacer(minLength: 0)
            TempoGradient.scrim(fromTop: false, strength: strength)
                .frame(height: bottomHeight)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - ModerationWarningBanner

/// The in-call warning shown after a first sexual-language flag: a white card over the video with
/// an amber icon tile and an amber border. Calm, unmissable.
///
///     ModerationWarningBanner(message: store.moderationWarning ?? "", onDismiss: { dismissWarning() })
struct ModerationWarningBanner: View {
    private let title: String
    private let message: String
    private let onDismiss: (() -> Void)?

    @State private var hasAppeared: Bool = false

    init(title: String = "Keep it respectful", message: String, onDismiss: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            IconTile(systemName: "exclamationmark.triangle", tone: TempoTone.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(message)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Font.system(size: 14, weight: Font.Weight.regular))
                        .foregroundStyle(Color.tempo.textSecondary)
                        .frame(width: TempoSize.hitTarget, height: TempoSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TempoPressStyle())
                .accessibilityLabel(Text("Dismiss warning"))
            }
        }
        .padding(.leading, TempoSpacing.md)
        .padding(.trailing, onDismiss == nil ? TempoSpacing.md : TempoSpacing.xxs)
        .padding(.vertical, TempoSpacing.sm)
        .tempoSurface(in: shape, isFloating: true, showsBorder: false)
        .overlay { shape.strokeBorder(Color.tempo.warning, lineWidth: 1) }
        .sensoryFeedback(SensoryFeedback.warning, trigger: hasAppeared)
        .onAppear {
            hasAppeared = true
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }
}

// MARK: - Preview

private struct CallPreview: View {
    @State private var isMicMuted: Bool = false
    @State private var isCameraOff: Bool = false

    var body: some View {
        ZStack {
            Color.tempo.textSecondary
                .ignoresSafeArea()
            VideoScrim()
            SelfViewPiP(topInset: 56, bottomInset: 96, isCameraOff: isCameraOff) {
                Color.tempo.pastelSky
            }
            VStack(spacing: TempoSpacing.md) {
                DateClockView(endsAt: Date().addingTimeInterval(192), totalDuration: 240)
                ModerationWarningBanner(message: "Sexual language isn't allowed here. One more and the date ends.", onDismiss: {})
                Spacer()
                CallControlBar(
                    isMicMuted: isMicMuted,
                    isCameraOff: isCameraOff,
                    onToggleMic: { isMicMuted.toggle() },
                    onToggleCamera: { isCameraOff.toggle() },
                    onFlip: {},
                    onReport: {},
                    onLeave: {}
                )
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.xs)
        }
    }
}

#Preview("Call components") {
    CallPreview()
}
