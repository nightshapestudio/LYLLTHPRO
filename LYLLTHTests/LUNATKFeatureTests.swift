import XCTest
@testable import LYLLTH

/// Song position, performers, trackers, voice inserts, feedback and macros
/// 5–8, driven through the C core the way the hosts drive it.
@MainActor
final class LUNATKFeatureTests: XCTestCase {
    private let rate = LYSynthInstrument.sampleRate

    private func synth(_ edit: (inout LYSynthPatch) -> Void = { _ in }) -> LYSynthInstrument {
        var patch = LYSynthPatch.initPatch
        edit(&patch)
        let synth = LYSynthInstrument()
        synth.apply(patch, bpm: 120)
        return synth
    }

    /// Renders `frames`, telling the core the song position before every
    /// 64-frame block when `beat` is given (120 BPM).
    private func render(_ synth: LYSynthInstrument, frames: Int, beat: Double? = nil, playing: Bool = true) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames), right = left
        var position = 0
        while position < frames {
            let n = min(64, frames - position)
            if let beat { lysynth_set_song_position(synth.core, beat + Double(position) / rate * 2, playing ? 1 : 0) }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    lysynth_render(synth.core, l.baseAddress! + position, r.baseAddress! + position, Int32(n), 0)
                }
            }
            position += n
        }
        return (left, right)
    }

    private func firstSound(_ samples: [Float], threshold: Float = 1e-3) -> Int? {
        samples.firstIndex { abs($0) > threshold }
    }

    private func modulation(_ display: LYSynthDisplay, _ destination: Int) -> Float {
        withUnsafeBytes(of: display.modulation) { $0.bindMemory(to: Float.self)[destination] }
    }

    private func pair<T>(_ tuple: (T, T), _ index: Int) -> T { index == 0 ? tuple.0 : tuple.1 }

    // MARK: Song position

    func testArpeggiatorWaitsForTheGridWhileTheSongPlays() {
        let arp: (inout LYSynthPatch) -> Void = { p in
            p.set(LY_ARP_ON, 1)
            p.set(LY_ARP_RATE, 10 / 14)            // 1/16: a quarter of a beat
            p.set(LY_ENV1_A, 0)
        }
        // A chord 0.05 beat after a grid line (more than 15% of a step) waits
        // for the next one, at beat 0.5.
        let late = synth(arp)
        _ = render(late, frames: Int(0.30 * 0.5 * rate), beat: 0)
        late.noteOn(60, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let out = render(late, frames: Int(0.5 * rate), beat: 0.30)
        let onset = Double(try! XCTUnwrap(firstSound(out.left))) / rate * 2 + 0.30
        XCTAssertEqual(onset, 0.5, accuracy: 0.01)

        // Just after a grid line, it plays on it at once.
        let onTime = synth(arp)
        _ = render(onTime, frames: Int(0.26 * 0.5 * rate), beat: 0)
        onTime.noteOn(60, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let now = render(onTime, frames: Int(0.5 * rate), beat: 0.26)
        XCTAssertLessThan(Double(try! XCTUnwrap(firstSound(now.left))) / rate * 2, 0.01)

        // With no transport it plays when the key goes down, as before.
        let free = synth(arp)
        _ = render(free, frames: Int(0.30 * 0.5 * rate))
        free.noteOn(60, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        let played = render(free, frames: Int(0.5 * rate))
        XCTAssertLessThan(try! XCTUnwrap(firstSound(played.left)), 128)
    }

    func testSyncedLFOFollowsTheBar() {
        let lfo = synth { p in
            p.set(LYSynthParameters.lfo(0, LY_LFO1_SYNC), 1)
            p.set(LYSynthParameters.lfo(0, LY_LFO1_RATE), 2 / 14)   // 1 BAR: four beats
        }
        _ = render(lfo, frames: 64, beat: 1.0)
        XCTAssertEqual(Double(lfo.display().lfoPhase.0), 0.25, accuracy: 0.01)
        _ = render(lfo, frames: 64, beat: 3.0)
        XCTAssertEqual(Double(lfo.display().lfoPhase.0), 0.75, accuracy: 0.01, "a jump in the song moves the LFO with it")
        XCTAssertEqual(lfo.display().songLocked, 1)
        _ = render(lfo, frames: 64, beat: 3.0, playing: false)
        XCTAssertEqual(lfo.display().songLocked, 0)
    }

    func testTransportAnchorDrivesTheBeatFromTheHostClock() {
        let core = synth()
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        let anchor: UInt64 = 10_000_000_000
        core.setTransport(playing: true, hostTime: anchor, beat: 8)
        var left = [Float](repeating: 0, count: 64), right = left
        lysynth_render(core.core, &left, &right, 64, anchor + UInt64(ticksPerSecond))   // one second later, 120 BPM
        XCTAssertEqual(Double(core.display().songBeat), 10 + 64 / rate * 2, accuracy: 0.001)
        XCTAssertEqual(core.display().songLocked, 1)
        core.setTransport(playing: false, hostTime: 0, beat: 0)
        lysynth_render(core.core, &left, &right, 64, anchor + UInt64(ticksPerSecond))
        XCTAssertEqual(core.display().songLocked, 0)
    }

    // MARK: Performers

    func testPerformerFollowsTheSongAndSwitchKeysPickThePattern() {
        let perf = synth { p in
            p.set(LY_PERF_KEYSWITCH, 1)
            p.set(LY_PERF_KEYROOT, 24)
        }
        _ = render(perf, frames: 64, beat: 0.3)
        XCTAssertEqual(pair(perf.display().perfStep, 0), 1, "1/16 steps: beat 0.3 is step 2")
        _ = render(perf, frames: 64, beat: 3.9)
        XCTAssertEqual(pair(perf.display().perfStep, 0), 15)
        XCTAssertEqual(pair(perf.display().perfPattern, 0), 0)

        // D1 (26) is the third switch key: pattern C, and no sound.
        perf.noteOn(26, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        let out = render(perf, frames: 2048, beat: 0)
        XCTAssertNil(firstSound(out.left))
        XCTAssertEqual(pair(perf.display().perfPattern, 0), 2)
        XCTAssertEqual(pair(perf.display().perfPattern, 1), 2)

        // Choosing a pattern in the patch takes over again.
        var patch = perf.patch!
        patch.set(LYSynthParameters.performer(0, LY_PERF1_PATTERN), 1)
        perf.apply(patch, bpm: 120)
        _ = render(perf, frames: 64, beat: 0)
        XCTAssertEqual(pair(perf.display().perfPattern, 0), 1)
    }

    func testNoteModePerformerStartsWithEachNote() {
        let perf = synth { p in p.set(LYSynthParameters.performer(0, LY_PERF1_MODE), Float(LY_PERFMODE_TRIG)) }
        _ = render(perf, frames: 64, beat: 2.3)
        perf.noteOn(60, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        _ = render(perf, frames: 256, beat: 2.3)
        XCTAssertEqual(pair(perf.display().perfStep, 0), 0)
    }

    func testPerformerModulatesThroughTheMatrix() {
        // Pattern D is a stepped line; step 1 is +1, step 4 is -1.
        let perf = synth { p in _ = p.route(source: LY_SRC_PERF1, destination: LY_DST_CUTOFF, amount: 0.5) }
        perf.noteOn(60, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        var patch = perf.patch!
        patch.set(LYSynthParameters.performer(0, LY_PERF1_PATTERN), 3)
        perf.apply(patch, bpm: 120)
        // Route amounts glide in over a few blocks; 2048 frames stay in one step.
        _ = render(perf, frames: 2048, beat: 0.1)
        XCTAssertEqual(modulation(perf.display(), LY_DST_CUTOFF), 0.5, accuracy: 0.01)
        _ = render(perf, frames: 2048, beat: 0.8)
        XCTAssertEqual(modulation(perf.display(), LY_DST_CUTOFF), -0.5, accuracy: 0.01)
    }

    // MARK: Trackers and macros

    func testTrackerReadsItsSourceThroughTheCurve() {
        let tracker = synth { p in
            _ = p.route(source: LY_SRC_TRACK1, destination: LY_DST_CUTOFF, amount: 1)
            for i in 0..<Int(LY_TRACK_POINTS) { p.set(LYSynthParameters.trackerPoint(0, i), i < 8 ? -0.5 : 0.8) }
        }
        tracker.noteOn(36, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        _ = render(tracker, frames: 2048)
        XCTAssertEqual(Double(pair(tracker.display().trackInput, 0)), 0.3, accuracy: 0.001, "NOTE 36 reads 30% of the way across")
        XCTAssertEqual(modulation(tracker.display(), LY_DST_CUTOFF), -0.5, accuracy: 0.001)
        tracker.noteOn(96, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        _ = render(tracker, frames: 2048)
        XCTAssertEqual(modulation(tracker.display(), LY_DST_CUTOFF), 0.8, accuracy: 0.001)
    }

    func testMacrosFiveToEightModulate() {
        let macros = synth { p in
            _ = p.route(source: LY_SRC_MACRO7, destination: LY_DST_CUTOFF, amount: 0.4)
            p.set(LY_MACRO7, 1)
        }
        macros.noteOn(60, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        _ = render(macros, frames: 2048)
        XCTAssertEqual(modulation(macros.display(), LY_DST_CUTOFF), 0.4, accuracy: 0.01)
    }

    // MARK: Voice FX

    private func held(_ edit: (inout LYSynthPatch) -> Void, note: UInt8 = 45, seconds: Double = 0.5) -> (left: [Float], right: [Float]) {
        let s = synth { p in
            p.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 1)
            p.set(LYSynthParameters.oscillator(0, LY_OSC_RANDPHASE), 0)
            edit(&p)
        }
        // Smoothed knobs glide from the core's defaults; let them arrive.
        _ = render(s, frames: Int(0.2 * rate))
        s.noteOn(note, velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
        return render(s, frames: Int(seconds * rate))
    }

    func testEveryInsertRunsCleanBeforeAndAfterAndMixZeroIsBypass() {
        let dry = held { _ in }
        for type in 1..<Int(LY_INS_COUNT) {
            for after in [false, true] {
                for slot in 0..<2 {
                    let name = "\(LYSynthNames.inserts[type]) \(after ? "AFTER" : "BEFORE") \(slot + 1)"
                    let wet = held { p in
                        p.set(LYSynthParameters.insert(slot, LY_INS1_TYPE), Float(type))
                        p.set(LYSynthParameters.insert(slot, LY_INS1_POSITION), after ? 1 : 0)
                        p.set(LYSynthParameters.insert(slot, LY_INS1_AMOUNT), 0.8)
                        p.set(LYSynthParameters.insert(slot, LY_INS1_FREQ), 0.7)
                    }
                    XCTAssertTrue(wet.left.allSatisfy(\.isFinite) && wet.right.allSatisfy(\.isFinite), name)
                    XCTAssertLessThan(wet.left.map(abs).max()!, 1.3, name)
                    let rms = (wet.left.reduce(0) { $0 + $1 * $1 } / Float(wet.left.count)).squareRoot()
                    XCTAssertGreaterThan(rms, 0.005, name)
                    XCTAssertNotEqual(wet.left, dry.left, "\(name) changes the sound")
                }
            }
            let bypass = held { p in
                p.set(LYSynthParameters.insert(0, LY_INS1_TYPE), Float(type))
                p.set(LYSynthParameters.insert(0, LY_INS1_MIX), 0)
            }
            XCTAssertEqual(bypass.left, dry.left, "\(LYSynthNames.inserts[type]) at MIX 0 is untouched")
        }
    }

    func testRectifyLeavesNoDC() {
        let out = held({ p in
            p.set(LYSynthParameters.insert(0, LY_INS1_TYPE), Float(LY_INS_RECTIFY))
            p.set(LYSynthParameters.insert(0, LY_INS1_POSITION), 1)
            p.set(LYSynthParameters.insert(0, LY_INS1_AMOUNT), 1)
        }, seconds: 1.5)
        let tail = out.left.suffix(Int(0.5 * rate))
        XCTAssertLessThan(abs(tail.reduce(0, +) / Float(tail.count)), 0.004)
    }

    func testFrequencyShifterMovesThePitchByHertz() {
        // A sine at A4 (440 Hz) shifted by +500 Hz peaks at 940 Hz.
        let out = held({ p in
            p.set(LY_FILTER_ON, 0)
            p.set(LYSynthParameters.oscillator(0, LY_OSC_WTPOS), 0)
            p.set(LYSynthParameters.insert(0, LY_INS1_TYPE), Float(LY_INS_SHIFT))
            p.set(LYSynthParameters.insert(0, LY_INS1_AMOUNT), 1)
            p.set(LYSynthParameters.insert(0, LY_INS1_FREQ), 0.75)
        }, note: 69, seconds: 1.0)
        let window = Array(out.left.suffix(8192))
        var best = (hz: 0.0, power: 0.0)
        for hz in stride(from: 300.0, through: 1500.0, by: 5.0) {
            var re = 0.0, im = 0.0
            for (i, x) in window.enumerated() {
                let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(window.count))
                re += Double(x) * w * cos(2 * .pi * hz * Double(i) / rate)
                im += Double(x) * w * sin(2 * .pi * hz * Double(i) / rate)
            }
            if re * re + im * im > best.power { best = (hz, re * re + im * im) }
        }
        XCTAssertEqual(best.hz, 940, accuracy: 10)
    }

    func testFeedbackIsAudibleAndStaysBounded() {
        let dry = held { p in p.set(LY_FILTER_RES, 0.5) }
        let off = held { p in p.set(LY_FILTER_RES, 0.5); p.set(LY_FB_DRIVE, 1) }
        XCTAssertEqual(off.left, dry.left, "no amount, no change")
        let loop = held { p in p.set(LY_FILTER_RES, 0.5); p.set(LY_FB_AMOUNT, 0.6) }
        XCTAssertNotEqual(loop.left, dry.left)
        for filter in [LY_FILTER_LP24, LY_FILTER_BP, LY_FILTER_COMB_POS, LY_FILTER_LADDER, LY_FILTER_FORMANT] {
            let hard = held({ p in
                p.set(LY_FILTER_TYPE, Float(filter))
                p.set(LY_FILTER_RES, 0.95)
                p.set(LY_FB_AMOUNT, 1)
                p.set(LY_FB_DRIVE, 1)
                p.set(LY_FB_TONE, 1)
            }, seconds: 1.5)
            XCTAssertTrue(hard.left.allSatisfy(\.isFinite), LYSynthNames.filters[filter])
            XCTAssertLessThan(hard.left.map(abs).max()!, 1.3, LYSynthNames.filters[filter])
        }
    }

    // MARK: Parameters

    func testEveryAddedParameterHasAKeyAndTheOldIdsStayPut() {
        for id in Int(LY_MACRO5)..<Int(LY_PARAM_COUNT) {
            XCTAssertNotNil(LYSynthParameters.byID[id], "parameter \(id) has no key")
        }
        XCTAssertEqual(Int(LY_MACRO5), Int(LY_LFO_POINTS_BASE) + 4 * Int(LY_LFO_POINTS), "added parameters come after the LFO points")
        XCTAssertEqual(LYSynthParameters.byKey["macro1"]?.id, Int(LY_MACRO1))
        XCTAssertEqual(LYSynthNames.sources.count, Int(LY_SRC_COUNT))
        XCTAssertEqual(Set(LYSynthNames.sourceOrder).count, Int(LY_SRC_COUNT))
        XCTAssertTrue(LYSynthNames.destinations.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(LYSynthNames.inserts.count, Int(LY_INS_COUNT))
        XCTAssertEqual(LYSynthNames.stepShapes.count, Int(LY_PSTEP_COUNT))
    }
}
