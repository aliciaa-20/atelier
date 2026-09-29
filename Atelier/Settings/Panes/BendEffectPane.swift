import MetalKit
import SwiftUI

/// Adapted from IuCC123/BendMac's `SettingsView.swift` `MetalPreview` (MIT),
/// pointed at the controller's `previewFrames` box instead of the live one
/// so scrubbing the preview angle never touches the real desktop capture.
private struct BendEffectMetalPreview: NSViewRepresentable {
    @ObservedObject var controller: BendEffectController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> MTKView {
        let view = context.coordinator.renderer?.makeView() ?? MTKView()
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.setNeedsDisplay(view.bounds)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor final class Coordinator {
        let renderer: BendRenderer?
        init(controller: BendEffectController) {
            renderer = try? BendRenderer(frames: controller.previewFrames)
            renderer?.parameters = { [weak controller] in
                controller?.parameters(preview: true) ?? BendParameters()
            }
        }
    }
}

/// Settings/Appearance controls adapted from BendMac's own bespoke Settings
/// window into Atelier's grouped-`Form` pane convention (see
/// `AppearancePane`) -- same controls (enable, style/perspective/blur/
/// shadow, follow-lid vs. manual angle, calibrate, sound), different chrome.
struct BendEffectPane: View {
    @ObservedObject private var controller = BendEffectController.shared
    @AppStorage(AtelierSettings.bendEffectStyleKey) private var style = 0
    @AppStorage(AtelierSettings.bendEffectPerspectiveKey) private var perspective = 1.0
    @AppStorage(AtelierSettings.bendEffectBlurKey) private var blur = 0.9
    @AppStorage(AtelierSettings.bendEffectShadowKey) private var shadow = 0.35
    @AppStorage(AtelierSettings.bendEffectClearAngleKey) private var clearAngle = 105.0
    @AppStorage(AtelierSettings.bendEffectFollowLidKey) private var followLid = true
    @AppStorage(AtelierSettings.bendEffectManualAngleKey) private var manualAngle = 115.0
    @AppStorage(AtelierSettings.bendEffectSoundKey) private var sound = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { controller.wantsEnabled },
                    set: { $0 ? controller.enable() : controller.disable() }
                )) {
                    Text(controller.starting ? "Connecting…" : "Bend the desktop as the lid closes")
                }
                Text(controller.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Needs Screen Recording permission -- see the Permissions pane. Press Escape anytime to pause instantly. Open at login is in the General pane.")
            }

            Section("Preview") {
                BendEffectMetalPreview(controller: controller)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: NotchLayout.cardCornerRadius, style: .continuous))
                    .accessibilityLabel("Animated desktop fold preview")
                HStack {
                    Button {
                        if controller.previewPlaying {
                            controller.previewPlaying = false
                        } else {
                            controller.playPreview()
                        }
                    } label: {
                        Image(systemName: controller.previewPlaying ? "pause.fill" : "play.fill")
                    }
                    .help(controller.previewPlaying ? "Pause preview" : "Play fold preview")
                    .accessibilityLabel(controller.previewPlaying ? "Pause fold preview" : "Play fold preview")
                    Slider(value: $controller.previewAngle, in: 12...135, onEditingChanged: { _ in
                        controller.previewPlaying = false
                    })
                    .disabled(controller.previewFollowsLid)
                    .accessibilityLabel("Preview lid angle")
                    Text("\(Int(controller.displayedPreviewAngle))°")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                Toggle("Use live lid angle", isOn: $controller.previewFollowsLid)
                    .disabled(controller.sensorAngle == nil)
            }

            Section("Appearance") {
                Picker("Style", selection: $style) {
                    Text("Silk").tag(0)
                    Text("Shade").tag(1)
                    Text("Frost").tag(2)
                }
                .pickerStyle(.segmented)
                LabeledContent("Perspective") {
                    HStack {
                        Slider(value: $perspective, in: 0...1) { Text("Perspective") }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        Text(perspective, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                LabeledContent("Blur") {
                    HStack {
                        Slider(value: $blur, in: 0...1) { Text("Blur") }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        Text(blur, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                LabeledContent("Shadow") {
                    HStack {
                        Slider(value: $shadow, in: 0...1) { Text("Shadow") }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        Text(shadow, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                Button("Reset appearance") { controller.resetAppearance() }
            }

            Section {
                LabeledContent("Lid sensor") {
                    Text(controller.sensorAngle.map { "\(Int($0))°" } ?? "Unavailable")
                        .foregroundStyle(.secondary)
                }
                Toggle("Follow physical lid", isOn: $followLid)
                if !followLid {
                    LabeledContent("Desktop angle") {
                        HStack {
                            Slider(value: $manualAngle, in: 12...135) { Text("Desktop angle") }
                                .labelsHidden()
                                .frame(maxWidth: 200)
                            Text("\(Int(manualAngle))°").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Clear at") {
                    HStack {
                        Slider(value: $clearAngle, in: 80...135) { Text("Clear at") }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        Text("\(Int(clearAngle))°").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Use your comfortable viewing position.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use current angle") { controller.calibrateOpenAngle() }
                        .disabled(controller.sensorAngle == nil)
                        .help("Sets the clear angle to your current lid angle, between 80° and 135°.")
                }
                Toggle("Play a soft sound when unfolding finishes", isOn: $sound)
            } header: {
                Text("Lid Behavior")
            } footer: {
                Text("Lid sensor support varies by MacBook model and macOS version. You can always try the preview above.")
            }
        }
        .formStyle(.grouped)
        .onAppear { controller.beginObservingSensor() }
        .onDisappear {
            controller.previewPlaying = false
            controller.endObservingSensor()
        }
    }
}
