import SwiftUI

struct AppearancePane: View {
    @AppStorage(AtelierSettings.glassEffectEnabledKey) private var glassEffectEnabled = false
    @AppStorage(AtelierSettings.glassIntensityKey) private var glassIntensity = 0.7

    var body: some View {
        Form {
            Section {
                Toggle("Liquid Glass effect", isOn: $glassEffectEnabled)
                // Disabled rather than hidden: the window is big enough that
                // a greyed control doesn't jump the layout, and it shows
                // the setting exists.
                //
                // Relabeled from "Transparency" -- see ADR 0023. This no
                // longer fades the glass material itself (that read as
                // faint/ghosted corners and "just transparency," not glass);
                // it now drives a dark dimming layer on top, Apple's own
                // documented technique for legibility over bright content.
                // 0 = clearest glass, higher = more dimmed/opaque-looking.
                LabeledContent("Dimming") {
                    Slider(value: $glassIntensity, in: 0...1) {
                        Text("Glass dimming")
                    }
                    // The label is for VoiceOver; the row's own label already
                    // shows "Dimming".
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                .disabled(!glassEffectEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
