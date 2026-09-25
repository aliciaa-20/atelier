import SwiftUI

extension View {
    /// Secondary text on the notch's black background. `opacity` defaults to
    /// 0.55 (~6:1 contrast, above WCAG AA's 4.5:1 -- white at 0.40-0.45 measured
    /// 3.7-4.4:1); with Increase Contrast on it lifts to 0.85.
    func dimmedText(_ opacity: Double = 0.55) -> some View {
        modifier(DimmedTextModifier(opacity: opacity))
    }
}

private struct DimmedTextModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let opacity: Double

    func body(content: Content) -> some View {
        content.foregroundStyle(.white.opacity(contrast == .increased ? max(opacity, 0.85) : opacity))
    }
}
