import AppKit
import Observation

struct ForegroundApp: Equatable, Sendable {
    let name: String
    let bundleID: String?
    var identity: String { bundleID ?? name }

    /// Processes that only host system alerts. They take focus when a dialog appears and keep it
    /// while the dialog waits unanswered, so they are never visits.
    static let systemDialogAgents: Set<String> = ["com.apple.UserNotificationCenter"]
    var isSystemDialogAgent: Bool { bundleID.map(Self.systemDialogAgents.contains) ?? false }

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
    private var systemSleeping = false
    private var displaySleeping = false
    private var sleeping: Bool { systemSleeping || displaySleeping }
    private let requiresActivity: Bool
    private var activity: ActivitySnapshot?
    private var lastMediaObserved: Date?
    private var mediaIdentity: String?
    private var mediaIsPlaying: Bool {
        guard let media = activity?.media, media.isPlaying else { return false }
        return media.appIdentity == currentApp()?.identity
    }
    private var idleThreshold: TimeInterval { Double(preferences.idleThresholdMinutes) * 60 }
    private var effectiveIdle: TimeInterval? {
        guard let activity, let idle = activity.idleSeconds, idle.isFinite, idle >= 0 else { return nil }
        let input = activity.timestamp.addingTimeInterval(-idle)
        let media = mediaIdentity == currentApp()?.identity ? lastMediaObserved : nil
        return max(0, activity.timestamp.timeIntervalSince(max(input, media ?? input)))
    }
    /// Only meaningful while capture is allowed: with media absent, idle input past the threshold
    /// would already have paused capture, so this is media time without input.
    private var passiveNow: Bool {
        guard preferences.pauseWhenIdle, let idle = activity?.idleSeconds, idle.isFinite else { return false }
        return idle >= idleThreshold
    }
    private var resumeNotBefore: Date?
    private var clockBlocked = false
    private var earliestCaptureDate: Date {
        max(resumeNotBefore ?? .distantPast, currentEvent?.timestamp ?? .distantPast)
    }

    var activityMessage: String? {
        guard requiresActivity else { return nil }
        guard let activity else { return "Checking session activity. Tracking is paused." }
        if activity.session == .unknown {
            return "Session activity is unavailable. Tracking is paused; retry the activity check."
        }
        if activity.session == .inactive {
            return "Tracking is paused while this console session is inactive."
        }
        if activity.session == .locked { return "Tracking is paused while the session is locked." }
        if clockBlocked {
            return "Tracking is paused until the clock catches up with the last visit boundary."
        }
        if preferences.pauseWhenIdle {
            guard let idle = effectiveIdle else {
                return "Idle activity is unavailable. Tracking is paused; retry the activity check."
            }
            if !mediaIsPlaying && idle >= idleThreshold {
                return
                    "Tracking is paused after \(preferences.idleThresholdMinutes) minutes without input or observed media activity."
            }
        }
        return nil
    }
    var isAutomaticallyPaused: Bool { sleeping || activityMessage != nil }
    private var activityAllowsCapture: Bool { activityMessage == nil }
    private func eligible(at date: Date) -> Bool {
        preferences.hasConsent && !isPaused && !sleeping && activityAllowsCapture
            && date >= earliestCaptureDate
    }
    private var running = false
    private var generation = 0

    init(
        store: any EventWriting, preferences: TrackingPreferences,
        currentApp: @escaping @MainActor () -> ForegroundApp? = { ForegroundApp.current() },
        clock: @escaping () -> Date = { .now },
        browserReader: any BrowserHostReading = BrowserHostReader(), requiresActivity: Bool = false
    ) {
        self.store = store
        self.preferences = preferences
        self.currentApp = currentApp
        self.clock = clock
        self.browserReader = browserReader
        self.requiresActivity = requiresActivity
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
        case NSWorkspace.willSleepNotification:
            systemSleeping = true
            endSegment()
        case NSWorkspace.screensDidSleepNotification:
            displaySleeping = true
            endSegment()
        case NSWorkspace.didWakeNotification:
            systemSleeping = false
            refresh()
        case NSWorkspace.screensDidWakeNotification:
            displaySleeping = false
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
        let date = clock()
        guard eligible(at: date) else {
            endSegment(at: date)
            return
        }
        guard pendingBoundary == nil, errorMessage == nil else { return }
        let app = currentApp()
        let readsHost =
            app?.bundleID.map {
                eligible(at: clock())
                    && !preferences.excludedBundleIDs.contains($0)
                    && preferences.enabledBrowserIDs.contains($0) && BrowserHostReader.supported[$0] != nil
            } ?? false
        if !readsHost { record(app, at: clock()) }
        startBrowserPolling()
    }

    /// Also used by deterministic capture tests; app metadata is never logged.
    func record(_ app: ForegroundApp?, at date: Date) {
        guard pendingBoundary == nil, errorMessage == nil else { return }
        if date < earliestCaptureDate { clockBlocked = true }
        guard eligible(at: date),
            let app, !preferences.excludedBundleIDs.contains(app.identity), !app.isSystemDialogAgent
        else {
            endSegment(at: date)
            return
        }
        if let currentEvent, (currentEvent.bundleID ?? currentEvent.displayName) == app.identity { return }
        let sample = EventSample(
            id: UUID(), timestamp: date, kind: .app, displayName: app.name, bundleID: app.bundleID, host: nil,
            passive: passiveNow)
        persist(sample)
    }

    func endSegment(at date: Date? = nil) {
        generation += 1
        browserTask?.cancel()
        browserTask = nil
        pollingBundleID = nil
        guard let currentEvent else { return }
        let requested = max(currentEvent.timestamp, date ?? clock())
        let boundary = min(pendingBoundary ?? requested, requested)
        do {
            try store.close(id: currentEvent.id, at: boundary)
            self.currentEvent = nil
            lastMediaObserved = nil
            mediaIdentity = nil
            resumeNotBefore = max(resumeNotBefore ?? boundary, boundary)
            pendingBoundary = nil
        } catch {
            pendingBoundary = boundary
            errorMessage = "History could not be saved. Tracking is stopped. Free up disk space and retry."
        }
    }

    func updateActivity(_ snapshot: ActivitySnapshot) {
        let wasAllowed = activityAllowsCapture
        if snapshot.timestamp.timeIntervalSince1970.isFinite {
            clockBlocked = snapshot.timestamp < earliestCaptureDate
            activity = snapshot
            if snapshot.session == .active, snapshot.media?.isPlaying == true,
                snapshot.media?.appIdentity == currentApp()?.identity
            {
                lastMediaObserved = snapshot.timestamp
                mediaIdentity = snapshot.media?.appIdentity
            }
        } else {
            activity = ActivitySnapshot(timestamp: clock(), idleSeconds: nil, session: .unknown)
        }
        if !activityAllowsCapture {
            var boundary = activity?.timestamp ?? clock()
            if snapshot.session == .active, preferences.pauseWhenIdle,
                let idle = effectiveIdle, idle >= idleThreshold
            {
                boundary = snapshot.timestamp.addingTimeInterval(-idle)
                boundary = min(snapshot.timestamp, max(currentEvent?.timestamp ?? boundary, boundary))
            }
            endSegment(at: boundary)
        } else if !wasAllowed {
            refresh()
        } else {
            reconcilePassive()
        }
    }

    /// Splits the visit where input stopped (or resumed) so media watched without input stays
    /// recorded but is told apart from time spent at the keyboard.
    private func reconcilePassive() {
        guard let current = currentEvent, pendingBoundary == nil, errorMessage == nil, let activity,
            current.passive != passiveNow
        else { return }
        let lastInput = activity.timestamp.addingTimeInterval(-(activity.idleSeconds ?? 0))
        let boundary = min(activity.timestamp, max(current.timestamp, lastInput))
        do {
            try store.close(id: current.id, at: boundary)
        } catch {
            endSegment(at: boundary)
            return
        }
        persist(
            EventSample(
                id: UUID(), timestamp: boundary, kind: current.kind, displayName: current.displayName,
                bundleID: current.bundleID, host: current.host, passive: passiveNow))
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

    func policyChanged(refresh shouldRefresh: Bool = true) {
        endSegment()
        if shouldRefresh && pendingBoundary == nil { refresh() }
    }

    private func persist(_ sample: EventSample) {
        do {
            try store.append(sample)
            if (currentEvent?.bundleID ?? currentEvent?.displayName)
                != (sample.bundleID ?? sample.displayName)
            {
                lastMediaObserved = nil
                mediaIdentity = nil
            }
            currentEvent = sample
            errorMessage = nil
        } catch {
            endSegment(at: sample.timestamp)
            errorMessage = "History could not be saved. Tracking is stopped. Free up disk space and retry."
            // Do not advance identity on failure: a retry must attempt this visit again.
        }
    }

    private func startBrowserPolling() {
        guard eligible(at: clock()), pendingBoundary == nil, errorMessage == nil,
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
                    self.eligible(at: self.clock()),
                    self.currentApp()?.bundleID == id
                else { return }
                switch result {
                case .host(let host):
                    self.browserMessage = nil
                    let sample = EventSample(
                        id: UUID(), timestamp: timestamp, kind: .site,
                        displayName: host, bundleID: id, host: host, passive: self.passiveNow)
                    if self.currentEvent?.nodeKey != sample.nodeKey { self.persist(sample) }
                case .noPage, .privateWindow:
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
            displayName: app.name, bundleID: app.bundleID, host: nil, passive: passiveNow)
        if currentEvent?.nodeKey != sample.nodeKey { persist(sample) }
    }
}
