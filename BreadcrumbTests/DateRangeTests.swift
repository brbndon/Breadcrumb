import Foundation
import Testing

@testable import Breadcrumb

struct DateRangeTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    @Test func todayDoesNotIncludeTomorrow() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-10-28T06:59:50Z")!
        let tomorrow = formatter.date(from: "2026-10-28T07:00:10Z")!
        #expect(!DateRange.today.interval(now: now, calendar: calendar).contains(tomorrow))
    }

    @Test(arguments: [("2026-03-09T12:00:00Z", 23.0), ("2026-11-02T12:00:00Z", 25.0)])
    func yesterdayUsesLocalCalendarDays(stamp: String, hours: Double) {
        let now = ISO8601DateFormatter().date(from: stamp)!
        let range = DateRange.yesterday.interval(now: now, calendar: calendar)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == hours * 3600)
        #expect(!range.contains(range.upperBound))
    }

    @Test func weekStartsOnMondayEvenOnSunday() {
        let now = ISO8601DateFormatter().date(from: "2026-11-01T20:00:00Z")!
        let range = DateRange.week.interval(now: now, calendar: calendar)
        #expect(calendar.component(.weekday, from: range.lowerBound) == 2)
        #expect(calendar.component(.hour, from: range.lowerBound) == 0)
    }
}
