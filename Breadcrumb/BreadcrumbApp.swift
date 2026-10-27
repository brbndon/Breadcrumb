import AppKit
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
        _runtime = State(
            initialValue: AppRuntime(
                preferences: preferences, presence: AppPresence(defaults: isolated ? nil : .standard),
                automaticCapture: !isolated,
                openStore: { try UsageStore.open(inMemory: isolated) }))
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
            .task {
                delegate.runtime = runtime
                runtime.start()
            }
        }
        .defaultSize(width: 1200, height: 820)

        MenuBarExtra {
            MenuBarContent().environment(runtime)
        } label: {
            let paused =
                runtime.tracker?.isPaused != false || !runtime.preferences.hasConsent
                || runtime.tracker?.errorMessage != nil
            Image(systemName: paused ? "pause.circle" : "point.topleft.down.to.point.bottomright.curvepath")
                .accessibilityLabel(paused ? "Breadcrumb (not tracking)" : "Breadcrumb")
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { runtime?.stop() }
}
