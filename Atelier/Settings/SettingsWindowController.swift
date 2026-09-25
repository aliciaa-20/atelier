import AppKit
import SwiftUI

/// Owns the Settings window. A plain `NSWindow` rather than SwiftUI's
/// `Settings` scene: that scene is unreliable to open and focus from an
/// `LSUIElement` app. The activation-policy flip mirrors what
/// boring.notch and Atoll do -- an accessory app's window won't come to
/// the front or take keyboard focus otherwise.
///
/// The window is created lazily and dropped on close, so nothing of it
/// (hosting view, SwiftUI state) stays in memory while Settings is shut.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// `pane` opens (or switches an already-open window to) that pane.
    func show(pane: SettingsPane? = nil) {
        // A Dock icon appears while Settings is open; it goes away on close.
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            window = makeWindow(initialPane: pane ?? .general)
            window?.center()
        } else if let pane {
            NotificationCenter.default.post(name: .atelierSelectSettingsPane, object: pane)
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(initialPane: SettingsPane) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Atelier Settings"
        // ARC, not AppKit, owns this window's lifetime (see `windowWillClose`).
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(initialPane: initialPane))
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.delegate = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
