import SwiftUI

/// Calendar tab. Stage 1 placeholder -- proves the page plumbing (tab dot,
/// settings toggle, render branch) before any EventKit code exists.
struct CalendarPageView: View {
    var body: some View {
        Text("Calendar")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
