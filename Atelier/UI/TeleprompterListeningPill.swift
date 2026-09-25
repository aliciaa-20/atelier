import SwiftUI

/// Small black pill hanging below the teleprompter while voice sync is
/// listening: a live waveform plus a mono "Listening" label (CueNotch look).
/// It exists only while listening, so its level updates cost nothing otherwise.
struct TeleprompterListeningPill: View {
    @ObservedObject var speech: SpeechRecognizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                ForEach(Self.barWeights.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2, height: barHeight(Self.barWeights[index]))
                }
            }
            .frame(height: 12)
            Text("Listening")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .frame(height: NotchLayout.teleprompterPillHeight)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(.black)
        )
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: speech.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening for your voice")
    }

    /// Reduce Motion: a fixed, calm shape instead of a live waveform.
    private func barHeight(_ weight: CGFloat) -> CGFloat {
        if reduceMotion { return 4 + 4 * weight }
        return 3 + 9 * weight * CGFloat(speech.level)
    }
}
