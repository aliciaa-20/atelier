# Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the crowded menu-bar settings menu with a native Settings window (sidebar panes), adding launch at login, a permissions status pane, and drag-to-reorder tabs.

**Architecture:** A hand-built `SettingsWindowController` (AppKit) hosts a SwiftUI `NavigationSplitView`; it flips the activation policy to `.regular` while open and back to `.accessory` on close. State stays in `AtelierSettings` (`@AppStorage`), so window and notch stay in sync. Tab order is a pure, unit-tested `TabOrder.resolve` read by the one choke point `NotchTabBar.activePages`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, `SMAppService`, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-24-settings-window-design.md`

## Global Constraints

- Swift 6, strict concurrency; SwiftUI first, AppKit where SwiftUI can't reach.
- Deployment target macOS 26.0.
- **No third-party dependencies.** Launch at login uses `SMAppService.mainApp`.
- Invariant 1: `TabOrder` (in `Notch/`) imports only Foundation.
- Window exists only while open: no timers or pollers; permission re-check is event-driven (`NSApplication.didBecomeActiveNotification`); activation policy reverts to `.accessory` on close.
- Match the surrounding code's comment density and style (comments explain *why*).
- Swift Testing (`import Testing`), not XCTest. Add tests only where this plan says (`TabOrder`); nothing else.
- Icon-only controls get `.help()`; anything bouncy honors Reduce Motion (nothing here animates).
- Build: `xcodebuild -scheme Atelier -configuration Debug build` → `** BUILD SUCCEEDED **`
- Test: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **` (145 tests before this plan)
- New files under `Atelier/` and `AtelierTests/` are picked up automatically (the project uses file-system-synchronized groups); do not edit `project.pbxproj`.
- Work on branch `feat/settings-window`. Commit at the end of each task. Do not push.

## Review Focus

- Saved tab order contains a page that is currently disabled, then it is re-enabled: it should return to its saved position (Task 3 test).
- Saved tab order contains unknown names (a page removed in a later version) or duplicates: ignored, no crash (Task 3 test).
- No tabs enabled at all: the bar still resolves to `[home]` (Task 3 test).
- User toggles Launch at Login off in System Settings while Atelier is running: the toggle reflects the real state on returning to the app, not a stale stored value (Task 2 manual check).
- Permission denied after having been granted (or vice versa) in System Settings: rows update on returning to the app with no restart (Task 4 manual check).

## File Structure

| File | Responsibility |
|---|---|
| `Atelier/Settings/SettingsWindowController.swift` (new) | AppKit shell: lazily creates the window, policy flip, releases on close |
| `Atelier/Settings/SettingsView.swift` (new) | Sidebar + pane switch (`SettingsPane` enum) |
| `Atelier/Settings/Panes/GeneralPane.swift` (new) | Launch at login, peek, gestures |
| `Atelier/Settings/Panes/AppearancePane.swift` (new) | Liquid Glass toggle + intensity |
| `Atelier/Settings/Panes/TabsPane.swift` (new) | Enable + drag-reorder |
| `Atelier/Settings/Panes/WidgetsPane.swift` (new) | Calendar / Camera / Color Picker options |
| `Atelier/Settings/Panes/PermissionsPane.swift` (new) | Permission status rows |
| `Atelier/System/LaunchAtLogin.swift` (new) | `SMAppService.mainApp` wrapper |
| `Atelier/Notch/TabOrder.swift` (new) | Pure ordering logic |
| `AtelierTests/TabOrderTests.swift` (new) | `TabOrder` tests |
| `Atelier/Notch/NotchPage.swift` (modify) | Give the enum `String` raw values |
| `Atelier/AtelierSettings.swift` (modify) | `tabOrderKey`, `tabOrder`, `enabledPages` |
| `Atelier/UI/NotchTabBar.swift` (modify) | `activePages` calls `TabOrder.resolve` |
| `Atelier/AtelierApp.swift` (modify) | Add `Settings…`, later slim the menu |

---

### Task 1: Window shell + `Settings…` menu item

**Files:**
- Create: `Atelier/Settings/SettingsWindowController.swift`
- Create: `Atelier/Settings/SettingsView.swift`
- Modify: `Atelier/AtelierApp.swift` (add a button under the version text)

**Interfaces:**
- Produces: `SettingsWindowController.shared.show()` (`@MainActor`); `SettingsPane` enum with cases `general, appearance, tabs, widgets, permissions`; `SettingsView` (no parameters).

The old menu content stays in this task so every commit keeps every setting reachable. It is slimmed in Task 4.

- [ ] **Step 1: Create the window controller**

`Atelier/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the Settings window. A plain `NSWindow` rather than SwiftUI's
/// `Settings` scene: that scene is unreliable to open and focus from an
/// `LSUIElement` app. The activation-policy flip mirrors what
/// boring.notch and Atoll do -- an accessory app's window won't come to
/// the front or take keyboard focus otherwise.
///
/// The window is created lazily and dropped on close, so nothing of it
/// (hosting view, SwiftUI state) stays in memory while Settings is shut.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        // A Dock icon appears while Settings is open; it goes away on close.
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            window = makeWindow()
            window?.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Atelier Settings"
        // ARC, not AppKit, owns this window's lifetime (see `windowWillClose`).
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window?.delegate = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 2: Create the sidebar shell**

`Atelier/Settings/SettingsView.swift`:

```swift
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
            // Temporary: each pane below is replaced by its real view in
            // Tasks 2-4.
            switch selection ?? .general {
            case .general: Text("General")
            case .appearance: Text("Appearance")
            case .tabs: Text("Tabs")
            case .widgets: Text("Widgets")
            case .permissions: Text("Permissions")
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}
```

- [ ] **Step 3: Add `Settings…` to the menu**

In `Atelier/AtelierApp.swift`, replace

```swift
                Text("Atelier 0.1.0")

                Divider()

                // `Section` (not another bare `Divider()`)
```

with

```swift
                Text("Atelier 0.1.0")

                // ⌘, works while this popover has focus; a global ⌘, would
                // need a real main menu, which an accessory app doesn't have.
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",")

                Divider()

                // `Section` (not another bare `Divider()`)
```

(Keep the rest of that comment block as it is.)

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run the existing tests**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Manual check (Alicia, on device)**

Run `/build`. Click the menu-bar icon → `Settings…`. Expected: a window titled "Atelier Settings" comes to the front with a five-item sidebar; clicking each item changes the detail text; a Dock icon appears while open. Close the window: the Dock icon disappears and the notch still works. Reopen it: works again. Screenshot the window.

- [ ] **Step 7: Commit**

```bash
git add Atelier/Settings Atelier/AtelierApp.swift
git commit -m "feat(settings): window shell with sidebar + Settings… menu item (stage 1)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: General + Appearance panes, launch at login

**Files:**
- Create: `Atelier/System/LaunchAtLogin.swift`
- Create: `Atelier/Settings/Panes/GeneralPane.swift`
- Create: `Atelier/Settings/Panes/AppearancePane.swift`
- Modify: `Atelier/Settings/SettingsView.swift` (detail switch)

**Interfaces:**
- Consumes: `SettingsPane`, `SettingsView` (Task 1); `AtelierSettings.peekOnTrackChangeKey`, `.gesturesEnabledKey`, `.glassEffectEnabledKey`, `.glassIntensityKey` (existing).
- Produces: `LaunchAtLogin.State` (`.enabled, .disabled, .requiresApproval, .unavailable`), `LaunchAtLogin.state`, `LaunchAtLogin.setEnabled(_:) throws`, `LaunchAtLogin.openLoginItemsSettings()`; `GeneralPane`, `AppearancePane` (no parameters).

- [ ] **Step 1: Create the launch-at-login wrapper**

`Atelier/System/LaunchAtLogin.swift`:

```swift
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. The Settings toggle reads
/// `state` live instead of storing a bool: the user can also flip this in
/// System Settings → Login Items, and a stored copy would go stale.
///
/// Caveat: this registers whichever build is running, so a Debug run from
/// Xcode registers the DerivedData copy. Harmless, but odd -- a stable
/// signing identity (ROADMAP Phase 16) is the long-term fix.
enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but macOS wants the user to approve it in Login Items.
        case requiresApproval
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 2: Create the General pane**

`Atelier/Settings/Panes/GeneralPane.swift`:

```swift
import AppKit
import SwiftUI

struct GeneralPane: View {
    @AppStorage(AtelierSettings.peekOnTrackChangeKey) private var peekOnTrackChange = true
    @AppStorage(AtelierSettings.gesturesEnabledKey) private var gesturesEnabled = true

    @State private var launchState = LaunchAtLogin.state
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchBinding)
                if launchState == .requiresApproval {
                    Text("Needs approval in System Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…") {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Behavior") {
                Toggle("Peek on track change", isOn: $peekOnTrackChange)
                Toggle("Enable gestures", isOn: $gesturesEnabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        // Re-read the real state when returning from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchState = LaunchAtLogin.state
        }
    }

    /// "On" while registered-but-awaiting-approval too: the user has asked
    /// for it, and the note below the toggle says what's still needed.
    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchState == .enabled || launchState == .requiresApproval },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
                launchState = LaunchAtLogin.state
            }
        )
    }
}
```

- [ ] **Step 3: Create the Appearance pane**

`Atelier/Settings/Panes/AppearancePane.swift`:

```swift
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
```

- [ ] **Step 4: Wire the panes into the sidebar**

In `Atelier/Settings/SettingsView.swift`, replace

```swift
            case .general: Text("General")
            case .appearance: Text("Appearance")
```

with

```swift
            case .general: GeneralPane()
            case .appearance: AppearancePane()
```

- [ ] **Step 5: Build and run existing tests**

Run: `xcodebuild -scheme Atelier -configuration Debug build` → `** BUILD SUCCEEDED **`
Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **`

- [ ] **Step 6: Manual check (Alicia, on device)**

`/build`, open Settings.
1. General: flip *Peek on track change* and confirm the menu-bar popover's same toggle mirrors it (both read the same key).
2. Flip *Launch at login* on: expect it stays on (or shows "Needs approval…" with an *Open Login Items…* button). Open System Settings → General → Login Items and confirm Atelier is listed; toggle it off *there*, return to Atelier, and confirm the Settings toggle turned off (Review Focus).
3. Appearance: turn Liquid Glass on, drag the slider, confirm the notch changes; turn it off and confirm the slider greys out.
Screenshot both panes.

- [ ] **Step 7: Commit**

```bash
git add Atelier/System/LaunchAtLogin.swift Atelier/Settings
git commit -m "feat(settings): General + Appearance panes, launch at login (stage 2)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Tab order — pure logic, wiring, Tabs pane

**Files:**
- Create: `Atelier/Notch/TabOrder.swift`
- Test: `AtelierTests/TabOrderTests.swift`
- Create: `Atelier/Settings/Panes/TabsPane.swift`
- Modify: `Atelier/Notch/NotchPage.swift:7` (raw type)
- Modify: `Atelier/AtelierSettings.swift` (key + accessors)
- Modify: `Atelier/UI/NotchTabBar.swift:41-56` (`activePages`)
- Modify: `Atelier/Settings/SettingsView.swift` (detail switch)

**Interfaces:**
- Consumes: `NotchPage` cases `home, shelf, systemMonitor, calendar, camera`; the existing `AtelierSettings.*EnabledKey`s.
- Produces: `NotchPage: String` (raw value = case name, e.g. `"systemMonitor"`); `TabOrder.resolve(stored: [String], enabled: Set<NotchPage>) -> [NotchPage]`; `AtelierSettings.tabOrderKey`, `AtelierSettings.tabOrder: [String]` (get/set), `AtelierSettings.enabledPages: Set<NotchPage>`; `TabsPane`.

- [ ] **Step 1: Write the failing tests**

`AtelierTests/TabOrderTests.swift`:

```swift
import Testing
@testable import Atelier

struct TabOrderTests {
    private let all = Set(NotchPage.allCases)

    @Test func emptyStoredOrderGivesTheDefaultOrder() {
        let result = TabOrder.resolve(stored: [], enabled: all)

        #expect(result == [.home, .shelf, .systemMonitor, .calendar, .camera])
    }

    @Test func followsTheStoredOrder() {
        let result = TabOrder.resolve(stored: ["camera", "calendar", "shelf", "systemMonitor"], enabled: all)

        #expect(result == [.home, .camera, .calendar, .shelf, .systemMonitor])
    }

    @Test func homeIsAlwaysFirstEvenIfStoredElsewhere() {
        let result = TabOrder.resolve(stored: ["camera", "home", "shelf"], enabled: all)

        #expect(result.first == .home)
        #expect(result.filter { $0 == .home }.count == 1)
    }

    @Test func disabledPagesAreSkipped() {
        let enabled: Set<NotchPage> = [.home, .camera]

        let result = TabOrder.resolve(stored: ["shelf", "camera"], enabled: enabled)

        #expect(result == [.home, .camera])
    }

    @Test func unknownNamesAndDuplicatesAreIgnored() {
        let result = TabOrder.resolve(stored: ["bogus", "camera", "camera", "shelf"], enabled: all)

        #expect(result == [.home, .camera, .shelf, .systemMonitor, .calendar])
    }

    @Test func aPageMissingFromTheStoredListIsAppendedInDefaultOrder() {
        let result = TabOrder.resolve(stored: ["camera", "shelf"], enabled: all)

        #expect(result == [.home, .camera, .shelf, .systemMonitor, .calendar])
    }

    @Test func aDisabledPageKeepsItsSavedPositionWhenReEnabled() {
        let stored = ["camera", "shelf", "systemMonitor", "calendar"]

        let whileDisabled = TabOrder.resolve(stored: stored, enabled: all.subtracting([.camera]))
        let afterReEnable = TabOrder.resolve(stored: stored, enabled: all)

        #expect(whileDisabled == [.home, .shelf, .systemMonitor, .calendar])
        #expect(afterReEnable == [.home, .camera, .shelf, .systemMonitor, .calendar])
    }

    @Test func noEnabledPagesStillResolvesToHome() {
        let result = TabOrder.resolve(stored: ["camera", "shelf"], enabled: [])

        #expect(result == [.home])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TabOrderTests`
Expected: build FAIL ("cannot find 'TabOrder' in scope").

- [ ] **Step 3: Give `NotchPage` raw values**

In `Atelier/Notch/NotchPage.swift`, change

```swift
enum NotchPage: Hashable, CaseIterable {
```

to

```swift
enum NotchPage: String, Hashable, CaseIterable {
```

(Raw values are the case names. They're what `TabOrder` persists, so adding a page later can't scramble a saved order. Do not rename cases without a migration.)

- [ ] **Step 4: Implement `TabOrder`**

`Atelier/Notch/TabOrder.swift`:

```swift
import Foundation

/// Decides which tabs show, and in what order. Pure: no `UserDefaults`, no
/// AppKit (Invariant 1) -- callers pass the stored order and the enabled set in.
enum TabOrder {
    /// - Home is always first, whatever `stored` says (the notch always
    ///   reopens on Home; `NotchPageTransition` relies on it).
    /// - Enabled pages follow `stored`; unknown names and duplicates are
    ///   skipped, so a page removed in a later version can't break anything.
    /// - Enabled pages missing from `stored` (e.g. a page added in a later
    ///   version) are appended in `NotchPage.allCases` order. An empty
    ///   `stored` therefore gives the original, pre-Settings order.
    /// - `stored` is never pruned by this function: a disabled page keeps
    ///   its saved position for when it's re-enabled.
    static func resolve(stored: [String], enabled: Set<NotchPage>) -> [NotchPage] {
        var result: [NotchPage] = [.home]
        var placed: Set<NotchPage> = [.home]

        for name in stored {
            guard let page = NotchPage(rawValue: name),
                  enabled.contains(page),
                  placed.insert(page).inserted
            else { continue }
            result.append(page)
        }

        for page in NotchPage.allCases where enabled.contains(page) && !placed.contains(page) {
            result.append(page)
        }
        return result
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/TabOrderTests`
Expected: 8 tests pass.

- [ ] **Step 6: Add the settings accessors**

In `Atelier/AtelierSettings.swift`, add after `static let glassIntensityKey = "glassIntensity"`:

```swift
    static let tabOrderKey = "tabOrder"
```

and add before the final closing brace of the enum:

```swift
    /// Page raw names in the user's preferred order; empty = default order.
    /// Kept in full (disabled pages included) so a re-enabled tab returns to
    /// its saved slot -- see `TabOrder.resolve`.
    static var tabOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: tabOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: tabOrderKey) }
    }

    /// Home is always enabled; the rest follow their own settings.
    static var enabledPages: Set<NotchPage> {
        var pages: Set<NotchPage> = [.home]
        if shelfEnabled { pages.insert(.shelf) }
        if systemMonitorEnabled { pages.insert(.systemMonitor) }
        if calendarEnabled { pages.insert(.calendar) }
        if cameraEnabled { pages.insert(.camera) }
        return pages
    }
```

- [ ] **Step 7: Route `activePages` through `TabOrder`**

In `Atelier/UI/NotchTabBar.swift`, replace the body of `activePages`:

```swift
    static var activePages: [NotchPage] {
        var pages: [NotchPage] = [.home]
        if AtelierSettings.shelfEnabled {
            pages.append(.shelf)
        }
        if AtelierSettings.systemMonitorEnabled {
            pages.append(.systemMonitor)
        }
        if AtelierSettings.calendarEnabled {
            pages.append(.calendar)
        }
        if AtelierSettings.cameraEnabled {
            pages.append(.camera)
        }
        return pages
    }
```

with

```swift
    static var activePages: [NotchPage] {
        TabOrder.resolve(stored: AtelierSettings.tabOrder, enabled: AtelierSettings.enabledPages)
    }
```

(Keep the doc comment above it.)

- [ ] **Step 8: Create the Tabs pane**

`Atelier/Settings/Panes/TabsPane.swift`:

```swift
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
                Label("Home", systemImage: NotchPage.home.symbol)
                    .badge(Text(Image(systemName: "lock.fill")))
                    .foregroundStyle(.secondary)
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
            Label(page.title, systemImage: page.symbol)
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
```

- [ ] **Step 9: Wire the pane into the sidebar**

In `Atelier/Settings/SettingsView.swift`, replace `case .tabs: Text("Tabs")` with `case .tabs: TabsPane()`.

- [ ] **Step 10: Build and run the full test suite**

Run: `xcodebuild -scheme Atelier -configuration Debug build` → `** BUILD SUCCEEDED **`
Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **` (153 tests: 145 + 8)

- [ ] **Step 11: Manual check (Alicia, on device)**

`/build`, open Settings → Tabs.
1. With no changes, hover the notch: the dots are in today's order.
2. Drag *Camera Mirror* to the top of the list; hover the notch: the camera dot is now second (after Home).
3. Turn *Calendar* off: its dot disappears. Turn it back on: it returns to its saved position.
4. Quit and relaunch Atelier: the order persisted.
Screenshot the Tabs pane and the notch dot row.

- [ ] **Step 12: Commit**

```bash
git add Atelier AtelierTests
git commit -m "feat(settings): reorderable tabs — TabOrder + Tabs pane (stage 3)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Widgets + Permissions panes, slim menu

**Files:**
- Create: `Atelier/Settings/Panes/WidgetsPane.swift`
- Create: `Atelier/Settings/Panes/PermissionsPane.swift`
- Modify: `Atelier/Settings/SettingsView.swift` (detail switch; the temporary placeholders go away)
- Modify: `Atelier/AtelierApp.swift` (slim the menu)

**Interfaces:**
- Consumes: `AccessibilityPermission.isGranted` / `.openSystemSettings()`; `CalendarPermission.status: EKAuthorizationStatus` / `.openSystemSettings()`; `CameraPermission.status: AVAuthorizationStatus` / `.requestAccess() async -> Bool` / `.openSystemSettings()`; `LocationPermission.status: CLAuthorizationStatus` / `.openSystemSettings()`; `CalendarAppLauncher.displayName(for:)`, `.chooseApp() -> String?`, `.defaultBundleID`; the `AtelierSettings` keys for calendar swipe/app, camera hold-open, color picker.
- Produces: `WidgetsPane`, `PermissionsPane` (no parameters).

- [ ] **Step 1: Create the Widgets pane**

`Atelier/Settings/Panes/WidgetsPane.swift`:

```swift
import SwiftUI

/// Per-widget options. Whether a tab exists at all is on the Tabs pane; the
/// options here are greyed out (not hidden) while their tab is off, so the
/// layout doesn't jump. Own sections replace the old menu's indented
/// sub-toggles.
struct WidgetsPane: View {
    @AppStorage(AtelierSettings.calendarEnabledKey) private var calendarEnabled = true
    @AppStorage(AtelierSettings.calendarScrollSwipeKey) private var calendarScrollSwipe = true
    @AppStorage(AtelierSettings.calendarAppBundleIDKey) private var calendarAppBundleID = CalendarAppLauncher.defaultBundleID
    @AppStorage(AtelierSettings.cameraEnabledKey) private var cameraEnabled = true
    @AppStorage(AtelierSettings.cameraHoldOpenKey) private var cameraHoldOpen = false
    @AppStorage(AtelierSettings.colorPickerEnabledKey) private var colorPickerEnabled = true

    var body: some View {
        Form {
            Section("Calendar") {
                Toggle("Scroll-style week swipe", isOn: $calendarScrollSwipe)
                LabeledContent("Opens in") {
                    Button(CalendarAppLauncher.displayName(for: calendarAppBundleID) + "…") {
                        if let id = CalendarAppLauncher.chooseApp() { calendarAppBundleID = id }
                    }
                }
            }
            .disabled(!calendarEnabled)

            Section("Camera") {
                Toggle("Keep notch open while the mirror is on", isOn: $cameraHoldOpen)
            }
            .disabled(!cameraEnabled)

            Section("Color Picker") {
                Toggle("Enable Color Picker", isOn: $colorPickerEnabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Widgets")
    }
}
```

- [ ] **Step 2: Create the Permissions pane**

`Atelier/Settings/Panes/PermissionsPane.swift`:

```swift
import AppKit
import AVFoundation
import CoreLocation
import EventKit
import SwiftUI

enum PermissionState {
    case granted
    case notDetermined
    case denied

    var text: String {
        switch self {
        case .granted: "Granted"
        case .notDetermined: "Not asked yet"
        case .denied: "Denied"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .notDetermined: .secondary
        case .denied: .red
        }
    }
}

/// Read fresh from the OS every time (never cached) -- the user can change
/// any of these in System Settings while Atelier is running.
private struct PermissionSnapshot {
    let accessibility: PermissionState
    let calendar: PermissionState
    let camera: PermissionState
    let location: PermissionState

    static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AccessibilityPermission.isGranted ? .granted : .denied,
            calendar: {
                switch CalendarPermission.status {
                case .fullAccess: .granted
                case .notDetermined: .notDetermined
                default: .denied  // denied, restricted, or write-only (we read events)
                }
            }(),
            camera: {
                switch CameraPermission.status {
                case .authorized: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }(),
            location: {
                switch LocationPermission.status {
                case .authorizedAlways: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }()
        )
    }
}

struct PermissionsPane: View {
    @State private var snapshot = PermissionSnapshot.current()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Volume and brightness keys",
                    state: snapshot.accessibility,
                    openSettings: AccessibilityPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Calendar",
                    detail: "Events in the Calendar tab",
                    state: snapshot.calendar,
                    notAskedHint: "Open the Calendar tab to be asked.",
                    openSettings: CalendarPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Camera",
                    detail: "The mirror in the Camera tab",
                    state: snapshot.camera,
                    grant: {
                        _ = await CameraPermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: CameraPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Location",
                    detail: "Local weather",
                    state: snapshot.location,
                    notAskedHint: "Open the Weather view on Home to be asked.",
                    openSettings: LocationPermission.openSystemSettings
                )
            } footer: {
                Text("Changes you make in System Settings show up here when you come back to Atelier.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            snapshot = .current()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    /// Shown in place of a button when there's no in-app way to trigger the
    /// system prompt from here (only Camera has a ready request helper).
    var notAskedHint: String?
    var grant: (() async -> Void)?
    let openSettings: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(state.text)
                    .foregroundStyle(state.color)
                action
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // One VoiceOver element per row: "Camera, The mirror…, Granted".
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .granted:
            EmptyView()
        case .denied:
            Button("Open System Settings…", action: openSettings)
        case .notDetermined:
            if let grant {
                Button("Grant Access") { Task { await grant() } }
            } else if let notAskedHint {
                Text(notAskedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

Note: `.accessibilityElement(children: .combine)` merges the row's buttons into one element, which can hide the button from VoiceOver. If manual VoiceOver checking shows that, drop `.combine` and use `.accessibilityElement(children: .contain)` instead.

- [ ] **Step 3: Replace the remaining placeholders**

In `Atelier/Settings/SettingsView.swift`, replace the whole detail `switch`, including its "Temporary" comment, with:

```swift
            switch selection ?? .general {
            case .general: GeneralPane()
            case .appearance: AppearancePane()
            case .tabs: TabsPane()
            case .widgets: WidgetsPane()
            case .permissions: PermissionsPane()
            }
```

- [ ] **Step 4: Slim the menu**

In `Atelier/AtelierApp.swift`:

1. Delete every `@AppStorage` property **except** `colorPickerEnabled` (it gates "Pick a Color…"); also delete the long doc comment above them (it explains the properties being removed, and now lives on in the panes).
2. Replace the whole `VStack { … }` popover content and the trailing `.menuBarExtraStyle` comment so `body` reads:

```swift
    var body: some Scene {
        MenuBarExtra(
            "Atelier",
            systemImage: "rectangle.topthird.inset.filled",
            isInserted: .constant(!Self.isRunningTests)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Atelier 0.1.0")

                Divider()

                // ⌘, works while this popover has focus; a global ⌘, would
                // need a real main menu, which an accessory app doesn't have.
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",")

                // An action, not a setting, so it stays here. Hidden once
                // turned off (Widgets pane), same "no leftover way in"
                // reasoning as before.
                if colorPickerEnabled {
                    Button("Pick a Color…") {
                        notchController?.pickColor()
                    }
                }

                Divider()

                Button("Quit Atelier") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(12)
            .frame(width: 200)
        }
        .menuBarExtraStyle(.window)
    }
```

- [ ] **Step 5: Build and run the tests**

Run: `xcodebuild -scheme Atelier -configuration Debug build` → `** BUILD SUCCEEDED **`
Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **` (153 tests)

- [ ] **Step 6: Manual check (Alicia, on device)**

`/build`.
1. Menu popover shows only: version, Settings…, Pick a Color… (while enabled), Quit. Nothing is truncated.
2. Widgets pane: turn Calendar off in Tabs and confirm the Calendar section greys out; turn Color Picker off and confirm "Pick a Color…" leaves the menu.
3. Permissions pane: the four rows match reality. Cross-check each against System Settings → Privacy & Security. Revoke Camera in System Settings, come back: the row updates to Denied with no relaunch (Review Focus). Click *Open System Settings…* and confirm it lands on the right page.
4. VoiceOver (⌘F5) on the Permissions pane: each row reads title, detail, state; the buttons are still reachable.
Screenshots of the popover and all five panes (per the "every tab" lesson).

- [ ] **Step 7: Commit**

```bash
git add Atelier
git commit -m "feat(settings): Widgets + Permissions panes, slim menu (stage 4)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Reorderable Home (own design pass first)

**Files:** decided by the design pass. Expected: `Atelier/Notch/TabOrder.swift`, `Atelier/Notch/NotchPage.swift` (`NotchPageTransition`), `Atelier/Settings/Panes/TabsPane.swift`, `AtelierTests/NotchPageTransitionTests.swift`, `AtelierTests/TabOrderTests.swift`.

**Interfaces:**
- Consumes: `TabOrder.resolve(stored:enabled:)` (Task 3), `NotchPageTransition.page(for:currentPage:)`, `NotchTabBar.activePages`.

The spec deliberately holds this back: Home being first is baked into `NotchPageTransition` ("collapsed/pill → `.home`"), which several tests pin, so it needs its own short design before code.

- [ ] **Step 1: Read what depends on "Home is first"**

Run: `grep -rn "\.home" Atelier --include='*.swift'` and read `NotchPageTransition` and its tests. List every place that assumes Home is index 0 or is the "reset" page.

- [ ] **Step 2: Present a short in-chat design to Alicia and wait for a yes**

It must answer: (a) does "always reopens on Home" become "reopens on the first tab" or stay "Home wherever it sits"? (b) can Home be disabled, and if not, how does the Tabs pane show it? (c) what does `TabOrder.resolve` return when Home is mid-list, and which existing tests change?

- [ ] **Step 3: Implement the approved design test-first**

Update `TabOrderTests` / `NotchPageTransitionTests` for the changed rule first, watch them fail, then change `TabOrder` / `NotchPageTransition` / `TabsPane` (unlock the Home row) to pass.

- [ ] **Step 4: Build, run all tests, manual check, commit**

Run: `xcodebuild -scheme Atelier -configuration Debug build` → `** BUILD SUCCEEDED **`
Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **`
Manual: drag Home to a different slot in Settings → Tabs; hover the notch, collapse and reopen, and confirm it opens on the page the approved design says.

```bash
git add Atelier AtelierTests
git commit -m "feat(settings): reorderable Home tab (stage 5)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Docs

**Files:**
- Create: `docs/decisions/0018-settings-window-own-nswindow-activation-policy.md`
- Modify: `README.md`, `docs/FEATURES.md`, `docs/ROADMAP.md` (Phase 16), `CLAUDE.md` (Architecture table), `STAGES.md`

- [ ] **Step 1: Write the ADR**

`docs/decisions/0018-settings-window-own-nswindow-activation-policy.md`:

```markdown
# ADR 0018 — Settings window: our own NSWindow + activation-policy flip

## Context

Atelier is `LSUIElement` (no Dock icon), and its settings had outgrown a
menu-bar popover (truncated labels, no room for launch-at-login or
permission status). SwiftUI's `Settings` scene / `SettingsLink` is unreliable
to open and focus from an accessory app.

## Decision

`SettingsWindowController` creates a plain `NSWindow` hosting a SwiftUI
`NavigationSplitView` (sidebar of panes, grouped `Form`s, instant apply). It
sets `NSApp.setActivationPolicy(.regular)` when shown and `.accessory` again
on close, as boring.notch and Atoll do. The window is created on open and
released on close, so nothing of it stays in memory while it's shut.

Tab order is a persisted list of page names resolved by the pure
`TabOrder.resolve`, read by `NotchTabBar.activePages`. Names, not indices, so
a page added later can't scramble a saved order. Launch at login uses
`SMAppService.mainApp` (no third-party package); its state is read live.

## Consequences

- A Dock icon appears while Settings is open. Accepted: it's the price of a
  window that reliably takes focus.
- ⌘, works only while the menu popover has focus; a global ⌘, would need a
  real main menu.
- A Debug run registers the DerivedData build for launch at login; stable
  signing (ROADMAP Phase 16) is the long-term fix.
- "Not asked yet" for Calendar and Location has no button here: only Camera
  has a request helper; the others prompt from their own tab.
```

- [ ] **Step 2: Update the docs**

- `README.md`: add a Settings section (Settings… in the menu-bar popover, the five panes, drag to reorder tabs, launch at login) and, next to the existing permissions table row for Camera (line ~75), a note that the Permissions pane shows all four statuses.
- `docs/FEATURES.md`: add a short "Settings window" entry stating what shipped and that the window, launch at login and permission rows are manually verified only.
- `docs/ROADMAP.md` Phase 16: tick "Settings window" and "Launch at login" and the two "Parked from the 2026-09-24 UI review" items *except* the template icon (still open); keep "Automation-permission UX" and "Stable signing" unticked, and note Automation is deferred because TCC only reveals its state by trying. Change the phase heading marker to ⬜→🔶 only if the roadmap uses that convention for partial phases; otherwise leave the heading.
- `CLAUDE.md`: add an Architecture-table row: `| Settings | Settings/*.swift, Settings/Panes/*.swift, System/LaunchAtLogin.swift | SettingsWindowController (own NSWindow, activation-policy flip, ADR 0018), SwiftUI sidebar + panes, manual-verification only; TabOrder in Notch/ is pure and unit-tested |`; add `Notch/TabOrder.swift` to the "Pure logic" row; add "no Settings scene" to the reasons list only if the file already lists such rationale.
- `STAGES.md`: replace its contents with a "Settings window (Phase 16)" stage list mirroring Tasks 1-6 with ✅ per finished stage.

- [ ] **Step 3: Run the tests, then commit**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'` → `** TEST SUCCEEDED **`

```bash
git add docs README.md CLAUDE.md STAGES.md
git commit -m "docs(settings): ADR 0018, README, FEATURES, ROADMAP, CLAUDE.md, STAGES (stage 6)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Stop before pushing**

Do not push. The `pre-push-docs-sync` skill runs first, and Alicia is asked before anything goes to a remote.
