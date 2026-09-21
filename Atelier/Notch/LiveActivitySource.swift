import Combine
import SwiftUI

/// One producer of notch content — now-playing, battery, AirPods, etc.
/// Mirrors `NowPlayingSource`'s seam: a new source is one new file
/// conforming here, registered once in `NotchController`, nothing else
/// touched. `nil` from `contentPublisher` means "nothing to show right
/// now," not "remove this source" -- it's how a source opts in/out of the
/// stack as its own state changes (e.g. battery no longer low).
///
/// Shape adapted from jackson-storm/dynamicnotch's `NotchContentProtocol`
/// + `NotchEngine`, read via `gh api` before designing (see
/// check-reference-apps-first) -- simplified to a priority list without
/// its queueing engine or temporary-notification distinction, neither of
/// which anything here needs yet.
protocol LiveActivitySource {
    /// Stable per source (e.g. "nowPlaying", "battery"), used as the
    /// `LiveActivityStack` entry id -- NOT the same as
    /// `LiveActivityContent.id`, which identifies a specific piece of
    /// content (a track, a battery state) and changes far more often.
    var id: String { get }
    var priority: Int { get }
    /// May emit from any thread/actor -- `LiveActivityCoordinator` applies
    /// `.receive(on: RunLoop.main)` itself, so implementations don't need
    /// to guarantee main-thread delivery on their own.
    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> { get }
    /// A badge source never competes for `topContent` -- its `priority` is
    /// ignored, it's composited as a small overlay on top of whatever the
    /// pill is already showing instead of replacing it, and it can't block
    /// hover-expand or the skip gesture (both gate on `topContent`, which a
    /// badge source never becomes). For a source that's genuinely just an
    /// indicator (e.g. a screen-recording dot), not a competing surface.
    var isBadge: Bool { get }
}

extension LiveActivitySource {
    var isBadge: Bool { false }
}

/// What a `LiveActivitySource` currently wants shown. UI-layer (may
/// import SwiftUI), unlike `LiveActivitySource` and `LiveActivityStack`.
protocol LiveActivityContent {
    /// Identifies *this specific piece of content* -- e.g. `"title|artist"`
    /// for a track, `"battery:low"` for a battery state. Two consecutive
    /// values with different ids is what makes `LiveActivityCoordinator`
    /// treat a change as peek-worthy.
    var id: String { get }
    /// Whether hovering while this content is on top should open a full
    /// interactive `.expanded` view. Only now-playing needs this --
    /// everything else defaults to pill/peek only, matching
    /// `NotchContentProtocol.isExpandable` defaulting to `false` in the
    /// dynamicnotch reference.
    var isExpandable: Bool { get }
    /// Whether this content arriving/becoming top should auto-pop the
    /// `.peeking` view. `false` for ambient state like Battery, which
    /// should only ever show as the small pill icon -- surfacing a full
    /// peek every time the charger state changes reads as noisy, not
    /// informative, on-device (confirmed by the user directly).
    var peeksOnChange: Bool { get }
    @ViewBuilder func pillView() -> AnyView
    @ViewBuilder func peekView() -> AnyView
}

extension LiveActivityContent {
    var isExpandable: Bool { false }
    var peeksOnChange: Bool { true }
}
