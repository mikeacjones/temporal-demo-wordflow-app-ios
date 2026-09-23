import Foundation

/// RFC 3339 parsing for Go's `time.Time` JSON encoding.
///
/// Go writes `2006-01-02T15:04:05.999999999Z07:00`, so the fractional part is
/// omitted when zero and can carry up to nine digits. `ISO8601DateFormatter`
/// needs a different option set for each of those shapes and is not `Sendable`,
/// so the fixed grammar is parsed directly instead.
enum GoTimestamp {
    static func parse(_ value: String) -> Date? {
        let scalars = Array(value.utf8)
        // Shortest legal form: 1970-01-01T00:00:00Z
        guard scalars.count >= 20 else { return nil }

        func digits(_ start: Int, _ count: Int) -> Int? {
            var result = 0
            for index in start..<(start + count) {
                guard index < scalars.count else { return nil }
                let digit = Int(scalars[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                result = result * 10 + digit
            }
            return result
        }
        func character(_ index: Int) -> UInt8? {
            index < scalars.count ? scalars[index] : nil
        }

        guard let year = digits(0, 4), character(4) == UInt8(ascii: "-"),
              let month = digits(5, 2), character(7) == UInt8(ascii: "-"),
              let day = digits(8, 2),
              character(10) == UInt8(ascii: "T") || character(10) == UInt8(ascii: "t")
                || character(10) == UInt8(ascii: " "),
              let hour = digits(11, 2), character(13) == UInt8(ascii: ":"),
              let minute = digits(14, 2), character(16) == UInt8(ascii: ":"),
              let second = digits(17, 2)
        else { return nil }

        var index = 19
        var fraction = 0.0
        if character(index) == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            var sawDigit = false
            while let byte = character(index), (48...57).contains(byte) {
                fraction += Double(Int(byte) - 48) * scale
                scale /= 10
                index += 1
                sawDigit = true
            }
            guard sawDigit else { return nil }
        }

        var offsetSeconds = 0
        switch character(index) {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            index += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            let negative = character(index) == UInt8(ascii: "-")
            guard let offsetHour = digits(index + 1, 2) else { return nil }
            // Both `+01:00` and `+0100` appear in the wild.
            let minuteStart = character(index + 3) == UInt8(ascii: ":") ? index + 4 : index + 3
            guard let offsetMinute = digits(minuteStart, 2) else { return nil }
            offsetSeconds = offsetHour * 3600 + offsetMinute * 60
            if negative { offsetSeconds = -offsetSeconds }
            index = minuteStart + 2
        default:
            return nil
        }
        guard index == scalars.count else { return nil }
        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds)
        return Date(timeIntervalSince1970: seconds + fraction)
    }

    /// Howard Hinnant's `days_from_civil`: proleptic Gregorian days since the
    /// Unix epoch, with no calendar or time-zone database involved.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
