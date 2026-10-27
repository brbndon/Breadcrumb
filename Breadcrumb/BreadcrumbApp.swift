import SwiftData
import SwiftUI

@main
struct BreadcrumbApp: App {
    private let container: ModelContainer
    @State private var tracker: FrontmostAppTracker
    @AppStorage("appearance") private var appearance = AppearanceSetting.auto

    init() {
        let container = try! ModelContainer(for: UsageEvent.self)
        self.container = container
        _tracker = State(initialValue: FrontmostAppTracker(container: container))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(appearance.colorScheme)
                .environment(tracker)
                .task { tracker.start() }
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 820)

        MenuBarExtra {
            MenuBarContent()
                .environment(tracker)
        } label: {
            Image(systemName: tracker.isPaused ? "pause.circle" : "point.topleft.down.to.point.bottomright.curvepath")
                .accessibilityLabel(tracker.isPaused ? "Breadcrumb (paused)" : "Breadcrumb")
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(tracker)
                .modelContainer(container)
        }
    }
}
