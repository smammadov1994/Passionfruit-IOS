import Foundation

/// What a match's agent has to say right now: one status line and a few things it prepared.
/// Each match has its own agent; it reads only that conversation.
struct AgentBrief: Sendable, Equatable, Identifiable {
    /// Where the conversation stands, which decides the agent's tone and what it offers.
    enum Standing: String, Sendable, Equatable {
        /// Matched, nobody has written yet.
        case fresh
        /// They wrote last.
        case yourMove
        /// You wrote last, recently.
        case waiting
        /// You wrote last and it has gone quiet.
        case quiet
        /// A plan to meet is on the table.
        case planning
    }

    /// The match this brief belongs to.
    let id: String
    var standing: Standing
    /// "Lena wrote 26 minutes ago. Your move."
    var status: String
    var items: [AgentItem]
    var updatedAt: Date
}

/// One thing an agent prepared.
struct AgentItem: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// A message the user could send. Tapping it opens the chat with the text filled in.
        case suggestion(text: String)
        /// Something to put in the calendar: a plan the two of them mentioned.
        case plan(title: String, start: Date, duration: TimeInterval)
        /// A nudge to come back to this conversation later.
        case reminder(title: String, at: Date)
        /// Something the agent is keeping track of. Not actionable.
        case note(text: String)
    }

    let id: String
    var kind: Kind
}

/// Who is writing in a chat. Nothing is ever sent without the user pressing send.
enum ChatVoice: String, Sendable, CaseIterable, Identifiable {
    /// Just the user. The agent stays out of it.
    case me
    /// The agent drafts each reply into the composer; the user reads it and sends (or edits).
    case dot
    /// The user writes, with the agent's suggestions one tap away: a wingman.
    case together

    var id: String { rawValue }
}
