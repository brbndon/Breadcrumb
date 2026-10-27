import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(FrontmostAppTracker.self) private var tracker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Breadcrumb") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Button(tracker.isPaused ? "Resume Tracking" : "Stop Tracking") {
            tracker.isPaused.toggle()
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Breadcrumb") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
