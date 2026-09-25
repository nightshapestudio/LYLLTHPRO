import XCTest
import SwiftUI
@testable import LYLLTH

@MainActor
final class LUNATKTests: XCTestCase {
    private func render(_ synth: LYSynthInstrument, seconds: Double) -> (peak: Float, rms: Float, finite: Bool) {
        let block = 512
        var left = [Float](repeating: 0, count: block), right = left
        var peak: Float = 0, sum: Double = 0, count = 0, finite = true
        for _ in 0..<Int(seconds * LYSynthInstrument.sampleRate) / block {
            lysynth_render(synth.core, &left, &right, Int32(block), 0)
            for i in 0..<block {
                if !left[i].isFinite || !right[i].isFinite { finite = false }
                peak = max(peak, abs(left[i]), abs(right[i]))
                sum += Double(left[i] * left[i] + right[i] * right[i]); count += 2
            }
        }
        return (peak, Float((sum / Double(max(count, 1))).squareRoot()), finite)
    }

    func testEveryEffectRunsCleanInEveryPosition() {
        for (index, on) in LYSynthFXPage.onIDs.enumerated() {
            var patch = LYSynthPatch.initPatch
            patch.set(on, 1)
            // Put this effect first, the rest after, to exercise reordering.
            var order = LYSynthPatch.defaultEffectOrder
            order.removeAll { $0 == index }
            order.insert(index, at: 0)
            patch.setEffectOrder(order)
            XCTAssertEqual(patch.effectOrder, order)
            let synth = LYSynthInstrument()
            synth.apply(patch, bpm: 120)
            synth.noteOn(48, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
            let held = render(synth, seconds: 0.6)
            XCTAssertTrue(held.finite, LYSynthNames.effects[index])
            XCTAssertLessThan(held.peak, 1.3, LYSynthNames.effects[index])
            XCTAssertGreaterThan(held.rms, 0.01, LYSynthNames.effects[index])
            XCTAssertGreaterThan(synth.display().fxLevel.0 + 1, 0)
        }
    }

    func testArpeggiatorPlaysStepsInTime() {
        var patch = LYSynthPatch.initPatch
        patch.set(LY_ARP_ON, 1)
        patch.set(LY_ARP_RATE, 10 / 14)   // 1/16
        let synth = LYSynthInstrument()
        synth.apply(patch, bpm: 120)
        for note in [60, 64, 67] { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
        var steps = Set<Int32>()
        for _ in 0..<86 { _ = render(synth, seconds: 512 / 44_100); steps.insert(synth.display().arpStep) }
        steps.remove(-1)
        XCTAssertTrue((7...10).contains(steps.count), "\(steps.count) steps in a second at 1/16, 120 BPM")
    }

    func testOlderPatchesKeepTheirMeaning() throws {
        // A patch as the first LYLLTH build saved it: old keys, old values.
        let json = """
        {"name":"OLD","values":{"a.warpmode":6,"a.warp":0.5,"mx0.src":4,"mx0.dst":17,"mx0.amt":0.4,"lfo2.rate":0.3,"lfo1.retrig":1,"filter.type":1},
         "tableA":1,"tableB":0}
        """.data(using: .utf8)!
        let patch = try JSONDecoder().decode(LYSynthPatch.self, from: json)
        XCTAssertEqual(Int(patch.value(LYSynthParameters.oscillator(0, LY_OSC_WARPMODE))), Int(LY_WARP_FM))
        XCTAssertEqual(patch.routes(into: LY_DST_CUTOFF).first?.source, LY_SRC_LFO1)
        XCTAssertEqual(patch.value(LYSynthParameters.lfo(1, LY_LFO1_RATE)), 0.3)
        XCTAssertEqual(Int(patch.value(LYSynthParameters.lfo(0, LY_LFO1_RETRIG))), Int(LY_LFOMODE_TRIG))
        XCTAssertEqual(patch.effectOrder, LYSynthPatch.defaultEffectOrder)
        XCTAssertEqual(patch.value(LY_DELAY_ON), 0)
    }

    func testMatrixHasThirtyTwoSlotsWithAuxCurveAndBipolar() {
        var patch = LYSynthPatch.initPatch
        for slot in 0..<32 { XCTAssertNotNil(patch.route(source: LY_SRC_LFO1 + slot % 4, destination: 1 + slot, amount: 0.1)) }
        XCTAssertNil(patch.route(source: LY_SRC_MACRO1, destination: LY_DST_MASTER, amount: 0.1))
        XCTAssertEqual(patch.usedMatrixSlots.count, 32)
        patch.clearRoute(5)
        XCTAssertEqual(patch.usedMatrixSlots.count, 31)
        let data = try! JSONEncoder().encode(patch)
        XCTAssertEqual(try! JSONDecoder().decode(LYSynthPatch.self, from: data), patch)
    }

    func testFactoryBankIsNamedAndUnique() {
        let names = LYSynthPatch.factory.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains("NIGHT KEYS"), "the song migration points at NIGHT KEYS")
        XCTAssertTrue(names.contains("LUNAR SUPERSAW"))
    }
}
