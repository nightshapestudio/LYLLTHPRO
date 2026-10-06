import XCTest
@testable import LYLLTH

/// The phase distortion warps: PD SQUARE and the resonant PD shapes.
@MainActor
final class LUNATKPhaseDistortionTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate
    private let f0 = 220.0

    /// A3 on oscillator A's sine (BASIC SHAPES at 0), no filter.
    private func note(_ mode: Int, _ amount: Float) -> [Float] {
        var patch = LYSynthPatch.initPatch
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 1)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_RANDPHASE), 0)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_WARPMODE), Float(mode))
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_WARPAMT), amount)
        patch.set(LY_FILTER_ON, 0)
        patch.set(LY_MASTER, 0.3)
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        _ = render(s, seconds: 0.2)
        s.noteOn(57, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        return Array(render(s, seconds: 0.6).suffix(Int(0.3 * rate)))
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

    /// Harmonics 1…16, in dB against the loudest.
    private func harmonics(_ x: [Float]) -> [Double] {
        let levels = (1...16).map { k -> Double in
            var re = 0.0, im = 0.0
            for (i, v) in x.enumerated() {
                let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(x.count))
                re += Double(v) * w * cos(2 * .pi * Double(k) * f0 * Double(i) / rate)
                im += Double(v) * w * sin(2 * .pi * Double(k) * f0 * Double(i) / rate)
            }
            return (re * re + im * im).squareRoot()
        }
        let top = levels.max()!
        return levels.map { 20 * log10(max($0 / top, 1e-9)) }
    }

    func testNamedAndOrdered() {
        XCTAssertEqual(LYSynthNames.warps.count, Int(LY_WARP_COUNT))
        XCTAssertEqual(LYSynthNames.warpsB.count, Int(LY_WARP_COUNT))
        XCTAssertEqual(Set(LYSynthNames.warpOrder), Set(0..<Int(LY_WARP_COUNT)))
    }

    func testAmountZeroIsThePlainTable() {
        let plain = note(LY_WARP_OFF, 0)
        for mode in [LY_WARP_PD_SQUARE, LY_WARP_PD_RESO_SAW, LY_WARP_PD_RESO_TRI] {
            XCTAssertEqual(note(mode, 0), plain, "mode \(mode) at 0")
        }
    }

    func testSquareIsOddHarmonics() {
        let h = harmonics(note(LY_WARP_PD_SQUARE, 0.7))
        XCTAssertGreaterThan(h[2], -12, "3rd: \(h[2])")
        XCTAssertGreaterThan(h[4], -15, "5th: \(h[4])")
        XCTAssertLessThan(h[1], -60, "2nd: \(h[1])")
        XCTAssertLessThan(h[3], -60, "4th: \(h[3])")
    }

    func testResonanceRisesWithAmountAndNeverClicks() {
        for mode in [LY_WARP_PD_RESO_SAW, LY_WARP_PD_RESO_TRI] {
            var previous = 0
            for amount: Float in [0.1, 0.3, 0.6] {
                let x = note(mode, amount)
                let h = harmonics(x)
                let peak = h.firstIndex(of: 0)! + 1
                XCTAssertGreaterThan(peak, previous, "mode \(mode) at \(amount): the peak is at harmonic \(peak)")
                previous = peak
                let step = zip(x, x.dropFirst()).map { abs($1 - $0) }.max()!
                XCTAssertLessThan(step, 0.1, "mode \(mode) at \(amount) jumps")
            }
        }
    }
}
