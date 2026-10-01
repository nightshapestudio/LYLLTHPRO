import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class BusRoutingTests: XCTestCase {
    private func session() -> LYLLTHSession {
        LYLLTHSession.starter()
    }

    func testEachDocumentControllerOwnsADifferentEngineGraph() {
        let first = AudioEngineController()
        let second = AudioEngineController()
        XCTAssertFalse(first.engine === second.engine)
        first.shutdown()
        second.shutdown()
    }

    func testStarterGivesAudioAndReturnTheirOwnChannels() {
        let session = session()
        XCTAssertEqual(TrackChannel.maxTracks, LYChannelMap.engineChannels)
        let channels = LYChannelMap.channels(in: session)
        XCTAssertEqual(channels.count, session.tracks.count)
        let bus = session.tracks.first { $0.kind == .auxiliary }!
        let audio = session.tracks.first { $0.kind == .audio }!
        XCTAssertEqual(LYFXBridge.engineIndex(for: audio.id, in: session), 16)
        XCTAssertEqual(LYFXBridge.engineIndex(for: bus.id, in: session), 17)
    }

    func testChannelIdentitySurvivesTrackReorder() {
        var session = session()
        let before = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        session.tracks.swapAt(0, session.tracks.count - 1)
        let after = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        XCTAssertEqual(after, before)
    }

    func testDuplicateAndMissingLegacyChannelAssignmentsAreRepaired() {
        var session = session()
        session.tracks[0].engineChannelIndex = 7
        session.tracks[1].engineChannelIndex = 7
        session.tracks[2].engineChannelIndex = nil
        session.normalizeEngineChannelIndices()
        let values = session.tracks.compactMap(\.engineChannelIndex)
        XCTAssertEqual(values.count, session.tracks.count)
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertEqual(session.tracks[0].engineChannelIndex, 7)
    }

    func testSendsAndOutputBecomeEngineRoutes() {
        var session = session()
        let bus = session.tracks.first { $0.kind == .auxiliary }!
        session.tracks[0].sends = [LYBusSend(busID: bus.id, level: 0.5)]
        session.tracks[1].outputBusID = bus.id
        let routes = LYChannelMap.routes(in: session)
        XCTAssertEqual(routes[0], .init(sends: [17: 0.5], toMain: true))
        XCTAssertEqual(routes[1], .init(sends: [17: 1], toMain: false))
        XCTAssertEqual(routes[17], .init())
    }

    func testSoloKeepsTheBusItFeeds() {
        var session = session()
        let busIndex = session.tracks.firstIndex { $0.kind == .auxiliary }!
        session.tracks[0].sends = [LYBusSend(busID: session.tracks[busIndex].id)]
        session.tracks[0].isSolo = true
        XCTAssertTrue(LYChannelMap.isAudible(session.tracks[0], in: session))
        XCTAssertTrue(LYChannelMap.isAudible(session.tracks[busIndex], in: session))
        XCTAssertFalse(LYChannelMap.isAudible(session.tracks[1], in: session))
    }

    func testOlderDocumentsDecodeWithoutRouting() throws {
        let data = try JSONEncoder().encode(session())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["tracks"] = (json["tracks"] as! [[String: Any]]).map { $0.filter { $0.key != "sends" && $0.key != "outputBusID" } }
        let decoded = try JSONDecoder().decode(LYLLTHSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.tracks.allSatisfy { $0.sends == nil && $0.outputBusID == nil })
    }

    func testRemovingTrackCleansEveryDependentReference() throws {
        var session = session()
        let removed = try XCTUnwrap(session.tracks.first { $0.kind == .auxiliary })
        let survivor = try XCTUnwrap(session.tracks.indices.first { session.tracks[$0].id != removed.id })

        session.tracks[survivor].sends = [LYBusSend(busID: removed.id, level: 0.5)]
        session.tracks[survivor].outputBusID = removed.id
        session.tracks[survivor].automation = [
            LYAutomationLane(target: .send(removed.id), points: [LYAutomationPoint(beat: 0, value: 0.5)])
        ]
        var rack = LYFXRack()
        var compressor = CompressorState.neutral
        compressor.sidechainSourceID = removed.id
        rack.compressor = compressor
        session.mainFX = rack
        var reverb = ReverbState.neutral
        reverb.duckSourceID = removed.id
        session.reverb = reverb
        session.songFX = [LYSongFXBlock(move: .open, trackID: removed.id, startBeat: 0, lengthBeats: 4)]
        _ = session.createFolder(name: "RETURN", trackIDs: [removed.id])
        _ = session.createMixGroup(name: "RETURN", trackIDs: [removed.id])

        XCTAssertEqual(session.removeTrack(id: removed.id), removed)
        XCTAssertFalse(session.tracks.contains { $0.id == removed.id })
        XCTAssertNil(session.tracks[survivor].sends)
        XCTAssertNil(session.tracks[survivor].outputBusID)
        XCTAssertNil(session.tracks[survivor].automation)
        XCTAssertNil(session.mainFX?.compressor?.sidechainSourceID)
        XCTAssertNil(session.reverb?.duckSourceID)
        XCTAssertNil(session.songFX)
        XCTAssertFalse((session.trackFolders ?? []).contains { $0.trackIDs.contains(removed.id) })
        XCTAssertFalse((session.mixGroups ?? []).contains { $0.trackIDs.contains(removed.id) })
    }
}

@MainActor
final class InsertOrderTests: XCTestCase {
    func testDraggingAnInsertMovesOnlyThatInsert() {
        var rack = LYFXRack()
        rack.order = [.eq, .comp, .tape, .flanger, .chorus, .filter]
        let chain = rack.chain(isMain: false)
        let shown = chain.filter { $0 != .eq && $0 != .reverb }
        guard shown.count >= 3 else { return XCTFail("need at least three inserts") }
        // Drag the first shown insert to third place.
        var dragged = shown
        let moving = dragged.remove(at: 0)
        dragged.insert(moving, at: 2)
        rack.reorderInserts(dragged, isMain: false)
        let after = rack.chain(isMain: false)
        XCTAssertEqual(after.filter { $0 != .eq && $0 != .reverb }, dragged)
        XCTAssertEqual(after.firstIndex(of: .eq), chain.firstIndex(of: .eq), "EQ stays put")
        XCTAssertEqual(Set(after), Set(chain), "nothing added or lost")
    }

    func testTheEngineGetsTheNewOrder() {
        var session = LYLLTHSession.starter()
        let audio = AudioEngineController()
        audio.prepare(session)
        let track = session.tracks[0].id
        var rack = LYFXBridge.rack(for: .track(track), in: session)
        rack.order = [.eq, .comp, .tape, .flanger, .chorus, .filter]
        var shown = rack.chain(isMain: false).filter { $0 != .eq && $0 != .reverb }
        shown.reverse()
        rack.reorderInserts(shown, isMain: false)
        LYFXBridge.setRack(rack, for: .track(track), in: &session)
        LYFXBridge.pushRack(target: .track(track), session: session, engine: audio.engine)
        XCTAssertEqual(session.tracks[0].fx?.chain(isMain: false).filter { $0 != .eq && $0 != .reverb }, shown)
    }
}
