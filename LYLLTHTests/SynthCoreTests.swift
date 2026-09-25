import XCTest
@testable import LYLLTH

@MainActor
final class SynthCoreTests: XCTestCase {
    private func render(_ instrument: LYSynthInstrument, seconds: Double) -> (peak: Float, rms: Float, finite: Bool) {
        let block = 512
        var left = [Float](repeating: 0, count: block), right = left
        var peak: Float = 0, sum: Double = 0, count = 0, finite = true
        for _ in 0..<Int(seconds * LYSynthInstrument.sampleRate) / block {
            lysynth_render(instrument.core, &left, &right, Int32(block), 0)
            for i in 0..<block {
                if !left[i].isFinite || !right[i].isFinite { finite = false }
                peak = max(peak, abs(left[i]), abs(right[i]))
                sum += Double(left[i] * left[i] + right[i] * right[i]); count += 2
            }
        }
        return (peak, Float((sum / Double(max(count, 1))).squareRoot()), finite)
    }

    func testEveryFactorySoundPlaysCleanlyAndReleases() {
        for patch in LYSynthPatch.factory {
            let synth = LYSynthInstrument()
            synth.apply(patch, bpm: 120)
            for note in [48, 55, 60, 64] { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
            let held = render(synth, seconds: 1.5)
            XCTAssertTrue(held.finite, "\(patch.name) produced NaN/inf")
            XCTAssertGreaterThan(held.rms, 0.005, "\(patch.name) is silent")
            XCTAssertLessThan(held.peak, 1.2, "\(patch.name) clips hard")
            for note in [48, 55, 60, 64] { synth.noteOff(UInt8(note), atHostTime: 0) }
            _ = render(synth, seconds: 4)
            let tail = render(synth, seconds: 0.5)
            XCTAssertLessThan(tail.rms, 0.001, "\(patch.name) does not release")
        }
    }

    func testHeavyPatchRendersFasterThanRealtime() {
        let synth = LYSynthInstrument()
        var patch = LYSynthPatch.factory(named: "NIGHT PAD")!
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 16)
        patch.set(LYSynthParameters.oscillator(1, LY_OSC_UNISON), 16)
        patch.set(LY_VOICES, 16)
        synth.apply(patch, bpm: 120)
        for note in 48..<64 { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
        let start = Date()
        _ = render(synth, seconds: 2)
        let elapsed = Date().timeIntervalSince(start)
        print("LYLLTH SYNTH worst case: 16 voices x 2 osc x 16 unison, 2 s of audio in \(String(format: "%.3f", elapsed)) s (\(String(format: "%.1f", elapsed / 2 * 100))% of one core)")
        XCTAssertLessThan(elapsed, 2.0)
    }
}
