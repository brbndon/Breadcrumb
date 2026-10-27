import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppearanceSetting.auto
    @Environment(AppRuntime.self) private var runtime
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var preferences = runtime.preferences
        @Bindable var presence = runtime.presence
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)

            Section("Dock & App Switcher") {
                Toggle("Hide from Dock when no windows are open", isOn: $presence.hideWhenNoWindows)
                Text(
                    "Breadcrumb stays in the menu bar. Opening Breadcrumb or Settings restores it to the Dock and Command-Tab. Minimized windows count as open."
                )
                .foregroundStyle(.secondary)
            }

            Section("Tracking") {
                Toggle("Pause tracking", isOn: $preferences.isPaused)
                    .disabled(!preferences.hasConsent || runtime.tracker == nil)
                if !preferences.hasConsent {
                    Text("Open Breadcrumb to complete privacy setup before tracking.")
                }
                if let message = runtime.tracker?.errorMessage {
                    Text(message)
                    Button("Retry Saving History") { runtime.tracker?.retry() }
                }
            }

            Section("Excluded apps") {
                Text("Excluded apps and their browser hosts are not recorded. Existing history is kept.")
                    .foregroundStyle(.secondary)
                ForEach(preferences.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(id).textSelection(.enabled)
                        Spacer()
                        Button("Remove") { preferences.excludedBundleIDs.removeAll { $0 == id } }
                            .accessibilityLabel("Remove exclusion for \(id)")
                    }
                }
                Button("Exclude an App…") { chooseExcludedApp() }
            }

            Section("Browser hosts — optional") {
                Text(
                    "Only hosts are kept, such as example.com. Enabling a browser requests macOS Automation access when that browser is foreground. Full URLs and titles are never saved."
                )
                .foregroundStyle(.secondary)
                ForEach(BrowserHostReader.supported.keys.sorted(), id: \.self) { id in
                    BrowserToggle(bundleID: id, preferences: preferences)
                        .disabled(!preferences.hasConsent)
                }
                if let message = runtime.tracker?.browserMessage { Text(message).foregroundStyle(.secondary) }
            }

            Section("Your history") {
                Text(
                    "Data stays in this app’s Application Support folder. No browsing data or app names are logged."
                )
                .foregroundStyle(.secondary)
                if let location = runtime.store?.location {
                    Button("Show History Folder") {
                        NSWorkspace.shared.selectFile(location.path, inFileViewerRootedAtPath: "")
                    }
                }
                Button("Export History…") { runtime.exportHistory() }.disabled(runtime.store == nil)
                Button("Import History…") { runtime.importHistory() }.disabled(runtime.store == nil)
                Button("Import Previous History…") { runtime.importHistory(legacy: true) }.disabled(
                    runtime.store == nil)
                Button("Delete All History…", role: .destructive) { confirmingDelete = true }
                    .disabled(runtime.store == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 640)
        .confirmationDialog("Delete all recorded history?", isPresented: $confirmingDelete) {
            Button("Delete All", role: .destructive) {
                if runtime.tracker?.deleteHistory() == true { runtime.notify("History deleted.") }
            }
        } message: {
            Text(
                "This cannot be undone. Exported files and earlier stores are kept. New visits are recorded while tracking is enabled."
            )
        }
        .alert(
            "Breadcrumb",
            isPresented: Binding(
                get: { !runtime.messageBelongsToMainWindow && runtime.operationMessage != nil },
                set: { if !$0 { runtime.operationMessage = nil } }
            )
        ) {
            Button("OK") { runtime.operationMessage = nil }
        } message: {
            Text(runtime.operationMessage ?? "")
        }
    }

    private func chooseExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            runtime.notify("This application has no bundle identifier and cannot be excluded.")
            return
        }
        runtime.preferences.exclude(id)
    }
}

private struct BrowserToggle: View {
    let bundleID: String
    @Bindable var preferences: TrackingPreferences
    var body: some View {
        Toggle(
            BrowserHostReader.supported[bundleID] ?? bundleID,
            isOn: Binding(
                get: { preferences.enabledBrowserIDs.contains(bundleID) },
                set: { preferences.setBrowser(bundleID, enabled: $0) }))
    }
}
