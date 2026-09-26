import XCTest
@testable import LYLLTH

/// Saturation between the filters, split routing, sustain slope, punch, arp
/// patterns and the vocoder.
@MainActor
final class LUNATKVirusFeatureTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    private func synth(_ edit: (inout LYSynthPatch) -> Void) -> LYSynthInstrument {
        var patch = LYSynthPatch.initPatch
        edit(&patch)
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        // Smoothed knobs glide from the core's defaults; let them arrive.
        _ = render(s, seconds: 0.2)
        return s
    }

    private func render(_ s: LYSynthInstrument, seconds: Double, input: [Float]? = nil, beat: Double? = nil) -> [Float] {
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames), right = left
        var position = 0
        while position < frames {
            let n = min(64, frames - position)
            if let beat { lysynth_set_song_position(s.core, beat + Double(position) / rate * 2, 1) }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    if let input {
                        input.withUnsafeBufferPointer { i in
                            let p = i.baseAddress! + position
                            lysynth_render_input(s.core, l.baseAddress! + position, r.baseAddress! + position, p, p, Int32(n), 0)
                        }
                    } else {
                        lysynth_render(s.core, l.baseAddress! + position, r.baseAddress! + position, Int32(n), 0)
                    }
                }
            }
            position += n
        }
        return left
    }

    private func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

    private func band(_ x: [Float], _ hz: Double) -> Double {
        var re = 0.0, im = 0.0
        for (i, v) in x.enumerated() {
            re += Double(v) * cos(2 * .pi * hz * Double(i) / rate)
            im += Double(v) * sin(2 * .pi * hz * Double(i) / rate)
        }
        return (re * re + im * im).squareRoot() / Double(x.count)
    }

    // MARK: Saturation and routing

    func testEverySaturationRunsInEveryRoutingAndMixZeroIsBypass() {
        func play(_ edit: (inout LYSynthPatch) -> Void) -> [Float] {
            let s = synth { p in
                p.set(LY_F2_ON, 1)
                p.set(LY_F2_TYPE, Float(LY_FILTER_LP12)); p.set(LY_F2_CUTOFF, 0.8)
                p.set(LYSynthParameters.oscillator(1, LY_OSC_ON), 1)
                edit(&p)
            }
            s.noteOn(48, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            return render(s, seconds: 0.5)
        }
        for routing in 0..<Int(LY_ROUTING_COUNT) {
            let plain = play { $0.set(LY_FILTER_ROUTING, Float(routing)) }
            XCTAssertTrue(plain.allSatisfy(\.isFinite))
            for type in 1..<Int(LY_FSAT_COUNT) {
                let name = "\(LYSynthNames.saturations[type]) \(LYSynthNames.routings[routing])"
                let wet = play { p in
                    p.set(LY_FILTER_ROUTING, Float(routing)); p.set(LY_FSAT_TYPE, Float(type)); p.set(LY_FSAT_DRIVE, 0.7)
                }
                XCTAssertTrue(wet.allSatisfy(\.isFinite), name)
                XCTAssertLessThan(wet.map(abs).max()!, 1.3, name)
                XCTAssertNotEqual(wet, plain, "\(name) changes the sound")
                let bypass = play { p in
                    p.set(LY_FILTER_ROUTING, Float(routing)); p.set(LY_FSAT_TYPE, Float(type)); p.set(LY_FSAT_MIX, 0)
                }
                XCTAssertEqual(bypass, plain, "\(name) at MIX 0 is untouched")
            }
        }
    }

    func testSplitSendsOscillatorBAroundFilterOne() {
        // Filter 1 is a low-pass at ~40 Hz; filter 2 is off. B is a sine an
        // octave and a fifth up. In series B is buried; in split it is there.
        func energy(_ routing: Int) -> Double {
            let s = synth { p in
                p.set(LY_FILTER_CUTOFF, 0.1)
                p.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 0)
                p.set(LYSynthParameters.oscillator(1, LY_OSC_ON), 1)
                p.set(LYSynthParameters.oscillator(1, LY_OSC_WTPOS), 0)
                p.set(LY_F2_ON, 0)
                p.set(LY_FILTER_ROUTING, Float(routing))
            }
            s.noteOn(69, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            return band(Array(render(s, seconds: 0.5).suffix(8192)), 440)
        }
        XCTAssertGreaterThan(energy(Int(LY_ROUTING_SPLIT)), energy(Int(LY_ROUTING_SERIAL)) * 20)
    }

    // MARK: Envelopes

    func testSustainSlopeFallsAndRises() {
        func held(_ slope: Float) -> (early: Float, late: Float) {
            let s = synth { p in
                p.set(LY_ENV1_A, 0); p.set(LY_ENV1_D, 0.2); p.set(LY_ENV1_S, 0.5)
                p.set(LY_ENV1_SLOPE, slope)
            }
            s.noteOn(60, velocity: 127, atHostTime: 0, cutoff: 1, resonance: 0)
            let out = render(s, seconds: 3.0)
            return (rms(out[Int(0.03 * rate)..<Int(0.1 * rate)]), rms(out[Int(2.6 * rate)..<Int(2.9 * rate)]))
        }
        let flat = held(0), falling = held(-0.8), rising = held(0.8)
        XCTAssertEqual(flat.late / flat.early, 1, accuracy: 0.05)
        XCTAssertLessThan(falling.late, falling.early * 0.5)
        XCTAssertGreaterThan(rising.late, rising.early * 1.4)
    }

    func testPunchLiftsTheAttackOnly() {
        func out(_ punch: Float) -> [Float] {
            let s = synth { p in p.set(LY_ENV1_A, 0); p.set(LY_ENV1_S, 1); p.set(LY_PUNCH, punch) }
            s.noteOn(60, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            return render(s, seconds: 0.6)
        }
        let plain = out(0), punched = out(1)
        XCTAssertGreaterThan(rms(punched[0..<Int(0.01 * rate)]), rms(plain[0..<Int(0.01 * rate)]) * 1.4)
        XCTAssertEqual(rms(punched[Int(0.3 * rate)...]) / rms(plain[Int(0.3 * rate)...]), 1, accuracy: 0.02)
    }

    // MARK: Arp pattern

    func testArpPatternLevelsAndRests() {
        let s = synth { p in
            p.set(LY_ARP_ON, 1); p.set(LY_ARP_RATE, 10 / 14)      // 1/16: 0.125 s at 120
            p.set(LY_ENV1_A, 0); p.set(LY_ENV1_D, 0.3); p.set(LY_ENV1_S, 1); p.set(LY_ENV1_R, 0.05)
            p.set(LY_ARP_STEPS, 4)
            for (i, level) in [Float(1), 0, 1, 0.3].enumerated() {
                p.set(LY_ARP_LEVEL_BASE + i, level); p.set(LY_ARP_LENGTH_BASE + i, 0.5)
            }
        }
        _ = render(s, seconds: 0.05, beat: 0)
        s.noteOn(60, velocity: 127, atHostTime: 0, cutoff: 1, resonance: 0)
        let out = render(s, seconds: 1.0, beat: 0.1)
        // Steps land on the sixteenth grid from beat 0.25 (0.075 s in).
        func step(_ k: Int) -> Float {
            let start = Int((0.075 + 0.125 * Double(k)) * rate)
            return rms(out[start + 200 ..< start + Int(0.05 * rate)])
        }
        XCTAssertGreaterThan(step(0), 0.02)
        XCTAssertLessThan(step(1), step(0) * 0.05, "step 2 is a rest")
        XCTAssertGreaterThan(step(2), 0.02)
        XCTAssertLessThan(step(3), step(2) * 0.9, "step 4 is quieter")
        XCTAssertGreaterThan(step(3), step(1) * 5)
        XCTAssertLessThan(step(5), step(4) * 0.05, "the pattern repeats: step 6 rests again")
    }

    // MARK: Vocoder

    func testVocoderFollowsItsInputAndStandsAsideWithout() {
        func carrier(_ vocoder: Bool) -> LYSynthInstrument {
            let s = synth { p in
                p.set(LY_FILTER_ON, 0)
                p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0.66)     // saw
                if vocoder { p.set(LY_VOC_ON, 1) }
            }
            for note in [48, 55, 60] { s.noteOn(UInt8(note), velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0) }
            return s
        }
        let frames = Int(0.8 * rate)
        // No input: the vocoder stands aside, sample for sample.
        XCTAssertEqual(render(carrier(true), seconds: 0.8), render(carrier(false), seconds: 0.8))
        // A silent input: nothing gets through.
        let silent = render(carrier(true), seconds: 0.8, input: [Float](repeating: 0, count: frames))
        XCTAssertLessThan(rms(silent[Int(0.3 * rate)...]), 0.001)
        // A 1.6 kHz tone as the voice: the vocoded chord gathers around it.
        let tone = (0..<frames).map { Float(0.3 * sin(2 * .pi * 1600 * Double($0) / rate)) }
        let vocoded = Array(render(carrier(true), seconds: 0.8, input: tone).suffix(16384))
        let dry = Array(render(carrier(false), seconds: 0.8).suffix(16384))
        XCTAssertTrue(vocoded.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(rms(vocoded[...]), 0.005)
        let focus = { (x: [Float]) in self.band(x, 1570) / max(self.band(x, 262), 1e-9) }
        XCTAssertGreaterThan(focus(vocoded), focus(dry) * 10, "energy moves to where the voice is")
    }

    func testAddedParametersAreKeyedAndOldIdsStay() {
        for id in Int(LY_FSAT_TYPE)..<Int(LY_PARAM_COUNT) {
            XCTAssertNotNil(LYSynthParameters.byID[id], "parameter \(id) has no key")
        }
        XCTAssertEqual(Int(LY_FSAT_TYPE), Int(LY_CHORUS_WIDTH) + 1)
        XCTAssertEqual(LYSynthNames.saturations.count, Int(LY_FSAT_COUNT))
        XCTAssertEqual(LYSynthNames.routings.count, Int(LY_ROUTING_COUNT))
        XCTAssertTrue(LYSynthNames.destinations.allSatisfy { !$0.isEmpty })
    }
}
