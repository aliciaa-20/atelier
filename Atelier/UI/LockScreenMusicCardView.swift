import SwiftUI

/// Atelier's own now-playing card for the lock screen (see the design
/// spec) -- collapsed by default (artwork + title/artist, with parallax),
/// expands on hover to a larger view with a real scrubber and transport
/// controls. Local `@State`, not `NotchStateMachine` -- this window is
/// entirely separate from the notch. Observes `NowPlayingCoordinator`
/// directly (not a snapshot `NowPlayingInfo`) so the card stays live for
/// as long as the window exists, the same way any other SwiftUI subtree
/// reacts to a `@Published` change.
///
/// One persistent view hierarchy for both states, sized by scalar
/// properties keyed on `isExpanded` -- matching Ebullioscopic/Atoll's own
/// `LockScreenMusicPanel` (`controlFrameSize`/`playPauseIconSize`/etc.).
/// An earlier version swapped between two separate `if isExpanded {}`
/// subtrees, which SwiftUI animates as a remove-then-insert rather than a
/// smooth resize -- keeping one tree and only animating its scalar
/// properties is what makes the hover morph read as continuous motion.
///
/// `cardCornerRadius` is a fixed constant, not interpolated between states
/// (an earlier version animated it 24->30) -- both Ebullioscopic/Atoll and
/// Clayton630/QuartzNotch's own lock-screen panels use one fixed
/// `panelCornerRadius` regardless of expand state. Animating it made the
/// panel's curve and the artwork's own (fixed-ratio) curve drift out of
/// sync mid-hover, which read as "the rounded corners don't match".
/// `artworkCornerRadius` stays proportional to `artworkSize` for the same
/// reason a container and its nested content should look concentric (see
/// the Liquid Glass shape system: parent radius minus padding for nested
/// shapes) rather than using an unrelated fixed value at each size step.
///
/// The card's background is a blurred, darkened copy of the track's own
/// artwork, not a flat tint or the system `.glassEffect()` -- that's what
/// iOS's own Lock Screen Now Playing widget and Control Center do, and
/// it's why they never look like a generic dark rounded rectangle: the
/// "glass" is built from the content, not a translucency effect sitting
/// on top of the wallpaper. Stacking the system glass material on top of a
/// custom blur would also be glass-on-glass, which Liquid Glass's own
/// design rules call out as incorrect.
struct LockScreenMusicCardView: View {
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    /// Shared with `NotchController`/the main notch panel via
    /// `LockScreenPanelController` -- not a second tap. See that
    /// controller's own `audioTap` doc comment for why.
    @ObservedObject var audioTap: AudioTap
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isExpanded = false
    /// Colors the waveform to match the artwork, same as `PillPlayerView`/
    /// `ExpandedPlayerView` -- a plain white waveform read flat against
    /// the artwork-derived background here.
    @StateObject private var artworkColor = ArtworkColorLoader()

    static let collapsedSize = CGSize(width: 280, height: 72)
    /// Noticeably shorter than an earlier 200pt pass -- Atoll and
    /// QuartzNotch both keep their expanded lock-screen card tight, with
    /// the artwork nearly filling the card's height and controls sitting
    /// close together, rather than spreading thin content across a tall,
    /// mostly-empty panel.
    static let expandedSize = CGSize(width: 300, height: 148)

    private static let hoverSpring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Fixed across both states -- see the type doc.
    private static let cardCornerRadius: CGFloat = 26

    private var artworkSize: CGFloat { isExpanded ? 60 : 40 }
    /// A steady ~0.28 ratio of `artworkSize` at both steps, not two
    /// unrelated fixed values -- keeps the artwork's own curve looking
    /// consistent as it scales, matching the concentric-shape idea above.
    private var artworkCornerRadius: CGFloat { artworkSize * 0.28 }
    private var titleFontSize: CGFloat { isExpanded ? 14 : 13 }
    private var artistFontSize: CGFloat { isExpanded ? 12 : 11 }
    private var headerSpacing: CGFloat { isExpanded ? 3 : 2 }
    private var cardSize: CGSize { isExpanded ? Self.expandedSize : Self.collapsedSize }
    /// Explicit, not measured -- see `MarqueeText`'s own doc comment on
    /// why its container width is always caller-supplied. Narrower when
    /// expanded because that state also reserves room for the waveform
    /// (see `content(for:)`'s trailing `HStack` member).
    private var marqueeWidth: CGFloat { isExpanded ? 130 : 160 }

    var body: some View {
        Group {
            if let info = nowPlaying.current {
                content(for: info)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.expandedSize.width, height: Self.expandedSize.height, alignment: .bottom)
        .onHover { hovering in
            withAnimation(Self.hoverSpring) {
                isExpanded = hovering
            }
        }
        .onAppear { artworkColor.load(from: nowPlaying.current?.artworkURL) }
        .onChange(of: nowPlaying.current?.artworkURL) { _, url in artworkColor.load(from: url) }
        // Swipe left/right to skip tracks, same pure `NotchGestureInterpreter`
        // + `NotchGestureModifier` pair the main notch panel uses -- both are
        // already generic over "whichever window this is attached to" (the
        // modifier reads its own view's screen rect, not the notch's), so
        // this window just needs its own capabilities: no open/close here,
        // this card has no expand-by-gesture state of its own (hover does
        // that already), only skip.
        .modifier(NotchGestureModifier(
            capabilities: NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: true),
            // Quicker than the notch panel's own 60pt/1.2x -- this card is a
            // much smaller, single-purpose target (skip only, no open/close
            // to disambiguate against), so it can afford to commit to a
            // swipe sooner without the notch's cross-axis-confusion risk.
            threshold: 32,
            dominanceMultiplier: 1.1,
            onOpen: {},
            onClose: {},
            onSkipForward: onNext,
            onSkipBackward: onPrevious
        ))
    }

    private func content(for info: NowPlayingInfo) -> some View {
        ZStack {
            BlurredArtworkBackground(url: info.artworkURL)
            GlassHighlightOverlay(cornerRadius: Self.cardCornerRadius)

            VStack(spacing: isExpanded ? 10 : 0) {
                HStack(spacing: 10) {
                    ArtworkView(url: info.artworkURL, cornerRadius: artworkCornerRadius)
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .parallax3D()
                    VStack(alignment: .leading, spacing: headerSpacing) {
                        // A light text shadow, new alongside the lighter
                        // overlay above -- with less darkening behind it,
                        // title/artist need their own small assist to
                        // stay legible over brighter album art, the same
                        // way iOS's own Lock Screen text sits on a
                        // shadow/gradient rather than raw content.
                        // `MarqueeText` (not a plain truncating `Text`,
                        // matching `ExpandedPlayerView`/`PeekPlayerView`)
                        // so a long title scrolls instead of clipping with
                        // "…" -- same `TimelineView`-driven, zero-cost-when-
                        // it-fits mechanism, see its own doc comment.
                        MarqueeText(text: info.title, font: .system(size: titleFontSize, weight: .semibold), color: .white, width: marqueeWidth, height: 16)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        MarqueeText(text: info.artist, font: .system(size: artistFontSize), color: .white.opacity(0.7), width: marqueeWidth, height: 14)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    }
                    Spacer(minLength: 0)

                    // Only in the expanded state -- the collapsed 72pt-tall
                    // card is already tight with just artwork+text (see
                    // the type doc's note on why it stays a fixed,
                    // non-interpolated corner radius/compact size), and
                    // ExpandedPlayerView/PillPlayerView both reserve the
                    // waveform its own breathing room rather than
                    // shoehorning it into an already-cramped row.
                    if isExpanded {
                        WaveformView(
                            isPlaying: info.isPlaying,
                            color: artworkColor.color,
                            height: artworkSize * 0.6,
                            levels: audioTap.isRunning ? audioTap.levels : nil
                        )
                    }
                }

                ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
                    .frame(height: isExpanded ? 18 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()

                transportRow(for: info)
                    .frame(height: isExpanded ? 26 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()
            }
            .padding(14)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        .overlay(
            // A gradient rim, not the previous flat `Color.white.opacity`
            // stroke -- brighter along the top-left edge, dimmer along
            // the bottom-right, so it reads as an edge actually catching
            // light rather than a uniform outline. Adapted from
            // cshariq/Sapphire's `LockScreenWidgetSurface.glassHighlightLayer`
            // (read via `gh api`), minus its private-API `NSGlassEffectView`
            // path -- this card's own doc comment already rejects stacking
            // system glass on top of the artwork blur, so only the public,
            // gradient-only half of Sapphire's technique applies here.
            // Rim brightened and thickened (0.34/0.08/0.18 @ 0.8pt ->
            // 0.5/0.1/0.24 @ 1pt) alongside the highlight boost above --
            // a subtle rim reads as a printed border, a brighter one
            // reads as an actual edge catching light.
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.24),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }

    /// A tight, centered cluster (Atoll/QuartzNotch's own transport rows),
    /// not the full-width `Spacer`-distributed row an earlier pass used --
    /// that spread the three buttons to the card's edges with a dead gap
    /// in the middle, which read as sparse rather than compact.
    private func transportRow(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 22) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel("Previous")
            Button(action: onPlayPause) {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(info.isPlaying ? "Pause" : "Play")
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// A specular sheen over the artwork blur -- a soft diagonal gradient plus
/// a brighter highlight pooled in the top-left corner, like light catching
/// a curved pane of glass. Adapted from cshariq/Sapphire's
/// `LockScreenWidgetSurface` (`glassHighlightLayer`, read via `gh api`),
/// which pairs this same highlight with an `NSGlassEffectView`-backed
/// material underneath; that private-API layer is deliberately dropped
/// here -- see `LockScreenMusicCardView`'s own doc comment on why a
/// second glass material stacked on the artwork blur would be glass-on-
/// glass, and [ADR 0013](../../docs/decisions/0013-lock-screen-card-gesture-and-glass.md)
/// for the full public-API-vs-private-API reasoning. Purely additive
/// color, `allowsHitTesting(false)`, sits above the artwork blur and below
/// the card's text/controls.
private struct GlassHighlightOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Boosted per direct feedback ("more glass-like") --
            // 0.10/0.02/0.05 -> 0.18/0.03/0.08 and the top-left pool
            // 0.14 -> 0.24 with a wider radius, so the sheen and the
            // corner highlight both read clearly instead of nearly
            // disappearing into the artwork blur underneath.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.24), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
            // A faint, opposite-corner dark pool -- real glass doesn't just
            // brighten where light hits, it darkens away from it. Without
            // this the sheen alone reads as a flat white wash rather than
            // a curved surface.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.16), .clear],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

/// A blurred, darkened, saturated copy of the artwork filling the card --
/// see the type doc for why this replaces a flat tint or system glass.
/// Shares `ArtworkImageCache` with `ArtworkView` so the two don't each run
/// their own fetch of the same URL.
private struct BlurredArtworkBackground: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Blur raised 36->44 and the darkening overlay
                        // below dropped 0.4->0.26 per direct feedback
                        // ("more liquid glass like, more transparent
                        // ish") -- more of the artwork's own color/light
                        // reads through, which is what makes glass read
                        // as glass rather than a dark tinted panel, while
                        // staying the same "glass built from content"
                        // technique the type doc documents (not a switch
                        // to system .glassEffect(), which would be
                        // glass-on-glass over the real wallpaper this
                        // window sits above). Saturation nudged 1.4->1.5
                        // alongside the `GlassHighlightOverlay` boost --
                        // together they push this past "blurred photo"
                        // toward "colored light diffusing through glass".
                        .blur(radius: 44)
                        .saturation(1.5)
                } else {
                    Color.black
                }
            }
            .overlay(Color.black.opacity(0.26))
        }
        .task(id: url) {
            image = nil
            guard let url,
                  let data = await ArtworkImageCache.shared.data(for: url),
                  let nsImage = NSImage(data: data) else { return }
            image = nsImage
        }
    }
}
