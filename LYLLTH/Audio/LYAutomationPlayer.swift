import AVFoundation
import Foundation
import NightshapeAudioEngine

/// Plays automation lanes while the song plays. The UI timer only wakes the
/// scheduler; every value is resolved through the same integer sample clock
/// used by offline export and timestamped MIDI.
@MainActor
final class LYAutomationPlayer {
    private let engine: NightshapeAudioEngine
    var instrument: (UUID) -> LYSynthInstrument? = { _ in nil }
    var pluginParameter: (UUID, UInt64, Double, UInt64) -> Void = { _, _, _, _ in }
    /// The song beat being heard, or nil.
    var songBeat: () -> Double? = { nil }
    /// The window the song transport cycles through, or nil when it does
    /// not cycle. Values scheduled ahead wrap with it.
    var window: () -> LYSongWindow? = { nil }

    private var session: LYLLTHSession?
    private var ticker: Timer?
    private var sent: [String: Double] = [:]
    private var touched: Set<String> = []
    private var scheduledUntilHost: UInt64 = 0

    init(engine: NightshapeAudioEngine) {
        self.engine = engine
    }

    func update(session: LYLLTHSession) {
        let previous = self.session
        let hadLanes = previous.map(Self.hasLanes) ?? false
        self.session = session
        // Reschedule from now with the edited lanes. The last scheduled
        // values hold until then, so an edit mid-play never jumps the level.
        engine.clearScheduledAutomation(release: false)
        scheduledUntilHost = 0
        if ticker != nil, hadLanes, !Self.hasLanes(session) {
            engine.clearScheduledAutomation()
            restore()
            return
        }
        // A track that lost its fader or pan lane goes back to its fader.
        guard ticker != nil, let previous else { return }
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        for track in session.tracks {
            guard let channel = channels[track.id],
                  let before = previous.tracks.first(where: { $0.id == track.id }),
                  Self.hasRenderLane(before), !Self.hasRenderLane(track) else { continue }
            engine.clearScheduledAutomation(trackIndex: channel)
            let cap = track.kind == .drumkit || track.kind == .instrument ? 1.0 : 3.98
            engine.setTrackVolume(trackIndex: channel, volume: min(pow(10, session.effectiveVolumeDB(for: track) / 20), cap))
            engine.setTrackPan(trackIndex: channel, pan: track.pan)
            for target in [LYAutomationTarget.volume, .pan] {
                let key = "\(track.id)|\(target)"
                sent[key] = nil
                touched.remove(key)
            }
        }
    }

    private static func hasRenderLane(_ track: LYTrack) -> Bool {
        (track.automation ?? []).contains { $0.isActive && ($0.target == .volume || $0.target == .pan) }
    }

    func start() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        engine.clearScheduledAutomation()
        scheduledUntilHost = 0
        restore()
    }

    private static func hasLanes(_ session: LYLLTHSession) -> Bool {
        session.tracks.contains { ($0.automation ?? []).contains(where: \.isActive) }
    }

    /// The value each automated control takes at a song beat, by channel.
    /// Split out so tests can check exactly what would be sent.
    static func values(in session: LYLLTHSession, at beat: Double) -> [(track: LYTrack, target: LYAutomationTarget, value: Double)] {
        session.tracks.flatMap { track in
            (track.automation ?? []).compactMap { lane -> (LYTrack, LYAutomationTarget, Double)? in
                guard lane.isActive, let value = lane.value(at: beat) else { return nil }
                let range = lane.target.range
                return (track, lane.target, min(max(value, range.lowerBound), range.upperBound))
            }
        }
    }

    private func tick() {
        guard let session, Self.hasLanes(session), let rawBeat = songBeat() else { return }
        let clock = LYTimelineClock(sampleRate: session.sampleRate, bpm: session.bpm)
        let beat = clock.beat(atFrame: clock.frame(atBeat: rawBeat))
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        scheduleRenderControls(session: session, beat: beat, channels: channels)
        var routes: [Int: NightshapeAudioEngine.BusRoute]?
        var racks: [UUID: (rack: LYFXRack, kinds: Set<FXKind>)] = [:]
        for (track, target, value) in Self.values(in: session, at: beat) {
            guard let channel = channels[track.id] else { continue }
            let key = "\(track.id)|\(target)"
            let changed = sent[key].map { abs($0 - value) > 1e-5 } ?? true
            switch target {
            case .volume:
                // Render-thread scheduling below owns volume/pan timing. The
                // static fader stays at unity while the scheduled absolute
                // gain is active.
                guard changed else { continue }
                engine.setTrackVolume(trackIndex: channel, volume: 1)
            case .pan:
                guard changed else { continue }
            case .send(let busID):
                guard changed, let bus = channels[busID] else { continue }
                if routes == nil { routes = LYChannelMap.routes(in: session) }
                routes?[channel, default: NightshapeAudioEngine.BusRoute()].sends[bus] = Float(value)
            case .fx(let fxKey):
                guard changed, let parameter = LYFXAutomation.byKey[fxKey] else { continue }
                var entry = racks[track.id] ?? (track.fx ?? LYFXRack(), [])
                parameter.set(&entry.rack, value)
                entry.kinds.insert(parameter.kind)
                racks[track.id] = entry
            case .synth(let synthKey):
                guard changed, let parameter = LYSynthParameters.byKey[synthKey], let synth = instrument(track.id) else { continue }
                lysynth_set_param(synth.core, Int32(parameter.id), Float(value))
            case .plugin:
                // Scheduled on the render horizon in scheduleRenderControls.
                guard changed else { continue }
            }
            sent[key] = value
            touched.insert(key)
        }
        if let routes {
            // Every send already sent keeps its latest value, not the static one.
            engine.setBusRouting(routes.merging(currentSendOverrides(session, channels: channels), uniquingKeysWith: { base, overrides in
                var merged = base
                for (bus, amount) in overrides.sends where merged.sends[bus] != nil { merged.sends[bus] = amount }
                return merged
            }))
        }
        for (trackID, entry) in racks {
            guard let channel = channels[trackID] else { continue }
            push(entry.kinds, rack: entry.rack, channel: channel, session: session)
        }
    }

    private func scheduleRenderControls(session: LYLLTHSession, beat: Double, channels: [UUID: Int]) {
        let now = mach_absolute_time()
        let leadSeconds = 0.12
        let horizon = now + AVAudioTime.hostTime(forSeconds: leadSeconds)
        let startHost = max(now, scheduledUntilHost)
        guard startHost < horizon else { return }
        let secondsFromNow = startHost > now ? AVAudioTime.seconds(forHostTime: startHost - now) : 0
        let startBeat = beat + secondsFromNow * session.bpm / 60
        let liveClock = LYTimelineClock(sampleRate: session.sampleRate, bpm: session.bpm,
                                        startBeat: startBeat, epochHostTime: startHost)
        let frameCount = Int64(((leadSeconds - secondsFromNow) * session.sampleRate).rounded(.up))
        guard frameCount > 0 else { return }
        // Past the end of a cycling window the song is back at its start.
        let cycle = window()
        func songBeat(atFrame frame: Int64) -> Double {
            let raw = liveClock.beat(atFrame: frame)
            guard let cycle, cycle.lengthBeats > 0, raw >= cycle.endBeat else { return raw }
            return cycle.startBeat + (raw - cycle.startBeat).truncatingRemainder(dividingBy: cycle.lengthBeats)
        }
        var wrapFrames: [Int64] = []
        if let cycle, cycle.lengthBeats > 0 {
            var edge = cycle.endBeat
            while true {
                let frame = Int64(((edge - startBeat) * 60 / max(session.bpm, 1) * session.sampleRate).rounded(.up))
                guard frame < frameCount else { break }
                if frame >= 0 { wrapFrames.append(frame) }
                edge += cycle.lengthBeats
            }
        }

        for track in session.tracks {
            guard let channel = channels[track.id] else { continue }
            let volumeLane = (track.automation ?? []).first { $0.target == .volume && $0.isActive }
            let panLane = (track.automation ?? []).first { $0.target == .pan && $0.isActive }
            if volumeLane != nil || panLane != nil {
                let frames = Set((volumeLane?.samples(from: 0, to: frameCount, clock: liveClock, quantum: 128) ?? []).map(\.frame)
                    + (panLane?.samples(from: 0, to: frameCount, clock: liveClock, quantum: 128) ?? []).map(\.frame)
                    + wrapFrames).sorted()
                for frame in frames {
                    let pointBeat = songBeat(atFrame: frame)
                    let groupOffset = session.effectiveVolumeDB(for: track) - track.volumeDB
                    let cap = track.kind == .drumkit || track.kind == .instrument ? 1.0 : 3.98
                    let gain = volumeLane?.value(at: pointBeat).map { db in
                        let effective = db + groupOffset
                        return min(effective <= -59.9 ? 0 : pow(10, effective / 20), cap)
                    }
                    let pan = panLane?.value(at: pointBeat)
                    let host = startHost + AVAudioTime.hostTime(forSeconds: Double(frame) / max(session.sampleRate, 1))
                    engine.scheduleTrackAutomation(trackIndex: channel, volume: gain, pan: pan, atHostTime: host)
                }
            }
            for lane in (track.automation ?? []) where lane.isActive {
                guard case .plugin(let slotID, let address) = lane.target else { continue }
                let frames = Set(lane.samples(from: 0, to: frameCount, clock: liveClock, quantum: 128).map(\.frame) + wrapFrames).sorted()
                for frame in frames {
                    guard let value = lane.value(at: songBeat(atFrame: frame)) else { continue }
                    let host = startHost + AVAudioTime.hostTime(forSeconds: Double(frame) / max(session.sampleRate, 1))
                    pluginParameter(slotID, address, min(max(value, 0), 1), host)
                }
            }
        }
        scheduledUntilHost = horizon
    }

    /// Sends automated this frame are in `routes`; the others must keep
    /// the value they were last given.
    private func currentSendOverrides(_ session: LYLLTHSession, channels: [UUID: Int]) -> [Int: NightshapeAudioEngine.BusRoute] {
        var out: [Int: NightshapeAudioEngine.BusRoute] = [:]
        for track in session.tracks {
            guard let channel = channels[track.id] else { continue }
            for lane in track.automation ?? [] where lane.isActive {
                guard case .send(let busID) = lane.target, let bus = channels[busID],
                      let value = sent["\(track.id)|\(lane.target)"] else { continue }
                out[channel, default: NightshapeAudioEngine.BusRoute()].sends[bus] = Float(value)
            }
        }
        return out
    }

    private func push(_ kinds: Set<FXKind>, rack: LYFXRack, channel: Int, session: LYLLTHSession) {
        for kind in kinds {
            if kind == .reverb {
                engine.setReverbSend(trackIndex: channel, amount: rack.reverbSend ?? 0)
            } else {
                LYFXBridge.push(kind, rack: rack, index: channel, session: session, engine: engine)
            }
        }
    }

    /// Everything automation moved goes back to the value it is set to.
    private func restore() {
        defer { sent = [:]; touched = [] }
        guard let session, !touched.isEmpty else { return }
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        var routesChanged = false
        for track in session.tracks {
            guard let channel = channels[track.id] else { continue }
            let moved = touched.filter { $0.hasPrefix(track.id.uuidString) }
            guard !moved.isEmpty else { continue }
            let cap = track.kind == .drumkit || track.kind == .instrument ? 1.0 : 3.98
            if moved.contains("\(track.id)|\(LYAutomationTarget.volume)") {
                engine.setTrackVolume(trackIndex: channel, volume: min(pow(10, track.volumeDB / 20), cap))
            }
            if moved.contains("\(track.id)|\(LYAutomationTarget.pan)") {
                engine.setTrackPan(trackIndex: channel, pan: track.pan)
            }
            var kinds: Set<FXKind> = []
            for lane in track.automation ?? [] where moved.contains("\(track.id)|\(lane.target)") {
                switch lane.target {
                case .send: routesChanged = true
                case .fx(let key): if let parameter = LYFXAutomation.byKey[key] { kinds.insert(parameter.kind) }
                case .synth(let key):
                    if let parameter = LYSynthParameters.byKey[key], let synth = instrument(track.id) {
                        lysynth_set_param(synth.core, Int32(parameter.id), (track.synth ?? .initPatch).value(parameter.id))
                    }
                case .plugin:
                    break
                default: break
                }
            }
            if !kinds.isEmpty { push(kinds, rack: track.fx ?? LYFXRack(), channel: channel, session: session) }
        }
        if routesChanged { engine.setBusRouting(LYChannelMap.routes(in: session)) }
    }
}
