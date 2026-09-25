import Combine
import Foundation
import NightshapeAudioEngine
import AVFoundation

@MainActor
final class AudioEngineController: ObservableObject {
    let engine = NightshapeAudioEngine.shared

    @Published private(set) var isPlaying = false
    @Published private(set) var currentStep = 0
    @Published private(set) var timecode = "00:00:00"
    @Published private(set) var startupError: String?
    @Published private(set) var isMetronomeEnabled = false
    @Published private(set) var audioEventError: String?
    @Published private(set) var isRenderingAudioEvent = false

    private var cancellables = Set<AnyCancellable>()
    init() {
        engine.state.$isPlaying
            .removeDuplicates()
            .assign(to: &$isPlaying)
        engine.state.$currentStep
            .removeDuplicates()
            .assign(to: &$currentStep)
        engine.state.$timecodeText
            .removeDuplicates()
            .assign(to: &$timecode)
    }

    func prepare(_ session: LYLLTHSession) {
        if !engine.isReady {
            do {
                try engine.start()
                startupError = nil
            } catch {
                startupError = error.localizedDescription
            }
        }

        syncSequencer(session)
    }

    func updateTempo(_ bpm: Double) {
        engine.setBPM(bpm)
    }

    /// Mirrors the document's active desktop pattern into the shared realtime
    /// engine. Unlike the original starter path, this supports every musical
    /// track and the engine's full 64 stored steps.
    func syncSequencer(_ session: LYLLTHSession, patternIndex: Int? = nil) {
        guard engine.isReady else { return }

        let selectedPattern = max(0, patternIndex ?? session.activePatternIndex ?? 0)
        let tracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        let clips = tracks.map { activeSequencedClip(in: $0, patternIndex: selectedPattern) }
        let stepCount = min(max(clips.compactMap { $0?.steps?.count }.max() ?? 16, 1), 64)
        let meter = transportMeter(numerator: session.numerator, denominator: session.denominator)
        let hasSolo = tracks.contains(where: \.isSolo)

        engine.setBPM(session.bpm)
        engine.setTransportMeter(meter)
        engine.setPatternLength(stepCount)
        configureMetronome(meter: meter, stepCount: stepCount)

        for (trackIndex, track) in tracks.prefix(16).enumerated() {
            let fallbackRoot = track.kind == .drumkit ? 36 : 48
            let rootNote = UInt8(clamping: track.rootNote ?? fallbackRoot)
            let preset = track.synthPresetID.flatMap(SynthPreset.init(rawValue:))
                ?? (track.kind == .drumkit ? .deepMono : .junoDream)
            engine.setTrackSynth(trackIndex: trackIndex, rootNote: rootNote, preset: preset)

            let clip = clips[trackIndex]
            let storedSteps = normalizedSteps(clip?.steps, count: stepCount)
            let locks = normalizedLocks(clip?.stepParameters, count: stepCount)
            let rendered = renderedPattern(
                track: track,
                storedSteps: storedSteps,
                locks: locks,
                key: session.songKey ?? .default,
                meter: meter,
                rootNote: Int(rootNote)
            )

            engine.setPattern(trackIndex: trackIndex, steps: rendered.enabled)
            engine.setStepParameters(
                trackIndex: trackIndex,
                velocities: rendered.locks.map { min(max($0.velocity, 0), 1) },
                volumes: rendered.locks.map { min(max($0.level, 0), 1) },
                cutoffs: rendered.locks.map { min(max($0.cutoff, 0), 1) },
                resonances: rendered.locks.map { min(max($0.resonance, 0), 1) },
                effects: rendered.locks.map { min(max($0.effect, 0), 1) },
                pans: rendered.locks.map { min(max($0.pan, -1), 1) },
                pitches: rendered.locks.map { Int($0.pitch.rounded()).clamped(to: -24...24) },
                noteLengths: rendered.locks.map { Int($0.noteLength.rounded()).clamped(to: 1...64) }
            )
            engine.setTrackVolume(trackIndex: trackIndex, volume: min(pow(10, track.volumeDB / 20), 1))
            engine.setTrackPan(trackIndex: trackIndex, pan: track.pan)
            engine.setTrackMuted(trackIndex: trackIndex, muted: track.isMuted || (hasSolo && !track.isSolo))
        }

        if tracks.count < 16 {
            for trackIndex in tracks.count..<16 {
                engine.setPattern(trackIndex: trackIndex, steps: Array(repeating: false, count: stepCount))
                engine.setTrackMuted(trackIndex: trackIndex, muted: true)
            }
        }
    }

    func togglePlayback() {
        guard engine.isReady else { return }
        engine.toggleTransport()
    }

    func stop() {
        engine.stopTransport()
        engine.stopAudition()
    }

    func previewAudioEvent(_ clip: LYClip, assetData: Data, projectBPM: Double) {
        guard clip.kind == .audio else { return }
        isRenderingAudioEvent = true
        audioEventError = nil
        Task {
            do {
                let buffer = try await LYAudioEventRenderer.render(
                    data: assetData,
                    fileExtension: URL(fileURLWithPath: clip.sourceRelativePath ?? "audio.wav").pathExtension,
                    clip: clip,
                    projectBPM: projectBPM
                )
                engine.audition(buffer)
                isRenderingAudioEvent = false
            } catch {
                audioEventError = error.localizedDescription
                isRenderingAudioEvent = false
            }
        }
    }

    func toggleMetronome(for session: LYLLTHSession) {
        isMetronomeEnabled.toggle()
        let tracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        let selectedPattern = max(0, session.activePatternIndex ?? 0)
        let stepCount = min(max(tracks.compactMap {
            activeSequencedClip(in: $0, patternIndex: selectedPattern)?.steps?.count
        }.max() ?? 16, 1), 64)
        configureMetronome(
            meter: transportMeter(numerator: session.numerator, denominator: session.denominator),
            stepCount: stepCount
        )
    }

    private func activeSequencedClip(in track: LYTrack, patternIndex: Int) -> LYClip? {
        let clips = track.clips.filter { $0.kind == .pattern || $0.kind == .midi }
        guard !clips.isEmpty else { return nil }
        return clips[min(patternIndex, clips.count - 1)]
    }

    private func normalizedSteps(_ values: [Bool]?, count: Int) -> [Bool] {
        (0..<count).map { index in
            guard let values, values.indices.contains(index) else { return false }
            return values[index]
        }
    }

    private func normalizedLocks(_ values: [LYStepParameters]?, count: Int) -> [LYStepParameters] {
        (0..<count).map { index in
            guard let values, values.indices.contains(index) else { return .default }
            return values[index]
        }
    }

    private func renderedPattern(
        track: LYTrack,
        storedSteps: [Bool],
        locks: [LYStepParameters],
        key: SongKey,
        meter: TransportMeter,
        rootNote: Int
    ) -> (enabled: [Bool], locks: [LYStepParameters]) {
        guard track.isChordTrack == true else { return (storedSteps, locks) }

        let preset = ChordSynthPreset.preset(id: track.chordPresetID) ?? ChordSynthPreset.all[0]
        let notes = ChordLaneCompiler.compile(
            markers: locks.map(\.chord),
            key: key,
            pattern: preset.pattern,
            stepsPerBar: meter.activeSubdivisionCount,
            rootNote: rootNote,
            pitchRange: -24...24,
            rootRange: 36...60
        )
        var compiledLocks = locks
        for index in notes.indices {
            guard let note = notes[index] else { continue }
            compiledLocks[index].pitch = Double(note.pitch)
            compiledLocks[index].velocity = Double(note.velocity)
            compiledLocks[index].noteLength = Double(note.length)
        }
        return (notes.map { $0 != nil }, compiledLocks)
    }

    private func transportMeter(numerator: Int, denominator: Int) -> TransportMeter {
        switch (numerator, denominator) {
        case (3, 4): return .threeFour
        case (6, 8): return .sixEight
        default: return .fourFour
        }
    }

    private func configureMetronome(meter: TransportMeter, stepCount: Int) {
        let pulseInterval = max(1, meter.activeSubdivisionCount / max(meter.bpmPulsesPerBar, 1))
        let beatSteps = (0..<stepCount).filter { step in
            (step % meter.activeSubdivisionCount) % pulseInterval == 0
        }
        engine.setTransportMetronome(enabled: isMetronomeEnabled, beatSteps: beatSteps)
    }
}

enum LYAudioEventRenderError: LocalizedError {
    case missingFrames
    case bufferAllocation
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .missingFrames: return "This audio event does not contain a playable source range."
        case .bufferAllocation: return "LYLLTH could not allocate the audio-event render buffer."
        case .renderFailed: return "LYLLTH could not render this audio event."
        }
    }
}

enum LYAudioEventRenderer {
    private struct Span {
        var sourceStart: Double
        var sourceDuration: Double
        var targetDuration: Double
    }

    static func render(
        data: Data,
        fileExtension: String,
        clip: LYClip,
        projectBPM: Double
    ) async throws -> AVAudioPCMBuffer {
        try await Task.detached(priority: .userInitiated) {
            let ext = fileExtension.isEmpty ? "audio" : fileExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lyllth-event-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            let file = try AVAudioFile(forReading: url)
            let sourceDuration = Double(file.length) / file.processingFormat.sampleRate
            let start = min(max(0, clip.sourceStartSeconds + clip.slipOffsetSeconds), sourceDuration)
            let requestedDuration = clip.sourceDurationSeconds ?? (sourceDuration - start)
            let duration = min(max(0, requestedDuration), max(0, sourceDuration - start))
            guard duration > 0.000_1 else { throw LYAudioEventRenderError.missingFrames }

            let spans = renderSpans(
                clip: clip,
                sourceStart: start,
                sourceDuration: duration,
                projectBPM: projectBPM
            )
            let rendered = try spans.map { span in
                try renderSpan(
                    fileURL: url,
                    sourceStart: span.sourceStart,
                    sourceDuration: span.sourceDuration,
                    targetDuration: span.targetDuration,
                    pitchSemitones: clip.pitchSemitones
                )
            }
            return try stitch(
                rendered,
                gainDB: clip.isMuted ? -60 : clip.eventGainDB,
                fadeInSeconds: clip.fadeInSeconds,
                fadeOutSeconds: clip.fadeOutSeconds
            )
        }.value
    }

    private static func renderSpans(
        clip: LYClip,
        sourceStart: Double,
        sourceDuration: Double,
        projectBPM: Double
    ) -> [Span] {
        let sourceEnd = sourceStart + sourceDuration
        if clip.stretchMode == .beatMapped, let map = clip.beatMap, projectBPM > 0 {
            let allAnchors = LYBeatMapPlanner.anchors(for: map, targetBPM: projectBPM)
            let boundaryStart = LYBeatMapPlanner.timelineTime(
                forSourceTime: sourceStart,
                map: map,
                targetBPM: projectBPM
            )
            let boundaryEnd = LYBeatMapPlanner.timelineTime(
                forSourceTime: sourceEnd,
                map: map,
                targetBPM: projectBPM
            )
            var anchors = [LYBeatMapAnchor(sourceTime: sourceStart, timelineTime: boundaryStart)]
            anchors += allAnchors.filter { $0.sourceTime > sourceStart && $0.sourceTime < sourceEnd }
            anchors.append(LYBeatMapAnchor(sourceTime: sourceEnd, timelineTime: boundaryEnd))
            let spans = zip(anchors, anchors.dropFirst()).compactMap { lower, upper -> Span? in
                let source = upper.sourceTime - lower.sourceTime
                let target = upper.timelineTime - lower.timelineTime
                guard source > 0.002, target > 0.002 else { return nil }
                return Span(sourceStart: lower.sourceTime, sourceDuration: source, targetDuration: target)
            }
            if !spans.isEmpty { return spans }
        }

        let rate: Double
        if clip.stretchMode == .tempo, let sourceBPM = clip.sourceBPM, sourceBPM > 0, projectBPM > 0 {
            rate = projectBPM / sourceBPM
        } else {
            rate = 1
        }
        return [
            Span(
                sourceStart: sourceStart,
                sourceDuration: sourceDuration,
                targetDuration: sourceDuration / max(0.031_25, rate)
            )
        ]
    }

    private static func renderSpan(
        fileURL: URL,
        sourceStart: Double,
        sourceDuration: Double,
        targetDuration: Double,
        pitchSemitones: Double
    ) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: fileURL)
        let sourceFormat = file.processingFormat
        // Apple's time/pitch Audio Unit is consistently available as stereo in
        // offline manual rendering. Mono sources are upmixed by AVAudioEngine.
        let channelCount: AVAudioChannelCount = 2
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceFormat.sampleRate,
            channels: channelCount
        ) else { throw LYAudioEventRenderError.bufferAllocation }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        timePitch.pitch = Float(min(max(pitchSemitones * 100, -4_800), 4_800))
        timePitch.rate = Float(min(max(sourceDuration / max(targetDuration, 0.001), 0.031_25), 32))

        let maximumFrames: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: maximumFrames)
        let startFrame = AVAudioFramePosition(sourceStart * sourceFormat.sampleRate)
        let sourceFrameCount = AVAudioFrameCount(
            min(
                Double(AVAudioFrameCount.max),
                max(1, sourceDuration * sourceFormat.sampleRate)
            )
        )
        let targetFrameCount = AVAudioFrameCount(
            min(
                Double(AVAudioFrameCount.max),
                max(1, targetDuration * outputFormat.sampleRate)
            )
        )
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: targetFrameCount),
              let scratch = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: maximumFrames) else {
            throw LYAudioEventRenderError.bufferAllocation
        }
        output.frameLength = targetFrameCount
        for channel in 0..<Int(outputFormat.channelCount) {
            output.floatChannelData?[channel].initialize(repeating: 0, count: Int(targetFrameCount))
        }

        player.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: sourceFrameCount,
            at: nil,
            completionHandler: nil
        )
        engine.prepare()
        try engine.start()
        player.play()
        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        var written: AVAudioFrameCount = 0
        while written < targetFrameCount {
            let request = min(maximumFrames, targetFrameCount - written)
            let status = try engine.renderOffline(request, to: scratch)
            switch status {
            case .success:
                guard let destination = output.floatChannelData,
                      let source = scratch.floatChannelData else {
                    throw LYAudioEventRenderError.renderFailed
                }
                let count = Int(scratch.frameLength)
                for channel in 0..<Int(outputFormat.channelCount) {
                    destination[channel].advanced(by: Int(written)).update(from: source[channel], count: count)
                }
                written += scratch.frameLength
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw LYAudioEventRenderError.renderFailed
            @unknown default:
                throw LYAudioEventRenderError.renderFailed
            }
        }
        return output
    }

    private static func stitch(
        _ buffers: [AVAudioPCMBuffer],
        gainDB: Double,
        fadeInSeconds: Double,
        fadeOutSeconds: Double
    ) throws -> AVAudioPCMBuffer {
        guard let format = buffers.first?.format, !buffers.isEmpty else {
            throw LYAudioEventRenderError.missingFrames
        }
        let joinFrames = min(
            AVAudioFrameCount(format.sampleRate * 0.0012),
            buffers.map(\.frameLength).min() ?? 0
        )
        let total = buffers.enumerated().reduce(AVAudioFrameCount(0)) { result, entry in
            result + entry.element.frameLength - (entry.offset == 0 ? 0 : joinFrames)
        }
        guard total > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let destination = output.floatChannelData else {
            throw LYAudioEventRenderError.bufferAllocation
        }
        output.frameLength = total
        for channel in 0..<Int(format.channelCount) {
            destination[channel].initialize(repeating: 0, count: Int(total))
        }

        var cursor = 0
        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let source = buffer.floatChannelData else { continue }
            if bufferIndex > 0 { cursor -= Int(joinFrames) }
            for channel in 0..<min(Int(format.channelCount), Int(buffer.format.channelCount)) {
                for frame in 0..<Int(buffer.frameLength) where cursor + frame < Int(total) {
                    var joinGain: Float = 1
                    if bufferIndex > 0, frame < Int(joinFrames) {
                        joinGain *= Float(frame) / Float(max(Int(joinFrames), 1))
                    }
                    if bufferIndex < buffers.count - 1,
                       Int(buffer.frameLength) - frame <= Int(joinFrames) {
                        joinGain *= Float(Int(buffer.frameLength) - frame) / Float(max(Int(joinFrames), 1))
                    }
                    destination[channel][cursor + frame] += source[channel][frame] * joinGain
                }
            }
            cursor += Int(buffer.frameLength)
        }

        let eventGain = gainDB <= -59.95 ? 0 : Float(pow(10, gainDB / 20))
        let fadeInFrames = min(Int(total), Int(fadeInSeconds * format.sampleRate))
        let fadeOutFrames = min(Int(total), Int(fadeOutSeconds * format.sampleRate))
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(total) {
                var gain = eventGain
                if fadeInFrames > 0, frame < fadeInFrames {
                    gain *= Float(frame) / Float(fadeInFrames)
                }
                if fadeOutFrames > 0, Int(total) - frame <= fadeOutFrames {
                    gain *= Float(Int(total) - frame) / Float(fadeOutFrames)
                }
                destination[channel][frame] *= gain
            }
        }
        return output
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
