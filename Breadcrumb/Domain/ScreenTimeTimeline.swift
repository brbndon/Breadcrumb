import Foundation

struct ScreenTimeSlot: Identifiable, Equatable, Sendable {
    let id: Date
    let end: Date
    var seconds: TimeInterval = 0
    /// Same offset in the preceding period; nil when that offset falls outside it.
    var previousSeconds: TimeInterval?
    var isFuture = false
}

enum ScreenTimeTimeline {
    static let maxCrumbs = 12

    /// Every hour of the day, or every day of the period, including empty and upcoming slots.
    static func slots(
        current: ScreenTimeSummary, previous: ScreenTimeSummary?, periods: ResolvedPeriods,
        range: DateRange, calendar: Calendar = .current, limit: Int = 4000
    ) -> [ScreenTimeSlot] {
        let unit = current.bucketUnit
        let interval = periods.current
        let anchor = range == .all ? current.buckets.first?.id : interval.lowerBound
        guard let anchor, let start = calendar.dateInterval(of: unit, for: anchor)?.start else { return [] }
        let end: Date
        if unit == .hour {
            end = calendar.dateInterval(of: .day, for: interval.lowerBound)?.end ?? interval.upperBound
        } else if range == .week {
            end = calendar.date(byAdding: .day, value: 7, to: start) ?? interval.upperBound
        } else {
            let last = max(interval.lowerBound, interval.upperBound.addingTimeInterval(-0.001))
            end = calendar.dateInterval(of: unit, for: last)?.end ?? interval.upperBound
        }
        let seconds = Dictionary(current.buckets.map { ($0.id, $0.seconds) }, uniquingKeysWith: +)
        let earlier = Dictionary((previous?.buckets ?? []).map { ($0.id, $0.seconds) }, uniquingKeysWith: +)
        let previousStart =
            previous == nil
            ? nil : periods.previous.flatMap { calendar.dateInterval(of: unit, for: $0.lowerBound)?.start }
        var slots: [ScreenTimeSlot] = []
        var cursor = start
        while cursor < end, slots.count < limit,
            let next = calendar.date(byAdding: unit, value: 1, to: cursor), next > cursor
        {
            var slot = ScreenTimeSlot(
                id: cursor, end: next, seconds: seconds[cursor] ?? 0, isFuture: cursor >= periods.asOf)
            if let previousStart, let window = periods.previous,
                let offset = calendar.date(byAdding: unit, value: slots.count, to: previousStart),
                offset < window.upperBound
            {
                slot.previousSeconds = earlier[offset] ?? 0
            }
            slots.append(slot)
            cursor = next
        }
        return slots
    }

    /// Seconds each crumb stands for: five minutes per hour slot, otherwise the smallest
    /// round step that keeps the busiest day within `maxCrumbs`.
    static func crumbValue(for slots: [ScreenTimeSlot], unit: Calendar.Component) -> TimeInterval {
        if unit == .hour { return 300 }
        let peak = slots.map { max($0.seconds, $0.previousSeconds ?? 0) }.max() ?? 0
        let steps: [TimeInterval] = [900, 1800, 3600, 7200]
        return steps.first { peak <= $0 * Double(maxCrumbs) } ?? 10800
    }
}
