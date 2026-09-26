import XCTest
@testable import LYLLTH

/// VINTAGE, the MORPH filter, ladder poles and bass loss, and mono key priority.
@MainActor
final class LUNATKAnalogFeatureTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    private func synth(_ edit: (inout LYSynthPatch) -> Void) -> LYSynthInstrument {
        var patch = LYSynthPatch.initPatch
        edit(&patch)
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        _ = render(s, seconds: 0.2)
        return s
    }

    /// In host-sized blocks: smoothed knobs move once per render call.
    private func render(_ s: LYSynthInstrument, seconds: Double) -> [Float] {
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames), right = left
        var position = 0
        while position < frames {
            let n = min(64, frames - position)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    lysynth_render(s.core, l.baseAddress! + position, r.baseAddress! + position, Int32(n), 0)
                }
            }
            position += n
        }
        return left
    }

    private func level(_ x: [Float], _ hz: Double) -> Double {
        var re = 0.0, im = 0.0
        for (i, v) in x.enumerated() {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(x.count))
            re += Double(v) * w * cos(2 * .pi * hz * Double(i) / rate)
            im += Double(v) * w * sin(2 * .pi * hz * Double(i) / rate)
        }
        return (re * re + im * im).squareRoot()
    }

    /// The strongest frequency between `low` and `high`, in 0.5 Hz steps.
    private func pitch(_ x: [Float], near hz: Double) -> Double {
        var best = (hz, 0.0)
        for f in stride(from: hz * 0.97, through: hz * 1.03, by: 0.25) {
            let l = level(x, f)
            if l > best.1 { best = (f, l) }
        }
        return best.0
    }

    // MARK: VINTAGE

    func testVintageGivesEachNoteItsOwnTuningAndStaysClose() {
        let sine: (inout LYSynthPatch) -> Void = { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
            p.set(LY_FILTER_ON, 0)
            p.set(LY_VINTAGE, 1)
        }
        let s = synth(sine)
        var pitches: [Double] = []
        for _ in 0..<4 {
            s.noteOn(69, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            let out = render(s, seconds: 0.6)
            pitches.append(pitch(Array(out.suffix(16384)), near: 440))
            s.noteOff(69, atHostTime: 0)
            _ = render(s, seconds: 0.5)
        }
        let cents = pitches.map { 1200 * log2($0 / 440) }
        XCTAssertTrue(cents.allSatisfy { abs($0) < 15 }, "\(cents)")
        XCTAssertGreaterThan(cents.max()! - cents.min()!, 1, "notes differ: \(cents)")
        // At 0 every note is the same, sample for sample.
        let plain = synth { p in sine(&p); p.set(LY_VINTAGE, 0) }
        plain.noteOn(69, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let first = render(plain, seconds: 0.3)
        plain.noteOff(69, atHostTime: 0); _ = render(plain, seconds: 0.5)
        plain.noteOn(69, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        XCTAssertEqual(pitch(Array(first.suffix(8192)), near: 440), pitch(Array(render(plain, seconds: 0.3).suffix(8192)), near: 440))
    }

    // MARK: Filters

    private func response(_ edit: @escaping (inout LYSynthPatch) -> Void, note: UInt8) -> Double {
        let s = synth { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
            p.set(LY_FILTER_KEYTRACK, 0)
            p.set(LY_FILTER_CUTOFF, 0.4)                      // a few hundred Hz
            edit(&p)
        }
        s.noteOn(note, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let out = Array(render(s, seconds: 0.6).suffix(16384))
        let hz = 440 * pow(2, (Double(note) - 69) / 12)
        return level(out, hz)
    }

    func testMorphSweepsLowPassNotchHighPass() {
        let morph = { (m: Float) -> (Inout) in { p in p.set(LY_FILTER_TYPE, Float(LY_FILTER_MORPH)); p.set(LY_FILTER_RES, 0.2); p.set(LY_FILTER_MORPH_POS, m) } }
        // A low note (55 Hz) and a high one (3.5 kHz), well either side of the cutoff.
        let lowLP = response(morph(0), note: 33), highLP = response(morph(0), note: 105)
        XCTAssertGreaterThan(lowLP, highLP * 20, "0 is low-pass")
        let lowHP = response(morph(1), note: 33), highHP = response(morph(1), note: 105)
        XCTAssertGreaterThan(highHP, lowHP * 20, "1 is high-pass")
        // Halfway, both ends pass and somewhere between them is a notch.
        let ends = min(response(morph(0.5), note: 33), response(morph(0.5), note: 105))
        let deepest = stride(from: 60, through: 90, by: 2).map { response(morph(0.5), note: UInt8($0)) }.min()!
        XCTAssertLessThan(deepest, ends * 0.3, "0.5 notches around the cutoff")
    }
    typealias Inout = (inout LYSynthPatch) -> Void

    func testLadderTwoPoleCutsLessAndBassLossThinsTheLows() {
        let ladder = { (poles: Float, res: Float, bass: Float) -> Inout in
            { p in p.set(LY_FILTER_TYPE, Float(LY_FILTER_LADDER)); p.set(LY_FILTER_RES, res); p.set(LY_LADDER_POLES, poles); p.set(LY_LADDER_BASS, bass) }
        }
        // Well above the cutoff: four poles leave far less than two.
        XCTAssertLessThan(response(ladder(0, 0.1, 0), note: 105), response(ladder(1, 0.1, 0), note: 105) * 0.35)
        // High resonance with BASS LOSS: the lows fall away.
        XCTAssertLessThan(response(ladder(0, 0.8, 1), note: 45), response(ladder(0, 0.8, 0), note: 45) * 0.8)
    }

    // MARK: Key priority

    func testMonoKeyPriorityAndReturningToHeldKeys() {
        func sounding(_ priority: Int, _ play: (LYSynthInstrument) -> Void) -> Double {
            let s = synth { p in
                p.set(LY_VOICES, 1)
                p.set(LY_KEY_PRIORITY, Float(priority))
                p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
                p.set(LY_FILTER_ON, 0)
            }
            play(s)
            let out = Array(render(s, seconds: 0.5).suffix(16384))
            return level(out, 261.63) > level(out, 329.63) ? 60 : 64
        }
        let c = UInt8(60), e = UInt8(64)
        func hold(_ first: UInt8, _ second: UInt8) -> (LYSynthInstrument) -> Void {
            { s in
                s.noteOn(first, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0); _ = self.render(s, seconds: 0.1)
                s.noteOn(second, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            }
        }
        XCTAssertEqual(sounding(LY_PRIORITY_LAST, hold(c, e)), 64, "LAST plays the newest key")
        XCTAssertEqual(sounding(LY_PRIORITY_LOW, hold(c, e)), 60, "LOW keeps the lower key")
        XCTAssertEqual(sounding(LY_PRIORITY_HIGH, hold(e, c)), 64, "HIGH keeps the higher key")
        // Letting go of the newest key goes back to the one still held.
        XCTAssertEqual(sounding(LY_PRIORITY_LAST) { s in
            hold(c, e)(s); _ = self.render(s, seconds: 0.1); s.noteOff(e, atHostTime: 0)
        }, 60)
    }

    func testAddedParametersAreKeyed() {
        for id in Int(LY_VINTAGE)..<Int(LY_PARAM_COUNT) {
            XCTAssertNotNil(LYSynthParameters.byID[id], "parameter \(id) has no key")
        }
        XCTAssertEqual(LYSynthNames.filters.count, Int(LY_FILTER_COUNT))
        XCTAssertEqual(Set(LYSynthNames.filterOrder).count, Int(LY_FILTER_COUNT))
        XCTAssertTrue(LYSynthNames.destinations.allSatisfy { !$0.isEmpty })
    }
}
