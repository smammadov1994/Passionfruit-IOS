import SwiftUI

/// Searching and connecting, as one screen of moving paint (`SearchingPaint`): two washes circle
/// each other while the search runs, then fall together into one bloom behind the person who was
/// found. `partner == nil` is the search; non-nil is the found state.
struct DateLobbyView: View {
    let partner: Partner?

    @Environment(AppEnvironment.self) private var environment
    @Environment(DateStore.self) private var dateStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SearchingPaint(gather: partner == nil ? 0 : 1)
                .opacity(dateStore.didSearchTimeOut ? 0.45 : 1)
            VStack(spacing: TempoSpacing.sm) {
                // Searching: the words sit under the circling paint. Found: the person sits on it.
                Spacer(minLength: TempoSpacing.md)
                if partner == nil {
                    Spacer(minLength: TempoSpacing.md)
                    Spacer(minLength: TempoSpacing.md)
                }
                center
                Spacer(minLength: TempoSpacing.md)
                if partner == nil {
                    Spacer(minLength: TempoSpacing.md)
                }
                footer
            }
            .tempoScreenPadding()
            .padding(.vertical, TempoSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Animation.tempo.resolved(Animation.spring(response: 0.9, dampingFraction: 0.8), reduceMotion: reduceMotion), value: partner?.id)
        // A slow pulse while searching; it quickens into three beats when someone is found.
        .onAppear {
            if partner == nil {
                TempoHaptics.shared.startSearchPulse()
            } else {
                TempoHaptics.shared.found()
            }
        }
        .onChange(of: dateStore.didSearchTimeOut) { _, timedOut in
            if timedOut {
                TempoHaptics.shared.stopSearchPulse()
            } else if partner == nil {
                TempoHaptics.shared.startSearchPulse()
            }
        }
        .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: dateStore.didSearchTimeOut)
        .onChange(of: partner?.id) { _, found in
            if found == nil {
                TempoHaptics.shared.startSearchPulse()
            } else {
                TempoHaptics.shared.found()
            }
        }
        .onDisappear {
            TempoHaptics.shared.stopSearchPulse()
        }
    }

    @ViewBuilder
    private var center: some View {
        if let partner {
            VStack(spacing: TempoSpacing.sm) {
                BlotPortrait(
                    url: environment.imageCache.resolve(partner.photoUrl),
                    name: partner.firstName,
                    blot: "BuddyRose",
                    size: 148,
                    turn: 16
                )
                Text(partner.nameAndAge)
                    .tempoText(.title)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .multilineTextAlignment(.center)
                DateLobbyFoundDetail(partner: partner, videoState: dateStore.videoState)
            }
            .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
        } else if dateStore.didSearchTimeOut {
            VStack(spacing: TempoSpacing.sm) {
                Text("No one right now.")
                    .tempoText(.displayS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                Text("Nobody compatible came online this time. Try again in a little while.")
                    .tempoText(.body)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        } else {
            VStack(spacing: TempoSpacing.sm) {
                Text("Finding someone good…")
                    .tempoText(.displayS)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(AccessibilityTraits.isHeader)
                DateLobbySearchingDetail(
                    compatibleOnline: dateStore.compatibleOnline,
                    isOffline: dateStore.socketState != SocketConnectionState.connected
                )
                SearchTips()
                    .padding(.top, TempoSpacing.md)
            }
            .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if partner == nil && dateStore.didSearchTimeOut {
            VStack(spacing: TempoSpacing.xs) {
                TempoButton("Try again") {
                    dateStore.searchAgain()
                }
                TempoButton("Go back", variant: TempoButtonVariant.ghost) {
                    dateStore.goOffline()
                }
            }
        } else if partner == nil {
            TempoButton("Cancel", variant: TempoButtonVariant.ghost) {
                dateStore.goOffline()
            }
        } else {
            TempoButton("Leave", variant: TempoButtonVariant.ghost) {
                dateStore.leaveDate()
            }
        }
    }
}

// MARK: - Searching

private struct DateLobbySearchingDetail: View {
    let compatibleOnline: Int
    let isOffline: Bool

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            Text(line)
                .tempoText(.body)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .animation(Animation.tempo.snappy, value: compatibleOnline)
            if isOffline {
                CallStatusPill(text: SocketConnectionState.reconnecting.displayName, showsActivity: true)
            }
        }
    }

    private var line: String {
        if compatibleOnline <= 0 {
            return "Usually under a minute."
        }
        return "\(compatibleOnline) online now. Usually under a minute."
    }
}

// MARK: - Found

private struct DateLobbyFoundDetail: View {
    let partner: Partner
    let videoState: VideoConnectionState

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            if let locationLine = partner.locationLine {
                Text(locationLine)
                    .tempoText(.serifBody)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let intention = partner.intention {
                Chip(intention.displayName)
            }
            HStack(spacing: TempoSpacing.xs) {
                Text(statusLine)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                LoadingDots(color: Color.tempo.textSecondary, dotSize: 4)
                    .accessibilityHidden(true)
            }
            .padding(.top, TempoSpacing.xxs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenLine))
    }

    private var statusLine: String {
        switch videoState {
        case .reconnecting, .failed:
            return videoState.displayName
        case .idle, .connecting, .connected, .closed:
            return "Starting in a moment"
        }
    }

    private var spokenLine: String {
        "\(partner.summaryLine). \(statusLine)."
    }
}

// MARK: - Tips

/// One tip at a time while the search runs, changing every few seconds with a fade.
private struct SearchTips: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let interval: TimeInterval = 5

    private static let tips: [(symbol: String, text: String)] = [
        ("sun.max", String(localized: "Good light and a quiet corner go a long way.")),
        ("figure.walk", String(localized: "Leave whenever you like. No explanation needed.")),
        ("checkmark.shield", String(localized: "Report or block anyone, during a date or after.")),
        ("text.bubble", String(localized: "Stuck for words? The question card takes turns for you.")),
        ("heart", String(localized: "If you both say yes, it's a match. If not, nobody finds out."))
    ]

    var body: some View {
        TimelineView(.periodic(from: Date(), by: SearchTips.interval)) { context in
            let index: Int = Int(context.date.timeIntervalSinceReferenceDate / SearchTips.interval) % SearchTips.tips.count
            let tip = SearchTips.tips[index]
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Image(systemName: tip.symbol)
                    .font(Font.system(size: 15, weight: Font.Weight.regular))
                    .accessibilityHidden(true)
                Text(tip.text)
                    .tempoText(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.tempo.textPrimary)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background { Capsule().fill(Color.tempo.background.opacity(0.78)) }
            .overlay { Capsule().strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline) }
            .id(index)
            .transition(AnyTransition.opacity)
            .animation(Animation.tempo.resolved(Animation.tempo.fade, reduceMotion: reduceMotion), value: index)
        }
        .frame(minHeight: 64)
    }
}
