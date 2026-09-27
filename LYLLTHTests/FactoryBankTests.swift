import XCTest
@testable import LYLLTH

final class FactoryBankTests: XCTestCase {
    func testTheBankLoadsWithEveryCategoryAndItsDocumentation() {
        let bank = LYSynthFactoryBank.presets
        XCTAssertEqual(bank.count, 424)
        let counts = Dictionary(grouping: bank, by: { $0.category ?? "" }).mapValues(\.count)
        XCTAssertEqual(counts, ["BASS": 68, "LEAD": 74, "PAD": 62, "KEYS": 55, "PLUCK": 16, "ARP": 63, "MOTION": 29, "DRONE": 29, "PERC": 12, "FX": 16])
        XCTAssertTrue(bank.allSatisfy { $0.info != nil && !($0.info?.mix.isEmpty ?? true) })
        XCTAssertEqual(Set(bank.map(\.name)).count, 424, "names are unique")
        // Every stored value is a real parameter.
        for patch in bank { for key in patch.values.keys { XCTAssertNotNil(LYSynthParameters.byKey[key], "\(patch.name): \(key)") } }
        // INIT, the bank, then the originals.
        XCTAssertEqual(LYSynthPatch.factory.first?.name, "INIT")
        XCTAssertEqual(LYSynthPatch.factory.filter { $0.category == "ORIGINAL" }.count, LYSynthPatch.original.count)
    }

    /// The showcase presets play NIGHTSHAPE's own wavetables; every one they
    /// name must ship in the bundle and load.
    @MainActor
    func testFactoryWavetablesShipAndResolve() {
        let library = LYWavetableLibrary.shared
        XCTAssertEqual(library.factoryNames.count, 12)
        let used = Set(LYSynthFactoryBank.presets.flatMap { [$0.customTableA, $0.customTableB].compactMap { $0 } })
        XCTAssertFalse(used.isEmpty)
        for name in used {
            XCTAssertTrue(library.factoryNames.contains(name), name)
            XCTAssertEqual(library.frameCount(name), 64, name)
        }
    }
}
