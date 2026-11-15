import SwiftUI

/// The Tonight tab: a greeting, the live count on a watercolor card, the user's matches, how a
/// date goes and a few tips, each on a painted card, with the slide-to-go-online control pinned
/// at the bottom and a heart in the header that opens Matches.
struct TonightView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DateStore.self) private var dateStore
    @Environment(ConfigStore.self) private var configStore
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(MatchesStore.self) private var matchesStore
    @Environment(AgentStore.self) private var agents
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasLoadedCount: Bool = false
    @State private var isRetrying: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    /// Seconds between refreshes of the online count while the tab is visible.
    private static let refreshInterval: Double = 15

    init() {}

    /// The count is refreshed only while this tab is on screen, the app is active and no date is running.
    private var shouldRefresh: Bool {
        scenePhase == ScenePhase.active && !dateStore.isActive
    }

    private var isOffline: Bool {
        guard hasLoadedCount else { return false }
        switch dateStore.socketState {
        case .disconnected, .reconnecting:
            return true
        case .connecting, .connected:
            return false
        }
    }

    private var onlineCount: Int? {
        if isOffline {
            return nil
        }
        if hasLoadedCount || dateStore.compatibleOnline > 0 {
            return dateStore.compatibleOnline
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                header
                notices
                hero
                matchesSection
                howItGoes
                premiumNote
            }
            .tempoScreenPadding()
            .padding(.top, TempoSpacing.md)
            .padding(.bottom, TempoSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        // Keeps scrolled content from showing through behind the status bar.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(Color.tempo.background.ignoresSafeArea(edges: .top))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            wayIn
        }
        .inkBackground()
        // The dots re-read their conversations whenever one moves.
        .task(id: matchesStore.matches) {
            await agents.refreshAll()
        }
        .task(id: shouldRefresh) {
            await refreshLoop()
        }
        #if DEBUG
        // `-startSearching` goes online at launch, to look at the search screen.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-startSearching") {
                try? await Task.sleep(for: Duration.seconds(1))
                goOnline()
            }
        }
        #endif
        .onChange(of: dateStore.permissionIssue) { _, issue in
            announcePermissionIssue(issue)
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    // MARK: Header

    /// Today's date, a greeting by name, then the day's allowance.
    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .center, spacing: TempoSpacing.sm) {
                Eyebrow(eyebrowText)
                Spacer(minLength: 0)
                matchesButton
            }
            ScreenHeader(title: greeting, emphasis: nameEmphasis)
            allowance
        }
    }

    /// The way to Matches (and from there to You): a heart, with a dot while something is unread.
    private var matchesButton: some View {
        IconCircleButton(
            systemImage: "heart",
            accessibilityLabel: matchesStore.totalUnread > 0
                ? String(localized: "Matches, new messages")
                : String(localized: "Matches"),
            kind: IconCircleButtonKind.outlined,
            size: 44,
            action: { router.select(AppTab.matches) }
        )
        .overlay(alignment: .topTrailing) {
            if matchesStore.totalUnread > 0 {
                Circle()
                    .fill(Color.tempo.accent)
                    .frame(width: 11, height: 11)
                    .overlay { Circle().stroke(Color.tempo.background, lineWidth: 2) }
                    .offset(x: -1, y: 1)
                    .accessibilityHidden(true)
            }
        }
    }

    /// "Tonight · Saturday, November 14"
    private var eyebrowText: String {
        let day: String = Date().formatted(Date.FormatStyle().weekday(.wide).month(.wide).day())
        return String(localized: "Tonight · \(day)")
    }

    private var greeting: String {
        let hour: Int = Calendar.current.component(Calendar.Component.hour, from: Date())
        let hasName: Bool = nameEmphasis != nil
        switch hour {
        case 5..<12:
            return hasName ? String(localized: "Good morning,") : String(localized: "Good morning.")
        case 12..<18:
            return hasName ? String(localized: "Good afternoon,") : String(localized: "Good afternoon.")
        default:
            return hasName ? String(localized: "Good evening,") : String(localized: "Good evening.")
        }
    }

    /// "Sam." in italics after the greeting; nil when there is no name yet.
    private var nameEmphasis: String? {
        let name: String = (session.user?.firstName ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return name.isEmpty ? nil : "\(name)."
    }

    @ViewBuilder
    private var allowance: some View {
        if session.isPremium {
            PremiumBadge(text: String(localized: "Unlimited dates"))
                .accessibilityLabel(Text("\(Brand.premiumName). Unlimited dates."))
        } else {
            Button {
                router.openPaywall()
            } label: {
                DatesLeftPill(remaining: dateStore.datesRemainingToday, dailyLimit: configStore.freeDailyDates)
            }
            .buttonStyle(TempoPressStyle(scale: 0.96))
            .accessibilityHint(Text("Opens \(Brand.premiumName)"))
        }
    }

    // MARK: Notices

    /// Going online is only possible from this tab, and Core raises a blocked camera or
    /// microphone while the date flow is still closed, so this card is the one place it is shown.
    @ViewBuilder
    private var notices: some View {
        if let issue = dateStore.permissionIssue {
            PermissionIssueCard(
                issue: issue,
                onOpenSettings: { dateStore.openSettings() },
                onDismiss: { dateStore.dismissPermissionIssue() }
            )
        } else if isOffline {
            ErrorBanner(
                message: String(localized: "You're offline. The count will come back when you do."),
                onRetry: retryAction
            )
        }
    }

    private var retryAction: (() -> Void)? {
        if isRetrying {
            return nil
        }
        return { retry() }
    }

    // MARK: Orb

    /// What is happening right now, on a watercolor card. The way in is the slide control pinned
    /// to the bottom of the screen, not this card.
    private var hero: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Eyebrow(String(localized: "Right now"))
            Spacer(minLength: TempoSpacing.md)
            heroFigure
            Text(heroLine)
                .tempoText(.serifBody)
                .foregroundStyle(Color.tempo.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .leading)
        .background {
            BlotField(BlotField.tonight, isActive: shouldRefresh)
        }
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous)
                .strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    /// The live count as a large numeral; nothing while it is unknown.
    @ViewBuilder
    private var heroFigure: some View {
        if let count = onlineCount, count > 0 {
            Text(verbatim: "\(count)")
                .font(Font.system(size: 64, weight: Font.Weight.medium, design: Font.Design.serif))
                .monospacedDigit()
                .foregroundStyle(Color.tempo.textPrimary)
                .contentTransition(ContentTransition.numericText())
                .animation(Animation.tempo.snappy, value: count)
        }
    }

    private var heroLine: String {
        guard let count = onlineCount else {
            return String(localized: "Ready when you are.")
        }
        if count == 0 {
            return String(localized: "Quiet right now. Go online and we'll pair you when someone arrives.")
        }
        if count == 1 {
            return String(localized: "person you could meet is online.")
        }
        return String(localized: "people you could meet are online.")
    }

    // MARK: Way in

    /// Pinned to the bottom of the screen: slide to go online. Deliberate, because the camera turns on.
    private var wayIn: some View {
        SlideToStart(title: slideTitle, systemImage: "video") {
            goOnline()
        }
        .disabled(dateStore.isStartingUp)
        .tempoScreenPadding()
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.xs)
        .background {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.tempo.background.opacity(0), location: 0),
                    Gradient.Stop(color: Color.tempo.background, location: 0.3),
                    Gradient.Stop(color: Color.tempo.background, location: 1)
                ],
                startPoint: UnitPoint.top,
                endPoint: UnitPoint.bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var slideTitle: String {
        if let count = onlineCount, count == 0 {
            return String(localized: "Slide to go online")
        }
        return String(localized: "Slide to meet someone")
    }

    // MARK: Matches

    private static let maximumMatchesShown: Int = 8

    /// People who said yes back, one tap from their chat. Hidden until there is a match.
    @ViewBuilder
    private var matchesSection: some View {
        let matches: [Match] = Array(matchesStore.matches.prefix(TonightView.maximumMatchesShown))
        if !matches.isEmpty {
            TonightPlainCard {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(matchesTitle)
                        Spacer(minLength: TempoSpacing.xs)
                        Button {
                            router.select(AppTab.matches)
                        } label: {
                            Text("See all")
                                .tempoText(.secondaryEmphasis)
                                .foregroundStyle(Color.tempo.textPrimary)
                        }
                        .buttonStyle(TempoPressStyle(scale: 0.96))
                    }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: TempoSpacing.sm) {
                            ForEach(matches) { match in
                                matchButton(match)
                            }
                        }
                        .padding(.vertical, TempoSpacing.xxs)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
    }

    private var matchesTitle: String {
        let unread: Int = matchesStore.totalUnread
        if unread == 1 {
            return String(localized: "1 new message")
        }
        if unread > 1 {
            return String(localized: "\(unread) new messages")
        }
        return String(localized: "Your matches")
    }

    private func matchButton(_ match: Match) -> some View {
        Button {
            router.openChat(matchId: match.id)
        } label: {
            VStack(spacing: TempoSpacing.xs) {
                matchBlot(match)
                Text(match.partner.firstName)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(TempoPressStyle(scale: 0.96))
        .accessibilityLabel(Text(match.unreadCount > 0 ? "\(match.partner.firstName), new message" : match.partner.firstName))
        .accessibilityHint(Text("Opens your chat"))
    }

    /// A match as a watercolor blot in the colour of its dot: the photo sits inside it when there
    /// is one, the initial when there is not. A vermilion spot marks unread messages.
    private func matchBlot(_ match: Match) -> some View {
        let size: CGFloat = 64
        let persona: AgentPersona = matchCast[match.id] ?? AgentPersona.generate(seed: match.id)
        let photo: URL? = environment.imageCache.resolve(match.partner.photoUrl)
        return BlotPortrait(
            url: photo,
            name: match.partner.firstName,
            blot: AgentBuddy.asset(for: persona.hue),
            size: size,
            turn: persona.tilt * 6
        )
        .overlay(alignment: .topTrailing) {
            if match.unreadCount > 0 {
                Circle()
                    .fill(Color.tempo.accent)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().stroke(Color.tempo.background, lineWidth: 2) }
                    .accessibilityHidden(true)
            }
        }
    }

    /// The dot assigned to each match, the same everywhere in the app.
    private var matchCast: [String: AgentPersona] {
        AgentPersona.cast(for: matchesStore.matches.sorted { $0.matchedAt < $1.matchedAt }.map(\.id))
    }

    // MARK: From your dots

    private static let maximumRecommendations: Int = 3

    /// What each match's dot recommends right now, most recent conversation first. With no
    /// matches yet, the three steps of a date take this place.
    @ViewBuilder
    private var howItGoes: some View {
        let recommendations: [DotRecommendation] = dotRecommendations
        if recommendations.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Eyebrow(String(localized: "How a date goes"))
                TonightTintCard(tint: Color.tempo.pastelSage) {
                    TonightStep(
                        number: 1,
                        title: String(localized: "\(TempoFormat.durationHeadline(configStore.dateDuration)), face to face"),
                        detail: String(localized: "You're paired on video with someone compatible who is online now.")
                    )
                }
                TonightTintCard(tint: Color.tempo.pastelButter) {
                    TonightStep(
                        number: 2,
                        title: String(localized: "A question to share"),
                        detail: String(localized: "Take \(TempoFormat.durationAdjective(configStore.turnDuration)) turns answering it, or pass.")
                    )
                }
                TonightTintCard(tint: Color.tempo.pastelBlush) {
                    TonightStep(
                        number: 3,
                        title: String(localized: "Yes or no, in private"),
                        detail: String(localized: "If you both say yes, it's a match. If not, nobody finds out.")
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Eyebrow(String(localized: "From your dots"))
                ForEach(recommendations) { recommendation in
                    Button {
                        open(recommendation)
                    } label: {
                        TonightTintCard(tint: AgentBuddy.color(for: recommendation.persona.hue).opacity(0.28)) {
                            DotRecommendationRow(recommendation: recommendation)
                        }
                    }
                    .buttonStyle(TempoPressStyle(scale: 0.98))
                    .accessibilityHint(Text("Opens your chat with \(recommendation.partnerName)"))
                }
            }
        }
    }

    /// One recommendation per match that has a brief: what the dot noticed and what to do next.
    private var dotRecommendations: [DotRecommendation] {
        let cast: [String: AgentPersona] = AgentPersona.cast(
            for: matchesStore.matches.sorted { $0.matchedAt < $1.matchedAt }.map(\.id)
        )
        var result: [DotRecommendation] = []
        for match in matchesStore.matches {
            guard let brief = agents.brief(for: match.id) else { continue }
            let persona: AgentPersona = cast[match.id] ?? AgentPersona.generate(seed: match.id)
            var action: String?
            var draft: String?
            for item in agents.items(for: match.id) {
                if case .plan(let title, let start, _) = item.kind {
                    let day: String = start.formatted(Date.FormatStyle().weekday(.wide).hour().minute())
                    action = String(localized: "Put it in the calendar: \(title), \(day).")
                    break
                }
            }
            if let first = agents.suggestions(for: match.id).first {
                draft = first
                if action == nil {
                    action = String(localized: "Try: “\(first)”")
                }
            }
            if action == nil {
                action = brief.standing == .waiting ? persona.temper.patience : persona.temper.nudge
            }
            result.append(DotRecommendation(
                id: match.id,
                partnerName: match.partner.firstName,
                persona: persona,
                status: brief.status,
                action: action ?? "",
                draft: draft
            ))
            if result.count == TonightView.maximumRecommendations { break }
        }
        return result
    }

    private func open(_ recommendation: DotRecommendation) {
        if let draft = recommendation.draft {
            router.openChat(matchId: recommendation.id, draft: draft)
        } else {
            router.openChat(matchId: recommendation.id)
        }
    }

    // MARK: Premium

    /// One painted card for free members; Premium members see nothing here.
    @ViewBuilder
    private var premiumNote: some View {
        if !session.isPremium {
            Button {
                router.openPaywall()
            } label: {
                TonightArtCard(art: "ArtGold") {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Eyebrow(Brand.premiumName, color: Color.tempo.premium)
                        Text("Never run out of evenings.")
                            .tempoText(.titleS)
                            .foregroundStyle(Color.tempo.textPrimary)
                        Text("Unlimited dates, dealbreaker filters, front of the line.")
                            .tempoText(.secondary)
                            .foregroundStyle(Color.tempo.textSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 230, alignment: .leading)
                }
            }
            .buttonStyle(TempoPressStyle(scale: 0.98))
            .accessibilityHint(Text("Opens \(Brand.premiumName)"))
        }
    }

    private func goOnline() {
        guard !dateStore.isStartingUp else { return }
        dateStore.goOnline()
    }

    /// The card appears above the orb the user just tapped; say so for VoiceOver and with a haptic.
    private func announcePermissionIssue(_ issue: PermissionIssue?) {
        guard let issue else { return }
        Haptics.warning()
        CallAnnouncer.announce("\(issue.title). \(issue.message)")
    }

    // MARK: Refresh

    private func refreshLoop() async {
        guard shouldRefresh else { return }
        while !Task.isCancelled {
            await dateStore.refreshOnlineCount()
            await dateStore.refreshUsage()
            if Task.isCancelled {
                return
            }
            hasLoadedCount = true
            do {
                try await Task.sleep(for: Duration.seconds(TonightView.refreshInterval))
            } catch {
                return
            }
        }
    }

    private func retry() {
        tasks.run("retry") {
            isRetrying = true
            await dateStore.refreshOnlineCount()
            await dateStore.refreshUsage()
            isRetrying = false
        }
    }
}

// MARK: - Dates left

/// "3 dates left today" with one pip per free date. Free members only.
private struct DatesLeftPill: View {
    let remaining: Int?
    let dailyLimit: Int

    private var text: String {
        guard let remaining else {
            if dailyLimit == 1 {
                return String(localized: "1 free date a day")
            }
            return String(localized: "\(dailyLimit) free dates a day")
        }
        return TempoFormat.datesLeft(remaining)
    }

    /// Pips are shown for small daily limits only; a long row would not fit the header.
    private var pipCount: Int {
        guard remaining != nil, dailyLimit > 0, dailyLimit <= 8 else { return 0 }
        return dailyLimit
    }

    var body: some View {
        HStack(spacing: TempoSpacing.xs) {
            if pipCount > 0 {
                pips
            }
            Text(text)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, TempoSpacing.xs)
        .tempoSurface(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(AccessibilityTraits.isButton)
    }

    private var pips: some View {
        let left: Int = max(0, remaining ?? 0)
        return HStack(spacing: 3) {
            ForEach(0..<pipCount, id: \.self) { index in
                Circle()
                    .fill(index < left ? Color.tempo.accent : Color.tempo.hairline)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// The Tonight card: white, 28 pt corners, a hairline, and a watercolor wash in the trailing
/// corner. Content sits on the leading side, clear of the paint.
private struct TonightArtCard<Content: View>: View {
    let art: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                Image(art)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 354, height: 170, alignment: .topTrailing)
                    .accessibilityHidden(true)
            }
            .background(Color.tempo.background)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous)
                    .strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline)
            }
    }
}

/// A dot's recommendation for one match.
private struct DotRecommendation: Identifiable {
    let id: String
    let partnerName: String
    let persona: AgentPersona
    let status: String
    let action: String
    /// A reply to place in the composer when the card is tapped.
    let draft: String?
}

/// The dot, who it is watching, what it noticed and what it suggests.
private struct DotRecommendationRow: View {
    let recommendation: DotRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            AgentBuddy(persona: recommendation.persona, size: 46)
                .frame(width: 52, height: 58, alignment: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(String(localized: "\(recommendation.persona.name) on \(recommendation.partnerName)"))
                Text(recommendation.status)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(recommendation.action)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineLimit(3)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(Font.system(size: 13, weight: Font.Weight.semibold))
                .foregroundStyle(Color.tempo.textTertiary)
                .padding(.top, TempoSpacing.xxs)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A plain white Tonight card with a hairline: no wash, no tint.
private struct TonightPlainCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempo.background)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous)
                    .strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline)
            }
    }
}

/// A Tonight card filled edge to edge with one light colour: no painted wash.
private struct TonightTintCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sheet, style: .continuous))
    }
}

/// A serif step number with a title and one line of detail.
private struct TonightStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
            Text(verbatim: "\(number)")
                .font(Font.system(size: 34, weight: Font.Weight.medium, design: Font.Design.serif))
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(minWidth: 24, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(title)
                    .tempoText(.bodyEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                Text(detail)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Tonight") {
    TonightView()
        .environment(AppRouter())
        .tempoEnvironment(AppEnvironment.demo())
}
