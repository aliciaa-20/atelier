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
