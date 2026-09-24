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
                LabeledContent("Transparency") {
                    Slider(value: $glassIntensity, in: 0...1) {
                        Text("Glass transparency")
                    }
                    .frame(maxWidth: 220)
                }
                .disabled(!glassEffectEnabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}
