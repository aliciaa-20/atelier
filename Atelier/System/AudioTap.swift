import Accelerate
import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Wraps a whole-system CoreAudio process tap (macOS 14.4+'s Audio Taps
/// API) — deliberately *not* scoped to Spotify's process specifically.
///
/// An earlier design tried a per-process tap on Spotify (ported from
/// Ebullioscopic/Atoll's `AudioTap.swift`, see check-reference-apps-first),
/// but Atoll's own source documents that process-tapping Spotify disturbs
/// the system AVRCP session AirPods' pause/skip gesture depends on. A
/// whole-system tap was spiked on-device instead (two independent runs,
/// AirPods pause/skip unaffected both times) — see
/// docs/decisions/0012-whole-system-audio-tap.md and
/// docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md.
///
/// Manual-verification only, like the rest of `System/` — the realtime
/// CoreAudio callback and macOS's own system-audio-recording TCC prompt
/// can't be exercised in CI.
///
/// `@unchecked Sendable`: the IOProc block below runs on a realtime
/// CoreAudio thread, not `@MainActor`, and captures `self` to reach
/// `tapID`/`aggregateID`/`procID`/`peak`/`continuation`. Those properties
/// (plus `consumerTask`, touched only from `teardown()`, which itself runs
/// from both `@MainActor` and non-isolated `deinit`) are `nonisolated(unsafe)`
/// and are only ever touched from `init`/`deinit`/`start()`/`stop()`/
/// `teardown()` (all effectively `@MainActor`-driven) or from that one
/// realtime callback while the tap is running — never concurrently from
/// both, the same reasoning `BatterySource` documents for its own
/// `nonisolated(unsafe) runLoopSource`.
@MainActor
final class AudioTap: ObservableObject, @unchecked Sendable {
    @Published private(set) var levels: [Float] = Array(repeating: AudioLevels.minimumScale, count: AudioLevels.barCount)
    @Published private(set) var isRunning = false

    nonisolated(unsafe) private var tapID: AudioObjectID = 0
    nonisolated(unsafe) private var aggregateID: AudioObjectID = 0
    nonisolated(unsafe) private var procID: AudioDeviceIOProcID?
    nonisolated(unsafe) private var peak: Float = 0.01
    nonisolated(unsafe) private var continuation: AsyncStream<[Float]>.Continuation?
    nonisolated(unsafe) private var consumerTask: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID: AudioObjectID = 0
        guard AudioHardwareCreateProcessTap(tapDescription, &newTapID) == noErr else {
            return
        }

        var tapUID: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(newTapID, &uidAddress, 0, nil, &uidSize, &tapUID) == noErr,
              let tapUIDString = tapUID as String? else {
            _ = AudioHardwareDestroyProcessTap(newTapID)
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Atelier Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUIDString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var newAggregateID: AudioObjectID = 0
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID) == noErr else {
            _ = AudioHardwareDestroyProcessTap(newTapID)
            return
        }

        let stream = AsyncStream<[Float]> { streamContinuation in
            self.continuation = streamContinuation
        }
        consumerTask = Task { @MainActor [weak self] in
            for await heights in stream {
                self?.levels = heights
            }
        }

        var newProcID: AudioDeviceIOProcID?
        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
            guard let self else { return }
            let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            var samples: [Float] = []
            for buffer in bufferList {
                guard let data = buffer.mData else { continue }
                let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
                let pointer = data.bindMemory(to: Float32.self, capacity: frameCount)
                samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: frameCount))
            }
            guard !samples.isEmpty else { return }
            let heights = AudioLevels.barHeights(samples: samples, peak: &self.peak)
            self.continuation?.yield(heights)
        }

        guard AudioDeviceCreateIOProcIDWithBlock(&newProcID, newAggregateID, nil, ioBlock) == noErr,
              let newProcID else {
            _ = AudioHardwareDestroyAggregateDevice(newAggregateID)
            _ = AudioHardwareDestroyProcessTap(newTapID)
            consumerTask?.cancel()
            continuation?.finish()
            return
        }

        guard AudioDeviceStart(newAggregateID, newProcID) == noErr else {
            _ = AudioDeviceDestroyIOProcID(newAggregateID, newProcID)
            _ = AudioHardwareDestroyAggregateDevice(newAggregateID)
            _ = AudioHardwareDestroyProcessTap(newTapID)
            consumerTask?.cancel()
            continuation?.finish()
            return
        }

        tapID = newTapID
        aggregateID = newAggregateID
        procID = newProcID
        peak = 0.01
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        teardown()
        isRunning = false
        levels = Array(repeating: AudioLevels.minimumScale, count: AudioLevels.barCount)
    }

    deinit {
        // `isRunning` is `@MainActor`-isolated and unreadable from this
        // nonisolated `deinit` -- `procID` (`nonisolated(unsafe)`) is the
        // actual thing being torn down, and is non-nil exactly when
        // `isRunning` would be `true`.
        if procID != nil {
            teardown()
        }
    }

    /// Runs from both `@MainActor` (`stop()`) and non-isolated context
    /// (`deinit`) — idempotent and side-effect-free to call twice, same
    /// pattern as `BatterySource.deinit`.
    nonisolated private func teardown() {
        if let procID {
            _ = AudioDeviceStop(aggregateID, procID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != 0 {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != 0 {
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = 0
        tapID = 0
        continuation?.finish()
        continuation = nil
        consumerTask?.cancel()
        consumerTask = nil
    }
}
