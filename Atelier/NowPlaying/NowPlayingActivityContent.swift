import SwiftUI

/// Wraps `NowPlayingInfo` as `LiveActivityContent` so the pill/peek
/// surfaces render it through the generic seam instead of being
/// hardcoded to now-playing. `id` is `"title|artist"` -- same dedup key
/// `NotchController` used to compute inline before this task; a change
/// here is what `LiveActivityCoordinator` treats as peek-worthy (see
/// Task 5). Pausing/resuming the *same* track does not change this id --
/// that's carried by the separate `hasContent` signal, not identity.
struct NowPlayingActivityContent: LiveActivityContent {
    let info: NowPlayingInfo
    let notchHeight: CGFloat
    let audioTap: AudioTap

    var id: String { "\(info.title)|\(info.artist)" }
    var isExpandable: Bool { true }

    func pillView() -> AnyView {
        AnyView(PillPlayerView(info: info, notchHeight: notchHeight, audioTap: audioTap))
    }

    func peekView() -> AnyView {
        AnyView(PeekPlayerView(info: info, notchHeight: notchHeight))
    }
}
