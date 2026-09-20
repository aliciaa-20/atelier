import Accelerate
import Foundation

/// Pure math: turns a raw PCM sample buffer into `barCount` normalized bar
/// heights for `WaveformView`. No CoreAudio types cross this boundary —
/// `AudioTap` extracts `[Float]` samples from an `AudioBufferList` before
/// calling in here, which is what keeps this file unit-testable without a
/// real audio tap. See docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md.
///
/// `nonisolated`: the project defaults every type to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), which would make
/// `barHeights` a `@MainActor` function despite having no actual affinity
/// for it. `AudioTap`'s realtime IOProc callback calls `barHeights`
/// synchronously from CoreAudio's own audio thread, not `@MainActor` — a
/// `@MainActor`-isolated `barHeights` crashed there at runtime
/// (`dispatch_assert_queue_fail` via the Swift runtime's isolation check)
/// the first time this was exercised on-device.
nonisolated enum AudioLevels {
    static let barCount = 6
    /// Lower than the fake animation's floor (was 0.32, matching
    /// `WaveformView`'s own -- lowered per direct feedback that the real
    /// waveform's swing read as too narrow) -- real audio's RMS tends to
    /// sit mid-range rather than swinging randomly across the full band
    /// the way the fake animation does, so a lower floor gives it more
    /// room to visually breathe between quiet and loud passages.
    static let minimumScale: Float = 0.18
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
