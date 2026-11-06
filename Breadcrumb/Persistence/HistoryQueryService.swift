import Foundation
import SwiftData

@MainActor
final class HistoryQueryService {
    let store: UsageStore
    init(store: UsageStore) { self.store = store }

    func journeyPage(for query: HistoryQuery, before cursor: JourneyCursor?, limit: Int) throws -> JourneyPage
    {
        guard limit > 0, !query.interval.isEmpty else { return JourneyPage(rows: [], nextCursor: nil) }
        var reader = try JourneyReader(service: self, query: query, cursor: cursor, limit: limit)
        while true { if let page = try reader.step() { return page } }
    }

    func journeyPageAsync(for query: HistoryQuery, before cursor: JourneyCursor?, limit: Int) async throws
        -> JourneyPage
    {
        guard limit > 0, !query.interval.isEmpty else { return JourneyPage(rows: [], nextCursor: nil) }
        let revision = store.revision
        var reader = try JourneyReader(service: self, query: query, cursor: cursor, limit: limit)
        while true {
            try Task.checkCancellation()
            guard revision == store.revision else { throw CancellationError() }
            if let page = try reader.step() { return page }
            await Task.yield()
        }
    }

    func report(in interval: Range<Date>) async throws -> Report {
        let revision = store.revision
        var accumulator = ReportBuilder.Accumulator(interval: interval)
        if let predecessor = try store.neighbor(of: interval.lowerBound, before: true) {
            accumulator.append(predecessor)
        }
        var after: Date?
        while true {
            try Task.checkCancellation()
            guard revision == store.revision else { throw CancellationError() }
            let batch = try batch(in: interval, boundary: after, ascending: true)
            guard !batch.isEmpty else { break }
            for event in batch { accumulator.append(event) }
            after = batch.last?.timestamp
            await Task.yield()
        }
        if let successor = try store.neighbor(of: interval.upperBound, before: false) {
            accumulator.append(successor)
        }
        return accumulator.report()
    }

    func screenTime(in interval: Range<Date>, asOf: Date, calendar: Calendar = .current) async throws
        -> ScreenTimeSummary
    {
        let revision = store.revision
        var accumulator = ScreenTimeBuilder.Accumulator(interval: interval, asOf: asOf, calendar: calendar)
        if let predecessor = try store.neighbor(of: interval.lowerBound, before: true) {
            accumulator.append(predecessor)
        }
        var after: Date?
        while true {
            try Task.checkCancellation()
            guard revision == store.revision else { throw CancellationError() }
            let events = try batch(in: interval, boundary: after, ascending: true)
            guard !events.isEmpty else { break }
            for event in events { accumulator.append(event) }
            after = events.last?.timestamp
            await Task.yield()
        }
        if let successor = try store.neighbor(of: interval.upperBound, before: false) {
            accumulator.append(successor)
        }
        try Task.checkCancellation()
        guard revision == store.revision else { throw CancellationError() }
        return accumulator.summary()
    }

    /// A SQL-limited fetch avoids enumerate() preparing identifiers for an entire
    /// period before its first callback. Complete only the final timestamp bucket.
    private func batch(in interval: Range<Date>, boundary: Date?, ascending: Bool) throws -> [EventSample] {
        let start = interval.lowerBound
        let end = interval.upperBound
        let edge = boundary ?? (ascending ? start : end)
        let hasBoundary = boundary != nil
        let predicate: Predicate<UsageEvent>
        if ascending {
            predicate = #Predicate {
                $0.timestamp >= start && $0.timestamp < end && (!hasBoundary || $0.timestamp > edge)
            }
        } else {
            predicate = #Predicate { $0.timestamp >= start && $0.timestamp < end && $0.timestamp < edge }
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: ascending ? .forward : .reverse)])
        descriptor.fetchLimit = 500
        let partial = try store.context.fetch(descriptor).map(\.sample)
        guard let last = partial.last?.timestamp else { return [] }
        let complete = partial.filter { $0.timestamp != last } + (try store.samples(at: last))
        return complete.sorted {
            ascending ? ReportBuilder.chronological($0, $1) : ReportBuilder.chronological($1, $0)
        }
    }

    private func firstAfter(_ time: Date) throws -> EventSample? {
        var descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp > time }, sortBy: [SortDescriptor(\.timestamp)])
        descriptor.fetchLimit = 1
        guard let timestamp = try store.context.fetch(descriptor).first?.timestamp else { return nil }
        return try store.samples(at: timestamp).first
    }

    @MainActor
    private struct JourneyReader {
        let service: HistoryQueryService
        let query: HistoryQuery
        let cursor: JourneyCursor?
        let limit: Int
        var next: EventSample?
        var before: Date
        var cursorBucket: Date?
        var rows: [JourneyRow] = []

        init(service: HistoryQueryService, query: HistoryQuery, cursor: JourneyCursor?, limit: Int) throws {
            self.service = service
            self.query = query
            self.cursor = cursor
            self.limit = limit
            before = min(query.interval.upperBound, cursor?.timestamp ?? query.interval.upperBound)
            cursorBucket = cursor?.timestamp
            next =
                try cursor.map { try service.firstAfter($0.timestamp) }
                ?? service.store.neighbor(of: query.interval.upperBound, before: false)
        }

        mutating func step() throws -> JourneyPage? {
            let events: [EventSample]
            if let timestamp = cursorBucket {
                cursorBucket = nil
                events =
                    query.interval.contains(timestamp)
                    ? try service.store.samples(at: timestamp).reversed() : []
                // An empty cursor bucket is not exhaustion; strictly older records still follow.
                if events.isEmpty { return nil }
            } else {
                events = try service.batch(in: query.interval, boundary: before, ascending: false)
                if events.isEmpty {
                    if let predecessor = try service.store.neighbor(
                        of: query.interval.lowerBound, before: true)
                    {
                        accept(predecessor)
                    }
                    return page
                }
                before = events.last!.timestamp
            }
            for event in events {
                accept(event)
                if rows.count > limit { return page }
            }
            return nil
        }

        private mutating func accept(_ event: EventSample) {
            let dwell = ReportBuilder.dwell(event, next: next)
            defer { next = event }
            guard cursor?.includes(event) ?? true, query.filter.matches(event) else { return }
            let carryIn = event.timestamp < query.interval.lowerBound
            if carryIn
                && (dwell == nil || event.timestamp.addingTimeInterval(dwell!) <= query.interval.lowerBound)
            {
                return
            }
            rows.append(JourneyRow(event: event, dwell: dwell, isCarryIn: carryIn))
        }

        private var page: JourneyPage {
            let visible = Array(rows.prefix(limit))
            let last = visible.last?.event
            let cursor =
                rows.count > limit ? last.map { JourneyCursor(timestamp: $0.timestamp, id: $0.id) } : nil
            return JourneyPage(rows: visible, nextCursor: cursor)
        }
    }
}
