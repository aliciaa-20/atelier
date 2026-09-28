import SwiftUI

extension View {
    /// Secondary text on the notch's black background. `opacity` defaults to
    /// 0.55 (~6:1 contrast, above WCAG AA's 4.5:1 -- white at 0.40-0.45 measured
    /// 3.7-4.4:1); with Increase Contrast on it lifts to 0.85.
    ///
    /// In Liquid Glass mode (Phase 18) that "solid black background" premise
    /// is false -- the wallpaper shows through behind the text, at whatever
    /// brightness it happens to be, so a fixed opacity tuned for black alone
    /// isn't reliably legible. Glass mode both lifts the floor (like
    /// Increase Contrast does) and adds a soft dark shadow, since a shadow
    /// stays legible across arbitrary backgrounds in a way a flat opacity
    /// bump alone can't -- parked from the 2026-09-24 UI review.
    func dimmedText(_ opacity: Double = 0.55) -> some View {
        modifier(DimmedTextModifier(opacity: opacity))
    }

    /// The shadow half of `dimmedText(_:)`'s glass-mode treatment, for views
    /// that already set their own text color (`MarqueeText`'s `color:`
    /// parameter) and can't host a `ViewModifier` for the opacity half --
    /// pair with `DimmedText.opacity(_:contrast:glassActive:)` at those call
    /// sites for the same result `dimmedText(_:)` gives directly.
    func dimmedTextShadow(glassActive: Bool) -> some View {
        modifier(DimmedTextShadowModifier(glassActive: glassActive))
    }
}

/// Free functions so `MarqueeText` call sites (which take a plain `Color`,
/// not a `ViewModifier`) can compute the same glass-aware opacity
/// `DimmedTextModifier` uses internally, via `@Environment` values pulled at
/// the call site.
enum DimmedText {
    static func opacity(_ base: Double, contrast: ColorSchemeContrast, glassActive: Bool) -> Double {
        if contrast == .increased { return max(base, 0.85) }
        if glassActive { return max(base, 0.75) }
        return base
    }

    /// Whether glass mode is actually rendering right now, given
    /// `\.accessibilityReduceTransparency` read at the call site -- mirrors
    /// `NotchRootView.usesGlassBackground`'s own
    /// `AtelierSettings.glassEffectEnabled && !reduceTransparency` check.
    /// Safe to call unconditionally on the state-gated part: every call site
    /// using this (`ExpandedPlayerView`/`PeekPlayerView`/`IdleHomeView`) only
    /// ever renders during `.expanded`/`.peeking`, exactly the states glass
    /// can apply to.
    static func glassActive(reduceTransparency: Bool) -> Bool {
        AtelierSettings.glassEffectEnabled && !reduceTransparency
    }
}

private struct DimmedTextShadowModifier: ViewModifier {
    let glassActive: Bool

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(glassActive ? 0.35 : 0),
            radius: glassActive ? 1.5 : 0,
            y: glassActive ? 0.5 : 0
        )
    }
}

private struct DimmedTextModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let opacity: Double

    func body(content: Content) -> some View {
        let glassActive = DimmedText.glassActive(reduceTransparency: reduceTransparency)
        content
            .foregroundStyle(.white.opacity(DimmedText.opacity(opacity, contrast: contrast, glassActive: glassActive)))
            .dimmedTextShadow(glassActive: glassActive)
    }
}
