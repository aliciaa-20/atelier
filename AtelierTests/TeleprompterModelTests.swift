import Testing
import Foundation
@testable import Atelier

@MainActor
struct TeleprompterModelTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    private func makeModel(script: String = "one two three four five six seven eight nine ten") throws -> (TeleprompterModel, ScriptStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierModelTests-\(UUID().uuidString)")
        let store = ScriptStore(directory: dir)
        try store.save(script)
        let model = TeleprompterModel(store: store, persistsWPM: false)
        model.updateLayout(width: 400, fontSize: 15, mono: false)
        return (model, store)
    }

    @Test func loadsTheStoredScript() throws {
        let (model, _) = try makeModel()
        #expect(model.script.wordCount == 10)
        #expect(model.lines.count >= 1)
    }

    @Test func playAndPauseToggleState() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        #expect(model.isPlaying)
        model.pause(now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
    }

    // Review Focus 1: Play on an empty script does nothing.
    @Test func playOnAnEmptyScriptIsANoOp() throws {
        let (model, _) = try makeModel(script: "  \n ")
        model.play(now: t0)
        #expect(!model.isPlaying)
    }

    // Review Focus 4: replacing the script mid-play stops and resets.
    @Test func editingTheScriptWhilePlayingResetsToTheTop() throws {
        let (model, store) = try makeModel()
        model.play(now: t0)
        model.pause(now: t0.addingTimeInterval(3))     // some progress
        model.play(now: t0.addingTimeInterval(3))
        try store.save("brand new script text")
        model.reloadScript()
        #expect(!model.isPlaying)
        #expect(model.script.wordCount == 4)
        #expect(model.scroll.position(at: t0.addingTimeInterval(60)) == 0)
    }

    @Test func settleStopsAScriptThatRanOffTheEnd() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        model.settle(now: t0.addingTimeInterval(600))
        #expect(!model.isPlaying)
    }

    @Test func steppingWPMClampsAndKeepsPosition() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        let mid = t0.addingTimeInterval(2)
        let before = model.scroll.position(at: mid)
        model.stepWPM(by: 10, now: mid)
        #expect(model.scroll.position(at: mid) == before)
        model.setWPM(9_999, now: mid)
        #expect(model.scroll.wpm == 300)
    }

    @Test func pointerEnteringPausesAndLeavingResumes() throws {
        let (model, _) = try makeModel()
        model.play(now: t0)
        model.setPointerInside(true, now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
        #expect(model.pausedForPointer)
        #expect(model.wantsNotchOpen)          // hold-open must survive the hover-out
        model.setPointerInside(false, now: t0.addingTimeInterval(5))
        #expect(model.isPlaying)
        #expect(!model.pausedForPointer)
    }

    @Test func pointerDoesNothingIfItWasNotPlaying() throws {
        let (model, _) = try makeModel()
        model.setPointerInside(true, now: t0)
        model.setPointerInside(false, now: t0.addingTimeInterval(1))
        #expect(!model.isPlaying)
        #expect(!model.wantsNotchOpen)
    }

    @Test func lineTextJoinsTheWordsOfALine() throws {
        let (model, _) = try makeModel(script: "alpha beta\ngamma")
        #expect(model.lineText(0) == "alpha beta")
        #expect(model.lineText(1) == "gamma")
        #expect(model.lineText(99) == "")
    }
}
