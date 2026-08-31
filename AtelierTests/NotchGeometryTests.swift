import Testing
import CoreGraphics
@testable import Atelier

struct NotchGeometryTests {
    @Test func computesNotchRectForAtelierBuiltInDisplay() {
        // Real numbers, probed live from the Atelier MacBook Pro M3 14" via
        // NSScreen (Built-in Retina Display) on 2026-08-31.
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsetTop: 32,
            auxiliaryTopLeftWidth: 665,
            auxiliaryTopRightWidth: 662
        )

        let rect = NotchGeometry.notchRect(for: metrics)

        #expect(rect == CGRect(x: 665, y: 950, width: 185, height: 32))
    }
}

extension NotchGeometryTests {
    @Test func fallsBackToHardCodedPillOnNotchlessDisplay() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaInsetTop: 0,
            auxiliaryTopLeftWidth: 0,
            auxiliaryTopRightWidth: 0
        )

        let rect = NotchGeometry.notchRect(for: metrics)

        #expect(rect.width == 200)
        #expect(rect.height == 32)
        #expect(rect.midX == metrics.frame.midX)
        #expect(rect.maxY == metrics.frame.maxY)
    }
}

extension NotchGeometryTests {
    @Test func computesNotchRectForDifferentScreenDimensions() {
        // A 16" MacBook Pro's published logical resolution and notch height,
        // used only to prove the formula generalizes past the one fixture
        // above rather than encoding its numbers.
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaInsetTop: 37,
            auxiliaryTopLeftWidth: 700,
            auxiliaryTopRightWidth: 700
        )

        let rect = NotchGeometry.notchRect(for: metrics)

        #expect(rect == CGRect(x: 700, y: 1080, width: 328, height: 37))
    }
}
