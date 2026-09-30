import XCTest
@testable import LYLLTH

/// SAMPLE, GRANULAR and SPECTRAL.
@MainActor
final class LUNATKOscillatorModeTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    private func mode(_ field: Int) -> Int { LYSynthParameters.oscillatorMode(0, field) }

    /// A second of A4 at 44.1 kHz, registered as a sample.
    private func sineSample() -> String {
        let samples = (0..<44_100).map { Float(0.8 * sin(2 * Double.pi * 440 * Double($0) / 44_100)) }
        return LYSampleLibrary.shared.store(LYSynthSample(samples: samples, rate: 44_100), named: "TEST SINE 440", writeToFolder: false)
    }

    private func render(note: Int = 57, seconds: Double = 0.6, _ edit: (inout LYSynthPatch) -> Void) -> [Float] {
        var patch = LYSynthPatch.initPatch
        patch.set(LY_FILTER_ON, 0)
        patch.set(LY_MASTER, 0.3)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_RANDPHASE), 0)
        edit(&patch)
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        s.noteOn(note, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames), right = left
        var position = 0
        while position < frames {
            let n = min(256, frames - position)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    lysynth_render(s.core, l.baseAddress! + position, r.baseAddress! + position, Int32(n), 0)
                }
            }
            position += n
        }
        return left
    }

    private func level(_ x: ArraySlice<Float>, _ hz: Double) -> Double {
        var re = 0.0, im = 0.0
        for (k, v) in x.enumerated() {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(k) / Double(x.count))
            re += Double(v) * w * cos(2 * .pi * hz * Double(k) / rate)
            im += Double(v) * w * sin(2 * .pi * hz * Double(k) / rate)
        }
        return (re * re + im * im).squareRoot()
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        20 * log10(max(1e-12, Double((x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot())))
    }

    func testKeyedWithSafeDefaults() {
        for o in 0..<3 {
            for field in 0..<Int(LY_OSX_STRIDE) {
                XCTAssertNotNil(LYSynthParameters.byID[LYSynthParameters.oscillatorMode(o, field)], "osc \(o) field \(field)")
            }
        }
        XCTAssertEqual(LYSynthPatch.initPatch.value(mode(LY_OSX_MODE)), Float(LY_OSCMODE_WAVETABLE))
        XCTAssertEqual(LYSynthPatch.initPatch.value(mode(LY_OSX_SPECTRAL)), Float(LY_SPEC_OFF))
        XCTAssertEqual(LYSynthPatch.initPatch.value(mode(LY_OSX_ROOT)), 60)
        XCTAssertEqual(LYSynthNames.spectralWarps.count, Int(LY_SPEC_COUNT))
        XCTAssertEqual(LYSynthNames.oscillatorModes.count, Int(LY_OSCMODE_COUNT))
    }

    func testSamplePlaysInTuneFromItsRoot() {
        let name = sineSample()
        for (note, hz) in [(69, 440.0), (81, 880.0)] {
            let out = render(note: note) { p in
                p.sampleA = name
                p.set(mode(LY_OSX_MODE), Float(LY_OSCMODE_SAMPLE))
                p.set(mode(LY_OSX_ROOT), 69)
                p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
            }
            let slice = out[4_000..<20_000]
            XCTAssertGreaterThan(level(slice, hz), level(slice, hz * 1.06) * 30, "note \(note)")
        }
    }

    func testOneShotStopsAndLoopCarriesOn() {
        let name = sineSample()
        let play = { (loop: Float) in
            self.render(note: 69, seconds: 1.4) { p in
                p.sampleA = name
                p.set(self.mode(LY_OSX_MODE), Float(LY_OSCMODE_SAMPLE))
                p.set(self.mode(LY_OSX_ROOT), 69)
                p.set(self.mode(LY_OSX_LOOP), loop)
            }
        }
        let late = Int(1.2 * rate)..<Int(1.3 * rate)
        XCTAssertLessThan(rms(play(0)[late]), -100)
        XCTAssertGreaterThan(rms(play(1)[late]), -40)
    }

    func testGranularSitsNearTheWavetablesLevel() {
        let table = render { _ in }
        let grains = render { p in p.set(self.mode(LY_OSX_MODE), Float(LY_OSCMODE_GRANULAR)) }
        XCTAssertEqual(rms(grains[8_000...]), rms(table[8_000...]), accuracy: 4)
        // In tune: the table plays a cycle per period.
        XCTAssertGreaterThan(level(grains[8_000..<24_000], 220), level(grains[8_000..<24_000], 233) * 4)
    }

    func testSpectralWarpsKeepThePitchAndShapeTheHarmonics() {
        let saw: (inout LYSynthPatch) -> Void = { p in p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0.66) }
        let slice = 6_000..<22_000
        for type in 1..<Int(LY_SPEC_COUNT) {
            let out = render { p in saw(&p); p.set(self.mode(LY_OSX_SPECTRAL), Float(type)); p.set(self.mode(LY_OSX_SPECTRAL_AMT), 0) }
            XCTAssertGreaterThan(level(out[slice], 220), level(out[slice], 233) * 10, "\(LYSynthNames.spectralWarps[type]) at 0")
        }
        let odd = render { p in saw(&p); p.set(self.mode(LY_OSX_SPECTRAL), Float(LY_SPEC_ODD)); p.set(self.mode(LY_OSX_SPECTRAL_AMT), 1) }
        XCTAssertLessThan(level(odd[slice], 440), level(odd[slice], 660) * 0.01, "ODD at 1 keeps no even harmonics")
        let dark = render { p in saw(&p); p.set(self.mode(LY_OSX_SPECTRAL), Float(LY_SPEC_LOWPASS)); p.set(self.mode(LY_OSX_SPECTRAL_AMT), 0.8) }
        let open = render { p in saw(&p); p.set(self.mode(LY_OSX_SPECTRAL), Float(LY_SPEC_LOWPASS)); p.set(self.mode(LY_OSX_SPECTRAL_AMT), 0) }
        XCTAssertLessThan(level(dark[slice], 220 * 12), level(open[slice], 220 * 12) * 0.2)
    }

    func testPresetsCarryTheirSamples() throws {
        let name = sineSample()
        var patch = LYSynthPatch.initPatch
        patch.sampleB = name
        let file = LYSynthPresetFile.carrying(patch)
        let data = try XCTUnwrap(file.samples?[name])
        XCTAssertEqual(LYSampleLibrary.decode(data), LYSampleLibrary.shared.sample(named: name))
        let old = #"{"patch":{"name":"OLD","values":{},"tableA":0,"tableB":0},"wavetables":{}}"#
        XCTAssertNil(try JSONDecoder().decode(LYSynthPresetFile.self, from: Data(old.utf8)).samples)
    }
}
