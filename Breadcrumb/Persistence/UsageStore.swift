import Foundation
import Observation
import SwiftData

@MainActor
protocol EventWriting: AnyObject {
    func append(_ sample: EventSample) throws
    func close(id: UUID, at date: Date) throws
    func clear() throws
}

@MainActor
@Observable
final class UsageStore: EventWriting {
    let container: ModelContainer
    let context: ModelContext
    let location: URL?
    private(set) var revision = 0

    init(container: ModelContainer, location: URL? = nil) {
        self.container = container
        self.context = container.mainContext
        self.context.autosaveEnabled = false
        self.location = location
    }

    static func open(in directory: URL? = nil, inMemory: Bool = false) throws -> UsageStore {
        let schema = Schema([UsageEvent.self])
        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return UsageStore(container: try ModelContainer(for: schema, configurations: [configuration]))
        }
        let folder =
            try directory
            ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Breadcrumb", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let location = folder.appendingPathComponent("Breadcrumb.store")
        let configuration = ModelConfiguration(schema: schema, url: location, cloudKitDatabase: .none)
        let store = UsageStore(
            container: try ModelContainer(for: schema, configurations: [configuration]), location: location)
        var latest = FetchDescriptor<UsageEvent>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        latest.fetchLimit = 1
        if let abandoned = try store.context.fetch(latest).first, abandoned.endedAt == nil {
            // After an unclean exit the actual end is unknown: never count process downtime as usage.
            try store.close(id: abandoned.id, at: abandoned.timestamp)
        }
        return store
    }

    func append(_ sample: EventSample) throws {
        try transaction {
            let event = UsageEvent(
                id: sample.id, timestamp: sample.timestamp, kind: sample.kind,
                displayName: sample.displayName, bundleID: sample.bundleID, host: sample.host,
                passive: sample.passive)
            event.endedAt = sample.endedAt
            context.insert(event)
        }
    }

    func close(id: UUID, at date: Date) throws {
        try transaction {
            let descriptor = FetchDescriptor<UsageEvent>(predicate: #Predicate { $0.id == id })
            if let event = try context.fetch(descriptor).first {
                event.endedAt = max(event.timestamp, date)
            }
        }
    }

    func clear() throws {
        try transaction {
            for event in try context.fetch(FetchDescriptor<UsageEvent>()) { context.delete(event) }
        }
    }

    func importSamples(_ samples: [EventSample]) throws {
        try transaction {
            let known = Set(try context.fetch(FetchDescriptor<UsageEvent>()).map(\.id))
            var inserted = known
            let finalID = samples.max(by: ReportBuilder.chronological)?.id
            for sample in samples where inserted.insert(sample.id).inserted {
                let event = UsageEvent(
                    id: sample.id, timestamp: sample.timestamp, kind: sample.kind,
                    displayName: sample.displayName, bundleID: sample.bundleID, host: sample.host,
                    passive: sample.passive)
                // An imported open visit must not join a new tracking session.
                event.endedAt = sample.endedAt ?? (sample.id == finalID ? sample.timestamp : nil)
                context.insert(event)
            }
        }
    }

    func report(in range: Range<Date>) throws -> Report {
        var accumulator = ReportBuilder.Accumulator(interval: range)
        if let predecessor = try neighbor(of: range.lowerBound, before: true) {
            accumulator.append(predecessor)
        }
        let start = range.lowerBound
        let end = range.upperBound
        let descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)])
        try enumerateChronologically(descriptor) { accumulator.append($0) }
        if let successor = try neighbor(of: end, before: false) { accumulator.append(successor) }
        return accumulator.report()
    }

    /// UUID comparison is performed on value snapshots within timestamp buckets.
    /// SwiftData cannot express UUID-string ordering without a schema change.
    func neighbor(of timestamp: Date, before: Bool) throws -> EventSample? {
        var descriptor: FetchDescriptor<UsageEvent>
        if before {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.timestamp < timestamp },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.timestamp >= timestamp },
                sortBy: [SortDescriptor(\.timestamp)])
        }
        descriptor.fetchLimit = 1
        guard let time = try context.fetch(descriptor).first?.timestamp else { return nil }
        let bucket = try samples(at: time)
        return before ? bucket.last : bucket.first
    }

    func samples(at timestamp: Date) throws -> [EventSample] {
        try context.fetch(FetchDescriptor<UsageEvent>(predicate: #Predicate { $0.timestamp == timestamp }))
            .map(\.sample).sorted(by: ReportBuilder.chronological)
    }

    func enumerateChronologically(
        _ descriptor: FetchDescriptor<UsageEvent>, visit: (EventSample) throws -> Void
    ) throws {
        var bucket: [EventSample] = []
        try context.enumerate(descriptor, batchSize: 500) { event in
            if let timestamp = bucket.first?.timestamp, event.timestamp != timestamp {
                for sample in bucket.sorted(by: ReportBuilder.chronological) { try visit(sample) }
                bucket.removeAll(keepingCapacity: true)
            }
            bucket.append(event.sample)
        }
        for sample in bucket.sorted(by: ReportBuilder.chronological) { try visit(sample) }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        do {
            try operation()
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw error
        }
    }
}
