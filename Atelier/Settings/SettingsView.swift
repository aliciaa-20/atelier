import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case tabs = "Tabs"
    case widgets = "Widgets"
    case permissions = "Permissions"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .tabs: "rectangle.3.group"
        case .widgets: "square.grid.2x2"
        case .permissions: "hand.raised"
        }
    }
}

/// Apple's Settings layout: a sidebar of panes, each pane a grouped `Form`
/// that applies changes instantly (no Save button).
///
/// A plain sidebar `List` beside the pane, not `NavigationSplitView`: that
/// merges with the window toolbar and adds a blurred scroll-edge band that
/// panes scrolled underneath on load, hiding their first section. With no
/// toolbar there is no band, so nothing can hide.
struct SettingsView: View {
    @State private var selection: SettingsPane? = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch selection ?? .general {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .tabs: TabsPane()
                case .widgets: WidgetsPane()
                case .permissions: PermissionsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}
