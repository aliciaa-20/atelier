import AppKit

/// The menu-bar glyph: a four-point sparkle, matching the app icon -- drawn in
/// code as a *template* image so macOS tints it for light and dark menu bars
/// and the selected state, like a hand-made asset would. Same `SparklePath`
/// construction the app icon uses at full size.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let path = SparklePath.make(in: rect.insetBy(dx: 1, dy: 1), pinch: 0.35)
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Atelier"
        return image
    }()
}
