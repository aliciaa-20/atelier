import AppKit
import os

/// Delegates a window into a private CGS "space" at the exact level
/// Notification Center uses to draw over the lock screen, letting it
/// render above the lock/login screen shield -- a private, undocumented
/// mechanism with no Apple guarantee across OS versions.
///
/// Adapted from Lakr233/SkyLightWindow's `SkyLightOperator` (read via
/// `gh api` per check-reference-apps-first) -- vendored rather than added
/// as a SwiftPM dependency (see the design spec), and hardened against a
/// real crash risk in the original: it force-unwraps every `dlsym`
/// result, so a renamed/removed private symbol on some future macOS
/// crashes at first use. This version checks every symbol and exposes
/// `isAvailable`, so a broken symbol silently disables the feature
/// instead of crashing the app.
@MainActor
final class SkyLightSpaceOperator {
    static let shared = SkyLightSpaceOperator()

    private static let log = Logger(subsystem: "com.aliciapereira.Atelier", category: "SkyLightSpaceOperator")

    /// The level Notification Center itself uses to draw over the lock
    /// screen -- see Lakr233/SkyLightWindow's own `SKL_CGSSpaceLevel`
    /// (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`).
    private static let screenLockNotificationLevel: Int32 = 400

    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let addWindows: F_SLSSpaceAddWindowsAndRemoveFromSpaces

    /// `false` if any private symbol failed to resolve. `delegateWindow`
    /// is a no-op when this is `false`; `LockScreenPanelController` also
    /// checks it directly before ever attempting to show its window.
    private(set) var isAvailable: Bool

    private init() {
        typealias F_SLSMainConnectionID = @convention(c) () -> Int32
        typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> Int32
        typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32

        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let mainConnectionIDSym = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSym = dlsym(handle, "SLSSpaceCreate"),
            let setAbsoluteLevelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSym = dlsym(handle, "SLSShowSpaces"),
            let addWindowsSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            Self.log.error("SkyLight private symbol resolution failed -- lock-screen widget disabled")
            connection = 0
            space = 0
            addWindows = { _, _, _, _ in 0 }
            isAvailable = false
            return
        }

        let mainConnectionID = unsafeBitCast(mainConnectionIDSym, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(spaceCreateSym, to: F_SLSSpaceCreate.self)
        let setAbsoluteLevel = unsafeBitCast(setAbsoluteLevelSym, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSpacesSym, to: F_SLSShowSpaces.self)

        let resolvedConnection = mainConnectionID()
        let resolvedSpace = spaceCreate(resolvedConnection, 1, nil)

        guard resolvedSpace != 0 else {
            Self.log.error("SLSSpaceCreate returned an invalid space -- lock-screen widget disabled")
            connection = 0
            space = 0
            addWindows = { _, _, _, _ in 0 }
            isAvailable = false
            return
        }

        connection = resolvedConnection
        space = resolvedSpace
        addWindows = unsafeBitCast(addWindowsSym, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)

        _ = setAbsoluteLevel(resolvedConnection, resolvedSpace, Self.screenLockNotificationLevel)
        _ = showSpaces(resolvedConnection, [resolvedSpace] as CFArray)
        isAvailable = true
    }

    /// Moves `window` into the private lock-screen-level space. No-op if
    /// `isAvailable` is `false`.
    func delegateWindow(_ window: NSWindow) {
        guard isAvailable else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
