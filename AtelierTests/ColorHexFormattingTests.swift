import Testing
@testable import Atelier

struct ColorHexFormattingTests {
    @Test func formatsPureRed() {
        #expect(ColorHexFormatting.hexString(red: 1, green: 0, blue: 0) == "#FF0000")
    }

    @Test func formatsBlack() {
        #expect(ColorHexFormatting.hexString(red: 0, green: 0, blue: 0) == "#000000")
    }

    @Test func formatsWhite() {
        #expect(ColorHexFormatting.hexString(red: 1, green: 1, blue: 1) == "#FFFFFF")
    }

    @Test func roundsFractionalComponents() {
        // 0.5 * 255 = 127.5, rounds to 128 (0x80).
        #expect(ColorHexFormatting.hexString(red: 0.5, green: 0.5, blue: 0.5) == "#808080")
    }

    @Test func clampsOutOfRangeComponents() {
        #expect(ColorHexFormatting.hexString(red: 1.5, green: -0.5, blue: 0.2) == "#FF0033")
    }
}
