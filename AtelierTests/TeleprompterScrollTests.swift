import Testing
import Foundation
@testable import Atelier

struct TeleprompterScrollTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func pausedPositionIsTheAnchor() {
        let scroll = TeleprompterScroll(totalWords: 100, wpm: 120)
        #expect(scroll.position(at: t0) == 0)
        #expect(scroll.position(at: t0.addingTimeInterval(99)) == 0)
        #expect(!scroll.isPlaying(at: t0))
    }

    @Test func playingAdvancesAtWPM() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        #expect(scroll.isPlaying(at: t0))
        // 120 words/min = 2 words/sec -> 30s = 60 words.
        #expect(scroll.position(at: t0.addingTimeInterval(30)) == 60)
    }

    @Test func pauseKeepsTheReachedPosition() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        scroll.pause(at: t0.addingTimeInterval(30))
        #expect(scroll.position(at: t0.addingTimeInterval(500)) == 60)
        #expect(!scroll.isPlaying(at: t0.addingTimeInterval(500)))
    }

    // Review Focus 3: changing speed mid-play must not make the text jump.
    @Test func changingWPMMidPlayDoesNotJump() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        let mid = t0.addingTimeInterval(30)
        scroll.setWPM(60, at: mid)
        #expect(scroll.position(at: mid) == 60)
        // 60 wpm = 1 word/sec -> 30 more seconds = 30 more words.
        #expect(scroll.position(at: mid.addingTimeInterval(30)) == 90)
    }

    @Test func wpmIsClampedToTheSupportedRange() {
        var scroll = TeleprompterScroll(totalWords: 100)
        scroll.setWPM(10, at: t0)
        #expect(scroll.wpm == 50)
        scroll.setWPM(999, at: t0)
        #expect(scroll.wpm == 300)
    }

    @Test func positionClampsAtTheEndAndReportsFinished() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        let late = t0.addingTimeInterval(100)
        #expect(scroll.position(at: late) == 10)
        #expect(scroll.isFinished(at: late))
        #expect(!scroll.isPlaying(at: late))
    }

    @Test func settleFreezesAFinishedScript() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        scroll.settle(at: t0.addingTimeInterval(100))
        #expect(scroll.position(at: t0.addingTimeInterval(9_999)) == 10)
    }

    @Test func playAtTheEndRestartsFromTheTop() {
        var scroll = TeleprompterScroll(totalWords: 10, wpm: 60)
        scroll.play(at: t0)
        let late = t0.addingTimeInterval(100)
        scroll.play(at: late)
        #expect(scroll.position(at: late) == 0)
        #expect(scroll.isPlaying(at: late))
    }

    // Review Focus 1: an empty script can't play and never divides by zero.
    @Test func emptyScriptCannotPlayAndHasZeroProgress() {
        var scroll = TeleprompterScroll(totalWords: 0, wpm: 120)
        scroll.play(at: t0)
        #expect(!scroll.isPlaying(at: t0))
        #expect(scroll.progress(at: t0) == 0)
        #expect(scroll.secondsRemaining(at: t0) == 0)
        #expect(!scroll.isFinished(at: t0))
    }

    @Test func seekClampsAndKeepsPlayingState() {
        var scroll = TeleprompterScroll(totalWords: 100, wpm: 120)
        scroll.seek(to: 500, at: t0)
        #expect(scroll.position(at: t0) == 100)
        scroll.seek(to: -5, at: t0)
        #expect(scroll.position(at: t0) == 0)

        scroll.play(at: t0)
        scroll.seek(to: 50, at: t0.addingTimeInterval(10))
        #expect(scroll.isPlaying(at: t0.addingTimeInterval(10)))
        #expect(scroll.position(at: t0.addingTimeInterval(20)) == 70)
    }

    @Test func timesAreDerivedFromWPM() {
        var scroll = TeleprompterScroll(totalWords: 120, wpm: 120)
        #expect(scroll.secondsTotal == 60)
        #expect(scroll.secondsRemaining(at: t0) == 60)
        scroll.play(at: t0)
        #expect(scroll.secondsElapsed(at: t0.addingTimeInterval(15)) == 15)
        #expect(scroll.secondsRemaining(at: t0.addingTimeInterval(15)) == 45)
        #expect(scroll.progress(at: t0.addingTimeInterval(30)) == 0.5)
    }
}
