import AppKit
import Testing

@testable import Breadcrumb

@MainActor
private final class LoginStub: LoginItemServing {
    enum Failure: Error { case unavailable }
    var status: LoginItemStatus = .disabled
    var registrations = 0
    var unregistrations = 0
    var settingsOpened = 0
    var fails = false
    var needsApproval = false
    func register() throws {
        registrations += 1
        if fails { throw Failure.unavailable }
        status = needsApproval ? .requiresApproval : .enabled
    }
    func unregister() throws {
        unregistrations += 1
        if fails { throw Failure.unavailable }
        status = .disabled
    }
    func openSettings() { settingsOpened += 1 }
}

@MainActor
struct LoginItemTests {
    @Test func constructionAndRuntimeStartupNeverRegister() throws {
        let service = LoginStub()
        let controller = LoginItemController(service: service)
        let runtime = AppRuntime(
            preferences: TrackingPreferences(defaults: nil), login: controller, automaticCapture: false
        ) { try UsageStore.open(inMemory: true) }
        runtime.start()
        #expect(controller.status == .disabled)
        #expect(service.registrations == 0)
        #expect(service.unregistrations == 0)
        runtime.stop()
    }
    @Test func explicitRequestsReadBackRealStateAndAvoidDuplicateOperations() {
        let service = LoginStub()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        controller.setEnabled(true)
        #expect(service.registrations == 1)
        #expect(controller.status == .enabled)
        controller.setEnabled(false)
        controller.setEnabled(false)
        #expect(service.unregistrations == 1)
        #expect(controller.status == .disabled)
    }
    @Test func approvalIsDistinctAndRecoveryDoesNotRegisterAgain() {
        let service = LoginStub()
        service.needsApproval = true
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        #expect(controller.status == .requiresApproval)
        controller.setEnabled(true)
        controller.openSettings()
        #expect(service.registrations == 1)
        #expect(service.settingsOpened == 1)
    }
    @Test func operationsFailHonestlyAndCanBeRetried() {
        let service = LoginStub()
        let controller = LoginItemController(service: service)
        service.fails = true
        controller.setEnabled(true)
        #expect(controller.status == .disabled)
        #expect(controller.errorMessage != nil)
        service.fails = false
        controller.setEnabled(true)
        #expect(controller.errorMessage == nil)
        service.fails = true
        controller.setEnabled(false)
        #expect(controller.status == .enabled)
        #expect(controller.errorMessage != nil)
        service.fails = false
        controller.setEnabled(false)
        #expect(controller.status == .disabled)
    }
    @Test func externalStateRefreshCoversEveryStatusAndAppActivation() {
        let service = LoginStub()
        let controller = LoginItemController(service: service)
        for status in [LoginItemStatus.enabled, .requiresApproval, .unavailable, .disabled] {
            service.status = status
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            #expect(controller.status == status)
        }
        controller.stop()
    }
    @Test func loginLaunchReasonRequiresActualOpenApplicationEventKeyword() {
        let manual = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        #expect(!LaunchReason.isLogin(event: nil))
        #expect(!LaunchReason.isLogin(event: manual))
        manual.setParam(
            NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
            forKeyword: AEKeyword(keyAEPropData))
        #expect(LaunchReason.isLogin(event: manual))
        #expect(LaunchReason.shouldOpenWindow(login: false, hasConsent: true))
        #expect(!LaunchReason.shouldOpenWindow(login: true, hasConsent: true))
        #expect(LaunchReason.shouldOpenWindow(login: true, hasConsent: false))
    }
    @Test func isolatedRuntimeUsesFakeAndKeepsManualPause() throws {
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = true
        preferences.isPaused = true
        let runtime = AppRuntime(preferences: preferences, automaticCapture: false) {
            try UsageStore.open(inMemory: true)
        }
        #expect(runtime.login.isIsolated)
        runtime.start()
        #expect(runtime.preferences.isPaused)
        #expect(runtime.login.status == .disabled)
        runtime.stop()
    }
}

extension LoginItemTests {
    @Test func isolatedAppearanceDoesNotPersistBetweenRuntimes() throws {
        let first = AppRuntime(preferences: TrackingPreferences(defaults: nil), automaticCapture: false) {
            try UsageStore.open(inMemory: true)
        }
        first.appearance = .dark
        let second = AppRuntime(preferences: TrackingPreferences(defaults: nil), automaticCapture: false) {
            try UsageStore.open(inMemory: true)
        }
        #expect(second.appearance == .auto)
        first.stop()
        second.stop()
    }
}

@MainActor
private final class PolicyLog {
    var policies: [NSApplication.ActivationPolicy] = []
}

extension LoginItemTests {
    private func launched(login: Bool, consent: Bool, paused: Bool = false) -> (AppRuntime, PolicyLog) {
        let log = PolicyLog()
        let preferences = TrackingPreferences(defaults: nil)
        preferences.hasConsent = consent
        preferences.isPaused = paused
        let presence = AppPresence(defaults: nil) { log.policies.append($0) }
        presence.hideWhenNoWindows = true
        log.policies.removeAll()
        let runtime = AppRuntime(
            preferences: preferences, presence: presence, login: LoginItemController(service: LoginStub()),
            automaticCapture: false
        ) { try UsageStore.open(inMemory: true) }
        runtime.finishLaunch(login: login)
        return (runtime, log)
    }

    @Test func manualLaunchRequestsWindowAndLeavesDockPolicyToWindowEvents() {
        let (runtime, log) = launched(login: false, consent: true)
        #expect(runtime.requestInitialWindow)
        #expect(log.policies.isEmpty)
    }

    @Test func loginLaunchWithConsentStaysQuietAndAppliesDockHiding() {
        let (runtime, log) = launched(login: true, consent: true, paused: true)
        #expect(!runtime.requestInitialWindow)
        #expect(log.policies == [.accessory])
        #expect(runtime.preferences.isPaused)
        #expect(runtime.preferences.hasConsent)
    }

    @Test func loginLaunchWithoutConsentStillExposesPrivacySetup() {
        let (runtime, log) = launched(login: true, consent: false)
        #expect(runtime.requestInitialWindow)
        #expect(log.policies.isEmpty)
        #expect(!runtime.preferences.hasConsent)
    }
}
