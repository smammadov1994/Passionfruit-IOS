import SwiftUI

/// The Matches tab: people who said yes back, newest activity first. Rows open the chat.
struct MatchesView: View {
    @Environment(MatchesStore.self) private var matchesStore
    @Environment(AgentStore.self) private var agents
    @Environment(AppRouter.self) private var router

    @State private var loadError: String?
    @State private var pendingUnmatch: Match?
    @State private var tasks: TaskBag = TaskBag()

    init() {}

    private var showsSkeleton: Bool {
        matchesStore.matches.isEmpty && !matchesStore.hasLoaded && loadError == nil
    }

    private var showsEmptyState: Bool {
        matchesStore.matches.isEmpty && matchesStore.hasLoaded && loadError == nil
    }

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.matchesPath) {
            list
                .inkBackground()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { matchId in
                    ChatView(matchId: matchId)
                }
        }
        .task {
            await load()
        }
        // The agents re-read whenever a conversation moves.
        .task(id: matchesStore.matches) {
            await agents.refreshAll()
        }
        .confirmationDialog(
            Text(unmatchTitle),
            isPresented: unmatchBinding,
            titleVisibility: .visible,
            actions: { unmatchActions },
            message: { Text("The conversation disappears for both of you. This can't be undone.") }
        )
        .onDisappear {
            tasks.cancelAll()
        }
    }

    // MARK: List

    private var list: some View {
        List {
            header
                .matchesListRow()
            if let loadError {
                ErrorBanner(message: loadError, onRetry: { retry() })
                    .matchesListRow()
            }
            if showsSkeleton {
                skeletonRows
            } else if showsEmptyState {
                emptyState
                    .matchesListRow()
            } else {
                matchRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                IconCircleButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: String(localized: "Back to Tonight"),
                    kind: IconCircleButtonKind.outlined,
                    size: 44,
                    action: { router.select(AppTab.tonight) }
                )
                Spacer()
                IconCircleButton(
                    systemImage: "gearshape",
                    accessibilityLabel: String(localized: "You and settings"),
                    kind: IconCircleButtonKind.outlined,
                    size: 44,
                    action: { router.select(AppTab.you) }
                )
            }
            ScreenHeader(
                title: String(localized: "Matches"),
                subtitle: String(localized: "Tap a dot to see what it has for you.")
            )
        }
        .padding(.top, TempoSpacing.xs)
        .padding(.bottom, TempoSpacing.xs)
    }

    private var matchRows: some View {
        // Cast in a stable order (oldest match first), so a character does not change when a new
        // message reorders the list.
        let cast: [String: AgentPersona] = AgentPersona.cast(
            for: matchesStore.matches.sorted { $0.matchedAt < $1.matchedAt }.map(\.id)
        )
        return ForEach(matchesStore.matches) { match in
            MatchAgentCard(match: match, persona: cast[match.id] ?? AgentPersona.generate(seed: match.id))
                .matchesListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingUnmatch = match
                } label: {
                    Label(String(localized: "Unmatch"), systemImage: "person.crop.circle.badge.xmark")
                }
                .tint(Color.tempo.danger)
            }
            .accessibilityAction(named: Text("Unmatch")) {
                pendingUnmatch = match
            }
        }
    }

    private var skeletonRows: some View {
        ForEach(0..<4, id: \.self) { _ in
            MatchRowSkeleton()
                .matchesListRow()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading your matches"))
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "heart",
            title: String(localized: "No matches yet"),
            message: String(localized: "When it's mutual, they'll be here. Go online to meet someone."),
            actionTitle: String(localized: "Go back"),
            action: { router.select(AppTab.tonight) }
        )
        .padding(.top, TempoSpacing.xxl)
    }

    // MARK: Unmatch

    private var unmatchTitle: String {
        guard let match = pendingUnmatch else { return String(localized: "Unmatch?") }
        return String(localized: "Unmatch \(match.partner.firstName)?")
    }

    private var unmatchBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingUnmatch != nil },
            set: { isPresented in
                if !isPresented {
                    pendingUnmatch = nil
                }
            }
        )
    }

    @ViewBuilder
    private var unmatchActions: some View {
        if let match = pendingUnmatch {
            Button(String(localized: "Unmatch"), role: .destructive) {
                unmatch(match)
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }

    private func unmatch(_ match: Match) {
        let matchId: String = match.id
        let name: String = match.partner.firstName
        tasks.run("unmatch-" + matchId) {
            let removed: Bool = await matchesStore.unmatch(matchId: matchId)
            if removed {
                router.showMessage(String(localized: "You unmatched \(name)."), systemImage: "checkmark.circle")
            }
            // A failure is left in `matchesStore.lastError`; the shell shows it as a toast.
        }
    }

    // MARK: Loading

    private func load() async {
        loadError = nil
        matchesStore.lastError = nil
        await matchesStore.load()
        if Task.isCancelled {
            return
        }
        if let error = matchesStore.lastError {
            // Shown inline here, so take it before the shell's toast does.
            matchesStore.lastError = nil
            loadError = error.userMessage
        }
    }

    private func retry() {
        tasks.run("load") {
            await load()
        }
    }
}

// MARK: - Rows

/// One match: avatar, name in serif, the last message, when, and an accent dot when unread.
struct MatchRow: View {
    private let match: Match

    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session

    init(match: Match) {
        self.match = match
    }

    private var isUnread: Bool {
        match.unreadCount > 0
    }

    private var preview: String {
        guard let message = match.lastMessage else {
            return String(localized: "New match. Say hello.")
        }
        if message.senderId == session.userId {
            return String(localized: "You: \(message.text)")
        }
        return message.text
    }

    private var timeText: String {
        TempoFormat.listTime(match.lastActivityAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: TempoSpacing.sm) {
                AvatarView(
                    url: environment.imageCache.resolve(match.partner.photoUrl),
                    name: match.partner.firstName,
                    size: 56,
                    ring: isUnread ? AvatarRing.ember : AvatarRing.hairline
                )
                texts
                trailing
            }
            .padding(.vertical, TempoSpacing.md)
            .frame(minHeight: 84)
            TempoDivider()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityHint(Text("Opens the conversation"))
        .accessibilityAddTraits(AccessibilityTraits.isButton)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.partner.firstName)
                .tempoText(.titleS)
                .foregroundStyle(Color.tempo.textPrimary)
                .lineLimit(1)
            Text(preview)
                .tempoText(.secondary)
                .foregroundStyle(isUnread ? Color.tempo.textPrimary : Color.tempo.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: TempoSpacing.xs) {
            Text(timeText)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .lineLimit(1)
            Circle()
                .fill(Color.tempo.accent)
                .frame(width: 9, height: 9)
                .opacity(isUnread ? 1.0 : 0.0)
        }
    }

    private var spokenLabel: String {
        let name: String = match.partner.firstName
        if isUnread {
            return String(localized: "\(name), unread. \(preview). \(timeText)")
        }
        return String(localized: "\(name). \(preview). \(timeText)")
    }
}

/// A placeholder row shown while the first load is in flight.
private struct MatchRowSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TempoSpacing.sm) {
                Circle()
                    .fill(Color.tempo.surface2)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Capsule()
                        .fill(Color.tempo.surface2)
                        .frame(width: 120, height: 16)
                    Capsule()
                        .fill(Color.tempo.surface)
                        .frame(height: 12)
                        .padding(.trailing, TempoSpacing.xxl)
                }
            }
            .padding(.vertical, TempoSpacing.md)
            .frame(minHeight: 84)
            TempoDivider()
        }
        .opacity(isDimmed ? 0.45 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
    }
}

private extension View {
    /// Plain list rows on white: no separators, no system background, screen padding.
    func matchesListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: TempoSpacing.screen, bottom: 0, trailing: TempoSpacing.screen))
    }
}

#Preview("Matches") {
    MatchesView()
        .environment(AppRouter())
        .tempoEnvironment(AppEnvironment.demo())
}

#Preview("Matches, loading") {
    MatchesView()
        .environment(AppRouter())
        .tempoEnvironment(AppEnvironment.demo(signedIn: false, onboarded: false))
}
