import XCTest
@testable import LYLLTH

/// QUALITY: the voices at 2× or 4× the sample rate, filtered back down.
@MainActor
final class LUNATKQualityTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    /// C6 (1046.5 Hz) through the hard saturation, quiet enough that the
    /// master clipper stays out of it.
    private func saturatedNote(quality: Int) -> [Float] {
        var patch = LYSynthPatch.initPatch
        patch.set(LY_FILTER_CUTOFF, 1)
        patch.set(LY_FILTER_DRIVE, 1)
        patch.set(LY_FSAT_TYPE, Float(LY_FSAT_HARD))
        patch.set(LY_FSAT_DRIVE, 0.8)
        patch.set(LY_FSAT_MIX, 1)
        patch.set(LY_MASTER, 0.2)
        patch.set(LY_OVERSAMPLE, Float(quality))
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        _ = render(s, seconds: 0.2)
        s.noteOn(84, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        return Array(render(s, seconds: 0.9).suffix(Int(0.5 * rate)))
    }

    private func render(_ s: LYSynthInstrument, seconds: Double) -> [Float] {
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

    private func level(_ x: [Float], _ hz: Double) -> Double {
        var re = 0.0, im = 0.0
        for (i, v) in x.enumerated() {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(x.count))
            re += Double(v) * w * cos(2 * .pi * hz * Double(i) / rate)
            im += Double(v) * w * sin(2 * .pi * hz * Double(i) / rate)
        }
        return re * re + im * im
    }

    /// Energy folded back from above 22 050 Hz against the harmonics', in dB.
    /// At 44.1 kHz C6's harmonics fold to 147 Hz either side of a harmonic.
    private func aliasing(_ x: [Float]) -> Double {
        let f0 = 440 * pow(2, 15.0 / 12)
        var folded = 0.0, harmonic = 0.0
        for j in 0..<20 {
            for side in [147.0, -147.0] where Double(j) * f0 + side > 0 && Double(j) * f0 + side < 20_000 {
                folded += level(x, Double(j) * f0 + side)
            }
            if j > 0 { harmonic += level(x, Double(j) * f0) }
        }
        return 10 * log10(folded / harmonic)
    }

    func testQualityIsKeyedAndOffByDefault() {
        XCTAssertEqual(LYSynthParameters.byKey["quality"]?.id, Int(LY_OVERSAMPLE))
        XCTAssertEqual(LYSynthPatch.initPatch.value(LY_OVERSAMPLE), 0)
        XCTAssertEqual(LYSynthNames.qualities.count, Int(LY_OS_COUNT))
    }

    func testOversamplingTakesTheAliasingOutOfHardSaturation() {
        let off = aliasing(saturatedNote(quality: Int(LY_OS_OFF)))
        let two = aliasing(saturatedNote(quality: Int(LY_OS_2X)))
        let four = aliasing(saturatedNote(quality: Int(LY_OS_4X)))
        XCTAssertGreaterThan(off, -35, "the test note should alias at 1×")
        XCTAssertLessThan(two, off - 30, "2×: \(two) dB against \(off) dB")
        XCTAssertLessThan(four, off - 30, "4×: \(four) dB against \(off) dB")
    }

    func testOversamplingKeepsTheTone() {
        let f0 = 440 * pow(2, 15.0 / 12)
        let off = saturatedNote(quality: Int(LY_OS_OFF))
        let four = saturatedNote(quality: Int(LY_OS_4X))
        for k in 1...5 {
            let a = 10 * log10(level(off, Double(k) * f0)), b = 10 * log10(level(four, Double(k) * f0))
            XCTAssertEqual(a, b, accuracy: 1, "harmonic \(k)")
        }
    }
}
