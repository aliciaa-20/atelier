import Testing
@testable import Atelier

struct ScriptMatcherTests {
    // 0 the, 1 quick, 2 brown, 3 fox, 4 jumps, 5 over, 6 the, 7 lazy,
    // 8 dog, 9 and, 10 runs, 11 away, 12 from, 13 the, 14 farmer, 15 today
    private let script = "the quick brown fox jumps over the lazy dog and runs away from the farmer today"
        .split(separator: " ").map(String.init)

    /// 60 distinct long words that are never within edit distance 1 of each other.
    private var longScript: [String] {
        (0..<60).map { i in
            let a = Character(UnicodeScalar(UInt8(97 + i / 26)))
            let b = Character(UnicodeScalar(UInt8(97 + i % 26)))
            return "\(a)\(a)\(a)\(b)\(b)\(b)"
        }
    }

    @Test func exactMatchAdvancesToTheSpokenWord() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick", "brown"]) == 3)
        #expect(matcher.cursor == 3)
    }

    @Test func punctuationCaseAndAccentsAreIgnored() {
        var matcher = ScriptMatcher(scriptWords: ["Hello,", "World!", "Café"])
        #expect(matcher.update(spoken: ["hello", "world", "cafe"]) == 3)
    }

    @Test func aFuzzyMisheardLongWordStillMatches() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick", "brawn"]) == 3)
    }

    @Test func aMisheardMiddleWordStillAdvances() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quik", "brown"]) == 3)
    }

    @Test func skippingAWordWithinTheWindowFollowsTheSpeaker() {
        var matcher = ScriptMatcher(scriptWords: script)
        // "over" was skipped.
        #expect(matcher.update(spoken: ["fox", "jumps", "the", "lazy"]) == 8)
    }

    @Test func aRepeatedPhraseOutsideTheWindowIsIgnored() {
        var matcher = ScriptMatcher(scriptWords: longScript)
        let far = [longScript[50], longScript[51]]
        #expect(matcher.update(spoken: far) == nil)
        #expect(matcher.cursor == 0)
        let near = [longScript[20], longScript[21]]
        #expect(matcher.update(spoken: near) == 22)
    }

    @Test func shortWordsAloneCannotAdvance() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the"]) == nil)
        #expect(matcher.cursor == 0)
    }

    @Test func revisedPartialTranscriptDoesNotRewind() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: ["the", "quick"]) == 2)
        #expect(matcher.update(spoken: ["the", "quick", "brown", "fox"]) == 4)
        // The recognizer rewrites an earlier word: same end position, no move.
        #expect(matcher.update(spoken: ["a", "quick", "brown", "fox"]) == nil)
        #expect(matcher.cursor == 4)
    }

    @Test func neverMovesBackwards() {
        var matcher = ScriptMatcher(scriptWords: script)
        matcher.reset(cursor: 8)
        #expect(matcher.update(spoken: ["quick", "brown"]) == nil)
        #expect(matcher.cursor == 8)
    }

    @Test func emptyOrNoiseInputIsIgnored() {
        var matcher = ScriptMatcher(scriptWords: script)
        #expect(matcher.update(spoken: []) == nil)
        #expect(matcher.update(spoken: ["", "..."]) == nil)
        var empty = ScriptMatcher(scriptWords: [])
        #expect(empty.update(spoken: ["hello", "world"]) == nil)
    }

    @Test func resetClampsToTheScript() {
        var matcher = ScriptMatcher(scriptWords: script)
        matcher.reset(cursor: 999)
        #expect(matcher.cursor == script.count)
        matcher.reset(cursor: -3)
        #expect(matcher.cursor == 0)
    }

    // Review finding 1: a real script repeats long words within 30 words.
    // 0 the, 1 team, 2 shipped, 3 the, 4 release, 5 on, 6 friday, 7 and, 8 then, 9 the,
    // 10 team, 11 celebrated, 12 the, 13 release, 14 together, 15 with, 16 pizza, 17 tonight
    private let repeating = "the team shipped the release on friday and then the team celebrated the release together with pizza tonight"
        .split(separator: " ").map(String.init)

    @Test func anIdenticalResendDoesNotAdvanceAgain() {
        var matcher = ScriptMatcher(scriptWords: repeating)
        let heard = ["the", "team", "shipped", "the", "release"]
        #expect(matcher.update(spoken: heard) == 5)
        #expect(matcher.update(spoken: heard) == nil)
        #expect(matcher.cursor == 5)
    }

    @Test func anAdLibbedLongWordDoesNotJumpAhead() {
        var matcher = ScriptMatcher(scriptWords: repeating)
        matcher.reset(cursor: 2)
        #expect(matcher.update(spoken: ["um", "basically", "pizza"]) == nil)
        #expect(matcher.cursor == 2)
    }

    @Test func rereadingAnEarlierLineDoesNotJumpToALaterCopy() {
        var matcher = ScriptMatcher(scriptWords: repeating)
        matcher.reset(cursor: 5)
        #expect(matcher.update(spoken: ["shipped", "the", "release"]) == nil)
        #expect(matcher.cursor == 5)
    }
}
