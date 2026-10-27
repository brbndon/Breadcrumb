import Foundation

struct RankedItem: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    let bundleID: String?
    let visits: Int
    let total: TimeInterval
    var id: String { key }
    var average: TimeInterval { visits > 0 ? total / Double(visits) : 0 }
}

struct TransitionCount: Identifiable, Equatable, Sendable {
    let from: String
    let to: String
    let count: Int
    var id: String { "\(from)→\(to)" }
}

struct Report: Equatable, Sendable {
    var switches = 0
    var apps = 0
    var activeMinutes = 0
    var topApps: [RankedItem] = []
    var topSites: [RankedItem] = []
    var transitions: [TransitionCount] = []
}

enum ReportBuilder {
    /// Dwell per event is capped so long gaps (sleep, idle) do not inflate Active.
    static let activeCap: TimeInterval = 5 * 60
    static let listLimit = 6

    /// - Parameter events: any order; sorted ascending internally.
    static func build(events: [EventSample]) -> Report {
        let events = events.sorted { $0.timestamp < $1.timestamp }
        guard !events.isEmpty else { return Report() }

        var report = Report()
        var stats: [String: (name: String, bundleID: String?, kind: EventKind, visits: Int, total: TimeInterval)] = [:]
        var pairs: [String: (from: String, to: String, count: Int)] = [:]
        var activeSeconds: TimeInterval = 0

        for (index, event) in events.enumerated() {
            let dwell: TimeInterval = index + 1 < events.count
                ? min(events[index + 1].timestamp.timeIntervalSince(event.timestamp), activeCap)
                : 0
            activeSeconds += dwell

            var entry = stats[event.nodeKey] ?? (event.displayName, event.bundleID, event.kind, 0, 0)
            entry.visits += 1
            entry.total += dwell
            stats[event.nodeKey] = entry

            if index > 0 {
                let previous = events[index - 1]
                if previous.nodeKey != event.nodeKey {
                    report.switches += 1
                    let key = "\(previous.nodeKey)>\(event.nodeKey)"
                    var pair = pairs[key] ?? (previous.displayName, event.displayName, 0)
                    pair.count += 1
                    pairs[key] = pair
                }
            }
        }

        func ranked(_ kind: EventKind) -> [RankedItem] {
            stats.filter { $0.value.kind == kind }
                .map { RankedItem(key: $0.key, name: $0.value.name, bundleID: $0.value.bundleID, visits: $0.value.visits, total: $0.value.total) }
                .sorted { ($0.visits, $0.total, $1.name) > ($1.visits, $1.total, $0.name) }
                .prefix(listLimit)
                .map { $0 }
        }

        report.apps = stats.values.filter { $0.kind == .app }.count
        report.activeMinutes = Int((activeSeconds / 60).rounded())
        report.topApps = ranked(.app)
        report.topSites = ranked(.site)
        report.transitions = pairs.values
            .map { TransitionCount(from: $0.from, to: $0.to, count: $0.count) }
            .sorted { ($0.count, $1.from, $1.to) > ($1.count, $0.from, $0.to) }
            .prefix(listLimit)
            .map { $0 }
        return report
    }

    /// Journey rows, newest first. Dwell runs to the next newer event; the newest has none.
    static func journey(events: [EventSample]) -> [JourneyRow] {
        let ascending = events.sorted { $0.timestamp < $1.timestamp }
        return ascending.enumerated().map { index, event in
            let dwell = index + 1 < ascending.count
                ? ascending[index + 1].timestamp.timeIntervalSince(event.timestamp)
                : nil
            return JourneyRow(event: event, dwell: dwell)
        }.reversed()
    }
}

struct JourneyRow: Identifiable, Equatable, Sendable {
    let event: EventSample
    let dwell: TimeInterval?
    var id: UUID { event.id }
}

enum DurationFormat {
    static func short(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
