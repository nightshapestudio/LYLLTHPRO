import Foundation
import NightshapeAudioEngine

/// One channel's NIGHTSHAPE effects, stored as DrumKit's own state types so a
/// DrumKit track's settings and a LYLLTH track's are the same data. Every
/// field is optional: an effect never opened keeps no state and plays neutral.
struct LYFXRack: Codable, Equatable {
    var order: [FXKind]? = nil
    var eqBands: [EQBandState]? = nil
    var eqCut: EQCutState? = nil
    var compressor: CompressorState? = nil
    var tape: TapeSaturationState? = nil
    var flanger: FlangerState? = nil
    var chorus: ChorusState? = nil
    var voidGate: VoidGateState? = nil
    var tempoDelay: TempoDelayState? = nil
    var filter: FilterState? = nil
    var fracture: FractureState? = nil
    var deadlock: DeadlockState? = nil
    var strike: StrikeState? = nil
    var steelBody: SteelBodyState? = nil
    var undertow: UndertowState? = nil
    var splitField: SplitFieldState? = nil
    var shear: ShearState? = nil
    var cabinet: CabinetState? = nil
    var pump: PumpState? = nil
    var finale: FinaleState? = nil
    var signalBloom: SignalBloomState? = nil
    var decimator: DecimatorState? = nil
    /// A track's send into the shared reverb. Unused on MAIN.
    var reverbSend: Float? = nil

    /// DrumKit's five-band EQ as it starts on every channel.
    static let defaultBands: [EQBandState] = [
        EQBandState(type: .lowShelf, frequency: 80, gain: 0, q: 0.7),
        EQBandState(type: .peaking, frequency: 250, gain: 0, q: 1.2),
        EQBandState(type: .peaking, frequency: 1000, gain: 0, q: 1.0),
        EQBandState(type: .peaking, frequency: 4000, gain: 0, q: 1.2),
        EQBandState(type: .highShelf, frequency: 12_000, gain: 0, q: 0.7)
    ]

    func chain(isMain: Bool) -> [FXKind] {
        FXKind.normalizedInsertOrder(
            order ?? (isMain ? FXKind.defaultMainInsertOrder : FXKind.defaultInsertOrder),
            defaultOrder: isMain ? FXKind.defaultMainInsertOrder : FXKind.defaultInsertOrder
        )
    }

    var bands: [EQBandState] { eqBands ?? Self.defaultBands }

    /// Puts the given inserts in this order. Effects not listed (EQ, and a
    /// track's reverb send) keep their places in the chain.
    mutating func reorderInserts(_ shown: [FXKind], isMain: Bool) {
        var full = chain(isMain: isMain)
        let slots = full.indices.filter { shown.contains(full[$0]) }
        guard slots.count == shown.count else { return }
        for (slot, kind) in zip(slots, shown) { full[slot] = kind }
        order = full
    }

    /// Whether an effect in the chain is switched in, the way DrumKit lights
    /// its node. EQ has no bypass; a track's reverb is on while its send is up.
    func isEngaged(_ kind: FXKind, isMain: Bool, reverb: ReverbState) -> Bool {
        guard chain(isMain: isMain).contains(kind) else { return false }
        switch kind {
        case .eq: return true
        case .comp: return !(compressor ?? .neutral).isBypassed
        case .tape: return !(tape ?? .neutral).isBypassed
        case .flanger: return !(flanger ?? .neutral).isBypassed
        case .decim: return !(decimator ?? .neutral).isBypassed
        case .chorus: return !(chorus ?? .neutral).isBypassed
        case .voidGate: return !(voidGate ?? .neutral).isBypassed
        case .tempoDelay: return !(tempoDelay ?? .neutral).isBypassed
        case .filter: return !(filter ?? .neutral).isBypassed
        case .fracture: return !(fracture ?? .neutral).isBypassed
        case .deadlock: return !(deadlock ?? .neutral).isBypassed
        case .strike: return !(strike ?? .neutral).isBypassed
        case .steelBody: return !(steelBody ?? .neutral).isBypassed
        case .undertow: return !(undertow ?? .neutral).isBypassed
        case .splitField: return !(splitField ?? .neutral).isBypassed
        case .shear: return !(shear ?? .neutral).isBypassed
        case .cabinet: return !(cabinet ?? .neutral).isBypassed
        case .pump: return !(pump ?? .neutral).isBypassed
        case .delay: return !(signalBloom ?? .neutral).isBypassed
        case .finale: return !(finale ?? .neutral).isBypassed
        case .reverb: return isMain ? !reverb.isBypassed : (reverbSend ?? 0) > 0.0001
        }
    }

    /// Flips an effect's bypass. EQ cannot be bypassed (flat is its off).
    mutating func toggleBypass(_ kind: FXKind, parkedReverbSend: inout Float?) {
        switch kind {
        case .eq: break
        case .comp: var s = compressor ?? .neutral; s.isBypassed.toggle(); compressor = s
        case .tape: var s = tape ?? .neutral; s.isBypassed.toggle(); tape = s
        case .flanger: var s = flanger ?? .neutral; s.isBypassed.toggle(); flanger = s
        case .decim: var s = decimator ?? .neutral; s.isBypassed.toggle(); decimator = s
        case .chorus: var s = chorus ?? .neutral; s.isBypassed.toggle(); chorus = s
        case .voidGate: var s = voidGate ?? .neutral; s.isBypassed.toggle(); voidGate = s
        case .tempoDelay: var s = tempoDelay ?? .neutral; s.isBypassed.toggle(); tempoDelay = s
        case .filter: var s = filter ?? .neutral; s.isBypassed.toggle(); filter = s
        case .fracture: var s = fracture ?? .neutral; s.isBypassed.toggle(); fracture = s
        case .deadlock: var s = deadlock ?? .neutral; s.isBypassed.toggle(); deadlock = s
        case .strike: var s = strike ?? .neutral; s.isBypassed.toggle(); strike = s
        case .steelBody: var s = steelBody ?? .neutral; s.isBypassed.toggle(); steelBody = s
        case .undertow: var s = undertow ?? .neutral; s.isBypassed.toggle(); undertow = s
        case .splitField: var s = splitField ?? .neutral; s.isBypassed.toggle(); splitField = s
        case .shear: var s = shear ?? .neutral; s.isBypassed.toggle(); shear = s
        case .cabinet: var s = cabinet ?? .neutral; s.isBypassed.toggle(); cabinet = s
        case .pump: var s = pump ?? .neutral; s.isBypassed.toggle(); pump = s
        case .delay: var s = signalBloom ?? .neutral; s.isBypassed.toggle(); signalBloom = s
        case .finale: var s = finale ?? .neutral; s.isBypassed.toggle(); finale = s
        case .reverb:
            // A track's reverb is a send: park it at zero and put it back,
            // as DrumKit does, so the amount survives being switched off.
            if (reverbSend ?? 0) > 0.0001 {
                parkedReverbSend = reverbSend
                reverbSend = 0
            } else {
                reverbSend = parkedReverbSend ?? 0.25
            }
        }
    }
}

/// Where each NIGHTSHAPE effect lives in the engine. The same calls DrumKit's
/// root view makes (its push…ToEngine functions), keyed by LYLLTH tracks.
@MainActor
enum LYFXBridge {
    /// Engine channel for a track: its position among the musical tracks the
    /// engine plays, or nil for tracks the engine has no channel for.
    static func engineIndex(for trackID: UUID, in session: LYLLTHSession) -> Int? {
        LYChannelMap.channels(in: session).first { $0.trackID == trackID }?.index
    }

    static func keySources(in session: LYLLTHSession, excluding target: FXTarget) -> [(id: UUID, name: String)] {
        session.tracks
            .filter { ($0.kind == .drumkit || $0.kind == .instrument) && target != .track($0.id) }
            .map { (id: $0.id, name: $0.name) }
    }

    static func rack(for target: FXTarget, in session: LYLLTHSession) -> LYFXRack {
        switch target {
        case .main: return session.mainFX ?? LYFXRack()
        case .track(let id): return session.tracks.first { $0.id == id }?.fx ?? LYFXRack()
        }
    }

    static func setRack(_ rack: LYFXRack, for target: FXTarget, in session: inout LYLLTHSession) {
        switch target {
        case .main: session.mainFX = rack
        case .track(let id):
            guard let index = session.tracks.firstIndex(where: { $0.id == id }) else { return }
            session.tracks[index].fx = rack
        }
    }

    /// Pushes every effect on every channel. Called when a project opens and
    /// when tracks move, since engine channels follow track order.
    static func pushAll(_ session: LYLLTHSession, engine: NightshapeAudioEngine) {
        LYChannelMap.ensureChannels(for: session, engine: engine)
        for track in session.tracks {
            guard engineIndex(for: track.id, in: session) != nil else { continue }
            pushRack(target: .track(track.id), session: session, engine: engine)
        }
        pushRack(target: .main, session: session, engine: engine)
        pushReverb(session, engine: engine)
    }

    static func pushRack(target: FXTarget, session: LYLLTHSession, engine: NightshapeAudioEngine) {
        let rack = rack(for: target, in: session)
        let isMain = target == .main
        let index: Int?
        if case .track(let id) = target {
            guard let resolved = engineIndex(for: id, in: session) else { return }
            index = resolved
        } else {
            index = nil
        }
        let order = rack.chain(isMain: isMain).map(\.engineKey)
        if let index { engine.setFXChainOrder(trackIndex: index, order: order) } else { engine.setMainFXChainOrder(order: order) }
        for kind in FXKind.controlDeckCases where kind != .reverb {
            push(kind, rack: rack, index: index, session: session, engine: engine)
        }
        if let index {
            engine.setReverbSend(trackIndex: index, amount: rack.reverbSend ?? 0)
        }
    }

    static func push(
        _ kind: FXKind,
        rack: LYFXRack,
        index: Int?,
        session: LYLLTHSession,
        engine: NightshapeAudioEngine
    ) {
        let bpm = session.bpm
        let key = { (id: UUID?) -> Int in
            guard let id, let resolved = engineIndex(for: id, in: session), resolved != index else { return -1 }
            return resolved
        }
        let stepsPerBar = session.numerator == 4 ? 16 : 12
        switch kind {
        case .eq:
            for (band, state) in rack.bands.enumerated() {
                if let index {
                    engine.setEQBand(trackIndex: index, band: band, frequency: Float(state.frequency), gain: Float(state.gain), q: Float(state.q))
                } else {
                    engine.setMainEQBand(band: band, frequency: Float(state.frequency), gain: Float(state.gain), q: Float(state.q))
                }
            }
            let cut = rack.eqCut ?? .neutral
            if let index {
                engine.setEQCuts(trackIndex: index, parameters: cut.parameters)
                engine.setTrackPolarityInverted(trackIndex: index, inverted: cut.polarityInverted)
            } else {
                engine.setMainEQCuts(cut.parameters)
            }
        case .comp:
            let value = (rack.compressor ?? .neutral).normalized()
            let character = value.character(sidechainIndex: key(value.sidechainSourceID))
            if let index {
                engine.setCompressor(trackIndex: index, thresholdDb: value.threshold, ratio: value.ratio,
                                     attackMilliseconds: value.attackMilliseconds, releaseMilliseconds: value.releaseMilliseconds,
                                     makeupDb: value.makeup, mix: value.mix, sidechainHPF: value.sidechainHPF,
                                     bypassed: value.isBypassed, character: character)
            } else {
                engine.setMainCompressor(thresholdDb: value.threshold, ratio: value.ratio,
                                         attackMilliseconds: value.attackMilliseconds, releaseMilliseconds: value.releaseMilliseconds,
                                         makeupDb: value.makeup, mix: value.mix, sidechainHPF: value.sidechainHPF,
                                         bypassed: value.isBypassed, character: character)
            }
        case .tape:
            let value = (rack.tape ?? .neutral).normalized()
            if let index { engine.setTapeSaturation(trackIndex: index, parameters: value.parameters()) } else { engine.setMainTapeSaturation(parameters: value.parameters()) }
        case .flanger:
            let value = (rack.flanger ?? .neutral).normalized()
            if let index { engine.setFlanger(trackIndex: index, parameters: value.parameters(atBPM: bpm)) } else { engine.setMainFlanger(parameters: value.parameters(atBPM: bpm)) }
        case .decim:
            let state = rack.decimator ?? .neutral
            if let index {
                engine.setDecimator(trackIndex: index, destroy: state.destroy, crush: state.crush, bypassed: state.isBypassed)
                engine.setDecimatorMotion(trackIndex: index, configuration: motion(for: state))
            } else {
                engine.setMainDecimator(destroy: state.destroy, crush: state.crush, bypassed: state.isBypassed)
                engine.setMainDecimatorMotion(configuration: motion(for: state))
            }
        case .chorus:
            let s = rack.chorus ?? .neutral
            if let index {
                engine.setChorus(trackIndex: index, mode: s.mode, rate: s.rate, depth: s.depth, width: s.width, mix: s.mix, trim: s.trim, bypassed: s.isBypassed)
            } else {
                engine.setMainChorus(mode: s.mode, rate: s.rate, depth: s.depth, width: s.width, mix: s.mix, trim: s.trim, bypassed: s.isBypassed)
            }
        case .voidGate:
            let s = rack.voidGate ?? .neutral
            if let index {
                engine.setVoidGate(trackIndex: index, archetype: s.archetype, hold: s.hold, rise: s.rise, floor: s.floor, size: s.size,
                                   tilt: s.tilt, mix: s.mix, bypassed: s.isBypassed, keySource: key(s.keySourceID))
            } else {
                engine.setMainVoidGate(archetype: s.archetype, hold: s.hold, rise: s.rise, floor: s.floor, size: s.size,
                                       tilt: s.tilt, mix: s.mix, bypassed: s.isBypassed, keySource: key(s.keySourceID))
            }
        case .tempoDelay:
            let s = rack.tempoDelay ?? .neutral
            let parameters = s.parameters(atBPM: bpm, meter: session.timeSignature)
            if let index {
                engine.setTempoDelay(trackIndex: index, parameters: parameters)
            } else {
                engine.setMainTempoDelay(parameters: parameters)
            }
            engine.setTempoDelayThrows(trackIndex: index, steps: s.activeThrowSteps)
        case .filter:
            let s = rack.filter ?? .neutral
            let parameters = s.parameters(atBPM: bpm, followSource: key(s.followSourceID))
            if let index {
                engine.setFilter(trackIndex: index, parameters: parameters)
                engine.setFilterMotion(trackIndex: index, configuration: s.isBypassed ? nil : s.motionConfiguration)
            } else {
                engine.setMainFilter(parameters: parameters)
                engine.setMainFilterMotion(configuration: s.isBypassed ? nil : s.motionConfiguration)
            }
        case .fracture:
            let s = rack.fracture ?? .neutral
            if let index { engine.setFracture(trackIndex: index, parameters: s.parameters) } else { engine.setMainFracture(parameters: s.parameters) }
        case .deadlock:
            let s = rack.deadlock ?? .neutral
            if let index { engine.setDeadlock(trackIndex: index, parameters: s.parameters) } else { engine.setMainDeadlock(parameters: s.parameters) }
        case .strike:
            let s = rack.strike ?? .neutral
            if let index { engine.setStrike(trackIndex: index, parameters: s.parameters) } else { engine.setMainStrike(parameters: s.parameters) }
        case .steelBody:
            let s = rack.steelBody ?? .neutral
            if let index { engine.setSteelBody(trackIndex: index, parameters: s.parameters) } else { engine.setMainSteelBody(parameters: s.parameters) }
            engine.setEffectMotion(.steelBody, trackIndex: index, configuration: s.isBypassed ? nil : s.motion?.holdingConfiguration)
        case .undertow:
            if let index { engine.setUndertow(trackIndex: index, parameters: (rack.undertow ?? .neutral).parameters) }
        case .splitField:
            let s = rack.splitField ?? .neutral
            if let index { engine.setSplitField(trackIndex: index, parameters: s.parameters) } else { engine.setMainSplitField(parameters: s.parameters) }
        case .shear:
            let s = rack.shear ?? .neutral
            if let index { engine.setShear(trackIndex: index, parameters: s.parameters) } else { engine.setMainShear(parameters: s.parameters) }
            engine.setEffectMotion(.shear, trackIndex: index, configuration: s.isBypassed ? nil : s.motion?.holdingConfiguration)
        case .cabinet:
            let s = rack.cabinet ?? .neutral
            if let index { engine.setCabinet(trackIndex: index, parameters: s.parameters) } else { engine.setMainCabinet(parameters: s.parameters) }
            engine.setEffectMotion(.cabinet, trackIndex: index, configuration: s.isBypassed ? nil : s.motion?.holdingConfiguration)
        case .pump:
            let v = (rack.pump ?? .neutral).normalized()
            if let index {
                engine.setPump(trackIndex: index, style: v.style, rateSteps: v.rateSteps, depth: v.depth, shape: v.shape, smooth: v.smooth,
                               mix: v.mix, bpm: Float(bpm), bypassed: v.isBypassed, keySource: key(v.keySourceID))
            } else {
                engine.setMainPump(style: v.style, rateSteps: v.rateSteps, depth: v.depth, shape: v.shape, smooth: v.smooth,
                                   mix: v.mix, bpm: Float(bpm), bypassed: v.isBypassed, keySource: key(v.keySourceID))
            }
        case .delay:
            let s = rack.signalBloom ?? .neutral
            let cut = min(max(s.cutSteps, 1), stepsPerBar)
            if let index {
                engine.setTrackSignalBloom(trackIndex: index, time: s.resolvedTime(atBPM: bpm), feedback: s.feedback, lowPassCutoff: s.tone,
                                           mix: s.mix, bypassed: s.isBypassed, triggerSteps: s.triggerSteps, cutSteps: cut, swell: s.bloom)
            } else {
                engine.setMainSignalBloom(time: s.resolvedTime(atBPM: bpm), feedback: s.feedback, lowPassCutoff: s.tone,
                                          mix: s.mix, bypassed: s.isBypassed, triggerSteps: s.triggerSteps, cutSteps: cut, swell: s.bloom)
            }
        case .finale:
            let v = (rack.finale ?? .neutral).normalized()
            if let index {
                engine.setElasticLimiter(trackIndex: index, mode: v.mode, gainDb: v.gainDb, ceilingDb: v.ceilingDb, lookaheadMs: v.lookaheadMs, bypassed: v.isBypassed)
            } else {
                engine.setFinaleLimiter(mode: v.mode, gainDb: v.gainDb, ceilingDb: v.ceilingDb, lookaheadMs: v.lookaheadMs, bypassed: v.isBypassed)
            }
        case .reverb:
            if let index { engine.setReverbSend(trackIndex: index, amount: rack.reverbSend ?? 0) } else { pushReverb(session, engine: engine) }
        }
    }

    /// The shared reverb every track sends into. It lives on MAIN.
    static func pushReverb(_ session: LYLLTHSession, engine: NightshapeAudioEngine) {
        let s = session.reverb ?? .neutral
        let mode: PlateReverbMode
        switch s.mode {
        case .room: mode = .room
        case .hall: mode = .hall
        case .plate: mode = .plate
        case .spring: mode = .spring
        }
        let duck: Int = s.duckSourceID.flatMap { engineIndex(for: $0, in: session) } ?? -1
        engine.setPlateReverb(
            mode: mode, preDelay: s.preDelay, decay: s.decay, size: s.size, damping: s.damping,
            lowCut: s.lowCut, highCut: s.highCut, diffusion: s.diffusion, modDepth: s.modDepth,
            modRate: s.modRate, width: s.width, duck: s.duck, duckRelease: s.duckRelease,
            outputLevel: s.outputLevel, bypassed: s.isBypassed, duckSource: duck
        )
    }

    private static func motion(for state: DecimatorState) -> DecimatorMotionConfiguration? {
        guard state.isMotionActive, let motion = state.motion else { return nil }
        return DecimatorMotionConfiguration(
            isEnabled: true,
            points: motion.normalized().steps.map { DecimatorMotionPoint(isOn: $0.isOn, destroy: $0.x, crush: $0.y) },
            length: motion.activeLength,
            ticksPerStep: motion.rate.ticksPerStep,
            glide: motion.glide,
            offMode: motion.offMode == .hold ? .hold : .dry
        )
    }
}

extension LYLLTHSession {
    /// DrumKit's meter enum, for FX that time themselves to the bar.
    var timeSignature: TimeSignature {
        switch (numerator, denominator) {
        case (3, 4): return .threeFour
        case (6, 8): return .sixEight
        default: return .fourFour
        }
    }
}

// MARK: - Channels and buses

/// Which engine channel each track plays on. The sequencer's tracks come
/// first, in track order, since the song compiler numbers them that way; then
/// audio tracks, then AUX RETURNs. The engine starts with sixteen channels
/// and builds more as tracks are added, up to `engineChannels`.
enum LYChannelMap {
    static let engineChannels = 256

    /// Must run before anything touches `NightshapeAudioEngine.shared`.
    static func configureEngine() {
        TrackChannel.maxTracks = engineChannels
        TrackChannel.initialTracks = 16
    }

    /// Builds any engine channels the session needs that do not exist yet.
    @MainActor
    static func ensureChannels(for session: LYLLTHSession, engine: NightshapeAudioEngine = .shared) {
        let needed = channels(in: session).count
        if needed > engine.trackChannelCount { engine.ensureTrackChannels(needed) }
    }

    static func channels(in session: LYLLTHSession) -> [(trackID: UUID, index: Int)] {
        let musical = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        let audio = session.tracks.filter { $0.kind == .audio }
        let buses = session.tracks.filter { $0.kind == .auxiliary }
        return (musical + audio + buses).prefix(TrackChannel.maxTracks).enumerated().map { ($0.element.id, $0.offset) }
    }

    /// The AUX RETURNs a track can send to or play through.
    static func buses(for track: LYTrack, in session: LYLLTHSession) -> [LYTrack] {
        session.tracks.filter { $0.kind == .auxiliary && $0.id != track.id }
    }

    /// Mute and solo together. A soloed track keeps the buses it feeds
    /// audible, the way a solo in Logic keeps its reverb.
    static func isAudible(_ track: LYTrack, in session: LYLLTHSession) -> Bool {
        guard !track.isMuted else { return false }
        let soloed = session.tracks.filter(\.isSolo)
        guard !soloed.isEmpty, !track.isSolo else { return true }
        guard track.kind == .auxiliary else { return false }
        return soloed.contains { $0.outputBusID == track.id || ($0.sends ?? []).contains { $0.busID == track.id && $0.level > 0 } }
    }

    /// Every channel's sends and MAIN output, for the engine.
    static func routes(in session: LYLLTHSession) -> [Int: NightshapeAudioEngine.BusRoute] {
        let map = Dictionary(uniqueKeysWithValues: channels(in: session).map { ($0.trackID, $0.index) })
        var routes: [Int: NightshapeAudioEngine.BusRoute] = [:]
        for track in session.tracks {
            guard let index = map[track.id] else { continue }
            var route = NightshapeAudioEngine.BusRoute()
            for send in track.sends ?? [] {
                guard let target = map[send.busID], send.level > 0.0001 else { continue }
                route.sends[target, default: 0] += send.level
            }
            if let output = track.outputBusID, let target = map[output], target != index {
                route.sends[target, default: 0] += 1
                route.toMain = false
            }
            routes[index] = route
        }
        return routes
    }
}
