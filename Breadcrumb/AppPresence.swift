import AppKit
import Observation

@MainActor
@Observable
final class AppPresence: NSObject {
    var hideWhenNoWindows: Bool {
        didSet {
            defaults?.set(hideWhenNoWindows, forKey: "hideWhenNoWindows")
            updatePolicy()
        }
    }

    private let defaults: UserDefaults?
    private let applyPolicy: (NSApplication.ActivationPolicy) -> Void
    @ObservationIgnored private let windows = NSHashTable<NSWindow>.weakObjects()
    @ObservationIgnored private var openWindows: Set<ObjectIdentifier> = []

    init(
        defaults: UserDefaults? = .standard,
        applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { policy in
            guard NSApp.activationPolicy() != policy else { return }
            NSApp.setActivationPolicy(policy)
        }
    ) {
        self.defaults = defaults
        self.applyPolicy = applyPolicy
        hideWhenNoWindows = defaults?.bool(forKey: "hideWhenNoWindows") ?? false
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(windowOpened(_:)), name: NSWindow.didBecomeKeyNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification,
            object: nil)
    }

    /// Applies the Dock policy without a window event, e.g. after a launch that opens no window.
    func refreshPolicy() { updatePolicy() }

    func register(_ window: NSWindow) {
        windows.add(window)
        openWindows.insert(ObjectIdentifier(window))
        updatePolicy()
    }

    @objc private func windowOpened(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, windows.contains(window) else { return }
        openWindows.insert(ObjectIdentifier(window))
        updatePolicy()
    }

    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        openWindows.remove(ObjectIdentifier(window))
        updatePolicy()
    }

    private func updatePolicy() {
        openWindows.formIntersection(windows.allObjects.map(ObjectIdentifier.init))
        applyPolicy(hideWhenNoWindows && openWindows.isEmpty ? .accessory : .regular)
    }
}
