import Foundation
import NightshapeAudioEngine

enum LYTrackKind: String, Codable, CaseIterable {
    case drumkit
    case audio
    case instrument
    case auxiliary

    var label: String {
        switch self {
        case .drumkit: return "DRUMKIT"
        case .audio: return "AUDIO"
        case .instrument: return "INSTRUMENT"
        case .auxiliary: return "AUX"
        }
    }
}

enum LYAccent: String, Codable, CaseIterable {
    case teal
    case indigo
    case purple
}

enum LYArrangementSnapMode: String, Codable, CaseIterable, Identifiable {
    case smart
    case bar
    case beat
    case division
    case ticks
    case frames
    case quarterFrames
    case samples
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smart: return "SMART"
        case .bar: return "BAR"
        case .beat: return "BEAT"
        case .division: return "DIVISION"
        case .ticks: return "TICKS"
        case .frames: return "FRAMES"
        case .quarterFrames: return "1/4 FRAMES"
        case .samples: return "SAMPLES"
        case .off: return "OFF"
        }
    }
}

enum LYSnapAlignment: String, Codable, CaseIterable {
    case absolute
    case relative

    var label: String { rawValue.uppercased() }
}

struct LYArrangementEditorState: Codable, Equatable {
    var horizontalZoom: Double = 29
    var verticalZoom: Double = 66
    var waveformZoom: Double = 1
    var snapMode: LYArrangementSnapMode = .smart
    var snapAlignment: LYSnapAlignment = .absolute
    var division: Int = 16
    var showsGrid = true
    var autoHorizontalZoom = false
    var autoVerticalZoom = false

    static let `default` = LYArrangementEditorState()

    mutating func normalize() {
        horizontalZoom = min(max(horizontalZoom.isFinite ? horizontalZoom : 29, 10), 140)
        verticalZoom = min(max(verticalZoom.isFinite ? verticalZoom : 66, 38), 144)
        waveformZoom = min(max(waveformZoom.isFinite ? waveformZoom : 1, 0.25), 8)
        division = [4, 8, 16, 32, 64].contains(division) ? division : 16
    }

    func gridBeats(
        bpm: Double,
        numerator: Int,
        denominator: Int,
        sampleRate: Double,
        beatWidth: Double,
        overrideMode: LYArrangementSnapMode? = nil
    ) -> Double? {
        let selected = overrideMode ?? snapMode
        let beatsPerBar = max(1, Double(numerator) * 4 / Double(max(denominator, 1)))
        switch selected {
        case .smart:
            if beatWidth < 18 { return beatsPerBar }
            if beatWidth < 34 { return 1 }
            if beatWidth < 68 { return 0.5 }
            if beatWidth < 108 { return 0.25 }
            return 0.125
        case .bar: return beatsPerBar
        case .beat: return 1
        case .division: return 4 / Double(max(division, 1))
        case .ticks: return 1 / 3_840
        case .frames: return max(bpm, 1) / 60 / 30
        case .quarterFrames: return max(bpm, 1) / 60 / 120
        case .samples: return max(bpm, 1) / 60 / max(sampleRate, 1)
        case .off: return nil
        }
    }

    func snap(
        rawBeat: Double,
        originalBeat: Double,
        bpm: Double,
        numerator: Int,
        denominator: Int,
        sampleRate: Double,
        beatWidth: Double,
        overrideMode: LYArrangementSnapMode? = nil
    ) -> Double {
        guard let grid = gridBeats(
            bpm: bpm,
            numerator: numerator,
            denominator: denominator,
            sampleRate: sampleRate,
            beatWidth: beatWidth,
            overrideMode: overrideMode
        ), grid.isFinite, grid > 0 else { return max(0, rawBeat) }

        switch snapAlignment {
        case .absolute:
            return max(0, (rawBeat / grid).rounded() * grid)
        case .relative:
            let delta = rawBeat - originalBeat
            return max(0, originalBeat + (delta / grid).rounded() * grid)
        }
    }
}

enum LYPluginFormat: String, Codable {
    case builtIn
    case audioUnit
    case vst3
}

struct LYPluginSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var format: LYPluginFormat
    var identifier: String
    var name: String
    var manufacturer: String
    var isBypassed: Bool = false
    var state: Data?
}

/// Per-step performance locks. Values stay normalized where possible so the
/// document can feed both NIGHTSHAPE's current engine and future plug-in hosts.
struct LYStepParameters: Codable, Equatable {
    var velocity: Double = 0.82
    var level: Double = 0.82
    var cutoff: Double = 0.7
    var resonance: Double = 0.18
    var effect: Double = 0
    var pan: Double = 0
    var pitch: Double = 0
    var noteLength: Double = 1
    /// Chord choice 0...7, `ChordLaneCompiler.rest`, or nil to carry the
    /// previous chord. Only used by chord tracks.
    var chord: Int? = nil

    static let `default` = LYStepParameters()
}

enum LYAudioFadeCurve: String, Codable, CaseIterable {
    case linear
    case equalPower
    case sCurve
}

enum LYAudioStretchMode: String, Codable, CaseIterable {
    /// Source time is played one-for-one.
    case off
    /// The whole event follows project tempo while retaining pitch.
    case tempo
    /// TETHR-style transient anchors correct local drift as well as tempo.
    case beatMapped
}

struct LYBeatMarker: Codable, Identifiable, Equatable {
    var id = UUID()
    var index: Int
    var sourceTime: Double
    var confidence: Double
    var strength: Double
}

struct LYBeatMap: Codable, Equatable {
    var sourceBPM: Double
    var beatInterval: Double
    var firstBeatTime: Double
    var sourceDuration: Double
    var markers: [LYBeatMarker]
    var confidence: Double
    var averageDriftMS: Double
    var maxDriftMS: Double
}

struct LYBeatMapAnchor: Equatable {
    var sourceTime: Double
    var timelineTime: Double
}

/// Native representation of TETHR's accepted beat-correction mapping. It
/// keeps analysis data in source time and derives render anchors from the
/// current project tempo, so tempo changes never require destructive renders.
enum LYBeatMapPlanner {
    private static let confidentMarkerThreshold = 0.16
    private static let minimumCorrectionDriftMS = 10.0
    private static let fullCorrectionDriftMS = 46.0
    private static let residualSmoothingBeats = 4
    private static let maximumResidualStepSeconds = 0.040

    static func anchors(for map: LYBeatMap, targetBPM: Double) -> [LYBeatMapAnchor] {
        guard targetBPM > 0, map.sourceBPM > 0, map.sourceDuration > 0 else {
            return [LYBeatMapAnchor(sourceTime: 0, timelineTime: 0)]
        }

        let sourceToTargetRatio = targetBPM / map.sourceBPM
        let targetBeatInterval = 60 / targetBPM
        let targetFirstBeat = map.firstBeatTime / max(0.05, sourceToTargetRatio)
        let residuals = smoothedResiduals(map)
        let strength = correctionStrength(map)
        var values = [LYBeatMapAnchor(sourceTime: 0, timelineTime: 0)]

        for marker in map.markers.sorted(by: { $0.index < $1.index }) {
            let idealSource = map.firstBeatTime + Double(marker.index) * map.beatInterval
            let residual = residuals[marker.index] ?? 0
            let source = min(max(0, idealSource + residual * strength), map.sourceDuration)
            let target = max(0, targetFirstBeat + Double(marker.index) * targetBeatInterval)
            guard let last = values.last,
                  source > last.sourceTime + 0.035,
                  target > last.timelineTime + 0.035 else { continue }
            values.append(LYBeatMapAnchor(sourceTime: source, timelineTime: target))
        }

        if let last = values.last, map.sourceDuration > last.sourceTime + 0.035 {
            let tailTarget = last.timelineTime
                + (map.sourceDuration - last.sourceTime) / max(0.05, sourceToTargetRatio)
            values.append(
                LYBeatMapAnchor(
                    sourceTime: map.sourceDuration,
                    timelineTime: max(last.timelineTime + 0.035, tailTarget)
                )
            )
        }
        return values
    }

    static func timelineTime(forSourceTime sourceTime: Double, map: LYBeatMap, targetBPM: Double) -> Double {
        interpolate(
            value: min(max(sourceTime, 0), map.sourceDuration),
            anchors: anchors(for: map, targetBPM: targetBPM),
            source: \.sourceTime,
            target: \.timelineTime
        )
    }

    static func sourceTime(forTimelineTime timelineTime: Double, map: LYBeatMap, targetBPM: Double) -> Double {
        interpolate(
            value: max(0, timelineTime),
            anchors: anchors(for: map, targetBPM: targetBPM),
            source: \.timelineTime,
            target: \.sourceTime
        )
    }

    private static func interpolate(
        value: Double,
        anchors: [LYBeatMapAnchor],
        source: KeyPath<LYBeatMapAnchor, Double>,
        target: KeyPath<LYBeatMapAnchor, Double>
    ) -> Double {
        guard let first = anchors.first else { return value }
        if value <= first[keyPath: source] { return first[keyPath: target] }
        for index in 0..<(anchors.count - 1) {
            let lower = anchors[index]
            let upper = anchors[index + 1]
            let lowerValue = lower[keyPath: source]
            let upperValue = upper[keyPath: source]
            guard value >= lowerValue, value <= upperValue else { continue }
            let progress = (value - lowerValue) / max(0.000_001, upperValue - lowerValue)
            return lower[keyPath: target]
                + progress * (upper[keyPath: target] - lower[keyPath: target])
        }
        guard let last = anchors.last else { return value }
        return last[keyPath: target]
    }

    private static func correctionStrength(_ map: LYBeatMap) -> Double {
        let normalized = (map.averageDriftMS - minimumCorrectionDriftMS)
            / max(1, fullCorrectionDriftMS - minimumCorrectionDriftMS)
        let confident = map.markers.filter { $0.confidence >= confidentMarkerThreshold }
        return min(max(normalized, 0), 0.92) * residualCoherence(
            confident,
            firstBeatTime: map.firstBeatTime,
            beatInterval: map.beatInterval
        )
    }

    private static func residualCoherence(
        _ markers: [LYBeatMarker],
        firstBeatTime: Double,
        beatInterval: Double
    ) -> Double {
        guard markers.count >= 4 else { return 0 }
        let sorted = markers.sorted(by: { $0.index < $1.index })
        var total = 0.0
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let marker = sorted[index]
            let beatGap = max(1, marker.index - previous.index)
            let previousResidual = previous.sourceTime
                - (firstBeatTime + Double(previous.index) * beatInterval)
            let residual = marker.sourceTime
                - (firstBeatTime + Double(marker.index) * beatInterval)
            total += abs(residual - previousResidual) / Double(beatGap)
        }
        let meanStep = total / Double(sorted.count - 1)
        return min(max(1 - ((meanStep - 0.010) / 0.060), 0), 1)
    }

    private static func smoothedResiduals(_ map: LYBeatMap) -> [Int: Double] {
        let raw = map.markers.map { marker in
            (
                index: marker.index,
                value: marker.sourceTime
                    - (map.firstBeatTime + Double(marker.index) * map.beatInterval),
                weight: min(max(marker.confidence, 0.05), 1)
            )
        }
        var smoothed: [Int: Double] = [:]
        for marker in raw {
            var weighted = 0.0
            var totalWeight = 0.0
            for other in raw {
                let distance = abs(other.index - marker.index)
                guard distance <= residualSmoothingBeats else { continue }
                let proximity = 1 - Double(distance) / Double(residualSmoothingBeats + 1)
                let weight = other.weight * proximity * proximity
                weighted += other.value * weight
                totalWeight += weight
            }
            smoothed[marker.index] = totalWeight > 0 ? weighted / totalWeight : marker.value
        }

        var previous = smoothed[0] ?? 0
        for index in map.markers.map(\.index).sorted() {
            let value = smoothed[index] ?? previous
            let delta = min(max(value - previous, -maximumResidualStepSeconds), maximumResidualStepSeconds)
            let limited = previous + delta
            smoothed[index] = limited
            previous = limited
        }
        return smoothed
    }
}

/// TETHR's transient-following beat detector, expressed as a pure Swift
/// analysis stage so imported or recorded PCM can use the same map. Rendering
/// remains separate: this never alters the source samples.
enum LYBeatMapAnalyzer {
    private static let analysisHop = 512
    private static let analysisFrame = 1_024
    private static let minimumMarkers = 8
    private static let confidentMarkerThreshold = 0.16
    private static let minimumMapConfidence = 0.38

    private struct OnsetEnvelope {
        var values: [Double]
        var hopSeconds: Double
        var threshold: Double
    }

    private struct Peak {
        var index: Int
        var strength: Double
        var score: Double
    }

    static func estimateBPM(
        monoSamples: [Float],
        sampleRate: Double,
        minimumBPM: Double = 60,
        maximumBPM: Double = 200
    ) -> (bpm: Double, confidence: Double)? {
        guard sampleRate > 0, minimumBPM > 0, maximumBPM > minimumBPM else { return nil }
        let frameSize = max(1, Int(sampleRate * 0.05))
        let frameCount = monoSamples.count / frameSize
        guard frameCount > 16 else { return nil }

        var envelope = [Double](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let start = frame * frameSize
            var energy = 0.0
            for index in start..<(start + frameSize) {
                let sample = Double(monoSamples[index])
                energy += sample * sample
            }
            envelope[frame] = sqrt(energy / Double(frameSize))
        }

        var smoothed = envelope
        for index in envelope.indices {
            let lower = max(0, index - 2)
            let upper = min(envelope.count - 1, index + 2)
            smoothed[index] = envelope[lower...upper].reduce(0, +) / Double(upper - lower + 1)
        }
        var onset = [Double](repeating: 0, count: smoothed.count)
        for index in 1..<smoothed.count {
            onset[index] = max(0, smoothed[index] - smoothed[index - 1])
        }

        let frameRate = sampleRate / Double(frameSize)
        let minimumLag = max(1, Int(frameRate * 60 / maximumBPM))
        let maximumLag = Int(frameRate * 60 / minimumBPM)
        guard minimumLag < maximumLag, maximumLag < onset.count else { return nil }

        var scores: [(lag: Int, score: Double)] = []
        let compareCount = onset.count - maximumLag
        for lag in minimumLag...maximumLag {
            var score = 0.0
            for index in 0..<compareCount {
                score += onset[index] * onset[index + lag]
            }
            scores.append((lag, score))
        }
        guard let best = scores.max(by: { $0.score < $1.score }), best.score > 0 else { return nil }
        let average = scores.map(\.score).reduce(0, +) / Double(scores.count)
        let confidence = min(max((best.score - average) / max(best.score, 0.000_001), 0), 1)
        let bpm = 60 * frameRate / Double(best.lag)
        return (bpm, confidence)
    }

    static func detect(
        monoSamples: [Float],
        sampleRate: Double,
        sourceBPM requestedBPM: Double
    ) -> LYBeatMap? {
        guard sampleRate > 0,
              requestedBPM > 0,
              Double(monoSamples.count) / sampleRate >= 2,
              let envelope = onsetEnvelope(samples: monoSamples, sampleRate: sampleRate),
              envelope.values.count >= 8 else { return nil }

        let sourceBPM = min(max(requestedBPM, 40), 240)
        let beatInterval = 60 / sourceBPM
        let beatFrames = max(1, Int((beatInterval / envelope.hopSeconds).rounded()))
        let phase = estimateBeatPhase(envelope.values, beatFrames: beatFrames)
        let markers = trackBeats(envelope, sourceBPM: sourceBPM, phaseFrame: phase)
        let confident = markers.filter { $0.confidence >= confidentMarkerThreshold }
        let duration = Double(monoSamples.count) / sampleRate
        let minimumRatio = duration > 45 ? 0.28 : 0.38

        guard markers.count >= minimumMarkers,
              Double(confident.count) >= max(4, Double(markers.count) * minimumRatio) else { return nil }

        let firstBeatTime = estimateFirstBeatTime(
            confident.isEmpty ? markers : confident,
            beatInterval: beatInterval
        )
        let drift = confident.map {
            abs($0.sourceTime - (firstBeatTime + Double($0.index) * beatInterval)) * 1_000
        }
        let averageDrift = drift.isEmpty ? 0 : drift.reduce(0, +) / Double(drift.count)
        let maximumDrift = drift.max() ?? 0
        let coverage = Double(confident.count) / Double(markers.count)
        let meanStrength = confident.isEmpty
            ? 0
            : confident.map(\.strength).reduce(0, +) / Double(confident.count)
        let coherence = residualCoherence(
            confident,
            firstBeatTime: firstBeatTime,
            beatInterval: beatInterval
        )
        let confidence = min(max(
            coverage * 0.56 + min(1, meanStrength) * 0.24 + coherence * 0.20,
            0
        ), 1)
        guard confidence >= minimumMapConfidence else { return nil }

        return LYBeatMap(
            sourceBPM: sourceBPM,
            beatInterval: beatInterval,
            firstBeatTime: firstBeatTime,
            sourceDuration: duration,
            markers: markers,
            confidence: confidence,
            averageDriftMS: averageDrift,
            maxDriftMS: maximumDrift
        )
    }

    private static func onsetEnvelope(samples: [Float], sampleRate: Double) -> OnsetEnvelope? {
        let frameCount = (samples.count - analysisFrame) / analysisHop
        guard frameCount >= 8 else { return nil }
        var raw = [Double](repeating: 0, count: frameCount)
        var previousRMS = 0.0
        var previousFlux = 0.0
        var maximum = 0.0

        for frame in 0..<frameCount {
            let start = frame * analysisHop
            var energy = 0.0
            var flux = 0.0
            var previousSample = 0.0
            for index in 0..<analysisFrame {
                let sample = Double(samples[start + index])
                energy += sample * sample
                flux += abs(sample - previousSample)
                previousSample = sample
            }
            let rms = sqrt(energy / Double(analysisFrame))
            let transientFlux = flux / Double(analysisFrame)
            let onset = max(0, rms - previousRMS) * 0.68
                + max(0, transientFlux - previousFlux) * 0.32
            raw[frame] = onset
            maximum = max(maximum, onset)
            previousRMS = rms
            previousFlux = transientFlux
        }
        guard maximum > 0 else { return nil }

        var values = [Double](repeating: 0, count: frameCount)
        var sum = 0.0
        for index in 0..<frameCount {
            let previous = raw[max(0, index - 1)]
            let current = raw[index]
            let next = raw[min(frameCount - 1, index + 1)]
            let value = (previous * 0.25 + current * 0.5 + next * 0.25) / maximum
            values[index] = value
            sum += value
        }
        let mean = sum / Double(frameCount)
        let variance = values.map { value in
            let difference = value - mean
            return difference * difference
        }.reduce(0, +) / Double(frameCount)
        return OnsetEnvelope(
            values: values,
            hopSeconds: Double(analysisHop) / sampleRate,
            threshold: min(max(mean + sqrt(variance) * 0.35, 0.045), 0.35)
        )
    }

    private static func estimateBeatPhase(_ values: [Double], beatFrames: Int) -> Int {
        let phaseStep = max(1, beatFrames / 72)
        let localRadius = max(1, Int(Double(beatFrames) * 0.06))
        var bestPhase = 0
        var bestScore = -Double.infinity
        for phase in stride(from: 0, to: beatFrames, by: phaseStep) {
            var score = 0.0
            var count = 0
            for frame in stride(from: phase, to: values.count, by: beatFrames) {
                score += localPeak(values, center: frame, radius: localRadius).score
                count += 1
            }
            let normalized = count > 0 ? score / sqrt(Double(count)) : 0
            if normalized > bestScore {
                bestScore = normalized
                bestPhase = phase
            }
        }
        return bestPhase
    }

    private static func trackBeats(
        _ envelope: OnsetEnvelope,
        sourceBPM: Double,
        phaseFrame: Int
    ) -> [LYBeatMarker] {
        let beatInterval = 60 / sourceBPM
        let beatFrames = max(1, Int((beatInterval / envelope.hopSeconds).rounded()))
        let searchRadius = max(2, Int(Double(beatFrames) * 0.28))
        let minimumSpacing = beatInterval * 0.45
        var markers: [LYBeatMarker] = []
        var predictedFrame = phaseFrame
        var index = 0

        while predictedFrame < envelope.values.count {
            let peak = localPeak(envelope.values, center: predictedFrame, radius: searchRadius)
            let strongEnough = peak.strength >= envelope.threshold
            let peakTime = Double(peak.index) * envelope.hopSeconds
            let predictedTime = Double(predictedFrame) * envelope.hopSeconds
            let tooClose = markers.last.map { peakTime - $0.sourceTime < minimumSpacing } ?? false
            let pull = strongEnough && !tooClose ? min(0.62, 0.24 + peak.strength * 0.34) : 0
            let trackedTime = predictedTime + (peakTime - predictedTime) * pull
            let sourceTime = strongEnough && !tooClose ? peakTime : predictedTime
            let strength = strongEnough && !tooClose ? peak.strength : max(0, peak.strength * 0.45)
            if sourceTime >= 0, sourceTime.isFinite {
                markers.append(
                    LYBeatMarker(
                        index: index,
                        sourceTime: sourceTime,
                        confidence: min(max(strength, 0), 1),
                        strength: strength
                    )
                )
            }
            predictedFrame = Int(((trackedTime + beatInterval) / envelope.hopSeconds).rounded())
            index += 1
        }
        return markers
    }

    private static func localPeak(_ values: [Double], center: Int, radius: Int) -> Peak {
        let start = max(0, center - radius)
        let end = min(values.count - 1, center + radius)
        var bestIndex = min(max(0, center), values.count - 1)
        var bestStrength = values[bestIndex]
        var bestScore = bestStrength
        for index in start...end {
            let value = values[index]
            let distance = Double(abs(index - center)) / Double(max(1, radius))
            let proximity = 1 - min(1, distance)
            let score = value * (0.58 + proximity * 0.42)
            if score > bestScore {
                bestIndex = index
                bestStrength = value
                bestScore = score
            }
        }
        return Peak(index: bestIndex, strength: bestStrength, score: bestScore)
    }

    private static func estimateFirstBeatTime(_ markers: [LYBeatMarker], beatInterval: Double) -> Double {
        let candidates = markers.map { marker in
            (
                value: marker.sourceTime - Double(marker.index) * beatInterval,
                weight: max(0.05, marker.confidence)
            )
        }.sorted(by: { $0.value < $1.value })
        let total = candidates.map(\.weight).reduce(0, +)
        var running = 0.0
        for candidate in candidates {
            running += candidate.weight
            if running >= total * 0.5 { return candidate.value }
        }
        return markers.first?.sourceTime ?? 0
    }

    private static func residualCoherence(
        _ markers: [LYBeatMarker],
        firstBeatTime: Double,
        beatInterval: Double
    ) -> Double {
        guard markers.count >= 4 else { return 0 }
        let sorted = markers.sorted(by: { $0.index < $1.index })
        var total = 0.0
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let marker = sorted[index]
            let gap = max(1, marker.index - previous.index)
            let previousResidual = previous.sourceTime
                - (firstBeatTime + Double(previous.index) * beatInterval)
            let residual = marker.sourceTime
                - (firstBeatTime + Double(marker.index) * beatInterval)
            total += abs(residual - previousResidual) / Double(gap)
        }
        let meanStep = total / Double(sorted.count - 1)
        return min(max(1 - ((meanStep - 0.010) / 0.060), 0), 1)
    }
}

struct LYClip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case pattern
        case audio
        case midi
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var startBeat: Double
    var lengthBeats: Double
    var steps: [Bool]?
    var stepParameters: [LYStepParameters]?
    var sourceRelativePath: String?
    /// Non-destructive ACID-style event properties. All source locations are
    /// measured in the original file; moving or duplicating an event never
    /// rewrites audio.
    var sourceStartSeconds: Double = 0
    var sourceDurationSeconds: Double?
    var waveformPeaks: [Float]?
    var sourceSampleRate: Double?
    var sourceChannelCount: Int?
    var slipOffsetSeconds: Double = 0
    var eventGainDB: Double = 0
    var pitchSemitones: Double = 0
    var fadeInSeconds: Double = 0
    var fadeOutSeconds: Double = 0
    var fadeCurve: LYAudioFadeCurve = .equalPower
    var stretchMode: LYAudioStretchMode = .off
    var sourceBPM: Double?
    var preservePitch = true
    var beatMap: LYBeatMap?
    var isMuted = false
    var isLocked = false
    var isLooped = false
    /// Where playback enters the source cycle, in beats. Trimming an event's
    /// left edge or splitting it moves this instead of rewriting the source
    /// region, so every piece of a chopped loop still repeats the same loop.
    var loopOffsetBeats: Double = 0
    /// Length of the whole original file. `waveformPeaks` spans all of it.
    var sourceFileDurationSeconds: Double?

    /// Resize a sequenced clip without turning newly-created chord space into
    /// an accidental sustain. Chord `nil` means HOLD, so the first appended
    /// step must be an explicit STOP; ordinary tracks simply gain empty cells.
    mutating func resizeSequencer(to requestedCount: Int, isChordTrack: Bool) {
        let count = min(max(requestedCount, 1), 64)
        var resizedSteps = steps ?? []
        var resizedLocks = stepParameters ?? []
        let oldCount = max(resizedSteps.count, resizedLocks.count)

        if resizedSteps.count < count {
            resizedSteps += Array(repeating: false, count: count - resizedSteps.count)
        }
        if resizedLocks.count < count {
            resizedLocks += Array(repeating: .default, count: count - resizedLocks.count)
        }
        if isChordTrack, count > oldCount, resizedLocks.indices.contains(oldCount) {
            resizedLocks[oldCount].chord = ChordLaneCompiler.rest
        }

        steps = Array(resizedSteps.prefix(count))
        stepParameters = Array(resizedLocks.prefix(count))
        lengthBeats = Double(max(count / 4, 1))
    }

    mutating func normalizeAudioEvent() {
        startBeat = max(0, startBeat.isFinite ? startBeat : 0)
        lengthBeats = max(0.001, lengthBeats.isFinite ? lengthBeats : 0.001)
        sourceStartSeconds = max(0, sourceStartSeconds.isFinite ? sourceStartSeconds : 0)
        if let duration = sourceDurationSeconds {
            sourceDurationSeconds = max(0.001, duration.isFinite ? duration : 0.001)
        }
        waveformPeaks = waveformPeaks?.map { min(max($0.isFinite ? $0 : 0, 0), 1) }
        if let rate = sourceSampleRate {
            sourceSampleRate = max(1, rate.isFinite ? rate : 44_100)
        }
        if let channels = sourceChannelCount {
            sourceChannelCount = min(max(channels, 1), 64)
        }
        slipOffsetSeconds = slipOffsetSeconds.isFinite ? slipOffsetSeconds : 0
        eventGainDB = min(max(eventGainDB.isFinite ? eventGainDB : 0, -60), 12)
        pitchSemitones = min(max(pitchSemitones.isFinite ? pitchSemitones : 0, -48), 48)
        fadeInSeconds = max(0, fadeInSeconds.isFinite ? fadeInSeconds : 0)
        fadeOutSeconds = max(0, fadeOutSeconds.isFinite ? fadeOutSeconds : 0)
        if let bpm = sourceBPM {
            sourceBPM = min(max(bpm.isFinite ? bpm : 120, 20), 400)
        }
        loopOffsetBeats = loopOffsetBeats.isFinite ? max(0, loopOffsetBeats) : 0
    }
}

extension LYClip {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, startBeat, lengthBeats, steps, stepParameters, sourceRelativePath
        case sourceStartSeconds, sourceDurationSeconds, waveformPeaks, sourceSampleRate, sourceChannelCount
        case slipOffsetSeconds, eventGainDB
        case pitchSemitones, fadeInSeconds, fadeOutSeconds, fadeCurve, stretchMode
        case sourceBPM, preservePitch, beatMap, isMuted, isLocked, isLooped, loopOffsetBeats, sourceFileDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(Kind.self, forKey: .kind)
        startBeat = try values.decode(Double.self, forKey: .startBeat)
        lengthBeats = try values.decode(Double.self, forKey: .lengthBeats)
        steps = try values.decodeIfPresent([Bool].self, forKey: .steps)
        stepParameters = try values.decodeIfPresent([LYStepParameters].self, forKey: .stepParameters)
        sourceRelativePath = try values.decodeIfPresent(String.self, forKey: .sourceRelativePath)
        sourceStartSeconds = try values.decodeIfPresent(Double.self, forKey: .sourceStartSeconds) ?? 0
        sourceDurationSeconds = try values.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds)
        waveformPeaks = try values.decodeIfPresent([Float].self, forKey: .waveformPeaks)
        sourceSampleRate = try values.decodeIfPresent(Double.self, forKey: .sourceSampleRate)
        sourceChannelCount = try values.decodeIfPresent(Int.self, forKey: .sourceChannelCount)
        slipOffsetSeconds = try values.decodeIfPresent(Double.self, forKey: .slipOffsetSeconds) ?? 0
        eventGainDB = try values.decodeIfPresent(Double.self, forKey: .eventGainDB) ?? 0
        pitchSemitones = try values.decodeIfPresent(Double.self, forKey: .pitchSemitones) ?? 0
        fadeInSeconds = try values.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 0
        fadeOutSeconds = try values.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 0
        fadeCurve = try values.decodeIfPresent(LYAudioFadeCurve.self, forKey: .fadeCurve) ?? .equalPower
        stretchMode = try values.decodeIfPresent(LYAudioStretchMode.self, forKey: .stretchMode) ?? .off
        sourceBPM = try values.decodeIfPresent(Double.self, forKey: .sourceBPM)
        preservePitch = try values.decodeIfPresent(Bool.self, forKey: .preservePitch) ?? true
        beatMap = try values.decodeIfPresent(LYBeatMap.self, forKey: .beatMap)
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isLooped = try values.decodeIfPresent(Bool.self, forKey: .isLooped) ?? false
        loopOffsetBeats = try values.decodeIfPresent(Double.self, forKey: .loopOffsetBeats) ?? 0
        sourceFileDurationSeconds = try values.decodeIfPresent(Double.self, forKey: .sourceFileDurationSeconds)
        normalizeAudioEvent()
    }
}

enum LYAudioEventEditor {
    /// Splits without touching the source region: the right piece enters the
    /// source where the cut fell. Both halves still loop the original audio if
    /// they are dragged longer, which is what makes chop-and-repeat work.
    static func split(_ clip: LYClip, atBeat beat: Double) -> (left: LYClip, right: LYClip)? {
        let end = clip.startBeat + clip.lengthBeats
        guard beat > clip.startBeat + 0.000_001, beat < end - 0.000_001 else { return nil }

        var left = clip
        var right = clip
        left.id = UUID()
        right.id = UUID()
        left.lengthBeats = beat - clip.startBeat
        right.startBeat = beat
        right.lengthBeats = end - beat
        right.loopOffsetBeats = clip.loopOffsetBeats + (beat - clip.startBeat)
        left.fadeOutSeconds = 0
        right.fadeInSeconds = 0
        left.normalizeAudioEvent()
        right.normalizeAudioEvent()
        return (left, right)
    }

    static func duplicate(_ clip: LYClip, atBeat beat: Double? = nil) -> LYClip {
        var copy = clip
        copy.id = UUID()
        copy.startBeat = max(0, beat ?? (clip.startBeat + clip.lengthBeats))
        copy.name = clip.name
        return copy
    }
}

struct LYTrack: Codable, Identifiable, Equatable {
    var isArmed: Bool {
        get { isRecordArmed ?? false }
        set { isRecordArmed = newValue }
    }

    var id = UUID()
    var name: String
    var kind: LYTrackKind
    var accent: LYAccent
    var volumeDB: Double = 0
    var pan: Double = 0
    var isMuted = false
    var isSolo = false
    /// Record arm. Optional preserves older documents.
    var isRecordArmed: Bool? = nil
    var inputName: String?
    var isChordTrack: Bool? = nil
    var chordPresetID: String? = nil
    var synthPresetID: String? = nil
    var rootNote: Int? = nil
    var clips: [LYClip] = []
    var inserts: [LYPluginSlot] = []
    /// NIGHTSHAPE effects on this channel. Optional preserves older documents.
    var fx: LYFXRack? = nil
    /// Set when this track plays LYLLTH SYNTH instead of a DrumKit synth preset.
    var synth: LYSynthPatch? = nil
    /// A drum track's DrumKit drum-synth preset. nil plays the default chosen
    /// from the track's name.
    var drumPresetID: String? = nil
    /// Post-fader sends into AUX RETURN tracks. Optional preserves older documents.
    var sends: [LYBusSend]? = nil
    /// The AUX RETURN this track plays through instead of MAIN. nil is MAIN.
    var outputBusID: UUID? = nil
}

/// One send from a track into an AUX RETURN.
struct LYBusSend: Codable, Equatable, Identifiable {
    var id: UUID { busID }
    var busID: UUID
    /// Linear gain, 0…1. 1 is 0 dB.
    var level: Float = 0.7
}

struct LYLoopRange: Codable, Equatable {
    var startBeat: Double
    var lengthBeats: Double
}

struct LYLLTHSession: Codable, Equatable {
    static let currentSchemaVersion = 4

    var schemaVersion = currentSchemaVersion
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var bpm: Double
    var numerator: Int
    var denominator: Int
    var sampleRate: Double
    var bitDepth: Int
    var loopRange: LYLoopRange?
    /// LOOP on the transport. Optional preserves older documents, which loop.
    var isLoopEnabled: Bool? = nil
    /// Four clicks before recording starts. Optional preserves older
    /// documents; on unless turned off.
    var countIn: Bool? = nil
    /// Optional preserves documents created before desktop pattern editing.
    var activePatternIndex: Int? = nil
    /// Shared with DrumKit's chord system. Optional preserves older documents.
    var songKey: SongKey? = nil
    /// Per-project Tracks-area view state. Optional preserves older documents.
    var arrangementEditor: LYArrangementEditorState? = nil
    /// MAIN's NIGHTSHAPE effects and the shared reverb every track sends to.
    var mainFX: LYFXRack? = nil
    /// MAIN fader, dB (≤ 0). Optional preserves older documents.
    var mainVolumeDB: Double? = nil
    var reverb: ReverbState? = nil
    var tracks: [LYTrack]

    var isLoopActive: Bool { (isLoopEnabled ?? true) && loopRange != nil }

    static func starter() -> LYLLTHSession {
        func pattern(
            _ name: String,
            index: Int,
            positions: [Int],
            velocity: Double = 0.82,
            noteLength: Double = 1,
            kind: LYClip.Kind = .pattern
        ) -> LYClip {
            var steps = Array(repeating: false, count: 16)
            var locks = Array(repeating: LYStepParameters.default, count: 16)
            for position in positions where steps.indices.contains(position) {
                steps[position] = true
                locks[position].velocity = velocity
                locks[position].noteLength = noteLength
            }
            return LYClip(
                name: name,
                kind: kind,
                startBeat: Double(index * 16),
                lengthBeats: 16,
                steps: steps,
                stepParameters: locks
            )
        }

        func voiceTrack(
            _ name: String,
            kind: LYTrackKind,
            accent: LYAccent,
            preset: SynthPreset,
            root: Int,
            first: [Int],
            second: [Int],
            velocity: Double = 0.82,
            noteLength: Double = 1,
            volumeDB: Double = -6
        ) -> LYTrack {
            LYTrack(
                name: name,
                kind: kind,
                accent: accent,
                volumeDB: volumeDB,
                synthPresetID: preset.rawValue,
                rootNote: root,
                clips: [
                    pattern("PATTERN 01", index: 0, positions: first, velocity: velocity, noteLength: noteLength, kind: kind == .drumkit ? .pattern : .midi),
                    pattern("PATTERN 02", index: 1, positions: second, velocity: velocity, noteLength: noteLength, kind: kind == .drumkit ? .pattern : .midi)
                ]
            )
        }

        var homeChord = Array(repeating: LYStepParameters.default, count: 16)
        homeChord[0].chord = 0
        var contrastChord = Array(repeating: LYStepParameters.default, count: 16)
        contrastChord[0].chord = 5

        var tracks: [LYTrack] = [
            voiceTrack("KICK", kind: .drumkit, accent: .teal, preset: .deepMono, root: 36, first: [0, 4, 8, 12], second: [0, 3, 7, 8, 11, 14], velocity: 0.95, volumeDB: -3),
            voiceTrack("SNARE", kind: .drumkit, accent: .purple, preset: .noiseSweep, root: 38, first: [4, 12], second: [4, 10, 12], velocity: 0.84),
            voiceTrack("CLOSED HAT", kind: .drumkit, accent: .indigo, preset: .ringBell, root: 42, first: [2, 6, 10, 14], second: [0, 2, 4, 6, 8, 10, 12, 14], velocity: 0.55),
            voiceTrack("OPEN HAT", kind: .drumkit, accent: .teal, preset: .ringBell, root: 46, first: [6, 14], second: [6, 15], velocity: 0.62, noteLength: 2),
            voiceTrack("CLAP", kind: .drumkit, accent: .purple, preset: .noiseSweep, root: 39, first: [4, 12], second: [4, 12, 15], velocity: 0.7),
            voiceTrack("LOW TOM", kind: .drumkit, accent: .teal, preset: .deepMono, root: 43, first: [], second: [9, 11, 13], velocity: 0.76),
            voiceTrack("HIGH TOM", kind: .drumkit, accent: .indigo, preset: .ringBell, root: 50, first: [], second: [10, 12, 14], velocity: 0.7),
            voiceTrack("PERC", kind: .drumkit, accent: .purple, preset: .ringBell, root: 56, first: [3, 11], second: [3, 7, 11, 15], velocity: 0.61),
            voiceTrack("SHAKER", kind: .drumkit, accent: .teal, preset: .noiseSweep, root: 62, first: [1, 3, 5, 7, 9, 11, 13, 15], second: Array(0..<16), velocity: 0.42),
            LYTrack(
                name: "DARK POLY",
                kind: .instrument,
                accent: .indigo,
                volumeDB: -8,
                isMuted: true,
                isChordTrack: true,
                chordPresetID: "rootNotes",
                synthPresetID: SynthPreset.junoDream.rawValue,
                rootNote: 48,
                clips: [
                    LYClip(name: "CHORD BED 01", kind: .midi, startBeat: 0, lengthBeats: 16, steps: Array(repeating: false, count: 16), stepParameters: homeChord),
                    LYClip(name: "CHORD BED 02", kind: .midi, startBeat: 16, lengthBeats: 16, steps: Array(repeating: false, count: 16), stepParameters: contrastChord)
                ],
                inserts: [LYPluginSlot(format: .builtIn, identifier: "nightshape.chorus", name: "CHORUS", manufacturer: "NIGHTSHAPE")]
            ),
            voiceTrack("SUB BASS", kind: .instrument, accent: .teal, preset: .deepDrop, root: 36, first: [0, 7, 8, 14], second: [0, 3, 8, 11], velocity: 0.78, noteLength: 3, volumeDB: -7),
            voiceTrack("GLASS ARP", kind: .instrument, accent: .purple, preset: .glassPluck, root: 60, first: [0, 2, 4, 6, 8, 10, 12, 14], second: [1, 3, 5, 7, 9, 11, 13, 15], velocity: 0.62, volumeDB: -10),
            voiceTrack("ANALOG PAD", kind: .instrument, accent: .indigo, preset: .analogPad, root: 48, first: [0, 8], second: [0, 4, 8, 12], velocity: 0.54, noteLength: 8, volumeDB: -12),
            voiceTrack("SYNC LEAD", kind: .instrument, accent: .purple, preset: .syncLead, root: 60, first: [7, 10, 14], second: [2, 6, 9, 13], velocity: 0.66, noteLength: 2, volumeDB: -11),
            voiceTrack("VINTAGE KEYS", kind: .instrument, accent: .teal, preset: .vintageKeys, root: 60, first: [0, 4, 8, 12], second: [0, 6, 8, 14], velocity: 0.58, noteLength: 3, volumeDB: -10),
            voiceTrack("FX TEXTURE", kind: .instrument, accent: .indigo, preset: .noiseSweep, root: 72, first: [15], second: [7, 15], velocity: 0.5, noteLength: 4, volumeDB: -14)
        ]

        tracks[0].inserts = Self.nightshapeStarterChain
        // The melodic starter tracks play LYLLTH SYNTH factory sounds.
        let starterSounds = [
            "SUB BASS": "SUB PRESSURE", "GLASS ARP": "GLASS ARP", "ANALOG PAD": "NIGHT PAD",
            "SYNC LEAD": "SYNC SCREAM", "VINTAGE KEYS": "NIGHT KEYS", "FX TEXTURE": "SPECTRAL DRIFT"
        ]
        for index in tracks.indices {
            if let sound = starterSounds[tracks[index].name] { tracks[index].synth = LYSynthPatch.factory(named: sound) }
        }
        tracks.append(
            LYTrack(
                name: "VOCAL",
                kind: .audio,
                accent: .purple,
                volumeDB: -6,
                inputName: "INPUT 1"
            )
        )
        tracks.append(LYTrack(name: "RETURN A", kind: .auxiliary, accent: .teal, volumeDB: -8))

        return LYLLTHSession(
            name: "UNTITLED 01",
            bpm: 118,
            numerator: 4,
            denominator: 4,
            sampleRate: 48_000,
            bitDepth: 24,
            loopRange: LYLoopRange(startBeat: 0, lengthBeats: 16),
            activePatternIndex: 0,
            songKey: .default,
            arrangementEditor: .default,
            tracks: tracks
        )
    }

    /// Version 1's starter project auto-played one held chord root. Extending
    /// the pattern padded chord locks with `nil` (HOLD), so a 32-step pattern
    /// became 8/16 steps of rhythm followed by a lone sustained synth note.
    /// Repair only the recognizable untouched starter scaffold; user-created
    /// chord tracks and renamed/customized projects retain their state.
    func migratedToCurrentSchema() -> LYLLTHSession {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        var migrated = self

        let starterNames = [
            "KICK", "SNARE", "CLOSED HAT", "OPEN HAT", "CLAP", "LOW TOM",
            "HIGH TOM", "PERC", "SHAKER", "DARK POLY", "SUB BASS", "GLASS ARP",
            "ANALOG PAD", "SYNC LEAD", "VINTAGE KEYS", "FX TEXTURE"
        ]
        let musicalNames = migrated.tracks
            .filter { $0.kind == .drumkit || $0.kind == .instrument }
            .prefix(starterNames.count)
            .map(\.name)
        let isStarterScaffold = migrated.name == "UNTITLED 01" && Array(musicalNames) == starterNames

        if isStarterScaffold,
           let chordIndex = migrated.tracks.firstIndex(where: {
               $0.name == "DARK POLY"
                   && $0.isChordTrack == true
                   && $0.chordPresetID == "rootNotes"
                   && $0.synthPresetID == SynthPreset.junoDream.rawValue
           }) {
            migrated.tracks[chordIndex].isMuted = true
            for clipIndex in migrated.tracks[chordIndex].clips.indices {
                var clip = migrated.tracks[chordIndex].clips[clipIndex]
                guard var locks = clip.stepParameters, locks.count > 16 else { continue }
                let appendedSpaceIsBlank = locks.dropFirst(16).allSatisfy { $0 == .default }
                    && (clip.steps?.dropFirst(16).allSatisfy { !$0 } ?? true)
                if appendedSpaceIsBlank {
                    locks[16].chord = ChordLaneCompiler.rest
                    clip.stepParameters = locks
                    migrated.tracks[chordIndex].clips[clipIndex] = clip
                }
            }
        }

        // Version 4: songs from before LYLLTH SYNTH give their melodic starter
        // tracks the factory sounds new songs start with.
        if schemaVersion < 4 {
            let sounds = [
                "SUB BASS": "SUB PRESSURE", "GLASS ARP": "GLASS ARP", "ANALOG PAD": "NIGHT PAD",
                "SYNC LEAD": "SYNC SCREAM", "VINTAGE KEYS": "NIGHT KEYS", "FX TEXTURE": "SPECTRAL DRIFT"
            ]
            for index in migrated.tracks.indices where migrated.tracks[index].synth == nil {
                if let sound = sounds[migrated.tracks[index].name] {
                    migrated.tracks[index].synth = LYSynthPatch.factory(named: sound)
                }
            }
        }

        migrated.schemaVersion = Self.currentSchemaVersion
        return migrated
    }

    private static var nightshapeStarterChain: [LYPluginSlot] {
        [
            LYPluginSlot(format: .builtIn, identifier: "nightshape.equalizer", name: "EQUALIZER", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.compressor", name: "COMPRESSOR", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.decimator", name: "SONIC DECIMATOR", manufacturer: "NIGHTSHAPE")
        ]
    }
}
