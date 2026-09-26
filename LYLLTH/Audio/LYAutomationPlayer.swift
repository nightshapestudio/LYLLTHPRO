import AVFoundation
import Foundation
import NightshapeAudioEngine

/// Plays automation lanes while the song plays: reads each lane at the song
/// beat every display frame and moves the channel, the effect or the LUNATK
/// knob. Only values that changed are sent. When playback stops every
/// automated control goes back to where it is set.
@MainActor
final class LYAutomationPlayer {
    private let engine: NightshapeAudioEngine
    var instrument: (UUID) -> LYSynthInstrument? = { _ in nil }
    /// The song beat being heard, or nil.
    var songBeat: () -> Double? = { nil }

    private var session: LYLLTHSession?
    private var ticker: Timer?
    private var sent: [String: Double] = [:]
    private var touched: Set<String> = []

    init(engine: NightshapeAudioEngine) {
        self.engine = engine
    }

    func update(session: LYLLTHSession) {
        let hadLanes = self.session.map(Self.hasLanes) ?? false
        self.session = session
        if ticker != nil, hadLanes, !Self.hasLanes(session) { restore() }
    }

    func start() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
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
        guard let session, Self.hasLanes(session), let beat = songBeat() else { return }
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        var routes: [Int: NightshapeAudioEngine.BusRoute]?
        var racks: [UUID: (rack: LYFXRack, kinds: Set<FXKind>)] = [:]
        for (track, target, value) in Self.values(in: session, at: beat) {
            guard let channel = channels[track.id] else { continue }
            let key = "\(track.id)|\(target)"
            let changed = sent[key].map { abs($0 - value) > 1e-5 } ?? true
            switch target {
            case .volume:
                guard changed else { continue }
                let cap = track.kind == .drumkit || track.kind == .instrument ? 1.0 : 3.98
                engine.setTrackVolume(trackIndex: channel, volume: min(value <= -59.9 ? 0 : pow(10, value / 20), cap))
            case .pan:
                guard changed else { continue }
                engine.setTrackPan(trackIndex: channel, pan: value)
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
                default: break
                }
            }
            if !kinds.isEmpty { push(kinds, rack: track.fx ?? LYFXRack(), channel: channel, session: session) }
        }
        if routesChanged { engine.setBusRouting(LYChannelMap.routes(in: session)) }
    }
}
