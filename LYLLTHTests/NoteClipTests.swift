import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

final class NoteClipTests: XCTestCase {
    private func clip(start: Double = 8, length: Double = 8, loop: Double = 4, notes: [LYNote]) -> LYClip {
        LYClip(name: "NOTES", kind: .notes, startBeat: start, lengthBeats: length, notes: notes, noteLoopBeats: loop)
    }

    func testContentRepeatsAcrossTheClip() {
        let c = clip(notes: [LYNote(start: 0, length: 1, pitch: 60), LYNote(start: 2.5, length: 0.5, pitch: 64, velocity: 70)])
        let played = c.songNotes(from: 0, to: 100)
        XCTAssertEqual(played.map(\.beat), [8, 10.5, 12, 14.5])
        XCTAssertEqual(played.map(\.pitch), [60, 64, 60, 64])
        XCTAssertEqual(played[1].velocity, 70)
    }

    func testNotesAreCutAtTheRepeatAndTheClipEnd() {
        // A note held past the loop point stops where the loop comes round.
        let c = clip(length: 6, notes: [LYNote(start: 3, length: 3, pitch: 48)])
        let played = c.songNotes(from: 0, to: 100)
        XCTAssertEqual(played.map(\.beat), [11])
        XCTAssertEqual(played[0].length, 1, accuracy: 1e-9)
        // Trimmed on the left: the clip enters its content 2 beats in.
        var trimmed = clip(notes: [LYNote(start: 0, length: 0.5, pitch: 60), LYNote(start: 3, length: 0.5, pitch: 62)])
        trimmed.loopOffsetBeats = 2
        XCTAssertEqual(trimmed.songNotes(from: 0, to: 100).map(\.beat), [9, 10, 13, 14])
    }

    func testSlicesDoNotDoubleSchedule() {
        let c = clip(notes: (0..<16).map { LYNote(start: Double($0) * 0.25, length: 0.2, pitch: 60 + $0 % 5) })
        var joined: [LYSongNote] = []
        var from = 0.0
        while from < 20 {
            joined += c.songNotes(from: from, to: from + 0.37)
            from += 0.37
        }
        XCTAssertEqual(joined, c.songNotes(from: 0, to: 20.35))
        XCTAssertEqual(joined.count, 32)
    }

    func testRecordingLandsInAClipAtItsPlaceInTheLoop() {
        let existing = clip(notes: [])
        let played: [LYNoteRecording.Played] = [(13.3, 0.4, 67, 90)]
        let out = LYNoteRecording.write(played, into: [existing], beatsPerBar: 4)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].notes?.first?.start ?? -1, 1.3, accuracy: 1e-9)
        XCTAssertEqual(out[0].notes?.first?.pitch, 67)
    }

    func testATakeOnEmptyLaneGrowsOneClipBarByBar() {
        let played: [LYNoteRecording.Played] = [(0.1, 0.5, 60, 100), (4.2, 0.5, 62, 100), (9.75, 0.25, 64, 100)]
        let out = LYNoteRecording.write(played, into: [], beatsPerBar: 4)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].startBeat, 0)
        XCTAssertEqual(out[0].lengthBeats, 12)
        XCTAssertEqual(out[0].noteCycleBeats, 12)
        XCTAssertEqual(out[0].notes?.map(\.start), [0.1, 4.2, 9.75])
    }

    func testNoteClipsSurviveSaving() throws {
        let c = clip(notes: [LYNote(start: 0.5, length: 1.25, pitch: 71, velocity: 33)])
        let back = try JSONDecoder().decode(LYClip.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        XCTAssertTrue(back.isNoteClip)
        XCTAssertFalse(back.isSequenced, "note clips never reach the step sequencer")
    }

    @MainActor func testMIDIExportCarriesPianoRollNotes() throws {
        var session = LYLLTHSession.starter()
        guard let index = session.tracks.firstIndex(where: { $0.kind == .instrument && $0.isChordTrack != true }) else {
            throw XCTSkip("starter has no melodic track")
        }
        session.tracks[index].clips = [clip(start: 0, length: 4, loop: 4, notes: [LYNote(start: 0.333, length: 0.5, pitch: 99, velocity: 55)])]
        let audio = AudioEngineController()
        let window = audio.exportWindow(session)
        let data = LYMIDIExport.data(session: session, frames: audio.songFrames(session, window: window), window: window)
        // Note on, channel any, pitch 99 velocity 55.
        let bytes = [UInt8](data)
        let found = bytes.indices.dropLast(2).contains { bytes[$0] & 0xF0 == 0x90 && bytes[$0 + 1] == 99 && bytes[$0 + 2] == 55 }
        XCTAssertTrue(found)
    }
}
