import XCTest
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class BusRoutingTests: XCTestCase {
    private func session() -> LYLLTHSession {
        LYLLTHSession.starter()
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
