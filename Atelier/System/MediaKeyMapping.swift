import Foundation

/// A physical media key `MediaKeyInterceptor` cares about.
enum MediaKeyAction: Equatable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
}

/// Pure mapping from `NX_KEYTYPE_*` key codes (from the public
/// `IOKit/hidsystem/ev_keymap.h`, not the private-API side of this phase --
/// see the new ADR) to a `MediaKeyAction`, plus the fail-open suppression
/// decision. Extracted from `MediaKeyInterceptor` so both are unit-testable
/// without a real `CGEventTap`, matching how `NotchGestureInterpreter` pulls
/// its pure logic out of the AppKit-side `NotchGestureModifier`.
enum MediaKeyMapping {
    private static let soundUp: Int32 = 0
    private static let soundDown: Int32 = 1
    private static let brightnessUpCode: Int32 = 2
    private static let brightnessDownCode: Int32 = 3
    private static let muteCode: Int32 = 7

    static func action(forKeyCode keyCode: Int32) -> MediaKeyAction? {
        switch keyCode {
        case soundUp: .volumeUp
        case soundDown: .volumeDown
        case muteCode: .mute
        case brightnessUpCode: .brightnessUp
        case brightnessDownCode: .brightnessDown
        default: nil
        }
    }

    /// Whether the tap callback should return `nil` (swallow the event, so
    /// the stock HUD never sees it) for this action. Fail-open per the
    /// design spec's Decision #2: an action that couldn't actually be
    /// applied must let the event pass through so the real HUD still shows,
    /// rather than the key silently doing nothing.
    static func shouldSuppressEvent(for action: MediaKeyAction, applySucceeded: Bool) -> Bool {
        applySucceeded
    }
}
