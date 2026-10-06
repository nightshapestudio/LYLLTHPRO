import XCTest
@testable import LYLLTH

/// Oscillator C: keyed, off by default, the same engine as A and B; and the
/// thirty-two voice ceiling.
@MainActor
final class LUNATKOscillatorCTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    private func render(_ instrument: LYSynthInstrument, seconds: Double) -> [Float] {
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames), right = left
        var position = 0
        while position < frames {
            let n = min(256, frames - position)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    lysynth_render(instrument.core, l.baseAddress! + position, r.baseAddress! + position, Int32(n), 0)
                }
            }
            position += n
        }
        return left
    }

    /// A3 for 0.4 s, after the patch has settled (parameters glide over 5 ms).
    private func render(_ edit: (inout LYSynthPatch) -> Void) -> [Float] {
        var patch = LYSynthPatch.initPatch
        for o in [0, 2] {
            patch.set(LYSynthParameters.oscillator(o, LY_OSC_RANDPHASE), 0)
        }
        patch.set(LY_FILTER_ON, 0)
        patch.set(LY_MASTER, 0.1)
        edit(&patch)
        let s = LYSynthInstrument()
        s.apply(patch, bpm: 120)
        _ = render(s, seconds: 0.1)
        s.noteOn(57, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        return render(s, seconds: 0.4)
    }

    private func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }

    func testKeyedAndOffByDefault() {
        for local in 0..<Int(LY_OSC_PARAM_COUNT) {
            XCTAssertNotNil(LYSynthParameters.byID[LYSynthParameters.oscillator(2, local)], "C field \(local)")
        }
        XCTAssertEqual(LYSynthParameters.byKey["c.on"]?.id, Int(LY_OSCC_BASE) + Int(LY_OSC_ON))
        XCTAssertEqual(LYSynthParameters.byKey["filter.routeC"]?.id, Int(LY_FILTER_ROUTE_C))
        XCTAssertEqual(LYSynthParameters.byKey["c.engine"]?.id, Int(LY_OSC_ENGINE_C))
        XCTAssertEqual(LYSynthParameters.byKey["c.spectral.tilt"]?.id, Int(LY_SPECTRAL_TILT_C))
        // A's and B's engine keys did not move.
        XCTAssertEqual(LYSynthParameters.byKey["b.engine"]?.id, Int(LY_OSC_ENGINE_B))
        XCTAssertEqual(LYSynthParameters.byKey["b.grain.spray"]?.id, Int(LY_GRAIN_SPRAY_B))
        XCTAssertEqual(LYSynthPatch.initPatch.value(LYSynthParameters.oscillator(2, LY_OSC_ON)), 0)
        XCTAssertEqual(LYSynthPatch.initPatch.value(LY_FILTER_ROUTE_C), 1)
        XCTAssertTrue(LYSynthNames.destinations.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(LYSynthNames.destinations[Int(LY_DST_C_WTPOS)], "C WT POS")
        XCTAssertEqual(Set(LYSynthParameters.all.map(\.id)).count, LYSynthParameters.all.count)
    }

    func testCPlaysExactlyLikeAWithTheSameSettings() {
        let a = render { _ in }
        let c = render { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 0)
            p.set(LYSynthParameters.oscillator(2, LY_OSC_ON), 1)
        }
        XCTAssertGreaterThan(a.map(abs).max()!, 0.01)
        XCTAssertEqual(a, c)
    }

    func testRouteCTakesItAroundTheFilter() {
        let dark: (inout LYSynthPatch) -> Void = { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 0)
            p.set(LYSynthParameters.oscillator(2, LY_OSC_ON), 1)
            p.set(LY_FILTER_ON, 1)
            p.set(LY_FILTER_CUTOFF, 0.2)
        }
        let through = render(dark), around = render { p in dark(&p); p.set(LY_FILTER_ROUTE_C, 0) }
        XCTAssertLessThan(rms(through), rms(around) * 0.1)
    }

    func testCHasItsOwnEngine() {
        let wavetable = render { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 0)
            p.set(LYSynthParameters.oscillator(2, LY_OSC_ON), 1)
        }
        let spectral = render { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 0)
            p.set(LYSynthParameters.oscillator(2, LY_OSC_ON), 1)
            p.set(LY_OSC_ENGINE_C, Float(LY_OSC_ENGINE_SPECTRAL))
        }
        XCTAssertGreaterThan(rms(spectral), 0.001)
        XCTAssertNotEqual(wavetable, spectral)
    }

    func testPatchesFromBeforeCStillLoad() throws {
        let json = #"{"name":"OLD","values":{"a.level":0.5},"tableA":3,"tableB":4}"#
        let patch = try JSONDecoder().decode(LYSynthPatch.self, from: Data(json.utf8))
        XCTAssertNil(patch.tableC)
        XCTAssertEqual(patch.factoryTable(2), Int(LY_TABLE_BASIC))
        var next = patch
        next.setFactoryTable(2, Int(LY_TABLE_GLASS))
        XCTAssertEqual(next.tableName(2), LYSynthNames.tables[Int(LY_TABLE_GLASS)])
        XCTAssertEqual(next.factoryTable(0), 3)
        next.setCustomTable(2, "NS OBSIDIAN")
        XCTAssertEqual(next.customTables, ["NS OBSIDIAN"])
    }

    func testThirtyTwoVoices() {
        XCTAssertEqual(LYSynthParameters.byID[Int(LY_VOICES)]?.range.upperBound, 32)
        for voices in [16, 32] {
            var patch = LYSynthPatch.initPatch
            patch.set(LY_VOICES, Float(voices))
            let s = LYSynthInstrument()
            s.apply(patch, bpm: 120)
            for note in 0..<24 { s.noteOn(UInt8(36 + note * 2), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
            _ = render(s, seconds: 0.05)
            var display = LYSynthDisplay()
            lysynth_get_display(s.core, &display)
            XCTAssertEqual(Int(display.activeVoices), min(voices, 24), "VOICES \(voices)")
        }
    }
}
