import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case tabs = "Tabs"
    case widgets = "Widgets"
    case teleprompter = "Teleprompter"
    case permissions = "Permissions"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .tabs: "rectangle.3.group"
        case .widgets: "square.grid.2x2"
        case .teleprompter: "text.alignleft"
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
extension Notification.Name {
    /// Posted with a `SettingsPane` as the object to switch an already-open
    /// Settings window to that pane.
    static let atelierSelectSettingsPane = Notification.Name("AtelierSelectSettingsPane")
}

struct SettingsView: View {
    @State private var selection: SettingsPane?

    init(initialPane: SettingsPane = .general) {
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Non-optional binding: clicking empty sidebar space would otherwise
            // deselect and leave no row highlighted.
            List(SettingsPane.allCases, selection: Binding(
                get: { selection },
                set: { if let pane = $0 { selection = pane } }
            )) { pane in
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
                case .teleprompter: TeleprompterPane()
                case .permissions: PermissionsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 420)
        .onReceive(NotificationCenter.default.publisher(for: .atelierSelectSettingsPane)) { note in
            if let pane = note.object as? SettingsPane { selection = pane }
        }
    }
}
