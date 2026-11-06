import AppKit
import IOKit.pwr_mgt

struct MediaActivity: Equatable, Sendable {
    let appIdentity: String
    let isPlaying: Bool
}

@MainActor
protocol MediaActivityProviding {
    func activity() -> MediaActivity?
}

/// Reads only coarse assertion types for the foreground process, never assertion names or content.
@MainActor
struct PowerAssertionMediaProvider: MediaActivityProviding {
    var frontmost: @MainActor () -> (identity: String, pid: pid_t)? = {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let identity = app.bundleIdentifier ?? app.localizedName
        else { return nil }
        return (identity, app.processIdentifier)
    }
    var assertions: @MainActor () -> [NSNumber: [[String: Any]]]? = {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess else { return nil }
        return result?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    }

    func activity() -> MediaActivity? {
        guard let app = frontmost(), let all = assertions() else { return nil }
        return MediaActivity(
            appIdentity: app.identity,
            isPlaying: Self.holdsDisplayAssertion(all[NSNumber(value: app.pid)] ?? []))
    }

    static func holdsDisplayAssertion(_ items: [[String: Any]]) -> Bool {
        items.contains {
            let type = $0[kIOPMAssertionTypeKey] as? String
            return type == kIOPMAssertionTypePreventUserIdleDisplaySleep
                || type == kIOPMAssertionTypeNoDisplaySleep
        }
    }
}
