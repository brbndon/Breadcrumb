import AppKit
import CoreGraphics

enum SessionActivity: Equatable, Sendable {
    case active, inactive, locked, unknown
}

struct ActivitySnapshot: Equatable, Sendable {
    let timestamp: Date
    let idleSeconds: TimeInterval?
    let session: SessionActivity
}

@MainActor
protocol ActivityProviding {
    func snapshot(at date: Date) -> ActivitySnapshot
}

/// Public APIs establish console activity, not screen-lock state. The lock key
/// sometimes found in this dictionary is undocumented and deliberately unused.
@MainActor
struct SystemActivityProvider: ActivityProviding {
    func snapshot(at date: Date) -> ActivitySnapshot {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        let session: SessionActivity
        if let console = dictionary?[kCGSessionOnConsoleKey as String] as? Bool,
            let loggedIn = dictionary?[kCGSessionLoginDoneKey as String] as? Bool
        {
            session = console && loggedIn ? .active : .inactive
        } else {
            session = .unknown
        }
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return ActivitySnapshot(
            timestamp: date, idleSeconds: idle.isFinite && idle >= 0 ? idle : nil, session: session)
    }
}

@MainActor
struct IsolatedActivityProvider: ActivityProviding {
    func snapshot(at date: Date) -> ActivitySnapshot {
        ActivitySnapshot(timestamp: date, idleSeconds: 0, session: .active)
    }
}

@MainActor
protocol ActivityScheduling: AnyObject {
    func start(_ callback: @escaping @MainActor (SessionActivity?) -> Void)
    func stop()
}

@MainActor
final class SystemActivityScheduler: NSObject, ActivityScheduling {
    private var callback: (@MainActor (SessionActivity?) -> Void)?
    private var task: Task<Void, Never>?
    func start(_ callback: @escaping @MainActor (SessionActivity?) -> Void) {
        stop()
        self.callback = callback
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(inactive), name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(active), name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil)
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.callback?(nil)
            }
        }
    }
    @objc private func inactive() { callback?(.inactive) }
    @objc private func active() { callback?(.active) }
    func stop() {
        task?.cancel()
        task = nil
        callback = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

@MainActor
final class ActivityMonitor {
    var onSample: (@MainActor (ActivitySnapshot) -> Void)?
    private let provider: any ActivityProviding
    private let scheduler: any ActivityScheduling
    private let clock: () -> Date
    private(set) var isRunning = false
    private var inactiveSession = false

    init(
        provider: any ActivityProviding, scheduler: any ActivityScheduling = SystemActivityScheduler(),
        clock: @escaping () -> Date = { .now }
    ) {
        self.provider = provider
        self.scheduler = scheduler
        self.clock = clock
    }
    func start() {
        guard !isRunning else { return }
        isRunning = true
        sample()
        scheduler.start { [weak self] state in
            guard let self, self.isRunning else { return }
            if let state { self.inactiveSession = state == .inactive }
            self.sample()
        }
    }
    func sample() {
        guard isRunning else { return }
        let snapshot = provider.snapshot(at: clock())
        onSample?(
            ActivitySnapshot(
                timestamp: snapshot.timestamp, idleSeconds: snapshot.idleSeconds,
                session: inactiveSession ? .inactive : snapshot.session))
    }
    func stop() {
        guard isRunning else { return }
        isRunning = false
        scheduler.stop()
        inactiveSession = false
    }
}
