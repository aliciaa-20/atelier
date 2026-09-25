import CoreGraphics

/// Layout values shared by every expanded-notch page, so tabs don't drift
/// apart (Calendar shipped at 14, System Monitor at 20, Shelf at 16 while
/// the player was 26). 26 is the value the player was widened to on direct
/// feedback that content sat too close to the rounded corners.
enum NotchLayout {
    static let pageHorizontalInset: CGFloat = 26

    /// Whole-panel height of the Teleprompter tab, notch band included
    /// (NotchPrompter's 150pt). Fits inside the player's footprint, so no
    /// other page's geometry changes.
    static let teleprompterHeight: CGFloat = 150

    /// Idle Home's weather detail card (glyph/temp row, quip, 5-day row).
    /// Starting value -- tune on-device.
    static let idleWeatherDetailContentHeight: CGFloat = 144

    // MARK: Calendar page height
    // The page grows with the selected day's events instead of always
    // claiming the tallest footprint. Starting values -- tune on-device.

    /// Tab bar + header + quip line + week strip + bottom padding.
    static let calendarFixedHeight: CGFloat = 142
    static let calendarRowHeight: CGFloat = 28
    static let calendarRowSpacing: CGFloat = 4
    /// Rows shown before the agenda scrolls.
    static let calendarMaxRows = 2
    /// Height of the "No events" line when the day is empty.
    static let calendarEmptyHeight: CGFloat = 16

    static func calendarContentHeight(eventCount: Int) -> CGFloat {
        guard eventCount > 0 else { return calendarFixedHeight + calendarEmptyHeight }
        let rows = min(eventCount, calendarMaxRows)
        return calendarFixedHeight
            + CGFloat(rows) * calendarRowHeight
            + CGFloat(rows - 1) * calendarRowSpacing
    }
}
