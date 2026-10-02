import Accelerate
import AVFoundation
import Foundation

/// Rebuilds a recording with its SIREN edit applied.
///
/// Pitch-synchronous overlap-add: the voice is cut into grains one pitch
/// period long, centered on each glottal pulse, and laid back down at the
/// spacing of the new pitch and the new timing. Each grain keeps its own
/// spectral envelope, so the singer's formants stay where they were and a
/// note moved up a third still sounds like the same person. Breaths and
/// consonants have no period; they are carried in short fixed grains.
enum LYVocalRenderer {
    /// Fade between a touched part and the untouched original around it.
    static let blendSeconds = 0.012
    static let unvoicedGrainSeconds = 0.006

    struct Plan {
        var analysis: LYVocalAnalysis
        var notes: [LYVocalNote]
        /// Output-to-source time map with note moves and alignment folded in.
        var warp: [LYWarpPoint]
    }

    static func plan(edit: LYVocalEdit, analysis: LYVocalAnalysis) -> Plan {
        let notes = edit.notes.sorted { $0.start < $1.start }
        var noteWarp: [LYWarpPoint] = []
        if notes.contains(where: { abs($0.timeOffset) > 0.000_5 }) {
            noteWarp.append(LYWarpPoint(output: 0, source: 0))
            var lastOutput = 0.0
            for note in notes {
                // Moves stop short of the neighbors so time never runs backward.
                let start = max(note.start + note.timeOffset, lastOutput + 0.001)
                let end = max(note.end + note.timeOffset, start + 0.001)
                noteWarp.append(LYWarpPoint(output: start, source: note.start))
                noteWarp.append(LYWarpPoint(output: end, source: note.end))
                lastOutput = end
            }
            let tail = max(analysis.duration, lastOutput + 0.001)
            noteWarp.append(LYWarpPoint(output: tail, source: analysis.duration))
        }
        // Note moves apply on top of the alignment: a nudged note moves from
        // where the alignment put it.
        let alignment = edit.alignment?.points ?? []
        let warp: [LYWarpPoint]
        if noteWarp.isEmpty { warp = alignment }
        else if alignment.isEmpty { warp = noteWarp }
        else {
            // Note anchors are in source time; move them into aligned time
            // first, then chain.
            let shifted = noteWarp.map { point in
                LYWarpPoint(output: LYWarp.output(atSource: point.source, alignment) + (point.output - point.source),
                            source: LYWarp.output(atSource: point.source, alignment))
            }
            warp = LYWarp.compose(outer: shifted, inner: alignment)
        }
        return Plan(analysis: analysis, notes: notes, warp: warp)
    }

    /// The note sounding at a source time. Notes are sorted and never overlap.
    static func note(at time: Double, in notes: [LYVocalNote]) -> LYVocalNote? {
        var low = 0, high = notes.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if time < notes[mid].start { high = mid - 1 }
            else if time >= notes[mid].end { low = mid + 1 }
            else { return notes[mid] }
        }
        return nil
    }

    /// A locally averaged pitch separates slow drift from the faster vibrato
    /// around it, so the two can be edited independently.
    private static func trendPitch(at time: Double, note: LYVocalNote, analysis: LYVocalAnalysis) -> Double? {
        let radius = 0.055
        let first = analysis.frame(at: max(note.start, time - radius))
        let last = analysis.frame(at: min(note.end, time + radius))
        guard last >= first else { return analysis.pitch(at: time) }
        var total = 0.0, count = 0
        for index in first...last where analysis.pitch[index] > 0 {
            total += Double(analysis.pitch[index])
            count += 1
        }
        return count > 0 ? total / Double(count) : analysis.pitch(at: time)
    }

    private static func rawShift(at time: Double, note: LYVocalNote, analysis: LYVocalAnalysis) -> Double {
        guard let sung = analysis.pitch(at: time) else { return note.pitchOffset }
        let trend = trendPitch(at: time, note: note, analysis: analysis) ?? sung
        let slow = (trend - note.detectedPitch) * note.drift
        let modulation = (sung - trend) * note.vibrato
        return note.detectedPitch + slow + modulation + note.pitchOffset - sung
    }

    /// A soft connection spans the end of one note and the beginning of the
    /// next. Its stored position moves the steep part earlier or later.
    private static func transition(at time: Double, notes: [LYVocalNote]) -> (left: LYVocalNote, right: LYVocalNote, start: Double, end: Double)? {
        guard notes.count > 1 else { return nil }
        for index in 0..<(notes.count - 1) {
            let left = notes[index], right = notes[index + 1]
            guard right.start - left.end < 0.08 else { continue }
            let edge = min(0.07, max(0.015, min(left.duration, right.duration) * 0.22))
            let start = left.end - edge
            let end = right.start + edge
            guard time >= start, time <= end, end > start else { continue }
            return (left, right, start, end)
        }
        return nil
    }

    private static func transitionAmount(time: Double, start: Double, end: Double, position: Double) -> Double {
        let center = start + (end - start) * min(max(position, 0.05), 0.95)
        let width = min(max((end - start) * 0.34, 0.012), 0.05)
        let linear = min(max((time - (center - width / 2)) / width, 0), 1)
        return linear * linear * (3 - 2 * linear)
    }

    /// The target pitch shift at a source time, in semitones, and whether
    /// that moment is edited at all.
    static func shift(at time: Double, plan: Plan) -> (semitones: Double, touched: Bool) {
        if let connection = transition(at: time, notes: plan.notes) {
            let a = rawShift(at: time, note: connection.left, analysis: plan.analysis)
            let b = rawShift(at: time, note: connection.right, analysis: plan.analysis)
            let amount = transitionAmount(time: time, start: connection.start, end: connection.end,
                                          position: connection.left.pitchTransition)
            let edited = connection.left.isEdited || connection.right.isEdited
            return (a + (b - a) * amount, edited)
        }
        guard let note = note(at: time, in: plan.notes) else { return (0, false) }
        let touched = abs(note.pitchOffset) > 0.000_5 || abs(note.drift - 1) > 0.000_5
            || abs(note.vibrato - 1) > 0.000_5 || abs(note.gainDB) > 0.01
        return (rawShift(at: time, note: note, analysis: plan.analysis), touched)
    }

    static func formant(at time: Double, plan: Plan) -> (semitones: Double, touched: Bool) {
        if let connection = transition(at: time, notes: plan.notes) {
            let shaped = transitionAmount(time: time, start: connection.start, end: connection.end,
                                          position: connection.left.formantTransition)
            let value = connection.left.formantShift
                + (connection.right.formantShift - connection.left.formantShift) * shaped
            return (value, abs(value) > 0.000_5 || connection.left.isEdited || connection.right.isEdited)
        }
        guard let note = note(at: time, in: plan.notes) else { return (0, false) }
        return (note.formantShift, abs(note.formantShift) > 0.000_5)
    }

    static func gain(at time: Double, plan: Plan) -> Float {
        guard let note = note(at: time, in: plan.notes), abs(note.gainDB) > 0.01 else { return 1 }
        // Gain ramps over 10 ms at the note's edges.
        let edge = min(time - note.start, note.end - time)
        let ramp = Float(min(max(edge / 0.01, 0), 1))
        return 1 + (Float(pow(10, note.gainDB / 20)) - 1) * ramp
    }

    // MARK: Render

    /// Renders every channel of `input` through the plan. The result is as
    /// long as the input: the edit moves sound inside the file, never past it.
    static func render(_ input: AVAudioPCMBuffer, plan: Plan) -> AVAudioPCMBuffer? {
        let frames = Int(input.frameLength)
        let rate = input.format.sampleRate
        guard frames > 0, let source = input.floatChannelData,
              let output = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: input.frameLength),
              let destination = output.floatChannelData else { return nil }
        output.frameLength = input.frameLength
        let channels = Int(input.format.channelCount)
        let marks = analysisMarks(mono: LYVocalAnalyzer.mono(input), rate: rate, analysis: plan.analysis)
        guard !marks.isEmpty else {
            for channel in 0..<channels { destination[channel].update(from: source[channel], count: frames) }
            return output
        }

        // One control value per millisecond of output: where it reads from,
        // how far it shifts, its gain, and how much of the rebuilt signal is
        // used. The C++ loop interpolates between them per sample.
        let warp = plan.warp
        let controlStep = max(1, Int(rate * 0.001))
        let controlCount = frames / controlStep + 2
        var controlSource = [Double](repeating: 0, count: controlCount)
        var controlSemitones = [Float](repeating: 0, count: controlCount)
        var controlFormants = [Float](repeating: 0, count: controlCount)
        var controlGain = [Float](repeating: 1, count: controlCount)
        var controlMix = [Float](repeating: 0, count: controlCount)
        for index in 0..<controlCount {
            let outputTime = Double(index * controlStep) / rate
            let sourceTime = warp.isEmpty ? outputTime : LYWarp.source(atOutput: outputTime, warp)
            let (semitones, pitched) = shift(at: sourceTime, plan: plan)
            let (formants, formanted) = formant(at: sourceTime, plan: plan)
            let moved = !warp.isEmpty && abs(sourceTime - outputTime) > 0.000_2
            controlSource[index] = sourceTime
            controlSemitones[index] = Float(semitones)
            controlFormants[index] = Float(formants)
            controlGain[index] = gain(at: sourceTime, plan: plan)
            controlMix[index] = pitched || formanted || moved ? 1 : 0
        }
        smooth(&controlMix, width: max(2, Int(blendSeconds * 1_000)))

        let positions = marks.map(\.position), periods = marks.map(\.period)
        let voiced = marks.map { UInt8($0.voiced ? 1 : 0) }
        let sources: [UnsafePointer<Float>?] = (0..<channels).map { UnsafePointer(source[$0]) }
        let destinations: [UnsafeMutablePointer<Float>?] = (0..<channels).map { destination[$0] }
        sources.withUnsafeBufferPointer { sourceList in
            destinations.withUnsafeBufferPointer { destinationList in
                lyv_psola(sourceList.baseAddress!, destinationList.baseAddress!, Int32(channels), Int32(frames), rate,
                          positions, periods, voiced, Int32(marks.count),
                          controlSource, controlSemitones, controlFormants, controlGain, controlMix,
                          Int32(controlCount), Int32(controlStep))
            }
        }
        return output
    }

    /// Moving average, applied forward and back so fades are symmetric.
    private static func smooth(_ values: inout [Float], width: Int) {
        guard width > 1, values.count > 1 else { return }
        for _ in 0..<2 {
            var output = values
            var sum: Float = 0
            for index in values.indices {
                sum += values[index]
                if index >= width { sum -= values[index - width] }
                output[index] = sum / Float(min(index + 1, width))
            }
            values = output.reversed()
        }
        // A running sum leaves rounding residue where it should be exactly
        // 0 or 1; untouched audio must stay bit-for-bit the original.
        for index in values.indices {
            if values[index] < 1e-4 { values[index] = 0 } else if values[index] > 1 - 1e-4 { values[index] = 1 }
        }
    }

    struct Mark {
        var position: Double   // sample
        var period: Double     // samples
        var voiced: Bool
    }

    /// Pulse marks through the recording: one per pitch period where it is
    /// sung, placed on the waveform's peak so consecutive grains line up in
    /// phase; fixed short steps where it is not.
    static func analysisMarks(mono: [Float], rate: Double, analysis: LYVocalAnalysis) -> [Mark] {
        let count = mono.count
        guard count > 0 else { return [] }
        var marks: [Mark] = []
        let unvoicedStep = unvoicedGrainSeconds * rate
        var position = 0.0
        while position < Double(count) {
            let time = position / rate
            if let pitch = analysis.pitch(at: time) {
                let period = rate / (440 * pow(2, (pitch - 69) / 12))
                // Peak within a quarter period of where the last period points.
                let low = max(0, Int(position - period * 0.25))
                let high = min(count - 1, Int(position + period * 0.25))
                var best = Int(position.rounded()).clamped(low, high)
                if high > low {
                    var peak: Float = 0
                    var peakIndex: vDSP_Length = 0
                    mono.withUnsafeBufferPointer { vDSP_maxvi($0.baseAddress! + low, 1, &peak, &peakIndex, vDSP_Length(high - low + 1)) }
                    best = low + Int(peakIndex)
                }
                // The first mark of a voiced run has no previous period to
                // follow; after that, peaks may not drift more than a quarter.
                let placed = marks.last.map { $0.voiced && Double(best) <= $0.position + 1 } == true ? position : Double(best)
                marks.append(Mark(position: placed, period: period, voiced: true))
                position = placed + period
            } else {
                marks.append(Mark(position: position, period: unvoicedStep, voiced: false))
                position += unvoicedStep
            }
        }
        return marks
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}

/// Rendered edits kept on disk for the session, keyed by the source file and
/// the edit, so playback, export and every stem pass share one render.
enum LYVocalRenderCache {
    private static let lock = NSLock()
    /// SIREN renders are deliberately serialized. Rapid note edits used to
    /// launch several whole-take PSOLA jobs at once, starving the UI and
    /// repeatedly forcing the transport to reschedule as stale jobs ended.
    private static let renderGate = DispatchSemaphore(value: 1)
    private static var rendered: [String: URL] = [:]
    private static var order: [String] = []

    static func url(forSource url: URL, edit: LYVocalEdit) throws -> URL {
        let key = url.standardizedFileURL.path + "|" + edit.renderKey
        lock.lock()
        if let hit = rendered[key], FileManager.default.fileExists(atPath: hit.path) { lock.unlock(); return hit }
        lock.unlock()

        renderGate.wait()
        defer { renderGate.signal() }
        try Task.checkCancellation()
        // Another request may have completed this exact edit while we waited.
        lock.lock()
        if let hit = rendered[key], FileManager.default.fileExists(atPath: hit.path) { lock.unlock(); return hit }
        lock.unlock()

        let file = try AVAudioFile(forReading: url)
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LYAudioEventRenderError.bufferAllocation
        }
        try file.read(into: input)
        let analysis = try LYVocalAnalysisCache.shared.analysis(for: url)
        try Task.checkCancellation()
        let plan = LYVocalRenderer.plan(edit: edit, analysis: analysis)
        guard let output = LYVocalRenderer.render(input, plan: plan) else { throw LYAudioEventRenderError.renderFailed }
        try Task.checkCancellation()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LYLLTH-SIREN", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let writer = try AVAudioFile(forWriting: destination, settings: output.format.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer.write(from: output)
        lock.lock(); defer { lock.unlock() }
        rendered[key] = destination
        // Keep the last few renders per recording; an edit session makes a
        // new one every time a note is let go.
        let prefix = url.standardizedFileURL.path + "|"
        order.append(key)
        let mine = order.filter { $0.hasPrefix(prefix) }
        for stale in mine.dropLast(4) {
            if let file = rendered.removeValue(forKey: stale) { try? FileManager.default.removeItem(at: file) }
            order.removeAll { $0 == stale }
        }
        return destination
    }
}
