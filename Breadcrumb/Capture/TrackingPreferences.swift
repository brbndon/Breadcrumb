import Foundation
import Observation

@MainActor
@Observable
final class TrackingPreferences {
    var hasConsent: Bool {
        didSet {
            defaults?.set(hasConsent, forKey: "privacyExplained")
            onChange?()
        }
    }
    var isPaused: Bool {
        didSet {
            defaults?.set(isPaused, forKey: "trackingPaused")
            onChange?()
        }
    }
    var excludedBundleIDs: [String] {
        didSet {
            defaults?.set(excludedBundleIDs, forKey: "excludedBundleIDs")
            onChange?()
        }
    }
    var enabledBrowserIDs: [String] {
        didSet {
            defaults?.set(enabledBrowserIDs, forKey: "enabledBrowserIDs")
            onChange?()
        }
    }
    @ObservationIgnored var onChange: (() -> Void)?
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        hasConsent = defaults?.bool(forKey: "privacyExplained") ?? false
        isPaused = defaults?.bool(forKey: "trackingPaused") ?? false
        excludedBundleIDs = defaults?.stringArray(forKey: "excludedBundleIDs") ?? []
        enabledBrowserIDs = defaults?.stringArray(forKey: "enabledBrowserIDs") ?? []
    }

    func exclude(_ bundleID: String) {
        if !excludedBundleIDs.contains(bundleID) {
            excludedBundleIDs = (excludedBundleIDs + [bundleID]).sorted()
        }
    }

    func setBrowser(_ bundleID: String, enabled: Bool) {
        enabledBrowserIDs =
            enabled
            ? Array(Set(enabledBrowserIDs + [bundleID])).sorted()
            : enabledBrowserIDs.filter { $0 != bundleID }
    }
}
