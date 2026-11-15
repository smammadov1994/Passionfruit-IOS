import Foundation

/// JSON coding configured for the wire protocol: camelCase keys, ISO-8601 UTC timestamps with milliseconds.
enum TempoJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder: Decoder) -> Date in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = TempoJSON.parseDate(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { (date: Date, encoder: Encoder) in
            var container = encoder.singleValueContainer()
            try container.encode(TempoJSON.string(from: date))
        }
        return encoder
    }

    /// Parses ISO-8601 with or without fractional seconds.
    static func parseDate(_ raw: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(raw) {
            return date
        }
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? plain.parse(raw) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    /// Formats as `2026-01-31T21:04:05.123Z`.
    static func string(from date: Date) -> String {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return style.format(date)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }
}

/// Birthdates travel as `YYYY-MM-DD` calendar dates (no time zone).
enum Birthdate {
    static func string(from date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2000
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from string: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let pieces = string.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            return nil
        }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)
    }

    /// Whole years between `birthdate` and `now`.
    static func age(from birthdate: Date, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let birth = calendar.dateComponents([.year, .month, .day], from: birthdate)
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        var years = (today.year ?? 0) - (birth.year ?? 0)
        let birthMonth = birth.month ?? 1
        let birthDay = birth.day ?? 1
        let month = today.month ?? 1
        let day = today.day ?? 1
        if month < birthMonth || (month == birthMonth && day < birthDay) {
            years -= 1
        }
        return max(0, years)
    }

    static let minimumAge: Int = 18
}
