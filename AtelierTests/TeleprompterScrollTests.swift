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

struct TeleprompterScrollVoiceTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    /// 120 wpm = 2 words/sec; catch-up is 1.5s, so a gap of 90 words glides at 60 words/sec.
    private func voiceScroll(total: Int = 1_000) -> TeleprompterScroll {
        var scroll = TeleprompterScroll(totalWords: total, wpm: 120)
        scroll.enterVoiceMode(at: t0)
        return scroll
    }

    @Test func aSmallGapGlidesAtTheReadingSpeed() {
        var scroll = voiceScroll()
        scroll.setTarget(1, at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(0.25)) == 0.5)
        #expect(scroll.position(at: t0.addingTimeInterval(5)) == 1)
    }

    @Test func aLargeGapCatchesUpWithinTheCatchUpTime() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(0.75)) == 45)
        #expect(scroll.position(at: t0.addingTimeInterval(1.5)) == 90)
        #expect(scroll.position(at: t0.addingTimeInterval(60)) == 90)
    }

    @Test func retargetingMidGlideDoesNotJump() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.setTarget(100, at: mid)
        #expect(scroll.position(at: mid) == 45)
        #expect(scroll.position(at: mid.addingTimeInterval(60)) == 100)
    }

    @Test func neverGoesBackwards() {
        var scroll = voiceScroll()
        scroll.setTarget(50, at: t0)
        let later = t0.addingTimeInterval(60)
        scroll.setTarget(10, at: later)
        #expect(scroll.position(at: later.addingTimeInterval(60)) == 50)
    }

    @Test func aTargetPastTheEndClampsAndFinishes() {
        var scroll = voiceScroll(total: 100)
        scroll.setTarget(500, at: t0)
        let later = t0.addingTimeInterval(60)
        #expect(scroll.position(at: later) == 100)
        #expect(scroll.isFinished(at: later))
    }

    @Test func playingMeansGlidingInVoiceMode() {
        var scroll = voiceScroll()
        #expect(!scroll.isPlaying(at: t0))
        scroll.setTarget(90, at: t0)
        #expect(scroll.isGliding(at: t0.addingTimeInterval(0.5)))
        #expect(scroll.isPlaying(at: t0.addingTimeInterval(0.5)))
        #expect(!scroll.isGliding(at: t0.addingTimeInterval(2)))
        #expect(!scroll.isPlaying(at: t0.addingTimeInterval(2)))
    }

    @Test func glideSecondsRemainingCountsDownToArrival() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        #expect(scroll.glideSecondsRemaining(at: t0) == 1.5)
        #expect(scroll.glideSecondsRemaining(at: t0.addingTimeInterval(0.75)) == 0.75)
        #expect(scroll.glideSecondsRemaining(at: t0.addingTimeInterval(5)) == 0)
    }

    @Test func pauseFreezesTheGlide() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        scroll.pause(at: t0.addingTimeInterval(0.5))
        #expect(scroll.position(at: t0.addingTimeInterval(60)) == 30)
        #expect(!scroll.isGliding(at: t0.addingTimeInterval(60)))
    }

    @Test func playIsIgnoredInVoiceMode() {
        var scroll = voiceScroll()
        scroll.play(at: t0)
        #expect(scroll.position(at: t0.addingTimeInterval(100)) == 0)
    }

    @Test func seekLeavesVoiceMode() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        scroll.seek(to: 10, at: t0.addingTimeInterval(5))
        #expect(!scroll.isVoiceMode)
        #expect(scroll.position(at: t0.addingTimeInterval(100)) == 10)
    }

    @Test func leavingVoiceModeKeepsThePositionAndTheClockResumes() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.exitVoiceMode(at: mid)
        #expect(scroll.position(at: mid.addingTimeInterval(100)) == 45)
        scroll.play(at: mid.addingTimeInterval(100))
        // 2 words/sec.
        #expect(scroll.position(at: mid.addingTimeInterval(101)) == 47)
    }

    @Test func enteringVoiceModeWhilePlayingKeepsThePosition() {
        var scroll = TeleprompterScroll(totalWords: 1_000, wpm: 120)
        scroll.play(at: t0)
        let mid = t0.addingTimeInterval(30)
        scroll.enterVoiceMode(at: mid)
        #expect(scroll.position(at: mid.addingTimeInterval(100)) == 60)
    }

    @Test func changingWPMMidGlideDoesNotJump() {
        var scroll = voiceScroll()
        scroll.setTarget(90, at: t0)
        let mid = t0.addingTimeInterval(0.75)
        scroll.setWPM(60, at: mid)
        #expect(scroll.position(at: mid) == 45)
    }
}
