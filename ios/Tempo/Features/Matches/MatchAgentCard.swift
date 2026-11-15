import SwiftUI

/// One match as a row. On the left, the match's agent: a little generated character with its own
/// colour, face and temper. Tap the character to see what it prepared (replies to send, plans and
/// reminders for the calendar, notes); tap the rest of the row to open the chat.
struct MatchAgentCard: View {
    private let match: Match
    private let persona: AgentPersona

    @Environment(AppEnvironment.self) private var environment
    @Environment(SessionStore.self) private var session
    @Environment(AgentStore.self) private var agents
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded: Bool = false
    @State private var tasks: TaskBag = TaskBag()

    init(match: Match, persona: AgentPersona) {
        self.match = match
        self.persona = persona
    }

    private var name: String { match.partner.firstName }
    private var isUnread: Bool { match.unreadCount > 0 }
    private var shownItems: [AgentItem] { agents.items(for: match.id) }

    /// Things to act on (notes do not count).
    private var actionCount: Int {
        shownItems.filter { item in
            if case .note = item.kind { return false }
            return !agents.done.contains(item.id)
        }.count
    }

    /// Where things stand.
    private var statusText: String {
        agents.brief(for: match.id)?.status ?? String(localized: "Reading the conversation…")
    }

    /// The agent's aside, in its own voice.
    private var asideText: String? {
        guard let brief = agents.brief(for: match.id) else { return nil }
        return brief.standing == .waiting ? persona.temper.patience : persona.temper.nudge
    }

    private var spokenText: String {
        [statusText, asideText].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .center, spacing: TempoSpacing.md) {
                buddy
                summary
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    // The agent introduces itself here, in its own voice.
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(persona.label, color: Color.tempo.accentText)
                        if let asideText {
                            Text(asideText)
                                .tempoText(.secondary)
                                .foregroundStyle(Color.tempo.textPrimary)
                        }
                    }
                    .padding(.bottom, TempoSpacing.xxs)
                    ForEach(shownItems) { item in
                        row(for: item)
                    }
                }
                .transition(AnyTransition.tempoReplace(reduceMotion: reduceMotion))
            }
            TempoDivider()
                .padding(.top, TempoSpacing.xs)
        }
        .padding(.top, TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            tasks.cancelAll()
        }
    }

    // MARK: Character

    private var buddy: some View {
        Button {
            withAnimation(Animation.tempo.standard(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            AgentBuddy(persona: persona, size: 50, isThinking: agents.thinking.contains(match.id))
                .frame(width: 56, height: 62, alignment: .bottom)
                .overlay(alignment: .topTrailing) {
                    if actionCount > 0 && !isExpanded {
                        Text(verbatim: "\(actionCount)")
                            .tempoText(.numeralS)
                            .foregroundStyle(Color.tempo.background)
                            .frame(minWidth: 17, minHeight: 17)
                            .background { Circle().fill(Color.tempo.textPrimary) }
                            .offset(x: 4, y: 0)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.92))
        .accessibilityLabel(Text("\(persona.name), \(name)'s agent, \(persona.temper.title)"))
        .accessibilityValue(Text(actionCount == 1 ? "1 thing ready" : "\(actionCount) things ready"))
        .accessibilityHint(Text(isExpanded ? "Hides what it prepared" : "Shows what it prepared"))
    }

    // MARK: Summary

    private var summary: some View {
        Button {
            router.openChat(matchId: match.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                    Text(name)
                        .tempoText(.titleS)
                        .foregroundStyle(Color.tempo.textPrimary)
                        .lineLimit(1)
                    if isUnread {
                        Circle()
                            .fill(Color.tempo.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: TempoSpacing.xs)
                    Text(TempoFormat.listTime(match.lastActivityAt))
                        .tempoText(.caption)
                        .foregroundStyle(Color.tempo.textTertiary)
                        .lineLimit(1)
                }
                Text(statusText)
                    .tempoText(.secondary)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TempoPressStyle(scale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isUnread ? "\(name), unread. \(spokenText)" : "\(name). \(spokenText)"))
        .accessibilityHint(Text("Opens the conversation"))
    }

    @ViewBuilder
    private func row(for item: AgentItem) -> some View {
        switch item.kind {
        case .suggestion(let text):
            Button {
                router.openChat(matchId: match.id, draft: text)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                    Image(systemName: "text.bubble")
                        .font(Font.system(size: 14, weight: Font.Weight.regular))
                        .foregroundStyle(Color.tempo.textSecondary)
                        .accessibilityHidden(true)
                    Text(text)
                        .tempoText(.caption)
                        .foregroundStyle(Color.tempo.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                        .fill(Color.tempo.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                        .strokeBorder(Color.tempo.hairlineStrong, lineWidth: TempoSize.hairline)
                }
            }
            .buttonStyle(TempoPressStyle(scale: 0.98))
            .accessibilityLabel(Text("Suggested reply: \(text)"))
            .accessibilityHint(Text("Opens the chat with this text ready to send"))
        case .plan(let title, let start, _):
            calendarRow(item: item, systemImage: "calendar", title: title, when: start, action: String(localized: "Add"))
        case .reminder(let title, let at):
            calendarRow(item: item, systemImage: "bell", title: title, when: at, action: String(localized: "Remind me"))
        case .note(let text):
            Text(text)
                .tempoText(.caption)
                .foregroundStyle(Color.tempo.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func calendarRow(item: AgentItem, systemImage: String, title: String, when: Date, action: String) -> some View {
        let isDone: Bool = agents.done.contains(item.id)
        let isAdding: Bool = agents.adding.contains(item.id)
        return HStack(alignment: .center, spacing: TempoSpacing.sm) {
            Image(systemName: systemImage)
                .font(Font.system(size: 16, weight: Font.Weight.regular))
                .foregroundStyle(Color.tempo.textPrimary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .tempoText(.secondaryEmphasis)
                    .foregroundStyle(Color.tempo.textPrimary)
                    .lineLimit(2)
                Text(when.formatted(Date.FormatStyle().weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .tempoText(.caption)
                    .foregroundStyle(Color.tempo.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: TempoSpacing.xs)
            Button {
                add(item)
            } label: {
                HStack(spacing: TempoSpacing.xxs) {
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(Font.system(size: 12, weight: Font.Weight.semibold))
                    }
                    Text(isDone ? String(localized: "Added") : action)
                        .tempoText(.secondaryEmphasis)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(isDone ? Color.tempo.yes : Color.tempo.background)
                .padding(.horizontal, TempoSpacing.sm)
                .frame(minHeight: TempoSize.buttonCompact)
                .background {
                    Capsule().fill(isDone ? Color.tempo.yesSoft : Color.tempo.textPrimary)
                }
                .opacity(isAdding ? 0.5 : 1)
            }
            .buttonStyle(TempoPressStyle(scale: 0.95))
            .disabled(isDone || isAdding)
            .accessibilityLabel(Text(isDone ? "\(title), in your calendar" : "\(action): \(title)"))
        }
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                .fill(Color.tempo.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TempoRadius.card, style: .continuous)
                .strokeBorder(Color.tempo.hairlineStrong, lineWidth: TempoSize.hairline)
        }
    }

    private func add(_ item: AgentItem) {
        tasks.run("calendar-\(item.id)") {
            let error: CalendarError? = await agents.addToCalendar(item, partnerName: name)
            switch error {
            case .none:
                Haptics.success()
            case .some(.denied):
                router.showError(String(localized: "Calendar access is off. Turn it on for \(Brand.name) in Settings."))
            case .some(.failed):
                router.showError(String(localized: "That didn't reach your calendar. Try again."))
            }
        }
    }
}

#Preview("Match agent card") {
    let environment = AppEnvironment.demo()
    return ScrollView {
        if let match = environment.matches.matches.first {
            MatchAgentCard(match: match, persona: AgentPersona.generate(seed: match.id))
                .padding()
        }
    }
    .environment(AppRouter())
    .tempoEnvironment(environment)
}
