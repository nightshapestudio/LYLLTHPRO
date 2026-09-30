import XCTest
@testable import LYLLTH

/// Oscillator C: keyed, off by default, the same engine as A and B.
@MainActor
final class LUNATKOscillatorCTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

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
        s.noteOn(57, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let frames = Int(0.4 * rate)
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

    func testKeyedAndOffByDefault() {
        for local in 0..<Int(LY_OSC_PARAM_COUNT) {
            XCTAssertNotNil(LYSynthParameters.byID[LYSynthParameters.oscillator(2, local)], "C field \(local)")
        }
        XCTAssertEqual(LYSynthParameters.byKey["c.on"]?.id, Int(LY_OSCC_BASE) + Int(LY_OSC_ON))
        XCTAssertEqual(LYSynthParameters.byKey["filter.routeC"]?.id, Int(LY_FILTER_ROUTE_C))
        XCTAssertEqual(LYSynthPatch.initPatch.value(LYSynthParameters.oscillator(2, LY_OSC_ON)), 0)
        XCTAssertEqual(LYSynthPatch.initPatch.value(LY_FILTER_ROUTE_C), 1)
        XCTAssertTrue(LYSynthNames.destinations.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(LYSynthNames.destinations[Int(LY_DST_C_WTPOS)], "C WT POS")
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
        let rms = { (x: [Float]) in (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }
        XCTAssertLessThan(rms(through), rms(around) * 0.1)
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
    }
}
