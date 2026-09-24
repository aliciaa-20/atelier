import SwiftUI

/// Calendar tab. Stage 2 placeholder -- shows permission state and today's
/// event count to prove the EventKit source works before the real UI.
struct CalendarPageView: View {
    @ObservedObject var source: CalendarSource

    var body: some View {
        Group {
            switch source.access {
            case .notDetermined: Text("Requesting calendar access…")
            case .denied: Text("Calendar access denied")
            case .granted: Text("\(source.events(on: source.selectedDay).count) events today")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { source.activate() }
    }
}
