import XCTest
import AVFoundation
@testable import LYLLTH

@MainActor
final class SynthFeatureTests: XCTestCase {
    private func rms(_ synth: LYSynthInstrument, seconds: Double) -> Float {
        let block = 512
        var left = [Float](repeating: 0, count: block), right = left
        var sum: Double = 0, count = 0
        for _ in 0..<max(1, Int(seconds * 44_100) / block) {
            lysynth_render(synth.core, &left, &right, Int32(block), 0)
            for i in 0..<block { sum += Double(left[i] * left[i]); count += 1 }
        }
        return Float((sum / Double(count)).squareRoot())
    }

    func testMIDINotesSustainPedalAndAllNotesOff() {
        let synth = LYSynthInstrument()
        var patch = LYSynthPatch.factory(named: "NIGHT KEYS")!
        patch.set(LY_ENV1_S, 1)
        synth.apply(patch, bpm: 120)
        lysynth_midi(synth.core, 0x90, 60, 100, 0)
        XCTAssertGreaterThan(rms(synth, seconds: 0.5), 0.01, "MIDI note on is silent")
        lysynth_midi(synth.core, 0xB0, 64, 127, 0)          // sustain down
        lysynth_midi(synth.core, 0x80, 60, 0, 0)            // key up, held by the pedal
        XCTAssertGreaterThan(rms(synth, seconds: 1.0), 0.01, "sustain pedal did not hold the note")
        lysynth_midi(synth.core, 0xB0, 64, 0, 0)            // pedal up releases it
        _ = rms(synth, seconds: 3)
        XCTAssertLessThan(rms(synth, seconds: 0.3), 0.001, "note hung after the pedal came up")
        lysynth_midi(synth.core, 0x90, 64, 100, 0)
        _ = rms(synth, seconds: 0.2)
        lysynth_midi(synth.core, 0xB0, 123, 0, 0)            // all notes off
        _ = rms(synth, seconds: 3)
        XCTAssertLessThan(rms(synth, seconds: 0.3), 0.001, "all notes off left a note sounding")
    }

    func testDrawnLFOAndEnvelopeCurvesStayFinite() {
        let synth = LYSynthInstrument()
        var patch = LYSynthPatch.initPatch
        patch.set(LY_LFO1_SHAPE, Float(LY_LFO_CUSTOM))
        for i in 0..<Int(LY_LFO_POINTS) { patch.set(LY_LFO_POINTS_BASE + i, i % 2 == 0 ? 1 : -1) }
        patch.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.5)
        patch.set(LY_ENV1_ACURVE, 1); patch.set(LY_ENV1_DCURVE, -1); patch.set(LY_ENV1_RCURVE, 1)
        synth.apply(patch, bpm: 120)
        synth.noteOn(57, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        let level = rms(synth, seconds: 1)
        XCTAssertTrue(level.isFinite)
        XCTAssertGreaterThan(level, 0.005)
    }

    func testImportsSerumTablesExactlyAndAudioAsSixtyFourFrames() throws {
        let size = LYWavetableLibrary.frameSize
        let folder = FileManager.default.temporaryDirectory
        let serum = folder.appendingPathComponent("lyllth-test-serum.wav")
        let table = (0..<(3 * size)).map { Float(sin(Double($0) * 2 * .pi / Double(size))) }
        try LYWavetableLibrary.writeWAV(table, to: serum)
        XCTAssertEqual(try LYWavetableLibrary.importFrames(from: serum).count, 3 * size)

        let audio = folder.appendingPathComponent("lyllth-test-audio.wav")
        try LYWavetableLibrary.writeWAV((0..<50_000).map { Float(sin(Double($0) * 0.05)) }, to: audio)
        XCTAssertEqual(try LYWavetableLibrary.importFrames(from: audio).count, 64 * size)
    }

    func testHarmonicEditorRoundTripsAFrame() {
        let size = LYWavetableLibrary.frameSize
        let frame = (0..<size).map { i -> Float in
            let p = Double(i) / Double(size) * 2 * .pi
            return Float(sin(p) * 0.6 + sin(3 * p) * 0.25 + cos(7 * p) * 0.1)
        }
        let rebuilt = LYWavetableEditor.synthesize(LYWavetableEditor.spectrum(frame))
        let error = zip(frame, rebuilt).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(error, 0.001)
    }

    func testUserPresetKeepsItsCustomWavetable() throws {
        let size = LYWavetableLibrary.frameSize
        let name = LYWavetableLibrary.shared.store(Array(repeating: 0.5, count: size), named: "LYLLTH TEST TABLE", writeToFolder: false)
        var patch = LYSynthPatch.initPatch
        patch.customTableA = name
        patch.set(LY_FILTER_CUTOFF, 0.33)
        try LYSynthPresetStore.shared.save(patch, as: "LYLLTH TEST PRESET")
        defer { LYSynthPresetStore.shared.delete("LYLLTH TEST PRESET") }
        let loaded = try XCTUnwrap(LYSynthPresetStore.shared.presets.first { $0.name == "LYLLTH TEST PRESET" })
        XCTAssertEqual(loaded.customTableA, name)
        XCTAssertEqual(loaded.value(LY_FILTER_CUTOFF), 0.33, accuracy: 0.0001)
        let file = LYSynthPresetStore.folder.appendingPathComponent("LYLLTH TEST PRESET.lyllthsynth")
        let stored = try JSONDecoder().decode(LYSynthPresetFile.self, from: Data(contentsOf: file))
        XCTAssertNotNil(stored.wavetables[name], "preset did not embed its wavetable")
    }

    func testProjectCarriesItsWavetables() throws {
        var document = LYLLTHSessionDocument()
        let frames = (0..<(2 * LYWavetableLibrary.frameSize)).map { Float($0 % 7) / 7 }
        document.wavetables["MY TABLE"] = LYWavetableLibrary.floatData(frames)
        document.session.tracks[10].synth?.customTableA = "MY TABLE"
        let reopened = try LYLLTHSessionDocument(fileWrapper: document.packageFileWrapper())
        XCTAssertEqual(LYWavetableLibrary.decodeFloatData(try XCTUnwrap(reopened.wavetables["MY TABLE"])), frames)
    }

    // MARK: DECIMATOR

    /// Energy of the sample-to-sample change against the signal: the grit
    /// crush and bit reduction add shows up here.
    private func roughness(_ synth: LYSynthInstrument, seconds: Double) -> Float {
        let block = 512
        var left = [Float](repeating: 0, count: block), right = left
        var level: Double = 0, change: Double = 0, previous: Float = 0
        for _ in 0..<max(1, Int(seconds * 44_100) / block) {
            lysynth_render(synth.core, &left, &right, Int32(block), 0)
            for i in 0..<block {
                level += Double(left[i] * left[i])
                change += Double((left[i] - previous) * (left[i] - previous))
                previous = left[i]
            }
        }
        return Float((change / max(level, 1e-12)).squareRoot())
    }

    func testDecimatorIsAudibleAtItsDefaults() {
        var patch = LYSynthPatch.initPatch
        let clean = LYSynthInstrument()
        clean.apply(patch, bpm: 120)
        clean.noteOn(48, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        patch.set(LY_DEC_ON, 1)
        let crushed = LYSynthInstrument()
        crushed.apply(patch, bpm: 120)
        crushed.noteOn(48, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        let before = roughness(clean, seconds: 1), after = roughness(crushed, seconds: 1)
        XCTAssertGreaterThan(20 * log10(after / before), 6, "switching the DECIMATOR on at its defaults should add clear grit")
    }

    func testVoidGrowlCarriesItsDecimatorMotionOnTheBeat() throws {
        let patch = try XCTUnwrap(LYSynthPatch.factory.first { $0.name == "VOID GROWL" })
        XCTAssertEqual(patch.value(LY_DEC_ON), 1)
        XCTAssertEqual(patch.value(LY_DEC_POST), 1)
        XCTAssertEqual(patch.value(LY_DEC_MOTION_ON), 1)
        XCTAssertEqual(patch.value(LY_DEC_MOTION_LENGTH), 8)
        XCTAssertEqual(patch.value(LY_DEC_STEP_ON_BASE + 1), 0, "step 2 falls dry")

        let synth = LYSynthInstrument()
        synth.apply(patch, bpm: 118)
        synth.noteOn(45, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        let block = 256
        var left = [Float](repeating: 0, count: block), right = left
        let beatsPerBlock = Double(block) * 118 / 60 / LYSynthInstrument.sampleRate
        var beat = 0.0
        var steps: [Int] = []
        for eighth in 0..<16 {
            // Render into the middle of this 1/8, then read the step playing.
            while beat < Double(eighth) * 0.5 + 0.25 {
                lysynth_set_song_position(synth.core, beat, 1)
                lysynth_render(synth.core, &left, &right, Int32(block), 0)
                beat += beatsPerBlock
            }
            steps.append(Int(synth.display().decimatorStep))
        }
        XCTAssertEqual(steps, Array(0..<8) + Array(0..<8))
    }

    /// No transport: MOTION starts on the key, whenever it lands, and moves
    /// with the arp's steps rather than a clock the player cannot hear.
    func testDecimatorMotionStartsWithTheKeyWithoutATransport() throws {
        var patch = try XCTUnwrap(LYSynthPatch.factory.first { $0.name == "VOID GROWL" })
        let synth = LYSynthInstrument()
        synth.apply(patch, bpm: 118)
        let block = 64
        var left = [Float](repeating: 0, count: block), right = left
        let samplesPerEighth = LYSynthInstrument.sampleRate * 60 / 118 / 2
        func run(eighths: Double) { for _ in 0..<Int(eighths * samplesPerEighth) / block { lysynth_render(synth.core, &left, &right, Int32(block), 0) } }
        func stepAfter(eighths: Double) -> Int { run(eighths: eighths); return Int(synth.display().decimatorStep) }

        for offGrid in [0.37, 1.61, 0.93] {
            run(eighths: offGrid)
            synth.noteOn(45, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
            XCTAssertEqual(stepAfter(eighths: 0.5), 0, "MOTION should start on the key")
            XCTAssertEqual(stepAfter(eighths: 1), 1)
            XCTAssertEqual(stepAfter(eighths: 1), 2)
            synth.noteOff(45, atHostTime: 0)
        }

        // With the arp on, each MOTION step changes on an arp step.
        patch.set(LY_ARP_ON, 1)
        patch.set(LY_ARP_RATE, patch.value(LY_DEC_MOTION_RATE))
        synth.apply(patch, bpm: 118)
        run(eighths: 0.71)
        synth.noteOn(45, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        synth.noteOn(52, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        var pairs: [[Int]] = []
        for _ in 0..<8 {
            run(eighths: 0.5)
            let display = synth.display()
            pairs.append([Int(display.arpStep) % 8, Int(display.decimatorStep)])
            run(eighths: 0.5)
        }
        XCTAssertEqual(pairs.map { $0[1] }, Array(0..<8))
        XCTAssertEqual(Set(pairs.map { ($0[1] - $0[0] + 8) % 8 }).count, 1, "MOTION drifted against the arp: \(pairs)")
    }

    func testPatchesFromBeforeTheDecimatorKeepTheirRackOrder() {
        var patch = LYSynthPatch(name: "OLD")
        let old = LYSynthPatch.defaultEffectOrder.prefix(10).reversed().map { $0 }
        for (place, fx) in old.enumerated() { patch.values["fx.order\(place)"] = Float(fx) }
        XCTAssertEqual(patch.effectOrder, old + [Int(LY_FX_DECIM)])
    }
}

@MainActor
final class DrumSoundTests: XCTestCase {
    func testStarterDrumTracksRenderRealDrumKitSounds() async throws {
        let session = LYLLTHSession.starter()
        let drums = session.tracks.filter { $0.kind == .drumkit }
        XCTAssertFalse(drums.isEmpty)
        for track in drums {
            let id = try XCTUnwrap(LYDrumSounds.presetID(for: track), "\(track.name) has no drum sound")
            let preset = try XCTUnwrap(LYDrumSounds.preset(id: id), "\(id) is not in the DrumKit library")
            let url = try await LYDrumSounds.renderedFile(for: preset)
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 1000, "\(track.name) rendered an empty sound")
        }
        XCTAssertGreaterThan(LYDrumSounds.presets.count, 300)
    }

}
