# Real-Time Audio Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `WaveformView`'s fake `CGFloat.random(in:)` bars with real audio-reactive levels in `ExpandedPlayerView`, sourced from a whole-system CoreAudio process tap, without breaking AirPods' pause/skip gesture on any output route.

**Architecture:** A new `AudioTap` (`Atelier/System/AudioTap.swift`) creates a whole-system CoreAudio tap (`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`) into a private aggregate device, reads raw samples on the realtime IOProc callback, and hands them across an `AsyncStream` to a `@MainActor` consumer that republishes 6 normalized bar heights via `@Published`. The RMS-to-bar-height math lives in a separate pure file (`AudioLevels.swift`) so it's unit-testable without any CoreAudio dependency. `NotchController` owns the `AudioTap`, starting/stopping it as `nowPlayingCoordinator.current?.isPlaying` transitions. `WaveformView` grows an optional `levels` parameter — when supplied, bar heights come from real data; when `nil` (tap not running, e.g. permission denied), it falls back to exactly today's random animation. Only `ExpandedPlayerView` gets real levels in this plan; `PillPlayerView`/`PeekPlayerView` keep the fake animation (see Global Constraints).

**Tech Stack:** Swift 6, strict concurrency, CoreAudio, AudioToolbox, Accelerate (`vDSP_rmsqv`), Combine (`ObservableObject`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md`

## Global Constraints

- Swift 6, strict concurrency; `AudioTap` is `@MainActor` and `@unchecked Sendable` (documented, not accidental — its stored properties are either only touched from `@MainActor` methods, or `nonisolated(unsafe)` and only touched from `init`/`deinit`/the realtime IOProc callback, matching the existing `nonisolated(unsafe)` convention in `BatterySource`).
- No third-party dependencies — CoreAudio, AudioToolbox, and Accelerate are all system frameworks.
- **No Bluetooth-route guard.** The whole-system tap was spike-verified not to disturb AirPods' AVRCP session (see the spec's "What changed since the v1 spec" section) — do not add an `OutputDeviceManager.isDefaultOutputBluetooth()` check or any output-route branching.
- The tap must never crash or repeatedly re-prompt on permission denial: `AudioTap.start()` checks every CoreAudio call's `OSStatus` and simply stays not-running (falling back to `WaveformView`'s existing fake animation) on any failure.
- Only `ExpandedPlayerView` gets real levels in this plan. `PillPlayerView` and `PeekPlayerView` are unchanged — they keep calling `WaveformView` without a `levels` argument, which defaults to `nil` (fake animation), exactly as today.
- `AudioTap.start()`/`.stop()` are driven by `nowPlayingCoordinator.current?.isPlaying`, not the app's lifetime — the tap only exists while there's something to visualize.
- Manual verification only for `AudioTap` itself (real hardware, real TCC permission, matches `System/`'s existing convention) — the RMS/normalization math in `AudioLevels.swift` is unit tested.

---

### Task 1: `AudioLevels` — pure RMS/normalization math

**Files:**
- Create: `Atelier/System/AudioLevels.swift`
- Test: `AtelierTests/AudioLevelsTests.swift`

**Interfaces:**
- Produces: `AudioLevels.barCount: Int`, `AudioLevels.minimumScale: Float`, `AudioLevels.barHeights(samples: [Float], peak: inout Float) -> [Float]` — used by Task 2 (`AudioTap`).

- [x] **Step 1: Write the failing tests**

Create `AtelierTests/AudioLevelsTests.swift`:

```swift
import Testing
@testable import Atelier

struct AudioLevelsTests {
    @Test func silenceProducesMinimumScaleBars() {
        var peak: Float = 0.01
        let samples = Array(repeating: Float(0), count: 600)
        let heights = AudioLevels.barHeights(samples: samples, peak: &peak)
        #expect(heights.count == AudioLevels.barCount)
        #expect(heights.allSatisfy { $0 == AudioLevels.minimumScale })
    }

    @Test func fullScaleSignalProducesNearMaxBars() {
        var peak: Float = 0.01
        let samples = Array(repeating: Float(1.0), count: 600)
        let heights = AudioLevels.barHeights(samples: samples, peak: &peak)
        #expect(heights.count == AudioLevels.barCount)
        for height in heights {
            #expect(height > 0.95)
        }
    }

    @Test func emptySamplesFallsBackToMinimumScale() {
        var peak: Float = 0.01
        let heights = AudioLevels.barHeights(samples: [], peak: &peak)
        #expect(heights == Array(repeating: AudioLevels.minimumScale, count: AudioLevels.barCount))
    }

    @Test func peakDecaysAfterALoudPassage() {
        var peak: Float = 0.01
        let loud = Array(repeating: Float(1.0), count: 600)
        _ = AudioLevels.barHeights(samples: loud, peak: &peak)
        #expect(peak > 0.9)

        let quiet = Array(repeating: Float(0.05), count: 600)
        let heights = AudioLevels.barHeights(samples: quiet, peak: &peak)
        // Peak decays toward the new (quieter) loudest chunk rather than
        // staying pinned at the earlier loud passage's level forever.
        #expect(peak < 0.9)
        #expect(heights.allSatisfy { $0 >= AudioLevels.minimumScale })
    }

    @Test func unevenSampleCountStillProducesSixBars() {
        var peak: Float = 0.01
        // 601 samples doesn't divide evenly by barCount (6) -- the last
        // chunk must absorb the remainder rather than dropping samples or
        // crashing.
        let samples = Array(repeating: Float(0.5), count: 601)
        let heights = AudioLevels.barHeights(samples: samples, peak: &peak)
        #expect(heights.count == AudioLevels.barCount)
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/AudioLevelsTests`
Expected: FAIL — `AudioLevels` doesn't exist yet.

- [x] **Step 3: Write the implementation**

Create `Atelier/System/AudioLevels.swift`:

```swift
import Accelerate
import Foundation

/// Pure math: turns a raw PCM sample buffer into `barCount` normalized bar
/// heights for `WaveformView`. No CoreAudio types cross this boundary —
/// `AudioTap` extracts `[Float]` samples from an `AudioBufferList` before
/// calling in here, which is what keeps this file unit-testable without a
/// real audio tap. See docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md.
enum AudioLevels {
    static let barCount = 6
    static let minimumScale: Float = 0.32
    /// Multiplied into `peak` on every call before comparing against the
    /// current loudest chunk -- lets the normalization ceiling settle back
    /// down after a loud passage instead of staying pinned at its level
    /// for the rest of the track.
    private static let peakDecay: Float = 0.98

    /// Splits `samples` into `barCount` equal-ish chunks (the last chunk
    /// absorbs any remainder), computes RMS per chunk via `vDSP_rmsqv`,
    /// and normalizes each against `peak` (updated in place). Empty input
    /// returns all-minimum bars rather than dividing by zero.
    static func barHeights(samples: [Float], peak: inout Float) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: minimumScale, count: barCount)
        }

        let chunkSize = max(1, samples.count / barCount)
        var rawRMS: [Float] = []
        rawRMS.reserveCapacity(barCount)

        samples.withUnsafeBufferPointer { buffer in
            for index in 0..<barCount {
                let start = index * chunkSize
                let end = (index == barCount - 1) ? samples.count : min(start + chunkSize, samples.count)
                guard start < end, let base = buffer.baseAddress else {
                    rawRMS.append(0)
                    continue
                }
                var rms: Float = 0
                vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(end - start))
                rawRMS.append(rms)
            }
        }

        let loudest = rawRMS.max() ?? 0
        peak = max(loudest, peak * peakDecay)
        guard peak > 0 else {
            return Array(repeating: minimumScale, count: barCount)
        }

        return rawRMS.map { raw in
            let normalized = min(1, raw / peak)
            return minimumScale + normalized * (1 - minimumScale)
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/AudioLevelsTests`
Expected: `** TEST SUCCEEDED **`, all 5 tests pass.

- [x] **Step 5: Commit**

```bash
git add Atelier/System/AudioLevels.swift AtelierTests/AudioLevelsTests.swift
git commit -m "feat: add AudioLevels RMS/normalization math for the real audio visualizer"
```

---

### Task 2: `AudioTap` — whole-system CoreAudio process tap

**Files:**
- Create: `Atelier/System/AudioTap.swift`

**Interfaces:**
- Consumes: `AudioLevels.barCount`, `AudioLevels.minimumScale`, `AudioLevels.barHeights(samples:peak:)` (Task 1).
- Produces: `AudioTap` (`ObservableObject`), `.levels: [Float]` (`@Published`), `.isRunning: Bool` (`@Published`), `.start()`, `.stop()` — used by Task 4 (`ExpandedPlayerView`/`NotchRootView`) and Task 5 (`NotchController`).

- [x] **Step 1: Write the file**

Create `Atelier/System/AudioTap.swift`:

```swift
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
/// docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md.
///
/// Manual-verification only, like the rest of `System/` — the realtime
/// CoreAudio callback and macOS's own system-audio-recording TCC prompt
/// can't be exercised in CI.
///
/// `@unchecked Sendable`: the IOProc block below runs on a realtime
/// CoreAudio thread, not `@MainActor`, and captures `self` to reach
/// `tapID`/`aggregateID`/`procID`/`peak`/`continuation`. Those five
/// properties are `nonisolated(unsafe)` and are only ever touched from
/// `init`/`deinit`/`start()`/`stop()` (all `@MainActor`) or from that one
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

    private var consumerTask: Task<Void, Never>?

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
        if isRunning {
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
```

- [x] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. If Swift 6 strict concurrency rejects the `[weak self]` capture in `ioBlock` (a non-`@Sendable` closure type from the CoreAudio overlay), the `@unchecked Sendable` conformance above should already cover it — if not, the fix is to make the capture explicit via `nonisolated(unsafe) let unsafeSelf = self` inside the block rather than relaxing any of the `nonisolated(unsafe)` property markers.

- [x] **Step 3: Commit**

```bash
git add Atelier/System/AudioTap.swift
git commit -m "feat: add AudioTap, a whole-system CoreAudio process tap for the audio visualizer"
```

---

### Task 3: `WaveformView` — real levels with fake-animation fallback

**Files:**
- Modify: `Atelier/UI/WaveformView.swift`

**Interfaces:**
- Consumes: nothing new (takes `levels: [Float]?` as plain data — no dependency on `AudioTap` itself, callers decide what to pass).
- Produces: `WaveformView(isPlaying:color:barWidth:barSpacing:height:levels:)` — the `levels` parameter used by Task 4.

- [x] **Step 1: Rewrite the file**

Replace `Atelier/UI/WaveformView.swift` with:

```swift
import SwiftUI

/// A small bar cluster next to the track info, colored to match the current
/// artwork (`ArtworkColorLoader`). When `levels` is supplied (a real tap is
/// running — see `AudioTap`), bar heights come from those 6 normalized RMS
/// values. When `levels` is `nil` (no tap, e.g. permission denied, or this
/// call site doesn't wire one up at all), falls back to the original fake
/// animation adapted from jackson-storm/dynamicnotch's
/// `LightweightNowPlayingEqualizerView` (`CGFloat.random(in:
/// minimumScale...1)` on a timer) — so the waveform is never blank, only
/// ever "fake but alive" vs. "real."
struct WaveformView: View {
    let isPlaying: Bool
    let color: Color
    var barWidth: CGFloat = 2.7
    var barSpacing: CGFloat = 2
    var height: CGFloat = 18
    var levels: [Float]? = nil

    private static let barCount = 6
    private static let minimumScale: CGFloat = 0.32
    private static let animationDuration: TimeInterval = 0.2
    private static let timerInterval: TimeInterval = 0.12

    @State private var scales: [CGFloat] = Array(repeating: WaveformView.minimumScale, count: WaveformView.barCount)
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color.gradient)
                    .frame(width: barWidth)
                    .scaleEffect(y: scales[index], anchor: .center)
                    .animation(.easeInOut(duration: Self.animationDuration), value: scales[index])
            }
        }
        .frame(width: CGFloat(Self.barCount) * barWidth + CGFloat(Self.barCount - 1) * barSpacing, height: height)
        .onAppear { setAnimating(isPlaying) }
        .onDisappear { setAnimating(false) }
        .onChange(of: isPlaying) { _, playing in setAnimating(playing) }
        .onChange(of: levels) { _, newLevels in applyLevels(newLevels) }
    }

    private func setAnimating(_ playing: Bool) {
        animationTask?.cancel()
        animationTask = nil
        guard playing else {
            scales = Array(repeating: Self.minimumScale, count: Self.barCount)
            return
        }
        if let levels, levels.count == Self.barCount {
            scales = levels.map { CGFloat($0) }
            return
        }
        animationTask = Task {
            while !Task.isCancelled {
                scales = (0..<Self.barCount).map { _ in CGFloat.random(in: Self.minimumScale...1) }
                try? await Task.sleep(for: .seconds(Self.timerInterval))
            }
        }
    }

    /// Handles `levels` changing while already playing: real data arriving
    /// (tap just started) switches off the fake-animation loop; real data
    /// disappearing (tap stopped, e.g. permission revoked mid-track)
    /// resumes it, rather than freezing on the last real values.
    private func applyLevels(_ newLevels: [Float]?) {
        guard isPlaying else { return }
        if let newLevels, newLevels.count == Self.barCount {
            animationTask?.cancel()
            animationTask = nil
            scales = newLevels.map { CGFloat($0) }
        } else if newLevels == nil, animationTask == nil {
            setAnimating(true)
        }
    }
}
```

- [x] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **` — `PillPlayerView`/`PeekPlayerView`'s existing `WaveformView(...)` call sites still compile unchanged since `levels` defaults to `nil`.

- [x] **Step 3: Commit**

```bash
git add Atelier/UI/WaveformView.swift
git commit -m "feat: WaveformView accepts real levels, falls back to fake animation"
```

---

### Task 4: Thread `AudioTap` into `ExpandedPlayerView`

**Files:**
- Modify: `Atelier/UI/ExpandedPlayerView.swift`
- Modify: `Atelier/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `AudioTap` (Task 2), `WaveformView`'s `levels` parameter (Task 3).
- Produces: `ExpandedPlayerView`'s and `NotchRootView`'s new `audioTap: AudioTap` parameter — constructed and passed in by Task 5 (`NotchController`).

- [x] **Step 1: Add the parameter and pass real levels to `WaveformView` in `ExpandedPlayerView`**

In `Atelier/UI/ExpandedPlayerView.swift`, add a stored property next to the existing ones (around line 16-25):

```swift
struct ExpandedPlayerView: View {
    let info: NowPlayingInfo?
    let waveformColor: Color
    @ObservedObject var audioTap: AudioTap
    let outputDevices: [AudioOutputDevice]
```

Then update the `WaveformView` call in `headerSection(for:)` (currently line 109):

```swift
            WaveformView(
                isPlaying: info.isPlaying,
                color: waveformColor,
                levels: audioTap.isRunning ? audioTap.levels : nil
            )
```

- [x] **Step 2: Thread `audioTap` through `NotchRootView`**

In `Atelier/UI/NotchRootView.swift`, add a stored property next to the existing observed objects (around line 6-7):

```swift
struct NotchRootView: View {
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @ObservedObject var audioTap: AudioTap
```

Then pass it through at the `ExpandedPlayerView(...)` construction site (around line 121-130):

```swift
                            ExpandedPlayerView(
                                info: nowPlaying.current,
                                waveformColor: /* existing argument, unchanged */,
                                audioTap: audioTap,
                                outputDevices: /* existing argument, unchanged */,
                                currentOutputDeviceID: /* existing argument, unchanged */,
                                onPlayPause: { Task { await nowPlaying.playPause() } },
                                onNext: { Task { await nowPlaying.next() } },
                                onPrevious: { Task { await nowPlaying.previous() } },
                                onSeek: { time in Task { await nowPlaying.seek(to: time) } },
                                onToggleShuffle: { Task { await nowPlaying.toggleShuffle() } },
```

(Keep every other existing argument in `ExpandedPlayerView(...)` exactly as it is today — only inserting the new `audioTap: audioTap` line. Read the surrounding lines before editing so the argument order and existing values are preserved exactly.)

- [x] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: This will fail until Task 5 updates every `NotchRootView(...)` construction site to pass `audioTap:` — that's expected here; if it fails only on the two `NotchRootView(...)` call sites in `NotchController.swift` missing the new argument, that confirms this task's own changes are otherwise correct. Do not modify `NotchController.swift` in this task — that's Task 5.

- [x] **Step 4: Commit**

```bash
git add Atelier/UI/ExpandedPlayerView.swift Atelier/UI/NotchRootView.swift
git commit -m "feat: thread AudioTap into NotchRootView and ExpandedPlayerView"
```

---

### Task 5: Wire `AudioTap` lifecycle into `NotchController`

**Files:**
- Modify: `Atelier/Notch/NotchController.swift`
- Modify: `docs/ROADMAP.md`

**Interfaces:**
- Consumes: `AudioTap` (Task 2), `NotchRootView`'s `audioTap:` parameter (Task 4), existing `nowPlayingCoordinator.$current`.

- [x] **Step 1: Add the stored property**

In `Atelier/Notch/NotchController.swift`, add next to the existing stored properties (around line 25-29):

```swift
    private let lockScreenManager: LockScreenManager
    private let lockScreenPanelController: LockScreenPanelController
    private let audioTap = AudioTap()
    private var notchStateCancellable: AnyCancellable?
    private var isPlayingCancellable: AnyCancellable?
    private var trackChangeCancellable: AnyCancellable?
    private var audioTapCancellable: AnyCancellable?
```

- [x] **Step 2: Pass `audioTap` into both `NotchRootView(...)` construction sites**

In the fallback (no-notch-screen) path, around line 125-132:

```swift
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(
                    viewModel: viewModel,
                    nowPlaying: nowPlayingCoordinator,
                    liveActivity: liveActivityCoordinator,
                    audioTap: audioTap,
                    shelfStore: shelfStore
                )
            )
```

In the real (notched-screen) path, around line 213-220, make the identical change:

```swift
        panel.contentView = ClickThroughHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                nowPlaying: nowPlayingCoordinator,
                liveActivity: liveActivityCoordinator,
                audioTap: audioTap,
                shelfStore: shelfStore
            )
        )
```

- [x] **Step 3: Drive `start()`/`stop()` from playback state**

In `init()`, near where `isPlayingCancellable`/`trackChangeCancellable` are set up (around line 268-309, after `isPlayingCancellable = ...` finishes its `.sink` block), add:

```swift
        // AudioTap's lifetime is tied to actual playback, not the pill/
        // peek UI state above -- it should start the moment something is
        // playing and stop the moment it isn't, independent of whether
        // the notch happens to be expanded to show it.
        audioTapCancellable = nowPlayingCoordinator.$current
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak audioTap] isPlaying in
                if isPlaying {
                    audioTap?.start()
                } else {
                    audioTap?.stop()
                }
            }
```

(This subscription only makes sense in the real, notched-screen `init()` path, alongside `notchStateCancellable`/`isPlayingCancellable`/`trackChangeCancellable` — the fallback no-notch-screen path returns early before reaching that code and does not need it, matching how the other three cancellables are already scoped.)

- [x] **Step 4: Build to verify it compiles**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 5: Run the full unit suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`, 120 tests (115 existing + 5 new `AudioLevelsTests` from Task 1).

- [x] **Step 6: Commit**

```bash
git add Atelier/Notch/NotchController.swift
git commit -m "feat: wire AudioTap lifecycle into NotchController, tied to isPlaying"
```

- [x] **Step 7: Build and relaunch for manual verification**

Use the `build` skill: kill any running `Atelier`, build, relaunch.

Manually verify on-device (check these off only once actually exercised, per `CLAUDE.md`'s Testing section):
- [x] Play music, hover the notch open → `ExpandedPlayerView`'s waveform visibly reacts to the actual audio (louder passages produce taller bars, quiet/silent passages settle near the floor), not the old uniform random flicker.
- [x] Permission handling — no system prompt was actually observed appearing for this `LSUIElement` background app; the "System Audio Recording Only" grant had to be added manually via System Settings → Privacy & Security. Confirmed once granted (and after a several-minute settle delay CoreAudio needed before real data actually started flowing — see the ROADMAP entry) the waveform goes live.
- [ ] Deny the permission prompt → falls back to fake animation. **Not tested** — `AudioHardwareCreateProcessTap` returning `noErr` even without the permission (confirmed this session — `isRunning` goes `true`, but samples stay empty) means an explicit hard-denial path still needs on-device verification; not yet confirmed whether that produces empty buffers forever (same as the not-yet-settled case, currently NOT falling back to the fake animation) or an actual error.
- [x] With AirPods as the output device, pause/skip via the physical gesture still works on this exact integrated code path — confirmed by the user, not just the standalone spike harness.
- [ ] Pause playback → resting state, tap stops, CPU settles. Not explicitly checked via Activity Monitor.
- [x] Resume / track-change → the tap picks back up and the waveform goes live again without an app restart (observed across multiple track changes this session).
- [x] ~~`PillPlayerView`'s and `PeekPlayerView`'s waveforms are unchanged~~ — scope intentionally expanded mid-plan per direct feedback: `PillPlayerView` now also gets real levels (matches `ExpandedPlayerView`), confirmed working. `PeekPlayerView` alone still uses the fake animation, as originally scoped.
- [x] Update `docs/ROADMAP.md` with the result of manual verification (or any bug found), same discipline as prior phases' entries.

---

## Self-Review Notes

- **Spec coverage:** whole-system `AudioTap` mechanism and teardown (Task 2), RMS/normalization DSP (Task 1), `isPlaying`-tied lifecycle (Task 5), `WaveformView` real-data/fallback integration (Task 3), permission-denial graceful fallback (Task 2's `guard` chain + Task 5's manual-verification checklist) — all spec sections have a task. The spec's two "open questions for the implementation plan" are resolved here: smoothing is deferred to on-device tuning (peak-decay normalization only, no explicit attack/decay curve — flagged in Task 5's manual verification as an area to watch, not silently dropped), and the pill/peek mini-waveform question is resolved as "stay fake" (Global Constraints), matching the spec's own suggestion that it's fine to leave for a later pass.
- **Type consistency:** `AudioLevels.barCount`/`.minimumScale`/`.barHeights(samples:peak:)` (Task 1) match their use in `AudioTap`'s IOProc block (Task 2). `AudioTap.levels: [Float]`/`.isRunning: Bool`/`.start()`/`.stop()` (Task 2) match their use in `ExpandedPlayerView` (Task 4) and `NotchController` (Task 5). `WaveformView`'s new `levels: [Float]? = nil` parameter (Task 3) matches its use in `ExpandedPlayerView` (Task 4) and its absence (defaulting to `nil`) at the unchanged `PillPlayerView`/`PeekPlayerView` call sites.
- **Placeholder scan:** no TBDs. Task 4's `ExpandedPlayerView(...)` snippet uses `/* existing argument, unchanged */` for arguments this plan doesn't touch — that's a deliberate instruction to preserve existing code exactly (the surrounding file must be read before editing), not a placeholder for content the plan is failing to specify; every argument this plan actually adds or changes has real code.
