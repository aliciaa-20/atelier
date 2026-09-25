import Combine
import CoreGraphics
import Darwin
import Foundation

/// Applies built-in-display brightness changes via `DisplayServices`'s
/// private, undocumented `DisplayServicesGetBrightness`/
/// `DisplayServicesSetBrightness` symbols -- there is no public API for the
/// internal panel (Apple's public `Brightness`-adjacent APIs only cover
/// external displays via DDC/CI). Resolved via `dlopen`/`dlsym` at runtime
/// rather than linking the private framework directly, so a missing or
/// renamed symbol on some future macOS fails to resolve (`nil`) instead of
/// refusing to launch. See the new ADR for the full risk writeup.
///
/// **Fail-open**: if the symbols can't be resolved, or the call itself
/// reports an error, `step(by:)` returns `false` and `MediaKeyInterceptor`
/// lets the key event pass through untouched -- the stock HUD reappears
/// rather than the feature silently doing nothing.
final class BrightnessSource: LiveActivitySource {
    let id = "brightness"
    private let hudOrder: SystemHUDOrder

    /// Computed, not stored -- see `VolumeSource.priority`'s doc comment.
    var priority: Int {
        hudOrder.mostRecentID == id ? NotchLiveActivityPriority.systemHUDActive : NotchLiveActivityPriority.systemHUDInactive
    }

    private static let step: Float = 1.0 / 16.0
    /// Same reasoning as `VolumeSource.decayDuration` -- must match
    /// `NotchController.peekDuration` exactly, not a shorter value.
    private static let decayDuration = NotchController.peekDuration

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_NOW
    )

    private static let getBrightness: GetBrightnessFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightnessFn.self)
    }()

    private static let setBrightness: SetBrightnessFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightnessFn.self)
    }()

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private var decayTask: Task<Void, Never>?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat, hudOrder: SystemHUDOrder) {
        self.notchHeight = notchHeight
        self.hudOrder = hudOrder
    }

    /// Nudges brightness by one step. Returns whether the change was
    /// actually applied -- `false` means the symbols were unavailable or
    /// the call failed, and `MediaKeyInterceptor` should let the key event
    /// pass through so the stock HUD shows instead.
    func step(by direction: Int) -> Bool {
        guard let getBrightness = Self.getBrightness, let setBrightness = Self.setBrightness else { return false }

        var current: Float = 0
        guard getBrightness(CGMainDisplayID(), &current) == 0 else { return false }

        let next = min(max(current + Float(direction) * Self.step, 0), 1)
        guard setBrightness(CGMainDisplayID(), next) == 0 else { return false }

        publish(percent: Int((next * 100).rounded()))
        return true
    }

    /// Sets brightness to an absolute level, for the peek's drag-to-scrub
    /// bar -- same reasoning as `VolumeSource.scrub(toPercent:)`.
    func scrub(toPercent percent: Int) {
        guard let setBrightness = Self.setBrightness else { return }
        let clamped = min(max(percent, 0), 100)
        guard setBrightness(CGMainDisplayID(), Float(clamped) / 100) == 0 else { return }
        publish(percent: clamped)
    }

    private func publish(percent: Int) {
        hudOrder.touch(id)
        HUDAnnouncer.announce("Brightness \(percent) percent")
        subject.send(BrightnessActivityContent(
            percent: percent,
            notchHeight: notchHeight,
            onScrub: { [weak self] percent in self?.scrub(toPercent: percent) }
        ))
        decayTask?.cancel()
        decayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.decayDuration)
            guard !Task.isCancelled else { return }
            self?.subject.send(nil)
        }
    }
}
