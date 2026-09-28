import Foundation

/// Small `UserDefaults`-backed settings, checked directly rather than
/// injected — there's no dedicated Settings window yet (planned for a
/// later phase), just a menu-bar toggle. Registers its own defaults so a
/// fresh install starts with peek enabled rather than reading `false`.
enum AtelierSettings {
    static let peekOnTrackChangeKey = "peekOnTrackChangeEnabled"
    static let gesturesEnabledKey = "gesturesEnabled"
    static let shelfEnabledKey = "shelfEnabled"
    static let systemMonitorEnabledKey = "systemMonitorEnabled"
    static let calendarEnabledKey = "calendarEnabled"
    static let cameraEnabledKey = "cameraEnabled"
    static let cameraHoldOpenKey = "cameraHoldOpen"
    static let teleprompterEnabledKey = "teleprompterEnabled"
    static let teleprompterWPMKey = "teleprompterWPM"
    static let teleprompterMonoFontKey = "teleprompterMonoFont"
    static let teleprompterFontSizeKey = "teleprompterFontSize"
    static let teleprompterPauseOnHoverKey = "teleprompterPauseOnHover"
    static let teleprompterHotkeysKey = "teleprompterHotkeys"
    static let ghostModeKey = "ghostMode"
    static let teleprompterControlOrderKey = "teleprompterControlOrder"
    static let teleprompterVoiceSyncKey = "teleprompterVoiceSync"
    static let hiddenCalendarIDsKey = "hiddenCalendarIDs"
    static let calendarAppBundleIDKey = "calendarAppBundleID"
    static let calendarScrollSwipeKey = "calendarScrollSwipe"
    static let colorPickerEnabledKey = "colorPickerEnabled"
    static let glassEffectEnabledKey = "glassEffectEnabled"
    static let glassIntensityKey = "glassIntensity"
    static let tabOrderKey = "tabOrder"
    static let nowPlayingSwipeSkipKey = "nowPlayingSwipeSkip"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            peekOnTrackChangeKey: true,
            gesturesEnabledKey: true,
            shelfEnabledKey: true,
            systemMonitorEnabledKey: true,
            calendarEnabledKey: true,
            cameraEnabledKey: true,
            teleprompterEnabledKey: true,
            teleprompterWPMKey: TeleprompterScroll.defaultWPM,
            teleprompterFontSizeKey: 15.0,
            teleprompterPauseOnHoverKey: true,
            calendarScrollSwipeKey: true,
            calendarAppBundleIDKey: CalendarAppLauncher.defaultBundleID,
            colorPickerEnabledKey: true,
            // Off by default -- ships conservatively (today's flat-black
            // look) until a user opts in, rather than changing the
            // default notch appearance out from under an existing install.
            glassEffectEnabledKey: false,
            // Low by default -- see ADR 0023. This drives a dark dimming
            // layer now, not the material's own opacity, so a low default
            // lets the glass read at close to full clarity out of the box;
            // raise it only if a bright wallpaper washes out legibility.
            glassIntensityKey: 0.25,
            // On by default -- this is existing behavior (swipe-to-skip
            // already shipped tied only to the master `gesturesEnabled`
            // toggle); this setting exists to let someone turn it off
            // independently, not to opt newcomers in.
            nowPlayingSwipeSkipKey: true
        ])
    }

    static var peekOnTrackChangeEnabled: Bool {
        UserDefaults.standard.bool(forKey: peekOnTrackChangeKey)
    }

    static var gesturesEnabled: Bool {
        UserDefaults.standard.bool(forKey: gesturesEnabledKey)
    }

    /// Gates both the Shelf tab's visibility and whether a file drag is
    /// even allowed to open it (`NotchDragModifier`'s `onDragEntered` in
    /// `NotchRootView`) -- per ADR 0011, a disabled feature shouldn't have
    /// a leftover way in via drag-and-drop just because its tab is hidden.
    static var shelfEnabled: Bool {
        UserDefaults.standard.bool(forKey: shelfEnabledKey)
    }

    /// Gates the System Monitor tab's visibility and, per the same
    /// lightweight-by-design reasoning `shelfEnabled`'s own drag-and-drop
    /// gating documents, `SystemMonitorSource`'s poll loop itself --
    /// disabled means no Mach syscalls every 4s, not just a hidden tab.
    static var systemMonitorEnabled: Bool {
        UserDefaults.standard.bool(forKey: systemMonitorEnabledKey)
    }

    /// Gates the Calendar tab's visibility. Read-only EventKit, so the
    /// only cost when off is the tab -- no permission prompt is raised
    /// until the tab is actually opened.
    static var calendarEnabled: Bool {
        UserDefaults.standard.bool(forKey: calendarEnabledKey)
    }

    /// Scroll-style week swipe (selection follows the finger day-by-day) vs.
    /// the original one-swipe-one-week. On by default while it's being tried
    /// out; off restores the discrete swipe exactly.
    static var cameraEnabled: Bool {
        UserDefaults.standard.bool(forKey: cameraEnabledKey)
    }

    static var cameraHoldOpen: Bool {
        UserDefaults.standard.bool(forKey: cameraHoldOpenKey)
    }

    static var teleprompterEnabled: Bool {
        UserDefaults.standard.bool(forKey: teleprompterEnabledKey)
    }

    /// Falls back to the default rather than 0 if defaults were never
    /// registered (unit tests that don't launch `AtelierApp`).
    static var teleprompterWPM: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: teleprompterWPMKey)
            return stored == 0 ? TeleprompterScroll.defaultWPM : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: teleprompterWPMKey) }
    }

    /// Sans bold is the default; mono is a Settings option.
    static var teleprompterMonoFont: Bool {
        UserDefaults.standard.bool(forKey: teleprompterMonoFontKey)
    }

    static var teleprompterFontSize: Double {
        let stored = UserDefaults.standard.double(forKey: teleprompterFontSizeKey)
        return stored == 0 ? 15 : stored
    }

    /// Pause while the pointer is over the notch, resume when it leaves.
    static var teleprompterPauseOnHover: Bool {
        UserDefaults.standard.bool(forKey: teleprompterPauseOnHoverKey)
    }

    /// Off by default: global shortcuts take keys from other apps, so
    /// they're opt-in.
    static var teleprompterHotkeysEnabled: Bool {
        UserDefaults.standard.bool(forKey: teleprompterHotkeysKey)
    }

    /// Order of the teleprompter's top-bar controls plus the "notch" marker,
    /// comma-separated (a string so `@AppStorage` observes it live); resolved
    /// by the pure `TeleprompterControlLayout`. Empty = default order.
    static var teleprompterControlOrder: [String] {
        get { (UserDefaults.standard.string(forKey: teleprompterControlOrderKey) ?? "").split(separator: ",").map(String.init) }
        set { UserDefaults.standard.set(newValue.joined(separator: ","), forKey: teleprompterControlOrderKey) }
    }

    /// Voice sync: the script follows the speaker's voice. Off by default
    /// (it uses the microphone and on-device speech recognition).
    static var teleprompterVoiceSync: Bool {
        get { UserDefaults.standard.bool(forKey: teleprompterVoiceSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: teleprompterVoiceSyncKey) }
    }

    /// Hides the whole notch panel from screen sharing and recording
    /// (`NSWindow.sharingType = .none`, applied by `NotchController`).
    static var ghostModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: ghostModeKey)
    }

    static var calendarScrollSwipeEnabled: Bool {
        UserDefaults.standard.bool(forKey: calendarScrollSwipeKey)
    }

    /// Bundle ID of the app the Calendar tab opens (default Calendar.app).
    static var calendarAppBundleID: String {
        UserDefaults.standard.string(forKey: calendarAppBundleIDKey) ?? CalendarAppLauncher.defaultBundleID
    }

    /// Calendar IDs the user hid from the Calendar tab. A *hidden* list, not
    /// a shown list, so a newly created calendar appears by default.
    /// EventKit doesn't expose Calendar.app's own sidebar checkboxes, so
    /// this is Atelier's own filter.
    static var hiddenCalendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenCalendarIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenCalendarIDsKey) }
    }

    /// Gates both the "Pick a Color..." menu item's visibility and
    /// `NotchController.pickColor()` itself -- same "no leftover way in
    /// once disabled" reasoning as `shelfEnabled` above, in case something
    /// else ever calls `pickColor()` besides that one menu item.
    static var colorPickerEnabled: Bool {
        UserDefaults.standard.bool(forKey: colorPickerEnabledKey)
    }

    /// Gates `NotchRootView.usesGlassBackground` -- whether `.expanded`/
    /// `.peeking`/`.shelf` render as Liquid Glass at all, vs. staying flat
    /// black everywhere (today's look). A user-facing toggle, not just a
    /// dev flag, since the material has real tradeoffs (see `glassIntensity`)
    /// some users may not want.
    static var glassEffectEnabled: Bool {
        UserDefaults.standard.bool(forKey: glassEffectEnabledKey)
    }

    /// Drives a dark dimming overlay on top of the glass material (Apple's
    /// own documented technique for legibility over bright content), not
    /// the material's own opacity -- see ADR 0023. Fading the material
    /// itself (the original approach) read as faint/ghosted at the corners
    /// and as plain transparency rather than glass. 0 is the clearest
    /// glass, 1 the most dimmed/opaque-looking.
    static var glassIntensity: Double {
        UserDefaults.standard.double(forKey: glassIntensityKey)
    }

    /// Horizontal swipe to skip next/previous track, on the main notch panel
    /// (any page except Calendar, which uses horizontal swipe for week
    /// navigation instead) and the lock-screen card. Independent of the
    /// master `gesturesEnabled` toggle so hover open/close can stay on while
    /// this is switched off (found via a ui-review-tahoe follow-up: it
    /// shipped always-on with no way to disable just this part).
    static var nowPlayingSwipeSkipEnabled: Bool {
        UserDefaults.standard.bool(forKey: nowPlayingSwipeSkipKey)
    }

    /// Page raw names in the user's preferred order; empty = default order.
    /// Kept in full (disabled pages included) so a re-enabled tab returns to
    /// its saved slot -- see `TabOrder.resolve`.
    static var tabOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: tabOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: tabOrderKey) }
    }

    /// The tab the notch opens on: first in the user's order (Home by default).
    static var firstPage: NotchPage {
        TabOrder.resolve(stored: tabOrder, enabled: enabledPages).first ?? .home
    }

    /// Home is always enabled; the rest follow their own settings.
    static var enabledPages: Set<NotchPage> {
        var pages: Set<NotchPage> = [.home]
        if shelfEnabled { pages.insert(.shelf) }
        if systemMonitorEnabled { pages.insert(.systemMonitor) }
        if calendarEnabled { pages.insert(.calendar) }
        if cameraEnabled { pages.insert(.camera) }
        if teleprompterEnabled { pages.insert(.teleprompter) }
        return pages
    }
}
