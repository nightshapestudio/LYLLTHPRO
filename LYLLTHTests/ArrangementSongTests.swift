import XCTest
import AVFoundation
import NightshapeAudioEngine
@testable import LYLLTH

/// Builds a LYLLTH song from an arrangement JSON (sections, DrumKit drum parts
/// with per-step hits, LUNATK parts with notes), saves it as a .lyllth package
/// and renders it with its stems. Tooling for recreating a song from a
/// transcription; skipped unless LYLLTH_ARRANGEMENT is set.
@MainActor
final class ArrangementSongTests: XCTestCase {
    private struct Arrangement: Decodable {
        struct Section: Decodable { var name: String; var bar: Int; var bars: Int }
        struct Drum: Decodable {
            var name: String; var preset: String; var volumeDB: Double; var pan: Double?; var chokeGroup: Int?
            /// Five EQ band gains (dB) for DrumKit's bands, a matching EQ.
            var eq: [Double]?
            /// A gain (dB) per section, on top of volumeDB, drawn as volume automation.
            var sectionGainDB: [Double]?
            /// Velocity 0…1 by song step (a sixteenth), keyed by the step as a string.
            var hits: [String: Double]
        }
        struct Part: Decodable {
            var name: String; var sound: String; var volumeDB: Double; var pan: Double?
            var patch: LYSynthPatch?
            var eq: [Double]?
            var sectionGainDB: [Double]?
            /// [start beat, length beats, pitch, velocity]
            var notes: [[Double]]
        }
        var title: String; var bpm: Double; var bars: Int
        var sections: [Section]; var drums: [Drum]; var parts: [Part]
        var mainFX: LYFXRack?
    }

    func testBuildArrangementSong() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LYLLTH_ARRANGEMENT"], let out = env["LYLLTH_ARRANGEMENT_OUT"] else { throw XCTSkip("set LYLLTH_ARRANGEMENT") }
        let arrangement = try JSONDecoder().decode(Arrangement.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let session = build(arrangement)
        let outDir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // The song, written exactly as LYLLTH saves it.
        let document = LYLLTHSessionDocument(session: session)
        let package = outDir.appendingPathComponent("\(arrangement.title).lyllth")
        try? FileManager.default.removeItem(at: package)
        try document.packageFileWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
        let reopened = try LYLLTHSessionDocument(fileWrapper: FileWrapper(url: package, options: .immediate))
        XCTAssertEqual(reopened.session.tracks.count, session.tracks.count)

        guard env["LYLLTH_ARRANGEMENT_RENDER"] != "0" else { return }
        func only(_ keep: (LYTrack) -> Bool) -> LYLLTHSession {
            var s = session
            for i in s.tracks.indices { s.tracks[i].isMuted = !keep(s.tracks[i]) }
            return s
        }
        let renders: [(String, LYLLTHSession)] = [
            ("mix", session),
            ("drums", only { $0.kind == .drumkit }),
            ("bass", only { $0.name == "BASS" }),
            ("music", only { $0.kind != .drumkit && $0.name != "BASS" }),
        ]
        for (name, s) in renders {
            let export = try await LYOfflineExport.prepare(session: s, assets: [:], audio: AudioEngineController())
            let url = outDir.appendingPathComponent("\(name).wav")
            try? FileManager.default.removeItem(at: url)
            _ = try await LYOfflineExport.render(export.snapshot(stem: nil), to: url, format: .wav32BitFloat,
                                                 cancellation: OfflineRenderCancellationToken()) { _ in }
        }
    }

    private func build(_ a: Arrangement) -> LYLLTHSession {
        let accents: [LYAccent] = [.teal, .teal, .indigo, .indigo, .purple, .purple]
        var tracks: [LYTrack] = []
        for drum in a.drums {
            var hits: [Int: Double] = [:]
            for (k, v) in drum.hits { if let step = Int(k) { hits[step] = v } }
            var track = drumTrack(drum.name, preset: drum.preset, volumeDB: drum.volumeDB, pan: drum.pan ?? 0,
                                  choke: drum.chokeGroup, hits: hits, sections: a.sections, accent: accents[tracks.count % 6])
            finish(&track, eq: drum.eq, gains: drum.sectionGainDB, sections: a.sections)
            tracks.append(track)
        }
        for part in a.parts {
            var track = LYTrack(name: part.name, kind: .instrument, accent: accents[tracks.count % 6], volumeDB: part.volumeDB,
                                pan: part.pan ?? 0, clips: noteClips(part.notes, sections: a.sections))
            track.synth = part.patch ?? LYSynthPatch.factory(named: part.sound)
            finish(&track, eq: part.eq, gains: part.sectionGainDB, sections: a.sections)
            tracks.append(track)
        }
        var session = LYLLTHSession(name: a.title, bpm: a.bpm, numerator: 4, denominator: 4, sampleRate: 48_000, bitDepth: 24,
                                    loopRange: nil, activePatternIndex: nil, songKey: SongKey(root: 5, isMinor: true),
                                    arrangementEditor: .default, tracks: tracks)
        session.mainFX = a.mainFX
        return session
    }

    /// Matching EQ, and section levels as a volume lane (steps at section
    /// starts, a short ramp so nothing clicks).
    private func finish(_ track: inout LYTrack, eq: [Double]?, gains: [Double]?, sections: [Arrangement.Section]) {
        if let eq, eq.count == 5 {
            var rack = track.fx ?? LYFXRack()
            var bands = LYFXRack.defaultBands
            for i in 0..<5 { bands[i].gain = eq[i] }
            rack.eqBands = bands
            track.fx = rack
        }
        if let gains, gains.count == sections.count {
            var points: [LYAutomationPoint] = []
            for (s, g) in zip(sections, gains) {
                let beat = Double(s.bar) * 4
                points.append(LYAutomationPoint(beat: beat, value: track.volumeDB + g))
                points.append(LYAutomationPoint(beat: Double(s.bar + s.bars) * 4 - 0.05, value: track.volumeDB + g))
            }
            track.automation = [LYAutomationLane(target: .volume, points: points)]
        }
    }

    /// One note clip per section, notes relative to the clip.
    private func noteClips(_ notes: [[Double]], sections: [Arrangement.Section]) -> [LYClip] {
        sections.compactMap { s in
            let start = Double(s.bar) * 4, end = Double(s.bar + s.bars) * 4
            let inside = notes.filter { $0[0] >= start - 1e-4 && $0[0] < end - 1e-4 }
            guard !inside.isEmpty else { return nil }
            let clipNotes = inside.map { n in
                LYNote(start: n[0] - start, length: min(n[1], end - n[0]), pitch: Int(n[2]), velocity: min(max(Int(n[3]), 1), 127))
            }
            return LYClip(name: s.name, kind: .notes, startBeat: start, lengthBeats: end - start, notes: clipNotes, noteLoopBeats: end - start)
        }
    }

    /// DrumKit pattern clips of up to four bars inside each section.
    private func drumTrack(_ name: String, preset: String, volumeDB: Double, pan: Double, choke: Int?,
                           hits: [Int: Double], sections: [Arrangement.Section], accent: LYAccent) -> LYTrack {
        var clips: [LYClip] = []
        for s in sections {
            var bar = s.bar
            while bar < s.bar + s.bars {
                let bars = min(4, s.bar + s.bars - bar)
                var steps = Array(repeating: false, count: 64)
                var locks = Array(repeating: LYStepParameters.default, count: 64)
                for i in 0..<(bars * 16) {
                    if let v = hits[bar * 16 + i] { steps[i] = true; locks[i].velocity = v }
                }
                if steps.contains(true) {
                    clips.append(LYClip(name: s.name, kind: .pattern, startBeat: Double(bar) * 4, lengthBeats: Double(bars) * 4,
                                        steps: steps, stepParameters: locks))
                }
                bar += bars
            }
        }
        var track = LYTrack(name: name, kind: .drumkit, accent: accent, volumeDB: volumeDB, pan: pan, clips: clips)
        track.drumPresetID = preset
        track.chokeGroup = choke
        return track
    }
}
