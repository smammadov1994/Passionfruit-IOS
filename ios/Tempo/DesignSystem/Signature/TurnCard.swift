import SwiftUI

// MARK: - TurnCard

/// The Turn Card: the icebreaker overlay, styled like a prompt card. A WHITE card (radius 16,
/// the one soft shadow) with an eyebrow, the question in 24 pt serif and a two-sided chess-clock
/// bar; the active half fills accent and drains against `turnEndsAt`. A black "Pass" capsule
/// appears only on my turn. Drag the card down to tuck it into a small white chip; tap the chip
/// to bring it back. It never touches audio or video.
///
/// Place it at the bottom of the call screen, above the control bar.
///
///     TurnCard(question: ice.question, questionNumber: ice.index + 1, myName: "You", partnerName: partner.firstName,
///              isMyTurn: ice.isMyTurn, turnEndsAt: ice.turnEndsAt, turnDuration: ice.turnDuration,
///              onPass: { store.passTurn() }, isCollapsed: $isIcebreakerHidden)
struct TurnCard: View {
    private let question: String
    private let questionNumber: Int
    private let myName: String
    private let partnerName: String
    private let isMyTurn: Bool
    private let turnEndsAt: Date
    private let turnDuration: TimeInterval
    private let onPass: () -> Void
    @Binding private var isCollapsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var passCount: Int = 0

    init(
        question: String,
        questionNumber: Int,
        myName: String,
        partnerName: String,
        isMyTurn: Bool,
        turnEndsAt: Date,
        turnDuration: TimeInterval,
        onPass: @escaping () -> Void,
        isCollapsed: Binding<Bool>
    ) {
        self.question = question
        self.questionNumber = questionNumber
        self.myName = myName
        self.partnerName = partnerName
        self.isMyTurn = isMyTurn
        self.turnEndsAt = turnEndsAt
        self.turnDuration = turnDuration
        self.onPass = onPass
        self._isCollapsed = isCollapsed
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isCollapsed {
                chip
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            } else {
                card
                    .transition(AnyTransition.tempoRise(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: isCollapsed)
        .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.medium), trigger: isMyTurn)
        .sensoryFeedback(SensoryFeedback.selection, trigger: passCount)
    }

    // MARK: Card

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            header
            questionText
            TurnClockBar(
                leftLabel: leftLabel,
                rightLabel: partnerName,
                isLeftActive: isMyTurn,
                endsAt: turnEndsAt,
                duration: turnDuration
            )
            if isMyTurn {
                passButton
                    .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            }
        }
        .padding(20)
        .tempoSurface(in: cardShape, isFloating: true)
        .contentShape(cardShape)
        .offset(y: dragOffset)
        .gesture(collapseDrag)
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: isMyTurn)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Hide question")) {
            setCollapsed(true)
        }
    }

    private var leftLabel: String {
        myName.isEmpty ? "You" : myName
    }

    private var turnLine: String {
        isMyTurn ? "Your turn" : "\(partnerName)'s turn"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Question \(questionNumber)")
            Spacer(minLength: TempoSpacing.sm)
            Text(turnLine)
                .tempoText(.eyebrow)
                .foregroundStyle(isMyTurn ? Color.tempo.accentText : Color.tempo.textSecondary)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
        }
    }

    private var questionText: some View {
        ZStack(alignment: .topLeading) {
            Text(question)
                .tempoText(.titleS)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(question)
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
        .animation(Animation.tempo.resolved(Animation.tempo.gentle, reduceMotion: reduceMotion), value: question)
    }

    private var passButton: some View {
        Button(action: pass) {
            HStack(spacing: TempoSpacing.xs) {
                Text("Pass")
                Image(systemName: "arrow.right")
                    .imageScale(Image.Scale.small)
                    .accessibilityHidden(true)
            }
            .tempoText(.button)
            .foregroundStyle(Color.tempo.onAccent)
            .frame(maxWidth: .infinity, minHeight: TempoSize.buttonRegular)
            .background { Capsule().fill(Color.tempo.textPrimary) }
            .contentShape(Capsule())
        }
        .buttonStyle(TempoPressStyle(scale: 0.97))
        .accessibilityLabel(Text("Pass"))
        .accessibilityHint(Text("Hands the question to \(partnerName)"))
    }

    // MARK: Chip

    private var chip: some View {
        Button {
            setCollapsed(false)
        } label: {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "text.bubble")
                    .font(Font.system(size: 15, weight: Font.Weight.regular))
                    .foregroundStyle(isMyTurn ? Color.tempo.accent : Color.tempo.textSecondary)
                    .accessibilityHidden(true)
                Text(turnLine)
                    .tempoText(.secondaryEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                TurnSecondsLabel(endsAt: turnEndsAt)
                Image(systemName: "chevron.up")
                    .font(Font.system(size: 12, weight: Font.Weight.regular))
                    .foregroundStyle(Color.tempo.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TempoSpacing.md)
            .frame(minHeight: TempoSize.hitTarget)
            .tempoSurface(in: Capsule(), isFloating: true)
            .contentShape(Capsule())
        }
        .buttonStyle(TempoPressStyle(scale: 0.95))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Show question"))
        .accessibilityValue(Text(turnLine))
        .accessibilityAddTraits(AccessibilityTraits.isButton)
        .accessibilityAction {
            setCollapsed(false)
        }
    }

    // MARK: Behaviour

    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let distance: CGFloat = value.translation.height
                dragOffset = distance > 0 ? distance : distance * 0.12
            }
            .onEnded { value in
                let far: Bool = value.translation.height > 70
                let fast: Bool = value.predictedEndTranslation.height > 180
                withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
                    dragOffset = 0
                    if far || fast {
                        isCollapsed = true
                    }
                }
            }
    }

    private func setCollapsed(_ collapsed: Bool) {
        withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
            isCollapsed = collapsed
        }
    }

    private func pass() {
        passCount += 1
        onPass()
    }
}

// MARK: - Chess-clock bar

/// Two halves meeting in the middle on a surface-2 track. The active half is full accent at the
/// start of the turn and drains toward the centre; the other half rests. Names sit under each half.
private struct TurnClockBar: View {
    let leftLabel: String
    let rightLabel: String
    let isLeftActive: Bool
    let endsAt: Date
    let duration: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30.0, paused: !isActive)) { context in
            bar(now: context.date)
        }
        .tempoTracksActivity($isActive)
    }

    private func bar(now: Date) -> some View {
        let remaining: TimeInterval = TempoCountdown.remaining(until: endsAt, now: now)
        let seconds: Int = TempoCountdown.wholeSeconds(remaining)
        let fraction: Double = TempoCountdown.fraction(until: endsAt, now: now, total: duration)
        let spoken: String = isLeftActive ? "Your turn" : "\(rightLabel)'s turn"

        return VStack(spacing: TempoSpacing.xs) {
            HStack(spacing: 4) {
                half(active: isLeftActive, fraction: fraction, anchor: UnitPoint.trailing)
                half(active: !isLeftActive, fraction: fraction, anchor: UnitPoint.leading)
            }
            .frame(height: 6)
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                side(label: leftLabel, active: isLeftActive, seconds: seconds, leading: true)
                Spacer(minLength: TempoSpacing.xs)
                side(label: rightLabel, active: !isLeftActive, seconds: seconds, leading: false)
            }
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: isLeftActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityValue(Text("\(seconds) seconds left"))
        .accessibilityAddTraits(AccessibilityTraits.updatesFrequently)
    }

    private func side(label: String, active: Bool, seconds: Int, leading: Bool) -> some View {
        HStack(spacing: 6) {
            if !leading, active {
                secondsText(seconds)
            }
            Text(label)
                .tempoText(.secondaryEmphasis)
                .foregroundStyle(active ? Color.tempo.textPrimary : Color.tempo.textSecondary)
                .lineLimit(1)
            if leading, active {
                secondsText(seconds)
            }
        }
    }

    private func secondsText(_ seconds: Int) -> some View {
        Text("\(seconds)")
            .tempoText(.numeralS)
            .foregroundStyle(Color.tempo.accentText)
            .contentTransition(.numericText(countsDown: true))
            .animation(Animation.tempo.snappy, value: seconds)
    }

    private func half(active: Bool, fraction: Double, anchor: UnitPoint) -> some View {
        Capsule()
            .fill(Color.tempo.surface2)
            .overlay {
                Rectangle()
                    .fill(Color.tempo.accent)
                    .scaleEffect(x: active ? CGFloat(fraction) : 0.0, y: 1.0, anchor: anchor)
            }
            .clipShape(Capsule())
    }
}

/// Whole seconds left in the turn, refreshed twice a second. Used by the collapsed chip.
private struct TurnSecondsLabel: View {
    let endsAt: Date

    var body: some View {
        TimelineView(.periodic(from: Date.now, by: 0.5)) { context in
            label(now: context.date)
        }
    }

    private func label(now: Date) -> some View {
        let seconds: Int = TempoCountdown.wholeSeconds(TempoCountdown.remaining(until: endsAt, now: now))
        return Text("\(seconds)")
            .tempoText(.numeralS)
            .foregroundStyle(Color.tempo.textSecondary)
            .contentTransition(.numericText(countsDown: true))
            .animation(Animation.tempo.snappy, value: seconds)
    }
}

// MARK: - Preview

private struct TurnCardPreview: View {
    @State private var isCollapsed: Bool = false
    @State private var isMyTurn: Bool = true
    @State private var index: Int = 0
    @State private var endsAt: Date = Date().addingTimeInterval(30)

    private let questions: [String] = [
        "What's a small thing that made this week better?",
        "Which film could you watch every year?",
        "What did you want to be at nine?"
    ]

    var body: some View {
        VStack {
            Spacer()
            TurnCard(
                question: questions[index % questions.count],
                questionNumber: index + 1,
                myName: "You",
                partnerName: "Maya",
                isMyTurn: isMyTurn,
                turnEndsAt: endsAt,
                turnDuration: 30,
                onPass: advance,
                isCollapsed: $isCollapsed
            )
        }
        .tempoScreenPadding()
        .padding(.bottom, TempoSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Color.tempo.textSecondary.ignoresSafeArea() }
    }

    private func advance() {
        if !isMyTurn {
            index += 1
        }
        isMyTurn.toggle()
        endsAt = Date().addingTimeInterval(30)
    }
}

#Preview("TurnCard") {
    TurnCardPreview()
}
