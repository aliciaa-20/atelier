import CoreGraphics

/// Layout values shared by every expanded-notch page, so tabs don't drift
/// apart (Calendar shipped at 14, System Monitor at 20, Shelf at 16 while
/// the player was 26). 26 is the value the player was widened to on direct
/// feedback that content sat too close to the rounded corners.
enum NotchLayout {
    static let pageHorizontalInset: CGFloat = 26
}
