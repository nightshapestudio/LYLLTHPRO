import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class AutomationTests: XCTestCase {
    func testLanesInterpolateAndHoldAtTheEnds() {
        let lane = LYAutomationLane(target: .volume, points: [
            LYAutomationPoint(beat: 4, value: -12),
            LYAutomationPoint(beat: 8, value: 0),
            LYAutomationPoint(beat: 8, value: -6),
            LYAutomationPoint(beat: 12, value: -6),
        ])
        XCTAssertEqual(lane.value(at: 0), -12)
        XCTAssertEqual(lane.value(at: 6)!, -6, accuracy: 1e-9)
        XCTAssertEqual(lane.value(at: 8.0001)!, -6, accuracy: 1e-3, "two points on one beat make a step")
        XCTAssertEqual(lane.value(at: 100), -6)
        XCTAssertNil(LYAutomationLane(target: .pan).value(at: 1))
    }

    func testPlayerValuesSkipBypassedLanesAndClampToTheRange() {
        var session = LYLLTHSession.starter()
        session.tracks[0].automation = [
            LYAutomationLane(target: .pan, points: [LYAutomationPoint(beat: 0, value: -3)]),
            LYAutomationLane(target: .volume, points: [LYAutomationPoint(beat: 0, value: -20)], isBypassed: true),
            LYAutomationLane(target: .synth("macro1"), points: [LYAutomationPoint(beat: 0, value: 0), LYAutomationPoint(beat: 4, value: 1)]),
        ]
        let values = LYAutomationPlayer.values(in: session, at: 2)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0].value, -1, "pan clamps to hard left")
        XCTAssertEqual(values[1].value, 0.5, accuracy: 1e-9)
    }

    func testLanesSurviveSaving() throws {
        var track = LYLLTHSession.starter().tracks[0]
        let bus = UUID()
        track.automation = [
            LYAutomationLane(target: .send(bus), points: [LYAutomationPoint(beat: 1, value: 0.3)]),
            LYAutomationLane(target: .fx("filter.cutoff"), points: []),
            LYAutomationLane(target: .synth("filter.cutoff"), points: [], isBypassed: true),
        ]
        track.showsAutomation = true
        let back = try JSONDecoder().decode(LYTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(back.automation, track.automation)
        XCTAssertEqual(back.showsAutomation, true)
    }

    func testAnAutomatedSendKeepsItsConnectionAtZero() {
        var session = LYLLTHSession.starter()
        let bus = session.tracks.first { $0.kind == .auxiliary }!
        let busChannel = LYFXBridge.engineIndex(for: bus.id, in: session)!
        session.tracks[0].sends = [LYBusSend(busID: bus.id, level: 0)]
        XCTAssertNil(LYChannelMap.routes(in: session)[0]?.sends[busChannel])
        session.tracks[0].automation = [LYAutomationLane(target: .send(bus.id), points: [LYAutomationPoint(beat: 0, value: 0.8)])]
        XCTAssertEqual(LYChannelMap.routes(in: session)[0]?.sends[busChannel], 0)
    }

    func testEveryOfferedTargetResolves() {
        for group in LYSynthAutomation.groups {
            XCTAssertFalse(group.keys.isEmpty, group.title)
            for key in group.keys { XCTAssertNotNil(LYSynthParameters.byKey[key], key) }
        }
        XCTAssertEqual(LYSynthAutomation.groups.flatMap(\.keys).count, 32, "nothing offered was dropped as stepped or unknown")
        var rack = LYFXRack()
        for parameter in LYFXAutomation.all {
            parameter.set(&rack, parameter.range.upperBound)
            XCTAssertEqual(parameter.get(rack), parameter.range.upperBound, accuracy: 1e-6, parameter.key)
        }
    }
}
