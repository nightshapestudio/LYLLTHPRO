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
    var validationError: String?
    var reportedLatencySeconds: Double?
    var componentType: UInt32?
    var componentSubType: UInt32?
    var componentManufacturer: UInt32?
}

struct LYAudioTake: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sourceRelativePath: String
    var sourceStartSeconds: Double
    var durationSeconds: Double
    var recordedAt = Date()
}

struct LYCompSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Beat range relative to the clip.
    var startBeat: Double
    var lengthBeats: Double
    var takeID: UUID
}

enum LYTakeLaneEditor {
    /// Promotes a take across a beat range, splitting existing comp pieces
    /// without changing or rewriting any source recording.
    static func promote(takeID: UUID, from startBeat: Double, to endBeat: Double,
                        in source: LYClip) -> LYClip {
        guard source.kind == .audio, (source.takes ?? []).contains(where: { $0.id == takeID }) else { return source }
        var clip = source
        let start = min(max(startBeat, 0), clip.lengthBeats)
        let end = min(max(endBeat, start), clip.lengthBeats)
        guard end - start > 0.000_001 else { return clip }
        let fallback = clip.activeTakeID ?? takeID
        let existing = (clip.compSegments?.isEmpty == false ? clip.compSegments! : [
            LYCompSegment(startBeat: 0, lengthBeats: clip.lengthBeats, takeID: fallback)
        ])
        var boundaries = Set([0.0, clip.lengthBeats, start, end])
        for segment in existing {
            boundaries.insert(min(max(segment.startBeat, 0), clip.lengthBeats))
            boundaries.insert(min(max(segment.startBeat + segment.lengthBeats, 0), clip.lengthBeats))
        }
        let sorted = boundaries.sorted()
        var result: [LYCompSegment] = []
        for pair in zip(sorted, sorted.dropFirst()) where pair.1 - pair.0 > 0.000_001 {
            let midpoint = (pair.0 + pair.1) * 0.5
            let chosen = midpoint >= start && midpoint < end ? takeID :
                (existing.first { midpoint >= $0.startBeat && midpoint < $0.startBeat + $0.lengthBeats }?.takeID ?? fallback)
            if let last = result.indices.last, result[last].takeID == chosen,
               abs(result[last].startBeat + result[last].lengthBeats - pair.0) < 0.000_001 {
                result[last].lengthBeats += pair.1 - pair.0
            } else {
                result.append(LYCompSegment(startBeat: pair.0, lengthBeats: pair.1 - pair.0, takeID: chosen))
            }
        }
        clip.compSegments = result
        clip.activeTakeID = takeID
        return clip
    }

    static func chooseWholeTake(_ takeID: UUID, in source: LYClip) -> LYClip {
        promote(takeID: takeID, from: 0, to: source.lengthBeats, in: source)
    }

    /// Fade at each cut inside a comp, so switching takes never clicks.
    static let compSeamSeconds = 0.005

    /// What a comped region plays: one piece per comp segment, each reading
    /// its own take from where the segment falls. A region without a comp
    /// plays as it is.
    static func pieces(of clip: LYClip) -> [LYClip] {
        guard clip.kind == .audio, let takes = clip.takes, !takes.isEmpty,
              let segments = clip.compSegments, !segments.isEmpty else { return [clip] }
        // A punch-in trims the region inside its take; every take is trimmed
        // the same way, since loop passes are the same length.
        let base = takes.first {
            $0.sourceRelativePath == clip.sourceRelativePath
                && clip.sourceStartSeconds >= $0.sourceStartSeconds - 0.000_001
                && clip.sourceStartSeconds < $0.sourceStartSeconds + $0.durationSeconds
        }
        let trim = base.map { clip.sourceStartSeconds - $0.sourceStartSeconds } ?? 0
        let ordered = segments.sorted { $0.startBeat < $1.startBeat }
        let pieces = ordered.enumerated().compactMap { index, segment -> LYClip? in
            guard let take = takes.first(where: { $0.id == segment.takeID }),
                  segment.lengthBeats > 0.000_001 else { return nil }
            var piece = clip
            piece.id = segment.id
            piece.startBeat = clip.startBeat + segment.startBeat
            piece.lengthBeats = min(segment.lengthBeats, clip.lengthBeats - segment.startBeat)
            piece.sourceRelativePath = take.sourceRelativePath
            piece.sourceStartSeconds = take.sourceStartSeconds + trim
            piece.sourceDurationSeconds = clip.sourceDurationSeconds
            piece.loopOffsetBeats = clip.loopOffsetBeats + segment.startBeat
            piece.fadeInSeconds = index == 0 ? clip.fadeInSeconds : compSeamSeconds
            piece.fadeOutSeconds = index == ordered.count - 1 ? clip.fadeOutSeconds : compSeamSeconds
            piece.takes = nil
            piece.compSegments = nil
            piece.normalizeAudioEvent()
            return piece
        }
        return pieces.isEmpty ? [clip] : pieces
    }
}

extension LYLLTHSession {
    /// The song as playback and export hear it: comped regions become one
    /// plain region per comp segment.
    func withCompsExpanded() -> LYLLTHSession {
        guard tracks.contains(where: { $0.clips.contains { ($0.compSegments?.isEmpty == false) && $0.kind == .audio } }) else { return self }
        var copy = self
        for index in copy.tracks.indices where copy.tracks[index].kind == .audio {
            copy.tracks[index].clips = copy.tracks[index].clips.flatMap(LYTakeLaneEditor.pieces(of:))
        }
        return copy
    }
}

struct LYRecordingSettings: Codable, Equatable {
    /// Bars heard before the record downbeat. Zero starts immediately.
    var preRollBars = 1
    var punchRange: LYLoopRange?
    var loopTakes = true
    var inputChannel = 0
    var inputMonitoring = false
    /// Manual converter/interface correction added to measured device latency.
    var manualLatencyMS: Double = 0
}

/// Per-step performance locks. Values stay normalized where possible so the
/// document can feed both NIGHTSHAPE's current engine and future plug-in hosts.
/// One piano-roll note.
struct LYNote: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    /// Beats from the start of its clip.
    var start: Double
    var length: Double
    /// MIDI note number, 0…127.
    var pitch: Int
    /// 1…127.
    var velocity: Int = 100
    /// Polyphonic performance recorded with the note. Values are normalized
    /// and time is measured from the note-on, so looping and moving the clip
    /// keeps expression attached to the note it belongs to.
    var expression: [LYMIDIExpressionPoint]? = nil

    var end: Double { start + length }
}

enum LYMIDIExpressionKind: String, Codable, CaseIterable, Hashable {
    case pitchBend
    case pressure
    case timbre
    case modulation
    case sustain
    case controlChange
}

struct LYMIDIExpressionPoint: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    /// Beats after the owning note begins.
    var offset: Double
    var kind: LYMIDIExpressionKind
    /// MIDI CC number for `.controlChange`; nil for the named dimensions.
    var controller: Int? = nil
    /// Normalized 0...1, except pitch bend which is normalized -1...1.
    var value: Double
    /// The original MIDI channel. This keeps MPE member-channel identity.
    var channel: Int = 0

    mutating func normalize(noteLength: Double) {
        offset = min(max(offset.isFinite ? offset : 0, 0), max(noteLength, 0))
        channel = min(max(channel, 0), 15)
        controller = controller.map { min(max($0, 0), 127) }
        if kind == .pitchBend {
            value = min(max(value.isFinite ? value : 0, -1), 1)
        } else {
            value = min(max(value.isFinite ? value : 0, 0), 1)
        }
    }
}

enum LYAutomationMode: String, Codable, CaseIterable {
    case read
    case touch
    case latch
    case write

    var label: String { rawValue.uppercased() }
}

struct LYMIDIRouting: Codable, Equatable {
    /// nil accepts every connected source/channel.
    var inputSourceID: Int32? = nil
    var inputSourceName: String? = nil
    var inputChannel: Int? = nil
    /// nil keeps the track internal; a destination enables MIDI thru/output.
    var outputDestinationID: Int32? = nil
    var outputDestinationName: String? = nil
    var outputChannel: Int = 0
    var usesMPE = false

    mutating func normalize() {
        inputChannel = inputChannel.map { min(max($0, 0), 15) }
        outputChannel = min(max(outputChannel, 0), 15)
    }
}

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
    /// A quiet grace hit just ahead of the step, as in DrumKit.
    var flam: Bool? = nil

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

/// Direct, non-destructive warp-marker edits. Detection remains automatic,
/// but a producer can now correct, insert, or remove anchors without touching
/// the source audio.
enum LYWarpMarkerEditor {
    static func moving(_ markerID: UUID, to sourceTime: Double, in map: LYBeatMap) -> LYBeatMap {
        var edited = map
        guard let index = edited.markers.firstIndex(where: { $0.id == markerID }) else { return map }
        let lower = index > 0 ? edited.markers[index - 1].sourceTime + 0.001 : 0
        let upper = index + 1 < edited.markers.count
            ? edited.markers[index + 1].sourceTime - 0.001
            : edited.sourceDuration
        edited.markers[index].sourceTime = min(max(sourceTime, lower), max(lower, upper))
        edited.markers[index].confidence = 1
        edited.markers[index].strength = max(edited.markers[index].strength, 1)
        return edited
    }

    static func inserting(sourceTime: Double, beatIndex: Int, in map: LYBeatMap) -> LYBeatMap {
        var edited = map
        edited.markers.removeAll { $0.index == beatIndex }
        edited.markers.append(LYBeatMarker(
            index: beatIndex,
            sourceTime: min(max(sourceTime, 0), map.sourceDuration),
            confidence: 1,
            strength: 1
        ))
        edited.markers.sort { ($0.index, $0.sourceTime) < ($1.index, $1.sourceTime) }
        return edited
    }

    static func removing(_ markerID: UUID, from map: LYBeatMap) -> LYBeatMap {
        var edited = map
        edited.markers.removeAll { $0.id == markerID }
        return edited
    }
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
        /// Piano-roll notes with free timing, played on LUNATK.
        case notes
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
    /// Set on a pattern region that plays another clip's pattern: one more
    /// placement of that pattern in the song. Its own steps are unused, so
    /// editing the pattern changes every placement.
    var patternSourceID: UUID? = nil
    /// A pattern kept for the sequencer but not placed in the song.
    var isOffTimeline: Bool? = nil
    /// A note clip's notes, their times in beats from the clip's start.
    var notes: [LYNote]? = nil
    /// How long a note clip's content is before it repeats. nil: the clip's
    /// length when it was made.
    var noteLoopBeats: Double? = nil
    /// Non-destructive recording alternatives. The main source fields mirror
    /// the active take for compatibility with existing playback/export.
    var takes: [LYAudioTake]? = nil
    var activeTakeID: UUID? = nil
    var compSegments: [LYCompSegment]? = nil
    /// SIREN tuning, timing and alignment for an audio region.
    var vocal: LYVocalEdit? = nil
    /// Set on an audio event printed from a drum track's sound, so it can be
    /// printed again after the sound changes.
    var printedDrum: LYPrintedDrum? = nil

    var isNoteClip: Bool { kind == .notes }
    /// The repeating length of a note clip.
    var noteCycleBeats: Double { max(noteLoopBeats ?? lengthBeats, 0.25) }

    var isSequenced: Bool { kind == .pattern || kind == .midi }
    var isPlacement: Bool { isSequenced && patternSourceID != nil }
    /// Whether this clip sits on the arrangement and sets the song's length.
    var isInSong: Bool {
        kind == .audio ? sourceRelativePath != nil : isOffTimeline != true
    }

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
        case patternSourceID, isOffTimeline, notes, noteLoopBeats, takes, activeTakeID, compSegments, vocal
        case printedDrum
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
        patternSourceID = try values.decodeIfPresent(UUID.self, forKey: .patternSourceID)
        isOffTimeline = try values.decodeIfPresent(Bool.self, forKey: .isOffTimeline)
        notes = try values.decodeIfPresent([LYNote].self, forKey: .notes)
        noteLoopBeats = try values.decodeIfPresent(Double.self, forKey: .noteLoopBeats)
        takes = try values.decodeIfPresent([LYAudioTake].self, forKey: .takes)
        activeTakeID = try values.decodeIfPresent(UUID.self, forKey: .activeTakeID)
        compSegments = try values.decodeIfPresent([LYCompSegment].self, forKey: .compSegments)
        vocal = try values.decodeIfPresent(LYVocalEdit.self, forKey: .vocal)
        printedDrum = try values.decodeIfPresent(LYPrintedDrum.self, forKey: .printedDrum)
        normalizeAudioEvent()
    }
}

/// Where a printed drum sound came from: the drum track and the preset it
/// played.
struct LYPrintedDrum: Codable, Equatable {
    var trackID: UUID
    var presetID: String
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

    /// Applies a symmetric equal-power (or chosen) crossfade to two audio
    /// events that overlap. It never rewrites either source.
    static func crossfade(
        _ first: LYClip,
        _ second: LYClip,
        curve: LYAudioFadeCurve = .equalPower,
        bpm: Double
    ) -> (first: LYClip, second: LYClip)? {
        guard first.kind == .audio, second.kind == .audio, bpm > 0 else { return nil }
        var left = first.startBeat <= second.startBeat ? first : second
        var right = first.startBeat <= second.startBeat ? second : first
        let overlapBeats = min(left.startBeat + left.lengthBeats, right.startBeat + right.lengthBeats) - right.startBeat
        guard overlapBeats > 0.000_001 else { return nil }
        let seconds = overlapBeats * 60 / bpm
        left.fadeOutSeconds = seconds
        right.fadeInSeconds = seconds
        left.fadeCurve = curve
        right.fadeCurve = curve
        return first.startBeat <= second.startBeat ? (left, right) : (right, left)
    }
}

struct LYFrozenTrackState: Codable, Equatable {
    var kind: LYTrackKind
    var clips: [LYClip]
    var inserts: [LYPluginSlot]
    var instrumentPlugin: LYPluginSlot?
    var fx: LYFXRack?
    var synth: LYSynthPatch?
    var synthPresetID: String?
    var drumPresetID: String?
    var customDrumPreset: DrumSynthPreset?
    var samplePath: String?
    var automation: [LYAutomationLane]?
}

struct LYTrackFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID]
    var isCollapsed = false
    var accent: LYAccent = .indigo
}

struct LYMixGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID]
    var volumeOffsetDB: Double = 0
    var isMuted = false
    var isSolo = false
}

struct LYTrack: Codable, Identifiable, Equatable {
    var isArmed: Bool {
        get { isRecordArmed ?? false }
        set { isRecordArmed = newValue }
    }

    var id = UUID()
    /// Stable graph address for this track. Unlike a track-array offset, this
    /// survives reorder, save/reopen and insertion of other track kinds.
    var engineChannelIndex: Int? = nil
    var name: String
    var kind: LYTrackKind
    var accent: LYAccent
    var volumeDB: Double = 0
    var pan: Double = 0
    var isMuted = false
    var isSolo = false
    /// Record arm. Optional preserves older documents.
    var isRecordArmed: Bool? = nil
    /// Zero-based hardware input for this audio track. Optional migrates to
    /// the session's legacy shared input selection.
    var audioInputChannel: Int? = nil
    var inputName: String?
    var isChordTrack: Bool? = nil
    var chordPresetID: String? = nil
    var synthPresetID: String? = nil
    var rootNote: Int? = nil
    var clips: [LYClip] = []
    var inserts: [LYPluginSlot] = []
    /// Third-party instrument source, separate from audio inserts so its node
    /// is restored at the beginning of the channel graph.
    var instrumentPlugin: LYPluginSlot? = nil
    /// NIGHTSHAPE effects on this channel. Optional preserves older documents.
    var fx: LYFXRack? = nil
    /// Set when this track plays LUNATK instead of a DrumKit synth preset.
    var synth: LYSynthPatch? = nil
    /// A drum track's DrumKit drum-synth preset. nil plays the default chosen
    /// from the track's name.
    var drumPresetID: String? = nil
    /// Post-fader sends into AUX RETURN tracks. Optional preserves older documents.
    var sends: [LYBusSend]? = nil
    /// The AUX RETURN this track plays through instead of MAIN. nil is MAIN.
    var outputBusID: UUID? = nil
    /// A drum-synth preset that is not in the built-in library (a DrumKit
    /// user preset brought in with a .fkit), played when `drumPresetID` names it.
    var customDrumPreset: DrumSynthPreset? = nil
    /// A one-shot sample this drum track plays, by its name in the song's
    /// audio. Takes over from any drum-synth preset.
    var samplePath: String? = nil
    /// DrumKit's choke group, 0 or nil for none.
    var chokeGroup: Int? = nil
    /// DrumKit's track-shaping ADSR. nil leaves the sound as it is.
    var envelope: TrackEnvelopeState? = nil
    /// Automation lanes, drawn under the track in SONG.
    var automation: [LYAutomationLane]? = nil
    /// Whether the lanes are open under the track.
    var showsAutomation: Bool? = nil
    /// Professional automation state; nil migrates as READ.
    var automationMode: LYAutomationMode? = nil
    /// Source/channel and optional external destination for this track.
    var midiRouting: LYMIDIRouting? = nil
    /// Present while a printed audio replacement is active. Unfreeze restores
    /// every original clip, instrument, plug-in, effect and automation lane.
    var frozenState: LYFrozenTrackState? = nil

    var isFrozen: Bool { frozenState != nil }
}

extension LYTrack {
    /// Clip indices of this track's patterns, in the sequencer's order:
    /// pattern and MIDI clips that carry their own steps.
    var patternIndices: [Int] {
        clips.indices.filter { clips[$0].isSequenced && !clips[$0].isPlacement }
    }

    var patterns: [LYClip] { patternIndices.map { clips[$0] } }

    /// Pattern regions that play in the song: placed patterns and placements.
    var songRegions: [LYClip] { clips.filter { $0.isSequenced && $0.isOffTimeline != true } }

    /// The clip whose steps a region plays: its source for a placement.
    func patternContent(of clip: LYClip) -> LYClip {
        guard let source = clip.patternSourceID, let found = clips.first(where: { $0.id == source }) else { return clip }
        return found
    }

    /// Index of the clip whose steps a region plays.
    func patternContentIndex(of clipIndex: Int) -> Int {
        guard let source = clips[clipIndex].patternSourceID,
              let found = clips.firstIndex(where: { $0.id == source }) else { return clipIndex }
        return found
    }
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
    static let currentSchemaVersion = 7

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
    var recordingSettings: LYRecordingSettings? = nil
    /// Sequencer swing, 0.5 straight … 0.75. Optional preserves older documents.
    var swing: Double? = nil
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
    /// DrumKit's song FX lane: filter sweeps and FRACTURE moves on a track
    /// or MAIN. Optional preserves older documents.
    var songFX: [LYSongFXBlock]? = nil
    /// Arrangement visibility and mix-link metadata live outside tracks so
    /// reordering tracks never breaks membership.
    var trackFolders: [LYTrackFolder]? = nil
    var mixGroups: [LYMixGroup]? = nil
    /// Set once the drum tracks have been put in their DRUMS folder, so a song
    /// whose drums were taken out of it is never regrouped.
    var drumsNested: Bool? = nil

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
        // The melodic starter tracks play LUNATK factory sounds.
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

        var session = LYLLTHSession(
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
        session.normalizeEngineChannelIndices()
        session.nestDrumTracksIfNeeded()
        return session
    }

    /// A new song: the starter's tracks and sounds with nothing programmed.
    /// One empty pattern per track, already in the song, so what gets
    /// programmed plays in SONG too.
    static func blank() -> LYLLTHSession {
        var session = starter()
        session.name = "UNTITLED"
        for t in session.tracks.indices {
            guard session.tracks[t].kind == .drumkit || session.tracks[t].kind == .instrument else { continue }
            guard var first = session.tracks[t].clips.first(where: \.isSequenced) else { continue }
            first.name = session.tracks[t].isChordTrack == true ? "CHORD BED 01" : "PATTERN 01"
            first.startBeat = 0
            first.steps = Array(repeating: false, count: first.steps?.count ?? 16)
            first.stepParameters = Array(repeating: .default, count: first.steps?.count ?? 16)
            session.tracks[t].clips = [first]
        }
        return session
    }

    /// Version 1's starter project auto-played one held chord root. Extending
    /// the pattern padded chord locks with `nil` (HOLD), so a 32-step pattern
    /// became 8/16 steps of rhythm followed by a lone sustained synth note.
    /// Repair only the recognizable untouched starter scaffold; user-created
    /// chord tracks and renamed/customized projects retain their state.
    func migratedToCurrentSchema() -> LYLLTHSession {
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

        // Version 4: songs from before LUNATK give their melodic starter
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

        // Version 5: graph identity belongs to the track, not its current row.
        // This is also run for newly-created current-version sessions so any
        // caller that appended a track without assigning a slot is repaired.
        migrated.normalizeEngineChannelIndices()

        if schemaVersion < 6, migrated.recordingSettings == nil {
            migrated.recordingSettings = LYRecordingSettings(preRollBars: migrated.countIn == false ? 0 : 1)
        }

        // Version 7: expression/routing and large-session organization. Keep
        // malformed external IDs or stale memberships from poisoning a song.
        let trackIDs = Set(migrated.tracks.map(\.id))
        for trackIndex in migrated.tracks.indices {
            if var routing = migrated.tracks[trackIndex].midiRouting {
                routing.normalize()
                migrated.tracks[trackIndex].midiRouting = routing
            }
            for clipIndex in migrated.tracks[trackIndex].clips.indices {
                guard var notes = migrated.tracks[trackIndex].clips[clipIndex].notes else { continue }
                for noteIndex in notes.indices {
                    notes[noteIndex].pitch = min(max(notes[noteIndex].pitch, 0), 127)
                    notes[noteIndex].velocity = min(max(notes[noteIndex].velocity, 1), 127)
                    notes[noteIndex].length = max(notes[noteIndex].length, 0.001)
                    if var expression = notes[noteIndex].expression {
                        for pointIndex in expression.indices {
                            expression[pointIndex].normalize(noteLength: notes[noteIndex].length)
                        }
                        expression.sort { ($0.offset, $0.kind.rawValue) < ($1.offset, $1.kind.rawValue) }
                        notes[noteIndex].expression = expression
                    }
                }
                migrated.tracks[trackIndex].clips[clipIndex].notes = notes
            }
        }
        migrated.trackFolders = migrated.trackFolders?.compactMap { folder in
            var cleaned = folder
            cleaned.trackIDs = folder.trackIDs.filter(trackIDs.contains)
            return cleaned.trackIDs.isEmpty ? nil : cleaned
        }
        migrated.mixGroups = migrated.mixGroups?.compactMap { group in
            var cleaned = group
            cleaned.trackIDs = group.trackIDs.filter(trackIDs.contains)
            cleaned.volumeOffsetDB = min(max(group.volumeOffsetDB, -60), 12)
            return cleaned.trackIDs.isEmpty ? nil : cleaned
        }

        migrated.nestDrumTracksIfNeeded()
        migrated.schemaVersion = Self.currentSchemaVersion
        return migrated
    }

    /// Preserves valid unique assignments and deterministically fills holes.
    /// Invalid/duplicate legacy values are repaired without moving any other
    /// track's established channel.
    mutating func normalizeEngineChannelIndices(limit: Int = 256) {
        var used = Set<Int>()
        for index in tracks.indices {
            guard let channel = tracks[index].engineChannelIndex,
                  (0..<limit).contains(channel),
                  used.insert(channel).inserted else {
                tracks[index].engineChannelIndex = nil
                continue
            }
        }
        var candidate = 0
        for index in tracks.indices where tracks[index].engineChannelIndex == nil {
            while used.contains(candidate) && candidate < limit { candidate += 1 }
            guard candidate < limit else { break }
            tracks[index].engineChannelIndex = candidate
            used.insert(candidate)
        }
    }

    mutating func assignEngineChannel(toTrackAt index: Int, limit: Int = 256) {
        guard tracks.indices.contains(index) else { return }
        let used = Set(tracks.enumerated().compactMap { offset, track in
            offset == index ? nil : track.engineChannelIndex
        })
        tracks[index].engineChannelIndex = (0..<limit).first { !used.contains($0) }
    }

    private static var nightshapeStarterChain: [LYPluginSlot] {
        [
            LYPluginSlot(format: .builtIn, identifier: "nightshape.equalizer", name: "EQUALIZER", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.compressor", name: "COMPRESSOR", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.decimator", name: "SONIC DECIMATOR", manufacturer: "NIGHTSHAPE")
        ]
    }
}

// MARK: - Patterns in the song

extension LYLLTHSession {
    func folder(containing trackID: UUID) -> LYTrackFolder? {
        trackFolders?.first { $0.trackIDs.contains(trackID) }
    }

    func groups(containing trackID: UUID) -> [LYMixGroup] {
        (mixGroups ?? []).filter { $0.trackIDs.contains(trackID) }
    }

    /// Drum tracks start nested in one collapsed DRUMS folder, so a kit takes
    /// one row in ARRANGE instead of one per sound. Only drum tracks in no
    /// other folder join it, and it happens once per song.
    mutating func nestDrumTracksIfNeeded() {
        guard drumsNested != true else { return }
        drumsNested = true
        let foldered = Set((trackFolders ?? []).flatMap(\.trackIDs))
        let drums = tracks.filter { $0.kind == .drumkit && !foldered.contains($0.id) }.map(\.id)
        guard drums.count > 1 else { return }
        var folders = trackFolders ?? []
        folders.append(LYTrackFolder(name: "DRUMS", trackIDs: drums, isCollapsed: true, accent: .teal))
        trackFolders = folders
    }

    /// The DRUMS folder, if the song has one.
    var drumFolderIndex: Int? {
        trackFolders?.firstIndex { folder in
            folder.name == "DRUMS" && folder.trackIDs.allSatisfy { id in tracks.first { $0.id == id }?.kind == .drumkit }
        }
    }

    mutating func createFolder(name: String, trackIDs: [UUID]) -> UUID? {
        let valid = Set(tracks.map(\.id))
        let members = trackIDs.filter(valid.contains)
        guard !members.isEmpty else { return nil }
        var folders = trackFolders ?? []
        for index in folders.indices { folders[index].trackIDs.removeAll { members.contains($0) } }
        folders.removeAll { $0.trackIDs.isEmpty }
        let folder = LYTrackFolder(name: name, trackIDs: members)
        folders.append(folder)
        trackFolders = folders
        return folder.id
    }

    mutating func createMixGroup(name: String, trackIDs: [UUID]) -> UUID? {
        let valid = Set(tracks.map(\.id))
        let members = trackIDs.filter(valid.contains)
        guard !members.isEmpty else { return nil }
        let group = LYMixGroup(name: name, trackIDs: members)
        var groups = mixGroups ?? []
        groups.append(group)
        mixGroups = groups
        return group.id
    }

    func effectiveVolumeDB(for track: LYTrack) -> Double {
        let offset = groups(containing: track.id).reduce(0) { $0 + $1.volumeOffsetDB }
        return min(max(track.volumeDB + offset, -96), 12)
    }

    private var sequencedTrackIndices: [Int] {
        tracks.indices.filter { tracks[$0].kind == .drumkit || tracks[$0].kind == .instrument }
    }

    private func patternClipIndex(trackIndex: Int, pattern: Int) -> Int? {
        let values = tracks[trackIndex].patternIndices
        guard !values.isEmpty else { return nil }
        return values[min(max(pattern, 0), values.count - 1)]
    }

    /// Whether pattern `index` plays anywhere in the song, on any track.
    func isPatternInSong(_ index: Int) -> Bool {
        sequencedTrackIndices.contains { trackIndex in
            guard let clipIndex = patternClipIndex(trackIndex: trackIndex, pattern: index) else { return false }
            let pattern = tracks[trackIndex].clips[clipIndex]
            return pattern.isOffTimeline != true
                || tracks[trackIndex].clips.contains { $0.patternSourceID == pattern.id && $0.isOffTimeline != true }
        }
    }

    /// Patterns have steps but none of them are in the song, so SONG plays
    /// nothing from the sequencer.
    var hasPatternsOutsideSong: Bool {
        let tracks = sequencedTrackIndices.map { self.tracks[$0] }
        return tracks.allSatisfy { $0.songRegions.isEmpty }
            && tracks.contains { $0.patterns.contains { ($0.steps ?? []).contains(true) } }
    }

    /// Places pattern `index` at the end of the song on every track.
    mutating func placePatternInSong(_ index: Int) {
        let beatsPerBar = max(1, Double(numerator) * 4 / Double(max(denominator, 1)))
        let end = tracks.flatMap(\.clips).filter(\.isInSong).map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let at = ceil(end / beatsPerBar - 0.000_1) * beatsPerBar
        for trackIndex in sequencedTrackIndices {
            guard let clipIndex = patternClipIndex(trackIndex: trackIndex, pattern: index) else { continue }
            let pattern = tracks[trackIndex].clips[clipIndex]
            if pattern.isOffTimeline == true,
               !tracks[trackIndex].clips.contains(where: { $0.patternSourceID == pattern.id }) {
                // First use: the pattern itself goes into the song.
                tracks[trackIndex].clips[clipIndex].isOffTimeline = nil
                tracks[trackIndex].clips[clipIndex].startBeat = at
            } else {
                var placement = pattern
                placement.id = UUID()
                placement.patternSourceID = pattern.id
                placement.steps = nil
                placement.stepParameters = nil
                placement.isOffTimeline = nil
                placement.startBeat = at
                placement.loopOffsetBeats = 0
                tracks[trackIndex].clips.append(placement)
            }
        }
    }
}
