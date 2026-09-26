import Combine
import Foundation
import NightshapeAudioEngine
import AVFoundation
import CryptoKit

/// DrumKit's two transport modes. PATTERN loops the pattern being edited;
/// SONG plays the arrangement, pattern regions and audio events together.
enum LYTransportMode: String {
    case pattern
    case song
}

@MainActor
final class AudioEngineController: ObservableObject {
    let engine: NightshapeAudioEngine = {
        LYChannelMap.configureEngine()
        return NightshapeAudioEngine.shared
    }()
    private lazy var notePlayer: LYNotePlayer = {
        let player = LYNotePlayer(engine: engine)
        player.instrument = { [weak self] id in self?.instruments[id] }
        return player
    }()
    private lazy var automationPlayer: LYAutomationPlayer = {
        let player = LYAutomationPlayer(engine: engine)
        player.instrument = { [weak self] id in self?.instruments[id] }
        player.songBeat = { [weak self] in self?.currentSongBeat() }
        return player
    }()
    private lazy var timeline: LYTimelineAudioPlayer = {
        let player = LYTimelineAudioPlayer(engine: engine)
        player.onRenderError = { [weak self] message in self?.audioEventError = message }
        return player
    }()

    /// Transport record enable. Capture is not built yet; this is the state
    /// the record path will read.
    @Published var isRecordEnabled = false
    @Published private(set) var transportMode: LYTransportMode = .song
    /// LUNATK instances by track, and which engine channel each is on.
    private var instruments: [UUID: LYSynthInstrument] = [:]
    private var instrumentOnChannel: [Int: UUID] = [:]
    /// Keeps every LUNATK told where the bar is while the transport runs.
    private var synthClock: Timer?
    /// What each engine channel's built-in synth was last set to, so an edit
    /// elsewhere does not re-apply it (which silences held notes).
    private var appliedSynth: [Int: (root: UInt8, preset: SynthPreset)] = [:]
    /// The drum preset each channel has loaded (or is loading).
    private var appliedDrum: [Int: String] = [:]

    // What the engine already has, so a sync only sends what changed. A mute
    // click should cost one engine call, not a full re-send of every pattern.
    private struct SentPattern: Equatable { var steps: [Bool]; var locks: [LYStepParameters] }
    private struct SentMix: Equatable { var volume: Double; var pan: Double; var muted: Bool }
    private struct SongInputs: Equatable {
        var tracks: [[LYClip]]
        var chord: [Bool]
        var chordPresets: [String?]
        var roots: [Int?]
        var key: SongKey
        var window: LYSongWindow
        var numerator: Int
        var denominator: Int
        var songFX: [LYSongFXBlock]
        var channels: [UUID]
    }
    private var sentPatterns: [Int: SentPattern] = [:]
    private var sentMix: [Int: SentMix] = [:]
    private var sentSong: SongInputs?
    private var sentRoutes: [Int: NightshapeAudioEngine.BusRoute]?
    private var sentSwing: Double?
    private struct SentShaping: Equatable { var choke: Int; var envelope: TrackEnvelopeState? }
    private var sentShaping: [Int: SentShaping] = [:]
    /// The song's audio, for drum tracks that play a sample from it.
    private var sampleAssets: [String: Data] = [:]
    private var sentTransport: (bpm: Double, numerator: Int, denominator: Int, length: Int, mode: LYTransportMode)?

    /// Drops every cache, for when the engine may have lost state.
    func invalidateEngineCaches() {
        sentPatterns = [:]
        sentMix = [:]
        sentSong = nil
        sentTransport = nil
        sentRoutes = nil
        sentSwing = nil
        sentShaping = [:]
        appliedSynth = [:]
        appliedDrum = [:]
    }
    /// The song window the transport cycles through while in SONG mode.
    @Published private(set) var songWindow = LYSongWindow(startBar: 0, barCount: 4, beatsPerBar: 4)

    @Published private(set) var isPlaying = false
    /// The playing step. Not published here: every view watching this
    /// controller would rebuild on each step. Views that follow the step
    /// watch `stepDisplay` instead.
    private(set) var currentStep = 0
    let stepDisplay = TransportDisplayState()
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
            .sink { [weak self] step in
                self?.currentStep = step
                self?.stepDisplay.update(step: step)
            }
            .store(in: &cancellables)
        engine.state.$timecodeText
            .removeDuplicates()
            .assign(to: &$timecode)
        engine.state.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self else { return }
                if playing { self.startSynthClock() } else { self.stopSynthClock() }
                if playing && self.transportMode == .song {
                    self.timeline.start()
                    self.notePlayer.start()
                    self.automationPlayer.start()
                } else {
                    self.timeline.stop()
                    self.notePlayer.stop()
                    self.automationPlayer.stop()
                }
            }
            .store(in: &cancellables)
    }

    /// Switches between looping the edited pattern and playing the song. A
    /// running transport keeps running; the next bar follows the new mode.
    func setTransportMode(_ mode: LYTransportMode, session: LYLLTHSession, assets: [String: Data]) {
        guard mode != transportMode else { return }
        transportMode = mode
        syncSequencer(session)
        syncTimeline(session, assets: assets)
        if isPlaying && mode == .song {
            timeline.start()
            notePlayer.start()
            automationPlayer.start()
        } else {
            timeline.stop()
            notePlayer.stop()
            automationPlayer.stop()
        }
    }

    /// Hands the arranged audio events to the timeline player. Cheap to call on
    /// every edit: renders are cached and only timing changes reschedule.
    func syncTimeline(_ session: LYLLTHSession, assets: [String: Data]) {
        if assets.keys != sampleAssets.keys {
            sampleAssets = assets
            // Sample drum tracks may have been waiting for their audio.
            if session.tracks.contains(where: { $0.samplePath != nil }) { syncSequencer(session) }
        }
        let meter = transportMeter(numerator: session.numerator, denominator: session.denominator)
        let window = LYSongWindow.resolve(for: session, stepsPerBar: meter.activeSubdivisionCount)
        if window != songWindow { songWindow = window }
        timeline.update(session: session, assets: assets, window: window)
        notePlayer.update(session: session, window: window)
        automationPlayer.update(session: session)
    }

    /// Step 0 of the running transport is a bar line: the song window's start
    /// in song mode, the pattern's start in pattern mode. Each LUNATK gets
    /// that anchor so its synced LFOs, arpeggiator and performers sit on the
    /// bar. Sent every 50 ms, which also covers a synth added mid-play and an
    /// epoch that moves when the meter or pattern length changes.
    private func startSynthClock() {
        guard synthClock == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendSynthTransport() }
        }
        RunLoop.main.add(timer, forMode: .common)
        synthClock = timer
        sendSynthTransport()
    }

    private func stopSynthClock() {
        synthClock?.invalidate()
        synthClock = nil
        for instrument in instruments.values { instrument.setTransport(playing: false, hostTime: 0, beat: 0) }
    }

    private func sendSynthTransport() {
        guard let anchor = engine.transportAnchor() else { return }
        let beat = transportMode == .song ? songWindow.startBeat : 0
        for instrument in instruments.values { instrument.setTransport(playing: true, hostTime: anchor.epochHostTime, beat: beat) }
    }

    /// The song beat being heard right now, for the arrangement playhead.
    func currentSongBeat() -> Double? {
        guard transportMode == .song, isPlaying else { return nil }
        if let beat = timeline.currentSongBeat() { return beat }
        guard let anchor = engine.transportAnchor() else { return nil }
        let now = mach_absolute_time()
        guard now >= anchor.epochHostTime else { return songWindow.startBeat }
        let beats = AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime) / anchor.stepDuration * lyBeatsPerStep
        return songWindow.startBeat + beats.truncatingRemainder(dividingBy: max(songWindow.lengthBeats, 0.25))
    }

    func prepare(_ session: LYLLTHSession) {
        if !engine.isReady {
            do {
                try engine.start()
                engine.setTrackMeteringEnabled(true)
                engine.setVisualRefreshRate(60)
                startupError = nil
            } catch {
                startupError = error.localizedDescription
            }
        }

        syncSequencer(session)
    }

    func updateTempo(_ bpm: Double) {
        engine.setBPM(bpm)
        sentTransport?.bpm = bpm
    }

    /// Mirrors the document's active desktop pattern into the shared realtime
    /// engine. Unlike the original starter path, this supports every musical
    /// track and the engine's full 64 stored steps.
    func syncSequencer(_ session: LYLLTHSession, patternIndex: Int? = nil) {
        guard engine.isReady else { return }
        LYChannelMap.ensureChannels(for: session, engine: engine)

        let selectedPattern = max(0, patternIndex ?? session.activePatternIndex ?? 0)
        let tracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        let clips = tracks.map { activeSequencedClip(in: $0, patternIndex: selectedPattern) }
        let stepCount = min(max(clips.compactMap { $0?.steps?.count }.max() ?? 16, 1), 64)
        let meter = transportMeter(numerator: session.numerator, denominator: session.denominator)

        let length = transportMode == .song ? meter.activeSubdivisionCount : stepCount
        let transport = (session.bpm, session.numerator, session.denominator, length, transportMode)
        let transportChanged = sentTransport.map { $0 != transport } ?? true
        if transportChanged {
            engine.setBPM(session.bpm)
            engine.setTransportMeter(meter)
            engine.setPatternLength(length)
            configureMetronome(meter: meter, stepCount: length)
            sentTransport = transport
        }
        if transportMode == .song {
            // Song frames are one bar each, so the pattern length becomes the bar.
            let stepsPerBar = meter.activeSubdivisionCount
            let window = LYSongWindow.resolve(for: session, stepsPerBar: stepsPerBar)
            if window != songWindow { songWindow = window }
            let key = session.songKey ?? .default
            let inputs = SongInputs(
                tracks: tracks.map { $0.clips.filter(\.isSequenced) },
                chord: tracks.map { $0.isChordTrack == true },
                chordPresets: tracks.map(\.chordPresetID),
                roots: tracks.map(\.rootNote),
                key: key,
                window: window,
                numerator: session.numerator,
                denominator: session.denominator,
                songFX: session.songFX ?? [],
                channels: LYChannelMap.channels(in: session).map(\.trackID)
            )
            if inputs != sentSong {
            sentSong = inputs
            engine.setSongArrangement(
                LYSongCompiler.frames(session: session, window: window, stepsPerBar: stepsPerBar) { track, clip in
                    let count = max(clip.steps?.count ?? 16, 1)
                    return self.renderedPattern(
                        track: track,
                        storedSteps: self.normalizedSteps(clip.steps, count: count),
                        locks: self.normalizedLocks(clip.stepParameters, count: count),
                        key: key,
                        meter: meter,
                        rootNote: track.rootNote ?? (track.kind == .drumkit ? 36 : 48)
                    )
                }
            )
            }
        } else if sentSong != nil || transportChanged {
            engine.setSongArrangement([])
            sentSong = nil
        }

        for (trackIndex, track) in tracks.enumerated() {
            let fallbackRoot = track.kind == .drumkit ? 36 : 48
            let rootNote = UInt8(clamping: track.rootNote ?? fallbackRoot)
            let preset = track.synthPresetID.flatMap(SynthPreset.init(rawValue:))
                ?? (track.kind == .drumkit ? .deepMono : .junoDream)
            if track.kind == .drumkit, let path = track.samplePath {
                loadSampleAsset(path, channel: trackIndex)
            } else if LYDrumSounds.presetID(for: track) != nil, let drum = LYDrumSounds.preset(for: track) {
                // A drum track plays its DrumKit drum-synth one-shot.
                loadDrum(drum, channel: trackIndex)
            } else {
                if appliedDrum[trackIndex] != nil { appliedDrum[trackIndex] = nil }
                if appliedSynth[trackIndex]?.root != rootNote || appliedSynth[trackIndex]?.preset != preset {
                    engine.setTrackSynth(trackIndex: trackIndex, rootNote: rootNote, preset: preset)
                    appliedSynth[trackIndex] = (rootNote, preset)
                }
            }
            syncInstrument(track: track, channel: trackIndex, bpm: session.bpm)
            syncShaping(track: track, channel: trackIndex)

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

            let pattern = SentPattern(steps: rendered.enabled, locks: rendered.locks)
            if sentPatterns[trackIndex] != pattern {
            sentPatterns[trackIndex] = pattern
            engine.setPattern(trackIndex: trackIndex, steps: rendered.enabled)
            engine.setFlamPattern(trackIndex: trackIndex, flams: rendered.locks.map { $0.flam == true })
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
            }
            let mix = SentMix(volume: track.volumeDB, pan: track.pan, muted: !LYChannelMap.isAudible(track, in: session))
            let previous = sentMix[trackIndex]
            if previous?.volume != mix.volume { engine.setTrackVolume(trackIndex: trackIndex, volume: min(pow(10, mix.volume / 20), 1)) }
            if previous?.pan != mix.pan { engine.setTrackPan(trackIndex: trackIndex, pan: mix.pan) }
            if previous?.muted != mix.muted { engine.setTrackMuted(trackIndex: trackIndex, muted: mix.muted) }
            sentMix[trackIndex] = mix
        }

        // Channels past the sequencer's play audio tracks and AUX RETURNs, or
        // sit muted. They get no pattern and no instrument.
        let byChannel = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.index, $0.trackID) })
        do {
            for trackIndex in min(tracks.count, engine.trackChannelCount)..<engine.trackChannelCount {
                let silent = SentPattern(steps: Array(repeating: false, count: stepCount), locks: [])
                if sentPatterns[trackIndex] != silent {
                    sentPatterns[trackIndex] = silent
                    engine.setPattern(trackIndex: trackIndex, steps: silent.steps)
                    engine.resetTrackStepState(trackIndex: trackIndex)
                }
                if instrumentOnChannel[trackIndex] != nil {
                    engine.setTrackInstrument(trackIndex: trackIndex, instrument: nil)
                    instrumentOnChannel[trackIndex] = nil
                }
                if sentShaping[trackIndex] != nil {
                    engine.setTrackChokeGroup(trackIndex: trackIndex, group: 0)
                    engine.setTrackEnvelope(trackIndex: trackIndex, attack: 0.001, decay: 0, sustain: 1, release: 0.001, bypassed: true)
                    sentShaping[trackIndex] = nil
                }
                if let id = byChannel[trackIndex], let track = session.tracks.first(where: { $0.id == id }) {
                    let mix = SentMix(volume: track.volumeDB, pan: track.pan, muted: !LYChannelMap.isAudible(track, in: session))
                    let previous = sentMix[trackIndex]
                    if previous?.volume != mix.volume { engine.setTrackVolume(trackIndex: trackIndex, volume: min(pow(10, mix.volume / 20), 3.98)) }
                    if previous?.pan != mix.pan { engine.setTrackPan(trackIndex: trackIndex, pan: mix.pan) }
                    if previous?.muted != mix.muted { engine.setTrackMuted(trackIndex: trackIndex, muted: mix.muted) }
                    sentMix[trackIndex] = mix
                } else if sentMix[trackIndex]?.muted != true {
                    engine.setTrackMuted(trackIndex: trackIndex, muted: true)
                    sentMix[trackIndex] = SentMix(volume: -96, pan: 0, muted: true)
                }
            }
        }

        let swing = min(max(session.swing ?? 0.5, 0.5), 0.75)
        if swing != sentSwing {
            engine.setSwing(swing)
            sentSwing = swing
        }

        let routes = LYChannelMap.routes(in: session)
        if routes != sentRoutes {
            engine.setBusRouting(routes)
            sentRoutes = routes
        }
    }

    // MARK: - Export

    /// The song as the sequencer plays it, one frame per bar of `window`,
    /// chord tracks compiled: what the MIDI export writes.
    func songFrames(_ session: LYLLTHSession, window: LYSongWindow) -> [SongPatternFrame] {
        let meter = transportMeter(numerator: session.numerator, denominator: session.denominator)
        let key = session.songKey ?? .default
        return LYSongCompiler.frames(session: session, window: window, stepsPerBar: meter.activeSubdivisionCount) { track, clip in
            let count = max(clip.steps?.count ?? 16, 1)
            return self.renderedPattern(
                track: track,
                storedSteps: self.normalizedSteps(clip.steps, count: count),
                locks: self.normalizedLocks(clip.stepParameters, count: count),
                key: key,
                meter: meter,
                rootNote: track.rootNote ?? (track.kind == .drumkit ? 36 : 48)
            )
        }
    }

    func exportWindow(_ session: LYLLTHSession) -> LYSongWindow {
        let meter = transportMeter(numerator: session.numerator, denominator: session.denominator)
        return LYSongWindow.resolve(for: session, stepsPerBar: meter.activeSubdivisionCount)
    }

    // MARK: - Drum sounds

    private func loadDrum(_ preset: DrumSynthPreset, channel: Int) {
        let key = preset.id
        guard appliedDrum[channel] != key else { return }
        appliedDrum[channel] = key
        appliedSynth[channel] = nil
        engine.clearTrackSynth(trackIndex: channel)
        Task { @MainActor in
            do {
                let url = try await LYDrumSounds.renderedFile(for: preset)
                // Another sound may have been chosen while this one rendered.
                guard appliedDrum[channel] == key else { return }
                try engine.loadSample(url: url, trackIndex: channel)
            } catch {
                audioEventError = "Could not load drum sound \(preset.name): \(error.localizedDescription)"
            }
        }
    }

    /// A drum track that plays a one-shot from the song's audio.
    private func loadSampleAsset(_ path: String, channel: Int) {
        let key = "sample:" + path
        guard appliedDrum[channel] != key, let data = sampleAssets[path] else { return }
        appliedDrum[channel] = key
        appliedSynth[channel] = nil
        engine.clearTrackSynth(trackIndex: channel)
        do {
            try engine.loadSample(url: LYSampleFiles.url(for: data, path: path), trackIndex: channel)
        } catch {
            audioEventError = "Could not load sample \(path): \(error.localizedDescription)"
        }
    }

    /// DrumKit's choke group and track envelope.
    private func syncShaping(track: LYTrack, channel: Int) {
        let shaping = SentShaping(choke: track.chokeGroup ?? 0, envelope: track.envelope)
        guard sentShaping[channel] != shaping else { return }
        sentShaping[channel] = shaping
        engine.setTrackChokeGroup(trackIndex: channel, group: shaping.choke)
        let envelope = track.envelope ?? TrackEnvelopeState()
        engine.setTrackEnvelope(
            trackIndex: channel,
            attack: envelope.attack,
            decay: envelope.decay,
            sustain: envelope.sustain,
            release: envelope.release,
            bypassed: track.envelope == nil || envelope.isBypassed
        )
    }

    func auditionDrum(_ preset: DrumSynthPreset) {
        Task { @MainActor in
            if let buffer = await LYDrumSounds.auditionBuffer(for: preset) { engine.audition(buffer) }
        }
    }

    // MARK: - LUNATK

    private func syncInstrument(track: LYTrack, channel: Int, bpm: Double) {
        guard let patch = track.synth else {
            if instrumentOnChannel[channel] != nil {
                engine.setTrackInstrument(trackIndex: channel, instrument: nil)
                instrumentOnChannel[channel] = nil
            }
            return
        }
        let instrument = instruments[track.id] ?? {
            let created = LYSynthInstrument()
            instruments[track.id] = created
            return created
        }()
        if instrument.patch != patch || instrument.bpm != bpm { instrument.apply(patch, bpm: bpm) }
        if instrumentOnChannel[channel] != track.id {
            engine.setTrackInstrument(trackIndex: channel, instrument: instrument)
            instrumentOnChannel[channel] = track.id
        }
    }

    func synthInstrument(for trackID: UUID) -> LYSynthInstrument? {
        instruments[trackID]
    }

    func togglePlayback() {
        guard engine.isReady else { return }
        engine.toggleTransport()
    }

    /// Stops the song without silencing what is still ringing, for the end
    /// of a bounce: synth releases and effect tails play out.
    func stopTransportKeepingTails() {
        engine.stopTransport()
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
        guard transportMode == .pattern else {
            configureMetronome(
                meter: transportMeter(numerator: session.numerator, denominator: session.denominator),
                stepCount: transportMeter(numerator: session.numerator, denominator: session.denominator).activeSubdivisionCount
            )
            return
        }
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
        let clips = track.patterns
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
            let url = try LYAudioSourceFileCache.url(for: data, fileExtension: fileExtension)
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

    /// Resamples a rendered event to the graph's fixed program format so every
    /// timeline player shares one connection format regardless of the source.
    static func convert(_ source: AVAudioPCMBuffer, to format: AVAudioFormat) async throws -> AVAudioPCMBuffer {
        if source.format.isEqual(format) { return source }
        return try await Task.detached(priority: .userInitiated) {
            guard let converter = AVAudioConverter(from: source.format, to: format) else {
                throw LYAudioEventRenderError.renderFailed
            }
            let capacity = AVAudioFrameCount(
                ceil(Double(source.frameLength) * format.sampleRate / source.format.sampleRate) + 64
            )
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw LYAudioEventRenderError.bufferAllocation
            }
            var provided = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if provided {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                provided = true
                inputStatus.pointee = .haveData
                return source
            }
            guard conversionError == nil, status != .error, output.frameLength > 0 else {
                throw LYAudioEventRenderError.renderFailed
            }
            return output
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

/// Project audio lives in the document as bytes; AVAudioFile needs a path.
/// Each distinct original is written once per launch and reused by every
/// render of every event cut from it.
enum LYAudioSourceFileCache {
    private static let lock = NSLock()
    private static var urls: [String: URL] = [:]

    static func url(for data: Data, fileExtension: String) throws -> URL {
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        lock.lock()
        defer { lock.unlock() }
        if let existing = urls[key], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LYLLTH-Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "audio" : fileExtension)
        try data.write(to: url, options: .atomic)
        urls[key] = url
        return url
    }
}
