import Accelerate
import AVFoundation
import Foundation

/// What SIREN hears in a recording: a pitch curve and a level curve on a
/// 5 ms grid, and the notes found in them. Rebuilt from the audio on
/// demand, so none of it is stored in the project.
struct LYVocalAnalysis: Sendable {
    /// Seconds between frames.
    var hop: Double
    /// MIDI pitch per frame; 0 where nothing is sung (breath, consonant, rest).
    var pitch: [Float]
    /// RMS level per frame, linear.
    var level: [Float]
    var duration: Double

    var frameCount: Int { pitch.count }

    func frame(at time: Double) -> Int {
        min(max(Int((time / hop).rounded()), 0), max(pitch.count - 1, 0))
    }

    /// Pitch at a time, or nil where unvoiced. Interpolates between voiced
    /// frames so a curve drawn from it is smooth.
    func pitch(at time: Double) -> Double? {
        guard !pitch.isEmpty else { return nil }
        let position = time / hop
        let low = min(max(Int(position.rounded(.down)), 0), pitch.count - 1)
        let high = min(low + 1, pitch.count - 1)
        let a = pitch[low], b = pitch[high]
        if a > 0, b > 0 { return Double(a + (b - a) * Float(position - Double(low))) }
        let nearest = pitch[frame(at: time)]
        return nearest > 0 ? Double(nearest) : nil
    }

    func level(at time: Double) -> Float {
        level.isEmpty ? 0 : level[frame(at: time)]
    }
}

enum LYVocalAnalyzer {
    static let hopSeconds = 0.005
    static let lowestHz = 65.0
    static let highestHz = 1_100.0

    // MARK: Audio in

    /// The file as one mono channel at its own rate.
    static func monoSamples(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return ([], format.sampleRate)
        }
        try file.read(into: buffer)
        return (mono(buffer), format.sampleRate)
    }

    static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        guard let channels = buffer.floatChannelData, count > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            vDSP_vadd(mono, 1, channels[channel], 1, &mono, 1, vDSP_Length(count))
        }
        var scale = 1 / Float(max(channelCount, 1))
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(count))
        return mono
    }

    // MARK: Analysis

    static func analyze(samples: [Float], sampleRate: Double) -> LYVocalAnalysis {
        let duration = Double(samples.count) / max(sampleRate, 1)
        // Pitch is found at about 16 kHz: plenty for a voice's fundamental,
        // and a third of the work at 48 kHz.
        let factor = max(1, Int((sampleRate / 16_000).rounded()))
        let rate = sampleRate / Double(factor)
        let low = decimate(samples, factor: factor)
        let hop = max(1, Int((hopSeconds * rate).rounded()))
        let window = Int((0.032 * rate).rounded())          // 32 ms
        let tauMin = max(2, Int(rate / highestHz))
        let tauMax = min(Int(rate / lowestHz), window - 1)
        let frameCount = max(1, Int(ceil(Double(low.count) / Double(hop))))

        var level = [Float](repeating: 0, count: frameCount)
        var raw = [Float](repeating: 0, count: frameCount)
        // Centered frames: half a window of silence before the audio, and
        // room after it for the last frame's full span.
        let span = window + tauMax
        var padded = [Float](repeating: 0, count: low.count + span + window)
        padded.withUnsafeMutableBufferPointer { buffer in
            low.withUnsafeBufferPointer { source in
                buffer.baseAddress!.advanced(by: window / 2).update(from: source.baseAddress!, count: low.count)
            }
        }
        lyv_yin(padded, Int32(frameCount), Int32(hop), Int32(window), Int32(tauMin), Int32(tauMax), rate, &raw, &level)

        let pitch = clean(raw, level: level)
        return LYVocalAnalysis(hop: Double(hop) / rate, pitch: pitch, level: level, duration: duration)
    }

    /// Gates quiet frames, removes octave slips and single-frame spikes, and
    /// fills one-frame holes inside sung notes.
    static func clean(_ raw: [Float], level: [Float]) -> [Float] {
        guard !raw.isEmpty else { return raw }
        let peak = level.max() ?? 0
        let gate = peak * 0.02                                 // -34 dB under the loudest frame
        var pitch = raw.indices.map { level[$0] >= gate ? raw[$0] : 0 }

        // Octave slips: a frame an octave off both neighbors folds back.
        for index in 1..<max(1, pitch.count - 1) where pitch[index] > 0 {
            let before = pitch[index - 1], after = pitch[index + 1]
            guard before > 0, after > 0 else { continue }
            for shift: Float in [-12, 12] where abs(pitch[index] + shift - before) < 1.2 && abs(pitch[index] + shift - after) < 1.2 {
                pitch[index] += shift
            }
        }
        // Five-frame median inside voiced runs.
        var smoothed = pitch
        for index in pitch.indices where pitch[index] > 0 {
            let window = (max(0, index - 2)...min(pitch.count - 1, index + 2)).map { pitch[$0] }.filter { $0 > 0 }
            if window.count >= 3 { smoothed[index] = window.sorted()[window.count / 2] }
        }
        // Voiced runs shorter than 25 ms are clicks or consonants.
        var index = 0
        while index < smoothed.count {
            guard smoothed[index] > 0 else { index += 1; continue }
            var end = index
            while end + 1 < smoothed.count, smoothed[end + 1] > 0 { end += 1 }
            if end - index + 1 < 5 { for frame in index...end { smoothed[frame] = 0 } }
            index = end + 1
        }
        // One-frame holes between voiced frames.
        for index in 1..<max(1, smoothed.count - 1) where smoothed[index] == 0 {
            let before = smoothed[index - 1], after = smoothed[index + 1]
            if before > 0, after > 0, abs(before - after) < 1 { smoothed[index] = (before + after) / 2 }
        }
        return smoothed
    }

    /// Low-passes, then keeps every `factor`th sample.
    static func decimate(_ samples: [Float], factor: Int) -> [Float] {
        guard factor > 1, samples.count > factor else { return samples }
        // Windowed-sinc low-pass at 0.45 of the new Nyquist.
        let taps = 8 * factor + 1
        let cutoff = 0.45 / Double(factor)
        let middle = Double(taps - 1) / 2
        var filter = (0..<taps).map { index -> Float in
            let x = Double(index) - middle
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let window = 0.42 - 0.5 * cos(2 * .pi * Double(index) / Double(taps - 1)) + 0.08 * cos(4 * .pi * Double(index) / Double(taps - 1))
            return Float(sinc * window)
        }
        let sum = filter.reduce(0, +)
        filter = filter.map { $0 / sum }
        let outCount = (samples.count - taps) / factor + 1
        guard outCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: outCount)
        vDSP_desamp(samples, vDSP_Stride(factor), filter, &output, vDSP_Length(outCount), vDSP_Length(taps))
        return output
    }

    // MARK: Notes

    /// Splits the sung parts into notes: at rests, and where the pitch moves
    /// to a new place and stays there.
    static func notes(in analysis: LYVocalAnalysis) -> [LYVocalNote] {
        let pitch = analysis.pitch
        let hop = analysis.hop
        let minimumFrames = max(1, Int(0.06 / hop))          // 60 ms
        let settleFrames = max(1, Int(0.035 / hop))          // a move must hold 35 ms
        var ranges: [ClosedRange<Int>] = []

        var index = 0
        while index < pitch.count {
            guard pitch[index] > 0 else { index += 1; continue }
            var end = index
            // A voiced run, bridging gaps up to 20 ms.
            while end + 1 < pitch.count {
                if pitch[end + 1] > 0 { end += 1; continue }
                var gapEnd = end + 1
                while gapEnd < pitch.count, pitch[gapEnd] == 0, gapEnd - end <= 4 { gapEnd += 1 }
                if gapEnd < pitch.count, pitch[gapEnd] > 0, gapEnd - end <= 4 { end = gapEnd } else { break }
            }
            // Pitch changes inside the run.
            var noteStart = index
            var center = pitch[index]
            var count: Float = 1
            var away = 0
            var frame = index + 1
            while frame <= end {
                let value = pitch[frame]
                if value > 0 {
                    if abs(value - center) > 0.8 {
                        away += 1
                        if away >= settleFrames {
                            let split = frame - away + 1
                            if split - noteStart >= minimumFrames {
                                ranges.append(noteStart...(split - 1))
                                noteStart = split
                            }
                            center = value; count = 1; away = 0
                        }
                    } else {
                        away = 0
                        // Center follows slowly, so a gentle slide stays one note.
                        count = min(count + 1, 40)
                        center += (value - center) / count
                    }
                }
                frame += 1
            }
            ranges.append(noteStart...end)
            index = end + 1
        }

        // Too-short pieces join the neighbor nearest in pitch.
        var merged: [ClosedRange<Int>] = []
        for range in ranges {
            if range.count < minimumFrames, let last = merged.last, range.lowerBound - last.upperBound <= 5 {
                merged[merged.count - 1] = last.lowerBound...range.upperBound
            } else {
                merged.append(range)
            }
        }
        if merged.count > 1, merged[0].count < minimumFrames, merged[1].lowerBound - merged[0].upperBound <= 5 {
            merged[1] = merged[0].lowerBound...merged[1].upperBound
            merged.removeFirst()
        }

        return merged.compactMap { range in
            guard range.count >= 3, let center = centerPitch(pitch, range) else { return nil }
            return LYVocalNote(
                start: Double(range.lowerBound) * hop,
                end: Double(range.upperBound + 1) * hop,
                detectedPitch: center
            )
        }
    }

    /// The pitch a note sits on: the median of its middle, leaving out the
    /// scoop in and the fall off.
    static func centerPitch(_ pitch: [Float], _ range: ClosedRange<Int>) -> Double? {
        let trim = range.count / 5
        let inner = (range.lowerBound + trim)...(range.upperBound - trim)
        let values = (inner.isEmpty ? Array(range) : Array(inner)).map { pitch[$0] }.filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return nil }
        return Double(values[values.count / 2])
    }
}

/// Analyses kept for the session, by source file. Finding pitch in a long
/// vocal takes a moment, so it happens once per recording.
final class LYVocalAnalysisCache: @unchecked Sendable {
    static let shared = LYVocalAnalysisCache()
    private let lock = NSLock()
    private var entries: [String: LYVocalAnalysis] = [:]
    private var order: [String] = []

    func analysis(for url: URL) throws -> LYVocalAnalysis {
        let key = url.standardizedFileURL.path
        lock.lock()
        if let hit = entries[key] { lock.unlock(); return hit }
        lock.unlock()
        let (samples, rate) = try LYVocalAnalyzer.monoSamples(url: url)
        let result = LYVocalAnalyzer.analyze(samples: samples, sampleRate: rate)
        lock.lock(); defer { lock.unlock() }
        entries[key] = result
        order.append(key)
        if order.count > 12 { entries[order.removeFirst()] = nil }
        return result
    }
}
