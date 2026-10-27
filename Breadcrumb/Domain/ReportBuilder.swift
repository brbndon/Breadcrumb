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

struct TransitionKey: Hashable, Sendable {
    let from: String
    let to: String
}

struct TransitionCount: Identifiable, Equatable, Sendable {
    let id: TransitionKey
    let from: String
    let to: String
    var count: Int
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
    static let activeCap: TimeInterval = 5 * 60
    static let listLimit = 6

    static func build(events: [EventSample]) -> Report {
        var accumulator = Accumulator()
        for event in events.sorted(by: chronological) { accumulator.append(event) }
        return accumulator.report()
    }

    static func chronological(_ lhs: EventSample, _ rhs: EventSample) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func dwell(_ event: EventSample, next: EventSample?) -> TimeInterval? {
        guard let end = event.endedAt ?? next?.timestamp else { return nil }
        return max(0, min(end, next?.timestamp ?? end).timeIntervalSince(event.timestamp))
    }

    /// Closed visits terminate a tracking segment; transitions never cross that boundary.
    struct Accumulator {
        private var previous: EventSample?
        private var stats: [String: RankedItem] = [:]
        private var kinds: [String: EventKind] = [:]
        private var pairs: [TransitionKey: TransitionCount] = [:]
        private var activeSeconds: TimeInterval = 0
        private var switches = 0

        mutating func append(_ event: EventSample) {
            if let previous {
                addDwell(previous, next: event)
                if previous.endedAt == nil && previous.nodeKey != event.nodeKey {
                    switches += 1
                    let key = TransitionKey(from: previous.nodeKey, to: event.nodeKey)
                    var pair =
                        pairs[key]
                        ?? TransitionCount(
                            id: key, from: previous.displayName, to: event.displayName, count: 0)
                    pair.count += 1
                    pairs[key] = pair
                }
            }
            let old = stats[event.nodeKey]
            stats[event.nodeKey] = RankedItem(
                key: event.nodeKey, name: event.displayName, bundleID: event.bundleID,
                visits: (old?.visits ?? 0) + 1, total: old?.total ?? 0)
            kinds[event.nodeKey] = event.kind
            previous = event
        }

        private mutating func addDwell(_ event: EventSample, next: EventSample?) {
            guard let old = stats[event.nodeKey] else { return }
            let seconds = min(ReportBuilder.dwell(event, next: next) ?? 0, activeCap)
            activeSeconds += seconds
            stats[event.nodeKey] = RankedItem(
                key: old.key, name: old.name, bundleID: old.bundleID,
                visits: old.visits, total: old.total + seconds)
        }

        func report() -> Report {
            var result = self
            if let previous { result.addDwell(previous, next: nil) }
            func ranked(_ kind: EventKind) -> [RankedItem] {
                Array(
                    result.stats.values.filter { result.kinds[$0.key] == kind }.sorted {
                        if $0.visits != $1.visits { return $0.visits > $1.visits }
                        if $0.total != $1.total { return $0.total > $1.total }
                        if $0.name != $1.name { return $0.name < $1.name }
                        return $0.key < $1.key
                    }.prefix(listLimit))
            }
            return Report(
                switches: switches,
                apps: result.kinds.values.filter { $0 == .app }.count,
                activeMinutes: Int((result.activeSeconds / 60).rounded()),
                topApps: ranked(.app), topSites: ranked(.site),
                transitions: Array(
                    pairs.values.sorted {
                        if $0.count != $1.count { return $0.count > $1.count }
                        if $0.from != $1.from { return $0.from < $1.from }
                        if $0.to != $1.to { return $0.to < $1.to }
                        if $0.id.from != $1.id.from { return $0.id.from < $1.id.from }
                        return $0.id.to < $1.id.to
                    }.prefix(listLimit)))
        }
    }

    static func journey(events: [EventSample]) -> [JourneyRow] {
        let ascending = events.sorted(by: chronological)
        return ascending.enumerated().map { index, event in
            let next = index + 1 < ascending.count ? ascending[index + 1] : nil
            return JourneyRow(event: event, dwell: dwell(event, next: next))
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
        guard interval.isFinite, interval < Double(Int.max) else { return "—" }
        let seconds = Int(max(0, interval).rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
