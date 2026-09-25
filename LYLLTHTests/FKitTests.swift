import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class FKitTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name + ".fkit")
        return try Data(contentsOf: url)
    }

    func testOpensADrumKitSongWithItsPatternsAndSong() throws {
        let imported = try LYFKit.importProject(from: fixture("NIGHT ENGINE"))
        let session = imported.session
        XCTAssertEqual(session.bpm, 128)
        XCTAssertEqual(session.tracks.count, 16)
        XCTAssertTrue(session.tracks.allSatisfy { $0.kind == .drumkit })
        XCTAssertEqual(session.tracks[0].name, "ARENA BODY")
        XCTAssertEqual(session.tracks[0].drumPresetID, "kick_083")
        XCTAssertTrue(session.tracks.allSatisfy { $0.patterns.count == 7 })
        XCTAssertTrue(session.tracks.allSatisfy { $0.patterns.allSatisfy { $0.isOffTimeline == true } })
        XCTAssertTrue(session.tracks.allSatisfy { $0.songRegions.count == 12 && $0.songRegions.allSatisfy(\.isPlacement) })
        XCTAssertTrue(session.tracks.allSatisfy { $0.fx != nil })
        XCTAssertTrue(imported.notes.isEmpty, imported.notes.joined(separator: "; "))
        // The first bar plays the first block's pattern.
        let frames = LYSongCompiler.frames(
            session: session,
            window: LYSongWindow(startBar: 0, barCount: 1, beatsPerBar: 4),
            stepsPerBar: 16
        ) { _, clip in (clip.steps ?? [], clip.stepParameters ?? []) }
        let first = session.tracks[0].patternContent(of: session.tracks[0].songRegions[0])
        XCTAssertEqual(frames[0].tracks[0].activeSteps, first.steps)
    }

    func testBringsCustomDrumPresetsAlong() throws {
        let imported = try LYFKit.importProject(from: fixture("CHARGED COMPANIONS"))
        let first = imported.session.tracks[0]
        XCTAssertEqual(first.drumPresetID, "user_cc26_broadcast")
        XCTAssertEqual(first.customDrumPreset?.id, "user_cc26_broadcast")
        XCTAssertEqual(LYDrumSounds.preset(for: first)?.id, "user_cc26_broadcast")
        XCTAssertTrue(imported.notes.isEmpty, imported.notes.joined(separator: "; "))
    }

    func testSavingAndReopeningKeepsTheSong() throws {
        let original = try LYFKit.importProject(from: fixture("CHARGED COMPANIONS")).session
        let saved = try LYFKit.exportProject(original, assets: [:])
        XCTAssertTrue(saved.notes.isEmpty, saved.notes.joined(separator: "; "))
        let reopened = try LYFKit.importProject(from: saved.data).session
        XCTAssertEqual(reopened.bpm, original.bpm)
        XCTAssertEqual(reopened.tracks.map(\.name), original.tracks.map(\.name))
        XCTAssertEqual(reopened.tracks.map(\.drumPresetID), original.tracks.map(\.drumPresetID))
        XCTAssertEqual(reopened.tracks.map { $0.customDrumPreset?.id }, original.tracks.map { $0.customDrumPreset?.id })
        for (a, b) in zip(original.tracks, reopened.tracks) {
            XCTAssertEqual(a.patterns.map(\.steps), b.patterns.map(\.steps))
            XCTAssertEqual(a.patterns.map { $0.stepParameters?.map(\.velocity) }, b.patterns.map { $0.stepParameters?.map(\.velocity) })
            XCTAssertEqual(a.songRegions.map(\.startBeat), b.songRegions.map(\.startBeat))
            XCTAssertEqual(a.fx, b.fx)
            XCTAssertEqual(a.volumeDB, b.volumeDB)
        }
        XCTAssertEqual(reopened.mainFX, original.mainFX)
    }

    func testSavingALYLLTHSongSaysWhatDrumKitCannotHold() throws {
        var session = LYLLTHSession.starter()
        let saved = try LYFKit.exportProject(session, assets: [:])
        XCTAssertTrue(saved.notes.contains { $0.contains("audio tracks and buses") })
        session.tracks.removeAll { $0.kind == .audio || $0.kind == .auxiliary }
        let reopened = try LYFKit.importProject(from: LYFKit.exportProject(session, assets: [:]).data).session
        XCTAssertEqual(reopened.tracks.count, 16)
        XCTAssertEqual(reopened.tracks[0].patterns.first?.steps, session.tracks[0].patterns.first?.steps)
    }
}
