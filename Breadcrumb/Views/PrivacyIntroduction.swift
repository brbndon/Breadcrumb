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
                "Arc, Dia, and Helium integrations are off by default. Enable a browser in Settings to request Automation permission and record only website hosts. Full URLs and page titles are never stored."
            )
            Text(
                "Pause, exclude apps, export, or delete history in Settings. Pauses, exclusions, sleep, and console-session inactivity end the current tracking segment. Optional idle pausing uses aggregate time since input and coarse foreground-app display-sleep assertions to retain media time, never keys, mouse positions, input contents, or audio content. Actual screen-lock detection is unavailable. Estimated time is capped at five minutes per visit. History’s newest ongoing visit contributes zero to Estimated time until its duration is known. Dashboard Screen time includes it through the last refresh. Recorded visit duration is uncapped and can include unattended time."
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
