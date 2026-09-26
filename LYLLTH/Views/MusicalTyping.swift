import AppKit
import SwiftUI

/// ⌘K: play the selected track from the computer keyboard, laid out like
/// Logic's Musical Typing. Notes go through the same path as a MIDI
/// keyboard (LYMIDIInput), so they play the selected or armed track and
/// record while recording.
///
///   A W S E D F T G Y H U J K O L P ; '   notes, C to F an octave up
///   Z / X  octave down / up      C / V  velocity down / up
///   TAB    sustain               1 / 2  pitch bend down / up (held)
///   3–8    mod wheel, off to full
@MainActor
final class LYMusicalTyping: ObservableObject {
    static let shared = LYMusicalTyping()
    /// Read by LUNATK's own key monitor, which steps aside while this is open.
    nonisolated(unsafe) static var isOpen = false

    @Published private(set) var octave = 4          // C4 = MIDI 60
    @Published private(set) var velocity = 100
    @Published private(set) var sustain = false
    @Published private(set) var bend = 0            // -1, 0, 1
    @Published private(set) var modLevel = 0        // 0...5
    @Published private(set) var held: Set<Int> = [] // sounding MIDI notes

    private var keyNotes: [UInt16: Int] = [:]
    private var monitor: Any?

    /// Key code to semitone above the octave's C, Logic's layout.
    static let noteKeys: [UInt16: Int] = [
        0: 0, 13: 1, 1: 2, 14: 3, 2: 4, 3: 5, 17: 6, 5: 7, 16: 8, 4: 9, 32: 10, 38: 11,
        40: 12, 31: 13, 37: 14, 35: 15, 41: 16, 39: 17,
    ]
    /// The letter printed on each key, by semitone.
    static let labels: [Int: String] = [
        0: "A", 1: "W", 2: "S", 3: "E", 4: "D", 5: "F", 6: "T", 7: "G", 8: "Y", 9: "H", 10: "U", 11: "J",
        12: "K", 13: "O", 14: "L", 15: "P", 16: ";", 17: "'",
    ]
    private static let modKeys: [UInt16: Int] = [20: 0, 21: 1, 23: 2, 22: 3, 26: 4, 28: 5]

    var baseNote: Int { (octave + 1) * 12 }

    /// Whether a key belongs to Musical Typing right now.
    nonisolated static func claims(_ event: NSEvent) -> Bool {
        guard isOpen, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.window?.firstResponder is NSTextView { return false }
        return noteKeys[event.keyCode] != nil || [6, 7, 8, 9, 48, 18, 19, 20, 21, 23, 22, 26, 28].contains(event.keyCode)
    }
    var rangeName: String { LYPianoRoll.name(baseNote) + "–" + LYPianoRoll.name(min(127, baseNote + 17)) }

    func open() {
        guard monitor == nil else { return }
        Self.isOpen = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Self.isOpen = false
        releaseEverything()
    }

    /// Mouse on the panel's keys.
    func press(_ note: Int) {
        guard (0...127).contains(note), !held.contains(note) else { return }
        held.insert(note)
        send(0x90, UInt8(note), UInt8(velocity))
    }

    func release(_ note: Int) {
        guard held.remove(note) != nil else { return }
        send(0x80, UInt8(note), 0)
    }

    func shiftOctave(_ step: Int) { octave = min(max(octave + step, 0), 9) }
    func shiftVelocity(_ step: Int) { velocity = min(max(velocity + step * 16, 1), 127) }

    // MARK: Keys

    func handle(_ event: NSEvent) -> Bool {
        // Text fields and ⌘ / ⌃ / ⌥ shortcuts keep their keys; so does Space.
        if event.window?.firstResponder is NSTextView { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        let down = event.type == .keyDown
        let code = event.keyCode
        if let semitone = Self.noteKeys[code] {
            if down {
                guard !event.isARepeat, keyNotes[code] == nil else { return true }
                let note = baseNote + semitone
                guard note <= 127 else { return true }
                keyNotes[code] = note
                press(note)
            } else if let note = keyNotes.removeValue(forKey: code) {
                release(note)
            }
            return true
        }
        let controls: Set<UInt16> = Set([6, 7, 8, 9, 48, 18, 19]).union(Self.modKeys.keys)
        guard controls.contains(code) else { return false }
        // Only sustain and bend act on release; the rest act on press.
        if !down && ![48, 18, 19].contains(code) { return true }
        switch code {
        case 6: if !event.isARepeat { shiftOctave(-1) }
        case 7: if !event.isARepeat { shiftOctave(1) }
        case 8: shiftVelocity(-1)
        case 9: shiftVelocity(1)
        case 48:
            guard !event.isARepeat else { return true }
            sustain = down
            send(0xB0, 64, down ? 127 : 0)
        case 18, 19:
            guard !event.isARepeat else { return true }
            bend = down ? (code == 18 ? -1 : 1) : 0
            let value = down ? (code == 18 ? 0 : 16383) : 8192
            send(0xE0, UInt8(value & 0x7F), UInt8(value >> 7))
        default:
            guard let level = Self.modKeys[code] else { return false }
            modLevel = level
            send(0xB0, 1, UInt8((Double(level) / 5 * 127).rounded()))
        }
        return true
    }

    private func releaseEverything() {
        for note in held { send(0x80, UInt8(note), 0) }
        held = []
        keyNotes = [:]
        if sustain { send(0xB0, 64, 0) }
        sustain = false
        if bend != 0 { send(0xE0, 0, 64) }
        bend = 0
    }

    private func send(_ status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        LYMIDIInput.shared.inject(status: status, data1: data1, data2: data2)
    }
}

// MARK: - Panel

/// The mini keyboard: an octave and a half with the computer keys printed
/// on it, lit while they sound, and the current octave, velocity, sustain,
/// bend and mod wheel.
struct LYMusicalTypingPanel: View {
    @ObservedObject var typing: LYMusicalTyping
    let target: String
    let accent: Color

    private let whiteSemitones = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17]
    private let blackSemitones = [1, 3, 6, 8, 10, 13, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLAYING").font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.4).foregroundStyle(LYLLTHTheme.dim)
                    Text(target).font(LYLLTHTheme.label(10, weight: .bold)).tracking(1).foregroundStyle(accent).lineLimit(1)
                }
                .frame(width: 190, alignment: .leading)
                readout("OCTAVE", typing.rangeName, keys: "Z  X")
                readout("VELOCITY", "\(typing.velocity)", keys: "C  V")
                light("SUSTAIN", typing.sustain, keys: "TAB")
                light(typing.bend < 0 ? "BEND ↓" : (typing.bend > 0 ? "BEND ↑" : "BEND"), typing.bend != 0, keys: "1  2")
                readout("MOD", typing.modLevel == 0 ? "OFF" : "\(typing.modLevel * 20)%", keys: "3–8")
                Spacer(minLength: 0)
            }
            keyboard
                .frame(height: 118)
        }
        .padding(14)
        .background(Color(hex: 0x07080B))
    }

    private var keyboard: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(whiteSemitones.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(whiteSemitones.enumerated()), id: \.offset) { index, semitone in
                    key(semitone, black: false)
                        .frame(width: whiteWidth - 3, height: geo.size.height)
                        .offset(x: CGFloat(index) * whiteWidth)
                }
                ForEach(blackSemitones, id: \.self) { semitone in
                    let leftWhite = whiteSemitones.lastIndex { $0 < semitone } ?? 0
                    key(semitone, black: true)
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.6)
                        .offset(x: CGFloat(leftWhite + 1) * whiteWidth - whiteWidth * 0.31 - 1.5)
                }
            }
        }
    }

    private func key(_ semitone: Int, black: Bool) -> some View {
        let note = typing.baseNote + semitone
        let lit = typing.held.contains(note)
        return ZStack(alignment: .bottom) {
            Rectangle().fill(lit ? accent.opacity(black ? 0.9 : 0.55) : (black ? Color(hex: 0x15161B) : LYLLTHTheme.chromeText.opacity(0.9)))
            Rectangle().stroke(lit ? accent : LYLLTHTheme.lineStrong, lineWidth: 1)
            VStack(spacing: 2) {
                Text(LYMusicalTyping.labels[semitone] ?? "")
                    .font(LYLLTHTheme.label(black ? 9 : 11, weight: .bold))
                    .foregroundStyle(black ? LYLLTHTheme.text : Color.black.opacity(0.75))
                if semitone % 12 == 0 {
                    Text(LYPianoRoll.name(note)).font(LYLLTHTheme.value(7.5)).foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .padding(.bottom, 8)
        }
        .lyBloom(accent, isOn: lit)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in typing.press(note) }
            .onEnded { _ in typing.release(note) })
    }

    private func readout(_ title: String, _ value: String, keys: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.4).foregroundStyle(LYLLTHTheme.dim)
            Text(value).font(LYLLTHTheme.value(12)).foregroundStyle(LYLLTHTheme.text)
            Text(keys).font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
        }
        .frame(minWidth: 62, alignment: .leading)
    }

    private func light(_ title: String, _ on: Bool, keys: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(on ? accent : LYLLTHTheme.lineStrong).frame(width: 6, height: 6).lyBloom(accent, isOn: on)
                Text(title).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1.2).foregroundStyle(on ? LYLLTHTheme.text : LYLLTHTheme.dim)
            }
            Text(keys).font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
        }
        .frame(minWidth: 62, alignment: .leading)
    }
}
