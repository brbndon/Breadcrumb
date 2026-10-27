import AppKit
import SwiftUI

// Register only our scene windows; menu bar popovers and transient panels must not keep the Dock icon.
struct AppPresenceWindow: NSViewRepresentable {
    let presence: AppPresence

    func makeNSView(context: Context) -> WindowView {
        WindowView(presence: presence)
    }

    func updateNSView(_ nsView: WindowView, context: Context) {}

    final class WindowView: NSView {
        let presence: AppPresence

        init(presence: AppPresence) {
            self.presence = presence
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { presence.register(window) }
        }
    }
}
