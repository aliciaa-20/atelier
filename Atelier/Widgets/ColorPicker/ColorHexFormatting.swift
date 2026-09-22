import Foundation

/// Pure RGB-to-hex formatting, deliberately split out from
/// `ColorPickerSource`/`ColorPickerActivityContent` (both AppKit/SwiftUI)
/// so this piece stays unit-testable without a real `NSColor`/color space
/// conversion -- same "pure logic gets the test suite" split as
/// `SpotifyOutputParser` vs. the AppleScript call itself.
enum ColorHexFormatting {
    /// `red`/`green`/`blue` are expected in the 0...1 range (as
    /// `NSColor`'s own component accessors return); values outside that
    /// range are clamped rather than producing an out-of-gamut string.
    static func hexString(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }

    private static func component(_ value: Double) -> Int {
        Int((value.clamped(to: 0...1) * 255).rounded())
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
