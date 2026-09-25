import Foundation

/// Whether a hover-out should be ignored so the script keeps scrolling.
/// Pure and Foundation-only like `CameraHoldOpen`: `NotchStateMachine`
/// doesn't learn about the teleprompter. Only hover-out consults this; an
/// explicit swipe-close or tab change still closes and pauses. Unlike the
/// camera there is no setting: retracting mid-read is never wanted.
enum TeleprompterHoldOpen {
    static func shouldSuppressRetract(
        isPlaying: Bool,
        currentPage: NotchPage,
        state: NotchState
    ) -> Bool {
        isPlaying && currentPage == .teleprompter && state == .expanded
    }
}
