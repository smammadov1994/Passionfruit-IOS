import SwiftUI
import UIKit

/// The scrolling part of a chat: day separators, bubbles, failed-to-send rows, pagination at the
/// top, and scroll-to-bottom behaviour that follows new messages and the keyboard.
struct ChatMessageList: View {
    private let match: Match
    private let thread: ChatThread

    @Environment(MatchesStore.self) private var matchesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAtBottom: Bool = true
    @State private var hasUnseenMessage: Bool = false
    @State private var isLoadingEarlier: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    private static let bottomId: String = "chat-bottom"

    init(match: Match, thread: ChatThread) {
        self.match = match
        self.thread = thread
    }

    private var rows: [ChatRow] {
        ChatRow.rows(from: thread.messages)
    }

    private var lastMessageId: String? {
        thread.messages.last?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollView(proxy: proxy)
                .overlay(alignment: .bottom) {
                    newMessageChip(proxy: proxy)
                }
                .onChange(of: lastMessageId) { _, _ in
                    handleNewMessage(proxy: proxy)
                }
                .onChange(of: thread.hasLoaded) { _, loaded in
                    if loaded {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    handleKeyboard(proxy: proxy)
                }
        }
        .onDisappear {
            tasks.cancelAll()
        }
    }

    private func scrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                topSection(proxy: proxy)
                ForEach(rows) { row in
                    rowView(row)
                }
                bottomSentinel
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.top, TempoSpacing.sm)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }

    private var bottomSentinel: some View {
        Color.clear
            .frame(height: TempoSpacing.xs)
            .id(ChatMessageList.bottomId)
            .onAppear {
                isAtBottom = true
                hasUnseenMessage = false
            }
            .onDisappear {
                isAtBottom = false
            }
            .accessibilityHidden(true)
    }

    // MARK: Top of the list

    @ViewBuilder
    private func topSection(proxy: ScrollViewProxy) -> some View {
        if let error = thread.loadError {
            ErrorBanner(message: error.userMessage, onRetry: { reload() })
                .padding(.vertical, TempoSpacing.sm)
        } else if !thread.hasLoaded {
            LoadingDots()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel(Text("Loading messages"))
        } else if thread.hasMoreHistory {
            LoadingDots(color: Color.tempo.textSecondary, dotSize: 5)
                .frame(maxWidth: .infinity, minHeight: TempoSize.hitTarget)
                .accessibilityLabel(Text("Loading earlier messages"))
                .onAppear {
                    loadEarlier(proxy: proxy)
                }
        } else {
            matchedLine
        }
    }

    private var matchedLine: some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text("You both said yes.")
                .tempoText(.serifBody)
                .foregroundStyle(Color.tempo.textPrimary)
            Text(TempoFormat.longDate(match.matchedAt))
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        switch row {
        case .day(let date):
            Text(TempoFormat.daySeparator(date))
                .tempoText(.eyebrow)
                .foregroundStyle(Color.tempo.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, TempoSpacing.md)
                .padding(.bottom, TempoSpacing.xxs)
                .accessibilityAddTraits(AccessibilityTraits.isHeader)
        case .message(let message, let endsGroup):
            messageView(message, endsGroup: endsGroup)
        }
    }

    private func messageView(_ message: ChatMessage, endsGroup: Bool) -> some View {
        let isFailed: Bool = message.delivery == ChatMessage.Delivery.failed
        let showsTime: Bool = endsGroup && message.delivery == ChatMessage.Delivery.sent
        return VStack(alignment: .trailing, spacing: TempoSpacing.xxs) {
            MessageBubble(
                text: message.text,
                isMine: message.isMine,
                timestamp: showsTime ? TempoFormat.clockTime(message.sentAt) : nil,
                isPending: message.delivery == ChatMessage.Delivery.sending,
                showsTail: endsGroup
            )
            if isFailed {
                failedFooter(message)
            }
        }
        .padding(.bottom, endsGroup ? TempoSpacing.xs : 0)
    }

    private func failedFooter(_ message: ChatMessage) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .font(Font.tempo.caption)
                .foregroundStyle(Color.tempo.danger)
                .accessibilityHidden(true)
            Text("Not sent")
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.danger)
            Button(String(localized: "Try again")) {
                retry(message)
            }
            .buttonStyle(TempoButtonStyle(TempoButtonVariant.secondary, size: TempoButtonSize.compact, fullWidth: false))
            Button(String(localized: "Delete")) {
                matchesStore.discardFailed(messageId: message.id, in: match.id)
            }
            .buttonStyle(TempoButtonStyle(TempoButtonVariant.ghost, size: TempoButtonSize.compact, fullWidth: false))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }

    // MARK: New message chip

    @ViewBuilder
    private func newMessageChip(proxy: ScrollViewProxy) -> some View {
        if hasUnseenMessage && !isAtBottom {
            Button {
                scrollToBottom(proxy: proxy, animated: true)
            } label: {
                FloatingCapsule {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "arrow.down")
                            .font(Font.tempo.caption)
                            .accessibilityHidden(true)
                        Text("New message")
                            .tempoText(.secondaryEmphasis)
                    }
                    .foregroundStyle(Color.tempo.textPrimary)
                }
            }
            .buttonStyle(TempoPressStyle(scale: 0.96))
            .padding(.bottom, TempoSpacing.xs)
            .transition(AnyTransition.tempoPop(reduceMotion: reduceMotion))
            .accessibilityHint(Text("Scrolls to the newest message"))
        }
    }

    // MARK: Behaviour

    private func handleNewMessage(proxy: ScrollViewProxy) {
        guard let last = thread.messages.last else { return }
        if last.isMine || isAtBottom {
            scrollToBottom(proxy: proxy, animated: true)
        } else {
            withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
                hasUnseenMessage = true
            }
        }
    }

    /// Keeps the newest message above the keyboard when the user was already reading the end.
    private func handleKeyboard(proxy: ScrollViewProxy) {
        guard isAtBottom else { return }
        tasks.run("keyboard") {
            do {
                try await Task.sleep(for: Duration.milliseconds(60))
            } catch {
                return
            }
            scrollToBottom(proxy: proxy, animated: true)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        hasUnseenMessage = false
        if animated && !reduceMotion {
            withAnimation(Animation.tempo.snappy) {
                proxy.scrollTo(ChatMessageList.bottomId, anchor: UnitPoint.bottom)
            }
        } else {
            proxy.scrollTo(ChatMessageList.bottomId, anchor: UnitPoint.bottom)
        }
    }

    private func reload() {
        tasks.run("reload") {
            await matchesStore.loadMessages(matchId: match.id)
        }
    }

    /// Loads the previous page and keeps the message the user was looking at in place.
    private func loadEarlier(proxy: ScrollViewProxy) {
        guard !isLoadingEarlier else { return }
        let anchorId: String? = thread.messages.first?.id
        tasks.run("earlier") {
            isLoadingEarlier = true
            await matchesStore.loadEarlier(matchId: match.id)
            isLoadingEarlier = false
            if Task.isCancelled {
                return
            }
            if let anchorId {
                proxy.scrollTo(anchorId, anchor: UnitPoint.top)
            }
        }
    }

    private func retry(_ message: ChatMessage) {
        let messageId: String = message.id
        let matchId: String = match.id
        let store: MatchesStore = matchesStore
        // Like a first send, a retry is not cancelled when the chat closes.
        Task { @MainActor in
            await store.retry(messageId: messageId, in: matchId)
        }
    }
}

// MARK: - Rows model

/// What the list shows: a day separator or one message.
enum ChatRow: Identifiable {
    case day(Date)
    /// `endsGroup` is true for the last message of a run from one sender (it gets the tail and the time).
    case message(ChatMessage, endsGroup: Bool)

    var id: String {
        switch self {
        case .day(let date):
            return "day-" + String(Int(date.timeIntervalSince1970))
        case .message(let message, _):
            return message.id
        }
    }

    /// Messages closer together than this, from the same sender, form one group.
    static let groupingGap: TimeInterval = 5 * 60

    static func rows(from messages: [ChatMessage], calendar: Calendar = Calendar.current) -> [ChatRow] {
        var result: [ChatRow] = []
        result.reserveCapacity(messages.count + 4)
        var previousDay: Date?
        for index in messages.indices {
            let message: ChatMessage = messages[index]
            let day: Date = calendar.startOfDay(for: message.sentAt)
            if previousDay != day {
                result.append(ChatRow.day(day))
                previousDay = day
            }
            var endsGroup: Bool = true
            let nextIndex: Int = index + 1
            if nextIndex < messages.count {
                let next: ChatMessage = messages[nextIndex]
                let sameSender: Bool = next.isMine == message.isMine
                let sameDay: Bool = calendar.startOfDay(for: next.sentAt) == day
                let close: Bool = next.sentAt.timeIntervalSince(message.sentAt) < ChatRow.groupingGap
                let bothSettled: Bool = message.delivery != ChatMessage.Delivery.failed
                endsGroup = !(sameSender && sameDay && close && bothSettled)
            }
            result.append(ChatRow.message(message, endsGroup: endsGroup))
        }
        return result
    }
}

#Preview("Message list") {
    let environment = AppEnvironment.demo()
    let match: Match = environment.matches.matches.first ?? Match(id: "preview", partner: DemoWorld.roster[0], matchedAt: Date())
    return ChatMessageList(match: match, thread: environment.matches.thread(for: match.id))
        .inkBackground()
        .tempoEnvironment(environment)
}
