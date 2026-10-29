import Foundation
import SwiftData

@MainActor
final class HistoryQueryService {
    let store: UsageStore
    init(store: UsageStore) { self.store = store }

    func journeyPage(for query: HistoryQuery, before cursor: JourneyCursor?, limit: Int) throws -> JourneyPage
    {
        guard limit > 0 else { return JourneyPage(rows: [], nextCursor: nil) }
        let start = query.interval.lowerBound
        let end = query.interval.upperBound
        let ceiling = cursor?.timestamp ?? end
        let descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end && $0.timestamp <= ceiling },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        var next = try store.neighbor(of: ceiling, before: false)
        // The cursor bucket is read in full, so its successor must be strictly newer.
        if cursor != nil { next = try firstAfter(ceiling) }
        var rows: [JourneyRow] = []
        func accept(_ event: EventSample) throws {
            let dwell = ReportBuilder.dwell(event, next: next)
            defer { next = event }
            guard cursor?.includes(event) ?? true, query.filter.matches(event) else { return }
            let carryIn = event.timestamp < start
            if carryIn && (dwell == nil || event.timestamp.addingTimeInterval(dwell!) <= start) { return }
            rows.append(JourneyRow(event: event, dwell: dwell, isCarryIn: carryIn))
            if rows.count > limit { throw PageComplete.enough }
        }
        var bucket: [EventSample] = []
        do {
            try store.context.enumerate(descriptor, batchSize: 500) { event in
                if let time = bucket.first?.timestamp, time != event.timestamp {
                    for sample in bucket.sorted(by: { ReportBuilder.chronological($1, $0) }) {
                        try accept(sample)
                    }
                    bucket.removeAll(keepingCapacity: true)
                }
                bucket.append(event.sample)
            }
            for sample in bucket.sorted(by: { ReportBuilder.chronological($1, $0) }) { try accept(sample) }
            if let predecessor = try store.neighbor(of: start, before: true) { try accept(predecessor) }
        } catch PageComplete.enough {
            // A single matching lookahead distinguishes exhaustion from another page.
        }
        let visible = Array(rows.prefix(limit))
        let last = visible.last?.event
        let cursor = rows.count > limit ? last.map { JourneyCursor(timestamp: $0.timestamp, id: $0.id) } : nil
        return JourneyPage(rows: visible, nextCursor: cursor)
    }

    private func firstAfter(_ time: Date) throws -> EventSample? {
        var descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp > time }, sortBy: [SortDescriptor(\.timestamp)])
        descriptor.fetchLimit = 1
        guard let timestamp = try store.context.fetch(descriptor).first?.timestamp else { return nil }
        return try store.samples(at: timestamp).first
    }

    private enum PageComplete: Error { case enough }
}
