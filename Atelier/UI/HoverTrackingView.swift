import AppKit
import SwiftUI

/// SwiftUI's `.onHover` only fires while this app is the active/frontmost
/// app — confirmed against Apple's own documented `NSTrackingArea` behavior
/// and reported SwiftUI limitations, not assumed. That's never true for
/// Atelier: it's an `LSUIElement` accessory app, so some other app (Safari,
/// Xcode, Finder...) is always frontmost while our panel floats on top.
/// `NSTrackingArea` with `.activeAlways` tracks correctly regardless of which
/// app has focus, so hover detection goes through this instead.
struct HoverTrackingView: NSViewRepresentable {
    var onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }

    final class TrackingNSView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }
    }
}
