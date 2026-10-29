import Foundation

enum DateRange: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case week = "Week"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }

    func interval(now: Date = .now, calendar: Calendar = .current) -> Range<Date> {
        // Custom selections require explicit dates through resolve().
        (try? resolve(now: now, calendar: calendar).current) ?? calendar.startOfDay(for: now)..<now
    }

    func resolve(
        now: Date = .now, calendar: Calendar = .current,
        customStart: Date? = nil, customEnd: Date? = nil
    ) throws -> ResolvedPeriods {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, from date: Date) -> Date {
            calendar.date(byAdding: .day, value: offset, to: date)!
        }
        func clockTime(on date: Date) -> Date {
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
            let time = calendar.date(
                bySettingHour: parts.hour!, minute: parts.minute!, second: parts.second!, of: date,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
            return time.addingTimeInterval(Double(parts.nanosecond ?? 0) / 1_000_000_000)
        }
        let current: Range<Date>
        let previous: Range<Date>?
        switch self {
        case .today:
            current = today..<now
            let yesterday = day(-1, from: today)
            previous = yesterday..<clockTime(on: yesterday)
        case .yesterday:
            let yesterday = day(-1, from: today)
            current = yesterday..<today
            previous = day(-1, from: yesterday)..<yesterday
        case .week:
            let weekday = calendar.component(.weekday, from: today)
            let monday = day(-((weekday + 5) % 7), from: today)
            current = monday..<now
            previous = day(-7, from: monday)..<clockTime(on: day(-7, from: today))
        case .all:
            current = Date(timeIntervalSince1970: 0)..<now
            previous = nil
        case .custom:
            guard let customStart, let customEnd else { throw PeriodError.missingDates }
            let start = calendar.startOfDay(for: customStart)
            let last = calendar.startOfDay(for: customEnd)
            guard start <= last else { throw PeriodError.reversed }
            guard last <= today else { throw PeriodError.future }
            let count = calendar.dateComponents([.day], from: start, to: last).day! + 1
            current = start..<(last == today ? now : day(1, from: last))
            let previousStart = day(-count, from: start)
            let previousEnd = last == today ? clockTime(on: day(-count, from: last)) : start
            previous = previousStart..<previousEnd
        }
        return ResolvedPeriods(current: current, previous: previous, asOf: now)
    }
}

enum PeriodError: Error, LocalizedError {
    case missingDates, reversed, future
    var errorDescription: String? {
        switch self {
        case .missingDates: "Choose both dates."
        case .reversed: "The end date must be on or after the start date."
        case .future: "Choose dates on or before today."
        }
    }
}
