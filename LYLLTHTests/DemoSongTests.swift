import XCTest
import AVFoundation
import NightshapeAudioEngine
@testable import LYLLTH

@MainActor
final class DemoSongTests: XCTestCase {
    func testDemoSongIsCompleteAndInKey() {
        let session = LYLLTHSession.demoSong()
        XCTAssertEqual(LYDemoSong.bars, 112)
        XCTAssertEqual(session.bpm, 112)
        for part in LYDemoSong.parts {
            XCTAssertNotNil(LYSynthPatch.factory(named: part.sound), "\(part.name): no factory sound \(part.sound)")
            XCTAssertFalse(part.notes.isEmpty, part.name)
            XCTAssertTrue(part.notes.allSatisfy { $0.end <= Double(LYDemoSong.bars) * 4 + 0.001 }, "\(part.name) runs past the end")
        }
        let instruments = session.tracks.filter { $0.kind == .instrument }
        XCTAssertEqual(instruments.count, LYDemoSong.parts.count)
        XCTAssertTrue(instruments.allSatisfy { $0.synth != nil && !$0.clips.isEmpty && $0.clips.allSatisfy(\.isNoteClip) })
        // Drums are DrumKit drum tracks playing DrumKit's bank, and their
        // pattern clips reproduce every hit exactly.
        let drums = session.tracks.filter { $0.kind == .drumkit }
        XCTAssertEqual(drums.count, LYDemoSong.drumParts.count)
        for part in LYDemoSong.drumParts {
            let track = try! XCTUnwrap(drums.first { $0.name == part.name })
            XCTAssertNotNil(LYDrumSounds.preset(id: track.drumPresetID), "\(part.name): \(part.preset) is not in DrumKit's bank")
            var played: [Int: Double] = [:]
            for clip in track.clips {
                XCTAssertEqual(clip.kind, .pattern)
                let steps = clip.steps ?? [], locks = clip.stepParameters ?? []
                let first = Int((clip.startBeat * 4).rounded())
                for i in 0..<Int((clip.lengthBeats * 4).rounded()) where steps[i % steps.count] {
                    played[first + i] = locks[i % locks.count].velocity
                }
            }
            XCTAssertEqual(played, part.hits, "\(part.name) plays exactly its hits")
        }
        // Everything melodic stays in F minor.
        let fMinor: Set<Int> = [5, 7, 8, 10, 0, 1, 3]
        let melodic = ["SUB", "BASS", "STUTTER", "PAD", "SAWS", "ARP", "GLASS", "LEAD", "HOOK", "HOOK HIGH", "SCREAM", "PIANO"]
        for part in LYDemoSong.parts where melodic.contains(part.name) {
            let outside = part.notes.filter { !fMinor.contains($0.pitch % 12) }
            XCTAssertTrue(outside.isEmpty, "\(part.name) has notes outside F minor: \(outside.map(\.pitch))")
        }
        // Every section has drums, bass or harmony under it.
        for section in LYDemoSong.sections {
            let start = Double(section.bar) * 4, end = Double(section.bar + section.bars) * 4
            let playing = LYDemoSong.parts.filter { part in part.notes.contains { $0.start >= start && $0.start < end } }
            let drumming = LYDemoSong.drumParts.filter { part in part.hits.keys.contains { Double($0) / 4 >= start && Double($0) / 4 < end } }
            XCTAssertGreaterThanOrEqual(playing.count + drumming.count, 4, "\(section.name) is too sparse")
        }
    }

    /// The demo through LYLLTH's own offline export (DrumKit drums, LUNATK,
    /// the main bus): the full mix, drums only and music only, written to
    /// LYLLTH_DEMO_DIR with a per-section level report.
    func testRenderDemoMix() async throws {
        guard let dir = ProcessInfo.processInfo.environment["LYLLTH_DEMO_DIR"] else { throw XCTSkip("set LYLLTH_DEMO_DIR") }
        let full = LYLLTHSession.demoSong()
        func only(_ keep: (LYTrack) -> Bool) -> LYLLTHSession {
            var session = full
            for i in session.tracks.indices where session.tracks[i].kind != .auxiliary { session.tracks[i].isMuted = !keep(session.tracks[i]) }
            return session
        }
        var report: [String] = []
        for (name, session) in [("NIGHT_SIGNAL_demo", full), ("drums_only", only { $0.kind == .drumkit }),
                                ("music_only", only { $0.kind != .drumkit })] {
            let audio = AudioEngineController()
            let export = try await LYOfflineExport.prepare(session: session, assets: [:], audio: audio)
            let url = URL(fileURLWithPath: dir + "/\(name).wav")
            try? FileManager.default.removeItem(at: url)
            _ = try await LYOfflineExport.render(export.snapshot(stem: nil), to: url, format: .wav32BitFloat,
                                                 cancellation: OfflineRenderCancellationToken()) { _ in }
            let file = try AVAudioFile(forReading: url)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let rate = file.processingFormat.sampleRate
            let l = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            let r = UnsafeBufferPointer(start: buffer.floatChannelData![1], count: Int(buffer.frameLength))
            XCTAssertTrue(l.allSatisfy(\.isFinite), name)
            let secondsPerBeat = 60 / LYDemoSong.bpm
            for s in LYDemoSong.sections {
                let a = min(Int(Double(s.bar) * 4 * secondsPerBeat * rate), l.count), b = min(Int(Double(s.bar + s.bars) * 4 * secondsPerBeat * rate), l.count)
                var sum = 0.0, peak: Float = 0
                for k in a..<b { sum += Double(l[k] * l[k] + r[k] * r[k]); peak = max(peak, abs(l[k]), abs(r[k])) }
                report.append(String(format: "%-18@ %-9@ rms %6.1f dB  peak %6.1f dBFS", name as NSString, s.name as NSString,
                                     10 * log10(max(sum / Double(max(1, (b - a) * 2)), 1e-12)), 20 * log10(max(peak, 1e-9))))
            }
            let peak = max(l.map(abs).max() ?? 0, r.map(abs).max() ?? 0)
            report.append(String(format: "%@ peak %.1f dBFS", name as NSString, 20 * log10(max(peak, 1e-9))))
        }
        try report.joined(separator: "\n").write(toFile: dir + "/demo_report.txt", atomically: true, encoding: .utf8)
    }
}
