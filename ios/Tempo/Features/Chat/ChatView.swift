import SwiftUI
import UIKit

/// The chat with one match, pushed on the Matches tab. Pops by itself when the match is gone
/// (unmatched or blocked by either person).
struct ChatView: View {
    private let matchId: String

    @Environment(MatchesStore.self) private var matchesStore
    @Environment(AppRouter.self) private var router

    init(matchId: String) {
        self.matchId = matchId
    }

    private var isGone: Bool {
        matchesStore.match(id: matchId) == nil
    }

    var body: some View {
        content
            .onChange(of: isGone, initial: true) { _, gone in
                if gone {
                    router.closeChat(matchId: matchId)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let match = matchesStore.match(id: matchId) {
            ChatScreen(match: match)
        } else {
            Color.clear
                .inkBackground()
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Screen

private struct ChatScreen: View {
    let match: Match

    @Environment(AppEnvironment.self) private var environment
    @Environment(MatchesStore.self) private var matchesStore
    @Environment(AgentStore.self) private var agents
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: String = ""
    /// The text the agent last put in the composer, so it is only replaced while untouched.
    @State private var agentDraft: String?
    /// The server refuses longer messages (`POST /v1/matches/:id/messages`, 2000 characters).
    private static let maximumMessageLength: Int = 2000
    @State private var isReportPresented: Bool = false
    @State private var deferredError: String?
    @State private var pendingAction: ChatDestructiveAction?
    @State private var tasks: TaskBag = TaskBag()

    private var partner: Partner {
        match.partner
    }

    private var thread: ChatThread {
        matchesStore.thread(for: match.id)
    }

    var body: some View {
        ChatMessageList(match: match, thread: thread)
            .safeAreaInset(edge: .top, spacing: 0) {
                voiceBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    wingman
                    ChatComposer(text: $draft, placeholder: composerPlaceholder, onSend: { send() })
                }
            }
            // The agent re-reads whenever the conversation moves, then drafts if it is its turn.
            .task(id: thread.messages.count) {
                await agents.refresh(matchId: match.id)
                draftIfDot()
            }
            .onChange(of: voice) { _, _ in
                draftIfDot()
            }
            .animation(Animation.tempo.standard(reduceMotion: reduceMotion), value: voice)
            .inkBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.tempo.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await matchesStore.openChat(matchId: match.id)
            }
            .onAppear {
                // A reply the match's agent suggested: put it in the composer, unsent.
                if let suggested = router.pendingDrafts.removeValue(forKey: match.id), draft.isEmpty {
                    draft = suggested
                }
            }
            .onChange(of: draft) { _, newValue in
                if newValue.count > ChatScreen.maximumMessageLength {
                    draft = String(newValue.prefix(ChatScreen.maximumMessageLength))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == ScenePhase.active {
                    markRead()
                }
            }
            .onDisappear {
                matchesStore.closeChat(matchId: match.id)
                tasks.cancelAll()
            }
            .sheet(isPresented: $isReportPresented, onDismiss: { showDeferredError() }) {
                ReportSheet(
                    partnerName: partner.firstName,
                    onSubmit: { reason, details in
                        report(reason: reason, details: details)
                    },
                    onBlock: {
                        block()
                    }
                )
            }
            .confirmationDialog(
                Text(dialogTitle),
                isPresented: dialogBinding,
                titleVisibility: .visible,
                actions: { dialogActions },
                message: { Text(dialogMessage) }
            )
            .fullScreenCover(isPresented: callBinding) {
                MatchCallView(match: match)
                    .interactiveDismissDisabled(true)
            }
    }

    private var composerPlaceholder: String {
        if thread.hasLoaded && thread.messages.isEmpty {
            return String(localized: "Say hello to \(partner.firstName)")
        }
        return String(localized: "Message \(partner.firstName)")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            header
        }
        ToolbarItem(placement: .topBarTrailing) {
            callButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            overflowMenu
        }
    }

    // MARK: Who is writing

    private var voice: ChatVoice {
        agents.voice(for: match.id)
    }

    /// The same character the Matches list shows for this match.
    private var persona: AgentPersona {
        let ids: [String] = matchesStore.matches.sorted { $0.matchedAt < $1.matchedAt }.map(\.id)
        return AgentPersona.cast(for: ids)[match.id] ?? AgentPersona.generate(seed: match.id)
    }

    /// Under the title: You, your dot, or the two of you together.
    private var voiceBar: some View {
        HStack(spacing: TempoSpacing.xs) {
            voiceOption(ChatVoice.me, title: String(localized: "You")) {
                Image(systemName: "person")
                    .font(Font.system(size: 13, weight: Font.Weight.medium))
            }
            voiceOption(ChatVoice.dot, title: persona.name) {
                AgentBuddy(persona: persona, size: 18)
            }
            voiceOption(ChatVoice.together, title: String(localized: "Both")) {
                HStack(spacing: -4) {
                    Image(systemName: "person")
                        .font(Font.system(size: 13, weight: Font.Weight.medium))
                    AgentBuddy(persona: persona, size: 18)
                }
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(Color.tempo.background)
        .overlay(alignment: .bottom) { TempoDivider() }
    }

    private func voiceOption<Icon: View>(_ option: ChatVoice, title: String, @ViewBuilder icon: () -> Icon) -> some View {
        let isSelected: Bool = voice == option
        return Button {
            agents.setVoice(option, for: match.id)
        } label: {
            HStack(spacing: 6) {
                icon()
                    .frame(height: 20)
                Text(title)
                    .tempoText(.secondaryEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.tempo.textPrimary)
            .padding(.horizontal, TempoSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                Capsule().fill(isSelected ? Color.tempo.pastelLilac : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.tempo.hairlineStrong : Color.tempo.hairline, lineWidth: TempoSize.hairline)
            }
        }
        .buttonStyle(TempoPressStyle(scale: 0.97))
        .accessibilityLabel(Text(voiceLabel(option)))
        .accessibilityAddTraits(isSelected ? [AccessibilityTraits.isButton, AccessibilityTraits.isSelected] : AccessibilityTraits.isButton)
    }

    private func voiceLabel(_ option: ChatVoice) -> String {
        switch option {
        case .me: return String(localized: "You write")
        case .dot: return String(localized: "\(persona.name) drafts, you send")
        case .together: return String(localized: "You write, \(persona.name) suggests")
        }
    }

    /// Above the composer: the agent's suggestions (Together) or a note about its draft (dot).
    @ViewBuilder
    private var wingman: some View {
        switch voice {
        case .me:
            EmptyView()
        case .together:
            let suggestions: [String] = agents.suggestions(for: match.id)
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: TempoSpacing.xs) {
                        AgentBuddy(persona: persona, size: 26)
                        ForEach(suggestions, id: \.self) { text in
                            Button {
                                draft = text
                                agentDraft = nil
                            } label: {
                                Text(text)
                                    .tempoText(.caption)
                                    .foregroundStyle(Color.tempo.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: 220, alignment: .leading)
                                    .padding(.horizontal, TempoSpacing.sm)
                                    .padding(.vertical, TempoSpacing.xs)
                                    .background {
                                        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                                            .fill(Color.tempo.surface)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                                            .strokeBorder(Color.tempo.hairline, lineWidth: TempoSize.hairline)
                                    }
                            }
                            .buttonStyle(TempoPressStyle(scale: 0.97))
                            .accessibilityLabel(Text("Suggested reply: \(text)"))
                        }
                    }
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, TempoSpacing.xs)
                }
                .scrollIndicators(.hidden)
                .background(Color.tempo.background)
            }
        case .dot:
            HStack(spacing: TempoSpacing.xs) {
                AgentBuddy(persona: persona, size: 22)
                Text(agentDraft != nil && agentDraft == draft
                     ? String(localized: "\(persona.name) drafted this. Edit it or press send.")
                     : String(localized: "\(persona.name) will draft your next reply."))
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempo.background)
        }
    }

    /// In dot mode, puts the agent's first suggestion in an empty (or still untouched) composer.
    /// It is never sent from here.
    private func draftIfDot() {
        guard voice == ChatVoice.dot else { return }
        let untouched: Bool = draft.isEmpty || draft == agentDraft
        guard untouched, let suggestion = agents.suggestions(for: match.id).first else { return }
        draft = suggestion
        agentDraft = suggestion
    }

    private var header: some View {
        HStack(spacing: TempoSpacing.xs) {
            AvatarView(
                url: environment.imageCache.resolve(partner.photoUrl),
                name: partner.firstName,
                size: 34,
                ring: AvatarRing.hairline
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(partner.firstName)
                    .tempoText(.serifBody)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(1)
                Text(headerDetail)
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineLimit(1)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(partner.firstName), \(headerDetail)"))
        .accessibilityAddTraits(AccessibilityTraits.isHeader)
    }

    private var headerDetail: String {
        if let location = partner.locationLine {
            return "\(partner.age) · \(location)"
        }
        return "\(partner.age)"
    }

    private var callButton: some View {
        Button {
            startCall()
        } label: {
            Image(systemName: "video")
                .font(Font.tempo.body)
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(minWidth: TempoSize.hitTarget, minHeight: TempoSize.hitTarget)
                .contentShape(Rectangle())
        }
        .disabled(isCallBusy)
        .accessibilityLabel(Text("Video call \(partner.firstName)"))
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                isReportPresented = true
            } label: {
                Label(String(localized: "Report"), systemImage: "flag")
            }
            Button(role: .destructive) {
                pendingAction = ChatDestructiveAction.block
            } label: {
                Label(String(localized: "Block"), systemImage: "hand.raised")
            }
            Button(role: .destructive) {
                pendingAction = ChatDestructiveAction.unmatch
            } label: {
                Label(String(localized: "Unmatch"), systemImage: "person.crop.circle.badge.xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Font.tempo.body)
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(minWidth: TempoSize.hitTarget, minHeight: TempoSize.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
    }

    // MARK: Messages

    private func send() {
        let text: String = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let matchId: String = match.id
        let store: MatchesStore = matchesStore
        // Not tied to this screen: a message keeps sending if the user leaves the chat.
        Task { @MainActor in
            await store.send(text: text, to: matchId)
        }
    }

    private func markRead() {
        tasks.run("read") {
            await matchesStore.markRead(matchId: match.id)
        }
    }

    // MARK: Call

    private var isCallBusy: Bool {
        matchesStore.callState != CallState.idle
    }

    /// The call screen is up for this match while ringing out, connecting, live, or just ended.
    /// An incoming ring is the shell's banner, not this cover.
    private var isCallPresented: Bool {
        guard matchesStore.callState.matchId == match.id else { return false }
        switch matchesStore.callState {
        case .idle, .incoming:
            return false
        case .outgoing, .connecting, .active, .ended:
            return true
        }
    }

    private var callBinding: Binding<Bool> {
        Binding<Bool>(
            get: { isCallPresented },
            set: { isPresented in
                if !isPresented && isCallPresented {
                    matchesStore.endCall()
                }
            }
        )
    }

    private func startCall() {
        let matchId: String = match.id
        let store: MatchesStore = matchesStore
        // Owned by the store once started; failures arrive as `lastError` or `callPermissionIssue`,
        // which the shell presents.
        Task { @MainActor in
            await store.startCall(matchId: matchId)
        }
    }

    // MARK: Report, block, unmatch

    private func report(reason: ReportReason, details: String?) {
        let matchId: String = match.id
        let store: MatchesStore = matchesStore
        Task { @MainActor in
            let sent: Bool = await store.report(matchId: matchId, reason: reason, details: details)
            if sent {
                return
            }
            // The sheet covers the shell's toast, so hold the message until the sheet closes.
            let message: String = store.lastError?.userMessage ?? String(localized: "Your report didn't send. Try again.")
            store.lastError = nil
            if isReportPresented {
                deferredError = message
            } else {
                router.showError(message)
            }
        }
    }

    private func showDeferredError() {
        guard let message = deferredError else { return }
        deferredError = nil
        router.showError(message)
    }

    private func block() {
        let matchId: String = match.id
        let name: String = partner.firstName
        let store: MatchesStore = matchesStore
        let router: AppRouter = self.router
        Task { @MainActor in
            let blocked: Bool = await store.block(matchId: matchId)
            if blocked {
                router.showMessage(String(localized: "\(name) is blocked."), systemImage: "hand.raised")
            }
        }
    }

    private func unmatch() {
        let matchId: String = match.id
        let name: String = partner.firstName
        let store: MatchesStore = matchesStore
        let router: AppRouter = self.router
        Task { @MainActor in
            let removed: Bool = await store.unmatch(matchId: matchId)
            if removed {
                router.showMessage(String(localized: "You unmatched \(name)."), systemImage: "checkmark.circle")
            }
        }
    }

    private var dialogBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAction = nil
                }
            }
        )
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .some(.block):
            return String(localized: "Block \(partner.firstName)?")
        case .some(.unmatch):
            return String(localized: "Unmatch \(partner.firstName)?")
        case .none:
            return ""
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case .some(.block):
            return String(localized: "The conversation disappears and you'll never be paired with \(partner.firstName) again.")
        case .some(.unmatch):
            return String(localized: "The conversation disappears for both of you. This can't be undone.")
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private var dialogActions: some View {
        switch pendingAction {
        case .some(.block):
            Button(String(localized: "Block"), role: .destructive) {
                block()
            }
        case .some(.unmatch):
            Button(String(localized: "Unmatch"), role: .destructive) {
                unmatch()
            }
        case .none:
            EmptyView()
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }
}

private enum ChatDestructiveAction: Hashable {
    case block
    case unmatch
}

#Preview("Chat") {
    NavigationStack {
        ChatView(matchId: "demo-match-lena")
    }
    .environment(AppRouter())
    .tempoEnvironment(AppEnvironment.demo())
}
