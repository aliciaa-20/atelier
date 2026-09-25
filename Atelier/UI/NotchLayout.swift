import CoreGraphics

/// Layout values shared by every expanded-notch page, so tabs don't drift
/// apart (Calendar shipped at 14, System Monitor at 20, Shelf at 16 while
/// the player was 26). 26 is the value the player was widened to on direct
/// feedback that content sat too close to the rounded corners.
enum NotchLayout {
    static let pageHorizontalInset: CGFloat = 26

    /// Bottom corner radius of the expanded/shelf panel (`NotchRootView.cornerRadii`).
    static let panelBottomRadius: CGFloat = 20

    /// One gap on the sides and bottom for every surface card (Shelf,
    /// Camera, Teleprompter empty states). They used to differ (bottom
    /// 22 / 12 / 8, sides 26), so the cards sat unevenly in the panel.
    static let cardInset: CGFloat = 10

    /// Concentric with the panel's own bottom corner: outer radius minus the
    /// gap between the two shapes, so the gap looks even around the curve.
    static let cardCornerRadius: CGFloat = panelBottomRadius - cardInset

    /// Whole-panel height of the Teleprompter tab, notch band included
    /// (NotchPrompter's 150pt). Fits inside the player's footprint, so no
    /// other page's geometry changes.
    static let teleprompterHeight: CGFloat = 150

    /// Wider than the 320pt player: a landscape reading area fits more words
    /// per line. The panel is sized to the widest page (Invariant 3).
    static let teleprompterWidth: CGFloat = 440

    /// One height for every control in the teleprompter's top bar (play,
    /// speed, time ring) so they read as a set. Sized to sit inside the
    /// notch band; the two flanks are ~100pt wide, so widths stay compact.
    static let teleprompterControlSize: CGFloat = 26

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
