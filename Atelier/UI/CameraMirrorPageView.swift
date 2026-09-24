import AppKit
import AVFoundation
import SwiftUI

/// The Camera tab. One fixed frame for every state so nothing jumps
/// (spec: "keep it clean"). The live state is video only; tap to stop.
struct CameraMirrorPageView: View {
    @ObservedObject var source: CameraMirrorSource
    /// Called only when a tap turned a live mirror off (not on tab change
    /// or retract), so the host can close the notch in hold-open mode.
    var onStopTapped: () -> Void = {}

    private static let cornerRadius: CGFloat = 16

    var body: some View {
        Button {
            let wasLive = source.isLive
            source.toggle()
            if wasLive { onStopTapped() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                CameraPreviewView(layer: source.previewLayer)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                    .opacity(source.phase == .live ? 1 : 0)
                    .allowsHitTesting(false)

                if source.phase != .live {
                    placeholder
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CameraPressStyle())
        .focusEffectDisabled()
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: source.phase)
        .accessibilityLabel(source.isLive ? "Camera mirror, on" : "Camera mirror, off")
        .help(source.isLive ? "Turn camera off" : "Turn camera on")
        .accessibilityHint(source.phase == .denied ? "Opens System Settings" : "Toggles the camera mirror")
        .onDisappear { source.stop() }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.5))
        .allowsHitTesting(false)
    }

    private var symbol: String {
        switch source.phase {
        case .denied: "exclamationmark.triangle"
        case .noCamera: "video.slash"
        default: "web.camera"
        }
    }

    private var caption: String {
        switch source.phase {
        case .idle: "Tap to mirror"
        case .starting: "Starting…"
        case .denied: "Camera access is off — tap to open Settings"
        case .noCamera: "No camera found"
        case .live: ""
        }
    }
}

/// Subtle press feedback (polish rule): a slight dim, no bounce.
private struct CameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Hosts the source's single `AVCaptureVideoPreviewLayer`, mirrored.
private struct CameraPreviewView: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    /// Resizes the hosted layer whenever AppKit lays the view out, so the
    /// preview tracks the page's frame without manual bookkeeping.
    private final class HostView: NSView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.wantsLayer = true
        view.previewLayer = layer
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The connection only exists once the session has an input, so
        // (re)apply mirroring on every update rather than once in make.
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
