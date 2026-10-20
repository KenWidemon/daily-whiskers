import Foundation

struct BonusDay: Equatable, Sendable {
    let key: String
    let timeZone: String
    init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        self.timeZone = timeZone.identifier
    }
}

enum BonusCardError: Error, LocalizedError {
    case noDistinctContent
    case todayUnavailable
    var errorDescription: String? {
        switch self {
        case .noDistinctContent:
            "A different cat and quote aren't available right now. You can still enjoy Today. Please try again later."
        case .todayUnavailable:
            "Today's card couldn't be prepared, so a new bonus can't be selected yet. Please try again later."
        }
    }
}
