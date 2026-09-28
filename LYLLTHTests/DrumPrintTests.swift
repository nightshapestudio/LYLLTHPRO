import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

final class DrumPrintTests: XCTestCase {
    private func sound(_ seconds: Double, name: String = "KICK_064_PRINT.wav") -> LYImportedAudio {
        LYImportedAudio(fileName: name, displayName: "KICK 064", data: Data(repeating: 1, count: 64),
                        duration: seconds, sampleRate: 48_000, channelCount: 2,
                        waveformPeaks: [0.5, 1, 0.25], sourceBPM: nil, beatMap: nil)
    }

    private func documentWithDrum() -> (LYLLTHSessionDocument, UUID) {
        var document = LYLLTHSessionDocument(session: .starter())
        let drum = document.session.tracks.first { $0.kind == .drumkit }!
        document.session.tracks.removeAll { $0.name == LYDrumPrint.trackName(for: drum) }
        return (document, drum.id)
    }

    func testFirstPrintMakesTrackBelowDrumAtItsLevel() throws {
        var (document, drumID) = documentWithDrum()
        let drumIndex = document.session.tracks.firstIndex { $0.id == drumID }!
        document.session.tracks[drumIndex].volumeDB = -4
        document.session.tracks[drumIndex].pan = -0.3
        let printed = LYPrintedDrum(trackID: drumID, presetID: "kick_064")

        let placed = try XCTUnwrap(document.addDrumPrint(sound(0.5), fromDrumTrackID: drumID, printed: printed, atBeat: 8))

        let track = document.session.tracks[drumIndex + 1]
        XCTAssertEqual(track.id, placed.trackID)
        XCTAssertEqual(track.kind, .audio)
        XCTAssertEqual(track.name, document.session.tracks[drumIndex].name + " PRINT")
        XCTAssertEqual(track.volumeDB, -4)
        XCTAssertEqual(track.pan, -0.3)
        XCTAssertNotNil(track.engineChannelIndex)
        let clip = try XCTUnwrap(track.clips.first)
        XCTAssertEqual(clip.id, placed.clipID)
        XCTAssertEqual(clip.startBeat, 8)
        XCTAssertEqual(clip.stretchMode, .off)
        XCTAssertEqual(clip.printedDrum, printed)
        XCTAssertEqual(clip.lengthBeats, 0.5 * document.session.bpm / 60, accuracy: 1e-9)
        XCTAssertTrue(document.audioMediaStore.contains(try XCTUnwrap(clip.sourceRelativePath)))
    }

    func testLaterPrintsShareTheTrack() throws {
        var (document, drumID) = documentWithDrum()
        let first = try XCTUnwrap(document.addDrumPrint(sound(0.5), fromDrumTrackID: drumID, printed: nil, atBeat: 0))
        let count = document.session.tracks.count
        let second = try XCTUnwrap(document.addDrumPrint(sound(0.5), fromDrumTrackID: drumID, printed: nil, atBeat: 4))
        XCTAssertEqual(first.trackID, second.trackID)
        XCTAssertEqual(document.session.tracks.count, count)
        XCTAssertEqual(document.session.tracks.first { $0.id == first.trackID }?.clips.count, 2)
    }

    func testPrintAgainKeepsTrimsAndFollowsEveryPiece() throws {
        var (document, drumID) = documentWithDrum()
        let placed = try XCTUnwrap(document.addDrumPrint(sound(1.0), fromDrumTrackID: drumID, printed: nil, atBeat: 0))
        let t = document.session.tracks.firstIndex { $0.id == placed.trackID }!
        // A chop: a second piece that plays 0.6 s from 0.3 s in.
        var chop = document.session.tracks[t].clips[0]
        chop.id = UUID()
        chop.startBeat = 4
        chop.sourceStartSeconds = 0.3
        chop.sourceDurationSeconds = 0.6
        chop.lengthBeats = 0.6 * document.session.bpm / 60
        document.session.tracks[t].clips.append(chop)
        let oldName = try XCTUnwrap(chop.sourceRelativePath)

        document.replaceDrumPrint(sourceName: oldName, with: sound(0.5))

        let whole = document.session.tracks[t].clips[0]
        let piece = document.session.tracks[t].clips[1]
        XCTAssertNotEqual(whole.sourceRelativePath, oldName)
        XCTAssertEqual(whole.sourceRelativePath, piece.sourceRelativePath)
        XCTAssertEqual(whole.sourceDurationSeconds, 0.5)
        XCTAssertEqual(whole.lengthBeats, 0.5 * document.session.bpm / 60, accuracy: 1e-9)
        XCTAssertEqual(piece.sourceStartSeconds, 0.3)
        XCTAssertEqual(try XCTUnwrap(piece.sourceDurationSeconds), 0.2, accuracy: 1e-9)
        XCTAssertEqual(piece.lengthBeats, chop.lengthBeats * 0.2 / 0.6, accuracy: 1e-9)
        XCTAssertEqual(piece.startBeat, 4)
    }

    func testCurrentPresetPrefersTheDrumTracksOwnSound() throws {
        var session = LYLLTHSession.starter()
        let index = session.tracks.firstIndex { $0.kind == .drumkit }!
        var custom = try XCTUnwrap(LYDrumSounds.preset(id: "kick_064"))
        custom.name = "MY KICK"
        session.tracks[index].drumPresetID = custom.id
        session.tracks[index].customDrumPreset = custom
        let printed = LYPrintedDrum(trackID: session.tracks[index].id, presetID: custom.id)
        XCTAssertEqual(LYDrumPrint.currentPreset(for: printed, in: session, userPresets: [])?.name, "MY KICK")

        session.tracks[index].drumPresetID = "snare_proof_001"
        session.tracks[index].customDrumPreset = nil
        XCTAssertEqual(LYDrumPrint.currentPreset(for: printed, in: session, userPresets: [])?.id, "kick_064")
    }

    func testPrintedDrumSurvivesSaving() throws {
        var clip = LYClip(name: "KICK", kind: .audio, startBeat: 0, lengthBeats: 1)
        clip.printedDrum = LYPrintedDrum(trackID: UUID(), presetID: "kick_064")
        let decoded = try JSONDecoder().decode(LYClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(decoded.printedDrum, clip.printedDrum)
    }

    func testPrintIsTheRenderTheDrumTrackPlays() async throws {
        let preset = try XCTUnwrap(LYDrumSounds.preset(id: "kick_064"))
        let sound = try await LYDrumPrint.audio(for: preset)
        let render = try await LYDrumSounds.renderedFile(for: preset)
        XCTAssertEqual(sound.data, try Data(contentsOf: render))
        XCTAssertGreaterThan(sound.duration, 0.05)
        XCTAssertNil(sound.beatMap)
        XCTAssertNil(sound.sourceBPM)
        XCTAssertEqual(sound.displayName, preset.name.uppercased())
        XCTAssertTrue(sound.fileName.hasSuffix("_PRINT.wav"))
    }
}
