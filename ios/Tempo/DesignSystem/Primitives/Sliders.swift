import SwiftUI

// MARK: - Formatting

/// Value formatters for slider rows.
enum TempoSliderFormat {
    /// "29"
    static func integer(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// "25 km"
    static func kilometers(_ value: Double) -> String {
        "\(Int(value.rounded())) km"
    }
}

// MARK: - Track

/// The custom slider track with one or two thumbs. Fractions are 0...1 along the track.
private struct TempoSliderTrack: View {
    let lowerFraction: Double
    let upperFraction: Double
    let showsLowerThumb: Bool
    let lowerLabel: String
    let lowerValue: String
    let upperLabel: String
    let upperValue: String
    let onDrag: (Double) -> Void
    let onDragEnded: () -> Void
    let onAdjustLower: (AccessibilityAdjustmentDirection) -> Void
    let onAdjustUpper: (AccessibilityAdjustmentDirection) -> Void

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width)
        }
        .frame(height: TempoSize.hitTarget)
    }

    private func content(width: CGFloat) -> some View {
        let usable: CGFloat = max(1.0, width - thumbSize)
        let lowerX: CGFloat = CGFloat(lowerFraction) * usable
        let upperX: CGFloat = CGFloat(upperFraction) * usable
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let raw: CGFloat = (value.location.x - thumbSize / 2.0) / usable
                onDrag(Double(min(1.0, max(0.0, raw))))
            }
            .onEnded { _ in
                onDragEnded()
            }

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.tempo.surface2)
                .frame(height: trackHeight)
                .padding(.horizontal, thumbSize / 2.0)
            Capsule()
                .fill(Color.tempo.textPrimary)
                .frame(width: max(0.0, upperX - lowerX), height: trackHeight)
                .offset(x: lowerX + thumbSize / 2.0)
            if showsLowerThumb {
                thumb(x: lowerX, label: lowerLabel, value: lowerValue, adjust: onAdjustLower)
            }
            thumb(x: upperX, label: upperLabel, value: upperValue, adjust: onAdjustUpper)
        }
        .frame(width: width, height: TempoSize.hitTarget, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private func thumb(
        x: CGFloat,
        label: String,
        value: String,
        adjust: @escaping (AccessibilityAdjustmentDirection) -> Void
    ) -> some View {
        Circle()
            .fill(Color.tempo.background)
            .frame(width: thumbSize, height: thumbSize)
            .overlay { Circle().strokeBorder(Color.tempo.textPrimary, lineWidth: 1.5) }
            .offset(x: x)
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .accessibilityAdjustableAction(adjust)
    }
}

// MARK: - RangeSliderRow

/// A titled dual-thumb range slider (age range). Touch anywhere on the track; the nearer thumb follows.
///
///     RangeSliderRow(title: "Age", lower: $ageMin, upper: $ageMax, bounds: 18...80)
struct RangeSliderRow: View {
    private let title: String
    @Binding private var lower: Double
    @Binding private var upper: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    private let minimumSpan: Double
    private let format: (Double) -> String

    @State private var draggingLower: Bool? = nil

    init(
        title: String,
        lower: Binding<Double>,
        upper: Binding<Double>,
        bounds: ClosedRange<Double>,
        step: Double = 1,
        minimumSpan: Double = 1,
        format: @escaping (Double) -> String = TempoSliderFormat.integer
    ) {
        self.title = title
        self._lower = lower
        self._upper = upper
        self.bounds = bounds
        self.step = step
        self.minimumSpan = minimumSpan
        self.format = format
    }

    /// Integer convenience: `RangeSliderRow(title: "Age", lower: $prefs.ageMin, upper: $prefs.ageMax, bounds: 18...80)`.
    init(
        title: String,
        lower: Binding<Int>,
        upper: Binding<Int>,
        bounds: ClosedRange<Int>,
        minimumSpan: Int = 1
    ) {
        let lowerBinding: Binding<Double> = Binding<Double>(
            get: { Double(lower.wrappedValue) },
            set: { newValue in lower.wrappedValue = Int(newValue.rounded()) }
        )
        let upperBinding: Binding<Double> = Binding<Double>(
            get: { Double(upper.wrappedValue) },
            set: { newValue in upper.wrappedValue = Int(newValue.rounded()) }
        )
        let doubleBounds: ClosedRange<Double> = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.init(
            title: title,
            lower: lowerBinding,
            upper: upperBinding,
            bounds: doubleBounds,
            step: 1,
            minimumSpan: Double(minimumSpan),
            format: TempoSliderFormat.integer
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            header
            TempoSliderTrack(
                lowerFraction: fraction(lower),
                upperFraction: fraction(upper),
                showsLowerThumb: true,
                lowerLabel: "\(title), minimum",
                lowerValue: format(lower),
                upperLabel: "\(title), maximum",
                upperValue: format(upper),
                onDrag: handleDrag,
                onDragEnded: { draggingLower = nil },
                onAdjustLower: adjustLower,
                onAdjustUpper: adjustUpper
            )
        }
        .sensoryFeedback(SensoryFeedback.selection, trigger: lower)
        .sensoryFeedback(SensoryFeedback.selection, trigger: upper)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textPrimary)
            Spacer(minLength: TempoSpacing.sm)
            Text("\(format(lower)) – \(format(upper))")
                .tempoText(.numeral)
                .foregroundStyle(Color.tempo.textPrimary)
                .contentTransition(.numericText())
                .animation(Animation.tempo.snappy, value: lower)
                .animation(Animation.tempo.snappy, value: upper)
        }
        .accessibilityHidden(true)
    }

    private var span: Double {
        max(0.0001, bounds.upperBound - bounds.lowerBound)
    }

    private func fraction(_ value: Double) -> Double {
        min(1.0, max(0.0, (value - bounds.lowerBound) / span))
    }

    private func snapped(_ value: Double) -> Double {
        guard step > 0 else { return value }
        let steps: Double = ((value - bounds.lowerBound) / step).rounded()
        return min(bounds.upperBound, max(bounds.lowerBound, bounds.lowerBound + steps * step))
    }

    private func handleDrag(_ fraction: Double) {
        let value: Double = snapped(bounds.lowerBound + fraction * span)
        let movesLower: Bool
        if let draggingLower {
            movesLower = draggingLower
        } else {
            let toLower: Double = abs(value - lower)
            let toUpper: Double = abs(value - upper)
            if toLower == toUpper {
                movesLower = value < lower
            } else {
                movesLower = toLower < toUpper
            }
            draggingLower = movesLower
        }
        if movesLower {
            setLower(value)
        } else {
            setUpper(value)
        }
    }

    private func setLower(_ value: Double) {
        let clamped: Double = min(value, upper - minimumSpan)
        let next: Double = max(bounds.lowerBound, clamped)
        if next != lower {
            lower = next
        }
    }

    private func setUpper(_ value: Double) {
        let clamped: Double = max(value, lower + minimumSpan)
        let next: Double = min(bounds.upperBound, clamped)
        if next != upper {
            upper = next
        }
    }

    private func adjustLower(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: setLower(snapped(lower + step))
        case .decrement: setLower(snapped(lower - step))
        @unknown default: break
        }
    }

    private func adjustUpper(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: setUpper(snapped(upper + step))
        case .decrement: setUpper(snapped(upper - step))
        @unknown default: break
        }
    }
}

// MARK: - SliderRow

/// A titled single-value slider (maximum distance), matching `RangeSliderRow`.
///
///     SliderRow(title: "Maximum distance", value: $maxDistanceKm, bounds: 1...160, format: TempoSliderFormat.kilometers)
struct SliderRow: View {
    private let title: String
    @Binding private var value: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    private let format: (Double) -> String

    init(
        title: String,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        step: Double = 1,
        format: @escaping (Double) -> String = TempoSliderFormat.integer
    ) {
        self.title = title
        self._value = value
        self.bounds = bounds
        self.step = step
        self.format = format
    }

    /// Integer convenience: `SliderRow(title: "Maximum distance", value: $prefs.maxDistanceKm, bounds: 1...160, format: TempoSliderFormat.kilometers)`.
    init(
        title: String,
        value: Binding<Int>,
        bounds: ClosedRange<Int>,
        format: @escaping (Double) -> String = TempoSliderFormat.integer
    ) {
        let doubleBinding: Binding<Double> = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { newValue in value.wrappedValue = Int(newValue.rounded()) }
        )
        let doubleBounds: ClosedRange<Double> = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.init(title: title, value: doubleBinding, bounds: doubleBounds, step: 1, format: format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            header
            TempoSliderTrack(
                lowerFraction: 0.0,
                upperFraction: fraction(value),
                showsLowerThumb: false,
                lowerLabel: "",
                lowerValue: "",
                upperLabel: title,
                upperValue: format(value),
                onDrag: handleDrag,
                onDragEnded: {},
                onAdjustLower: { _ in },
                onAdjustUpper: adjust
            )
        }
        .sensoryFeedback(SensoryFeedback.selection, trigger: value)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textPrimary)
            Spacer(minLength: TempoSpacing.sm)
            Text(format(value))
                .tempoText(.numeral)
                .foregroundStyle(Color.tempo.textPrimary)
                .contentTransition(.numericText())
                .animation(Animation.tempo.snappy, value: value)
        }
        .accessibilityHidden(true)
    }

    private var span: Double {
        max(0.0001, bounds.upperBound - bounds.lowerBound)
    }

    private func fraction(_ input: Double) -> Double {
        min(1.0, max(0.0, (input - bounds.lowerBound) / span))
    }

    private func snapped(_ input: Double) -> Double {
        guard step > 0 else { return input }
        let steps: Double = ((input - bounds.lowerBound) / step).rounded()
        return min(bounds.upperBound, max(bounds.lowerBound, bounds.lowerBound + steps * step))
    }

    private func handleDrag(_ fraction: Double) {
        let next: Double = snapped(bounds.lowerBound + fraction * span)
        if next != value {
            value = next
        }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: value = snapped(value + step)
        case .decrement: value = snapped(value - step)
        @unknown default: break
        }
    }
}

// MARK: - Preview

private struct SlidersPreview: View {
    @State private var ageMin: Double = 26
    @State private var ageMax: Double = 38
    @State private var distance: Double = 25

    var body: some View {
        VStack(spacing: TempoSpacing.lg) {
            RangeSliderRow(title: "Age", lower: $ageMin, upper: $ageMax, bounds: 18...80)
            TempoDivider()
            SliderRow(title: "Maximum distance", value: $distance, bounds: 1...160, format: TempoSliderFormat.kilometers)
        }
        .tempoScreenPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inkBackground()
    }
}

#Preview("Sliders") {
    SlidersPreview()
}
