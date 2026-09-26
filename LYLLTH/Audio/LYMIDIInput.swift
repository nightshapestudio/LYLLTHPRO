import CoreMIDI
import Foundation

/// Listens to every MIDI source on the Mac and hands channel messages to
/// whichever LUNATK is the target: the selected track's, or the first
/// record-armed synth track. Messages keep their host timestamps, so a
/// hardware keyboard plays with the same timing the sequencer gets.
@MainActor
final class LYMIDIInput: ObservableObject {
    static let shared = LYMIDIInput()

    @Published private(set) var sourceNames: [String] = []
    /// Bumped when a note arrives, for activity lights.
    @Published private(set) var activity = 0

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var started = false
    /// Read on CoreMIDI's thread. Swapped whole, never mutated in place.
    nonisolated(unsafe) private var target: LYSynthInstrument?
    /// Set while recording: every channel message, with its host time.
    nonisolated(unsafe) var recordHandler: ((UInt8, UInt8, UInt8, UInt64) -> Void)?
    /// Plays notes on a track that has no LUNATK (a DrumKit drum or synth
    /// track). Called on the main thread with note-ons only: (note, velocity).
    nonisolated(unsafe) var fallback: ((UInt8, UInt8) -> Void)?

    func start() {
        guard !started else { return }
        started = true
        let status = MIDIClientCreateWithBlock("LYLLTH" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.connectAllSources() }
        }
        guard status == noErr else { return }
        MIDIInputPortCreateWithProtocol(client, "LYLLTH IN" as CFString, ._1_0, &port) { [weak self] list, _ in
            self?.receive(list)
        }
        connectAllSources()
    }

    func setTarget(_ instrument: LYSynthInstrument?, fallback: ((UInt8, UInt8) -> Void)? = nil) {
        if target !== instrument { target?.allNotesOff() }
        target = instrument
        self.fallback = instrument == nil ? fallback : nil
    }

    /// A message from inside LYLLTH (Musical Typing): the same path as a
    /// hardware keyboard, stamped now.
    func inject(status: UInt8, data1: UInt8, data2: UInt8) {
        let now = mach_absolute_time()
        if let target { lysynth_midi(target.core, status, data1, data2, 0) }
        recordHandler?(status, data1, data2, now)
        if status & 0xF0 == 0x90 && data2 > 0 {
            if target == nil { fallback?(data1, data2) }
            activity &+= 1
        }
    }

    private func connectAllSources() {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(port, source, nil)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr, let name {
                names.append((name.takeRetainedValue() as String).uppercased())
            }
        }
        sourceNames = names
    }

    /// MIDI 1.0 channel voice messages arrive as type-2 universal packets.
    nonisolated private func receive(_ list: UnsafePointer<MIDIEventList>) {
        let target = self.target
        let record = recordHandler
        guard target != nil || record != nil || fallback != nil else { return }
        var sawNote = false
        for packet in list.unsafeSequence() {
            let host = packet.pointee.timeStamp
            let words = MIDIEventPacket.WordCollection(packet)
            for word in words where (word >> 28) == 0x2 {
                let status = UInt8((word >> 16) & 0xFF)
                let data1 = UInt8((word >> 8) & 0x7F)
                let data2 = UInt8(word & 0x7F)
                if let target { lysynth_midi(target.core, status, data1, data2, host) }
                record?(status, data1, data2, host)
                if status & 0xF0 == 0x90 { sawNote = true }
                if target == nil, status & 0xF0 == 0x90, data2 > 0, let fallback = self.fallback {
                    DispatchQueue.main.async { fallback(data1, data2) }
                }
            }
        }
        if sawNote {
            DispatchQueue.main.async { [weak self] in self?.activity &+= 1 }
        }
    }
}
