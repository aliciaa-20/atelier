import SwiftUI

/// The Teleprompter tab's text area: a few display lines gliding upward at
/// the script's WPM, the current line brightest (Focus Guide), lines
/// already read dimmed, top/bottom edges faded. Only the visible window of
/// lines is built. Redraws at 30 fps while playing, 4 fps under Reduce
/// Motion (where the scroll steps line by line instead of gliding), and
/// not at all when paused.
struct TeleprompterPageView: View {
    @ObservedObject var model: TeleprompterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AtelierSettings.teleprompterFontSizeKey) private var fontSize = 15.0
    @AppStorage(AtelierSettings.teleprompterMonoFontKey) private var mono = false

    /// Lines shown above the current one (already read, dimmed).
    private static let readLinesAbove = 1.0
    private static let lineHeightFactor = 1.35

    var body: some View {
        GeometryReader { geo in
            Group {
                if model.script.isEmpty {
                    emptyState
                } else {
                    reader(height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { model.updateLayout(width: geo.size.width, fontSize: fontSize, mono: mono) }
            .onChange(of: geo.size.width) { _, width in model.updateLayout(width: width, fontSize: fontSize, mono: mono) }
            .onChange(of: fontSize) { _, size in model.updateLayout(width: geo.size.width, fontSize: size, mono: mono) }
            .onChange(of: mono) { _, isMono in model.updateLayout(width: geo.size.width, fontSize: fontSize, mono: isMono) }
        }
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.bottom, 8)
    }

    private func reader(height: CGFloat) -> some View {
        let lineHeight = fontSize * Self.lineHeightFactor
        let tick: TimeInterval = reduceMotion ? 0.25 : 1.0 / 30
        return TeleprompterTicker(interval: tick, active: model.isPlaying) { now in
            let wordPosition = model.scroll.position(at: now)
            let linePosition = model.lines.linePosition(forWord: wordPosition)
            // Reduce Motion: step whole lines instead of gliding.
            let shown = reduceMotion ? linePosition.rounded(.down) : linePosition
            let current = model.lines.currentLine(forWord: wordPosition)
            let visible = model.lines.visibleLines(
                around: shown, behind: 2, ahead: Int(height / lineHeight) + 2
            )
            ZStack(alignment: .topLeading) {
                ForEach(visible, id: \.self) { index in
                    Text(model.lineText(index))
                        .font(TeleprompterFont.swiftUIFont(size: fontSize, mono: mono))
                        .foregroundStyle(.white.opacity(Self.opacity(line: index, current: current)))
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: (Double(index) - shown + Self.readLinesAbove) * lineHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .mask(edgeFade)
            // One element for VoiceOver: the current line, not every Text.
            // Inside the ticker so the value follows the scroll instead of
            // going stale while playing.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Teleprompter script")
            .accessibilityValue(model.lineText(current))
        }
        .allowsHitTesting(false)
        // Paused: scroll the script by hand (ignored by the model while
        // playing). Content follows the fingers, like any scroll view.
        .background(TeleprompterScrollCatcher { deltaY in
            model.scrollLines(by: -Double(deltaY) / lineHeight)
        })
    }

    /// Focus Guide: current line full, read lines dim, upcoming lines mid.
    private static func opacity(line: Int, current: Int) -> Double {
        if line < current { return 0.35 }
        if line == current { return 1 }
        return 0.7
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The shared empty-state style: soft card, one SF Symbol, one short line.
    private var emptyState: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                VStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 20, weight: .regular))
                    Text("Add a script in Settings")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No script. Open Settings to add one")
        .help("Open Settings")
    }
}
