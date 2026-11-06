import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var explorer: HistoryExplorer?
    @State private var dashboard: DashboardModel?
    @State private var showsHistory = false
    private let refresh = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let tracker = runtime.tracker, let message = tracker.errorMessage {
                HStack {
                    Text(message)
                    Button("Retry") { tracker.retry() }
                }.padding(12)
            }
            if let message = runtime.tracker?.activityMessage, runtime.preferences.hasConsent {
                HStack {
                    Text(message)
                    Button("Retry Activity Check") { runtime.activityMonitor.sample() }
                }.padding(12)
            }
            if !runtime.preferences.hasConsent {
                PrivacyIntroduction()
            } else {
                if let explorer {
                    if showsHistory {
                        ExplorerContent(explorer: explorer)
                    } else if let dashboard {
                        DashboardView(model: dashboard) { row, kind in
                            dashboard.configureHistory(explorer)
                            explorer.select(
                                RankedItem(
                                    key: row.id, name: row.name, bundleID: row.bundleID, visits: 0,
                                    total: row.seconds), kind: kind, screenTime: true)
                            showsHistory = true
                        }
                    }
                } else {
                    ProgressView("Loading history")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(.body, design: .monospaced))
        .background(PaperCanvas())
        .tint(BreadcrumbPalette.rose)
        .toolbar {
            if runtime.preferences.hasConsent {
                ToolbarItem {
                    Picker("Screen", selection: $showsHistory) {
                        Text("Dashboard").tag(false)
                        Text("History").tag(true)
                    }.pickerStyle(.segmented)
                }
            }
        }
        .task(id: runtime.store.map(ObjectIdentifier.init)) {
            explorer?.stop()
            dashboard?.stop()
            if let store = runtime.store {
                let owner = HistoryExplorer(store: store)
                explorer = owner
                dashboard = DashboardModel(store: store)
                dashboard?.storeChanged(revision: store.revision)
                owner.storeChanged(revision: store.revision)
            }
        }
        .onChange(of: runtime.store?.revision) {
            explorer?.storeChanged(revision: runtime.store?.revision ?? 0)
            dashboard?.storeChanged(revision: runtime.store?.revision ?? 0)
        }
        .onReceive(refresh) {
            explorer?.dayChanged(now: $0)
            dashboard?.dayChanged(now: $0)
        }
        .onDisappear {
            explorer?.stop()
            dashboard?.stop()
        }
        .alert(
            "Breadcrumb",
            isPresented: Binding(
                get: { runtime.messageBelongsToMainWindow && runtime.operationMessage != nil },
                set: { if !$0 { runtime.operationMessage = nil } }
            )
        ) {
            Button("OK") { runtime.operationMessage = nil }
        } message: {
            Text(runtime.operationMessage ?? "")
        }
    }
}

private struct ExplorerContent: View {
    @Bindable var explorer: HistoryExplorer

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                RangeSidebar(selection: $explorer.range)
                if explorer.range == .custom { CustomDateControls(explorer: explorer) }
                Button("Refresh history", systemImage: "arrow.clockwise") { explorer.refresh() }
                    .padding(10)
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
            .onChange(of: explorer.range) { explorer.refresh() }
            VStack(spacing: 0) {
                HistoryControls(explorer: explorer)
                Divider()
                JourneyView(explorer: explorer)
            }.frame(minWidth: 380, idealWidth: 550, maxHeight: .infinity)
            Group {
                if explorer.isReporting && !explorer.keepsReportVisible {
                    ProgressView("Building report").padding()
                } else if let error = explorer.reportError {
                    VStack {
                        Text(error)
                        Button("Retry Report") { explorer.updateReports() }
                    }.padding()
                } else {
                    ReportView(explorer: explorer)
                        .opacity(explorer.isReporting ? 0.6 : 1)
                        .overlay(alignment: .topTrailing) {
                            if explorer.isReporting { ProgressView().controlSize(.small).padding(8) }
                        }
                }
            }.frame(minWidth: 300, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
