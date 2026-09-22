import AppKit
import Combine

/// Wraps `NSColorSampler`, macOS's built-in eyedropper -- public API, no
/// entitlement or TCC grant needed, so unlike `ScreenRecordingSource`'s
/// private CGS symbols this is fully sanctioned. Triggered from the menu
/// bar (`AtelierApp`'s "Pick a Color..." item -> `NotchController.pickColor()`
/// -> here), not polled or event-driven like the other widgets -- a picked
/// color is a one-shot user action, not ambient state.
@MainActor
final class ColorPickerSource: LiveActivitySource {
    let id = "colorPicker"
    let priority = NotchLiveActivityPriority.colorPicker

    /// Matches `VolumeSource`/`BrightnessSource`'s own `decayDuration`
    /// exactly, for the same on-device-confirmed reason documented on
    /// theirs: a shorter, independent timer clears the content before
    /// `NotchController`'s own peek-close timer retracts the panel, which
    /// reads as a glitchy close with stale/blank content sitting visible.
    private static let decayDuration = NotchController.peekDuration

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private var decayTask: Task<Void, Never>?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
    }

    /// Shows the system eyedropper and publishes the result as a peek.
    /// `NSColorSampler.show`'s completion is documented to run on the main
    /// queue; this type is `@MainActor` regardless, matching every other
    /// source.
    func pick() {
        NSColorSampler().show { [weak self] color in
            guard let self, let color else { return }
            self.publish(color)
        }
    }

    private func publish(_ color: NSColor) {
        // Not every color space exposes red/green/blue components directly
        // (e.g. a picked grayscale/pattern color) -- converting to sRGB
        // first matches how the swatch itself will actually render.
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let hex = ColorHexFormatting.hexString(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)

        // Copying to the clipboard is the whole point of picking a color
        // outside the app -- without it, the peek is just a pretty dead end.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)

        subject.send(ColorPickerActivityContent(color: rgb, hex: hex, notchHeight: notchHeight))
        decayTask?.cancel()
        decayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.decayDuration)
            guard !Task.isCancelled else { return }
            self?.subject.send(nil)
        }
    }
}
