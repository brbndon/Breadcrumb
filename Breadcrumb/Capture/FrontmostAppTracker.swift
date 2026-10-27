import AppKit
import Observation
import SwiftData

/// Records a `UsageEvent` whenever the frontmost app changes. Local-only; no polling.
@MainActor
@Observable
final class FrontmostAppTracker {
    var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: Self.pausedKey)
            if isPaused { lastBundleID = nil } else { recordCurrent() }
        }
    }

    private static let pausedKey = "trackingPaused"
    private let context: ModelContext
    private var observer: (any NSObjectProtocol)?
    private var lastBundleID: String?

    init(container: ModelContainer) {
        context = ModelContext(container)
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.record(app) }
        }
        recordCurrent()
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func recordCurrent() {
        record(NSWorkspace.shared.frontmostApplication)
    }

    private func record(_ app: NSRunningApplication?) {
        guard !isPaused, let app, let name = app.localizedName else { return }
        let identity = app.bundleIdentifier ?? name
        guard identity != lastBundleID else { return }
        lastBundleID = identity
        context.insert(UsageEvent(displayName: name, bundleID: app.bundleIdentifier))
        try? context.save()
    }
}
