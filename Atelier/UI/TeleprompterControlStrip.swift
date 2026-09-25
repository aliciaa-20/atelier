import SwiftUI

/// Play/pause + speed on the left of the camera cutout, ghost icon + the
/// time ring on the right, all inside the notch band (CueNotch's layout).
/// `notchWidth`/`height` are the real notch, so the flanks line up with it.
struct TeleprompterControlStrip: View {
    @ObservedObject var model: TeleprompterModel
    let notchWidth: CGFloat
    let height: CGFloat
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false

    private static let speedPresets: [Int] = [60, 80, 100, 120, 140, 160, 180, 200, 240, 280]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                playPauseButton
                speedMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The camera cutout: nothing to draw, nothing to click.
            Color.clear
                .frame(width: notchWidth)
                .allowsHitTesting(false)

            HStack(spacing: 8) {
                if ghostMode {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Ghost Mode is on: hidden from screen sharing")
                        .accessibilityLabel("Ghost Mode on")
                }
                ring
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Clear of the panel's rounded top corners (the ring used to touch
        // the right edge).
        .padding(.horizontal, 24)
        .frame(height: height)
    }

    private var playPauseButton: some View {
        Button {
            model.toggle()
        } label: {
            Image(systemName: model.wantsNotchOpen ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(TeleprompterPressStyle())
        .disabled(!model.canPlay)
        .opacity(model.canPlay ? 1 : 0.35)
        .help(model.wantsNotchOpen ? "Pause" : "Play")
        .accessibilityLabel(model.wantsNotchOpen ? "Pause script" : "Play script")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speedPresets, id: \.self) { wpm in
                Button("\(wpm) WPM") { model.setWPM(Double(wpm)) }
            }
        } label: {
            Text("\(Int(model.scroll.wpm))")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // A `Menu` label is bridged to AppKit and can keep showing the old
        // number until something else re-renders it; a new id per speed
        // rebuilds it immediately.
        .id(Int(model.scroll.wpm))
        .help("Reading speed, words per minute")
        .accessibilityLabel("Reading speed")
        .accessibilityValue("\(Int(model.scroll.wpm)) words per minute")
    }

    private var ring: some View {
        TeleprompterTicker(interval: 1, active: model.isPlaying) { now in
            let remaining = model.scroll.secondsRemaining(at: now)
            let elapsed = model.scroll.secondsElapsed(at: now)
            TeleprompterRing(
                fraction: model.scroll.progress(at: now),
                label: TimeFormatting.mmss(remaining),
                detail: "\(TimeFormatting.mmss(elapsed)) of \(TimeFormatting.mmss(model.scroll.secondsTotal))"
            )
        }
    }
}

/// Subtle press feedback (polish rule): a slight dim, no bounce. Same idea
/// as `CameraPressStyle`, which is private to the camera page.
private struct TeleprompterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
