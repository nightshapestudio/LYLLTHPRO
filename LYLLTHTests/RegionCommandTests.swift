import XCTest
@testable import LYLLTH

final class RegionCommandTests: XCTestCase {
    private func sessionWithNotes() -> (LYLLTHSession, UUID) {
        var session = LYLLTHSession.blank()
        let track = session.tracks.firstIndex { $0.kind == .instrument && $0.isChordTrack != true }!
        var clip = LYClip(name: "NOTES", kind: .notes, startBeat: 4, lengthBeats: 8)
        clip.notes = [LYNote(start: 0, length: 1, pitch: 60, velocity: 100),
                      LYNote(start: 3, length: 2, pitch: 64, velocity: 120),
                      LYNote(start: 6.1, length: 1, pitch: 67, velocity: 10)]
        session.tracks[track].clips.append(clip)
        return (session, clip.id)
    }

    func testSplittingANoteClipTrimsTheNoteAcrossTheCut() throws {
        var (session, id) = sessionWithNotes()
        let rightID = try XCTUnwrap(LYRegionCommands.split(id, atBeat: 8, in: &session))
        let right = try XCTUnwrap(LYRegionCommands.locate(rightID, in: session)).clip
        let track = session.tracks.first { $0.clips.contains { $0.id == rightID } }!
        let left = track.clips[right - 1], piece = track.clips[right]
        XCTAssertEqual(left.lengthBeats, 4)
        XCTAssertEqual(piece.startBeat, 8)
        XCTAssertEqual(left.notes?.map(\.pitch), [60, 64])
        XCTAssertEqual(left.notes?.last?.length, 1, "the E is cut off at the split")
        XCTAssertEqual(piece.notes?.map(\.pitch), [64, 67])
        XCTAssertEqual(piece.notes?.first?.start, 0)
        XCTAssertEqual(piece.notes?.first?.length ?? 0, 1, accuracy: 1e-9)
    }

    func testSplittingAPatternMakesAPlacementThatEntersWhereTheCutFell() throws {
        var session = LYLLTHSession.starter()
        let t = session.tracks.firstIndex { $0.kind == .drumkit }!
        let pattern = session.tracks[t].clips.first { $0.isSequenced && $0.isInSong }!
        let rightID = try XCTUnwrap(LYRegionCommands.split(pattern.id, atBeat: pattern.startBeat + 4, in: &session))
        let right = session.tracks[t].clips.first { $0.id == rightID }!
        XCTAssertEqual(right.patternSourceID, pattern.id)
        XCTAssertEqual(right.loopOffsetBeats, pattern.loopOffsetBeats + 4)
        XCTAssertEqual(session.tracks[t].clips.first { $0.id == pattern.id }?.lengthBeats, 4)
    }

    func testMakeUniqueGivesAPlacementItsOwnSteps() throws {
        var session = LYLLTHSession.starter()
        let t = session.tracks.firstIndex { $0.kind == .drumkit }!
        let pattern = session.tracks[t].clips.first { $0.isSequenced && $0.isInSong }!
        let copyID = try XCTUnwrap(LYRegionCommands.duplicate(pattern.id, in: &session))
        XCTAssertEqual(session.tracks[t].clips.first { $0.id == copyID }?.patternSourceID, pattern.id)
        LYRegionCommands.makeUnique(copyID, in: &session)
        let unique = session.tracks[t].clips.first { $0.id == copyID }!
        XCTAssertNil(unique.patternSourceID)
        XCTAssertEqual(unique.steps, pattern.steps)
    }

    func testAMutedPatternRegionIsSilentInTheSong() {
        var session = LYLLTHSession.starter()
        let t = session.tracks.firstIndex { $0.kind == .drumkit }!
        let window = LYSongWindow.resolve(for: session, stepsPerBar: 16)
        let render: (LYTrack, LYClip) -> (enabled: [Bool], locks: [LYStepParameters]) = { _, clip in
            (clip.steps ?? [], clip.stepParameters ?? [])
        }
        let before = LYSongCompiler.frames(session: session, window: window, stepsPerBar: 16, render: render)
        for index in session.tracks[t].clips.indices where session.tracks[t].clips[index].isSequenced {
            session.tracks[t].clips[index].isMuted = true
        }
        let after = LYSongCompiler.frames(session: session, window: window, stepsPerBar: 16, render: render)
        let id = session.tracks[t].id
        let channel = LYChannelMap.channels(in: session).first { $0.trackID == id }!.index
        XCTAssertTrue(before.contains { $0.tracks[channel].activeSteps.contains(true) })
        XCTAssertFalse(after.contains { $0.tracks[channel].activeSteps.contains(true) })
    }

    func testQuantizeVelocityAndTranspose() throws {
        var (session, id) = sessionWithNotes()
        LYRegionCommands.quantize(id, grid: 0.5, in: &session)
        LYRegionCommands.scaleVelocity(id, by: 1.2, in: &session)
        LYRegionCommands.transpose(id, by: 12, in: &session)
        let at = try XCTUnwrap(LYRegionCommands.locate(id, in: session))
        let notes = try XCTUnwrap(session.tracks[at.track].clips[at.clip].notes)
        XCTAssertEqual(notes.map(\.start), [0, 3, 6])
        XCTAssertEqual(notes.map(\.velocity), [120, 127, 12], "velocity stays inside 1…127")
        XCTAssertEqual(notes.map(\.pitch), [72, 76, 79])
    }

    func testNormalizeUsesThePeakOfThePartThatPlays() throws {
        var session = LYLLTHSession.blank()
        let t = session.tracks.firstIndex { $0.kind == .audio }!
        var clip = LYClip(name: "VOX", kind: .audio, startBeat: 0, lengthBeats: 4, sourceRelativePath: "v.wav")
        clip.sourceFileDurationSeconds = 4
        clip.sourceStartSeconds = 0
        clip.sourceDurationSeconds = 2
        // First half peaks at 0.5; the second half, which is trimmed off, at 1.
        clip.waveformPeaks = [0.2, 0.5, 0.3, 0.1, 1, 1, 1, 1]
        session.tracks[t].clips.append(clip)
        LYRegionCommands.normalize(clip.id, in: &session)
        let gain = session.tracks[t].clips.first { $0.id == clip.id }!.eventGainDB
        XCTAssertEqual(gain, -0.3 - 20 * log10(0.5), accuracy: 0.01)
    }

    func testRemoveSirenPreservesTheOriginalAudioEvent() throws {
        var session = LYLLTHSession.blank()
        let track = try XCTUnwrap(session.tracks.firstIndex { $0.kind == .audio })
        var clip = LYClip(name: "VOX", kind: .audio, startBeat: 8, lengthBeats: 4,
                          sourceRelativePath: "Audio/vox.wav", sourceStartSeconds: 0.25,
                          sourceDurationSeconds: 2)
        var note = LYVocalNote(start: 0.3, end: 0.8, detectedPitch: 60)
        note.pitchOffset = 1
        clip.vocal = LYVocalEdit(sourceRelativePath: "Audio/vox.wav", notes: [note])
        let originalSource = clip.sourceRelativePath
        let originalStart = clip.startBeat
        session.tracks[track].clips.append(clip)

        LYRegionCommands.removeSiren(clip.id, in: &session)

        let restored = try XCTUnwrap(session.tracks[track].clips.first { $0.id == clip.id })
        XCTAssertNil(restored.vocal)
        XCTAssertEqual(restored.sourceRelativePath, originalSource)
        XCTAssertEqual(restored.startBeat, originalStart)
        XCTAssertEqual(restored.sourceStartSeconds, 0.25)
        XCTAssertEqual(restored.sourceDurationSeconds, 2)
    }
}
