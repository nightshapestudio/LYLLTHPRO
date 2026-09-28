import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

final class SoundSteppingTests: XCTestCase {
    func testDrumStepsStayInCategoryAndWrap() throws {
        var track = LYTrack(name: "KICK", kind: .drumkit, accent: .teal, volumeDB: 0)
        let kicks = try XCTUnwrap(LYDrumSounds.grouped.first { $0.1.count > 2 }?.1)
        track.drumPresetID = kicks[0].id
        let next = try XCTUnwrap(LYSoundStepping.drum(from: track, step: 1, userPresets: []))
        XCTAssertEqual(next.id, kicks[1].id)
        XCTAssertEqual(next.category, kicks[0].category)
        let previous = try XCTUnwrap(LYSoundStepping.drum(from: track, step: -1, userPresets: []))
        XCTAssertEqual(previous.id, kicks.last?.id)
    }

    func testSynthStepsWithinFactoryCategory() throws {
        let patch = try XCTUnwrap(LYSynthPatch.factory.first { $0.category != nil && $0.name != LYSynthPatch.initPatch.name })
        let next = try XCTUnwrap(LYSoundStepping.synth(from: patch, step: 1, userPatches: []))
        XCTAssertEqual(next.category, patch.category)
        let back = try XCTUnwrap(LYSoundStepping.synth(from: next, step: -1, userPatches: []))
        XCTAssertEqual(back.name, patch.name)
    }

    func testUserPatchStepsAmongUserPatches() throws {
        var a = LYSynthPatch.initPatch; a.name = "MINE A"
        var b = LYSynthPatch.initPatch; b.name = "MINE B"
        XCTAssertEqual(LYSoundStepping.synth(from: a, step: 1, userPatches: [a, b])?.name, "MINE B")
        XCTAssertEqual(LYSoundStepping.synth(from: b, step: 1, userPatches: [a, b])?.name, "MINE A")
    }
}
