import Foundation
import IOKit.pwr_mgt
import Testing

@testable import Breadcrumb

@MainActor
struct MediaActivityTests {
    private func assertion(_ type: String) -> [String: Any] { [kIOPMAssertionTypeKey as String: type] }
    private func provider(
        pid: pid_t = 10, assertions: [NSNumber: [[String: Any]]]?
    ) -> PowerAssertionMediaProvider {
        PowerAssertionMediaProvider(
            frontmost: { ("browser.app", pid) }, assertions: { assertions })
    }

    @Test func onlyDisplaySleepAssertionTypesCountAsMedia() {
        let display = assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
        let noDisplay = assertion(kIOPMAssertionTypeNoDisplaySleep as String)
        let system = assertion(kIOPMAssertionTypePreventUserIdleSystemSleep as String)
        #expect(PowerAssertionMediaProvider.holdsDisplayAssertion([display]))
        #expect(PowerAssertionMediaProvider.holdsDisplayAssertion([system, noDisplay]))
        #expect(!PowerAssertionMediaProvider.holdsDisplayAssertion([system, [:]]))
        #expect(!PowerAssertionMediaProvider.holdsDisplayAssertion([]))
    }

    @Test func providerReadsOnlyTheForegroundProcess() {
        let display = assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
        #expect(
            provider(assertions: [NSNumber(value: 10): [display]]).activity()
                == MediaActivity(appIdentity: "browser.app", isPlaying: true))
        #expect(
            provider(assertions: [NSNumber(value: 11): [display]]).activity()
                == MediaActivity(appIdentity: "browser.app", isPlaying: false))
    }

    @Test func unavailableSignalsReturnNil() {
        #expect(provider(assertions: nil).activity() == nil)
        let noForeground = PowerAssertionMediaProvider(frontmost: { nil }, assertions: { [:] })
        #expect(noForeground.activity() == nil)
    }

    @Test func activitySnapshotSkipsMediaWhenDisabled() {
        struct Fake: MediaActivityProviding {
            func activity() -> MediaActivity? { MediaActivity(appIdentity: "x", isPlaying: true) }
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var system = SystemActivityProvider(mediaProvider: Fake(), mediaEnabled: { false })
        #expect(system.snapshot(at: date).media == nil)
        system.mediaEnabled = { true }
        #expect(system.snapshot(at: date).media?.isPlaying == true)
    }

    @Test func browserScriptsKeepWindowOneAndQueryPrivateModeOnlyForHelium() {
        let helium = BrowserHostReader.script(
            bundleID: "net.imput.helium", flavor: .chromiumWithPrivateMode)
        #expect(helium.contains("tell application id \"net.imput.helium\""))
        #expect(helium.contains("mode of window 1 is \"incognito\""))
        #expect(helium.contains("URL of active tab of window 1"))
        let arc = BrowserHostReader.script(bundleID: "company.thebrowser.Browser", flavor: .chromium)
        #expect(!arc.contains("mode of"))
        #expect(!arc.contains("front window"))
        #expect(arc.contains("URL of active tab of window 1"))
    }
}
