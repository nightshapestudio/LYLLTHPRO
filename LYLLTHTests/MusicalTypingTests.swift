import XCTest
import AppKit
@testable import LYLLTH

@MainActor
final class MusicalTypingTests: XCTestCase {
    private var sent: [(UInt8, UInt8, UInt8)] = []

    override func setUp() {
        sent = []
        LYMIDIInput.shared.setTarget(nil)
        LYMIDIInput.shared.recordHandler = { [weak self] status, d1, d2, _ in self?.sent.append((status, d1, d2)) }
    }

    override func tearDown() {
        LYMusicalTyping.shared.close()
        LYMIDIInput.shared.recordHandler = nil
    }

    private func key(_ code: UInt16, down: Bool = true, flags: NSEvent.ModifierFlags = [], repeat isRepeat: Bool = false) -> Bool {
        let event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                     isARepeat: isRepeat, keyCode: code)!
        return LYMusicalTyping.shared.handle(event)
    }

    func testTheLogicLayoutPlaysAndReleasesNotes() {
        let typing = LYMusicalTyping.shared
        typing.open()
        XCTAssertTrue(key(0))                       // A = C4
        XCTAssertTrue(key(13))                      // W = C#4
        XCTAssertTrue(key(39))                      // ' = F5
        XCTAssertFalse(key(0, repeat: true) && sent.count > 3, "key repeat never retriggers")
        XCTAssertEqual(sent.filter { $0.0 == 0x90 }.map(\.1), [60, 61, 77])
        XCTAssertTrue(sent.allSatisfy { $0.2 == 100 })
        // Octave up while A is held: A's release is still C4.
        XCTAssertTrue(key(7))
        XCTAssertEqual(typing.octave, 5)
        XCTAssertTrue(key(0, down: false))
        XCTAssertEqual(sent.last?.0, 0x80)
        XCTAssertEqual(sent.last?.1, 60)
        XCTAssertTrue(key(0))
        XCTAssertEqual(sent.last?.1, 72, "A now plays C5")
    }

    func testVelocitySustainBendAndMod() {
        let typing = LYMusicalTyping.shared
        typing.open()
        XCTAssertTrue(key(8))                       // C: velocity down
        XCTAssertEqual(typing.velocity, 84)
        XCTAssertTrue(key(48))                      // TAB down
        XCTAssertEqual(sent.last.map { [$0.0, $0.1, $0.2] }, [0xB0, 64, 127])
        XCTAssertTrue(key(48, down: false))
        XCTAssertEqual(sent.last.map { [$0.0, $0.1, $0.2] }, [0xB0, 64, 0])
        XCTAssertTrue(key(19))                      // 2: bend up
        XCTAssertEqual(sent.last.map { Int($0.1) | Int($0.2) << 7 }, 16383)
        XCTAssertTrue(key(19, down: false))
        XCTAssertEqual(sent.last.map { Int($0.1) | Int($0.2) << 7 }, 8192)
        XCTAssertTrue(key(28))                      // 8: mod full
        XCTAssertEqual(sent.last.map { [$0.0, $0.1, $0.2] }, [0xB0, 1, 127])
    }

    func testShortcutsAndOtherKeysPassThrough() {
        LYMusicalTyping.shared.open()
        XCTAssertFalse(key(40, flags: .command), "⌘K and other shortcuts are not notes")
        XCTAssertFalse(key(49), "Space still runs the transport")
        XCTAssertTrue(sent.isEmpty)
    }

    func testClosingReleasesEverything() {
        let typing = LYMusicalTyping.shared
        typing.open()
        _ = key(0); _ = key(1); _ = key(48)
        typing.close()
        XCTAssertTrue(typing.held.isEmpty)
        XCTAssertEqual(Set(sent.filter { $0.0 == 0x80 }.map(\.1)), [60, 62])
        XCTAssertFalse(LYMusicalTyping.isOpen)
    }
}
