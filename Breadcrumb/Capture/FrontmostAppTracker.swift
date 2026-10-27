import AppKit
import Observation

struct ForegroundApp: Equatable, Sendable {
    let name: String
    let bundleID: String?
    var identity: String { bundleID ?? name }

    @MainActor static func current() -> ForegroundApp? {
        guard let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName else {
            return nil
        }
        return ForegroundApp(name: name, bundleID: app.bundleIdentifier)
    }
}

@MainActor
@Observable
final class FrontmostAppTracker {
    let preferences: TrackingPreferences
    private(set) var errorMessage: String?
    private(set) var browserMessage: String?
    var isPaused: Bool {
        get { preferences.isPaused }
        set { preferences.isPaused = newValue }
    }
    private let store: any EventWriting
    private let currentApp: @MainActor () -> ForegroundApp?
    private let clock: () -> Date
    private var observers: [any NSObjectProtocol] = []
    private var browserTask: Task<Void, Never>?
    private let browserReader: any BrowserHostReading
    private var pollingBundleID: String?
    private var currentEvent: EventSample?
    private var pendingBoundary: Date?
    private var sleeping = false
    private var running = false
    private var generation = 0

    init(
        store: any EventWriting, preferences: TrackingPreferences,
        currentApp: @escaping @MainActor () -> ForegroundApp? = { ForegroundApp.current() },
        clock: @escaping () -> Date = { .now },
        browserReader: any BrowserHostReading = BrowserHostReader()
    ) {
        self.store = store
        self.preferences = preferences
        self.currentApp = currentApp
        self.clock = clock
        self.browserReader = browserReader
        preferences.onChange = { [weak self] in self?.policyChanged() }
    }

    func start() {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification, NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleWorkspaceNotification(name) }
                })
        }
        refresh()
    }

    func handleWorkspaceNotification(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            sleeping = true
            endSegment()
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification:
            sleeping = false
            refresh()
        default:
            refresh()
        }
    }

    func stop() {
        endSegment()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        running = false
    }

    func refresh() {
        guard running else { return }
        let app = currentApp()
        let readsHost =
            app?.bundleID.map {
                preferences.hasConsent && !isPaused && !sleeping
                    && !preferences.excludedBundleIDs.contains($0)
                    && preferences.enabledBrowserIDs.contains($0) && BrowserHostReader.supported[$0] != nil
            } ?? false
        if !readsHost { record(app, at: clock()) }
        startBrowserPolling()
    }

    /// Also used by deterministic capture tests; app metadata is never logged.
    func record(_ app: ForegroundApp?, at date: Date) {
        guard pendingBoundary == nil, errorMessage == nil else { return }
        guard preferences.hasConsent, !isPaused, !sleeping,
            let app, !preferences.excludedBundleIDs.contains(app.identity)
        else {
            endSegment(at: date)
            return
        }
        if let currentEvent, (currentEvent.bundleID ?? currentEvent.displayName) == app.identity { return }
        let sample = EventSample(
            id: UUID(), timestamp: date, kind: .app, displayName: app.name, bundleID: app.bundleID, host: nil)
        persist(sample)
    }

    func endSegment(at date: Date? = nil) {
        generation += 1
        browserTask?.cancel()
        browserTask = nil
        pollingBundleID = nil
        guard let currentEvent else { return }
        let boundary = pendingBoundary ?? date ?? clock()
        do {
            try store.close(id: currentEvent.id, at: boundary)
            self.currentEvent = nil
            pendingBoundary = nil
        } catch {
            pendingBoundary = boundary
            errorMessage = "History could not be saved. Tracking is stopped. Free up disk space and retry."
        }
    }

    func retry() {
        if pendingBoundary != nil { endSegment() }
        guard pendingBoundary == nil else { return }
        errorMessage = nil
        refresh()
    }

    func deleteHistory() -> Bool {
        endSegment()
        guard pendingBoundary == nil else { return false }
        do {
            try store.clear()
            currentEvent = nil
            errorMessage = nil
            // Restart on the next activation/reconciliation, so the empty state is visible first.
            return true
        } catch {
            errorMessage =
                "History could not be deleted. Your existing history has been kept. Retry when storage is available."
            return false
        }
    }

    private func policyChanged() {
        endSegment()
        if pendingBoundary == nil { refresh() }
    }

    private func persist(_ sample: EventSample) {
        do {
            try store.append(sample)
            currentEvent = sample
            errorMessage = nil
        } catch {
            endSegment(at: sample.timestamp)
            errorMessage = "History could not be saved. Tracking is stopped. Free up disk space and retry."
            // Do not advance identity on failure: a retry must attempt this visit again.
        }
    }

    private func startBrowserPolling() {
        guard preferences.hasConsent, !isPaused, !sleeping, pendingBoundary == nil, errorMessage == nil,
            let app = currentApp(), let id = app.bundleID,
            preferences.enabledBrowserIDs.contains(id),
            !preferences.excludedBundleIDs.contains(id), BrowserHostReader.supported[id] != nil
        else {
            generation += 1
            browserTask?.cancel()
            browserTask = nil
            pollingBundleID = nil
            return
        }
        if browserTask != nil && pollingBundleID == id { return }
        generation += 1
        browserTask?.cancel()
        pollingBundleID = id
        let token = generation
        browserTask = Task { [weak self, browserReader] in
            while !Task.isCancelled {
                let timestamp = self?.clock() ?? .now
                let result = await browserReader.read(bundleID: id)
                guard let self, !Task.isCancelled, self.generation == token, self.errorMessage == nil,
                    self.currentApp()?.bundleID == id
                else { return }
                switch result {
                case .host(let host):
                    self.browserMessage = nil
                    let sample = EventSample(
                        id: UUID(), timestamp: timestamp, kind: .site,
                        displayName: host, bundleID: id, host: host)
                    if self.currentEvent?.nodeKey != sample.nodeKey { self.persist(sample) }
                case .noPage:
                    self.browserMessage = nil
                    self.recordBrowserFallback(app, at: timestamp)
                case .unavailable:
                    self.browserMessage =
                        "Browser access is unavailable. Allow Breadcrumb in System Settings → Privacy & Security → Automation, or turn off this integration. App-only tracking continues."
                    self.recordBrowserFallback(app, at: timestamp)
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func recordBrowserFallback(_ app: ForegroundApp, at date: Date) {
        let sample = EventSample(
            id: UUID(), timestamp: date, kind: .app,
            displayName: app.name, bundleID: app.bundleID, host: nil)
        if currentEvent?.nodeKey != sample.nodeKey { persist(sample) }
    }
}
