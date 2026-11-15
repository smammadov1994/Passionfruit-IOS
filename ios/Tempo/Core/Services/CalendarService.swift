import EventKit
import Foundation

enum CalendarError: Error, Equatable {
    /// The user said no to calendar access (now or earlier).
    case denied
    case failed
}

/// Adds entries to the user's calendar. Write-only: the app never reads what is in it.
protocol CalendarService: Sendable {
    /// Adds an event with an alert 30 minutes before. Asks for write-only access the first time.
    func addEvent(title: String, start: Date, duration: TimeInterval, notes: String?) async throws
}

struct LiveCalendarService: CalendarService {
    init() {}

    func addEvent(title: String, start: Date, duration: TimeInterval, notes: String?) async throws {
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestWriteOnlyAccessToEvents()
        } catch {
            throw CalendarError.failed
        }
        guard granted else { throw CalendarError.denied }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        do {
            try store.save(event, span: EKSpan.thisEvent)
        } catch {
            throw CalendarError.failed
        }
    }
}

/// Demo mode: nothing is written anywhere; it only waits a moment so the UI can show progress.
struct MockCalendarService: CalendarService {
    var result: Result<Void, CalendarError> = Result.success(())

    init(result: Result<Void, CalendarError> = Result.success(())) {
        self.result = result
    }

    func addEvent(title: String, start: Date, duration: TimeInterval, notes: String?) async throws {
        try? await Task.sleep(for: Duration.milliseconds(350))
        try result.get()
    }
}
