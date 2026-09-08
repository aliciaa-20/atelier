import Combine
import CoreAudio
import Foundation

/// Applies volume/mute changes via public CoreAudio
/// (`AudioObjectSetPropertyData` on the default output device) and
/// publishes a transient `VolumeActivityContent` for `MediaKeyInterceptor`
/// to pop into the notch. A new, small wrapper deliberately separate from
/// `OutputDeviceManager` -- that type manages *which* device is the
/// default output, a different concern from *this* device's volume/mute,
/// per the design spec.
final class VolumeSource: LiveActivitySource {
    let id = "volume"
    let priority = NotchLiveActivityPriority.volume

    /// Matches the ~1/16 step macOS itself applies per key press.
    private static let step: Float32 = 0.0625
    /// Deliberately matches `NotchController.peekDuration` exactly, not a
    /// shorter, independent value: this source withdraws its own content
    /// (`subject.send(nil)`) on this timer, while `NotchController`
    /// separately closes the peek panel itself on its own `peekDuration`
    /// timer. A shorter value here (an earlier pass tried ~1.3s, closer to
    /// the real HUD's own faster timing) meant content vanished ~1.2s
    /// before the panel started retracting -- `NotchRootView`'s
    /// `lastPeekContent` papered over the blank content, but the panel
    /// itself sat open with stale content for that whole window before
    /// finally snapping shut, reading as a glitchy close. Confirmed
    /// on-device.
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

    /// Nudges volume by one step in the given direction and publishes the
    /// resulting HUD. Returns whether the change was actually applied --
    /// `MediaKeyInterceptor` uses this to decide whether to suppress the
    /// key event.
    func step(by direction: Int) -> Bool {
        guard let deviceID = Self.defaultOutputDevice() else { return false }
        guard let current = Self.volume(for: deviceID) else { return false }

        let wasMuted = Self.isMuted(for: deviceID) ?? false
        let next = min(max(current + Float32(direction) * Self.step, 0), 1)
        guard Self.setVolume(next, for: deviceID) else { return false }
        // A volume key press also implicitly unmutes, matching stock
        // macOS behavior.
        if wasMuted, next > 0 {
            _ = Self.setMuted(false, for: deviceID)
        }

        publish(percent: Int((next * 100).rounded()), isMuted: next == 0 && wasMuted)
        return true
    }

    /// Toggles mute and publishes the resulting HUD.
    func toggleMute() -> Bool {
        guard let deviceID = Self.defaultOutputDevice(),
              let isMuted = Self.isMuted(for: deviceID),
              Self.setMuted(!isMuted, for: deviceID)
        else { return false }

        let percent = Self.volume(for: deviceID).map { Int(($0 * 100).rounded()) } ?? 0
        publish(percent: percent, isMuted: !isMuted)
        return true
    }

    private func publish(percent: Int, isMuted: Bool) {
        subject.send(VolumeActivityContent(percent: percent, isMuted: isMuted, notchHeight: notchHeight))
        decayTask?.cancel()
        decayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.decayDuration)
            guard !Task.isCancelled else { return }
            self?.subject.send(nil)
        }
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    /// Not every output device exposes `kAudioDevicePropertyVolumeScalar`
    /// on the virtual master element (`kAudioObjectPropertyElementMain`) --
    /// some only support it per-channel. Falls back to channel 1 (left/
    /// mono) when the main element isn't available, rather than silently
    /// failing `step(by:)`/`toggleMute()` on those devices.
    private static func volumeElement(for deviceID: AudioDeviceID) -> AudioObjectPropertyElement {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &address) ? kAudioObjectPropertyElementMain : 1
    }

    private static func volume(for deviceID: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: volumeElement(for: deviceID)
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return volume
    }

    private static func setVolume(_ volume: Float32, for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: volumeElement(for: deviceID)
        )
        var mutableVolume = volume
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutableVolume) == noErr
    }

    private static func isMuted(for deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    private static func setMuted(_ muted: Bool, for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
