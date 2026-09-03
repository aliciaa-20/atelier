import SwiftUI

/// A small bar cluster next to the track info, colored to match the current
/// artwork (`ArtworkColorLoader`). Adapted from jackson-storm/dynamicnotch's
/// `LightweightNowPlayingEqualizerView` — pulled via `gh api` as ground
/// truth after a real system-audio tap (CoreAudio Process Tap, matching
/// Ebullioscopic/Atoll's approach) proved unreliable in practice. Their own
/// "equalizer" isn't real-audio-reactive either: `CGFloat.random(in:
/// minimumPlayingScale...1)` driven purely by `isPlaying`, the same
/// technique this file uses (with their timing constants) — a shipped,
/// reference-quality app makes the same call for the same component.
struct WaveformView: View {
    let isPlaying: Bool
    let color: Color
    var barWidth: CGFloat = 2.7
    var barSpacing: CGFloat = 2
    var height: CGFloat = 18

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
    }

    private func setAnimating(_ playing: Bool) {
        animationTask?.cancel()
        guard playing else {
            scales = Array(repeating: Self.minimumScale, count: Self.barCount)
            return
        }
        animationTask = Task {
            while !Task.isCancelled {
                scales = (0..<Self.barCount).map { _ in CGFloat.random(in: Self.minimumScale...1) }
                try? await Task.sleep(for: .seconds(Self.timerInterval))
            }
        }
    }
}
