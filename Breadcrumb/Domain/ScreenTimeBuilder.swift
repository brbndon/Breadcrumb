import Foundation

struct ScreenTimeRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let bundleID: String?
    var seconds: TimeInterval = 0
    var sites: [ScreenTimeRow] = []
}

struct ScreenTimeBucket: Identifiable, Equatable, Sendable {
    let id: Date
    var seconds: TimeInterval
}

struct ScreenTimeSummary: Equatable, Sendable {
    var totalSeconds: TimeInterval = 0
    var apps: [ScreenTimeRow] = []
    var sites: [ScreenTimeRow] = []
    var buckets: [ScreenTimeBucket] = []
    var bucketUnit: Calendar.Component = .hour
}

enum ScreenTimeBuilder {
    static func normalizedHost(_ host: String) -> String {
        var host = host.lowercased()
        // Keep at least two labels so hosts such as m.me are not reduced to a bare TLD.
        while host.hasPrefix("www.") || host.hasPrefix("m.") {
            let stripped = String(host.dropFirst(host.hasPrefix("www.") ? 4 : 2))
            guard stripped.contains(".") else { break }
            host = stripped
        }
        return host
    }

    struct Accumulator: Sendable {
        let interval: Range<Date>
        let asOf: Date
        var calendar: Calendar = .current
        private var pending: EventSample?
        private var apps: [String: ScreenTimeRow] = [:]
        private var sites: [String: ScreenTimeRow] = [:]
        private var children: [String: [String: ScreenTimeRow]] = [:]
        private var buckets: [Date: TimeInterval] = [:]
        private var total: TimeInterval = 0

        init(interval: Range<Date>, asOf: Date, calendar: Calendar = .current) {
            self.interval = interval
            self.asOf = asOf
            self.calendar = calendar
        }

        mutating func append(_ event: EventSample) {
            if let pending { add(pending, next: event) }
            pending = event
        }

        func summary() -> ScreenTimeSummary {
            var copy = self
            if let pending { copy.add(pending, next: nil) }
            let apps = copy.apps.values.map { row in
                var row = row
                row.sites = Self.ranked(Array(copy.children[row.id, default: [:]].values))
                return row
            }
            return ScreenTimeSummary(
                totalSeconds: copy.total, apps: Self.ranked(apps),
                sites: Self.ranked(Array(copy.sites.values)),
                buckets: copy.buckets.map { ScreenTimeBucket(id: $0.key, seconds: $0.value) }.sorted {
                    $0.id < $1.id
                }, bucketUnit: copy.bucketComponent)
        }

        private var bucketComponent: Calendar.Component {
            interval.upperBound
                <= (calendar.date(byAdding: .day, value: 1, to: interval.lowerBound) ?? interval.lowerBound)
                ? .hour : .day
        }

        private static func ranked(_ rows: [ScreenTimeRow]) -> [ScreenTimeRow] {
            rows.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
        }

        private mutating func add(_ event: EventSample, next: EventSample?) {
            let start = max(event.timestamp, interval.lowerBound)
            let end = min(
                event.endedAt ?? next?.timestamp ?? asOf, next?.timestamp ?? asOf, interval.upperBound, asOf)
            guard end > start else { return }
            let seconds = end.timeIntervalSince(start)
            total += seconds
            let appKey = "app:\(event.bundleID ?? event.displayName)"
            let appName =
                event.kind == .app
                ? event.displayName
                : event.bundleID.flatMap { BrowserHostReader.supported[$0] } ?? event.bundleID ?? "Browser"
            var app = apps[appKey] ?? ScreenTimeRow(id: appKey, name: appName, bundleID: event.bundleID)
            app.seconds += seconds
            apps[appKey] = app
            if event.kind == .site {
                let host = ScreenTimeBuilder.normalizedHost(event.host ?? event.displayName)
                let key = "site:\(host)"
                var site = sites[key] ?? ScreenTimeRow(id: key, name: host, bundleID: nil)
                site.seconds += seconds
                sites[key] = site
                var child =
                    children[appKey, default: [:]][key] ?? ScreenTimeRow(id: key, name: host, bundleID: nil)
                child.seconds += seconds
                children[appKey, default: [:]][key] = child
            }
            let component = bucketComponent
            var cursor = start
            while cursor < end, let bucket = calendar.dateInterval(of: component, for: cursor) {
                let boundary = min(end, bucket.end)
                guard boundary > cursor else { break }
                buckets[bucket.start, default: 0] += boundary.timeIntervalSince(cursor)
                cursor = boundary
            }
        }
    }
}
