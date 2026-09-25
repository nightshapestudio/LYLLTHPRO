import Foundation

// MARK: - Parameters

/// One LYLLTH SYNTH parameter as the editor and the document see it. `id` is
/// the core's index (LYSynthCore.h); `key` is what a saved patch stores, so a
/// patch survives parameters being added or renumbered.
struct LYSynthParameter: Hashable {
    let id: Int
    let key: String
    let label: String
    let range: ClosedRange<Float>
    let isStepped: Bool

    func normalized(_ value: Float) -> Float {
        (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.000_1)
    }

    func value(fromNormalized fraction: Float) -> Float {
        let raw = range.lowerBound + min(max(fraction, 0), 1) * (range.upperBound - range.lowerBound)
        return isStepped ? raw.rounded() : raw
    }
}

enum LYSynthParameters {
    static func oscillator(_ index: Int, _ local: Int) -> Int {
        (index == 0 ? LY_OSCA_BASE : LY_OSCB_BASE) + local
    }

    static let all: [LYSynthParameter] = {
        var list: [LYSynthParameter] = []
        func add(_ id: Int, _ key: String, _ label: String, _ range: ClosedRange<Float>, stepped: Bool = false) {
            list.append(LYSynthParameter(id: id, key: key, label: label, range: range, isStepped: stepped))
        }
        for (o, name) in ["a", "b"].enumerated() {
            let b = o == 0 ? LY_OSCA_BASE : LY_OSCB_BASE
            add(b + LY_OSC_ON, "\(name).on", "ON", 0...1, stepped: true)
            add(b + LY_OSC_LEVEL, "\(name).level", "LEVEL", 0...1)
            add(b + LY_OSC_PAN, "\(name).pan", "PAN", -1...1)
            add(b + LY_OSC_OCTAVE, "\(name).octave", "OCT", -3...3, stepped: true)
            add(b + LY_OSC_SEMI, "\(name).semi", "SEMI", -12...12, stepped: true)
            add(b + LY_OSC_FINE, "\(name).fine", "FINE", -100...100)
            add(b + LY_OSC_WTPOS, "\(name).wtpos", "WT POS", 0...1)
            add(b + LY_OSC_UNISON, "\(name).unison", "UNISON", 1...16, stepped: true)
            add(b + LY_OSC_DETUNE, "\(name).detune", "DETUNE", 0...1)
            add(b + LY_OSC_BLEND, "\(name).blend", "BLEND", 0...1)
            add(b + LY_OSC_WIDTH, "\(name).width", "WIDTH", 0...1)
            add(b + LY_OSC_PHASE, "\(name).phase", "PHASE", 0...1)
            add(b + LY_OSC_RANDPHASE, "\(name).rand", "RAND", 0...1)
            add(b + LY_OSC_WARPMODE, "\(name).warpmode", "WARP", 0...Float(LY_WARP_COUNT - 1), stepped: true)
            add(b + LY_OSC_WARPAMT, "\(name).warp", "WARP", 0...1)
        }
        add(LY_SUB_ON, "sub.on", "ON", 0...1, stepped: true)
        add(LY_SUB_LEVEL, "sub.level", "LEVEL", 0...1)
        add(LY_SUB_OCTAVE, "sub.octave", "OCT", 1...2, stepped: true)
        add(LY_SUB_SHAPE, "sub.shape", "SHAPE", 0...2, stepped: true)
        add(LY_NOISE_ON, "noise.on", "ON", 0...1, stepped: true)
        add(LY_NOISE_LEVEL, "noise.level", "LEVEL", 0...1)
        add(LY_NOISE_COLOR, "noise.color", "COLOR", 0...1)
        add(LY_FILTER_ON, "filter.on", "ON", 0...1, stepped: true)
        add(LY_FILTER_TYPE, "filter.type", "TYPE", 0...Float(LY_FILTER_COUNT - 1), stepped: true)
        add(LY_FILTER_CUTOFF, "filter.cutoff", "CUTOFF", 0...1)
        add(LY_FILTER_RES, "filter.res", "RES", 0...1)
        add(LY_FILTER_DRIVE, "filter.drive", "DRIVE", 0...1)
        add(LY_FILTER_KEYTRACK, "filter.keytrack", "KEY", 0...1)
        add(LY_FILTER_ENVAMT, "filter.envamt", "ENV 2", -1...1)
        add(LY_FILTER_MIX, "filter.mix", "MIX", 0...1)
        add(LY_FILTER_ROUTE_A, "filter.routeA", "A", 0...1, stepped: true)
        add(LY_FILTER_ROUTE_B, "filter.routeB", "B", 0...1, stepped: true)
        add(LY_FILTER_ROUTE_SUB, "filter.routeSub", "SUB", 0...1, stepped: true)
        add(LY_FILTER_ROUTE_NOISE, "filter.routeNoise", "NOISE", 0...1, stepped: true)
        for e in 0..<3 {
            let b = LY_ENV1_A + e * 4
            for (k, label) in ["A", "D", "S", "R"].enumerated() {
                add(b + k, "env\(e + 1).\(label.lowercased())", label, 0...1)
            }
        }
        for l in 0..<4 {
            let b = LY_LFO1_SHAPE + l * 4
            add(b, "lfo\(l + 1).shape", "SHAPE", 0...Float(LY_LFO_SHAPE_COUNT - 1), stepped: true)
            add(b + 1, "lfo\(l + 1).rate", "RATE", 0...1)
            add(b + 2, "lfo\(l + 1).sync", "SYNC", 0...1, stepped: true)
            add(b + 3, "lfo\(l + 1).retrig", "RETRIG", 0...1, stepped: true)
        }
        for m in 0..<4 { add(LY_MACRO1 + m, "macro\(m + 1)", "MACRO \(m + 1)", 0...1) }
        add(LY_MODWHEEL, "modwheel", "MOD", 0...1)
        add(LY_VOICES, "voices", "VOICES", 1...16, stepped: true)
        add(LY_GLIDE, "glide", "GLIDE", 0...1)
        add(LY_LEGATO, "legato", "LEGATO", 0...1, stepped: true)
        add(LY_MASTER, "master", "MASTER", 0...1)
        for e in 0..<3 {
            add(LY_ENV1_ACURVE + e * 3, "env\(e + 1).acurve", "A CURVE", -1...1)
            add(LY_ENV1_DCURVE + e * 3, "env\(e + 1).dcurve", "D CURVE", -1...1)
            add(LY_ENV1_RCURVE + e * 3, "env\(e + 1).rcurve", "R CURVE", -1...1)
        }
        for l in 0..<4 {
            add(LY_LFO1_SMOOTH + l, "lfo\(l + 1).smooth", "SMOOTH", 0...1, stepped: true)
            for i in 0..<Int(LY_LFO_POINTS) {
                add(LY_LFO_POINTS_BASE + l * Int(LY_LFO_POINTS) + i, "lfo\(l + 1).p\(i)", "POINT", -1...1)
            }
        }
        add(LY_MPE, "mpe", "MPE", 0...1, stepped: true)
        add(LY_BEND_RANGE, "bendRange", "BEND", 0...24, stepped: true)
        for slot in 0..<Int(LY_MATRIX_SLOTS) {
            let b = LY_MATRIX_BASE + slot * 3
            add(b, "mx\(slot).src", "SOURCE", 0...Float(LY_SRC_COUNT - 1), stepped: true)
            add(b + 1, "mx\(slot).dst", "DESTINATION", 0...Float(LY_DST_COUNT - 1), stepped: true)
            add(b + 2, "mx\(slot).amt", "AMOUNT", -1...1)
        }
        return list
    }()

    static let byID: [Int: LYSynthParameter] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let byKey: [String: LYSynthParameter] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// The core's own defaults, read from a throwaway instance so Swift and
    /// C++ can never disagree about them.
    static let defaults: [Int: Float] = {
        guard let core = lysynth_create(44_100) else { return [:] }
        defer { lysynth_destroy(core) }
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, lysynth_get_param(core, Int32($0.id))) })
    }()
}

// MARK: - Names for choices

enum LYSynthNames {
    static let warps = ["OFF", "SYNC", "BEND +", "BEND −", "MIRROR", "PWM", "FM ← B", "RM ← B", "QUANTIZE"]
    static let warpsB = ["OFF", "SYNC", "BEND +", "BEND −", "MIRROR", "PWM", "FM ← A", "RM ← A", "QUANTIZE"]
    static let filters = ["LP 12", "LP 24", "HP 12", "HP 24", "BAND", "NOTCH", "LADDER"]
    static let lfoShapes = ["SINE", "TRI", "SAW ↑", "SAW ↓", "SQUARE", "S + H", "DRIFT", "DRAW"]
    static let syncDivisions = ["4 BAR", "2 BAR", "1 BAR", "3/4", "1/2", "3/8", "1/4", "3/16", "1/8", "3/32", "1/16", "3/64", "1/32", "1/12", "1/64"]
    static let subShapes = ["SINE", "TRI", "SQUARE"]
    static let tables = ["BASIC SHAPES", "ANALOG", "PWM", "HARMONIC SWEEP", "FORMANT", "FM BELL", "SYNC SWEEP",
                         "ORGAN", "DIGITAL", "VOID FOLD", "GROWL", "CHOIR", "SPECTRAL COMB", "GLASS"]
    static let sources = ["—", "ENV 1", "ENV 2", "ENV 3", "LFO 1", "LFO 2", "LFO 3", "LFO 4", "VELOCITY", "NOTE",
                          "MOD WHEEL", "MACRO 1", "MACRO 2", "MACRO 3", "MACRO 4", "RANDOM", "STEP CUTOFF", "STEP RES",
                          "PRESSURE", "TIMBRE", "PITCH BEND"]
    static let destinations = ["—", "A LEVEL", "A PAN", "A PITCH", "A WT POS", "A DETUNE", "A BLEND", "A WARP",
                               "B LEVEL", "B PAN", "B PITCH", "B WT POS", "B DETUNE", "B BLEND", "B WARP",
                               "SUB LEVEL", "NOISE LEVEL", "CUTOFF", "RESONANCE", "DRIVE", "FILTER MIX",
                               "AMP", "PAN", "PITCH", "LFO 1 RATE", "LFO 2 RATE", "LFO 3 RATE", "LFO 4 RATE"]
}

// MARK: - Patch

/// A saved LYLLTH SYNTH sound. Values are stored by parameter key; anything
/// missing plays at the core's default.
struct LYSynthPatch: Codable, Equatable {
    var name: String
    var values: [String: Float] = [:]
    var tableA: Int = 0
    var tableB: Int = 0
    /// A user or imported wavetable by name; overrides the factory table.
    var customTableA: String? = nil
    var customTableB: String? = nil

    func tableName(_ oscillator: Int) -> String {
        let custom = oscillator == 0 ? customTableA : customTableB
        if let custom { return custom }
        let index = oscillator == 0 ? tableA : tableB
        return LYSynthNames.tables[min(max(index, 0), LYSynthNames.tables.count - 1)]
    }

    func value(_ id: Int) -> Float {
        guard let parameter = LYSynthParameters.byID[id] else { return 0 }
        return values[parameter.key] ?? LYSynthParameters.defaults[id] ?? 0
    }

    mutating func set(_ id: Int, _ value: Float) {
        guard let parameter = LYSynthParameters.byID[id] else { return }
        values[parameter.key] = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
    }

    /// Adds a modulation route in the first empty matrix slot, or updates the
    /// amount if that route already exists. Returns the slot, or nil if full.
    @discardableResult
    mutating func route(source: Int, destination: Int, amount: Float) -> Int? {
        for slot in 0..<Int(LY_MATRIX_SLOTS) {
            let base = LY_MATRIX_BASE + slot * 3
            if Int(value(base)) == source && Int(value(base + 1)) == destination {
                set(base + 2, amount)
                return slot
            }
        }
        for slot in 0..<Int(LY_MATRIX_SLOTS) {
            let base = LY_MATRIX_BASE + slot * 3
            if Int(value(base)) == LY_SRC_NONE || Int(value(base + 1)) == LY_DST_NONE {
                set(base, Float(source))
                set(base + 1, Float(destination))
                set(base + 2, amount)
                return slot
            }
        }
        return nil
    }

    /// Every route into a destination: (slot, source, amount).
    func routes(into destination: Int) -> [(slot: Int, source: Int, amount: Float)] {
        (0..<Int(LY_MATRIX_SLOTS)).compactMap { slot in
            let base = LY_MATRIX_BASE + slot * 3
            let src = Int(value(base))
            guard src != LY_SRC_NONE, Int(value(base + 1)) == destination else { return nil }
            return (slot, src, value(base + 2))
        }
    }
}

// MARK: - Factory sounds

extension LYSynthPatch {
    static let initPatch = LYSynthPatch(name: "INIT")

    private static func make(_ name: String, tableA: Int, tableB: Int = LY_TABLE_BASIC, _ build: (inout LYSynthPatch) -> Void) -> LYSynthPatch {
        var patch = LYSynthPatch(name: name, tableA: tableA, tableB: tableB)
        build(&patch)
        return patch
    }

    private static func osc(_ o: Int, _ local: Int) -> Int { LYSynthParameters.oscillator(o, local) }

    static let factory: [LYSynthPatch] = [
        initPatch,
        make("NIGHT PAD", tableA: LY_TABLE_ANALOG, tableB: LY_TABLE_CHOIR) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.45); p.set(osc(0, LY_OSC_UNISON), 7); p.set(osc(0, LY_OSC_DETUNE), 0.38); p.set(osc(0, LY_OSC_WIDTH), 0.95)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.45); p.set(osc(1, LY_OSC_WTPOS), 0.3); p.set(osc(1, LY_OSC_UNISON), 4); p.set(osc(1, LY_OSC_DETUNE), 0.3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.58); p.set(LY_FILTER_RES, 0.2); p.set(LY_FILTER_ENVAMT, 0.12)
            p.set(LY_ENV1_A, 0.55); p.set(LY_ENV1_D, 0.6); p.set(LY_ENV1_S, 0.85); p.set(LY_ENV1_R, 0.62)
            p.set(LY_ENV2_A, 0.5); p.set(LY_ENV2_D, 0.7); p.set(LY_ENV2_S, 0.4); p.set(LY_ENV2_R, 0.6)
            p.set(LY_LFO1_RATE, 0.22); p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.22)
            p.set(LY_LFO2_SHAPE, Float(LY_LFO_SMOOTH_RANDOM)); p.set(LY_LFO2_RATE, 0.3); p.route(source: LY_SRC_LFO2, destination: LY_DST_CUTOFF, amount: 0.05)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_CUTOFF, amount: 0.35)
            p.set(LY_MASTER, 0.62)
        },
        make("GLASS ARP", tableA: LY_TABLE_GLASS, tableB: LY_TABLE_FM_BELL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.3); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.14)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.32); p.set(osc(1, LY_OSC_OCTAVE), 1); p.set(osc(1, LY_OSC_WTPOS), 0.25)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.62); p.set(LY_FILTER_RES, 0.25); p.set(LY_FILTER_ENVAMT, 0.28)
            p.set(LY_ENV1_A, 0.02); p.set(LY_ENV1_D, 0.45); p.set(LY_ENV1_S, 0.18); p.set(LY_ENV1_R, 0.42)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.36); p.set(LY_ENV2_S, 0.05)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WTPOS, amount: 0.35)
            p.route(source: LY_SRC_VELOCITY, destination: LY_DST_CUTOFF, amount: 0.15)
            p.set(LY_MASTER, 0.66)
        },
        make("SUB PRESSURE", tableA: LY_TABLE_BASIC, tableB: LY_TABLE_ANALOG) { p in
            p.set(osc(0, LY_OSC_LEVEL), 0.8)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.28); p.set(osc(1, LY_OSC_WTPOS), 0.6)
            p.set(LY_SUB_ON, 1); p.set(LY_SUB_LEVEL, 0.5)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.36); p.set(LY_FILTER_RES, 0.16); p.set(LY_FILTER_ENVAMT, 0.26); p.set(LY_FILTER_DRIVE, 0.3)
            p.set(LY_ENV1_A, 0.02); p.set(LY_ENV1_D, 0.4); p.set(LY_ENV1_S, 0.9); p.set(LY_ENV1_R, 0.2)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.35); p.set(LY_ENV2_S, 0.1)
            p.set(LY_VOICES, 1); p.set(LY_LEGATO, 1); p.set(LY_GLIDE, 0.06)
            p.set(LY_MASTER, 0.72)
        },
        make("SYNC SCREAM", tableA: LY_TABLE_SYNC_SWEEP, tableB: LY_TABLE_ANALOG) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.25); p.set(osc(0, LY_OSC_UNISON), 5); p.set(osc(0, LY_OSC_DETUNE), 0.2)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.35); p.set(osc(1, LY_OSC_OCTAVE), -1); p.set(osc(1, LY_OSC_WTPOS), 0.8)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LADDER)); p.set(LY_FILTER_CUTOFF, 0.62); p.set(LY_FILTER_RES, 0.32); p.set(LY_FILTER_DRIVE, 0.4); p.set(LY_FILTER_ENVAMT, 0.18)
            p.set(LY_ENV2_A, 0.08); p.set(LY_ENV2_D, 0.5); p.set(LY_ENV2_S, 0.2)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WTPOS, amount: 0.5)
            p.set(LY_LFO1_SHAPE, Float(LY_LFO_TRIANGLE)); p.set(LY_LFO1_RATE, 0.62)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_PITCH, amount: 0.004)
            p.route(source: LY_SRC_MODWHEEL, destination: LY_DST_A_WARP, amount: 0.6)
            p.set(LY_VOICES, 1); p.set(LY_LEGATO, 1); p.set(LY_GLIDE, 0.08)
            p.set(LY_MASTER, 0.55)
        },
        make("VOID GROWL", tableA: LY_TABLE_GROWL, tableB: LY_TABLE_VOID_FOLD) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.2); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.12)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.5); p.set(osc(1, LY_OSC_OCTAVE), -1)
            p.set(LY_SUB_ON, 1); p.set(LY_SUB_LEVEL, 0.45)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.46); p.set(LY_FILTER_RES, 0.3); p.set(LY_FILTER_DRIVE, 0.5)
            p.set(LY_LFO1_SHAPE, Float(LY_LFO_SAW_DOWN)); p.set(LY_LFO1_SYNC, 1); p.set(LY_LFO1_RATE, 8 / 14); p.set(LY_LFO1_RETRIG, 1)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.6)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_B_WTPOS, amount: 0.4)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.16)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_DRIVE, amount: 0.5)
            p.set(LY_VOICES, 1); p.set(LY_MASTER, 0.55)
        },
        make("FORMANT CHOIR", tableA: LY_TABLE_FORMANT, tableB: LY_TABLE_CHOIR) { p in
            p.set(osc(0, LY_OSC_UNISON), 5); p.set(osc(0, LY_OSC_DETUNE), 0.3)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.4); p.set(osc(1, LY_OSC_OCTAVE), 1); p.set(osc(1, LY_OSC_UNISON), 3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.7)
            p.set(LY_ENV1_A, 0.45); p.set(LY_ENV1_S, 0.9); p.set(LY_ENV1_R, 0.6)
            p.set(LY_LFO1_RATE, 0.18); p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.45)
            p.set(LY_LFO2_RATE, 0.24); p.set(LY_LFO2_SHAPE, Float(LY_LFO_TRIANGLE)); p.route(source: LY_SRC_LFO2, destination: LY_DST_B_WTPOS, amount: 0.4)
            p.set(LY_MASTER, 0.6)
        },
        make("DIGITAL RAIN", tableA: LY_TABLE_DIGITAL, tableB: LY_TABLE_PWM) { p in
            p.set(osc(0, LY_OSC_UNISON), 2); p.set(osc(0, LY_OSC_DETUNE), 0.1)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_OCTAVE), 1)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.66); p.set(LY_FILTER_RES, 0.3)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.35); p.set(LY_ENV1_S, 0.0); p.set(LY_ENV1_R, 0.35)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.3); p.set(LY_ENV2_S, 0)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WTPOS, amount: 0.8)
            p.route(source: LY_SRC_RANDOM, destination: LY_DST_B_WTPOS, amount: 0.5)
            p.set(LY_MASTER, 0.62)
        },
        make("NIGHT KEYS", tableA: LY_TABLE_ORGAN, tableB: LY_TABLE_FM_BELL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.3); p.set(osc(0, LY_OSC_UNISON), 2); p.set(osc(0, LY_OSC_DETUNE), 0.08)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_WTPOS), 0.2)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.64); p.set(LY_FILTER_ENVAMT, 0.14)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.52); p.set(LY_ENV1_S, 0.45); p.set(LY_ENV1_R, 0.36)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_B_LEVEL, amount: 0.4)
            p.set(LY_MASTER, 0.64)
        },
        make("SPECTRAL DRIFT", tableA: LY_TABLE_SPECTRAL_COMB, tableB: LY_TABLE_HARMONIC_SWEEP) { p in
            p.set(osc(0, LY_OSC_UNISON), 6); p.set(osc(0, LY_OSC_DETUNE), 0.3)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.35); p.set(osc(1, LY_OSC_OCTAVE), 1)
            p.set(LY_NOISE_ON, 1); p.set(LY_NOISE_LEVEL, 0.18); p.set(LY_NOISE_COLOR, 0.6)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_BP)); p.set(LY_FILTER_CUTOFF, 0.62); p.set(LY_FILTER_RES, 0.35)
            p.set(LY_ENV1_A, 0.6); p.set(LY_ENV1_S, 0.8); p.set(LY_ENV1_R, 0.7)
            p.set(LY_LFO1_SHAPE, Float(LY_LFO_SMOOTH_RANDOM)); p.set(LY_LFO1_RATE, 0.35)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.6)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.2)
            p.set(LY_MASTER, 0.6)
        }
    ]

    static func factory(named name: String) -> LYSynthPatch? {
        factory.first { $0.name == name }
    }
}
