import SwiftUI

/// Whether the notch body is currently rendering as Liquid Glass rather than
/// flat black -- set once by `NotchRootView` from its own
/// `usesGlassBackground`, read wherever `dimmedText()` is used across every
/// page. A plain black background is opaque and behind every glyph equally,
/// so secondary text's fixed opacity always contrasts the same way; glass is
/// a live material whose luminosity depends on what's behind the *window*
/// (menu bar, desktop), which can wash out low-opacity text -- see the
/// 2026-09-24 UI review's parked finding.
private struct GlassBackgroundActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glassBackgroundActive: Bool {
        get { self[GlassBackgroundActiveKey.self] }
        set { self[GlassBackgroundActiveKey.self] = newValue }
    }
}

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
    @Environment(\.glassBackgroundActive) private var glassBackgroundActive
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white.opacity(contrast == .increased ? max(opacity, 0.85) : opacity))
            // A flat opacity reads consistently against solid black, but
            // glass's own luminosity shifts with whatever's behind the
            // window -- a soft dark shadow (Apple's own "adaptive shadows
            // flip small elements light/dark for legibility over any
            // content" pattern) keeps it readable without just cranking
            // opacity up and losing the "secondary" hierarchy everywhere,
            // including on plain black.
            .shadow(color: .black.opacity(glassBackgroundActive ? 0.5 : 0), radius: glassBackgroundActive ? 1.5 : 0)
    }
}
