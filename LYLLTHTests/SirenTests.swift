import AVFoundation
import Accelerate
import XCTest
@testable import LYLLTH

/// SIREN on synthetic singing: a pulse train with falling harmonics through
/// two vowel formants, with vibrato and rests, at pitches the test knows.
final class SirenTests: XCTestCase {
    private let rate = 48_000.0

    private struct Sung { var start: Double; var end: Double; var midi: Double }

    /// A voice singing `notes`, with 5.5 Hz vibrato of `vibratoCents`.
    private func sing(_ notes: [Sung], duration: Double, vibratoCents: Double = 30, vibratoHz: Double = 5.5, formant: Double = 700) -> [Float] {
        let count = Int(duration * rate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let time = Double(index) / rate
            guard let note = notes.first(where: { time >= $0.start && time < $0.end }) else { phase = 0; continue }
            let cents = vibratoCents * sin(2 * .pi * vibratoHz * (time - note.start))
            let hz = 440 * pow(2, (note.midi + cents / 100 - 69) / 12)
            phase += hz / rate
            var sample = 0.0
            for harmonic in 1...24 {
                let f = hz * Double(harmonic)
                guard f < rate / 2 else { break }
                // Vowel-ish envelope: two resonances over a falling slope.
                let envelope = 1 / Double(harmonic)
                    * (1 + 3 * exp(-pow((f - formant) / 150, 2)) + 2 * exp(-pow((f - formant * 1.75) / 200, 2)))
                sample += envelope * sin(2 * .pi * phase * Double(harmonic))
            }
            // 8 ms fades at note edges.
            let edge = min(time - note.start, note.end - time)
            out[index] = Float(sample * 0.2 * min(1, edge / 0.008))
        }
        return out
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        buffer.floatChannelData![0].update(from: samples, count: samples.count)
        return buffer
    }

    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private let melody = [
        Sung(start: 0.10, end: 0.60, midi: 57),   // A3
        Sung(start: 0.70, end: 1.20, midi: 60),   // C4
        Sung(start: 1.30, end: 1.80, midi: 64)    // E4
    ]

    // MARK: Hearing

    func testFindsEachSungNoteAndItsPitch() {
        let analysis = LYVocalAnalyzer.analyze(samples: sing(melody, duration: 2), sampleRate: rate)
        let notes = LYVocalAnalyzer.notes(in: analysis)
        XCTAssertEqual(notes.count, 3)
        for (found, sung) in zip(notes, melody) {
            XCTAssertEqual(found.detectedPitch, sung.midi, accuracy: 0.15)
            XCTAssertEqual(found.start, sung.start, accuracy: 0.03)
            XCTAssertEqual(found.end, sung.end, accuracy: 0.03)
        }
    }

    func testALegatoStepIsTwoNotes() {
        let legato = [Sung(start: 0.1, end: 0.6, midi: 62), Sung(start: 0.6, end: 1.1, midi: 65)]
        let analysis = LYVocalAnalyzer.analyze(samples: sing(legato, duration: 1.2), sampleRate: rate)
        let notes = LYVocalAnalyzer.notes(in: analysis)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.last?.detectedPitch ?? 0, 65, accuracy: 0.15)
    }

    // MARK: Changing

    private func render(_ input: [Float], _ change: (inout [LYVocalNote]) -> Void) -> (out: [Float], notes: [LYVocalNote]) {
        let analysis = LYVocalAnalyzer.analyze(samples: input, sampleRate: rate)
        var notes = LYVocalAnalyzer.notes(in: analysis)
        change(&notes)
        let edit = LYVocalEdit(sourceRelativePath: "v.wav", notes: notes)
        let plan = LYVocalRenderer.plan(edit: edit, analysis: analysis)
        return (samples(LYVocalRenderer.render(buffer(input), plan: plan)!), notes)
    }

    func testMovingANoteChangesOnlyThatNote() {
        let input = sing(melody, duration: 2)
        let (out, _) = render(input) { $0[1].pitchOffset = 2 }
        let heard = LYVocalAnalyzer.notes(in: LYVocalAnalyzer.analyze(samples: out, sampleRate: rate))
        XCTAssertEqual(heard.count, 3)
        XCTAssertEqual(heard[0].detectedPitch, 57, accuracy: 0.15)
        XCTAssertEqual(heard[1].detectedPitch, 62, accuracy: 0.15, "C4 moved up a whole step")
        XCTAssertEqual(heard[2].detectedPitch, 64, accuracy: 0.15)
    }

    func testUntouchedNotesAreBitForBitTheOriginal() {
        let input = sing(melody, duration: 2)
        let (out, _) = render(input) { $0[2].pitchOffset = -1 }
        // The first note and the rest after it are far from the edit.
        let span = Int(0.1 * rate)..<Int(1.1 * rate)
        XCTAssertEqual(Array(out[span]), Array(input[span]))
    }

    func testDriftZeroHoldsTheNoteFlat() {
        let input = sing(melody, duration: 2, vibratoCents: 40)
        let (out, _) = render(input) { notes in for index in notes.indices { notes[index].drift = 0 } }
        let analysis = LYVocalAnalyzer.analyze(samples: out, sampleRate: rate)
        // Middle of the C4: the 40 cent vibrato should be gone.
        let values = stride(from: 0.8, to: 1.1, by: 0.005).compactMap { analysis.pitch(at: $0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let spread = sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count))
        XCTAssertLessThan(spread, 0.06, "vibrato spread \(spread) semitones")
        XCTAssertEqual(mean, 60, accuracy: 0.1)
    }

    func testFormantsStayPutWhenPitchMoves() {
        let one = [Sung(start: 0.05, end: 0.95, midi: 55)]
        let input = sing(one, duration: 1, vibratoCents: 0, formant: 800)
        let (out, _) = render(input) { $0[0].pitchOffset = 5 }
        func resonance(_ signal: [Float]) -> Double {
            // Peak of the smoothed spectrum between 400 Hz and 1.2 kHz.
            let size = 8_192
            let start = Int(0.3 * rate)
            var frame = Array(signal[start..<(start + size)])
            var window = [Float](repeating: 0, count: size)
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(size))
            let setup = vDSP_create_fftsetup(13, FFTRadix(kFFTRadix2))!
            defer { vDSP_destroy_fftsetup(setup) }
            var real = [Float](repeating: 0, count: size / 2), imaginary = [Float](repeating: 0, count: size / 2)
            var power = [Float](repeating: 0, count: size / 2)
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    frame.withUnsafeBufferPointer { $0.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2)) } }
                    vDSP_fft_zrip(setup, &split, 1, 13, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(size / 2))
                }
            }
            let hzPerBin = rate / Double(size)
            // Smooth over 300 Hz so harmonics blur into the envelope.
            let radius = Int(150 / hzPerBin)
            var best = 0.0, bestHz = 0.0
            for bin in Int(400 / hzPerBin)...Int(1_200 / hzPerBin) {
                let sum = (bin - radius...bin + radius).reduce(0.0) { $0 + Double(power[$1]) }
                if sum > best { best = sum; bestHz = Double(bin) * hzPerBin }
            }
            return bestHz
        }
        let before = resonance(input), after = resonance(out)
        XCTAssertEqual(after, before, accuracy: before * 0.15, "formant \(before) Hz moved to \(after) Hz")
    }

    func testNudgingANoteMovesItInTime() {
        let input = sing(melody, duration: 2)
        let (out, _) = render(input) { $0[1].timeOffset = 0.05 }
        let heard = LYVocalAnalyzer.notes(in: LYVocalAnalyzer.analyze(samples: out, sampleRate: rate))
        XCTAssertEqual(heard.count, 3)
        XCTAssertEqual(heard[1].start, 0.75, accuracy: 0.02)
        XCTAssertEqual(heard[1].detectedPitch, 60, accuracy: 0.15)
    }

    // MARK: Aligning

    func testAlignmentFindsHowLateTheDoubleIs() {
        // Guide: a phrase. Double: the same phrase 70 ms late, a little
        // flat, with a different vowel.
        let guideNotes = [Sung(start: 0.20, end: 0.55, midi: 60), Sung(start: 0.65, end: 0.90, midi: 62),
                          Sung(start: 1.00, end: 1.60, midi: 64), Sung(start: 1.75, end: 2.30, midi: 60)]
        let late = guideNotes.map { Sung(start: $0.start + 0.07, end: $0.end + 0.07, midi: $0.midi - 0.2) }
        let guide = sing(guideNotes, duration: 2.6)
        let dub = sing(late, duration: 2.6, vibratoHz: 4.8, formant: 760)
        let match = LYVocalAligner.path(guide: LYVocalAligner.features(guide, sampleRate: rate),
                                        dub: LYVocalAligner.features(dub, sampleRate: rate))
        let hop = LYVocalAligner.hopSeconds
        let points = LYVocalAligner.warp(match: match, tightness: 1,
                                         outputTime: { Double($0) * hop }, sourceTime: { Double($0) * hop })
        for time in [0.4, 1.2, 2.0] {
            XCTAssertEqual(LYWarp.source(atOutput: time, points) - time, 0.07, accuracy: 0.02, "at \(time) s")
        }
    }

    func testAlignedDoubleLandsOnTheGuide() {
        let guideNotes = [Sung(start: 0.20, end: 0.70, midi: 60), Sung(start: 0.90, end: 1.40, midi: 64)]
        let late = guideNotes.map { Sung(start: $0.start + 0.06, end: $0.end + 0.06, midi: $0.midi) }
        let dub = sing(late, duration: 1.8)
        let analysis = LYVocalAnalyzer.analyze(samples: dub, sampleRate: rate)
        var edit = LYVocalEdit(sourceRelativePath: "d.wav", notes: LYVocalAnalyzer.notes(in: analysis))
        edit.alignment = LYVocalAlignment(guideClipID: UUID(), tightness: 1, alignsPitch: false,
                                          points: [LYWarpPoint(output: 0, source: 0.06), LYWarpPoint(output: 1.7, source: 1.76)])
        let out = samples(LYVocalRenderer.render(buffer(dub), plan: LYVocalRenderer.plan(edit: edit, analysis: analysis))!)
        let heard = LYVocalAnalyzer.notes(in: LYVocalAnalyzer.analyze(samples: out, sampleRate: rate))
        XCTAssertEqual(heard.first?.start ?? 0, 0.20, accuracy: 0.02)
        XCTAssertEqual(heard.last?.start ?? 0, 0.90, accuracy: 0.02)
    }

    // MARK: Model

    func testEditSurvivesTheProjectFile() throws {
        var clip = LYClip(name: "VOX", kind: .audio, startBeat: 0, lengthBeats: 8, sourceRelativePath: "vox.wav")
        var note = LYVocalNote(start: 0.1, end: 0.5, detectedPitch: 60.2)
        note.pitchOffset = -0.2
        clip.vocal = LYVocalEdit(sourceRelativePath: "vox.wav", notes: [note])
        let back = try JSONDecoder().decode(LYClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(back.vocal, clip.vocal)
        XCTAssertNotNil(back.activeVocalEdit)
    }

    func testAnEditForAnotherTakeIsIgnored() {
        var clip = LYClip(name: "VOX", kind: .audio, startBeat: 0, lengthBeats: 8, sourceRelativePath: "take2.wav")
        var note = LYVocalNote(start: 0.1, end: 0.5, detectedPitch: 60)
        note.pitchOffset = 1
        clip.vocal = LYVocalEdit(sourceRelativePath: "take1.wav", notes: [note])
        XCTAssertNil(clip.activeVocalEdit)
    }

    @MainActor
    func testPlaybackFallbackFollowsTheSourceButNotEachSirenRevision() {
        var note = LYVocalNote(start: 0.1, end: 0.5, detectedPitch: 60)
        note.pitchOffset = 1
        var clip = LYClip(name: "VOX", kind: .audio, startBeat: 0, lengthBeats: 8,
                          sourceRelativePath: "take1.wav", sourceStartSeconds: 0.25,
                          sourceDurationSeconds: 2)
        clip.vocal = LYVocalEdit(sourceRelativePath: "take1.wav", notes: [note])

        let firstRender = LYTimelineAudioPlayer.renderKey(for: clip, bpm: 120)
        let firstFallback = LYTimelineAudioPlayer.fallbackRenderKey(for: clip, bpm: 120)
        clip.vocal?.notes[0].pitchOffset = 2
        XCTAssertNotEqual(LYTimelineAudioPlayer.renderKey(for: clip, bpm: 120), firstRender)
        XCTAssertEqual(LYTimelineAudioPlayer.fallbackRenderKey(for: clip, bpm: 120), firstFallback)

        clip.sourceRelativePath = "take2.wav"
        XCTAssertNotEqual(LYTimelineAudioPlayer.fallbackRenderKey(for: clip, bpm: 120), firstFallback,
                          "a previous take must never be used as the temporary playback fallback")
    }

    func testWarpRoundTrips() {
        let points = [LYWarpPoint(output: 0, source: 0), LYWarpPoint(output: 1, source: 1.2), LYWarpPoint(output: 2, source: 2)]
        for time in stride(from: 0.0, through: 2.0, by: 0.25) {
            XCTAssertEqual(LYWarp.output(atSource: LYWarp.source(atOutput: time, points), points), time, accuracy: 1e-9)
        }
    }
}
