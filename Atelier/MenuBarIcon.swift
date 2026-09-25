import AppKit

/// The menu-bar glyph: a laptop-screen outline with the notch filled in at the
/// top edge -- drawn in code as a *template* image so macOS tints it for light
/// and dark menu bars and the selected state, like a hand-made asset would.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let screen = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: 3, yRadius: 3
            )
            screen.lineWidth = 1.4
            screen.stroke()

            // The notch: a filled tab hanging from the top edge, bottom corners rounded.
            let notch = NSBezierPath(
                roundedRect: NSRect(x: rect.midX - 3.5, y: rect.maxY - 5.5, width: 7, height: 5.5),
                xRadius: 2, yRadius: 2
            )
            notch.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Atelier"
        return image
    }()
}
