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
struct SettingsView: View {
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralPane()
            case .appearance: AppearancePane()
            case .tabs: TabsPane()
            case .widgets: WidgetsPane()
            case .permissions: PermissionsPane()
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}
