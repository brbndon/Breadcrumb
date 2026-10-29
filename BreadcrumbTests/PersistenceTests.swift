import Foundation
import SwiftData
import Testing

@testable import Breadcrumb

@MainActor
struct PersistenceTests {
    private func sample(_ name: String = "Synthetic", at seconds: Double = 0) -> EventSample {
        EventSample(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 1_800_000_000 + seconds),
            kind: .app, displayName: name, bundleID: "audit.\(name)", host: nil)
    }

    @Test func startupFailureIsRecoverableWithoutErasingFiles() throws {
        enum Failure: Error { case unavailable }
        var fail = true
        let runtime = AppRuntime(preferences: TrackingPreferences(defaults: nil), automaticCapture: false) {
            if fail { throw Failure.unavailable }
            return try UsageStore.open(inMemory: true)
        }
        #expect(runtime.store == nil)
        #expect(runtime.storageError != nil)
        fail = false
        runtime.load()
        #expect(runtime.store != nil)
        #expect(runtime.storageError == nil)
    }

    @Test func clearAlsoClearsOtherContextAndAllowsNextVisit() throws {
        let store = try UsageStore.open(inMemory: true)
        let other = ModelContext(store.container)
        try store.append(sample())
        #expect(try other.fetchCount(FetchDescriptor<UsageEvent>()) == 1)
        try store.clear()
        #expect(try other.fetchCount(FetchDescriptor<UsageEvent>()) == 0)
        try store.append(sample("Next", at: 10))
        #expect(try other.fetchCount(FetchDescriptor<UsageEvent>()) == 1)
    }

    @Test func importIsIdempotentAndPreservesDwellAndTransitions() throws {
        let store = try UsageStore.open(inMemory: true)
        let events = [sample("A"), sample("B", at: 60), sample("A", at: 120)]
        try store.importSamples(events)
        try store.importSamples(events)
        #expect(try store.context.fetchCount(FetchDescriptor<UsageEvent>()) == 3)
        let report = try store.report(in: Date(timeIntervalSince1970: 0)..<Date.distantFuture)
        #expect(report.switches == 2)
        #expect(report.activeMinutes == 2)
    }

    @Test func queryReportUsesSelectedRange() throws {
        let store = try UsageStore.open(inMemory: true)
        let first = sample("A")
        try store.append(first)
        try store.append(sample("B", at: 60))
        let report = try store.report(in: first.timestamp..<first.timestamp.addingTimeInterval(60))
        #expect(report.apps == 1)
        #expect(report.switches == 0)
        #expect(report.activeMinutes == 1)
    }

    @Test func diskStoreUsesAppScopedFilenameAndPersists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try UsageStore.open(in: folder)
        #expect(store.location?.lastPathComponent == "Breadcrumb.store")
        try store.append(sample())
        let reopened = try UsageStore.open(in: folder)
        #expect(try reopened.context.fetchCount(FetchDescriptor<UsageEvent>()) == 1)
    }

    @Test func reopenedStoreDoesNotBridgeAnAbandonedVisit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let original = try UsageStore.open(in: folder)
            try original.append(sample("A"))
        }
        let reopened = try UsageStore.open(in: folder)
        try reopened.append(sample("B", at: 3600))
        let report = try reopened.report(in: Date(timeIntervalSince1970: 0)..<Date.distantFuture)
        #expect(report.activeMinutes == 0)
        #expect(report.switches == 0)
    }

    @Test func exportImportRoundTripPreservesIdentifiersAndBoundaries() throws {
        var event = sample()
        event.endedAt = event.timestamp.addingTimeInterval(60)
        let data = try HistoryTransfer.encode([event])
        #expect(try HistoryTransfer.decode(data) == [event])
        #expect(throws: (any Error).self) { try HistoryTransfer.decode(Data("{}".utf8)) }
    }

    @Test func archiveRejectsHostOnAppEvent() throws {
        let event = EventSample(
            id: UUID(), timestamp: .now, kind: .app,
            displayName: "Synthetic", bundleID: "audit.app",
            host: "https://example.com/private?token=synthetic")
        let data = try HistoryTransfer.encode([event])
        #expect(throws: (any Error).self) { try HistoryTransfer.decode(data) }
    }

    @Test func archiveRejectsURLStoredAsHost() throws {
        let event = EventSample(
            id: UUID(), timestamp: .now, kind: .site,
            displayName: "example.com/private", bundleID: nil,
            host: "example.com/private")
        let data = try HistoryTransfer.encode([event])
        #expect(throws: (any Error).self) { try HistoryTransfer.decode(data) }
    }

    @Test(arguments: ["file:///private/secret", "about:blank", "javascript:alert(1)", "not a url"])
    func browserHostRejectsNonWebURLs(value: String) {
        #expect(BrowserHostReader.host(from: value) == nil)
    }

    @Test func browserHostDropsCredentialsPathQueryAndFragment() {
        #expect(
            BrowserHostReader.host(from: "https://user:password@Example.COM/path?secret=1#section")
                == "example.com")
    }
}

@MainActor
struct LegacyImportTests {
    @Test func stagingDoesNotChangeOriginalStoreOrSidecars() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: path, cloudKitDatabase: .none)
        let container = try ModelContainer(for: UsageEvent.self, configurations: configuration)
        let first = UsageEvent(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000), displayName: "A", bundleID: "audit.a")
        let second = UsageEvent(
            timestamp: first.timestamp.addingTimeInterval(60), displayName: "B", bundleID: "audit.b")
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let files = ["", "-wal", "-shm"].map { URL(fileURLWithPath: path.path + $0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let samples = try HistoryTransfer.readLegacyStore(in: folder)
        #expect(samples.count == 2)
        #expect(samples.last?.endedAt == second.timestamp)
        #expect(samples.first?.endedAt == nil)
        for (index, file) in files.enumerated() {
            #expect(try Data(contentsOf: file) == before[index])
        }
    }
}
