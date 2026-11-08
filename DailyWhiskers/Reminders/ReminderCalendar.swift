import Foundation

struct ReminderTime: Codable, Equatable, Sendable {
    var hour = 9
    var minute = 0
    var isValid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
}

struct ReminderTarget: Codable, Equatable, Sendable {
    let day: String
    let zone: String
    let date: Date
}

/// Calendar labels, rather than 24-hour increments, define the coverage window.
/// Today is the first of fourteen labels. Passed times and missing dates are not
/// backfilled with a fifteenth date. Reopening extends the window.
enum ReminderCalendar {
    static let coverageDays = 14
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = zone
        return calendar
    }

    static func day(_ date: Date, zone: TimeZone) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func labels(start: String, count: Int) -> [String] {
        let utc = TimeZone(secondsFromGMT: 0)!
        let calendar = calendar(utc)
        let parts = start.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, count > 0,
              let anchor = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              day(anchor, zone: utc) == start else { return [] }
        return (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: anchor).map { day($0, zone: utc) }
        }
    }

    static func resolve(day: String, zone: TimeZone, time: ReminderTime) -> ReminderTarget? {
        guard time.isValid else { return nil }
        let calendar = calendar(zone)
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let anchor = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              self.day(anchor, zone: zone) == day,
              let interval = calendar.dateInterval(of: .day, for: anchor) else { return nil }
        let wanted = DateComponents(hour: time.hour, minute: time.minute, second: 0)
        if let exact = calendar.nextDate(after: interval.start.addingTimeInterval(-1), matching: wanted,
                                          matchingPolicy: .strict, repeatedTimePolicy: .first),
           interval.contains(exact), self.day(exact, zone: zone) == day {
            return ReminderTarget(day: day, zone: zone.identifier, date: exact)
        }
        // .nextTime can advance to the next date for a half-hour gap. Keep the
        // reviewed within-date resolver; this rare fallback is bounded and runs
        // off the main actor. Second precision also covers historical offsets.
        guard interval.duration <= 172800 else { return nil }
        let requested = time.hour * 3600 + time.minute * 60
        var candidate = interval.start
        while candidate < interval.end {
            let wall = calendar.dateComponents([.hour, .minute, .second], from: candidate)
            if wall.hour! * 3600 + wall.minute! * 60 + wall.second! >= requested,
               self.day(candidate, zone: zone) == day {
                return ReminderTarget(day: day, zone: zone.identifier, date: candidate)
            }
            candidate = candidate.addingTimeInterval(1)
        }
        return nil
    }

    static func queue(now: Date, zone: TimeZone, time: ReminderTime) -> [ReminderTarget] {
        labels(start: day(now, zone: zone), count: coverageDays).compactMap {
            guard let target = resolve(day: $0, zone: zone, time: time), target.date > now else { return nil }
            return target
        }
    }
}
