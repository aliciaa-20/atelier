/// Which `LiveActivitySource` is currently "on top" of the notch, ranked
/// by priority. Pure — Foundation only, no AppKit/SwiftUI — same
/// invariant as `NotchGeometry`/`NotchState`. Holds only `(id, priority)`
/// pairs; the actual content each id maps to is owned by
/// `LiveActivityCoordinator`, not this type.
struct LiveActivityStack: Equatable {
    private struct Entry: Equatable {
        let id: String
        let priority: Int
    }

    private var entries: [Entry] = []

    var topID: String? { entries.first?.id }

    mutating func upsert(id: String, priority: Int) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, priority: priority))
        entries.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }

    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }
}
