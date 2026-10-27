import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Breadcrumb") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        if let tracker = runtime.tracker {
            if runtime.preferences.hasConsent {
                Button(tracker.isPaused ? "Resume Tracking" : "Stop Tracking") {
                    tracker.isPaused.toggle()
                }
                if tracker.errorMessage != nil { Button("Retry Saving History") { tracker.retry() } }
            } else {
                Text("Complete privacy setup to start tracking")
            }
        } else {
            Text("History unavailable — open Breadcrumb to retry")
        }
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Divider()
        Button("Quit Breadcrumb") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
