import XCTest
import AVFoundation
@testable import LYLLTH

/// Factory-bank tooling for LUNATK. Skipped unless LUNATK_BANK_DIR is set
/// (tools/lunatk_bank runs it). Exports the engine's parameter table, then
/// renders every preset in a render plan through the real patch path,
/// writing WAVs and timing the core.
@MainActor
final class LUNATKBankRenderTests: XCTestCase {
    private struct Plan: Decodable {
        struct Render: Decodable {
            var file: String
            var bpm: Double
            var seconds: Double
            /// [start seconds, note, velocity, duration seconds]
            var notes: [[Double]]
            var macros: [Float]?
            var modwheel: Float?
        }
        struct Preset: Decodable {
            var name: String
            var patch: LYSynthPatch
            var renders: [Render]
        }
        var sampleRate: Double
        var presets: [Preset]
        var only: [String]?
    }

    private struct Timing: Encodable {
        var file: String
        var audioSeconds: Double
        var renderSeconds: Double
    }

    func testExportParametersAndRenderPlan() throws {
        guard let dir = ProcessInfo.processInfo.environment["LUNATK_BANK_DIR"] else { throw XCTSkip("LUNATK_BANK_DIR not set") }
        let folder = URL(fileURLWithPath: dir)
        try exportParameters(to: folder.appendingPathComponent("params.json"))

        let planURL = folder.appendingPathComponent("plan.json")
        guard FileManager.default.fileExists(atPath: planURL.path) else { return }
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: planURL))
        let out = folder.appendingPathComponent("renders", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var timings: [Timing] = []
        for preset in plan.presets where plan.only == nil || plan.only!.contains(preset.name) {
            for render in preset.renders {
                let started = Date()
                let (left, right) = self.render(preset.patch, render, sampleRate: plan.sampleRate)
                timings.append(Timing(file: render.file, audioSeconds: render.seconds, renderSeconds: Date().timeIntervalSince(started)))
                try writeWAV(left, right, sampleRate: plan.sampleRate, to: out.appendingPathComponent(render.file))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(timings).write(to: folder.appendingPathComponent("timings.json"))
    }

    private func exportParameters(to url: URL) throws {
        let table = LYSynthParameters.all.map { p -> [String: Any] in
            ["id": p.id, "key": p.key, "min": p.range.lowerBound, "max": p.range.upperBound,
             "stepped": p.isStepped, "default": LYSynthParameters.defaults[p.id] ?? 0]
        }
        let data = try JSONSerialization.data(withJSONObject: ["parameters": table, "tables": LYSynthNames.tables,
                                                               "syncDivisions": LYSynthNames.syncDivisions], options: [.prettyPrinted])
        try data.write(to: url)
    }

    /// The phrase, sample-accurate, after half a second of settling so every
    /// smoothed parameter has reached the patch.
    private func render(_ patch: LYSynthPatch, _ render: Plan.Render, sampleRate: Double) -> ([Float], [Float]) {
        let instrument = LYSynthInstrument(sampleRate: sampleRate)
        instrument.apply(patch, bpm: render.bpm)
        let core = instrument.core
        if let macros = render.macros {
            for (index, value) in macros.enumerated() where index < 8 {
                lysynth_set_param(core, Int32(index < 4 ? LY_MACRO1 + index : LY_MACRO5 + index - 4), value)
            }
        }
        if let wheel = render.modwheel { lysynth_set_param(core, Int32(LY_MODWHEEL), wheel) }

        let block = 256
        var scratchL = [Float](repeating: 0, count: block), scratchR = [Float](repeating: 0, count: block)
        for _ in 0..<Int(0.5 * sampleRate) / block { lysynth_render(core, &scratchL, &scratchR, Int32(block), 0) }

        struct Event { var frame: Int; var on: Bool; var note: Int32; var velocity: Int32 }
        var events: [Event] = []
        for n in render.notes where n.count >= 4 {
            let on = Int(n[0] * sampleRate), off = Int((n[0] + n[3]) * sampleRate)
            events.append(Event(frame: on, on: true, note: Int32(n[1]), velocity: Int32(n[2])))
            events.append(Event(frame: max(off, on + 1), on: false, note: Int32(n[1]), velocity: 0))
        }
        events.sort { $0.frame == $1.frame ? (!$0.on && $1.on) : $0.frame < $1.frame }

        let total = Int(render.seconds * sampleRate)
        var left = [Float](repeating: 0, count: total), right = [Float](repeating: 0, count: total)
        var position = 0, next = 0
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                while position < total {
                    while next < events.count, events[next].frame <= position {
                        let e = events[next]
                        if e.on { lysynth_note_on(core, e.note, e.velocity, 0, 1, 0) } else { lysynth_note_off(core, e.note, 0) }
                        next += 1
                    }
                    var until = min(total, position + block)
                    if next < events.count { until = min(until, max(position + 1, events[next].frame)) }
                    // The phrase starts on a bar line with the song playing, so
                    // bar-locked performers, LFOs and arps sound as in a song.
                    lysynth_set_song_position(core, Double(position) / sampleRate * render.bpm / 60, 1)
                    lysynth_render(core, l.baseAddress! + position, r.baseAddress! + position, Int32(until - position), 0)
                    position = until
                }
            }
        }
        _ = instrument
        return (left, right)
    }

    private func writeWAV(_ left: [Float], _ right: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))!
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: right.count) }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                                                  AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                                                                  AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false],
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
