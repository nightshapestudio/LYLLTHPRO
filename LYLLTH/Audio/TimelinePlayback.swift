import AVFoundation
import Foundation
import NightshapeAudioEngine

// MARK: - Timing

/// One sequencer step is always a sixteenth: a quarter of a timeline beat.
let lyBeatsPerStep = 0.25

enum LYAudioEventTiming {
    /// How many timeline beats one pass through an event's source region lasts
    /// at the project tempo. An event longer than this repeats its source,
    /// which is how ACID turns a one-bar loop into eight bars by dragging.
    static func cycleBeats(for clip: LYClip, projectBPM: Double) -> Double? {
        guard clip.kind == .audio,
              let duration = clip.sourceDurationSeconds,
              duration > 0.000_1,
              projectBPM > 0 else { return nil }
        let seconds: Double
        if clip.stretchMode == .beatMapped, let map = clip.beatMap {
            let start = max(0, clip.sourceStartSeconds + clip.slipOffsetSeconds)
            let end = start + duration
            seconds = LYBeatMapPlanner.timelineTime(forSourceTime: end, map: map, targetBPM: projectBPM)
                - LYBeatMapPlanner.timelineTime(forSourceTime: start, map: map, targetBPM: projectBPM)
        } else if clip.stretchMode == .tempo, let sourceBPM = clip.sourceBPM, sourceBPM > 0 {
            seconds = duration * sourceBPM / projectBPM
        } else {
            seconds = duration
        }
        guard seconds.isFinite, seconds > 0.000_1 else { return nil }
        return seconds * projectBPM / 60
    }
}

// MARK: - Song compilation

/// The window of the arrangement the transport cycles through: the loop brace
/// when LOOP is on, otherwise everything up to the end of the last event.
struct LYSongWindow: Equatable {
    var startBar: Int
    var barCount: Int
    var beatsPerBar: Double

    var startBeat: Double { Double(startBar) * beatsPerBar }
    var lengthBeats: Double { Double(barCount) * beatsPerBar }
    var endBeat: Double { startBeat + lengthBeats }

    static func resolve(for session: LYLLTHSession, stepsPerBar: Int) -> LYSongWindow {
        let beatsPerBar = Double(max(stepsPerBar, 1)) * lyBeatsPerStep
        if session.isLoopActive, let loop = session.loopRange, loop.lengthBeats > 0 {
            let first = Int(floor(loop.startBeat / beatsPerBar + 0.000_1))
            let last = Int(ceil((loop.startBeat + loop.lengthBeats) / beatsPerBar - 0.000_1))
            return LYSongWindow(startBar: max(0, first), barCount: max(1, last - first), beatsPerBar: beatsPerBar)
        }
        let end = session.tracks
            .flatMap(\.clips)
            .filter(\.isInSong)
            .map { $0.startBeat + $0.lengthBeats }
            .max() ?? beatsPerBar
        return LYSongWindow(
            startBar: 0,
            barCount: max(1, Int(ceil(end / beatsPerBar - 0.000_1))),
            beatsPerBar: beatsPerBar
        )
    }
}

enum LYSongCompiler {
    /// Turns the pattern regions on every musical track into the engine's
    /// per-bar frames. A region longer than its pattern repeats the pattern,
    /// and a bar with no region on a track is silent for that track.
    static func frames(
        session: LYLLTHSession,
        window: LYSongWindow,
        stepsPerBar: Int,
        render: (LYTrack, LYClip) -> (enabled: [Bool], locks: [LYStepParameters])
    ) -> [SongPatternFrame] {
        let tracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        var renderedByClip: [UUID: (enabled: [Bool], locks: [LYStepParameters])] = [:]
        for track in tracks {
            for clip in track.patterns {
                renderedByClip[clip.id] = render(track, clip)
            }
        }

        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        return (0..<window.barCount).map { barOffset in
            let barStart = Double(window.startBar + barOffset) * window.beatsPerBar
            let songTracks: [SongPatternTrack] = tracks.map { track in
                var active = Array(repeating: false, count: stepsPerBar)
                var locks = Array(repeating: LYStepParameters.default, count: stepsPerBar)
                let regions = track.songRegions
                for step in 0..<stepsPerBar {
                    let beat = barStart + Double(step) * lyBeatsPerStep
                    // Regions that overlap (a DrumKit song's lanes) sound
                    // together; the last one that hits sets the step's values.
                    var sawRegion = false
                    for clip in regions where beat >= clip.startBeat - 0.000_1 && beat < clip.startBeat + clip.lengthBeats - 0.000_1 {
                        guard let rendered = renderedByClip[clip.patternSourceID ?? clip.id], !rendered.enabled.isEmpty else { continue }
                        let offset = Int(floor((beat - clip.startBeat + clip.loopOffsetBeats) / lyBeatsPerStep + 0.000_1))
                        let index = ((offset % rendered.enabled.count) + rendered.enabled.count) % rendered.enabled.count
                        if rendered.enabled[index] || !sawRegion {
                            if rendered.locks.indices.contains(index) { locks[step] = rendered.locks[index] }
                        }
                        active[step] = active[step] || rendered.enabled[index]
                        sawRegion = true
                    }
                }
                return SongPatternTrack(
                    activeSteps: active,
                    flamSteps: locks.map { $0.flam == true },
                    velocities: locks.map { min(max($0.velocity, 0), 1) },
                    volumes: locks.map { min(max($0.level, 0), 1) },
                    cutoffs: locks.map { min(max($0.cutoff, 0), 1) },
                    resonances: locks.map { min(max($0.resonance, 0), 1) },
                    effects: locks.map { min(max($0.effect, 0), 1) },
                    pans: locks.map { min(max($0.pan, -1), 1) },
                    pitches: locks.map { min(max(Int($0.pitch.rounded()), -24), 24) },
                    noteLengths: locks.map { min(max(Int($0.noteLength.rounded()), 1), 64) }
                )
            }
            let fx = LYSongFXCompiler.lanes(session.songFX ?? [], barStartBeat: barStart, stepsPerBar: stepsPerBar, channels: channels)
            return SongPatternFrame(stepCount: stepsPerBar, tracks: songTracks, filterLanes: fx.filter, fractureLanes: fx.fracture)
        }
    }
}

// MARK: - Audio events on the transport

/// A stretch of one audio event inside one pass of the song window.
private struct LYEventSegment {
    var clipID: UUID
    var renderKey: String
    /// Beats from the start of the window pass.
    var windowOffsetBeats: Double
    var lengthBeats: Double
    /// Beats into the source cycle where this segment begins.
    var cycleOffsetBeats: Double
    var fadeInBeats: Double
    var fadeOutBeats: Double
}

/// Plays arranged audio events in time with the NIGHTSHAPE transport.
///
/// Each event is rendered once per pass through its source (stretch, beat map
/// and pitch applied) and cached. Scheduling repeats that one cycle for as
/// long as the event runs, so a long loop costs no more memory than one pass.
/// Gain, pan, mute and solo are node mix properties and change live without
/// a re-render.
@MainActor
final class LYTimelineAudioPlayer {
    static let programFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private let engine: NightshapeAudioEngine
    private var nodes: [UUID: AVAudioPlayerNode] = [:]
    private var cycles: [String: AVAudioPCMBuffer] = [:]
    private var rendering: Set<String> = []
    private var failed: Set<String> = []

    private var session: LYLLTHSession?
    private var assets: [String: Data] = [:]
    private var window: LYSongWindow?
    private var segments: [LYEventSegment] = []
    /// The engine channel each player feeds; nil is the program mix.
    private var nodeChannels: [UUID: Int?] = [:]

    private var anchor: NightshapeAudioEngine.TransportAnchor?
    /// Transport beats (since the anchor's epoch) already handed to players.
    private var scheduledThroughBeat = 0.0
    private var needsResync = true
    private var ticker: Timer?
    private static let horizonSeconds = 0.9

    var onRenderError: ((String) -> Void)?

    init(engine: NightshapeAudioEngine) {
        self.engine = engine
    }

    // MARK: Model

    func update(session: LYLLTHSession, assets: [String: Data], window: LYSongWindow) {
        LYChannelMap.ensureChannels(for: session, engine: engine)
        let structureChanged = self.window != window || Self.structure(of: session) != Self.structure(of: self.session)
        self.session = session
        self.assets = assets
        self.window = window
        rebuildSegments()
        routeNodes()
        applyMix()
        prerender()
        if structureChanged { needsResync = true }
    }

    // MARK: Transport

    func start() {
        guard ticker == nil else { return }
        needsResync = true
        anchor = nil
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        anchor = nil
        for node in nodes.values { node.stop() }
    }

    /// The window-relative song beat heard now, or nil while stopped.
    func currentSongBeat() -> Double? {
        guard let anchor, let window, anchor.stepDuration > 0 else { return nil }
        let now = mach_absolute_time()
        guard now >= anchor.epochHostTime else { return window.startBeat }
        let transportBeat = AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime)
            / anchor.stepDuration * lyBeatsPerStep
        return window.startBeat + transportBeat.truncatingRemainder(dividingBy: window.lengthBeats)
    }

    private func tick() {
        guard let latest = engine.transportAnchor() else { return }
        if latest != anchor {
            anchor = latest
            needsResync = true
        }
        if needsResync { resync(anchor: latest) }
        schedule(anchor: latest, includeTails: false)
    }

    private func resync(anchor: NightshapeAudioEngine.TransportAnchor) {
        needsResync = false
        for node in nodes.values { node.stop() }
        let now = mach_absolute_time()
        let elapsed = now > anchor.epochHostTime
            ? AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime)
            : 0
        // A few milliseconds of lead so the first rescheduled buffer is not late.
        scheduledThroughBeat = (elapsed + 0.02) / anchor.stepDuration * lyBeatsPerStep
        schedule(anchor: anchor, includeTails: true)
    }

    private func schedule(anchor: NightshapeAudioEngine.TransportAnchor, includeTails: Bool) {
        guard let window, window.lengthBeats > 0, !segments.isEmpty else { return }
        let secondsPerBeat = anchor.stepDuration / lyBeatsPerStep
        let now = mach_absolute_time()
        let elapsed = now > anchor.epochHostTime ? AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime) : 0
        let horizonBeat = (elapsed + Self.horizonSeconds) / secondsPerBeat
        guard horizonBeat > scheduledThroughBeat else { return }

        let from = scheduledThroughBeat
        let firstPass = Int(floor(from / window.lengthBeats))
        let lastPass = Int(floor(horizonBeat / window.lengthBeats))
        for pass in firstPass...lastPass {
            let passStart = Double(pass) * window.lengthBeats
            for segment in segments {
                let start = passStart + segment.windowOffsetBeats
                let end = start + segment.lengthBeats
                if start >= from && start < horizonBeat {
                    play(segment, skipBeats: 0, atTransportBeat: start, anchor: anchor, secondsPerBeat: secondsPerBeat)
                } else if includeTails && pass == firstPass && start < from && end > from + 0.01 {
                    play(segment, skipBeats: from - start, atTransportBeat: from, anchor: anchor, secondsPerBeat: secondsPerBeat)
                }
            }
        }
        scheduledThroughBeat = horizonBeat
    }

    private func play(
        _ segment: LYEventSegment,
        skipBeats: Double,
        atTransportBeat beat: Double,
        anchor: NightshapeAudioEngine.TransportAnchor,
        secondsPerBeat: Double
    ) {
        guard let cycle = cycles[segment.renderKey], let node = node(for: segment.clipID) else { return }
        let rate = cycle.format.sampleRate
        let startFrame = Int(((segment.cycleOffsetBeats + skipBeats) * secondsPerBeat * rate).rounded())
        let frameCount = Int(((segment.lengthBeats - skipBeats) * secondsPerBeat * rate).rounded())
        guard frameCount > 32,
              let buffer = Self.slice(
                cycle,
                from: startFrame,
                count: frameCount,
                fadeInFrames: skipBeats > 0 ? 0 : Int(segment.fadeInBeats * secondsPerBeat * rate),
                fadeOutFrames: Int(segment.fadeOutBeats * secondsPerBeat * rate)
              ) else { return }
        let host = anchor.epochHostTime + AVAudioTime.hostTime(forSeconds: beat * secondsPerBeat)
        node.scheduleBuffer(buffer, at: AVAudioTime(hostTime: host), options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    private func node(for clipID: UUID) -> AVAudioPlayerNode? {
        if let existing = nodes[clipID] { return existing }
        guard engine.isReady else { return nil }
        let node = AVAudioPlayerNode()
        let channel = session.flatMap { session in
            session.tracks.first { $0.clips.contains { $0.id == clipID } }
                .flatMap { LYFXBridge.engineIndex(for: $0.id, in: session) }
        }
        engine.routeTimelineSource(node, format: Self.programFormat, trackIndex: channel)
        nodeChannels[clipID] = channel
        nodes[clipID] = node
        applyMix()
        return node
    }

    /// Moves players whose track changed channel (tracks added, removed or
    /// reordered) onto the new one.
    private func routeNodes() {
        guard let session else { return }
        for track in session.tracks where track.kind == .audio {
            let channel = LYFXBridge.engineIndex(for: track.id, in: session)
            for clip in track.clips {
                guard let node = nodes[clip.id], nodeChannels[clip.id] != channel else { continue }
                engine.routeTimelineSource(node, format: Self.programFormat, trackIndex: channel)
                nodeChannels[clip.id] = channel
            }
        }
    }

    // MARK: Segments and mix

    private func rebuildSegments() {
        guard let session, let window else { segments = []; return }
        var result: [LYEventSegment] = []
        for track in session.tracks where track.kind == .audio {
            for clip in track.clips where clip.kind == .audio && clip.sourceRelativePath != nil {
                guard let cycle = LYAudioEventTiming.cycleBeats(for: clip, projectBPM: session.bpm),
                      cycle > 0.01 else { continue }
                let clipEnd = clip.startBeat + clip.lengthBeats
                let visibleStart = max(clip.startBeat, window.startBeat)
                let visibleEnd = min(clipEnd, window.endBeat)
                guard visibleEnd > visibleStart + 0.001 else { continue }

                // Walk the event one source cycle at a time, clipped to the window.
                var cursor = visibleStart
                while cursor < visibleEnd - 0.001 {
                    let intoEvent = cursor - clip.startBeat + clip.loopOffsetBeats
                    let intoCycle = intoEvent.truncatingRemainder(dividingBy: cycle)
                    let length = min(cycle - intoCycle, visibleEnd - cursor)
                    let isEventStart = abs(cursor - clip.startBeat) < 0.000_1
                    let isEventEnd = abs(cursor + length - clipEnd) < 0.000_1
                    let secondsPerBeat = 60 / max(session.bpm, 1)
                    result.append(
                        LYEventSegment(
                            clipID: clip.id,
                            renderKey: Self.renderKey(for: clip, bpm: session.bpm),
                            windowOffsetBeats: cursor - window.startBeat,
                            lengthBeats: length,
                            cycleOffsetBeats: intoCycle,
                            fadeInBeats: isEventStart ? min(length, clip.fadeInSeconds / secondsPerBeat) : 0,
                            fadeOutBeats: isEventEnd ? min(length, clip.fadeOutSeconds / secondsPerBeat) : 0
                        )
                    )
                    cursor += length
                }
            }
        }
        segments = result

        let live = Set(result.map(\.clipID))
        for (id, node) in nodes where !live.contains(id) {
            engine.detachTimelineSource(node)
            nodes[id] = nil
            nodeChannels[id] = nil
        }
    }

    /// Per-event gain on each player. A track on an engine channel gets its
    /// level, pan, mute and solo there; one without (past sixteen channels)
    /// gets them here.
    private func applyMix() {
        guard let session else { return }
        for track in session.tracks where track.kind == .audio {
            let onChannel = LYFXBridge.engineIndex(for: track.id, in: session) != nil
            let trackAudible = LYChannelMap.isAudible(track, in: session)
            let trackGain = Float(pow(10, track.volumeDB / 20))
            for clip in track.clips {
                guard let node = nodes[clip.id] else { continue }
                let eventGain: Float = clip.eventGainDB <= -59.95 ? 0 : Float(pow(10, clip.eventGainDB / 20))
                if onChannel {
                    node.volume = clip.isMuted ? 0 : eventGain
                    node.pan = 0
                } else {
                    node.volume = trackAudible && !clip.isMuted ? trackGain * eventGain : 0
                    node.pan = Float(min(max(track.pan, -1), 1))
                }
            }
        }
    }

    // MARK: Rendering

    private func prerender() {
        guard let session else { return }
        for track in session.tracks where track.kind == .audio {
            for clip in track.clips where clip.kind == .audio {
                guard let path = clip.sourceRelativePath, let data = assets[path] else { continue }
                let key = Self.renderKey(for: clip, bpm: session.bpm)
                guard cycles[key] == nil, !rendering.contains(key), !failed.contains(key) else { continue }
                rendering.insert(key)
                var cycleClip = clip
                cycleClip.eventGainDB = 0
                cycleClip.fadeInSeconds = 0
                cycleClip.fadeOutSeconds = 0
                cycleClip.isMuted = false
                let bpm = session.bpm
                Task {
                    do {
                        let rendered = try await LYAudioEventRenderer.render(
                            data: data,
                            fileExtension: URL(fileURLWithPath: path).pathExtension,
                            clip: cycleClip,
                            projectBPM: bpm
                        )
                        let converted = try await LYAudioEventRenderer.convert(rendered, to: Self.programFormat)
                        self.rendering.remove(key)
                        self.cycles[key] = converted
                        self.trimCache()
                        self.needsResync = true
                    } catch {
                        self.rendering.remove(key)
                        self.failed.insert(key)
                        self.onRenderError?(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Keeps only renders the current arrangement still refers to.
    private func trimCache() {
        guard let session else { return }
        let live = Set(session.tracks.flatMap(\.clips).filter { $0.kind == .audio }.map {
            Self.renderKey(for: $0, bpm: session.bpm)
        })
        for key in cycles.keys where !live.contains(key) { cycles[key] = nil }
    }

    private static func renderKey(for clip: LYClip, bpm: Double) -> String {
        [
            clip.sourceRelativePath ?? "",
            String(format: "%.5f", clip.sourceStartSeconds),
            String(format: "%.5f", clip.sourceDurationSeconds ?? -1),
            String(format: "%.5f", clip.slipOffsetSeconds),
            String(format: "%.3f", clip.pitchSemitones),
            clip.stretchMode.rawValue,
            String(format: "%.4f", clip.sourceBPM ?? 0),
            String(format: "%.4f", clip.stretchMode == .off ? 0 : bpm),
            String(clip.beatMap?.markers.count ?? 0)
        ].joined(separator: "|")
    }

    /// Only the parts of the session that move audio in time. Gain and mute
    /// edits skip this so dragging an event's volume line never re-schedules.
    private static func structure(of session: LYLLTHSession?) -> [String] {
        guard let session else { return [] }
        return session.tracks.flatMap(\.clips).filter { $0.kind == .audio }.map {
            "\($0.id)|\($0.startBeat)|\($0.lengthBeats)|\($0.loopOffsetBeats)|\($0.fadeInSeconds)|\($0.fadeOutSeconds)|"
                + renderKey(for: $0, bpm: session.bpm)
        } + ["\(session.bpm)"]
    }

    private static func slice(
        _ source: AVAudioPCMBuffer,
        from start: Int,
        count: Int,
        fadeInFrames: Int,
        fadeOutFrames: Int
    ) -> AVAudioPCMBuffer? {
        let available = Int(source.frameLength)
        let first = min(max(0, start), available)
        let frames = min(count, available - first)
        guard frames > 0,
              let output = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(frames)),
              let from = source.floatChannelData,
              let to = output.floatChannelData else { return nil }
        output.frameLength = AVAudioFrameCount(frames)
        let fadeIn = min(fadeInFrames, frames)
        let fadeOut = min(fadeOutFrames, frames)
        // A few samples of ramp on every cut so a slice starting mid-waveform
        // does not click. Two milliseconds is below what reads as a fade.
        let declick = min(88, frames / 4)
        for channel in 0..<Int(source.format.channelCount) {
            to[channel].update(from: from[channel].advanced(by: first), count: frames)
            for frame in 0..<max(fadeIn, declick) {
                to[channel][frame] *= Float(frame) / Float(max(fadeIn, declick))
            }
            for frame in 0..<max(fadeOut, declick) {
                to[channel][frames - 1 - frame] *= Float(frame) / Float(max(fadeOut, declick))
            }
        }
        return output
    }
}
