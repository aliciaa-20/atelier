import AppKit

/// A borderless, non-activating panel pinned above the menu bar so it can
/// render over the notch without ever taking keyboard focus or showing up in
/// the Dock/Cmd-Tab switcher.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Documented in ADR 0003 as part of the combination that fixed
        // click handling (alongside canBecomeKey/acceptsFirstMouse below)
        // but never actually applied here -- caught 2026-09-28 while
        // investigating a real click-through-to-the-app-behind bug.
        // `isFloatingPanel` is what gives a panel priority event routing
        // over a regular window even when that window is key/frontmost,
        // independent of `level`; without it, a high `level` alone may
        // only guarantee rendering order, not reliable event dispatch.
        isFloatingPanel = true
        hidesOnDeactivate = false
        // .statusBar sits at the same level as the real menu bar, which
        // appears to claim mouseDown dispatch in that exact screen strip
        // even though hover tracking worked fine there — DynamicNotchKit
        // (.screenSaver) and Atoll (.mainMenu + 3) both sit higher for
        // their clickable notch content; matching Atoll's value here.
        level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
