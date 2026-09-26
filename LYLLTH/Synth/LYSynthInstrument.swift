import AVFoundation
import NightshapeAudioEngine

/// One LUNATK on one track. Owns the C++ core and the source node the
/// engine plugs into the track's channel.
final class LYSynthInstrument: NightshapeTrackInstrument {
    static let sampleRate = 44_100.0

    let core: OpaquePointer
    private(set) var patch: LYSynthPatch?
    private(set) var bpm: Double = 0

    lazy var sourceNode: AVAudioNode = {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)!
        let core = self.core
        return AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let stamp = timestamp.pointee
            let host = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : 0
            lysynth_render(core, left, right, Int32(frameCount), host)
            return noErr
        }
    }()

    /// `sampleRate` other than the live one is for offline renders, which
    /// drive the core directly and never use `sourceNode`.
    init(sampleRate: Double = LYSynthInstrument.sampleRate) {
        core = lysynth_create(sampleRate)
    }

    deinit {
        lysynth_destroy(core)
    }

    // MARK: Notes

    func noteOn(_ note: UInt8, velocity: UInt8, atHostTime hostTime: UInt64, cutoff: Float, resonance: Float) {
        lysynth_note_on(core, Int32(note), Int32(velocity), hostTime, cutoff, resonance)
    }

    func noteOff(_ note: UInt8, atHostTime hostTime: UInt64) {
        lysynth_note_off(core, Int32(note), hostTime)
    }

    func allNotesOff() {
        lysynth_all_notes_off(core)
    }

    // MARK: Patch

    /// Sends only what changed since the last patch, so turning one knob
    /// writes one parameter.
    @MainActor
    func apply(_ next: LYSynthPatch, bpm: Double) {
        let previous = patch
        for oscillator in 0..<2 {
            let custom = oscillator == 0 ? next.customTableA : next.customTableB
            let previousCustom = oscillator == 0 ? previous?.customTableA : previous?.customTableB
            let factory = oscillator == 0 ? next.tableA : next.tableB
            let previousFactory = oscillator == 0 ? previous?.tableA : previous?.tableB
            guard previous == nil || custom != previousCustom || factory != previousFactory else { continue }
            if let custom, let frames = LYWavetableLibrary.shared.frames(named: custom) {
                frames.withUnsafeBufferPointer {
                    lysynth_set_wavetable(core, Int32(oscillator), $0.baseAddress, Int32(frames.count / LYWavetableLibrary.frameSize))
                }
            } else {
                lysynth_use_factory_table(core, Int32(oscillator), Int32(factory))
            }
        }
        for parameter in LYSynthParameters.all {
            let value = next.value(parameter.id)
            if previous == nil || previous?.value(parameter.id) != value {
                lysynth_set_param(core, Int32(parameter.id), value)
            }
        }
        lysynth_set_param(core, Int32(LY_BPM), Float(bpm))
        self.bpm = bpm
        patch = next
    }

    /// Forces the next apply to resend everything, wavetables included. Used
    /// after a custom table is re-saved under the name it already had.
    func forgetTables() { patch = nil }

    func display() -> LYSynthDisplay {
        var value = LYSynthDisplay()
        lysynth_get_display(core, &value)
        return value
    }

    func scope(count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { lysynth_get_scope(core, $0.baseAddress, Int32(count)) }
        return samples
    }
}
