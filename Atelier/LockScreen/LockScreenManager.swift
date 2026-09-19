import Foundation

/// Detects the screen lock/unlock transition via the same
/// `DistributedNotificationCenter` notification names every other
/// lock-screen-aware macOS app relies on. These are undocumented
/// notification *names*, but a long-standing, widely-used mechanism --
/// much lower risk than `SkyLightSpaceOperator`'s private-framework
/// symbol calls, which is why the two live in separate files.
@MainActor
final class LockScreenManager: ObservableObject {
    @Published private(set) var isLocked = false

    private nonisolated(unsafe) var lockObserver: NSObjectProtocol?
    private nonisolated(unsafe) var unlockObserver: NSObjectProtocol?

    init() {
        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLocked = true
        }
        unlockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLocked = false
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        if let lockObserver { center.removeObserver(lockObserver) }
        if let unlockObserver { center.removeObserver(unlockObserver) }
    }
}
