import AppKit
import SwiftData
import SwiftUI

@main
struct BreadcrumbApp: App {
    @NSApplicationDelegateAdaptor(BreadcrumbDelegate.self) private var delegate
    @State private var runtime: AppRuntime
    @AppStorage("appearance") private var appearance = AppearanceSetting.auto

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isolated = environment["BREADCRUMB_TESTING"] == "1" || environment["BREADCRUMB_DEMO"] == "1"
        let preferences = TrackingPreferences(defaults: isolated ? nil : .standard)
        let runtime = AppRuntime(
            preferences: preferences, presence: AppPresence(defaults: isolated ? nil : .standard),
            automaticCapture: !isolated,
            openStore: { try UsageStore.open(inMemory: isolated) })
        _runtime = State(initialValue: runtime)
        delegate.runtime = runtime
    }

    var body: some Scene {
        Window("Breadcrumb", id: "main") {
            Group {
                if let store = runtime.store {
                    RootView().modelContainer(store.container)
                } else {
                    StorageFailureView()
                }
            }
            .frame(minWidth: 960, minHeight: 640)
            .preferredColorScheme(appearance.colorScheme)
            .environment(runtime)
            .background(AppPresenceWindow(presence: runtime.presence))

        }
        .defaultSize(width: 1200, height: 820)
        .defaultLaunchBehavior(.suppressed)

        // A Settings scene can be the first window on a quiet login launch.
        MenuBarExtra {
            MenuBarContent().environment(runtime)
        } label: {
            let paused =
                runtime.tracker?.isPaused != false || !runtime.preferences.hasConsent
                || runtime.tracker?.errorMessage != nil
            LaunchMenuLabel(runtime: runtime, paused: paused)
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(runtime)
                .background(AppPresenceWindow(presence: runtime.presence))
        }
    }
}

@MainActor
final class BreadcrumbDelegate: NSObject, NSApplicationDelegate {
    var runtime: AppRuntime?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime else { return }
        let login = LaunchReason.isLogin(event: NSAppleEventManager.shared().currentAppleEvent)
        runtime.start()
        if LaunchReason.shouldOpenWindow(login: login, hasConsent: runtime.preferences.hasConsent) {
            // SwiftUI owns the single main window; opening by identifier also works before it exists.
            runtime.requestInitialWindow = true
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { runtime?.stop() }
}

private struct LaunchMenuLabel: View {
    let runtime: AppRuntime
    let paused: Bool
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: paused ? "pause.circle" : "point.topleft.down.to.point.bottomright.curvepath")
            .accessibilityLabel(paused ? "Breadcrumb (not tracking)" : "Breadcrumb")
            .onChange(of: runtime.requestInitialWindow, initial: true) {
                if runtime.requestInitialWindow {
                    runtime.requestInitialWindow = false
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
    }
}
