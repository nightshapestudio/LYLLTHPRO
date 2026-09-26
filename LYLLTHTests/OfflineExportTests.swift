import XCTest
import AVFoundation
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class OfflineExportTests: XCTestCase {
    private func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lyllth-offline-\(UUID().uuidString)-\(name)")
    }

    private func samples(_ url: URL) throws -> (left: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return (Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))), file.processingFormat.sampleRate)
    }

    private func rms(_ values: ArraySlice<Float>) -> Float {
        sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(max(values.count, 1)))
    }

    private func render(_ session: LYLLTHSession, stem: Int? = nil) async throws -> (left: [Float], rate: Double, wall: Double, song: Double) {
        let audio = AudioEngineController()
        let export = try await LYOfflineExport.prepare(session: session, assets: [:], audio: audio)
        let url = temp("mix.wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let started = Date()
        _ = try await LYOfflineExport.render(export.snapshot(stem: stem), to: url, format: .wav32BitFloat,
                                             cancellation: OfflineRenderCancellationToken()) { _ in }
        let wall = Date().timeIntervalSince(started)
        let read = try samples(url)
        return (read.left, read.rate, wall, export.window.lengthBeats * 60 / session.bpm)
    }

    /// Only the given track sounds; everything else is muted.
    private func solo(_ session: LYLLTHSession, _ index: Int) -> LYLLTHSession {
        var session = session
        for i in session.tracks.indices where session.tracks[i].kind != .auxiliary { session.tracks[i].isMuted = i != index }
        return session
    }

    func testTheStarterSongRendersFasterThanItPlays() async throws {
        let session = LYLLTHSession.starter()
        let result = try await render(session)
        XCTAssertGreaterThanOrEqual(Double(result.left.count) / result.rate, result.song - 0.01, "the whole song is there")
        XCTAssertGreaterThan(result.left.map(abs).max() ?? 0, 0.05, "and it makes a sound")
        print("OFFLINE: \(String(format: "%.1f", result.song)) s of song in \(String(format: "%.2f", result.wall)) s")
        XCTAssertLessThan(result.wall, result.song, "faster than real time, even in a debug build")
    }

    func testALUNATKNoteClipRendersWhereItIsPlaced() async throws {
        var session = LYLLTHSession.starter()
        let index = try XCTUnwrap(session.tracks.firstIndex { $0.kind == .instrument && $0.synth != nil && $0.isChordTrack != true })
        // Only a note clip on the second bar: a two-beat C3.
        session.tracks[index].clips = [LYClip(name: "N", kind: .notes, startBeat: 4, lengthBeats: 4,
                                              notes: [LYNote(start: 0, length: 2, pitch: 48, velocity: 110)], noteLoopBeats: 4)]
        session.tracks[index].automation = nil
        // Other tracks keep the song two bars long but stay silent.
        let result = try await render(solo(session, index))
        let barFrames = Int(4 * 60 / session.bpm * result.rate)
        XCTAssertLessThan(rms(result.left[0..<barFrames - 2_000]), 0.0005, "nothing before the clip")
        XCTAssertGreaterThan(rms(result.left[barFrames + 1_000..<barFrames + barFrames / 2]), 0.005, "the note sounds in bar 2")
    }

    func testVolumeAutomationShapesTheRender() async throws {
        var session = LYLLTHSession.starter()
        let index = try XCTUnwrap(session.tracks.firstIndex { $0.kind == .drumkit })
        let plain = try await render(solo(session, index))
        // Silent for the first bar, at the fader's own level from the second.
        let level = session.tracks[index].volumeDB
        session.tracks[index].automation = [LYAutomationLane(target: .volume, points: [
            LYAutomationPoint(beat: 0, value: -60), LYAutomationPoint(beat: 3.99, value: -60), LYAutomationPoint(beat: 4, value: level),
        ])]
        let automated = try await render(solo(session, index))
        let bar = Int(4 * 60 / session.bpm * plain.rate)
        XCTAssertGreaterThan(rms(plain.left[1_000..<bar - 1_000]), 0.005)
        XCTAssertLessThan(rms(automated.left[1_000..<bar - 1_000]), 0.0005)
        XCTAssertEqual(rms(automated.left[bar + 2_000..<2 * bar]), rms(plain.left[bar + 2_000..<2 * bar]), accuracy: 0.005)
    }

    func testEveryStemIsATrackThatPlays() async throws {
        let session = LYLLTHSession.starter()
        let export = try await LYOfflineExport.prepare(session: session, assets: [:], audio: AudioEngineController())
        let stems = export.stemChannels
        XCTAssertFalse(stems.isEmpty)
        XCTAssertTrue(stems.allSatisfy { $0.track.kind != .auxiliary })
        // A stem of the first one is not silent, and is quieter than the mix.
        let first = try await render(session, stem: stems[0].index)
        let mix = try await render(session)
        XCTAssertGreaterThan(rms(first.left[...]), 0.001)
        XCTAssertLessThan(rms(first.left[...]), rms(mix.left[...]) + 0.001)
    }
}
