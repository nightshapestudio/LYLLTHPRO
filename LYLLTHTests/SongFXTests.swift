import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class SongFXTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name + ".fkit")
        return try Data(contentsOf: url)
    }

    func testAFilterSweepBecomesPerStepSegmentsOnItsChannel() {
        let session = LYLLTHSession.starter()
        let track = session.tracks[2]
        let channel = LYFXBridge.engineIndex(for: track.id, in: session)!
        // Two bars from beat 2: the sweep enters the first bar at step 8.
        let block = LYSongFXBlock(move: .open, trackID: track.id, startBeat: 2, lengthBeats: 8)
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        let bar0 = LYSongFXCompiler.lanes([block], barStartBeat: 0, stepsPerBar: 16, channels: channels)
        XCTAssertEqual(bar0.filter.map(\.target), [channel])
        XCTAssertTrue(bar0.fracture.isEmpty)
        let segments = bar0.filter[0].segments
        XCTAssertNil(segments[7])
        XCTAssertEqual(segments[8]?.from ?? -1, block.startLevel, accuracy: 1e-6)
        XCTAssertEqual(segments[8]?.to ?? -1, block.level(atBeat: 2.25), accuracy: 1e-6)
        XCTAssertEqual(segments[8]?.mode, .lowPass)
        // It finishes at its end level inside the third bar.
        let bar2 = LYSongFXCompiler.lanes([block], barStartBeat: 8, stepsPerBar: 16, channels: channels)
        XCTAssertEqual(bar2.filter[0].segments[7]?.to ?? -1, block.endLevel, accuracy: 1e-6)
        XCTAssertNil(bar2.filter[0].segments[8])
    }

    func testFractureOnMainKeepsItsBlockIdentityAcrossBars() {
        let block = LYSongFXBlock(move: .stutter, trackID: nil, startBeat: 3, lengthBeats: 2)
        let a = LYSongFXCompiler.lanes([block], barStartBeat: 0, stepsPerBar: 16, channels: [:])
        let b = LYSongFXCompiler.lanes([block], barStartBeat: 4, stepsPerBar: 16, channels: [:])
        XCTAssertEqual(a.fracture.first?.target, SongFilterLane.mainTarget)
        XCTAssertEqual(a.fracture[0].cells[12]?.stepsIntoBlock, 0)
        XCTAssertEqual(b.fracture[0].cells[3]?.stepsIntoBlock, 7)
        XCTAssertNil(b.fracture[0].cells[4])
        XCTAssertEqual(a.fracture[0].cells[12]?.blockID, b.fracture[0].cells[0]?.blockID)
        XCTAssertEqual(a.fracture[0].cells[12]?.blockLengthSteps, 8)
    }

    func testSongFramesCarryTheLanes() {
        var session = LYLLTHSession.starter()
        session.songFX = [LYSongFXBlock(move: .dip, trackID: nil, startBeat: 0, lengthBeats: 4)]
        let frames = LYSongCompiler.frames(session: session, window: LYSongWindow(startBar: 0, barCount: 2, beatsPerBar: 4), stepsPerBar: 16) { _, clip in
            (clip.steps ?? [], clip.stepParameters ?? [])
        }
        XCTAssertEqual(frames[0].filterLanes.count, 1)
        XCTAssertTrue(frames[1].filterLanes.isEmpty)
    }

    func testTheLaneSurvivesADrumKitRoundTrip() throws {
        var session = try LYFKit.importProject(from: fixture("NIGHT ENGINE")).session
        var sweep = LYSongFXBlock(move: .close, trackID: session.tracks[3].id, startBeat: 16, lengthBeats: 8, row: 1)
        sweep.endLevel = 0.2
        sweep.resonance = 0.55
        let roll = LYSongFXBlock(move: .roll, trackID: nil, startBeat: 30, lengthBeats: 2)
        session.songFX = [sweep, roll]
        let exported = try LYFKit.exportProject(session, assets: [:])
        XCTAssertFalse(exported.notes.contains { $0.contains("FX") }, exported.notes.joined(separator: "; "))
        let back = try LYFKit.importProject(from: exported.data).session
        let blocks = try XCTUnwrap(back.songFX)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].move, .close)
        XCTAssertEqual(blocks[0].trackID, back.tracks[3].id)
        XCTAssertEqual(blocks[0].startBeat, 16)
        XCTAssertEqual(blocks[0].lengthBeats, 8)
        XCTAssertEqual(blocks[0].row, 1)
        XCTAssertEqual(blocks[0].endLevel, 0.2, accuracy: 1e-6)
        XCTAssertEqual(blocks[0].resonance, 0.55, accuracy: 1e-6)
        XCTAssertEqual(blocks[1].move, .roll)
        XCTAssertNil(blocks[1].trackID)
    }
}
