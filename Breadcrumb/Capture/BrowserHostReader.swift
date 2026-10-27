import AppKit
import Foundation

protocol BrowserHostReading: Sendable {
    func read(bundleID: String) async -> BrowserHostReader.Result
}

actor BrowserHostReader: BrowserHostReading {
    static let supported = ["company.thebrowser.Browser": "Arc", "company.thebrowser.dia": "Dia"]

    enum Result: Sendable {
        case host(String)
        case noPage
        case unavailable
    }

    /// Called only for an enabled, foreground browser. URL text is transient and never logged or stored.
    func read(bundleID: String) -> Result {
        guard Self.supported[bundleID] != nil else { return .unavailable }
        let source = """
            with timeout of 3 seconds
                tell application id "\(bundleID)"
                    if (count of windows) is 0 then return ""
                    return URL of active tab of window 1
                end tell
            end timeout
            """
        guard let script = NSAppleScript(source: source) else { return .unavailable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            return number == -1728 ? .noPage : .unavailable
        }
        guard let value = result.stringValue, let host = Self.host(from: value) else { return .noPage }
        return .host(host)
    }

    nonisolated static func host(from value: String) -> String? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host?.lowercased(), !host.isEmpty,
            host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }
}
