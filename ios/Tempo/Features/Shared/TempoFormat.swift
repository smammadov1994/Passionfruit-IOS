import Foundation

/// Small, pure text formatters shared by the screens.
enum TempoFormat {
    /// Time for a row in the matches list: "9:12 PM", "Yesterday", "Sunday", "Nov 3".
    static func listTime(_ date: Date, now: Date = Date(), calendar: Calendar = Calendar.current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return dayName(date, now: now, calendar: calendar)
    }

    /// Label of a day separator in a chat: "Today", "Yesterday", "Sunday", "Nov 3".
    static func daySeparator(_ date: Date, now: Date = Date(), calendar: Calendar = Calendar.current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today")
        }
        return dayName(date, now: now, calendar: calendar)
    }

    /// "9:12 PM"
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "November 3, 2026"
    static func longDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    private static func dayName(_ date: Date, now: Date, calendar: Calendar) -> String {
        let startOfToday: Date = calendar.startOfDay(for: now)
        let startOfThat: Date = calendar.startOfDay(for: date)
        let days: Int = calendar.dateComponents([.day], from: startOfThat, to: startOfToday).day ?? 0
        if days == 1 {
            return String(localized: "Yesterday")
        }
        if days > 1 && days < 7 {
            return date.formatted(Date.FormatStyle().weekday(.wide))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(Date.FormatStyle().month(.abbreviated).day())
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "4 minutes", "45 seconds", "1 minute". Used wherever copy mentions a duration from config.
    static func durationPhrase(_ duration: TimeInterval) -> String {
        let seconds: Int = max(0, Int(duration.rounded()))
        if seconds >= 60 && seconds % 60 == 0 {
            let minutes: Int = seconds / 60
            if minutes == 1 {
                return String(localized: "1 minute")
            }
            return String(localized: "\(minutes) minutes")
        }
        if seconds == 1 {
            return String(localized: "1 second")
        }
        return String(localized: "\(seconds) seconds")
    }

    /// The duration as a compound modifier: "4-minute", "45-second". For "a 4-minute video call".
    static func durationAdjective(_ duration: TimeInterval) -> String {
        let seconds: Int = max(0, Int(duration.rounded()))
        if seconds >= 60 && seconds % 60 == 0 {
            return String(localized: "\(seconds / 60)-minute")
        }
        return String(localized: "\(seconds)-second")
    }

    /// The same duration with the number spelled out and capitalised: "Four minutes".
    static func durationHeadline(_ duration: TimeInterval) -> String {
        let seconds: Int = max(0, Int(duration.rounded()))
        let isWholeMinutes: Bool = seconds >= 60 && seconds % 60 == 0
        let amount: Int = isWholeMinutes ? seconds / 60 : seconds
        let word: String = capitalised(spelledOut(amount))
        if isWholeMinutes {
            if amount == 1 {
                return String(localized: "\(word) minute")
            }
            return String(localized: "\(word) minutes")
        }
        if amount == 1 {
            return String(localized: "\(word) second")
        }
        return String(localized: "\(word) seconds")
    }

    /// "four", or the digits when the number cannot be spelled out.
    static func spelledOut(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    /// "3 dates left today", "1 date left today", "No dates left today".
    static func datesLeft(_ remaining: Int) -> String {
        if remaining <= 0 {
            return String(localized: "No dates left today")
        }
        if remaining == 1 {
            return String(localized: "1 date left today")
        }
        return String(localized: "\(remaining) dates left today")
    }
}
