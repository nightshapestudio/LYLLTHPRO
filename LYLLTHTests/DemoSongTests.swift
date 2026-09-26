import XCTest
import AVFoundation
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
            XCTAssertGreaterThanOrEqual(playing.count, 4, "\(section.name) is too sparse")
        }
    }

    /// An audition mix of the whole song through LUNATK, written to
    /// LYLLTH_DEMO_DIR as a WAV with a per-section level report. Track volume
    /// and pan are applied; the plug-in racks and main bus are not.
    func testRenderDemoMix() throws {
        guard let dir = ProcessInfo.processInfo.environment["LYLLTH_DEMO_DIR"] else { throw XCTSkip("set LYLLTH_DEMO_DIR") }
        let rate = 44_100.0
        let secondsPerBeat = 60 / LYDemoSong.bpm
        let total = Int((Double(LYDemoSong.bars) * 4 * secondsPerBeat + 4) * rate)
        var mixL = [Float](repeating: 0, count: total), mixR = mixL
        var report: [String] = []
        for part in LYDemoSong.parts {
            guard let patch = LYSynthPatch.factory(named: part.sound) else { continue }
            let synth = LYSynthInstrument(sampleRate: rate)
            synth.apply(patch, bpm: LYDemoSong.bpm)
            struct Event { var frame: Int; var on: Bool; var note: Int32; var velocity: Int32 }
            var events: [Event] = []
            for n in part.notes {
                let on = Int(n.start * secondsPerBeat * rate), off = Int(n.end * secondsPerBeat * rate)
                events.append(Event(frame: on, on: true, note: Int32(n.pitch), velocity: Int32(n.velocity)))
                events.append(Event(frame: max(off - 1, on + 1), on: false, note: Int32(n.pitch), velocity: 0))
            }
            events.sort { $0.frame == $1.frame ? (!$0.on && $1.on) : $0.frame < $1.frame }
            var left = [Float](repeating: 0, count: total), right = left
            var position = 0, next = 0
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    while position < total {
                        while next < events.count, events[next].frame <= position {
                            let e = events[next]
                            if e.on { lysynth_note_on(synth.core, e.note, e.velocity, 0, 1, 0) } else { lysynth_note_off(synth.core, e.note, 0) }
                            next += 1
                        }
                        var until = min(total, position + 256)
                        if next < events.count { until = min(until, max(position + 1, events[next].frame)) }
                        lysynth_set_song_position(synth.core, Double(position) / rate / secondsPerBeat, 1)
                        lysynth_render(synth.core, l.baseAddress! + position, r.baseAddress! + position, Int32(until - position), 0)
                        position = until
                    }
                }
            }
            let gain = Float(pow(10, part.volumeDB / 20))
            let angle = (Float(part.pan) + 1) * .pi / 4
            let gl = gain * cos(angle) * 1.4142, gr = gain * sin(angle) * 1.4142
            var peak: Float = 0
            for i in 0..<total {
                mixL[i] += left[i] * gl; mixR[i] += right[i] * gr
                peak = max(peak, abs(left[i] * gl), abs(right[i] * gr))
            }
            XCTAssertTrue(left.allSatisfy(\.isFinite), part.name)
            // Level while it plays, in the first verse and the first chorus.
            func level(_ name: String) -> String {
                guard let s = LYDemoSong.sections.first(where: { $0.name == name }) else { return "" }
                let a = Int(Double(s.bar) * 4 * secondsPerBeat * rate), b = Int(Double(s.bar + s.bars) * 4 * secondsPerBeat * rate)
                var sum = 0.0
                for i in a..<b { let l = Double(left[i] * gl), r = Double(right[i] * gr); sum += l * l + r * r }
                let db = 10 * log10(max(sum / Double((b - a) * 2), 1e-14))
                return db < -100 ? "   —  " : String(format: "%6.1f", db)
            }
            report.append(String(format: "TRACK %-10@ peak %6.1f dBFS  verse %@  chorus %@", part.name as NSString,
                                 20 * log10(max(peak, 1e-9)), level("VERSE 1") as NSString, level("CHORUS 1") as NSString))
        }
        func rmsDB(_ from: Int, _ to: Int) -> Double {
            var sum = 0.0
            for i in from..<to { sum += Double(mixL[i] * mixL[i] + mixR[i] * mixR[i]) }
            return 10 * log10(max(sum / Double(max(1, (to - from) * 2)), 1e-12))
        }
        for s in LYDemoSong.sections {
            let a = Int(Double(s.bar) * 4 * secondsPerBeat * rate), b = Int(Double(s.bar + s.bars) * 4 * secondsPerBeat * rate)
            let peak = (a..<b).map { max(abs(mixL[$0]), abs(mixR[$0])) }.max() ?? 0
            report.append(String(format: "SECTION %-9@ rms %6.1f dB  peak %6.1f dBFS", s.name as NSString, rmsDB(a, b), 20 * log10(max(peak, 1e-9))))
        }
        let peak = max(mixL.map(abs).max() ?? 0, mixR.map(abs).max() ?? 0)
        report.append(String(format: "MIX peak %.1f dBFS", 20 * log10(max(peak, 1e-9))))
        try report.joined(separator: "\n").write(toFile: dir + "/demo_report.txt", atomically: true, encoding: .utf8)

        // Normalize the audition file to -1 dBFS peak so it can be played as is.
        let scale = peak > 0 ? pow(10, -1.0 / 20) / peak : 1
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        for i in 0..<total {
            buffer.floatChannelData![0][i] = mixL[i] * scale
            buffer.floatChannelData![1][i] = mixR[i] * scale
        }
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: dir + "/NIGHT_SIGNAL_demo.wav"),
                                   settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                                              AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
        try file.write(from: buffer)
    }
}
