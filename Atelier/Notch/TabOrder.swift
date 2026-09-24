import Foundation

/// Decides which tabs show, and in what order. Pure: no `UserDefaults`, no
/// AppKit (Invariant 1) -- callers pass the stored order and the enabled set in.
enum TabOrder {
    /// - Home is a tab like any other and can sit anywhere in `stored`, but
    ///   it can't be disabled: it is always in the result. An order saved
    ///   before Home was movable doesn't mention it, and then Home stays
    ///   first, as it always was.
    /// - Enabled pages follow `stored`; unknown names and duplicates are
    ///   skipped, so a page removed in a later version can't break anything.
    /// - Enabled pages missing from `stored` (e.g. a page added in a later
    ///   version) are appended in `NotchPage.allCases` order. An empty
    ///   `stored` therefore gives the original, pre-Settings order.
    /// - `stored` is never pruned by this function: a disabled page keeps
    ///   its saved position for when it's re-enabled.
    static func resolve(stored: [String], enabled: Set<NotchPage>) -> [NotchPage] {
        let enabled = enabled.union([.home])
        let ordered = stored.contains(NotchPage.home.rawValue) ? stored : [NotchPage.home.rawValue] + stored

        var result: [NotchPage] = []
        var placed: Set<NotchPage> = []

        for name in ordered {
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
