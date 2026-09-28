import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

final class DrumKitTests: XCTestCase {
    func testFactoryKitsComeFromDrumKit() {
        XCTAssertEqual(LYDrumKitLibrary.factory.map(\.name), ["NOIR SIGNAL", "RETRO CATHEDRAL", "ELECTRIC GRID", "CHROME BLOOM", "IRON PULSE"])
        XCTAssertTrue(LYDrumKitLibrary.factory.allSatisfy { $0.slots.count == 16 && $0.slots.allSatisfy { $0.preset != nil } })
    }

    func testAKitLoadsByRole() throws {
        var session = LYLLTHSession.blank()
        let noir = LYDrumKitLibrary.factory[0]
        let changed = LYDrumKitLibrary.load(noir, into: &session)
        XCTAssertGreaterThan(changed, 5)
        func sound(_ name: String) -> DrumSynthPreset? {
            session.tracks.first { $0.name == name }.flatMap { LYDrumSounds.preset(for: $0) }
        }
        XCTAssertEqual(sound("KICK")?.id, "kick_018")
        XCTAssertEqual(sound("SNARE")?.id, "snare_021")
        XCTAssertEqual(sound("OPEN HAT")?.category, .openHat, "never a clap on the open hat")
        XCTAssertEqual(sound("CLAP")?.category, .clap)
        XCTAssertEqual(sound("LOW TOM")?.category, .tom)
        XCTAssertEqual(sound("HIGH TOM")?.category, .tom, "one tom in the kit plays on both tom tracks")
        XCTAssertEqual(LYDrumKitLibrary.loadedKit(in: session, among: LYDrumKitLibrary.factory)?.name, "NOIR SIGNAL")
    }

    func testYourKitComesBackOnTheSameTracksWithEditedSounds() throws {
        var session = LYLLTHSession.blank()
        let kick = session.tracks.firstIndex { $0.name == "KICK" }!
        var edited = try XCTUnwrap(DrumSynthPresetLibrary.preset(id: "kick_064"))
        edited.id = "kick_064_edit_test"
        edited.parameters.decay = 0.9
        session.tracks[kick].customDrumPreset = edited
        session.tracks[kick].drumPresetID = edited.id
        let mine = LYDrumKitLibrary.kit(named: "Heavy", from: session)
        XCTAssertEqual(mine.name, "HEAVY")

        LYDrumKitLibrary.load(LYDrumKitLibrary.factory[2], into: &session)
        XCTAssertNotEqual(LYDrumSounds.presetID(for: session.tracks[kick]), edited.id)
        LYDrumKitLibrary.load(mine, into: &session)
        XCTAssertEqual(LYDrumSounds.preset(for: session.tracks[kick]), edited, "the edited kick travels in the kit")
    }

    func testKnobAccessRoundTrips() throws {
        var preset = try XCTUnwrap(DrumSynthPresetLibrary.preset(id: "kick_064"))
        DrumSynthParameterAccess.setNormalizedValue(0.5, for: .filterFreq, in: &preset)
        XCTAssertEqual(DrumSynthParameterAccess.normalizedValue(for: .filterFreq, in: preset), 0.5, accuracy: 0.02)
        DrumSynthParameterAccess.setNormalizedValue(1, for: .filterType, in: &preset)
        XCTAssertEqual(DrumSynthParameterAccess.displayValue(for: .filterType, in: preset), "PEAK")
        DrumSynthParameterAccess.setNormalizedValue(0, for: .decay, in: &preset)
        XCTAssertTrue(DrumSynthParameterAccess.displayValue(for: .decay, in: preset).hasSuffix("MS"))
    }
}
