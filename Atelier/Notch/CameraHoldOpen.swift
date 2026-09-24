import Foundation

/// Whether a hover-out should be ignored so the camera mirror stays up.
/// Pure and Foundation-only on purpose, like `NotchPageTransition`:
/// `NotchStateMachine` doesn't learn about the camera, and the decision
/// is testable without a camera. Only hover-out consults this; an
/// explicit swipe-close or tab change still closes/stops.
enum CameraHoldOpen {
    static func shouldSuppressRetract(
        holdOpenEnabled: Bool,
        mirrorLive: Bool,
        currentPage: NotchPage,
        state: NotchState
    ) -> Bool {
        holdOpenEnabled && mirrorLive && currentPage == .camera && state == .expanded
    }
}
