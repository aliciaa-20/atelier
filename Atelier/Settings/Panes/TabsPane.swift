import SwiftUI

/// Enable/disable and reorder in one list, like the System Settings and
/// Shortcuts "drag to reorder" pattern. Every page is listed, disabled ones
/// too, so a hidden tab can be turned back on from here. Home can be moved
/// like the rest but not turned off, so there's always at least one tab.
struct TabsPane: View {
    /// Every page, Home included, in the saved order.
    @State private var order: [NotchPage] = TabsPane.savedOrder()

    /// A `List`, not the grouped `Form` the other panes use: `.onMove`
    /// drag-to-reorder doesn't work in a macOS `Form` (confirmed on-device).
    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { page in
                    Group {
                        if let key = page.enabledKey {
                            ToggleTabRow(page: page, enabledKey: key)
                        } else {
                            HomeTabRow()
                        }
                    }
                    // Dragging is mouse-only; these give VoiceOver and the
                    // keyboard (and a right-click) a way to reorder too.
                    .accessibilityAction(named: "Move Up") { move(page, by: -1) }
                    .accessibilityAction(named: "Move Down") { move(page, by: 1) }
                    .contextMenu {
                        Button("Move Up") { move(page, by: -1) }
                        Button("Move Down") { move(page, by: 1) }
                    }
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            } header: {
                Text("Drag to reorder")
            } footer: {
                Text("The notch opens on the first tab.")
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func move(_ page: NotchPage, by offset: Int) {
        guard let index = order.firstIndex(of: page) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        save()
    }

    private func save() {
        AtelierSettings.tabOrder = order.map(\.rawValue)
    }

    private static func savedOrder() -> [NotchPage] {
        // Resolve against *all* pages so disabled ones are listed too.
        TabOrder.resolve(stored: AtelierSettings.tabOrder, enabled: Set(NotchPage.allCases))
    }
}

/// Fixed-width icon column so titles line up whatever the symbol's width.
private struct TabLabel: View {
    let page: NotchPage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: page.symbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(page.title)
        }
    }
}

private struct ToggleTabRow: View {
    let page: NotchPage
    /// `@AppStorage` (not a hand-rolled `Binding` over `UserDefaults`) so the
    /// switch re-renders when flipped -- same lesson as the old menu toggles.
    @AppStorage private var isEnabled: Bool

    init(page: NotchPage, enabledKey: String) {
        self.page = page
        _isEnabled = AppStorage(wrappedValue: true, enabledKey)
    }

    var body: some View {
        // `.switch` explicitly: a `List` (needed for drag-to-reorder) would
        // otherwise render these as checkboxes.
        Toggle(isOn: $isEnabled) {
            TabLabel(page: page)
        }
        .toggleStyle(.switch)
        .padding(.vertical, 4)
    }
}

private struct HomeTabRow: View {
    var body: some View {
        HStack {
            TabLabel(page: .home)
            Spacer()
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .foregroundStyle(.secondary)
        .help("Home can be moved but not turned off")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Can be moved but not turned off")
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
