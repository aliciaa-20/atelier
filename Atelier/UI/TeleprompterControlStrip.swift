import SwiftUI

/// Play/pause + speed on the left of the camera cutout, ghost icon + the
/// time ring on the right, all inside the notch band (CueNotch's layout).
/// `notchWidth`/`height` are the real notch, so the flanks line up with it.
struct TeleprompterControlStrip: View {
    @ObservedObject var model: TeleprompterModel
    let notchWidth: CGFloat
    let height: CGFloat
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false
    @AppStorage(AtelierSettings.teleprompterControlOrderKey) private var controlOrder = ""

    private static let controlSize = NotchLayout.teleprompterControlSize

    /// Trackpad points per 10 WPM step when scrolling over the speed control.
    private static let scrollPointsPerStep: CGFloat = 14
    @State private var scrollRemainder: CGFloat = 0

    var body: some View {
        // Which controls sit on which side of the camera cutout is the
        // user's order from Settings (`TeleprompterControlLayout`).
        let layout = TeleprompterControlLayout.resolve(stored: controlOrder.split(separator: ",").map(String.init))
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(layout.left, id: \.self) { control in controlView(control) }
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
                ForEach(layout.right, id: \.self) { control in controlView(control) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Clear of the panel's rounded top corners (the ring used to touch
        // the right edge).
        .padding(.horizontal, 24)
        .frame(height: height)
    }

    @ViewBuilder
    private func controlView(_ control: TeleprompterControl) -> some View {
        switch control {
        case .play: playPauseButton
        case .speed: speedStepper
        case .ring: ring
        }
    }

    private var playPauseButton: some View {
        Button {
            model.toggle()
        } label: {
            Image(systemName: model.wantsNotchOpen ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(TeleprompterPressStyle())
        .disabled(!model.canPlay)
        .opacity(model.canPlay ? 1 : 0.35)
        .help(model.wantsNotchOpen ? "Pause" : "Play")
        .accessibilityLabel(model.wantsNotchOpen ? "Pause script" : "Play script")
    }

    /// `−  100  +` capsule, all inside the notch (no popup window, so the
    /// notch never sees the pointer "leave"). Scrolling over it also changes
    /// the speed, like the Calendar's scroll: up = faster.
    private var speedStepper: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", label: "Slower", delta: -10)
            Text("\(Int(model.scroll.wpm))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText(value: model.scroll.wpm))
                .animation(.snappy(duration: 0.2), value: model.scroll.wpm)
                .frame(minWidth: 24)
            stepButton(symbol: "plus", label: "Faster", delta: 10)
        }
        .padding(.horizontal, 2)
        .frame(height: Self.controlSize)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .background(TeleprompterScrollCatcher { deltaY in
            // Content-follows-fingers: fingers up (negative) = faster.
            scrollRemainder += -deltaY
            let steps = (scrollRemainder / Self.scrollPointsPerStep).rounded(.towardZero)
            guard steps != 0 else { return }
            scrollRemainder -= steps * Self.scrollPointsPerStep
            model.stepWPM(by: Double(steps) * 10)
        })
        .help("Reading speed, words per minute. Scroll here to change it")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading speed")
        .accessibilityValue("\(Int(model.scroll.wpm)) words per minute")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.stepWPM(by: 10)
            case .decrement: model.stepWPM(by: -10)
            @unknown default: break
            }
        }
    }

    private func stepButton(symbol: String, label: String, delta: Double) -> some View {
        Button {
            model.stepWPM(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18, height: Self.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(TeleprompterPressStyle())
        .help(label)
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
            .notchFocusRing(cornerRadius: 13)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
