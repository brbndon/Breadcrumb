import AppKit
import Observation
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case disabled, enabled, requiresApproval, unavailable
    var description: String {
        switch self {
        case .disabled: "Off"
        case .enabled: "Enabled"
        case .requiresApproval: "Requires approval in System Settings"
        case .unavailable: "Unavailable — use a signed, installed copy of Breadcrumb"
        }
    }
}

@MainActor
protocol LoginItemServing: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
final class SystemLoginItemService: LoginItemServing {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// In-memory adapter for demos/tests; never touches ServiceManagement.
@MainActor
final class IsolatedLoginItemService: LoginItemServing {
    var status: LoginItemStatus = .disabled
    func register() throws { status = .enabled }
    func unregister() throws { status = .disabled }
    func openSettings() {}
}

@MainActor
@Observable
final class LoginItemController: NSObject {
    private(set) var status: LoginItemStatus = .disabled
    private(set) var errorMessage: String?
    private(set) var isChanging = false
    let isIsolated: Bool
    private let service: any LoginItemServing
    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    init(service: any LoginItemServing) {
        self.service = service
        isIsolated = service is IsolatedLoginItemService
        super.init()
        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc func refresh() { status = service.status }
    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        refresh()
        guard enabled != isRequested else { return }
        isChanging = true
        defer {
            isChanging = false
            refresh()
        }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            errorMessage = nil
        } catch {
            errorMessage =
                "Launch at login could not be changed. Check Login Items in System Settings, then retry."
        }
    }
    func openSettings() { service.openSettings() }
    func stop() { NotificationCenter.default.removeObserver(self) }
}

enum LaunchReason {
    @MainActor static func isLogin(event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
            event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
    static func shouldOpenWindow(login: Bool, hasConsent: Bool) -> Bool { !login || !hasConsent }
}
