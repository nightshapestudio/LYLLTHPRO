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
