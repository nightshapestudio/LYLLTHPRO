import AVFoundation
import CryptoKit
import Foundation
import NightshapeAudioEngine

/// Faster-than-realtime export. The song goes through DrumKit's offline
/// renderer, the same channels, FX and reverb the live engine plays, driven
/// by a sample clock instead of the audio device. LYLLTH's own parts ride on
/// the renderer's host hooks:
/// - LUNATK tracks render their core in step with the render, steps and
///   piano-roll notes placed on exact frames;
/// - audio tracks stream their events from the same renders the timeline plays;
/// - AUX RETURNs, sends and outputs are the live routes;
/// - automation moves the channels and knobs block by block.
@MainActor
struct LYOfflineExport {
    let session: LYLLTHSession
    let window: LYSongWindow
    let sampleRate: Double
    let meter: TransportMeter
    let frames: [SongPatternFrame]
    /// Every track with an engine channel, by channel.
    let channels: [(track: LYTrack, index: Int)]

    private var sourceURLs: [Int: URL] = [:]
    private var synthSources: [Int: OfflineSynthSource] = [:]
    private var cycles: [String: AVAudioPCMBuffer] = [:]
    private let segments: [LYEventSegment]

    private var stepSeconds: Double { meter.stepDuration(atBPM: session.bpm) }
    private var secondsPerBeat: Double { stepSeconds / lyBeatsPerStep }
    private var musicalCount: Int { session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }.count }

    // MARK: Preparing

    /// Resolves every source once: drum sounds rendered, samples on disk,
    /// audio events rendered at the export rate. Stem passes reuse it.
    static func prepare(session: LYLLTHSession, assets: [String: Data], audio: AudioEngineController) async throws -> LYOfflineExport {
        let window = audio.exportWindow(session)
        var export = LYOfflineExport(
            session: session,
            window: window,
            sampleRate: [44_100.0, 48_000.0].contains(session.sampleRate) ? session.sampleRate : 48_000,
            meter: TransportMeter.preset(session.meterPreset),
            frames: audio.songFrames(session, window: window),
            channels: LYChannelMap.channels(in: session).compactMap { entry in
                session.tracks.first { $0.id == entry.trackID }.map { ($0, entry.index) }
            },
            segments: LYTimelineAudioPlayer.segments(session: session, window: window)
        )
        for (track, index) in export.channels where track.kind == .drumkit || track.kind == .instrument {
            guard track.synth == nil else { continue }
            // The same choice the live sequencer makes for the channel.
            if track.kind == .drumkit, let path = track.samplePath, let data = assets[path] {
                export.sourceURLs[index] = try LYSampleFiles.url(for: data, path: path)
            } else if LYDrumSounds.presetID(for: track) != nil, let drum = LYDrumSounds.preset(for: track) {
                export.sourceURLs[index] = try await LYDrumSounds.renderedFile(for: drum)
            } else {
                let preset = track.synthPresetID.flatMap(SynthPreset.init(rawValue:)) ?? (track.kind == .drumkit ? .deepMono : .junoDream)
                let root = UInt8(clamping: track.rootNote ?? (track.kind == .drumkit ? 36 : 48))
                if let parameters = audio.engine.synthPresetParameters(preset) {
                    export.synthSources[index] = OfflineSynthSource(rootNote: root, parameters: parameters)
                }
            }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: export.sampleRate, channels: 2)!
        for track in session.tracks where track.kind == .audio {
            for clip in track.clips where clip.kind == .audio {
                guard let path = clip.sourceRelativePath, let data = assets[path] else { continue }
                let key = LYTimelineAudioPlayer.renderKey(for: clip, bpm: session.bpm)
                guard export.cycles[key] == nil else { continue }
                var cycleClip = clip
                cycleClip.eventGainDB = 0
                cycleClip.fadeInSeconds = 0
                cycleClip.fadeOutSeconds = 0
                cycleClip.isMuted = false
                let rendered = try await LYAudioEventRenderer.render(
                    data: data, fileExtension: URL(fileURLWithPath: path).pathExtension, clip: cycleClip, projectBPM: session.bpm)
                export.cycles[key] = try await LYAudioEventRenderer.convert(rendered, to: format)
            }
        }
        return export
    }

    // MARK: Stems

    /// Channels that get a stem: every audible track that makes sound of its
    /// own. AUX RETURNs are heard inside the stems that feed them.
    var stemChannels: [(track: LYTrack, index: Int)] {
        channels.filter { track, index in
            guard track.kind != .auxiliary, LYChannelMap.isAudible(track, in: session) else { return false }
            if track.kind == .audio { return segments.contains { segment in track.clips.contains { $0.id == segment.clipID } } }
            let hasSteps = index < musicalCount && frames.contains { frame in
                frame.tracks.indices.contains(index) && frame.tracks[index].activeSteps.contains(true)
            }
            let hasNotes = track.clips.contains { !$0.songNotes(from: window.startBeat, to: window.endBeat).isEmpty }
            return hasSteps || hasNotes
        }
    }

    // MARK: Snapshot

    /// The render input. With `stem`, every other sounding track is muted;
    /// buses stay open so the stem carries its sends, and the stems sum back
    /// to the mix. Each call builds fresh LUNATK cores, so a snapshot renders
    /// once.
    func snapshot(stem: Int? = nil) -> OfflineProjectRenderSnapshot {
        let lunatk = Set(channels.filter { $0.track.synth != nil && $0.index < musicalCount }.map(\.index))
        let bars = frames.map { frame in
            OfflineRenderBar(
                tracks: frame.tracks.enumerated().map { index, track in
                    (0..<frame.stepCount).map { step in
                        OfflineRenderStep(
                            isEnabled: !lunatk.contains(index) && track.activeSteps.indices.contains(step) && track.activeSteps[step],
                            velocity: value(track.velocities, step, 0.82),
                            volume: value(track.volumes, step, 1),
                            cutoff: value(track.cutoffs, step, 1),
                            resonance: value(track.resonances, step, 0),
                            fx: value(track.effects, step, 0),
                            isFlam: track.flamSteps.indices.contains(step) && track.flamSteps[step],
                            pan: value(track.pans, step, 0),
                            pitchSemitones: track.pitches.indices.contains(step) ? track.pitches[step] : 0,
                            noteLengthSteps: track.noteLengths.indices.contains(step) ? track.noteLengths[step] : 1
                        )
                    }
                },
                stepCount: frame.stepCount,
                filterLanes: frame.filterLanes,
                fractureLanes: frame.fractureLanes
            )
        }

        let count = (channels.map(\.index).max() ?? -1) + 1
        var tracks: [OfflineRenderTrack] = (0..<count).map { _ in
            OfflineRenderTrack(sourceURL: nil, sourceIdentity: "empty", volume: 0, muted: true, insertOrder: [], eqBands: [], compressor: .init(),
                               decimator: .init(), chorus: .init(), voidGate: .init(), reverbSend: 0)
        }
        for (track, index) in channels {
            let audible = LYChannelMap.isAudible(track, in: session)
            let muted = !audible || (stem != nil && stem != index && track.kind != .auxiliary)
            var offline = offlineTrack(track, index: index, muted: muted, audible: audible)
            if lunatk.contains(index) {
                offline.stream = lunatkStream(track, index: index)
            } else if track.kind == .audio {
                offline.stream = audioStream(track)
            }
            tracks[index] = offline
        }

        let main = session.mainFX ?? LYFXRack()
        let comp = (main.compressor ?? .neutral).normalized()
        let tape = main.tape ?? .neutral
        let flanger = main.flanger ?? .neutral
        let decimator = main.decimator ?? .neutral
        let chorus = main.chorus ?? .neutral
        let gate = main.voidGate ?? .neutral
        let pump = (main.pump ?? .neutral).normalized()
        let finale = (main.finale ?? .neutral).normalized()
        var snapshot = OfflineProjectRenderSnapshot(
            sampleRate: sampleRate,
            bpm: session.bpm,
            meter: session.meterPreset,
            bars: bars,
            tracks: tracks,
            mainInsertOrder: main.chain(isMain: true).map(\.engineKey),
            mainEQBands: main.bands.map { OfflineEQBand(frequency: Float($0.frequency), gain: Float($0.gain), q: Float($0.q)) },
            mainCompressor: OfflineFETCompressor(
                thresholdDb: comp.threshold, ratio: comp.ratio, attackMilliseconds: comp.attackMilliseconds,
                releaseMilliseconds: comp.releaseMilliseconds, makeupDb: comp.makeup, mix: comp.mix, sidechainHPF: comp.sidechainHPF,
                bypassed: comp.isBypassed, character: comp.character(sidechainIndex: key(comp.sidechainSourceID, own: nil))),
            mainTape: offlineTape(tape),
            mainFlanger: offlineFlanger(flanger),
            mainDecimator: OfflineDecimator(destroy: decimator.destroy, crush: decimator.crush, bypassed: decimator.isBypassed,
                                            motion: LYFXBridge.motion(for: decimator)),
            mainChorus: OfflineChorus(mode: chorus.mode, rate: chorus.rate, depth: chorus.depth, width: chorus.width, mix: chorus.mix,
                                      trim: chorus.trim, bypassed: chorus.isBypassed),
            mainVoidGate: OfflineVoidGate(archetype: gate.archetype, hold: gate.hold, rise: gate.rise, floor: gate.floor, size: gate.size,
                                          tilt: gate.tilt, mix: gate.mix, bypassed: gate.isBypassed, keySource: key(gate.keySourceID, own: nil)),
            mainPump: OfflinePump(style: pump.style, rateSteps: pump.rateSteps, depth: pump.depth, shape: pump.shape, smooth: pump.smooth,
                                  mix: pump.mix, bypassed: pump.isBypassed, keySource: key(pump.keySourceID, own: nil)),
            finaleLimiter: OfflineFinaleLimiter(mode: finale.mode, gainDb: finale.gainDb, ceilingDb: finale.ceilingDb,
                                                lookaheadMs: finale.lookaheadMs, bypassed: finale.isBypassed),
            plateReverb: OfflinePlateReverb(parameters: plateReverb),
            tapeDelay: offlineBloom(main.signalBloom ?? .neutral),
            swing: min(max(session.swing ?? 0.5, 0.5), 0.75),
            mainTempoDelay: (main.tempoDelay ?? .neutral).offline(atBPM: session.bpm, meter: session.timeSignature)
        )
        let filter = main.filter ?? .neutral
        snapshot.mainFilter = filter.parameters(atBPM: session.bpm, followSource: key(filter.followSourceID, own: nil))
        snapshot.mainFilterMotion = filter.isBypassed ? nil : filter.motionConfiguration
        snapshot.mainFracture = (main.fracture ?? .neutral).parameters
        snapshot.mainDeadlock = (main.deadlock ?? .neutral).parameters
        let shear = main.shear ?? .neutral
        snapshot.mainShear = shear.parameters
        if !shear.isBypassed { snapshot.mainEffectMotion[.shear] = shear.motion?.holdingConfiguration }
        let cabinet = main.cabinet ?? .neutral
        snapshot.mainCabinet = cabinet.parameters
        if !cabinet.isBypassed { snapshot.mainEffectMotion[.cabinet] = cabinet.motion?.holdingConfiguration }
        snapshot.mainSplitField = (main.splitField ?? .neutral).parameters
        let steel = main.steelBody ?? .neutral
        snapshot.mainSteelBody = steel.parameters
        if !steel.isBypassed { snapshot.mainEffectMotion[.steelBody] = steel.motion?.holdingConfiguration }
        snapshot.mainStrike = (main.strike ?? .neutral).parameters
        snapshot.mainEQCuts = (main.eqCut ?? .neutral).parameters
        snapshot.busRoutes = LYChannelMap.routes(in: session)
        snapshot.mainOutputVolume = Float(min(pow(10, (session.mainVolumeDB ?? 0) / 20), 1))
        snapshot.automation = mixAutomation()
        return snapshot
    }

    private func value(_ values: [Double], _ index: Int, _ fallback: Double) -> Double {
        values.indices.contains(index) ? values[index] : fallback
    }

    /// Another channel's index for a sidechain key, or -1.
    private func key(_ id: UUID?, own: Int?) -> Int {
        guard let id, let index = channels.first(where: { $0.track.id == id })?.index, index != own else { return -1 }
        return index
    }

    private var plateReverb: PlateReverbParameters {
        let s = session.reverb ?? .neutral
        var p = PlateReverbParameters()
        switch s.mode {
        case .room: p.mode = .room
        case .hall: p.mode = .hall
        case .plate: p.mode = .plate
        case .spring: p.mode = .spring
        }
        p.preDelay = s.preDelay; p.decay = s.decay; p.size = s.size; p.damping = s.damping
        p.lowCut = s.lowCut; p.highCut = s.highCut; p.diffusion = s.diffusion; p.modDepth = s.modDepth
        p.modRate = s.modRate; p.width = s.width; p.duck = s.duck; p.duckRelease = s.duckRelease
        p.duckSource = key(s.duckSourceID, own: nil)
        p.outputLevel = s.outputLevel; p.bypassed = s.isBypassed
        return p
    }

    private func offlineTape(_ tape: TapeSaturationState) -> OfflineTapeSaturation {
        OfflineTapeSaturation(tapeType: tape.tapeType, speed: tape.speed, drive: tape.drive, bias: tape.bias, head: tape.head, mix: tape.mix,
                              outputDb: tape.outputDb, wow: tape.wow, flutter: tape.flutter, bypassed: tape.isBypassed)
    }

    private func offlineFlanger(_ flanger: FlangerState) -> OfflineFlanger {
        OfflineFlanger(mode: flanger.mode, rateHz: flanger.resolvedRateHz(atBPM: session.bpm), depth: flanger.depth, manual: flanger.manual,
                       feedback: flanger.feedback, width: flanger.width, tone: flanger.tone, mix: flanger.mix, bypassed: flanger.isBypassed)
    }

    private func offlineBloom(_ bloom: SignalBloomState) -> OfflineSignalBloom {
        OfflineSignalBloom(time: bloom.resolvedTime(atBPM: session.bpm), feedback: bloom.feedback, lowPassCutoff: bloom.tone, mix: bloom.mix,
                           bypassed: bloom.isBypassed, triggerSteps: bloom.triggerSteps,
                           cutSteps: min(max(bloom.cutSteps, 1), meter.activeSubdivisionCount), usesStepTriggers: true, swell: bloom.bloom)
    }

    /// One channel: its fader, FX chain and source, as the live engine has it.
    private func offlineTrack(_ track: LYTrack, index: Int, muted: Bool, audible: Bool) -> OfflineRenderTrack {
        let rack = track.fx ?? LYFXRack()
        let comp = (rack.compressor ?? .neutral).normalized()
        let decimator = rack.decimator ?? .neutral
        let chorus = rack.chorus ?? .neutral
        let gate = rack.voidGate ?? .neutral
        let pump = (rack.pump ?? .neutral).normalized()
        let envelope = track.envelope ?? TrackEnvelopeState()
        let musical = track.kind == .drumkit || track.kind == .instrument
        var offline = OfflineRenderTrack(
            sourceURL: sourceURLs[index],
            sourceIdentity: sourceURLs[index]?.lastPathComponent ?? track.id.uuidString,
            volume: Float(min(pow(10, track.volumeDB / 20), musical ? 1 : 3.98)),
            muted: muted,
            pan: Float(min(max(track.pan, -1), 1)),
            insertOrder: rack.chain(isMain: false).map(\.engineKey),
            eqBands: rack.bands.map { OfflineEQBand(frequency: Float($0.frequency), gain: Float($0.gain), q: Float($0.q)) },
            compressor: OfflineFETCompressor(
                thresholdDb: comp.threshold, ratio: comp.ratio, attackMilliseconds: comp.attackMilliseconds,
                releaseMilliseconds: comp.releaseMilliseconds, makeupDb: comp.makeup, mix: comp.mix, sidechainHPF: comp.sidechainHPF,
                bypassed: comp.isBypassed, character: comp.character(sidechainIndex: key(comp.sidechainSourceID, own: index))),
            tape: offlineTape(rack.tape ?? .neutral),
            flanger: offlineFlanger(rack.flanger ?? .neutral),
            decimator: OfflineDecimator(destroy: decimator.destroy, crush: decimator.crush, bypassed: decimator.isBypassed,
                                        motion: LYFXBridge.motion(for: decimator)),
            chorus: OfflineChorus(mode: chorus.mode, rate: chorus.rate, depth: chorus.depth, width: chorus.width, mix: chorus.mix,
                                  trim: chorus.trim, bypassed: chorus.isBypassed),
            voidGate: OfflineVoidGate(archetype: gate.archetype, hold: gate.hold, rise: gate.rise, floor: gate.floor, size: gate.size,
                                      tilt: gate.tilt, mix: gate.mix, bypassed: gate.isBypassed, keySource: key(gate.keySourceID, own: index)),
            envelope: OfflineTrackEnvelope(attack: envelope.attack, decay: envelope.decay, sustain: envelope.sustain, release: envelope.release,
                                           isBypassed: track.envelope == nil || envelope.isBypassed),
            reverbSend: rack.reverbSend ?? 0,
            signalBloom: offlineBloom(rack.signalBloom ?? .neutral),
            pump: OfflinePump(style: pump.style, rateSteps: pump.rateSteps, depth: pump.depth, shape: pump.shape, smooth: pump.smooth,
                              mix: pump.mix, bypassed: pump.isBypassed, keySource: key(pump.keySourceID, own: index)),
            tempoDelay: (rack.tempoDelay ?? .neutral).offline(atBPM: session.bpm, meter: session.timeSignature),
            chokeGroup: track.chokeGroup ?? 0,
            chokesGroup: audible
        )
        offline.synth = synthSources[index]
        let filter = rack.filter ?? .neutral
        offline.filter = filter.parameters(atBPM: session.bpm, followSource: key(filter.followSourceID, own: index))
        offline.filterMotion = filter.isBypassed ? nil : filter.motionConfiguration
        offline.fracture = (rack.fracture ?? .neutral).parameters
        offline.deadlock = (rack.deadlock ?? .neutral).parameters
        let shear = rack.shear ?? .neutral
        offline.shear = shear.parameters
        if !shear.isBypassed { offline.effectMotion[.shear] = shear.motion?.holdingConfiguration }
        let cabinet = rack.cabinet ?? .neutral
        offline.cabinet = cabinet.parameters
        if !cabinet.isBypassed { offline.effectMotion[.cabinet] = cabinet.motion?.holdingConfiguration }
        offline.splitField = (rack.splitField ?? .neutral).parameters
        let steel = rack.steelBody ?? .neutral
        offline.steelBody = steel.parameters
        if !steel.isBypassed { offline.effectMotion[.steelBody] = steel.motion?.holdingConfiguration }
        offline.strike = (rack.strike ?? .neutral).parameters
        offline.undertow = (rack.undertow ?? .neutral).parameters
        let cut = rack.eqCut ?? .neutral
        offline.eqCuts = cut.parameters
        offline.polarityInverted = cut.polarityInverted
        if let finale = rack.finale?.normalized(), !finale.isBypassed {
            offline.elasticLimiter = OfflineFinaleLimiter(mode: finale.mode, gainDb: finale.gainDb, ceilingDb: finale.ceilingDb,
                                                          lookaheadMs: finale.lookaheadMs, bypassed: false)
        }
        return offline
    }

    // MARK: LUNATK

    private struct NoteEvent {
        var frame: Int64
        var isOn: Bool
        var note: Int32
        var velocity: Int32 = 0
        var cutoff: Float = 1
        var resonance: Float = 0
    }

    private func frame(ofWindowBeat beat: Double) -> Int64 {
        Int64((beat * secondsPerBeat * sampleRate).rounded())
    }

    /// The notes a LUNATK track plays: its steps, exactly as a live channel
    /// hands them to the instrument (swing, flams, gates, per-step filter),
    /// then its piano-roll notes.
    private func noteEvents(for track: LYTrack, index: Int) -> [NoteEvent] {
        var events: [NoteEvent] = []
        let root = track.rootNote ?? 48
        let swingFrames = Int64((NightshapeAudioEngine.swingOffsetSeconds(amount: min(max(session.swing ?? 0.5, 0.5), 0.75),
                                                                          stepDuration: stepSeconds) * sampleRate).rounded())
        var barStep: Int64 = 0
        func add(on: Int64, gateSeconds: Double, note: Int, gain: Double, cutoff: Double, resonance: Double) {
            let pitch = Int32(min(max(note, 0), 127))
            let velocity = Int32(max(1, min(127, (max(0.04, min(1, gain)) * 127).rounded())))
            events.append(NoteEvent(frame: on, isOn: true, note: pitch, velocity: velocity,
                                    cutoff: Float(min(max(cutoff, 0), 1)), resonance: Float(min(max(resonance, 0), 1)) * 0.95))
            events.append(NoteEvent(frame: on + max(1, Int64((max(gateSeconds, 0.001) * sampleRate).rounded())), isOn: false, note: pitch))
        }
        for frame in frames {
            if frame.tracks.indices.contains(index) {
                let steps = frame.tracks[index]
                for step in 0..<min(frame.stepCount, steps.activeSteps.count) where steps.activeSteps[step] {
                    var on = OfflineProjectRenderer.framePosition(forStep: barStep + Int64(step), meter: meter, bpm: session.bpm, sampleRate: sampleRate)
                    if step % 2 == 1 { on += swingFrames }
                    let length = steps.noteLengths.indices.contains(step) ? steps.noteLengths[step] : 1
                    let note = root + (steps.pitches.indices.contains(step) ? steps.pitches[step] : 0)
                    let gain = value(steps.velocities, step, 0.82) * value(steps.volumes, step, 1)
                    let cutoff = value(steps.cutoffs, step, 1), resonance = value(steps.resonances, step, 0)
                    if steps.flamSteps.indices.contains(step), steps.flamSteps[step] {
                        let grace = on - Int64(TrackChannel.flamGraceSeconds * sampleRate)
                        if grace >= 0 {
                            add(on: grace, gateSeconds: 0, note: note, gain: gain * TrackChannel.flamGraceVelocityScale, cutoff: cutoff, resonance: resonance)
                        }
                    }
                    add(on: on, gateSeconds: length > 1 ? Double(length) * stepSeconds : 0, note: note, gain: gain, cutoff: cutoff, resonance: resonance)
                }
            }
            barStep += Int64(frame.stepCount)
        }
        for clip in track.clips where clip.isNoteClip && clip.isInSong && !clip.isMuted {
            for note in clip.songNotes(from: window.startBeat, to: window.endBeat) {
                let on = frame(ofWindowBeat: note.beat - window.startBeat)
                let end = frame(ofWindowBeat: min(note.beat + note.length, window.endBeat) - window.startBeat)
                let pitch = Int32(min(max(note.pitch, 0), 127))
                events.append(NoteEvent(frame: on, isOn: true, note: pitch, velocity: Int32(min(max(note.velocity, 1), 127))))
                events.append(NoteEvent(frame: max(end, on + 1), isOn: false, note: pitch))
            }
        }
        // Offs before ons on the same frame, so a repeated note retriggers.
        return events.sorted { $0.frame == $1.frame ? (!$0.isOn && $1.isOn) : $0.frame < $1.frame }
    }

    private func lunatkStream(_ track: LYTrack, index: Int) -> OfflineStreamSource.Render {
        let instrument = LYSynthInstrument(sampleRate: sampleRate)
        instrument.apply(track.synth ?? .initPatch, bpm: session.bpm)
        let core = instrument.core
        let events = noteEvents(for: track, index: index)
        let lanes = (track.automation ?? []).filter(\.isActive).compactMap { lane -> (Int32, LYAutomationLane)? in
            guard case .synth(let key) = lane.target, let parameter = LYSynthParameters.byKey[key] else { return nil }
            return (Int32(parameter.id), lane)
        }
        let startBeat = window.startBeat
        let framesPerBeat = secondsPerBeat * sampleRate
        var next = 0
        var sent: [Int32: Float] = [:]
        return { left, right, count, start in
            _ = instrument
            if !lanes.isEmpty {
                let beat = startBeat + Double(start) / framesPerBeat
                for (id, lane) in lanes {
                    guard let raw = lane.value(at: beat) else { continue }
                    let range = lane.target.range
                    let value = Float(min(max(raw, range.lowerBound), range.upperBound))
                    guard sent[id] != value else { continue }
                    sent[id] = value
                    lysynth_set_param(core, id, value)
                }
            }
            var position = 0
            while position < count {
                let now = start + Int64(position)
                while next < events.count, events[next].frame <= now {
                    let event = events[next]
                    if event.isOn {
                        lysynth_note_on(core, event.note, event.velocity, 0, event.cutoff, event.resonance)
                    } else {
                        lysynth_note_off(core, event.note, 0)
                    }
                    next += 1
                }
                let until = next < events.count ? min(Int(events[next].frame - start), count) : count
                let frames = max(1, until - position)
                lysynth_set_song_position(core, startBeat + Double(now) / framesPerBeat, 1)
                lysynth_render(core, left + position, right + position, Int32(frames), 0)
                position += frames
            }
        }
    }

    // MARK: Audio events

    private func audioStream(_ track: LYTrack) -> OfflineStreamSource.Render? {
        let clips = Dictionary(uniqueKeysWithValues: track.clips.map { ($0.id, $0) })
        struct Placed {
            var start: Int64
            var cycle: AVAudioPCMBuffer
            var cycleStart: Int
            var count: Int
            var fadeIn: Int
            var fadeOut: Int
            var gain: Float
        }
        var placed: [Placed] = []
        for segment in segments {
            guard let clip = clips[segment.clipID], !clip.isMuted, let cycle = cycles[segment.renderKey] else { continue }
            let rate = sampleRate
            placed.append(Placed(
                start: frame(ofWindowBeat: segment.windowOffsetBeats),
                cycle: cycle,
                cycleStart: Int((segment.cycleOffsetBeats * secondsPerBeat * rate).rounded()),
                count: Int((segment.lengthBeats * secondsPerBeat * rate).rounded()),
                fadeIn: Int(segment.fadeInBeats * secondsPerBeat * rate),
                fadeOut: Int(segment.fadeOutBeats * secondsPerBeat * rate),
                gain: clip.eventGainDB <= -59.95 ? 0 : Float(pow(10, clip.eventGainDB / 20))
            ))
        }
        guard !placed.isEmpty else { return nil }
        placed.sort { $0.start < $1.start }
        // Slices are cut when first heard and dropped once passed, so a long
        // song never holds its whole audio in memory.
        var sliced: [Int: AVAudioPCMBuffer] = [:]
        return { left, right, count, start in
            let end = start + Int64(count)
            for (index, piece) in placed.enumerated() {
                if piece.start >= end { break }
                let pieceEnd = piece.start + Int64(piece.count)
                guard pieceEnd > start else { sliced[index] = nil; continue }
                if sliced[index] == nil {
                    sliced[index] = LYTimelineAudioPlayer.slice(piece.cycle, from: piece.cycleStart, count: piece.count,
                                                                fadeInFrames: piece.fadeIn, fadeOutFrames: piece.fadeOut)
                }
                guard let buffer = sliced[index], let data = buffer.floatChannelData else { continue }
                let channels = Int(buffer.format.channelCount)
                let from = max(start, piece.start), to = min(end, piece.start + Int64(buffer.frameLength))
                guard to > from else { continue }
                let source = Int(from - piece.start), target = Int(from - start)
                for i in 0..<Int(to - from) {
                    left[target + i] += data[0][source + i] * piece.gain
                    right[target + i] += data[min(1, channels - 1)][source + i] * piece.gain
                }
            }
        }
    }

    // MARK: Automation

    /// Volume, pan, sends and effect lanes, applied before every block.
    private func mixAutomation() -> ((Int64, OfflineMixControl) -> Void)? {
        let byChannel = Dictionary(uniqueKeysWithValues: channels.map { ($0.track.id, $0.index) })
        let lanes: [(track: LYTrack, channel: Int, lane: LYAutomationLane)] = channels.flatMap { track, index in
            (track.automation ?? []).filter { lane in
                guard lane.isActive else { return false }
                if case .synth = lane.target { return false }
                return true
            }.map { (track, index, $0) }
        }
        guard !lanes.isEmpty else { return nil }
        let baseRoutes = LYChannelMap.routes(in: session)
        let startBeat = window.startBeat
        let framesPerBeat = secondsPerBeat * sampleRate
        let session = session
        var sent: [String: Double] = [:]
        var sendLevels: [Int: [Int: Float]] = [:]
        return { frame, mix in
            let beat = startBeat + Double(frame) / framesPerBeat
            var routesChanged = false
            var racks: [Int: (rack: LYFXRack, track: LYTrack, kinds: Set<FXKind>)] = [:]
            for (track, channel, lane) in lanes {
                guard let raw = lane.value(at: beat) else { continue }
                let range = lane.target.range
                let value = min(max(raw, range.lowerBound), range.upperBound)
                let key = "\(channel)|\(lane.target)"
                guard sent[key].map({ abs($0 - value) > 1e-5 }) ?? true else { continue }
                sent[key] = value
                switch lane.target {
                case .volume:
                    let cap = track.kind == .drumkit || track.kind == .instrument ? 1.0 : 3.98
                    mix.setTrackVolume(channel, min(value <= -59.9 ? 0 : pow(10, value / 20), cap))
                case .pan:
                    mix.setTrackPan(channel, Float(value))
                case .send(let busID):
                    guard let bus = byChannel[busID] else { continue }
                    sendLevels[channel, default: [:]][bus] = Float(value)
                    routesChanged = true
                case .fx(let fxKey):
                    guard let parameter = LYFXAutomation.byKey[fxKey] else { continue }
                    var entry = racks[channel] ?? (track.fx ?? LYFXRack(), track, [])
                    parameter.set(&entry.rack, value)
                    entry.kinds.insert(parameter.kind)
                    racks[channel] = entry
                case .synth:
                    break
                }
            }
            if routesChanged {
                var routes = baseRoutes
                for (channel, sends) in sendLevels {
                    for (bus, amount) in sends { routes[channel, default: .init()].sends[bus] = amount }
                }
                mix.setBusRouting(routes)
            }
            for (channel, entry) in racks {
                // Other lanes on the same effect keep their latest values.
                var rack = entry.rack
                for (track, laneChannel, lane) in lanes where laneChannel == channel {
                    guard case .fx(let fxKey) = lane.target, let parameter = LYFXAutomation.byKey[fxKey],
                          let value = sent["\(channel)|\(lane.target)"] else { continue }
                    _ = track
                    parameter.set(&rack, value)
                }
                for kind in entry.kinds {
                    LYOfflineExport.push(kind, rack: rack, channel: channel, session: session, mix: mix)
                }
            }
        }
    }

    nonisolated private static func push(_ kind: FXKind, rack: LYFXRack, channel: Int, session: LYLLTHSession, mix: OfflineMixControl) {
        switch kind {
        case .reverb:
            mix.setReverbSend(channel, rack.reverbSend ?? 0)
        case .filter:
            let s = rack.filter ?? .neutral
            let follow = s.followSourceID.flatMap { id in LYChannelMap.channels(in: session).first { $0.trackID == id }?.index } ?? -1
            mix.setTrackFilter(channel, s.parameters(atBPM: session.bpm, followSource: follow == channel ? -1 : follow))
        case .tempoDelay:
            mix.setTrackTempoDelay(channel, (rack.tempoDelay ?? .neutral).parameters(atBPM: session.bpm, meter: session.timeSignature))
        case .decim:
            let s = rack.decimator ?? .neutral
            mix.setTrackDecimator(channel, destroy: s.destroy, crush: s.crush, bypassed: s.isBypassed)
        case .tape:
            mix.setTrackTape(channel, (rack.tape ?? .neutral).normalized().parameters())
        case .flanger:
            mix.setTrackFlanger(channel, (rack.flanger ?? .neutral).normalized().parameters(atBPM: session.bpm))
        case .chorus:
            let s = rack.chorus ?? .neutral
            mix.setTrackChorus(channel, ChorusParameters(mode: s.mode, rate: s.rate, depth: s.depth, width: s.width, mix: s.mix, trim: s.trim, bypassed: s.isBypassed))
        default:
            break
        }
    }

    // MARK: Rendering

    /// Renders on a background thread. `progress` is called there too.
    nonisolated static func render(
        _ snapshot: OfflineProjectRenderSnapshot,
        to url: URL,
        format: OfflineExportFormat,
        cancellation: OfflineRenderCancellationToken,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> OfflineProjectRenderResult {
        try await Task.detached(priority: .userInitiated) {
            try OfflineProjectRenderer().render(snapshot: snapshot, to: url, format: format, cancellation: cancellation, progress: progress)
        }.value
    }
}

extension LYLLTHSession {
    /// The transport meter the engine plays this song in.
    var meterPreset: TransportMeter.Preset {
        switch (numerator, denominator) {
        case (3, 4): return .threeFour
        case (6, 8): return .sixEight
        default: return .fourFour
        }
    }
}

/// One-shot samples from the song's audio, on disk where the engine can
/// load them. Named by content, so the same sample is written once.
enum LYSampleFiles {
    static func url(for data: Data, path: String) throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LYLLTH/Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let url = folder.appendingPathComponent(digest + "-" + (path as NSString).lastPathComponent)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url) }
        return url
    }
}
