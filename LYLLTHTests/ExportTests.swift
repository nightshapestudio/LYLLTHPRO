import XCTest
import AVFoundation
import NightshapeAudioEngine
@testable import LYLLTH

/// Exports record silence here (nothing plays), which is enough to prove the
/// capture path writes real, readable files on a Mac.
@MainActor
final class ExportTests: XCTestCase {
    private func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lyllth-export-\(UUID().uuidString)-\(name)")
    }

    private func finish(_ end: (@escaping (Result<Void, NightshapeAudioError>) -> Void) -> Void) -> String {
        let done = expectation(description: "end")
        var outcome = "pending"
        end { result in
            if case .failure(let error) = result { outcome = error.localizedDescription } else { outcome = "ok" }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return outcome
    }

    func testEveryMixdownFormatWritesAReadableFile() throws {
        let audio = AudioEngineController()
        audio.prepare(LYLLTHSession.starter())
        try XCTSkipUnless(audio.engine.isReady, "no audio output here")
        for (format, name) in [(NightshapeAudioEngine.CaptureFormat.wav, "mix.wav"), (.wavFloat, "mix32.wav"), (.m4a, "mix.m4a")] {
            let url = temp(name)
            try audio.engine.beginOutputCapture(to: url, format: format)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            XCTAssertEqual(finish { audio.engine.endOutputCapture(completion: $0) }, "ok", name)
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 10_000, name)
            XCTAssertEqual(file.fileFormat.channelCount, 2, name)
            if format == .wavFloat { XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatFloat32) }
        }
    }

    func testStemsRecordEveryChannelAndTheReverbAtOnce() throws {
        let session = LYLLTHSession.starter()
        let audio = AudioEngineController()
        audio.prepare(session)
        try XCTSkipUnless(audio.engine.isReady, "no audio output here")
        let sources: [NightshapeAudioEngine.StemSource] = [.track(0), .track(1), .track(16), .sharedReverb]
        let urls = sources.enumerated().map { temp("stem\($0.offset).wav") }
        try audio.engine.beginStemCapture(Array(zip(sources, urls)).map { ($0.0, $0.1) }, format: .wav)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(finish { audio.engine.endStemCapture(completion: $0) }, "ok")
        for url in urls {
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 10_000, url.lastPathComponent)
        }
    }

    func testMIDIHasATrackPerSoundingPart() throws {
        let session = LYLLTHSession.starter()
        let audio = AudioEngineController()
        let frames = audio.songFrames(session, window: audio.exportWindow(session))
        XCTAssertFalse(frames.isEmpty)
        let data = LYMIDIExport.data(session: session, frames: frames)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "MThd")
        let tracks = Int(data[10]) << 8 | Int(data[11])
        XCTAssertGreaterThan(tracks, 4, "conductor plus the parts that play")
    }
}
