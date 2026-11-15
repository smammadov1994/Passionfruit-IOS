import SwiftUI

/// A slide-to-confirm control for an action that should be deliberate (going online turns the
/// camera on). A capsule of slowly drifting watercolor with a white knob: drag the knob to the end
/// to fire `action`. It pushes back like a sprung trigger (`TempoHaptics.triggerUpdate`): the pull
/// tightens with fine teeth clicking past, snaps slack at the commit point, and lands with a thud.
/// Visually: The washes start faint; the knob paints them in at full strength behind it,
/// like a brush, and on arrival the whole track is painted.
/// Ticks as it passes each third, lands with a firm tap, springs back if released early. A tap
/// anywhere nudges the knob to show which way to slide. VoiceOver activates it like a button.
///
///     SlideToStart(title: "Slide to meet someone", systemImage: "video") { dateStore.goOnline() }
struct SlideToStart: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var didComplete: Bool = false
    @State private var width: CGFloat = 0

    private static let height: CGFloat = 64
    private static let inset: CGFloat = 6
    private static let completeAt: CGFloat = 0.82
    private var knobSize: CGFloat { SlideToStart.height - SlideToStart.inset * 2 }

    init(title: String, systemImage: String = "arrow.right", action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    #if DEBUG
    private static let previewFraction: CGFloat? = {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-slidePreview"), index + 1 < arguments.count,
              let value = Double(arguments[index + 1]) else { return nil }
        return CGFloat(value)
    }()
    #endif

    private var travel: CGFloat {
        max(1, width - knobSize - SlideToStart.inset * 2)
    }

    private var progress: CGFloat {
        min(1, max(0, offset / travel))
    }

    var body: some View {
        // The gesture lives on a plain, static shape. Everything that animates (the drifting
        // paint, the pulsing chevrons, the knob) is background or overlay and takes no touches,
        // so a redraw can never interrupt a drag.
        Capsule()
            .fill(Color.tempo.background)
            .frame(height: SlideToStart.height)
            .contentShape(Capsule())
            .gesture(drag)
            .simultaneousGesture(TapGesture().onEnded { nudge() })
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { newWidth in
                width = newWidth
                #if DEBUG
                // `-slidePreview 0.5` parks the knob part-way, to look at the painted track.
                if let fraction = SlideToStart.previewFraction {
                    offset = fraction * max(1, newWidth - knobSize - SlideToStart.inset * 2)
                }
                #endif
            })
            .overlay {
                SlidePaint(
                    progress: progress,
                    knobCenter: SlideToStart.inset + offset + knobSize / 2,
                    flood: didComplete ? 1 : 0
                )
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.tempo.hairlineStrong, lineWidth: TempoSize.hairline)
                    .allowsHitTesting(false)
            }
            .overlay {
                label
                    .opacity(Double(1 - min(1, progress * 1.8)))
                    .offset(x: progress * 44)
                    .padding(.leading, knobSize + SlideToStart.inset)
                    .padding(.trailing, TempoSpacing.md)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                knob(progress: progress)
                    .offset(x: SlideToStart.inset + offset)
                    .allowsHitTesting(false)
            }
            .tempoShadow(TempoShadow.floating)
            .opacity(isEnabled ? 1.0 : 0.4)
            .onAppear { TempoHaptics.shared.prepare() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(AccessibilityTraits.isButton)
            .accessibilityAction {
                complete()
            }
    }

    /// The title, with chevrons that keep pointing the way.
    private var label: some View {
        HStack(spacing: TempoSpacing.xs) {
            Text(title)
                .tempoText(.button)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            chevrons
        }
        .foregroundStyle(Color.tempo.textPrimary)
    }

    @ViewBuilder
    private var chevrons: some View {
        let glyph = Image(systemName: "chevron.right.2")
            .font(Font.system(size: 13, weight: Font.Weight.semibold))
        if reduceMotion {
            glyph.opacity(0.6)
        } else {
            glyph.phaseAnimator([false, true]) { view, forward in
                view
                    .opacity(forward ? 0.9 : 0.35)
                    .offset(x: forward ? 5 : 0)
            } animation: { _ in
                Animation.easeInOut(duration: 0.9)
            }
        }
    }

    /// White, with a black icon that never changes: the paint does the talking.
    private func knob(progress: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(Font.system(size: 20, weight: Font.Weight.medium))
            .foregroundStyle(Color.tempo.textPrimary)
            .frame(width: knobSize, height: knobSize)
            .background {
                Circle()
                    .fill(Color.tempo.background)
                    .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 2)
            }
            .overlay { Circle().strokeBorder(Color.tempo.hairlineStrong, lineWidth: TempoSize.hairline) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEnabled else { return }
                if !isDragging {
                    isDragging = true
                    TempoHaptics.shared.triggerBegin()
                }
                offset = min(travel, max(0, value.translation.width))
                // The pull tightens toward the commit point, then snaps slack past it.
                TempoHaptics.shared.triggerUpdate(progress: offset / travel, breakAt: SlideToStart.completeAt)
            }
            .onEnded { _ in
                isDragging = false
                if offset / travel >= SlideToStart.completeAt {
                    withAnimation(Animation.tempo.resolved(Animation.tempo.press, reduceMotion: reduceMotion)) {
                        offset = travel
                    }
                    complete()
                } else {
                    TempoHaptics.shared.triggerEnd(completed: false)
                    reset()
                }
            }
    }

    private func complete() {
        guard isEnabled else { return }
        TempoHaptics.shared.triggerEnd(completed: true)
        withAnimation(Animation.tempo.resolved(Animation.tempo.snappy, reduceMotion: reduceMotion)) {
            didComplete = true
        }
        action()
        // The screen usually changes now; if it does not, the knob returns for another go.
        Task { @MainActor in
            try? await Task.sleep(for: Duration.milliseconds(900))
            reset()
        }
    }

    private func reset() {
        withAnimation(Animation.tempo.resolved(Animation.tempo.snappy, reduceMotion: reduceMotion)) {
            offset = 0
            didComplete = false
        }
    }

    /// A tap is not enough: hop the knob forward and back to show the gesture.
    private func nudge() {
        guard isEnabled, !isDragging, offset == 0 else { return }
        TempoHaptics.shared.tick()
        guard !reduceMotion else { return }
        withAnimation(Animation.tempo.press) {
            offset = 22
        }
        Task { @MainActor in
            try? await Task.sleep(for: Duration.milliseconds(140))
            withAnimation(Animation.tempo.snappy) {
                offset = 0
            }
        }
    }
}

// MARK: - Paint

/// The track's paint. At rest the washes are faint, like a first pale layer. The knob is the
/// brush: behind it the same washes show at full strength, and the edge of the paint stays
/// under the knob. On arrival the whole track is painted.
/// Animatable, so the painted edge glides back with the knob when it is released early.
private struct SlidePaint: View, Animatable {
    var progress: CGFloat
    var knobCenter: CGFloat
    var flood: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(progress, knobCenter), flood) }
        set {
            progress = newValue.first.first
            knobCenter = newValue.first.second
            flood = newValue.second
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let height: CGFloat = proxy.size.height
            let width: CGFloat = max(1, proxy.size.width)
            let painted: CGFloat = knobCenter + flood * width
            // Full strength behind the knob, fading out across the knob itself, so there is no
            // visible seam: the edge of the paint is always under the brush.
            let solid: CGFloat = min(1, max(0, (painted - height * 0.4) / width))
            let clear: CGFloat = min(1, max(solid + 0.001, (painted + height * 0.55) / width))
            ZStack(alignment: .topLeading) {
                BlotField(BlotField.track)
                    .opacity(0.5)
                BlotField(BlotField.track)
                    .mask {
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: Color.black, location: solid),
                                Gradient.Stop(color: Color.black.opacity(0), location: clear)
                            ],
                            startPoint: UnitPoint.leading,
                            endPoint: UnitPoint.trailing
                        )
                    }
            }
            .background(Color.tempo.background)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Slide to start") {
    SlideToStart(title: "Slide to meet someone", systemImage: "video") {}
        .padding()
}
