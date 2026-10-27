import AppKit
import Observation
import SwiftData
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppRuntime {
    let preferences: TrackingPreferences
    let presence: AppPresence
    private(set) var store: UsageStore?
    private(set) var tracker: FrontmostAppTracker?
    private(set) var storageError: String?
    var operationMessage: String?
    private(set) var messageBelongsToMainWindow = false
    private let automaticCapture: Bool
    private let openStore: () throws -> UsageStore

    init(
        preferences: TrackingPreferences = TrackingPreferences(),
        presence: AppPresence = AppPresence(), automaticCapture: Bool = true,
        openStore: @escaping () throws -> UsageStore = { try UsageStore.open() }
    ) {
        self.preferences = preferences
        self.presence = presence
        self.automaticCapture = automaticCapture
        self.openStore = openStore
        load()
    }

    func load() {
        tracker?.stop()
        do {
            let store = try openStore()
            self.store = store
            tracker = FrontmostAppTracker(store: store, preferences: preferences)
            storageError = nil
        } catch {
            store = nil
            tracker = nil
            storageError =
                "Breadcrumb could not open its history. Your existing files have been kept. Check available disk space and folder access, then retry."
        }
    }

    func start() { if automaticCapture { tracker?.start() } }
    func stop() { tracker?.stop() }

    func notify(_ message: String, inMainWindow: Bool = false) {
        messageBelongsToMainWindow = inMainWindow
        operationMessage = message
    }

    func exportHistory() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Breadcrumb-history.json"
        panel.allowedContentTypes = [.json]
        panel.message = "This export contains private app names, timestamps, and any opted-in browser hosts."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let count = try store.context.fetchCount(FetchDescriptor<UsageEvent>())
            guard count <= HistoryTransfer.maximumEvents else { throw HistoryTransfer.TransferError.tooLarge }
            let events = try store.context.fetch(
                FetchDescriptor<UsageEvent>(sortBy: [SortDescriptor(\.timestamp)]))
            try HistoryTransfer.encode(events.map(\.sample)).write(to: url, options: .atomic)
            notify("History exported. Keep the file somewhere private.")
        } catch {
            notify(
                "Export failed. Your history is unchanged. Check the destination and available disk space. Exports support up to 250,000 events."
            )
        }
    }

    func importHistory(legacy: Bool = false, inMainWindow: Bool = false) {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !legacy
        panel.canChooseDirectories = legacy
        panel.allowsMultipleSelection = false
        if !legacy { panel.allowedContentTypes = [.json] }
        panel.message =
            legacy
            ? "Close the previous Breadcrumb build, then select the folder containing its default.store and WAL. The originals will not be changed."
            : "Choose a Breadcrumb JSON export. Existing records are kept; duplicates are skipped."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        tracker?.endSegment()
        guard tracker?.errorMessage == nil else { return }
        do {
            let samples: [EventSample]
            if legacy {
                samples = try HistoryTransfer.readLegacyStore(in: url)
            } else {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= HistoryTransfer.maximumBytes else {
                    throw HistoryTransfer.TransferError.tooLarge
                }
                samples = try HistoryTransfer.decode(Data(contentsOf: url))
            }
            try store.importSamples(samples)
            notify(
                "History imported. Original files and existing records have been kept.",
                inMainWindow: inMainWindow)
        } catch {
            notify(
                "Import failed. The file may be incompatible or too large. Your existing history and the selected original files have been kept.",
                inMainWindow: inMainWindow)
        }
        tracker?.refresh()
    }
}
