import SwiftUI

struct PrivacyIntroduction: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your path stays on your Mac").font(.title2.bold())
            Text(
                "Breadcrumb records the name and bundle identifier of the foreground app, and when you switch. Tracking starts after you choose below."
            )
            Text(
                "History is stored in Breadcrumb/Breadcrumb.store inside this app’s Application Support folder. There is no account, upload, or analytics."
            )
            Text(
                "Arc and Dia integrations are off by default. Enable either in Settings to request Automation permission and record only website hosts. Full URLs and page titles are never stored."
            )
            Text(
                "Pause, exclude apps, export, or delete history in Settings. Pauses, exclusions, and sleep end the current tracking segment. Active time is an estimate capped at five minutes per visit, not keyboard or mouse activity."
            )
            HStack {
                Button("Start Tracking") {
                    runtime.preferences.isPaused = false
                    runtime.preferences.hasConsent = true
                }.keyboardShortcut(.defaultAction)
                Button("Continue Without Tracking") {
                    runtime.preferences.isPaused = true
                    runtime.preferences.hasConsent = true
                }
            }
            Button("Import Previous History…") { runtime.importHistory(legacy: true, inMainWindow: true) }
                .help("Keeps the old default.store and its WAL unchanged. Close the old build first.")
        }
        .padding(40)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StorageFailureView: View {
    @Environment(AppRuntime.self) private var runtime
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle).accessibilityHidden(
                true)
            Text("History is unavailable").font(.title2)
            Text(runtime.storageError ?? "History could not be opened.")
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            Button("Retry Opening History") {
                runtime.load()
                runtime.start()
            }
        }
        .padding(30)
    }
}
