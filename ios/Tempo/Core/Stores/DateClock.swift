import Foundation

/// Pure clock math for the date timer, the decision ring and icebreaker turns.
/// Everything is derived from end timestamps, never from local counters.
enum DateClock {
    /// Seconds left until `end`, never negative.
    static func remaining(until end: Date, now: Date = Date()) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// 1 at the start of the window, 0 when it is over.
    static func fractionRemaining(endsAt: Date, duration: TimeInterval, now: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let fraction: Double = remaining(until: endsAt, now: now) / duration
        return min(1, max(0, fraction))
    }

    /// 0 at the start of the window, 1 when it is over.
    static func fractionElapsed(endsAt: Date, duration: TimeInterval, now: Date = Date()) -> Double {
        1 - fractionRemaining(endsAt: endsAt, duration: duration, now: now)
    }

    /// Whole seconds to show: 59.2 s left reads as 60, 0.4 s as 1, 0 as 0.
    static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        guard remaining > 0 else { return 0 }
        return Int(remaining.rounded(.up))
    }

    /// "3:12", "0:07".
    static func clockText(_ remaining: TimeInterval) -> String {
        let total: Int = wholeSeconds(remaining)
        let minutes: Int = total / 60
        let seconds: Int = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// True in the last `threshold` seconds (the clock warms to amber), false once time is up.
    static func isFinalStretch(remaining: TimeInterval, threshold: TimeInterval = 30) -> Bool {
        remaining > 0 && remaining <= threshold
    }
}

/// Corrects server timestamps for a device clock that is clearly wrong.
/// Small differences (network latency, normal drift) are ignored.
struct ServerClock: Sendable, Equatable {
    /// Server time minus device time, in seconds. 0 unless the skew exceeds `threshold`.
    private(set) var offset: TimeInterval = 0
    var threshold: TimeInterval = 5

    init() {}

    /// `serverNow` is a server timestamp known to mean "now" (e.g. `startsAt` of `date.started`).
    mutating func observe(serverNow: Date, localNow: Date = Date()) {
        let raw: TimeInterval = serverNow.timeIntervalSince(localNow)
        offset = abs(raw) > threshold ? raw : 0
    }

    /// Converts a server timestamp to the device's clock.
    func local(_ serverDate: Date) -> Date {
        serverDate.addingTimeInterval(-offset)
    }
}

/// The current icebreaker turn, as the Turn Card needs it.
struct IcebreakerState: Sendable, Equatable {
    var question: String
    var questionIndex: Int
    var speakerId: String
    /// Already converted to the device's clock.
    var turnEndsAt: Date
    var turnDuration: TimeInterval
    var isMyTurn: Bool

    func remaining(at now: Date = Date()) -> TimeInterval {
        DateClock.remaining(until: turnEndsAt, now: now)
    }

    /// 1 when the turn starts, draining to 0.
    func fractionRemaining(at now: Date = Date()) -> Double {
        DateClock.fractionRemaining(endsAt: turnEndsAt, duration: turnDuration, now: now)
    }
}
