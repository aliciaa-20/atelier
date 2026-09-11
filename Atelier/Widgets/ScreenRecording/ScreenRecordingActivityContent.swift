import SwiftUI

struct ScreenRecordingActivityContent: LiveActivityContent {
    /// Same reasoning as `BatteryActivityContent.notchHeight`: peek content
    /// starts below the physical notch cutout, which has no display pixels.
    let notchHeight: CGFloat

    let id = "screenRecording:active"

    /// Pill-only, like Battery -- confirmed on-device that popping a peek
    /// for this reads as an unwanted interruption, not a wanted alert.
    var peeksOnChange: Bool { false }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
            }
            .padding(.trailing, 18)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text("Screen Recording")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
