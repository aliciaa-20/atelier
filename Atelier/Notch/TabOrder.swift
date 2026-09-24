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
