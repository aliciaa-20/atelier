import AppKit
import SwiftUI

/// Reports vertical scroll-wheel/trackpad deltas that happen over its own
/// frame, without ever intercepting clicks (`hitTest` is nil, Invariant 4)
/// or consuming the event: the notch's gesture layer keeps seeing every
/// scroll too, which is why the root view turns swipe-to-close off while the
/// paused teleprompter owns vertical scrolling.
///
/// `onScroll` gets points with the sign AppKit uses: positive = content
/// should move down. Precise (trackpad) deltas pass through; a mouse wheel's
/// coarse "line" deltas are scaled up to points.
struct TeleprompterScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { removeMonitor() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            let dy = event.scrollingDeltaY
            // Vertical-dominant only, so a sideways swipe (tab/track change)
            // never nudges the script.
            guard abs(dy) > abs(event.scrollingDeltaX) else { return }
            onScroll?(event.hasPreciseScrollingDeltas ? dy : dy * 10)
        }
    }
}
