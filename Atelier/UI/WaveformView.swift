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
    private static let animationDuration: TimeInterval = 0.12
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
                    .animation(.easeOut(duration: Self.animationDuration), value: scales[index])
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
