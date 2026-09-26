import XCTest
@testable import LYLLTH

final class FactoryBankTests: XCTestCase {
    func testTheBankLoadsWithEveryCategoryAndItsDocumentation() {
        let bank = LYSynthFactoryBank.presets
        XCTAssertEqual(bank.count, 160)
        let counts = Dictionary(grouping: bank, by: { $0.category ?? "" }).mapValues(\.count)
        XCTAssertEqual(counts, ["BASS": 24, "LEAD": 18, "PAD": 22, "KEYS": 16, "PLUCK": 16, "MOTION": 18, "DRONE": 18, "PERC": 12, "FX": 16])
        XCTAssertTrue(bank.allSatisfy { $0.info != nil && !($0.info?.mix.isEmpty ?? true) })
        XCTAssertEqual(Set(bank.map(\.name)).count, 160, "names are unique")
        // Every stored value is a real parameter.
        for patch in bank { for key in patch.values.keys { XCTAssertNotNil(LYSynthParameters.byKey[key], "\(patch.name): \(key)") } }
        // INIT, the bank, then the originals.
        XCTAssertEqual(LYSynthPatch.factory.first?.name, "INIT")
        XCTAssertEqual(LYSynthPatch.factory.filter { $0.category == "ORIGINAL" }.count, LYSynthPatch.original.count)
    }
}
