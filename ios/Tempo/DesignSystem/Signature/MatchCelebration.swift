import SwiftUI

// MARK: - MatchCelebration

/// The Match: a white screen. Two people, each inside a watercolor blot, overlapping,
/// "It's mutual." in 44 pt serif (the last word italic), one line of copy, a black "Say hello"
/// and a "Keep dating" text button. One soft scale-in, one heavy haptic; nothing else moves.
/// Full screen; brings its own background.
///
///     MatchCelebration(myPhoto: me.photoURL, myName: me.firstName, partnerPhoto: partner.photoUrl,
///                      partnerName: partner.firstName, onSayHello: { openChat() }, onKeepDating: { store.continueToNext() })
struct MatchCelebration: View {
    private let myPhoto: URL?
    private let myName: String
    private let partnerPhoto: URL?
    private let partnerName: String
    private let headline: String
    private let onSayHello: () -> Void
    private let onKeepDating: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown: Bool = false

    private let photoSize: CGFloat = 124
    private let separation: CGFloat = 88

    init(
        myPhoto: URL?,
        myName: String,
        partnerPhoto: URL?,
        partnerName: String,
        headline: String = "It's mutual.",
        onSayHello: @escaping () -> Void,
        onKeepDating: @escaping () -> Void
    ) {
        self.myPhoto = myPhoto
        self.myName = myName
        self.partnerPhoto = partnerPhoto
        self.partnerName = partnerName
        self.headline = headline
        self.onSayHello = onSayHello
        self.onKeepDating = onKeepDating
    }

    var body: some View {
        ZStack {
            InkBackground()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: TempoSpacing.lg)
                emblem
                copy
                    .padding(.top, TempoSpacing.xl)
                Spacer(minLength: TempoSpacing.lg)
                Spacer(minLength: 0)
                buttons
            }
            .tempoScreenPadding()
            .padding(.bottom, TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isShown || reduceMotion ? 1.0 : 0.96)
            .opacity(isShown ? 1.0 : 0.0)
        }
        .onAppear {
            TempoHaptics.shared.match()
            withAnimation(Animation.tempo.resolved(Animation.tempo.settle, reduceMotion: reduceMotion)) {
                isShown = true
            }
        }
    }

    // MARK: Pieces

    private var emblem: some View {
        let ringDiameter: CGFloat = photoSize + 14.0
        return ZStack {
            portrait(url: myPhoto, name: myName, blot: "BuddyBlush", turn: -14)
                .offset(x: -separation / 2.0)
            portrait(url: partnerPhoto, name: partnerName, blot: "BuddySage", turn: 22)
                .blendMode(BlendMode.multiply)
                .offset(x: separation / 2.0)
        }
        .frame(width: ringDiameter + separation + 2.0, height: ringDiameter + 2.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("You and \(partnerName)"))
    }

    /// Each person inside their own blot: no circles.
    private func portrait(url: URL?, name: String, blot: String, turn: Double) -> some View {
        BlotPortrait(url: url, name: name, blot: blot, size: photoSize, turn: turn)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            headlineText
                .tempoText(.displayL)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
            Text("You and \(partnerName) both said yes. Say something while it's fresh.")
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The headline with its last word in italic ("It's *mutual.*").
    private var headlineText: Text {
        let words: [String] = headline.split(separator: " ").map { String($0) }
        guard words.count > 1, let last = words.last else {
            return Text(headline)
        }
        let lead: String = words.dropLast().joined(separator: " ")
        return Text(lead + " ") + Text(last).italic()
    }

    private var buttons: some View {
        VStack(spacing: TempoSpacing.xs) {
            TempoButton("Say hello", action: onSayHello)
            TempoTextButton("Keep dating", action: onKeepDating)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("MatchCelebration") {
    MatchCelebration(myPhoto: nil, myName: "Seren", partnerPhoto: nil, partnerName: "Maya", onSayHello: {}, onKeepDating: {})
}
