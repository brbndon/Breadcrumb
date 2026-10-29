import AppKit
import Foundation
import Testing

@testable import Breadcrumb

@MainActor
private final class RecordingStore: EventWriting {
    enum Failure: Error { case unavailable }
    var events: [EventSample] = []
    var failAppend = false
    var failClose = false
    var failClear = false
    func append(_ event: EventSample) throws {
        if failAppend { throw Failure.unavailable }
        events.append(event)
    }
    func close(id: UUID, at date: Date) throws {
        if failClose { throw Failure.unavailable }
        if let index = events.firstIndex(where: { $0.id == id }) { events[index].endedAt = date }
    }
    func clear() throws {
        if failClear { throw Failure.unavailable }
        events = []
    }
}

@MainActor
struct TrackingTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let app = ForegroundApp(name: "Synthetic", bundleID: "audit.app")

    @Test func captureRequiresConsentAndDeduplicatesBundleIdentity() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        let tracker = FrontmostAppTracker(store: store, preferences: preferences)
        tracker.record(app, at: base)
        #expect(store.events.isEmpty)
        preferences.hasConsent = true
        tracker.record(app, at: base)
        tracker.record(
            ForegroundApp(name: "Renamed", bundleID: app.bundleID), at: base.addingTimeInterval(10))
        #expect(store.events.count == 1)
    }

    @Test func pauseClosesVisitAndReportsExcludeStoppedTime() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, clock: { base.addingTimeInterval(60) })
        tracker.record(app, at: base)
        tracker.isPaused = true
        tracker.record(ForegroundApp(name: "Hidden", bundleID: "hidden"), at: base.addingTimeInterval(120))
        #expect(store.events.count == 1)
        tracker.isPaused = false
        tracker.record(app, at: base.addingTimeInterval(3600))
        tracker.record(app, at: base.addingTimeInterval(3610))
        let report = ReportBuilder.build(events: store.events)
        #expect(store.events.count == 2)
        #expect(report.activeMinutes == 1)
        #expect(report.switches == 0)
        #expect(ReportBuilder.journey(events: store.events).last?.dwell == 60)
    }

    @Test func exclusionsEndSegmentsWithoutRecordingExcludedApp() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(store: store, preferences: preferences, clock: { base })
        tracker.record(app, at: base)
        preferences.exclude("audit.app")
        tracker.record(app, at: base.addingTimeInterval(30))
        tracker.record(ForegroundApp(name: "Other", bundleID: "other"), at: base.addingTimeInterval(60))
        #expect(store.events.count == 2)
        #expect(store.events.first?.endedAt == base)
        #expect(ReportBuilder.build(events: store.events).switches == 0)
    }

    @Test func failedSaveDoesNotAdvanceIdentityAndRequiresRetry() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(store: store, preferences: preferences)
        store.failAppend = true
        tracker.record(app, at: base)
        #expect(tracker.errorMessage != nil)
        #expect(store.events.isEmpty)
        store.failAppend = false
        tracker.record(app, at: base)
        #expect(store.events.isEmpty)
        tracker.retry()
        tracker.record(app, at: base)
        #expect(store.events.count == 1)
        #expect(tracker.errorMessage == nil)
    }

    @Test func failedBoundaryKeepsOriginalPauseTimeDuringRetry() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, clock: { base.addingTimeInterval(30) })
        tracker.record(app, at: base)
        store.failClose = true
        tracker.isPaused = true
        #expect(tracker.errorMessage != nil)
        store.failClose = false
        tracker.retry()
        #expect(store.events.first?.endedAt == base.addingTimeInterval(30))
        #expect(tracker.errorMessage == nil)
    }

    @Test func deleteFailureIsVisibleAndPreservesRecords() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(store: store, preferences: preferences, clock: { base })
        tracker.record(app, at: base)
        store.failClear = true
        #expect(!tracker.deleteHistory())
        #expect(store.events.count == 1)
        #expect(tracker.errorMessage != nil)
        store.failClear = false
        #expect(tracker.deleteHistory())
        #expect(store.events.isEmpty)
    }

    @Test func appActivationCannotResumeTrackingDuringSystemSleep() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(store: store, preferences: preferences, currentApp: { app })
        tracker.start()
        defer { tracker.stop() }
        #expect(store.events.count == 1)
        tracker.handleWorkspaceNotification(NSWorkspace.willSleepNotification)
        tracker.handleWorkspaceNotification(NSWorkspace.didActivateApplicationNotification)
        #expect(store.events.count == 1)
        tracker.handleWorkspaceNotification(NSWorkspace.didWakeNotification)
        #expect(store.events.count == 2)
        #expect(ReportBuilder.build(events: store.events).switches == 0)
    }

    @Test func browserIntegrationsAreOffByDefault() {
        let preferences = TrackingPreferences(defaults: nil)
        #expect(preferences.enabledBrowserIDs.isEmpty)
        preferences.setBrowser("company.thebrowser.Browser", enabled: true)
        #expect(preferences.enabledBrowserIDs == ["company.thebrowser.Browser"])
        preferences.setBrowser("company.thebrowser.Browser", enabled: false)
        #expect(preferences.enabledBrowserIDs.isEmpty)
    }
}

private actor HostReaderStub: BrowserHostReading {
    private(set) var calls = 0
    let result: BrowserHostReader.Result
    init(_ result: BrowserHostReader.Result = .host("example.com")) { self.result = result }
    func read(bundleID: String) -> BrowserHostReader.Result {
        calls += 1
        return result
    }
}

@Suite(.serialized)
@MainActor
struct BrowserTrackingTests {
    private let browser = ForegroundApp(name: "Synthetic Browser", bundleID: "company.thebrowser.Browser")

    @Test func enabledBrowserRecordsHostWithoutExtraAppVisit() async throws {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.enabledBrowserIDs = ["company.thebrowser.Browser"]
        let reader = HostReaderStub()
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences,
            currentApp: { browser }, browserReader: reader)
        tracker.start()
        defer { tracker.stop() }
        for _ in 0..<100 where store.events.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.events.count == 1)
        #expect(store.events.first?.kind == .site)
        #expect(store.events.first?.host == "example.com")
        tracker.refresh()
        #expect(store.events.count == 1)
        #expect(await reader.calls == 1)
    }

    @Test func disabledAndExcludedBrowsersAreNotQueried() async throws {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let reader = HostReaderStub()
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences,
            currentApp: { browser }, browserReader: reader)
        tracker.start()
        defer { tracker.stop() }
        #expect(store.events.first?.kind == .app)
        preferences.exclude("company.thebrowser.Browser")
        preferences.enabledBrowserIDs = ["company.thebrowser.Browser"]
        try await Task.sleep(for: .milliseconds(20))
        #expect(await reader.calls == 0)
        #expect(store.events.count == 1)
    }

    @Test func permissionFailureFallsBackToAppAndSurfacesRecovery() async throws {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.enabledBrowserIDs = ["company.thebrowser.Browser"]
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences,
            currentApp: { browser }, browserReader: HostReaderStub(.unavailable))
        tracker.start()
        defer { tracker.stop() }
        for _ in 0..<100 where store.events.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.events.first?.kind == .app)
        #expect(tracker.browserMessage != nil)
    }
}

extension TrackingTests {
    private func activity(_ time: Double, idle: Double? = 0, session: SessionActivity = .active)
        -> ActivitySnapshot
    {
        ActivitySnapshot(timestamp: base.addingTimeInterval(time), idleSeconds: idle, session: session)
    }
    @Test func idleClosesAtLastInputAndResumeStartsFreshSegment() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.pauseWhenIdle = true
        var now = base
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { app }, clock: { now },
            requiresActivity: true)
        tracker.updateActivity(activity(0))
        tracker.start()
        defer { tracker.stop() }
        now = base.addingTimeInterval(420)
        tracker.updateActivity(activity(420, idle: 360))
        #expect(store.events.first?.endedAt == base.addingTimeInterval(60))
        tracker.refresh()
        #expect(store.events.count == 1)
        now = base.addingTimeInterval(421)
        tracker.updateActivity(activity(421))
        #expect(store.events.count == 2)
        #expect(store.events.last?.timestamp == now)
        #expect(ReportBuilder.build(events: store.events).switches == 0)
        #expect(ReportBuilder.build(events: store.events).activeMinutes == 1)
    }
    @Test func independentSessionPauseSleepAndIdleBlockersCannotBypassEachOther() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { app }, clock: { base },
            requiresActivity: true)
        tracker.start()
        defer { tracker.stop() }
        #expect(store.events.isEmpty)
        tracker.updateActivity(activity(0, session: .locked))
        #expect(store.events.isEmpty)
        preferences.pauseWhenIdle = false
        #expect(store.events.isEmpty)
        tracker.updateActivity(activity(0))
        #expect(store.events.count == 1)
        tracker.isPaused = true
        tracker.updateActivity(activity(10, session: .inactive))
        tracker.updateActivity(activity(11))
        #expect(store.events.count == 1)
        tracker.handleWorkspaceNotification(NSWorkspace.willSleepNotification)
        tracker.handleWorkspaceNotification(NSWorkspace.screensDidSleepNotification)
        tracker.isPaused = false
        tracker.handleWorkspaceNotification(NSWorkspace.didWakeNotification)
        #expect(store.events.count == 1)
        tracker.handleWorkspaceNotification(NSWorkspace.screensDidWakeNotification)
        #expect(store.events.count == 2)
    }
    @Test func invalidActivityFailsClosedAndIdleBoundariesAreClamped() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.pauseWhenIdle = true
        var now = base.addingTimeInterval(100)
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { app }, clock: { now },
            requiresActivity: true)
        tracker.updateActivity(activity(100))
        tracker.start()
        defer { tracker.stop() }
        now = base.addingTimeInterval(420)
        tracker.updateActivity(activity(420, idle: 1000))
        #expect(store.events.first?.endedAt == base.addingTimeInterval(100))
        now = base.addingTimeInterval(421)
        tracker.updateActivity(activity(421, idle: .nan))
        #expect(store.events.count == 1)
        #expect(tracker.activityMessage != nil)
        tracker.updateActivity(activity(421))
        #expect(store.events.count == 2)
        tracker.updateActivity(activity(422, idle: nil, session: .unknown))
        #expect(store.events.last?.endedAt == base.addingTimeInterval(422))
    }
    @Test func backwardClockDoesNotCreateVisitsBeforeClosedBoundary() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        var now = base.addingTimeInterval(100)
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { app }, clock: { now },
            requiresActivity: true)
        tracker.updateActivity(activity(100))
        tracker.start()
        defer { tracker.stop() }
        now = base.addingTimeInterval(50)
        tracker.updateActivity(activity(50))
        #expect(store.events.first?.endedAt == base.addingTimeInterval(100))
        tracker.updateActivity(activity(51))
        #expect(store.events.count == 1)
        now = base.addingTimeInterval(101)
        tracker.updateActivity(activity(101))
        #expect(store.events.count == 2)
    }
    @Test func failedIdleBoundaryRetainsFirstCloseTimeAcrossRetries() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.pauseWhenIdle = true
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, clock: { base.addingTimeInterval(900) },
            requiresActivity: true)
        tracker.updateActivity(activity(0))
        tracker.record(app, at: base)
        store.failClose = true
        tracker.updateActivity(activity(420, idle: 360))
        tracker.updateActivity(activity(700, idle: 640))
        #expect(tracker.errorMessage != nil)
        store.failClose = false
        tracker.retry()
        #expect(store.events.first?.endedAt == base.addingTimeInterval(60))
        tracker.record(app, at: base.addingTimeInterval(800))
        #expect(store.events.count == 1)
    }
}

private actor DelayedHostReader: BrowserHostReading {
    var pending: [CheckedContinuation<BrowserHostReader.Result, Never>] = []
    var count: Int { pending.count }
    func read(bundleID: String) async -> BrowserHostReader.Result {
        await withCheckedContinuation { pending.append($0) }
    }
    func finish(_ index: Int) { pending[index].resume(returning: .host("synthetic.example")) }
}

extension BrowserTrackingTests {
    @Test func blockedBrowserResultIsDiscardedAndResumeHasNoExtraAppVisit() async throws {
        let base = Date.now
        var now = base
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.pauseWhenIdle = true
        preferences.enabledBrowserIDs = ["company.thebrowser.Browser"]
        let reader = DelayedHostReader()
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { browser }, clock: { now },
            browserReader: reader, requiresActivity: true)
        tracker.updateActivity(ActivitySnapshot(timestamp: now, idleSeconds: 0, session: .active))
        tracker.start()
        defer { tracker.stop() }
        for _ in 0..<100 where await reader.count < 1 { await Task.yield() }
        now = base.addingTimeInterval(400)
        tracker.updateActivity(ActivitySnapshot(timestamp: now, idleSeconds: 350, session: .active))
        await reader.finish(0)
        for _ in 0..<20 { await Task.yield() }
        #expect(store.events.isEmpty)
        #expect(await reader.count == 1)
        now = base.addingTimeInterval(401)
        tracker.updateActivity(ActivitySnapshot(timestamp: now, idleSeconds: 0, session: .active))
        for _ in 0..<100 where await reader.count < 2 { await Task.yield() }
        await reader.finish(1)
        for _ in 0..<100 where store.events.isEmpty { await Task.yield() }
        #expect(store.events.count == 1)
        #expect(store.events.first?.kind == .site)
    }
}

extension TrackingTests {
    @Test func ordinaryDelayBetweenActivitySampleAndAppCaptureDoesNotPause() {
        let store = RecordingStore()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        let now = base.addingTimeInterval(0.01)
        let tracker = FrontmostAppTracker(
            store: store, preferences: preferences, currentApp: { app }, clock: { now },
            requiresActivity: true)
        tracker.updateActivity(activity(0))
        tracker.start()
        defer { tracker.stop() }
        tracker.refresh()
        #expect(tracker.activityMessage == nil)
        #expect(store.events.count == 1)
        #expect(store.events.first?.endedAt == nil)
    }
}
