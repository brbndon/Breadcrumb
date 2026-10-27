import AppKit
import Testing

@testable import Breadcrumb

@MainActor
struct AppPresenceTests {
    @Test func defaultKeepsDockPresenceAndPreferencePersists() throws {
        let suite = "BreadcrumbPresenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var policy: NSApplication.ActivationPolicy?
        let presence = AppPresence(defaults: defaults) { policy = $0 }
        #expect(!presence.hideWhenNoWindows)
        presence.hideWhenNoWindows = true
        #expect(policy == .accessory)
        #expect(AppPresence(defaults: defaults, applyPolicy: { _ in }).hideWhenNoWindows)
        presence.hideWhenNoWindows = false
        #expect(policy == .regular)
    }

    @Test func closingLastSceneWindowHidesDockAndReopeningRestoresIt() {
        var policy: NSApplication.ActivationPolicy?
        let presence = AppPresence(defaults: nil) { policy = $0 }
        let main = NSWindow()
        let settings = NSWindow()
        presence.hideWhenNoWindows = true
        presence.register(main)
        presence.register(settings)
        #expect(policy == .regular)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: main)
        #expect(policy == .regular)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: settings)
        #expect(policy == .accessory)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: main)
        #expect(policy == .regular)
    }

    @Test func transientWindowsCannotRestoreDockPresence() {
        var policy: NSApplication.ActivationPolicy?
        let presence = AppPresence(defaults: nil) { policy = $0 }
        presence.hideWhenNoWindows = true
        let panel = NSPanel()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)
        #expect(policy == .accessory)
    }

    @Test func minimizedWindowsStillCountAsOpenAndDisablingRestoresDock() {
        var policy: NSApplication.ActivationPolicy?
        let presence = AppPresence(defaults: nil) { policy = $0 }
        let window = NSWindow()
        presence.register(window)
        presence.hideWhenNoWindows = true
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        #expect(policy == .regular)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(policy == .accessory)
        presence.hideWhenNoWindows = false
        #expect(policy == .regular)
    }
}
