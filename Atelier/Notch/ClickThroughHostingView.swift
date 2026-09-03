import AppKit
import SwiftUI

/// AppKit's default `acceptsFirstMouse` is `false`: a click on a control in
/// a window that isn't key first activates/focuses the window and is
/// consumed doing that, rather than reaching the control. Overriding it to
/// `true` lets the expanded player's buttons and scrubber respond on the
/// very first click, regardless of whether the panel was already key. See
/// `docs/decisions/0003-notch-panel-can-become-key.md`.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
