import XCTest
import Accelerate
@testable import LYLLTH

@MainActor
final class SynthCoreTests: XCTestCase {
    private let qualitySampleRate = 44_100.0

    private func qualityPatch(warpMode: Int? = nil, warpAmount: Float = 0,
                              quality: Int = Int(LY_QUALITY_HIGH)) -> LYSynthPatch {
        var patch = LYSynthPatch.initPatch
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_ON), 1)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_LEVEL), 0.7)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 1)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_RANDPHASE), 0)
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_PHASE), 0)
        patch.set(LYSynthParameters.oscillator(1, LY_OSC_ON), 0)
        patch.set(LY_SUB_ON, 0)
        patch.set(LY_NOISE_ON, 0)
        patch.set(LY_FILTER_ON, 0)
        patch.set(LY_F2_ON, 0)
        patch.set(LY_ENV1_A, 0)
        patch.set(LY_ENV1_D, 0)
        patch.set(LY_ENV1_S, 1)
        patch.set(LY_ENV1_R, 0)
        patch.set(LY_VEL_SENS, 0)
        patch.set(LY_VOICES, 1)
        patch.set(LY_MASTER, 0.5)
        patch.set(LY_VINTAGE, 0)
        patch.set(LY_ARP_ON, 0)
        for id in LYSynthFXPage.onIDs { patch.set(id, 0) }
        patch.set(LY_DEC_ON, 0)
        patch.set(LY_RENDER_QUALITY, Float(quality))
        if let warpMode {
            patch.set(LYSynthParameters.oscillator(0, LY_OSC_WARPMODE), Float(warpMode))
            patch.set(LYSynthParameters.oscillator(0, LY_OSC_WARPAMT), warpAmount)
        }
        return patch
    }

    private func installSineTable(on instrument: LYSynthInstrument) {
        let size = LYWavetableLibrary.frameSize
        let samples = (0..<size).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
        samples.withUnsafeBufferPointer {
            lysynth_set_wavetable(instrument.core, 0, $0.baseAddress, 1)
        }
    }

    private func installSawTable(on instrument: LYSynthInstrument) {
        let size = LYWavetableLibrary.frameSize
        let samples = (0..<size).map { -1 + 2 * Float($0) / Float(size) }
        samples.withUnsafeBufferPointer {
            lysynth_set_wavetable(instrument.core, 0, $0.baseAddress, 1)
        }
    }

    private func renderFrames(
        _ instrument: LYSynthInstrument,
        count: Int,
        blockSize: Int,
        startFrame: Int = 0,
        songPosition: Bool = false
    ) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: blockSize)
        var position = 0
        while position < count {
            let frames = min(blockSize, count - position)
            if songPosition {
                let beat = Double(startFrame + position) / qualitySampleRate * 2
                lysynth_set_song_position(instrument.core, beat, 1)
            }
            output.withUnsafeMutableBufferPointer { left in
                right.withUnsafeMutableBufferPointer { right in
                    lysynth_render(instrument.core, left.baseAddress! + position, right.baseAddress!, Int32(frames), 0)
                }
            }
            position += frames
        }
        return output
    }

    private func settledInstrument(_ patch: LYSynthPatch, blockSize: Int) -> LYSynthInstrument {
        let instrument = LYSynthInstrument(sampleRate: qualitySampleRate)
        instrument.apply(patch, bpm: 120)
        installSineTable(on: instrument)
        _ = renderFrames(instrument, count: Int(qualitySampleRate), blockSize: blockSize)
        instrument.noteOn(96, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
        _ = renderFrames(instrument, count: Int(qualitySampleRate / 2), blockSize: blockSize)
        return instrument
    }

    private func qualityRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
    }

    private func differenceDB(_ a: [Float], _ b: [Float]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        let error = qualityRMS((0..<count).map { a[$0] - b[$0] })
        let reference = max(qualityRMS(Array(a.prefix(count))), 1e-12)
        return 20 * log10(max(error, 1e-12) / reference)
    }

    /// Energy that does not sit on an integer harmonic of the requested note.
    /// A Hann window and an eight-bin guard around every harmonic keep ordinary
    /// spectral leakage out of the alias measurement.
    private func nonHarmonicEnergyDB(_ samples: [Float], fundamental: Double) -> Double {
        let count = 1 << Int(floor(log2(Double(samples.count))))
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        var input = Array(samples.prefix(count))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(count))

        let half = count / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        let log2n = vDSP_Length(log2(Float(count)))
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                input.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        let binHz = qualitySampleRate / Double(count)
        let guardHz = binHz * 8.5
        var total = 0.0
        var nonHarmonic = 0.0
        for bin in 1..<half {
            let energy = Double(real[bin] * real[bin] + imaginary[bin] * imaginary[bin])
            total += energy
            let frequency = Double(bin) * binHz
            let harmonic = max(1, Int((frequency / fundamental).rounded()))
            let expected = Double(harmonic) * fundamental
            if expected >= qualitySampleRate / 2 || abs(frequency - expected) > guardHz {
                nonHarmonic += energy
            }
        }
        return 10 * log10(max(nonHarmonic, 1e-30) / max(total, 1e-30))
    }

    private func attachQualityMetrics(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "LUNATK QUALITY METRICS"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(text)
    }

    private func render(_ instrument: LYSynthInstrument, seconds: Double) -> (peak: Float, rms: Float, finite: Bool) {
        let block = 512
        var left = [Float](repeating: 0, count: block), right = left
        var peak: Float = 0, sum: Double = 0, count = 0, finite = true
        for _ in 0..<Int(seconds * LYSynthInstrument.sampleRate) / block {
            lysynth_render(instrument.core, &left, &right, Int32(block), 0)
            for i in 0..<block {
                if !left[i].isFinite || !right[i].isFinite { finite = false }
                peak = max(peak, abs(left[i]), abs(right[i]))
                sum += Double(left[i] * left[i] + right[i] * right[i]); count += 2
            }
        }
        return (peak, Float((sum / Double(max(count, 1))).squareRoot()), finite)
    }

    func testEveryFactorySoundPlaysCleanlyAndReleases() {
        for patch in LYSynthPatch.factory {
            let synth = LYSynthInstrument()
            synth.apply(patch, bpm: 120)
            for note in [48, 55, 60, 64] { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
            let held = render(synth, seconds: 1.5)
            XCTAssertTrue(held.finite, "\(patch.name) produced NaN/inf")
            XCTAssertGreaterThan(held.rms, 0.005, "\(patch.name) is silent")
            XCTAssertLessThan(held.peak, 1.2, "\(patch.name) clips hard")
            for note in [48, 55, 60, 64] { synth.noteOff(UInt8(note), atHostTime: 0) }
            _ = render(synth, seconds: 4)
            let tail = render(synth, seconds: 0.5)
            XCTAssertLessThan(tail.rms, 0.001, "\(patch.name) does not release")
        }
    }

    func testHeavyPatchRendersFasterThanRealtime() {
        let synth = LYSynthInstrument()
        var patch = LYSynthPatch.factory(named: "NIGHT PAD")!
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 16)
        patch.set(LYSynthParameters.oscillator(1, LY_OSC_UNISON), 16)
        patch.set(LY_VOICES, 16)
        synth.apply(patch, bpm: 120)
        for note in 48..<64 { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0) }
        let start = Date()
        _ = render(synth, seconds: 2)
        let elapsed = Date().timeIntervalSince(start)
        print("LYLLTH SYNTH worst case: 16 voices x 2 osc x 16 unison, 2 s of audio in \(String(format: "%.3f", elapsed)) s (\(String(format: "%.1f", elapsed / 2 * 100))% of one core)")
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testRealtimeAndOfflineBlockSizesNullForAStaticPatch() {
        let live = settledInstrument(qualityPatch(), blockSize: 64)
        let offline = settledInstrument(qualityPatch(), blockSize: 512)
        let frameCount = Int(qualitySampleRate)
        let liveRender = renderFrames(live, count: frameCount, blockSize: 64, songPosition: true)
        let offlineRender = renderFrames(offline, count: frameCount, blockSize: 512, songPosition: true)
        let nullDB = differenceDB(liveRender, offlineRender)
        attachQualityMetrics(String(format: "STATIC LIVE/OFFLINE NULL: %.2f dB", nullDB))
        XCTAssertLessThan(nullDB, -100, "a static patch should not change with host render quantum")
    }

    func testAutomationSmoothingIsBlockSizeInvariant() {
        let live = settledInstrument(qualityPatch(), blockSize: 64)
        let offline = settledInstrument(qualityPatch(), blockSize: 512)
        lysynth_set_param(live.core, Int32(LY_MASTER), 0.95)
        lysynth_set_param(offline.core, Int32(LY_MASTER), 0.95)
        let frameCount = Int(qualitySampleRate / 2)
        let liveRender = renderFrames(live, count: frameCount, blockSize: 64)
        let offlineRender = renderFrames(offline, count: frameCount, blockSize: 512)
        let nullDB = differenceDB(liveRender, offlineRender)
        attachQualityMetrics(String(format: "AUTOMATED LIVE/OFFLINE NULL: %.2f dB", nullDB))

        XCTAssertLessThan(nullDB, -100, "automation must sound the same at 64- and 512-frame host blocks")
    }

    func testMipBoundaryCrossfadeRemovesOctaveStep() {
        func render(tune: Float) -> [Float] {
            var patch = qualityPatch()
            patch.set(LY_TUNE, tune)
            let synth = LYSynthInstrument(sampleRate: qualitySampleRate)
            synth.apply(patch, bpm: 120)
            installSawTable(on: synth)
            _ = renderFrames(synth, count: Int(qualitySampleRate / 2), blockSize: 128)
            synth.noteOn(89, velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0)
            return renderFrames(synth, count: 1_024, blockSize: 128)
        }

        // MIDI 89 crosses the 64-harmonic/32-harmonic mip boundary at this
        // tuning. Either side differs by only 0.02 cent; an abrupt mip switch
        // used to replace an octave of upper partials here.
        let boundary = Float(1_200 * log2((qualitySampleRate * 64 / 2_048) / (440 * pow(2, Double(89 - 69) / 12))))
        let below = render(tune: boundary - 0.01)
        let above = render(tune: boundary + 0.01)
        let discontinuity = differenceDB(below, above)
        attachQualityMetrics(String(format: "MIP BOUNDARY NULL: %.2f dB", discontinuity))
        XCTAssertLessThan(discontinuity, -38, "adjacent mip levels must crossfade rather than switch")
    }

    func testPhaseWarpAliasingStaysBelowQualityFloor() {
        let note = 96
        let fundamental = 440.0 * pow(2, Double(note - 69) / 12)
        let clean = settledInstrument(qualityPatch(), blockSize: 256)
        let draft = settledInstrument(qualityPatch(warpMode: LY_WARP_SYNC, warpAmount: 0.82,
                                                   quality: Int(LY_QUALITY_DRAFT)), blockSize: 256)
        let high = settledInstrument(qualityPatch(warpMode: LY_WARP_SYNC, warpAmount: 0.82,
                                                  quality: Int(LY_QUALITY_HIGH)), blockSize: 256)
        let ultra = settledInstrument(qualityPatch(warpMode: LY_WARP_SYNC, warpAmount: 0.82,
                                                   quality: Int(LY_QUALITY_ULTRA)), blockSize: 256)
        let frameCount = 65_536
        let cleanAlias = nonHarmonicEnergyDB(renderFrames(clean, count: frameCount, blockSize: 256), fundamental: fundamental)
        let draftAlias = nonHarmonicEnergyDB(renderFrames(draft, count: frameCount, blockSize: 256), fundamental: fundamental)
        let highAlias = nonHarmonicEnergyDB(renderFrames(high, count: frameCount, blockSize: 256), fundamental: fundamental)
        let ultraAlias = nonHarmonicEnergyDB(renderFrames(ultra, count: frameCount, blockSize: 256), fundamental: fundamental)
        attachQualityMetrics(String(format: "ALIAS ENERGY: clean %.2f dB · draft %.2f dB · high %.2f dB · ultra %.2f dB",
                                    cleanAlias, draftAlias, highAlias, ultraAlias))
        XCTAssertLessThan(cleanAlias, -55, "the analyzer's clean sine control should be essentially harmonic")
        XCTAssertLessThan(highAlias, draftAlias - 4, "HIGH must materially reduce warp aliases")
        XCTAssertLessThan(ultraAlias, highAlias - 4, "ULTRA must materially improve on HIGH")
        XCTAssertLessThan(ultraAlias, -28, "ULTRA must deliver at least a 10 dB improvement over the native-rate baseline")

        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("4× oversampling still cannot fully band-limit every non-integer hard-sync discontinuity", options: options) {
            XCTAssertLessThan(ultraAlias, -60, "phase-warp aliases should remain below the final quality floor")
        }
    }

    func testHighQualityWarpLoadRendersFasterThanRealtime() {
        var patch = qualityPatch(warpMode: LY_WARP_SYNC, warpAmount: 0.82, quality: Int(LY_QUALITY_HIGH))
        patch.set(LYSynthParameters.oscillator(0, LY_OSC_UNISON), 16)
        patch.set(LY_VOICES, 16)
        let synth = LYSynthInstrument()
        synth.apply(patch, bpm: 120)
        installSineTable(on: synth)
        for note in 48..<64 { synth.noteOn(UInt8(note), velocity: 100, atHostTime: 0, cutoff: 0, resonance: 0) }
        let start = Date()
        _ = render(synth, seconds: 2)
        let elapsed = Date().timeIntervalSince(start)
        attachQualityMetrics(String(format: "HIGH WARP LOAD: 16 voices × 16 unison, 2 s in %.3f s (%.1f%% of one core)",
                                    elapsed, elapsed / 2 * 100))
        XCTAssertLessThan(elapsed, 2, "HIGH quality must remain realtime-safe at the documented maximum load")
    }

    func testRenderQualityLeavesAnUnwarpedOscillatorBitIdentical() {
        let draft = settledInstrument(qualityPatch(quality: Int(LY_QUALITY_DRAFT)), blockSize: 128)
        let high = settledInstrument(qualityPatch(quality: Int(LY_QUALITY_HIGH)), blockSize: 128)
        let ultra = settledInstrument(qualityPatch(quality: Int(LY_QUALITY_ULTRA)), blockSize: 128)
        let frames = 8_192
        let reference = renderFrames(draft, count: frames, blockSize: 128)
        XCTAssertEqual(renderFrames(high, count: frames, blockSize: 128), reference)
        XCTAssertEqual(renderFrames(ultra, count: frames, blockSize: 128), reference)
    }

    func testEveryWarpModeRendersFiniteAtEveryQuality() {
        for quality in Int(LY_QUALITY_DRAFT)...Int(LY_QUALITY_ULTRA) {
            for mode in 1..<Int(LY_WARP_COUNT) {
                let synth = settledInstrument(qualityPatch(warpMode: mode, warpAmount: 0.9, quality: quality), blockSize: 128)
                let output = renderFrames(synth, count: 8_192, blockSize: 128)
                XCTAssertTrue(output.allSatisfy(\.isFinite), "quality \(quality), warp \(mode) produced NaN/inf")
                XCTAssertGreaterThan(qualityRMS(output), 0.001, "quality \(quality), warp \(mode) went silent")
                XCTAssertLessThan(output.map(abs).max() ?? 0, 1.2, "quality \(quality), warp \(mode) exceeded the synth ceiling")
            }
        }
    }
}
