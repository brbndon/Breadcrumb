import Foundation

enum DateRange: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case week = "Week"
    case all = "All"

    var id: String { rawValue }

    /// Half-open interval `[start, end)` in the given calendar. Weeks start on Monday.
    func interval(now: Date = .now, calendar: Calendar = .current) -> Range<Date> {
        let startOfToday = calendar.startOfDay(for: now)
        let future = now.addingTimeInterval(60)
        switch self {
        case .today:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? future
            return startOfToday..<min(future, tomorrow)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return start..<startOfToday
        case .week:
            var cal = calendar
            cal.firstWeekday = 2
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
            return start..<future
        case .all:
            return Date(timeIntervalSince1970: 0)..<future
        }
    }
}
