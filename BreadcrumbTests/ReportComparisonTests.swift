import Foundation
import Testing

@testable import Breadcrumb

struct ReportComparisonTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func currentPeriodsCompareSameLocalTime() throws {
        let now = date("2026-10-28T20:30:00Z")
        let today = try DateRange.today.resolve(now: now, calendar: calendar)
        #expect(today.current.upperBound == now)
        #expect(today.previous?.upperBound == date("2026-10-27T20:30:00Z"))
        let week = try DateRange.week.resolve(now: now, calendar: calendar)
        #expect(week.current.lowerBound == date("2026-10-26T07:00:00Z"))
        #expect(week.previous?.lowerBound == date("2026-10-19T07:00:00Z"))
        #expect(week.previous?.upperBound == date("2026-10-21T20:30:00Z"))
        #expect(try DateRange.all.resolve(now: now, calendar: calendar).previous == nil)
    }

    @Test func customIncludesLastCalendarDayAndPreviousEqualBlock() throws {
        let periods = try DateRange.custom.resolve(
            now: date("2026-11-04T20:00:00Z"), calendar: calendar,
            customStart: date("2026-10-31T19:00:00Z"), customEnd: date("2026-11-01T19:00:00Z"))
        #expect(periods.current.lowerBound == date("2026-10-31T07:00:00Z"))
        #expect(periods.current.upperBound == date("2026-11-02T08:00:00Z"))
        #expect(periods.previous?.lowerBound == date("2026-10-29T07:00:00Z"))
        #expect(periods.previous?.upperBound == date("2026-10-31T07:00:00Z"))
    }

    @Test func customEndingTodayUsesAsOfAndRejectsInvalidDates() throws {
        let now = date("2026-03-01T20:00:00Z")
        let periods = try DateRange.custom.resolve(
            now: now, calendar: calendar, customStart: date("2026-02-28T20:00:00Z"), customEnd: now)
        #expect(periods.current.upperBound == now)
        #expect(periods.previous?.upperBound == date("2026-02-27T20:00:00Z"))
        #expect(throws: (any Error).self) {
            try DateRange.custom.resolve(
                now: now, calendar: calendar, customStart: now, customEnd: date("2026-02-28T20:00:00Z"))
        }
        #expect(throws: (any Error).self) {
            try DateRange.custom.resolve(
                now: now, calendar: calendar, customStart: now, customEnd: date("2026-03-02T20:00:00Z"))
        }
    }

    @Test func comparisonUsesNextValidAndFirstRepeatedWallTime() throws {
        let spring = try DateRange.today.resolve(now: date("2026-03-09T09:30:00Z"), calendar: calendar)
        #expect(spring.previous?.upperBound == date("2026-03-08T10:00:00Z"))
        let fall = try DateRange.today.resolve(now: date("2026-11-02T09:30:00Z"), calendar: calendar)
        #expect(fall.previous?.upperBound == date("2026-11-01T08:30:00Z"))
    }

    @Test func completeDayComparisonCrossesLeapAndMonthBoundaries() throws {
        let periods = try DateRange.yesterday.resolve(now: date("2024-03-01T20:00:00Z"), calendar: calendar)
        #expect(periods.current.lowerBound == date("2024-02-29T08:00:00Z"))
        #expect(periods.previous?.lowerBound == date("2024-02-28T08:00:00Z"))
    }
}
