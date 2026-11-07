import Foundation
import Testing

@testable import Breadcrumb

struct ScreenTimeTimelineTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    func date(_ day: Int, _ hour: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
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

    @Test func weekAlignsPreviousDaysAndStopsAtTheCutoff() throws {
        let periods = try DateRange.week.resolve(now: date(4, 10), calendar: calendar)
        let current = ScreenTimeSummary(
            totalSeconds: 600, buckets: [.init(id: date(3), seconds: 600)], bucketUnit: .day)
        let previous = ScreenTimeSummary(
            totalSeconds: 600,
            buckets: [
                .init(id: date(26, month: 10), seconds: 100), .init(id: date(27, month: 10), seconds: 200),
                .init(id: date(28, month: 10), seconds: 300),
            ], bucketUnit: .day)
        let slots = ScreenTimeTimeline.slots(
            current: current, previous: previous, periods: periods, range: .week, calendar: calendar)
        #expect(slots[1].seconds == 600)
        #expect(slots.prefix(3).map(\.previousSeconds) == [100, 200, 300])
        // Last week's comparison ends at 10:00 on its Wednesday, so later days have no counterpart.
        #expect(slots.dropFirst(3).allSatisfy { $0.previousSeconds == nil })
        #expect(ScreenTimeTimeline.hasComparison(slots))
        #expect(!slots[2].isFuture)
        #expect(slots[3].isFuture)
    }

    @Test func yesterdayFillsTheWholeDayAgainstTheDayBefore() throws {
        let periods = try DateRange.yesterday.resolve(now: date(7, 14), calendar: calendar)
        let current = ScreenTimeSummary(
            totalSeconds: 100, buckets: [.init(id: date(6, 9), seconds: 100)], bucketUnit: .hour)
        let previous = ScreenTimeSummary(
            totalSeconds: 110,
            buckets: [.init(id: date(5, 9), seconds: 50), .init(id: date(5, 23), seconds: 60)],
            bucketUnit: .hour)
        let slots = ScreenTimeTimeline.slots(
            current: current, previous: previous, periods: periods, range: .yesterday, calendar: calendar)
        #expect(slots.count == 24)
        #expect(slots[0].id == date(6))
        #expect(slots[9].seconds == 100)
        #expect(slots[9].previousSeconds == 50)
        #expect(slots[23].previousSeconds == 60)
        #expect(slots.allSatisfy { !$0.isFuture })
    }

    @Test func customRangeEndingTodayComparesPartialFinalDay() throws {
        let periods = try DateRange.custom.resolve(
            now: date(7, 14), calendar: calendar, customStart: date(5), customEnd: date(7))
        let current = ScreenTimeSummary(bucketUnit: .day)
        let previous = ScreenTimeSummary(
            buckets: [
                .init(id: date(2), seconds: 10), .init(id: date(3), seconds: 20),
                .init(id: date(4), seconds: 30),
            ], bucketUnit: .day)
        let slots = ScreenTimeTimeline.slots(
            current: current, previous: previous, periods: periods, range: .custom, calendar: calendar)
        #expect(slots.map(\.id) == [date(5), date(6), date(7)])
        #expect(slots.map(\.previousSeconds) == [10, 20, 30])
        #expect(slots.allSatisfy { !$0.isFuture })
    }

    @Test func mondayWeekIsHourlyAndComparesToLastMondayUntilNow() throws {
        let periods = try DateRange.week.resolve(now: date(9, 10), calendar: calendar)
        let previous = ScreenTimeSummary(
            totalSeconds: 40, buckets: [.init(id: date(2, 3), seconds: 40)], bucketUnit: .hour)
        let slots = ScreenTimeTimeline.slots(
            current: ScreenTimeSummary(bucketUnit: .hour), previous: previous, periods: periods,
            range: .week, calendar: calendar)
        #expect(slots.count == 24)
        #expect(slots[0].id == date(9))
        #expect(slots[3].previousSeconds == 40)
        #expect(slots[9].previousSeconds == 0)
        #expect(slots[10].previousSeconds == nil)
        #expect(slots[10].isFuture)
    }

    @Test func daylightSavingDaysHaveTwentyThreeAndTwentyFiveHourSlots() throws {
        let pacific = calendar(in: "America/Los_Angeles")
        func slots(_ month: Int, _ day: Int, buckets: [ScreenTimeBucket] = []) throws -> [ScreenTimeSlot] {
            let now = pacific.date(from: DateComponents(year: 2026, month: month, day: day, hour: 20))!
            let periods = try DateRange.today.resolve(now: now, calendar: pacific)
            return ScreenTimeTimeline.slots(
                current: ScreenTimeSummary(buckets: buckets, bucketUnit: .hour), previous: nil,
                periods: periods, range: .today, calendar: pacific)
        }
        #expect(try slots(3, 8).count == 23)
        let midnight = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let fallBack = try slots(
            11, 1, buckets: [.init(id: midnight.addingTimeInterval(2 * 3600), seconds: 77)])
        #expect(fallBack.count == 25)
        #expect(Set(fallBack.map(\.id)).count == 25)
        #expect(fallBack[1].seconds == 0)
        #expect(fallBack[2].seconds == 77)
    }

    @Test func overlongRangesKeepTheNewestSlotsAndTheirComparison() throws {
        let all = try DateRange.all.resolve(now: date(4, 10), calendar: calendar)
        let daily = ScreenTimeSummary(
            totalSeconds: 120, buckets: [.init(id: date(1), seconds: 60), .init(id: date(3), seconds: 60)],
            bucketUnit: .day)
        let recent = ScreenTimeTimeline.slots(
            current: daily, previous: nil, periods: all, range: .all, calendar: calendar, limit: 2)
        #expect(recent.map(\.id) == [date(3), date(4)])
        #expect(recent[0].seconds == 60)
        #expect(!ScreenTimeTimeline.hasComparison(recent))

        let custom = try DateRange.custom.resolve(
            now: date(4, 10), calendar: calendar, customStart: date(1), customEnd: date(4))
        let earlier = ScreenTimeSummary(
            buckets: [
                .init(id: date(30, month: 10), seconds: 5), .init(id: date(31, month: 10), seconds: 7),
            ],
            bucketUnit: .day)
        let trimmed = ScreenTimeTimeline.slots(
            current: daily, previous: earlier, periods: custom, range: .custom, calendar: calendar, limit: 2)
        #expect(trimmed.map(\.id) == [date(3), date(4)])
        #expect(trimmed.map(\.previousSeconds) == [5, 7])
    }

    @Test func yearsAreShownOnlyWhenSlotsCrossAYearBoundary() {
        func slot(_ year: Int, _ month: Int, _ day: Int) -> ScreenTimeSlot {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            return ScreenTimeSlot(id: date, end: date)
        }
        #expect(!ScreenTimeTimeline.spansYears([], calendar: calendar))
        #expect(!ScreenTimeTimeline.spansYears([slot(2026, 1, 1), slot(2026, 12, 31)], calendar: calendar))
        #expect(ScreenTimeTimeline.spansYears([slot(2026, 12, 31), slot(2027, 1, 1)], calendar: calendar))
    }
}
