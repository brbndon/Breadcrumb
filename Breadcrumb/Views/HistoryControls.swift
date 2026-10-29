import SwiftUI

struct HistoryControls: View {
    @Bindable var explorer: HistoryExplorer
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search names, bundle IDs, or hosts", text: $explorer.filter.text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search complete journey")
                .focused($searchFocused)
                .onChange(of: explorer.filter.text) { explorer.reloadJourney(debounce: true) }
            HStack {
                Picker("Visit kind", selection: $explorer.filter.kind) {
                    ForEach(HistoryKindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                    .onChange(of: explorer.filter.kind) { explorer.reloadJourney() }
                if explorer.filter.isActive {
                    Button("Clear filters") {
                        explorer.clearFilters()
                        searchFocused = true
                    }
                }
            }
            if let node = explorer.filter.nodeKey {
                Text("Selected: \(node)").font(.caption).textSelection(.enabled)
            }
        }.padding(12)
            .onChange(of: explorer.selectionRevision) { searchFocused = true }
    }
}

struct CustomDateControls: View {
    @Bindable var explorer: HistoryExplorer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("From", selection: $explorer.customStart, in: ...Date.now, displayedComponents: .date)
            DatePicker("Through", selection: $explorer.customEnd, in: ...Date.now, displayedComponents: .date)
                .help("The end calendar date is included. Today ends at the captured as-of time.")
            Button("Apply dates") { explorer.refresh() }
            if let error = explorer.periodError {
                Text(error).foregroundStyle(.secondary)
                Text("Showing the last valid period.").font(.caption)
            }
        }.padding(10)
    }
}
