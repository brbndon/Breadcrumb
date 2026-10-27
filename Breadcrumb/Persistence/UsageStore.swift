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
                displayName: sample.displayName, bundleID: sample.bundleID, host: sample.host)
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
                    displayName: sample.displayName, bundleID: sample.bundleID, host: sample.host)
                // An imported open visit must not join a new tracking session.
                event.endedAt = sample.endedAt ?? (sample.id == finalID ? sample.timestamp : nil)
                context.insert(event)
            }
        }
    }

    func report(in range: Range<Date>) throws -> Report {
        let start = range.lowerBound
        let end = range.upperBound
        let descriptor = FetchDescriptor<UsageEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)])
        var accumulator = ReportBuilder.Accumulator()
        try context.enumerate(descriptor, batchSize: 500) { accumulator.append($0.sample) }
        return accumulator.report()
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
