import Foundation
import AVFoundation

/// What an automation lane moves.
enum LYAutomationTarget: Codable, Hashable {
    case volume
    case pan
    /// The track's send into an AUX RETURN, by the bus's track id.
    case send(UUID)
    /// A NIGHTSHAPE effect parameter on the track, by `LYFXAutomation` key.
    case fx(String)
    /// A LUNATK parameter, by its patch key.
    case synth(String)
    /// A hosted Audio Unit parameter. Values are normalized 0...1.
    case plugin(UUID, UInt64)
}

struct LYAutomationPoint: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Song beats.
    var beat: Double
    /// In the target's own units: dB, pan, send level, parameter value.
    var value: Double
}

struct LYAutomationLane: Codable, Equatable, Identifiable {
    var id = UUID()
    var target: LYAutomationTarget
    var points: [LYAutomationPoint] = []
    /// Off: the lane is kept but the control stays where it is set.
    var isBypassed: Bool? = nil

    var isActive: Bool { isBypassed != true && !points.isEmpty }

    /// The value at a song beat: straight lines between points, the first
    /// point's value before it and the last one's after.
    func value(at beat: Double) -> Double? {
        guard let first = points.first else { return nil }
        if beat <= first.beat { return first.value }
        var previous = first
        for point in points.dropFirst() {
            if beat < point.beat {
                let span = point.beat - previous.beat
                guard span > 1e-9 else { return point.value }
                return previous.value + (point.value - previous.value) * (beat - previous.beat) / span
            }
            previous = point
        }
        return previous.value
    }

    mutating func sortPoints() {
        points.sort { $0.beat < $1.beat }
    }

    /// Adds or replaces one sample without growing a lane with multiple points
    /// at effectively the same sample position.
    mutating func write(value: Double, at beat: Double, clock: LYTimelineClock) {
        let clampedBeat = max(0, beat)
        let frame = clock.frame(atBeat: clampedBeat)
        let value = min(max(value, target.range.lowerBound), target.range.upperBound)
        if let index = points.firstIndex(where: { clock.frame(atBeat: $0.beat) == frame }) {
            points[index].beat = clampedBeat
            points[index].value = value
        } else {
            points.append(LYAutomationPoint(beat: clampedBeat, value: value))
        }
        sortPoints()
    }
}

/// The one conversion used by live note scheduling, automation playback, and
/// offline rendering. All musical time is ultimately resolved to an integer
/// sample frame before it is handed to a renderer or host clock.
struct LYTimelineClock: Equatable {
    var sampleRate: Double
    var bpm: Double
    var startBeat: Double = 0
    var epochHostTime: UInt64 = 0

    var framesPerBeat: Double { max(sampleRate, 1) * 60 / max(bpm, 1) }

    func frame(atBeat beat: Double) -> Int64 {
        Int64(((beat - startBeat) * framesPerBeat).rounded())
    }

    func beat(atFrame frame: Int64) -> Double {
        startBeat + Double(frame) / framesPerBeat
    }

    func hostTime(atBeat beat: Double) -> UInt64 {
        let seconds = Double(max(0, frame(atBeat: beat))) / max(sampleRate, 1)
        return epochHostTime + AVAudioTime.hostTime(forSeconds: seconds)
    }

    func beat(atHostTime hostTime: UInt64) -> Double {
        guard hostTime > epochHostTime else { return startBeat }
        let seconds = AVAudioTime.seconds(forHostTime: hostTime - epochHostTime)
        return startBeat + seconds * max(bpm, 1) / 60
    }
}

struct LYAutomationSample: Equatable {
    var frame: Int64
    var beat: Double
    var value: Double
}

extension LYAutomationLane {
    /// Deterministic automation samples for a render interval. Point frames are
    /// always included, and long ramps are sampled at the renderer quantum so
    /// live and offline paths evaluate the same curve at the same frame.
    func samples(
        from startFrame: Int64,
        to endFrame: Int64,
        clock: LYTimelineClock,
        quantum: Int64 = 128
    ) -> [LYAutomationSample] {
        guard isActive, endFrame > startFrame else { return [] }
        let step = max(1, quantum)
        var frames = Set<Int64>()
        var frame = startFrame
        while frame < endFrame {
            frames.insert(frame)
            frame += step
        }
        frames.insert(endFrame - 1)
        for point in points {
            let pointFrame = clock.frame(atBeat: point.beat)
            if pointFrame >= startFrame, pointFrame < endFrame { frames.insert(pointFrame) }
        }
        return frames.sorted().compactMap { frame in
            let beat = clock.beat(atFrame: frame)
            return value(at: beat).map { raw in
                LYAutomationSample(
                    frame: frame,
                    beat: beat,
                    value: min(max(raw, target.range.lowerBound), target.range.upperBound)
                )
            }
        }
    }
}

/// Stateful write-mode semantics independent of the UI control driving them.
/// The caller samples this at transport frames; TOUCH releases immediately,
/// LATCH keeps the last value, and WRITE records for the whole pass.
struct LYAutomationWritePass {
    var mode: LYAutomationMode
    private(set) var isTouching = false
    private(set) var latchedValue: Double?

    mutating func beginTouch(value: Double) {
        isTouching = true
        latchedValue = value
    }

    mutating func move(to value: Double) {
        guard isTouching || mode == .write else { return }
        latchedValue = value
    }

    mutating func endTouch() {
        isTouching = false
        if mode == .touch { latchedValue = nil }
    }

    mutating func finish() {
        isTouching = false
        latchedValue = nil
    }

    func valueToWrite(staticValue: Double) -> Double? {
        switch mode {
        case .read: return nil
        case .touch: return isTouching ? latchedValue : nil
        case .latch: return latchedValue
        case .write: return latchedValue ?? staticValue
        }
    }
}

/// The effect parameters a lane can move. Only continuous controls: a
/// switch or a mode flipping at display rate would click.
enum LYFXAutomation {
    struct Parameter {
        let key: String
        let kind: FXKind
        let label: String
        let range: ClosedRange<Double>
        let get: (LYFXRack) -> Double
        let set: (inout LYFXRack, Double) -> Void
    }

    static let all: [Parameter] = [
        Parameter(key: "reverb.send", kind: .reverb, label: "REVERB SEND", range: 0...1,
                  get: { Double($0.reverbSend ?? 0) }, set: { $0.reverbSend = Float($1) }),
        Parameter(key: "filter.cutoff", kind: .filter, label: "FILTER CUTOFF", range: 0...1,
                  get: { Double(($0.filter ?? FilterState()).cutoff) }, set: { rack, v in var s = rack.filter ?? FilterState(); s.cutoff = Float(v); rack.filter = s }),
        Parameter(key: "filter.resonance", kind: .filter, label: "FILTER RESONANCE", range: 0...1,
                  get: { Double(($0.filter ?? FilterState()).resonance) }, set: { rack, v in var s = rack.filter ?? FilterState(); s.resonance = Float(v); rack.filter = s }),
        Parameter(key: "filter.drive", kind: .filter, label: "FILTER DRIVE", range: 0...1,
                  get: { Double(($0.filter ?? FilterState()).drive) }, set: { rack, v in var s = rack.filter ?? FilterState(); s.drive = Float(v); rack.filter = s }),
        Parameter(key: "delay.mix", kind: .tempoDelay, label: "DELAY MIX", range: 0...1,
                  get: { Double(($0.tempoDelay ?? TempoDelayState()).mix) }, set: { rack, v in var s = rack.tempoDelay ?? TempoDelayState(); s.mix = Float(v); rack.tempoDelay = s }),
        Parameter(key: "delay.feedback", kind: .tempoDelay, label: "DELAY FEEDBACK", range: 0...0.95,
                  get: { Double(($0.tempoDelay ?? TempoDelayState()).feedback) }, set: { rack, v in var s = rack.tempoDelay ?? TempoDelayState(); s.feedback = Float(v); rack.tempoDelay = s }),
        Parameter(key: "decim.destroy", kind: .decim, label: "DECIMATOR DESTROY", range: 0...1,
                  get: { Double(($0.decimator ?? .neutral).destroy) }, set: { rack, v in var s = rack.decimator ?? .neutral; s.destroy = Float(v); rack.decimator = s }),
        Parameter(key: "decim.crush", kind: .decim, label: "DECIMATOR CRUSH", range: 0...1,
                  get: { Double(($0.decimator ?? .neutral).crush) }, set: { rack, v in var s = rack.decimator ?? .neutral; s.crush = Float(v); rack.decimator = s }),
        Parameter(key: "tape.drive", kind: .tape, label: "TAPE DRIVE", range: 0...1,
                  get: { Double(($0.tape ?? .neutral).drive) }, set: { rack, v in var s = rack.tape ?? .neutral; s.drive = Float(v); rack.tape = s }),
        Parameter(key: "tape.mix", kind: .tape, label: "TAPE MIX", range: 0...1,
                  get: { Double(($0.tape ?? .neutral).mix) }, set: { rack, v in var s = rack.tape ?? .neutral; s.mix = Float(v); rack.tape = s }),
        Parameter(key: "chorus.mix", kind: .chorus, label: "CHORUS MIX", range: 0...1,
                  get: { Double(($0.chorus ?? .neutral).mix) }, set: { rack, v in var s = rack.chorus ?? .neutral; s.mix = Float(v); rack.chorus = s }),
        Parameter(key: "flanger.mix", kind: .flanger, label: "FLANGER MIX", range: 0...1,
                  get: { Double(($0.flanger ?? .neutral).mix) }, set: { rack, v in var s = rack.flanger ?? .neutral; s.mix = Float(v); rack.flanger = s }),
    ]

    static let byKey: [String: Parameter] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
}

/// The LUNATK knobs offered for automation, grouped the way the editor
/// shows them. Every continuous parameter can be automated; these are the
/// ones worth finding quickly.
enum LYSynthAutomation {
    static let groups: [(title: String, keys: [String])] = [
        ("MACROS", ["macro1", "macro2", "macro3", "macro4"]),
        ("FILTER", ["filter.cutoff", "filter.res", "filter.drive", "filter.envamt", "filter.mix", "filter2.cutoff", "filter2.res"]),
        ("OSCILLATORS", ["a.level", "a.wtpos", "a.warp", "a.detune", "b.level", "b.wtpos", "b.warp", "b.detune", "sub.level", "noise.level"]),
        ("FX", ["dist.drive", "dist.mix", "chorus.mix", "delay.mix", "delay.feedback", "reverb.mix", "reverb.size", "fxfilter.cutoff"]),
        ("GLOBAL", ["master", "glide", "modwheel"]),
    ].map { group in (group.0, group.1.filter { key in LYSynthParameters.byKey[key].map { !$0.isStepped } ?? false }) }
}

extension LYAutomationTarget {
    /// The range a lane is drawn over.
    var range: ClosedRange<Double> {
        switch self {
        case .volume: return -60...6
        case .pan: return -1...1
        case .send: return 0...1
        case .fx(let key): return LYFXAutomation.byKey[key]?.range ?? 0...1
        case .synth(let key):
            guard let parameter = LYSynthParameters.byKey[key] else { return 0...1 }
            return Double(parameter.range.lowerBound)...Double(parameter.range.upperBound)
        case .plugin: return 0...1
        }
    }

    func title(in session: LYLLTHSession) -> String {
        switch self {
        case .volume: return "VOLUME"
        case .pan: return "PAN"
        case .send(let id): return "SEND · " + (session.tracks.first { $0.id == id }?.name ?? "BUS")
        case .fx(let key): return LYFXAutomation.byKey[key]?.label ?? key.uppercased()
        case .synth(let key): return "LUNATK · " + LYSynthAutomation.label(key)
        case .plugin: return "AUDIO UNIT PARAMETER"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .volume: return value <= -59.9 ? "−∞ DB" : String(format: "%+.1f DB", value)
        case .pan:
            if abs(value) < 0.01 { return "C" }
            return String(format: "%@%.0f", value < 0 ? "L" : "R", abs(value) * 100)
        case .synth(let key) where key == "tune": return String(format: "%+.0f CT", value)
        default:
            let range = self.range
            let unit = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1e-9)
            return range.lowerBound < 0 ? String(format: "%+.2f", value) : String(format: "%.0f%%", unit * 100)
        }
    }

    /// Where the control sits without automation, the value a new lane starts from.
    func staticValue(of track: LYTrack) -> Double {
        switch self {
        case .volume: return track.volumeDB
        case .pan: return track.pan
        case .send(let id): return (track.sends ?? []).first { $0.busID == id }.map { Double($0.level) } ?? 0
        case .fx(let key): return LYFXAutomation.byKey[key].map { $0.get(track.fx ?? LYFXRack()) } ?? 0
        case .synth(let key):
            guard let parameter = LYSynthParameters.byKey[key] else { return 0 }
            return Double((track.synth ?? .initPatch).value(parameter.id))
        case .plugin: return 0
        }
    }
}

extension LYSynthAutomation {
    static func label(_ key: String) -> String {
        guard let parameter = LYSynthParameters.byKey[key] else { return key.uppercased() }
        let section = key.split(separator: ".").first.map(String.init) ?? ""
        let prefix: String
        switch section {
        case "a": prefix = "OSC A "
        case "b": prefix = "OSC B "
        case "filter": prefix = "FILTER 1 "
        case "filter2": prefix = "FILTER 2 "
        case "sub": prefix = "SUB "
        case "noise": prefix = "NOISE "
        case "dist": prefix = "DISTORTION "
        case "chorus": prefix = "CHORUS "
        case "delay": prefix = "DELAY "
        case "reverb": prefix = "REVERB "
        case "fxfilter": prefix = "FX FILTER "
        default: prefix = ""
        }
        return prefix + parameter.label
    }
}
