import Foundation

/// The controls that can sit in the teleprompter's top bar.
enum TeleprompterControl: String, CaseIterable {
    case play
    case speed
    case ring
    case voice
}

/// Which controls sit left and right of the camera cutout, from a persisted
/// order that also contains a `"notch"` marker: controls before the marker go
/// on the left, the rest on the right. Pure and Foundation-only, like
/// `TabOrder`: no `UserDefaults`, callers pass the stored order in.
///
/// The marker is kept between the first and last control so each side always
/// has at least one (a crowded ~100pt flank would overflow).
struct TeleprompterControlLayout: Equatable {
    static let notchToken = "notch"

    let left: [TeleprompterControl]
    let right: [TeleprompterControl]

    static func resolve(stored: [String]) -> TeleprompterControlLayout {
        let order = normalized(stored)
        let split = order.firstIndex(of: notchToken) ?? 2
        let controls = order.filter { $0 != notchToken }.compactMap(TeleprompterControl.init(rawValue:))
        return TeleprompterControlLayout(left: Array(controls[..<split]), right: Array(controls[split...]))
    }

    /// The canonical five-row order (four controls plus the notch marker):
    /// unknown names and duplicates dropped, missing controls appended in
    /// default order, a missing marker put in the default spot, and the
    /// marker clamped to sit between controls. An empty list is the default.
    static func normalized(_ stored: [String]) -> [String] {
        var items: [String] = []
        let known = Set(TeleprompterControl.allCases.map(\.rawValue) + [notchToken])
        for name in stored where known.contains(name) && !items.contains(name) {
            items.append(name)
        }
        for control in TeleprompterControl.allCases where !items.contains(control.rawValue) {
            items.append(control.rawValue)
        }
        if !items.contains(notchToken) {
            items.insert(notchToken, at: min(2, items.count))
        }
        let controls = items.filter { $0 != notchToken }
        let notchIndex = min(max(items.firstIndex(of: notchToken) ?? 2, 1), controls.count - 1)
        return Array(controls[..<notchIndex]) + [notchToken] + Array(controls[notchIndex...])
    }

    /// Drag-and-drop reorder: `item` lands next to `target` (after it when
    /// moving down, before it when moving up). Unknown names, or dropping a
    /// row onto itself, change nothing.
    static func move(_ item: String, onto target: String, in stored: [String]) -> [String] {
        var items = normalized(stored)
        guard item != target,
              let from = items.firstIndex(of: item),
              let to = items.firstIndex(of: target)
        else { return items }
        items.remove(at: from)
        let targetIndex = items.firstIndex(of: target) ?? items.count
        items.insert(item, at: from < to ? targetIndex + 1 : targetIndex)
        return normalized(items)
    }
}
