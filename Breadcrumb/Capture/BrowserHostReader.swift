import AppKit
import Foundation

protocol BrowserHostReading: Sendable {
    func read(bundleID: String) async -> BrowserHostReader.Result
}

actor BrowserHostReader: BrowserHostReading {
    enum ScriptingFlavor: Sendable { case chromium, chromiumWithPrivateMode }
    struct Browser: Sendable {
        let name: String
        let flavor: ScriptingFlavor
    }
    static let browsers: [String: Browser] = [
        "company.thebrowser.Browser": Browser(name: "Arc", flavor: .chromium),
        "company.thebrowser.dia": Browser(name: "Dia", flavor: .chromium),
        "net.imput.helium": Browser(name: "Helium", flavor: .chromiumWithPrivateMode),
    ]
    static let supported = browsers.mapValues(\.name)

    enum Result: Sendable {
        case host(String)
        case privateWindow
        case noPage
        case unavailable
    }

    /// Window 1 matches the original Arc/Dia script; "front window" was not verified for them.
    static func script(bundleID: String, flavor: ScriptingFlavor) -> String {
        let privacyCheck =
            flavor == .chromiumWithPrivateMode
            ? "if mode of window 1 is \"incognito\" then return \"breadcrumb-private-window\"" : ""
        return """
            with timeout of 3 seconds
                tell application id "\(bundleID)"
                    if (count of windows) is 0 then return ""
                    \(privacyCheck)
                    return URL of active tab of window 1
                end tell
            end timeout
            """
    }

    /// Called only for an enabled, foreground browser. URL text is transient and never logged or stored.
    func read(bundleID: String) -> Result {
        guard let browser = Self.browsers[bundleID] else { return .unavailable }
        let source = Self.script(bundleID: bundleID, flavor: browser.flavor)
        guard let script = NSAppleScript(source: source) else { return .unavailable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            return number == -1728 ? .noPage : .unavailable
        }
        if result.stringValue == "breadcrumb-private-window" { return .privateWindow }
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
