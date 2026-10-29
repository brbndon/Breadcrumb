import Foundation
import Testing

@testable import Breadcrumb

@MainActor
private final class ActivityStub: ActivityProviding {
    var calls = 0
    var session: SessionActivity = .active
    func snapshot(at date: Date) -> ActivitySnapshot {
        calls += 1
        return ActivitySnapshot(timestamp: date, idleSeconds: 0, session: session)
    }
}

@MainActor
private final class SchedulerStub: ActivityScheduling {
    var starts = 0
    var stops = 0
    var callback: (@MainActor (SessionActivity?) -> Void)?
    func start(_ callback: @escaping @MainActor (SessionActivity?) -> Void) {
        starts += 1
        self.callback = callback
    }
    func stop() {
        stops += 1
        callback = nil
    }
}

@MainActor
struct ActivityMonitorTests {
    @Test func monitoringWaitsForConsentAndDoesNotDuplicateAcrossStoreRetries() throws {
        let provider = ActivityStub()
        let scheduler = SchedulerStub()
        let monitor = ActivityMonitor(provider: provider, scheduler: scheduler)
        let preferences = TrackingPreferences(defaults: nil)
        var appReads = 0
        let runtime = AppRuntime(
            preferences: preferences, login: LoginItemController(service: IsolatedLoginItemService()),
            activityMonitor: monitor,
            currentApp: {
                appReads += 1
                return ForegroundApp(name: "Synthetic", bundleID: "synthetic")
            },
            openStore: { try UsageStore.open(inMemory: true) })
        runtime.start()
        #expect(provider.calls == 0)
        #expect(appReads == 0)
        preferences.hasConsent = true
        #expect(provider.calls == 1)
        #expect(scheduler.starts == 1)
        runtime.start()
        #expect(scheduler.starts == 1)
        runtime.load()
        #expect(scheduler.starts == 2)
        preferences.hasConsent = false
        let calls = provider.calls
        scheduler.callback?(nil)
        #expect(provider.calls == calls)
        runtime.stop()
        #expect(scheduler.callback == nil)
    }
    @Test func immediateInactiveSignalOverridesProviderUntilNextActiveSample() {
        let provider = ActivityStub()
        let scheduler = SchedulerStub()
        let monitor = ActivityMonitor(provider: provider, scheduler: scheduler)
        var samples: [ActivitySnapshot] = []
        monitor.onSample = { samples.append($0) }
        monitor.start()
        scheduler.callback?(.inactive)
        #expect(samples.last?.session == .inactive)
        scheduler.callback?(nil)
        #expect(samples.last?.session == .inactive)
        scheduler.callback?(.active)
        #expect(samples.last?.session == .active)
        monitor.stop()
    }
    @Test func idleSettingIsOffByDefaultAndPersistsOnlyToInjectedSuite() throws {
        let suite = "BreadcrumbIdleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = TrackingPreferences(defaults: defaults)
        #expect(!preferences.pauseWhenIdle)
        preferences.pauseWhenIdle = true
        #expect(TrackingPreferences(defaults: defaults).pauseWhenIdle)
        #expect(!TrackingPreferences(defaults: nil).pauseWhenIdle)
    }
}
