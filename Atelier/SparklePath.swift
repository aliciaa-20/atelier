import AppKit

/// The four-point sparkle used for both the menu-bar glyph (`MenuBarIcon`)
/// and the app icon: four outer points (N/E/S/W) joined by cubic curves
/// whose control point is pulled toward the center by `pinch` (0-1; lower
/// pulls the sides in more, giving sharper points and a deeper concave
/// waist -- 0.35 is the app icon's look).
enum SparklePath {
    static func make(in rect: NSRect, pinch: Double) -> NSBezierPath {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let outer = [
            NSPoint(x: center.x, y: center.y + radius),
            NSPoint(x: center.x + radius, y: center.y),
            NSPoint(x: center.x, y: center.y - radius),
            NSPoint(x: center.x - radius, y: center.y),
        ]

        let path = NSBezierPath()
        path.move(to: outer[0])
        for i in 0..<4 {
            let p0 = outer[i]
            let p1 = outer[(i + 1) % 4]
            let mid = NSPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            let control = NSPoint(
                x: center.x + (mid.x - center.x) * pinch,
                y: center.y + (mid.y - center.y) * pinch
            )
            let cp1 = NSPoint(x: p0.x + (control.x - p0.x) * (2.0 / 3.0), y: p0.y + (control.y - p0.y) * (2.0 / 3.0))
            let cp2 = NSPoint(x: p1.x + (control.x - p1.x) * (2.0 / 3.0), y: p1.y + (control.y - p1.y) * (2.0 / 3.0))
            path.curve(to: p1, controlPoint1: cp1, controlPoint2: cp2)
        }
        path.close()
        return path
    }
}
