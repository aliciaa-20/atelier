import AppKit
import MetalKit

/// New file, not a port (per the design spec) -- covers only the built-in
/// display while the fold is visible. Non-key, non-main, click-through, and
/// sits just above the menu bar, same "never intercept input" posture as
/// `NotchPanel`. Window construction adapted from IuCC123/BendMac's
/// `AppModel.OverlayWindow` and the inline setup in `AppModel.connect()`
/// (MIT), consolidated here since Atelier's window-lifecycle conventions
/// differ enough from BendMac's own `AppModel` that adapting beats porting
/// line-for-line.
@MainActor
final class BendEffectOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    let metalView: MTKView

    init(screenFrame: CGRect, renderer: BendRenderer) {
        let view = renderer.makeView()
        view.layer?.isOpaque = false
        view.isPaused = true
        self.metalView = view
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Transparent until Metal has drawn: an undrawn frame then shows the
        // real desktop underneath, not black.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
        setFrame(screenFrame, display: true)
    }

    func show() {
        metalView.isPaused = false
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        metalView.isPaused = true
    }
}
