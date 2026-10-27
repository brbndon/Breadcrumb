import Foundation
import SwiftData

struct HistoryArchive: Codable {
    let version: Int
    let events: [EventSample]
}

enum HistoryTransfer {
    enum TransferError: Error { case invalidArchive, tooLarge }
    static let maximumBytes = 128 * 1024 * 1024
    static let maximumEvents = 250_000

    static func encode(_ events: [EventSample]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard events.count <= maximumEvents else { throw TransferError.tooLarge }
        let data = try encoder.encode(HistoryArchive(version: 1, events: events))
        guard data.count <= maximumBytes else { throw TransferError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> [EventSample] {
        guard data.count <= maximumBytes else { throw TransferError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(HistoryArchive.self, from: data)
        guard archive.version == 1, archive.events.count <= maximumEvents else {
            throw TransferError.invalidArchive
        }
        for event in archive.events {
            guard !event.displayName.isEmpty, event.displayName.count <= 1024,
                event.timestamp >= .distantPast, event.timestamp <= .distantFuture,
                event.endedAt.map({ $0 >= event.timestamp && $0 <= .distantFuture }) ?? true
            else {
                throw TransferError.invalidArchive
            }
            if event.kind == .site {
                guard let host = event.host,
                    BrowserHostReader.host(from: "https://\(host)") == host,
                    event.displayName == host
                else { throw TransferError.invalidArchive }
            } else if event.host != nil {
                throw TransferError.invalidArchive
            }
        }
        return archive.events
    }

    /// Copy first: opening even a read-only SQLite connection can update the source SHM file.
    /// The user selects the old store's folder, with the old app closed, to include its WAL.
    @MainActor static func readLegacyStore(in folder: URL) throws -> [EventSample] {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let source = folder.appendingPathComponent("default.store")
        for suffix in ["", "-wal"] {
            let file = URL(fileURLWithPath: source.path + suffix)
            guard manager.fileExists(atPath: file.path) else {
                if suffix.isEmpty { throw TransferError.invalidArchive }
                continue
            }
            let attributes = try manager.attributesOfItem(atPath: file.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= maximumBytes else {
                throw TransferError.tooLarge
            }
            try manager.copyItem(
                at: file,
                to: URL(fileURLWithPath: staging.appendingPathComponent("legacy.store").path + suffix))
        }
        let schema = Schema([UsageEvent.self])
        let configuration = ModelConfiguration(
            schema: schema, url: staging.appendingPathComponent("legacy.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        var descriptor = FetchDescriptor<UsageEvent>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.fetchLimit = maximumEvents + 1
        var samples = try container.mainContext.fetch(descriptor).map(\.sample)
        guard samples.count <= maximumEvents else { throw TransferError.tooLarge }
        // Preserve historical dwell, but prevent imports from bridging into live tracking.
        if let last = samples.indices.last, samples[last].endedAt == nil {
            samples[last].endedAt = samples[last].timestamp
        }
        return samples
    }
}
