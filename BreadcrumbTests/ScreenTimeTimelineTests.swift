import Foundation
import Testing

@testable import Breadcrumb

struct ScreenTimeTimelineTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func todayFillsEveryHourAndComparesToYesterdayUntilNow() throws {
        let periods = try DateRange.today.resolve(
            now: date(7, 14).addingTimeInterval(1800), calendar: calendar)
        let current = ScreenTimeSummary(
            totalSeconds: 3000, buckets: [.init(id: date(7, 9), seconds: 3000)], bucketUnit: .hour)
        let previous = ScreenTimeSummary(
            totalSeconds: 600, buckets: [.init(id: date(6, 9), seconds: 600)], bucketUnit: .hour)
        let slots = ScreenTimeTimeline.slots(
            current: current, previous: previous, periods: periods, range: .today, calendar: calendar)
        #expect(slots.count == 24)
        #expect(slots[0].id == date(7))
        #expect(slots[9].seconds == 3000)
        #expect(slots[9].previousSeconds == 600)
        #expect(slots[8].previousSeconds == 0)
        // Yesterday's comparison window ends at the current clock time.
        #expect(slots[14].previousSeconds == 0)
        #expect(slots[15].previousSeconds == nil)
        #expect(!slots[14].isFuture)
        #expect(slots[15].isFuture)
    }

    @Test func weekSpansSevenDaysAndAllStartsAtFirstActivity() throws {
        let week = try DateRange.week.resolve(now: date(4, 10), calendar: calendar)
        let daily = ScreenTimeSummary(
            totalSeconds: 60, buckets: [.init(id: date(3), seconds: 60)], bucketUnit: .day)
        let slots = ScreenTimeTimeline.slots(
            current: daily, previous: nil, periods: week, range: .week, calendar: calendar)
        #expect(slots.map(\.id) == (2...8).map { date($0) })
        #expect(slots.allSatisfy { $0.previousSeconds == nil })
        #expect(slots[5].isFuture)

        let all = try DateRange.all.resolve(now: date(4, 10), calendar: calendar)
        let history = ScreenTimeTimeline.slots(
            current: daily, previous: nil, periods: all, range: .all, calendar: calendar)
        #expect(history.map(\.id) == [date(3), date(4)])
        #expect(
            ScreenTimeTimeline.slots(
                current: ScreenTimeSummary(bucketUnit: .day), previous: nil, periods: all, range: .all,
                calendar: calendar
            ).isEmpty)
    }

    @Test func crumbValueKeepsTheBusiestSlotWithinTwelveCrumbs() {
        func slot(_ seconds: TimeInterval, previous: TimeInterval? = nil) -> ScreenTimeSlot {
            ScreenTimeSlot(id: .now, end: .now, seconds: seconds, previousSeconds: previous)
        }
        #expect(ScreenTimeTimeline.crumbValue(for: [slot(3600)], unit: .hour) == 300)
        #expect(ScreenTimeTimeline.crumbValue(for: [], unit: .day) == 900)
        #expect(ScreenTimeTimeline.crumbValue(for: [slot(3 * 3600)], unit: .day) == 900)
        #expect(ScreenTimeTimeline.crumbValue(for: [slot(5 * 3600)], unit: .day) == 1800)
        #expect(
            ScreenTimeTimeline.crumbValue(for: [slot(60), slot(0, previous: 13 * 3600)], unit: .day) == 7200)
        #expect(ScreenTimeTimeline.crumbValue(for: [slot(86400)], unit: .day) == 7200)
    }
}
