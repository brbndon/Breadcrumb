import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppearanceSetting.auto
    @Environment(FrontmostAppTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var tracker = tracker
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Pause tracking", isOn: $tracker.isPaused)

            Section {
                Text("Breadcrumb records which app is in front and when. Data stays on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Delete All History…", role: .destructive) { confirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 300)
        .confirmationDialog("Delete all recorded history?", isPresented: $confirmingDelete) {
            Button("Delete All", role: .destructive) {
                try? context.delete(model: UsageEvent.self)
                try? context.save()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}
