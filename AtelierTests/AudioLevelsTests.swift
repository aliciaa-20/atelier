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

        // Decay is per-call (0.98x), matching one IOProc callback -- a
        // single call only takes peak from 1.0 to 0.98, so simulate
        // several callbacks' worth of a quieter passage, same as real
        // playback would produce many callbacks per second.
        let quiet = Array(repeating: Float(0.05), count: 600)
        var heights: [Float] = []
        for _ in 0..<60 {
            heights = AudioLevels.barHeights(samples: quiet, peak: &peak)
        }
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
