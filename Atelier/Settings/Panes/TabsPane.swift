import SwiftUI

/// Enable/disable and reorder in one list, like the System Settings and
/// Shortcuts "drag to reorder" pattern. Every page is listed, disabled ones
/// too, so a hidden tab can be turned back on from here. Home is a locked
/// row: it's always first and can't be turned off.
struct TabsPane: View {
    /// Every non-Home page, in the saved order.
    @State private var order: [NotchPage] = TabsPane.savedOrder()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: NotchPage.home.symbol)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text("Home")
                    Spacer()
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                    .help("Home is always first and can't be turned off")
            }

            Section("Drag to reorder") {
                ForEach(order, id: \.self) { page in
                    TabRow(page: page)
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    AtelierSettings.tabOrder = order.map(\.rawValue)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tabs")
    }

    private static func savedOrder() -> [NotchPage] {
        // Resolve against *all* pages so disabled ones are listed, then drop Home.
        Array(TabOrder.resolve(stored: AtelierSettings.tabOrder, enabled: Set(NotchPage.allCases)).dropFirst())
    }
}

private struct TabRow: View {
    let page: NotchPage
    /// `@AppStorage` (not a hand-rolled `Binding` over `UserDefaults`) so the
    /// switch re-renders when flipped -- same lesson as the old menu toggles.
    @AppStorage private var isEnabled: Bool

    init(page: NotchPage) {
        self.page = page
        _isEnabled = AppStorage(wrappedValue: true, page.enabledKey ?? "")
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 8) {
                // Fixed width so titles line up whatever the symbol's width.
                Image(systemName: page.symbol)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(page.title)
            }
        }
    }
}

private extension NotchPage {
    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "File Shelf"
        case .systemMonitor: "System Monitor"
        case .calendar: "Calendar"
        case .camera: "Camera Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .shelf: "tray"
        case .systemMonitor: "gauge.with.dots.needle.33percent"
        case .calendar: "calendar"
        case .camera: "camera"
        }
    }

    /// `nil` for Home, which has no enable switch.
    var enabledKey: String? {
        switch self {
        case .home: nil
        case .shelf: AtelierSettings.shelfEnabledKey
        case .systemMonitor: AtelierSettings.systemMonitorEnabledKey
        case .calendar: AtelierSettings.calendarEnabledKey
        case .camera: AtelierSettings.cameraEnabledKey
        }
    }
}
