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
            // Centered over the waveform flank specifically (13pt trailing
            // padding + ~17.5pt-wide flank, see `PillPlayerView`), not the
            // whole pill -- a first attempt pinned it to the pill's very
            // top-trailing corner, which read as floating off on its own
            // rather than belonging to that flank.
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 19)
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
