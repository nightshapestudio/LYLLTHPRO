import Foundation

// MARK: - Parameters

/// One LUNATK parameter as the editor and the document see it. `id` is
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

    static func lfo(_ index: Int, _ field: Int) -> Int {
        LY_LFO1_SHAPE + index * Int(LY_LFO_STRIDE) + (field - LY_LFO1_SHAPE)
    }

    static func matrix(_ slot: Int, _ field: Int) -> Int {
        LY_MATRIX_BASE + slot * Int(LY_MATRIX_STRIDE) + field
    }

    static func insert(_ index: Int, _ field: Int) -> Int {
        field + index * Int(LY_INS_STRIDE)
    }

    static func performer(_ index: Int, _ field: Int) -> Int {
        field + index * Int(LY_PERF_STRIDE)
    }

    static func performerStep(_ index: Int, _ pattern: Int, _ step: Int) -> Int {
        LY_PERF_VALUES_BASE + (index * Int(LY_PERF_PATTERNS) + pattern) * Int(LY_PERF_MAX_STEPS) + step
    }

    static func performerShape(_ index: Int, _ pattern: Int, _ step: Int) -> Int {
        LY_PERF_SHAPES_BASE + (index * Int(LY_PERF_PATTERNS) + pattern) * Int(LY_PERF_MAX_STEPS) + step
    }

    static func trackerPoint(_ index: Int, _ point: Int) -> Int {
        LY_TRACK_POINTS_BASE + index * Int(LY_TRACK_POINTS) + point
    }

    // Keys are what a saved patch stores. Never rename one.
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
            add(b + LY_OSC_WARPMODE2, "\(name).warpmode2", "WARP 2", 0...Float(LY_WARP_COUNT - 1), stepped: true)
            add(b + LY_OSC_WARPAMT2, "\(name).warp2", "WARP 2", 0...1)
            add(b + LY_OSC_UNIMODE, "\(name).unimode", "MODE", 0...Float(LY_UNI_COUNT - 1), stepped: true)
            add(b + LY_OSC_STACK, "\(name).stack", "STACK", 0...Float(LY_STACK_COUNT - 1), stepped: true)
        }
        add(LY_SUB_ON, "sub.on", "ON", 0...1, stepped: true)
        add(LY_SUB_LEVEL, "sub.level", "LEVEL", 0...1)
        add(LY_SUB_OCTAVE, "sub.octave", "OCT", 1...2, stepped: true)
        add(LY_SUB_SHAPE, "sub.shape", "SHAPE", 0...3, stepped: true)
        add(LY_SUB_PAN, "sub.pan", "PAN", -1...1)
        add(LY_NOISE_ON, "noise.on", "ON", 0...1, stepped: true)
        add(LY_NOISE_LEVEL, "noise.level", "LEVEL", 0...1)
        add(LY_NOISE_COLOR, "noise.color", "COLOR", 0...1)
        add(LY_NOISE_TYPE, "noise.type", "TYPE", 0...Float(LY_NOISE_COUNT - 1), stepped: true)
        add(LY_NOISE_PITCH, "noise.pitch", "PITCH", 0...1)
        add(LY_NOISE_KEYTRACK, "noise.keytrack", "KEY", 0...1, stepped: true)
        add(LY_NOISE_PAN, "noise.pan", "PAN", -1...1)
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
        add(LY_FILTER_PAN, "filter.pan", "PAN", -1...1)
        add(LY_F2_ON, "filter2.on", "ON", 0...1, stepped: true)
        add(LY_F2_TYPE, "filter2.type", "TYPE", 0...Float(LY_FILTER_COUNT - 1), stepped: true)
        add(LY_F2_CUTOFF, "filter2.cutoff", "CUTOFF", 0...1)
        add(LY_F2_RES, "filter2.res", "RES", 0...1)
        add(LY_F2_DRIVE, "filter2.drive", "DRIVE", 0...1)
        add(LY_F2_KEYTRACK, "filter2.keytrack", "KEY", 0...1)
        add(LY_F2_ENVAMT, "filter2.envamt", "ENV 3", -1...1)
        add(LY_F2_MIX, "filter2.mix", "MIX", 0...1)
        add(LY_FILTER_ROUTING, "filter.routing", "ROUTING", 0...1, stepped: true)
        for e in 0..<4 {
            let b = LY_ENV1_A + e * 4
            for (k, label) in ["A", "D", "S", "R"].enumerated() {
                add(b + k, "env\(e + 1).\(label.lowercased())", label, 0...1)
            }
            add(LY_ENV1_H + e, "env\(e + 1).h", "HOLD", 0...1)
            add(LY_ENV1_ACURVE + e * 3, "env\(e + 1).acurve", "A CURVE", -1...1)
            add(LY_ENV1_DCURVE + e * 3, "env\(e + 1).dcurve", "D CURVE", -1...1)
            add(LY_ENV1_RCURVE + e * 3, "env\(e + 1).rcurve", "R CURVE", -1...1)
        }
        for l in 0..<4 {
            let n = "lfo\(l + 1)"
            add(lfo(l, LY_LFO1_SHAPE), "\(n).shape", "SHAPE", 0...Float(LY_LFO_SHAPE_COUNT - 1), stepped: true)
            add(lfo(l, LY_LFO1_RATE), "\(n).rate", "RATE", 0...1)
            add(lfo(l, LY_LFO1_SYNC), "\(n).sync", "SYNC", 0...1, stepped: true)
            add(lfo(l, LY_LFO1_RETRIG), "\(n).retrig", "MODE", 0...Float(LY_LFOMODE_COUNT - 1), stepped: true)
            add(lfo(l, LY_LFO1_SMOOTH), "\(n).smooth", "SMOOTH", 0...1, stepped: true)
            add(lfo(l, LY_LFO1_PHASE), "\(n).phase", "PHASE", 0...1)
            add(lfo(l, LY_LFO1_DELAY), "\(n).delay", "DELAY", 0...1)
            add(lfo(l, LY_LFO1_RISE), "\(n).rise", "RISE", 0...1)
            for i in 0..<Int(LY_LFO_POINTS) {
                add(LY_LFO_POINTS_BASE + l * Int(LY_LFO_POINTS) + i, "\(n).p\(i)", "POINT", -1...1)
            }
        }
        for m in 0..<4 { add(LY_MACRO1 + m, "macro\(m + 1)", "MACRO \(m + 1)", 0...1) }
        add(LY_MODWHEEL, "modwheel", "MOD", 0...1)
        add(LY_VOICES, "voices", "VOICES", 1...16, stepped: true)
        add(LY_GLIDE, "glide", "GLIDE", 0...1)
        add(LY_LEGATO, "legato", "LEGATO", 0...1, stepped: true)
        add(LY_GLIDE_ALWAYS, "glideAlways", "ALWAYS", 0...1, stepped: true)
        add(LY_MASTER, "master", "MASTER", 0...1)
        add(LY_TUNE, "tune", "TUNE", -100...100)
        add(LY_VEL_SENS, "velSens", "VELOCITY", 0...1)
        add(LY_MPE, "mpe", "MPE", 0...1, stepped: true)
        add(LY_BEND_RANGE, "bendRange", "BEND", 0...24, stepped: true)
        add(LY_ARP_ON, "arp.on", "ON", 0...1, stepped: true)
        add(LY_ARP_MODE, "arp.mode", "MODE", 0...Float(LY_ARP_COUNT - 1), stepped: true)
        add(LY_ARP_RATE, "arp.rate", "RATE", 0...1)
        add(LY_ARP_OCTAVES, "arp.octaves", "OCTAVES", 1...4, stepped: true)
        add(LY_ARP_GATE, "arp.gate", "GATE", 0.05...1)
        add(LY_ARP_SWING, "arp.swing", "SWING", 0...1)
        add(LY_ARP_LATCH, "arp.latch", "LATCH", 0...1, stepped: true)
        for i in 0..<Int(LY_FX_COUNT) {
            add(LY_FX_ORDER + i, "fx.order\(i)", "ORDER", 0...Float(LY_FX_COUNT - 1), stepped: true)
        }
        let fx: [(Int, String, String, ClosedRange<Float>, Bool)] = [
            (LY_HYPER_ON, "hyper.on", "ON", 0...1, true), (LY_HYPER_RATE, "hyper.rate", "RATE", 0...1, false),
            (LY_HYPER_DETUNE, "hyper.detune", "DETUNE", 0...1, false), (LY_HYPER_VOICES, "hyper.voices", "UNISON", 0...1, false),
            (LY_HYPER_MIX, "hyper.mix", "MIX", 0...1, false), (LY_HYPER_DIM_SIZE, "hyper.dimSize", "SIZE", 0...1, false),
            (LY_HYPER_DIM_MIX, "hyper.dimMix", "DIMENSION", 0...1, false),
            (LY_DIST_ON, "dist.on", "ON", 0...1, true), (LY_DIST_MODE, "dist.mode", "MODE", 0...Float(LY_DIST_COUNT - 1), true),
            (LY_DIST_DRIVE, "dist.drive", "DRIVE", 0...1, false), (LY_DIST_TONE, "dist.tone", "TONE", 0...1, false),
            (LY_DIST_MIX, "dist.mix", "MIX", 0...1, false),
            (LY_FLANGER_ON, "flanger.on", "ON", 0...1, true), (LY_FLANGER_RATE, "flanger.rate", "RATE", 0...1, false),
            (LY_FLANGER_DEPTH, "flanger.depth", "DEPTH", 0...1, false), (LY_FLANGER_FEEDBACK, "flanger.feedback", "FEEDBACK", 0...1, false),
            (LY_FLANGER_MIX, "flanger.mix", "MIX", 0...1, false),
            (LY_PHASER_ON, "phaser.on", "ON", 0...1, true), (LY_PHASER_RATE, "phaser.rate", "RATE", 0...1, false),
            (LY_PHASER_DEPTH, "phaser.depth", "DEPTH", 0...1, false), (LY_PHASER_FREQ, "phaser.freq", "FREQ", 0...1, false),
            (LY_PHASER_FEEDBACK, "phaser.feedback", "FEEDBACK", 0...1, false), (LY_PHASER_MIX, "phaser.mix", "MIX", 0...1, false),
            (LY_CHORUS_ON, "chorus.on", "ON", 0...1, true), (LY_CHORUS_RATE, "chorus.rate", "RATE", 0...1, false),
            (LY_CHORUS_DELAY, "chorus.delay", "DELAY", 0...1, false), (LY_CHORUS_DEPTH, "chorus.depth", "DEPTH", 0...1, false),
            (LY_CHORUS_FEEDBACK, "chorus.feedback", "FEEDBACK", 0...1, false), (LY_CHORUS_TONE, "chorus.tone", "TONE", 0...1, false),
            (LY_CHORUS_MIX, "chorus.mix", "MIX", 0...1, false),
            (LY_DELAY_ON, "delay.on", "ON", 0...1, true), (LY_DELAY_TIME, "delay.time", "TIME", 0...1, false),
            (LY_DELAY_FEEDBACK, "delay.feedback", "FEEDBACK", 0...1, false), (LY_DELAY_PINGPONG, "delay.pingpong", "PING-PONG", 0...1, true),
            (LY_DELAY_WIDTH, "delay.width", "OFFSET", 0...1, false), (LY_DELAY_LOWCUT, "delay.lowcut", "LOW CUT", 0...1, false),
            (LY_DELAY_HIGHCUT, "delay.highcut", "HIGH CUT", 0...1, false), (LY_DELAY_MIX, "delay.mix", "MIX", 0...1, false),
            (LY_COMP_ON, "comp.on", "ON", 0...1, true), (LY_COMP_MODE, "comp.mode", "MODE", 0...1, true),
            (LY_COMP_THRESHOLD, "comp.threshold", "THRESHOLD", 0...1, false), (LY_COMP_RATIO, "comp.ratio", "RATIO", 0...1, false),
            (LY_COMP_ATTACK, "comp.attack", "ATTACK", 0...1, false), (LY_COMP_RELEASE, "comp.release", "RELEASE", 0...1, false),
            (LY_COMP_GAIN, "comp.gain", "GAIN", 0...1, false), (LY_COMP_DEPTH, "comp.depth", "DEPTH", 0...1, false),
            (LY_COMP_MIX, "comp.mix", "MIX", 0...1, false),
            (LY_EQ_ON, "eq.on", "ON", 0...1, true), (LY_EQ_LOW_FREQ, "eq.lowFreq", "LOW", 0...1, false),
            (LY_EQ_LOW_GAIN, "eq.lowGain", "LOW GAIN", -1...1, false), (LY_EQ_MID_FREQ, "eq.midFreq", "MID", 0...1, false),
            (LY_EQ_MID_GAIN, "eq.midGain", "MID GAIN", -1...1, false), (LY_EQ_MID_Q, "eq.midQ", "Q", 0...1, false),
            (LY_EQ_HIGH_FREQ, "eq.highFreq", "HIGH", 0...1, false), (LY_EQ_HIGH_GAIN, "eq.highGain", "HIGH GAIN", -1...1, false),
            (LY_FXF_ON, "fxfilter.on", "ON", 0...1, true), (LY_FXF_TYPE, "fxfilter.type", "TYPE", 0...Float(LY_FXF_COUNT - 1), true),
            (LY_FXF_CUTOFF, "fxfilter.cutoff", "CUTOFF", 0...1, false), (LY_FXF_RES, "fxfilter.res", "RES", 0...1, false),
            (LY_FXF_DRIVE, "fxfilter.drive", "DRIVE", 0...1, false), (LY_FXF_MIX, "fxfilter.mix", "MIX", 0...1, false),
            (LY_REVERB_ON, "reverb.on", "ON", 0...1, true), (LY_REVERB_MODE, "reverb.mode", "MODE", 0...1, true),
            (LY_REVERB_SIZE, "reverb.size", "SIZE", 0...1, false), (LY_REVERB_DECAY, "reverb.decay", "DECAY", 0...1, false),
            (LY_REVERB_DAMP, "reverb.damp", "DAMP", 0...1, false), (LY_REVERB_WIDTH, "reverb.width", "WIDTH", 0...1, false),
            (LY_REVERB_PREDELAY, "reverb.predelay", "PRE-DELAY", 0...1, false), (LY_REVERB_MIX, "reverb.mix", "MIX", 0...1, false),
        ]
        for item in fx { add(item.0, item.1, item.2, item.3, stepped: item.4) }
        for slot in 0..<Int(LY_MATRIX_SLOTS) {
            add(matrix(slot, LY_MX_SOURCE), "mx\(slot).src", "SOURCE", 0...Float(LY_SRC_COUNT - 1), stepped: true)
            add(matrix(slot, LY_MX_DEST), "mx\(slot).dst", "DESTINATION", 0...Float(LY_DST_COUNT - 1), stepped: true)
            add(matrix(slot, LY_MX_AMOUNT), "mx\(slot).amt", "AMOUNT", -1...1)
            add(matrix(slot, LY_MX_AUX), "mx\(slot).aux", "AUX", 0...Float(LY_SRC_COUNT - 1), stepped: true)
            add(matrix(slot, LY_MX_CURVE), "mx\(slot).curve", "CURVE", -1...1)
            add(matrix(slot, LY_MX_BIPOLAR), "mx\(slot).bi", "BIPOLAR", 0...1, stepped: true)
        }
        // Added later; their ids come after everything above.
        for m in 4..<8 { add(LY_MACRO5 + (m - 4), "macro\(m + 1)", "MACRO \(m + 1)", 0...1) }
        add(LY_FB_AMOUNT, "fb.amount", "AMOUNT", 0...1)
        add(LY_FB_DRIVE, "fb.drive", "DRIVE", 0...1)
        add(LY_FB_TONE, "fb.tone", "TONE", 0...1)
        for k in 0..<2 {
            let b = insert(k, LY_INS1_TYPE), n = "ins\(k + 1)"
            add(b, "\(n).type", "TYPE", 0...Float(LY_INS_COUNT - 1), stepped: true)
            add(insert(k, LY_INS1_POSITION), "\(n).position", "AFTER FILTER", 0...1, stepped: true)
            add(insert(k, LY_INS1_AMOUNT), "\(n).amount", "AMOUNT", 0...1)
            add(insert(k, LY_INS1_FREQ), "\(n).freq", "FREQ", 0...1)
            add(insert(k, LY_INS1_MIX), "\(n).mix", "MIX", 0...1)
        }
        for k in 0..<2 {
            let n = "perf\(k + 1)"
            add(performer(k, LY_PERF1_MODE), "\(n).mode", "MODE", 0...Float(LY_PERFMODE_COUNT - 1), stepped: true)
            add(performer(k, LY_PERF1_RATE), "\(n).rate", "RATE", 0...1)
            add(performer(k, LY_PERF1_STEPS), "\(n).steps", "STEPS", 1...16, stepped: true)
            add(performer(k, LY_PERF1_PATTERN), "\(n).pattern", "PATTERN", 0...Float(LY_PERF_PATTERNS - 1), stepped: true)
        }
        add(LY_PERF_KEYSWITCH, "perf.keyswitch", "SWITCH KEYS", 0...1, stepped: true)
        add(LY_PERF_KEYROOT, "perf.keyroot", "SWITCH ROOT", 0...124, stepped: true)
        add(LY_TRACK1_SOURCE, "track1.source", "SOURCE", 0...Float(LY_SRC_COUNT - 1), stepped: true)
        add(LY_TRACK2_SOURCE, "track2.source", "SOURCE", 0...Float(LY_SRC_COUNT - 1), stepped: true)
        for k in 0..<2 {
            for pattern in 0..<Int(LY_PERF_PATTERNS) {
                let letter = ["A", "B", "C", "D"][pattern]
                for step in 0..<Int(LY_PERF_MAX_STEPS) {
                    add(performerStep(k, pattern, step), "perf\(k + 1).\(letter.lowercased()).v\(step)", "\(letter) STEP \(step + 1)", -1...1)
                    add(performerShape(k, pattern, step), "perf\(k + 1).\(letter.lowercased()).s\(step)", "\(letter) SHAPE \(step + 1)",
                        0...Float(LY_PSTEP_COUNT - 1), stepped: true)
                }
            }
        }
        for t in 0..<2 {
            for i in 0..<Int(LY_TRACK_POINTS) {
                add(trackerPoint(t, i), "track\(t + 1).t\(i)", "POINT \(i + 1)", -1...1)
            }
        }
        add(LY_CHORUS_MODE, "chorus.mode", "MODE", 0...Float(LY_CHORUS_MODE_COUNT - 1), stepped: true)
        add(LY_CHORUS_WIDTH, "chorus.width", "WIDTH", 0...1)
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

/// Names shown for each choice, indexed by the core's value. Where the core's
/// values run in the order they were added, `order` lists them the way the
/// editor presents them.
enum LYSynthNames {
    static let warps = ["OFF", "SYNC", "BEND +", "BEND −", "MIRROR", "PWM", "FM ← B", "RM ← B", "QUANTIZE",
                        "ASYM +", "ASYM −", "FLIP", "AM ← B", "FOLD"]
    static let warpsB = ["OFF", "SYNC", "BEND +", "BEND −", "MIRROR", "PWM", "FM ← A", "RM ← A", "QUANTIZE",
                         "ASYM +", "ASYM −", "FLIP", "AM ← A", "FOLD"]
    static let warpOrder = [LY_WARP_OFF, LY_WARP_SYNC, LY_WARP_BEND_POS, LY_WARP_BEND_NEG, LY_WARP_ASYM_POS, LY_WARP_ASYM_NEG,
                            LY_WARP_MIRROR, LY_WARP_PWM, LY_WARP_FLIP, LY_WARP_FOLD, LY_WARP_QUANTIZE,
                            LY_WARP_FM, LY_WARP_RM, LY_WARP_AM].map { Int($0) }
    static let unisonModes = ["LINEAR", "SUPER", "EXP", "RANDOM"]
    static let stacks = ["OFF", "+12", "±12", "+7 +12", "+7"]
    static let filters = ["LP 12", "LP 24", "HP 12", "HP 24", "BAND", "NOTCH", "LADDER", "COMB +", "COMB −", "FORMANT", "PHASER", "BAND 24"]
    static let filterOrder = [LY_FILTER_LP12, LY_FILTER_LP24, LY_FILTER_LADDER, LY_FILTER_HP12, LY_FILTER_HP24, LY_FILTER_BP,
                              LY_FILTER_BP24, LY_FILTER_NOTCH, LY_FILTER_COMB_POS, LY_FILTER_COMB_NEG, LY_FILTER_FORMANT,
                              LY_FILTER_PHASER].map { Int($0) }
    static let lfoShapes = ["SINE", "TRI", "SAW ↑", "SAW ↓", "SQUARE", "S + H", "DRIFT", "DRAW"]
    static let lfoModes = ["FREE", "TRIG", "ENV"]
    static let syncDivisions = ["4 BAR", "2 BAR", "1 BAR", "3/4", "1/2", "3/8", "1/4", "3/16", "1/8", "3/32", "1/16", "3/64", "1/32", "1/12", "1/64"]
    static let subShapes = ["SINE", "TRI", "SQUARE", "SAW"]
    static let noiseTypes = ["WHITE", "PINK", "BROWN", "CRACKLE", "VINYL", "DIGITAL", "METAL", "BREATH"]
    static let arpModes = ["UP", "DOWN", "UP + DOWN", "AS PLAYED", "RANDOM", "CHORD"]
    static let chorusModes = ["CLASSIC", "SUBTLE", "WIDE", "DEEP"]
    static let inserts = ["OFF", "BITCRUSH", "DECIMATE", "SINE SHAPER", "FOLD", "RECTIFY", "RING MOD", "FREQ SHIFT", "COMB"]
    static let performerModes = ["SONG", "NOTE"]
    static let stepShapes = ["HOLD", "RAMP UP", "RAMP DOWN", "TRIANGLE", "DECAY", "RISE", "PULSE", "GLIDE"]
    static let effects = ["HYPER", "DISTORTION", "FLANGER", "PHASER", "CHORUS", "DELAY", "COMPRESSOR", "EQ", "FILTER", "REVERB"]
    static let distortionModes = ["TUBE", "SOFT", "HARD", "DIODE", "LIN FOLD", "SIN FOLD", "ZERO-SQ", "DOWNSAMPLE", "BITCRUSH", "RECTIFY"]
    static let compModes = ["SINGLE", "MULTIBAND"]
    static let reverbModes = ["PLATE", "HALL"]
    static let fxFilters = ["LOW PASS", "HIGH PASS", "BAND", "NOTCH", "LADDER", "COMB"]
    static let tables = ["BASIC SHAPES", "ANALOG", "PWM", "HARMONIC SWEEP", "FORMANT", "FM BELL", "SYNC SWEEP",
                         "ORGAN", "DIGITAL", "VOID FOLD", "GROWL", "CHOIR", "SPECTRAL COMB", "GLASS"]
    static let sources = ["—", "ENV 1", "ENV 2", "ENV 3", "LFO 1", "LFO 2", "LFO 3", "LFO 4", "VELOCITY", "NOTE",
                          "MOD WHEEL", "MACRO 1", "MACRO 2", "MACRO 3", "MACRO 4", "RANDOM", "STEP CUTOFF", "STEP RES",
                          "PRESSURE", "TIMBRE", "PITCH BEND", "ENV 4",
                          "MACRO 5", "MACRO 6", "MACRO 7", "MACRO 8", "PERFORMER 1", "PERFORMER 2", "TRACKER 1", "TRACKER 2"]
    static let sourceOrder = [LY_SRC_NONE, LY_SRC_ENV1, LY_SRC_ENV2, LY_SRC_ENV3, LY_SRC_ENV4,
                              LY_SRC_LFO1, LY_SRC_LFO2, LY_SRC_LFO3, LY_SRC_LFO4,
                              LY_SRC_MACRO1, LY_SRC_MACRO2, LY_SRC_MACRO3, LY_SRC_MACRO4,
                              LY_SRC_MACRO5, LY_SRC_MACRO6, LY_SRC_MACRO7, LY_SRC_MACRO8,
                              LY_SRC_PERF1, LY_SRC_PERF2, LY_SRC_TRACK1, LY_SRC_TRACK2,
                              LY_SRC_VELOCITY, LY_SRC_NOTE, LY_SRC_RANDOM, LY_SRC_MODWHEEL, LY_SRC_PITCHBEND,
                              LY_SRC_PRESSURE, LY_SRC_TIMBRE, LY_SRC_STEP_CUTOFF, LY_SRC_STEP_RES].map { Int($0) }
    static let destinations: [String] = {
        var names = Array(repeating: "", count: Int(LY_DST_COUNT))
        for group in destinationGroups { for item in group.items { names[item.0] = item.1 } }
        names[Int(LY_DST_NONE)] = "—"
        return names
    }()
    /// Destinations as the matrix lists them, grouped by section.
    static let destinationGroups: [(title: String, items: [(Int, String)])] = [
        ("OSC A", [(LY_DST_A_LEVEL, "A LEVEL"), (LY_DST_A_PAN, "A PAN"), (LY_DST_A_PITCH, "A PITCH"), (LY_DST_A_FINE, "A FINE"),
                   (LY_DST_A_WTPOS, "A WT POS"), (LY_DST_A_WARP, "A WARP"), (LY_DST_A_WARP2, "A WARP 2"),
                   (LY_DST_A_DETUNE, "A DETUNE"), (LY_DST_A_BLEND, "A BLEND"), (LY_DST_A_WIDTH, "A WIDTH")].map { (Int($0.0), $0.1) }),
        ("OSC B", [(LY_DST_B_LEVEL, "B LEVEL"), (LY_DST_B_PAN, "B PAN"), (LY_DST_B_PITCH, "B PITCH"), (LY_DST_B_FINE, "B FINE"),
                   (LY_DST_B_WTPOS, "B WT POS"), (LY_DST_B_WARP, "B WARP"), (LY_DST_B_WARP2, "B WARP 2"),
                   (LY_DST_B_DETUNE, "B DETUNE"), (LY_DST_B_BLEND, "B BLEND"), (LY_DST_B_WIDTH, "B WIDTH")].map { (Int($0.0), $0.1) }),
        ("SUB + NOISE", [(LY_DST_SUB_LEVEL, "SUB LEVEL"), (LY_DST_SUB_PAN, "SUB PAN"), (LY_DST_NOISE_LEVEL, "NOISE LEVEL"),
                         (LY_DST_NOISE_COLOR, "NOISE COLOR"), (LY_DST_NOISE_PITCH, "NOISE PITCH"), (LY_DST_NOISE_PAN, "NOISE PAN")].map { (Int($0.0), $0.1) }),
        ("FILTERS", [(LY_DST_CUTOFF, "CUTOFF"), (LY_DST_RES, "RESONANCE"), (LY_DST_DRIVE, "DRIVE"), (LY_DST_FILTER_MIX, "FILTER MIX"),
                     (LY_DST_F2_CUTOFF, "F2 CUTOFF"), (LY_DST_F2_RES, "F2 RES"), (LY_DST_F2_DRIVE, "F2 DRIVE"), (LY_DST_F2_MIX, "F2 MIX"),
                     (LY_DST_FILTER_PAN, "FILTER PAN")].map { (Int($0.0), $0.1) }),
        ("VOICE FX", [(LY_DST_FEEDBACK, "FEEDBACK"), (LY_DST_FB_TONE, "FEEDBACK TONE"),
                      (LY_DST_INS1_AMOUNT, "INSERT 1 AMOUNT"), (LY_DST_INS1_FREQ, "INSERT 1 FREQ"),
                      (LY_DST_INS2_AMOUNT, "INSERT 2 AMOUNT"), (LY_DST_INS2_FREQ, "INSERT 2 FREQ")].map { (Int($0.0), $0.1) }),
        ("VOICE", [(LY_DST_AMP, "AMP"), (LY_DST_PAN, "PAN"), (LY_DST_PITCH, "PITCH"),
                   (LY_DST_ENV1_ATTACK, "ENV 1 ATTACK"), (LY_DST_ENV1_DECAY, "ENV 1 DECAY"), (LY_DST_ENV1_RELEASE, "ENV 1 RELEASE"),
                   (LY_DST_ENV2_ATTACK, "ENV 2 ATTACK"), (LY_DST_ENV2_DECAY, "ENV 2 DECAY"), (LY_DST_ENV2_RELEASE, "ENV 2 RELEASE"),
                   (LY_DST_LFO1_RATE, "LFO 1 RATE"), (LY_DST_LFO2_RATE, "LFO 2 RATE"), (LY_DST_LFO3_RATE, "LFO 3 RATE"),
                   (LY_DST_LFO4_RATE, "LFO 4 RATE")].map { (Int($0.0), $0.1) }),
        ("FX", [(LY_DST_HYPER_MIX, "HYPER MIX"), (LY_DST_HYPER_DETUNE, "HYPER DETUNE"), (LY_DST_DIM_MIX, "DIMENSION"),
                (LY_DST_DIST_DRIVE, "DIST DRIVE"), (LY_DST_DIST_MIX, "DIST MIX"),
                (LY_DST_FLANGER_DEPTH, "FLANGER DEPTH"), (LY_DST_FLANGER_MIX, "FLANGER MIX"),
                (LY_DST_PHASER_FREQ, "PHASER FREQ"), (LY_DST_PHASER_MIX, "PHASER MIX"),
                (LY_DST_CHORUS_DEPTH, "CHORUS DEPTH"), (LY_DST_CHORUS_MIX, "CHORUS MIX"),
                (LY_DST_DELAY_FEEDBACK, "DELAY FEEDBACK"), (LY_DST_DELAY_MIX, "DELAY MIX"),
                (LY_DST_COMP_DEPTH, "COMP DEPTH"), (LY_DST_COMP_MIX, "COMP MIX"),
                (LY_DST_EQ_LOW, "EQ LOW"), (LY_DST_EQ_MID, "EQ MID"), (LY_DST_EQ_HIGH, "EQ HIGH"),
                (LY_DST_FXF_CUTOFF, "FX CUTOFF"), (LY_DST_FXF_RES, "FX RES"), (LY_DST_FXF_MIX, "FX FILTER MIX"),
                (LY_DST_REVERB_SIZE, "REVERB SIZE"), (LY_DST_REVERB_DECAY, "REVERB DECAY"), (LY_DST_REVERB_MIX, "REVERB MIX"),
                (LY_DST_MASTER, "MASTER")].map { (Int($0.0), $0.1) }),
    ]
}

// MARK: - Patch

/// A saved LUNATK sound. Values are stored by parameter key; anything
/// missing plays at the core's default.
struct LYSynthPatch: Codable, Equatable {
    var name: String
    var values: [String: Float] = [:]
    var tableA: Int = 0
    var tableB: Int = 0
    /// A user or imported wavetable by name; overrides the factory table.
    var customTableA: String? = nil
    var customTableB: String? = nil
    /// Factory bank metadata: which category it lives in and how to use it.
    var category: String? = nil
    var info: LYSynthPresetInfo? = nil

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
            let base = LYSynthParameters.matrix(slot, 0)
            if Int(value(base + LY_MX_SOURCE)) == source && Int(value(base + LY_MX_DEST)) == destination {
                set(base + LY_MX_AMOUNT, amount)
                return slot
            }
        }
        for slot in 0..<Int(LY_MATRIX_SLOTS) {
            let base = LYSynthParameters.matrix(slot, 0)
            if Int(value(base + LY_MX_SOURCE)) == LY_SRC_NONE || Int(value(base + LY_MX_DEST)) == LY_DST_NONE {
                set(base + LY_MX_SOURCE, Float(source))
                set(base + LY_MX_DEST, Float(destination))
                set(base + LY_MX_AMOUNT, amount)
                set(base + LY_MX_AUX, 0)
                set(base + LY_MX_CURVE, 0)
                set(base + LY_MX_BIPOLAR, 0)
                return slot
            }
        }
        return nil
    }

    /// Every route into a destination: (slot, source, amount).
    func routes(into destination: Int) -> [(slot: Int, source: Int, amount: Float)] {
        (0..<Int(LY_MATRIX_SLOTS)).compactMap { slot in
            let base = LYSynthParameters.matrix(slot, 0)
            let src = Int(value(base + LY_MX_SOURCE))
            guard src != LY_SRC_NONE, Int(value(base + LY_MX_DEST)) == destination else { return nil }
            return (slot, src, value(base + LY_MX_AMOUNT))
        }
    }

    /// Slots holding a route.
    var usedMatrixSlots: [Int] {
        (0..<Int(LY_MATRIX_SLOTS)).filter { slot in
            let base = LYSynthParameters.matrix(slot, 0)
            return Int(value(base + LY_MX_SOURCE)) != LY_SRC_NONE || Int(value(base + LY_MX_DEST)) != LY_DST_NONE
        }
    }

    mutating func clearRoute(_ slot: Int) {
        let base = LYSynthParameters.matrix(slot, 0)
        for field in 0..<Int(LY_MATRIX_STRIDE) { values.removeValue(forKey: LYSynthParameters.byID[base + field]?.key ?? "") }
        set(base + LY_MX_SOURCE, 0)
        set(base + LY_MX_DEST, 0)
    }

    /// The effects rack in play order.
    var effectOrder: [Int] {
        let order = (0..<Int(LY_FX_COUNT)).map { Int(value(LY_FX_ORDER + $0)) }
        return Set(order).count == Int(LY_FX_COUNT) && order.allSatisfy({ (0..<Int(LY_FX_COUNT)).contains($0) })
            ? order : LYSynthPatch.defaultEffectOrder
    }

    static let defaultEffectOrder = [LY_FX_HYPER, LY_FX_DIST, LY_FX_FLANGER, LY_FX_PHASER, LY_FX_CHORUS,
                                     LY_FX_DELAY, LY_FX_COMP, LY_FX_REVERB, LY_FX_EQ, LY_FX_FILTER].map { Int($0) }

    mutating func setEffectOrder(_ order: [Int]) {
        for (index, fx) in order.enumerated() { set(LY_FX_ORDER + index, Float(fx)) }
    }
}

// MARK: - Factory sounds

/// What a factory sound is for, shown in the browser.
struct LYSynthPresetInfo: Codable, Equatable {
    var role: String
    var register: String
    var genres: String
    var playing: String
    var layer: String
    var mix: String
}

/// The factory bank, shipped as LUNATKFactory.json beside the code (the app,
/// the Audio Unit and the VST3 each carry a copy). Built and gated by
/// tools/lunatk_bank.
enum LYSynthFactoryBank {
    private final class Token {}

    struct Entry: Decodable {
        var name: String
        var category: String
        var info: LYSynthPresetInfo
        var patch: LYSynthPatch
    }

    private struct File: Decodable { var presets: [Entry] }

    static let categories = ["BASS", "LEAD", "PAD", "KEYS", "PLUCK", "ARP", "MOTION", "DRONE", "PERC", "FX"]

    static let presets: [LYSynthPatch] = {
        let bundles = [Bundle(for: Token.self), Bundle.main]
        for bundle in bundles {
            guard let url = bundle.url(forResource: "LUNATKFactory", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data) else { continue }
            return file.presets.map { entry in
                var patch = entry.patch
                patch.name = entry.name
                patch.category = entry.category
                patch.info = entry.info
                return patch
            }
        }
        return []
    }()
}

extension LYSynthPatch {
    static let initPatch = LYSynthPatch(name: "INIT")

    /// Every factory sound: INIT, the bank by category, then the originals.
    static let factory: [LYSynthPatch] = [initPatch] + LYSynthFactoryBank.presets + original.map { patch in
        var tagged = patch
        tagged.category = "ORIGINAL"
        return tagged
    }

    private static func make(_ name: String, tableA: Int, tableB: Int = LY_TABLE_BASIC, _ build: (inout LYSynthPatch) -> Void) -> LYSynthPatch {
        var patch = LYSynthPatch(name: name, tableA: tableA, tableB: tableB)
        build(&patch)
        return patch
    }

    private static func osc(_ o: Int, _ local: Int) -> Int { LYSynthParameters.oscillator(o, local) }
    private static func lfo(_ l: Int, _ field: Int) -> Int { LYSynthParameters.lfo(l, field) }
    /// A sync division as the rate knob stores it.
    private static func division(_ name: String) -> Float {
        Float(LYSynthNames.syncDivisions.firstIndex(of: name) ?? 6) / Float(LYSynthNames.syncDivisions.count - 1)
    }

    /// LUNATK's first factory sounds, kept as they were.
    static let original: [LYSynthPatch] = [
        make("NIGHT PAD", tableA: LY_TABLE_ANALOG, tableB: LY_TABLE_CHOIR) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.45); p.set(osc(0, LY_OSC_UNISON), 7); p.set(osc(0, LY_OSC_DETUNE), 0.38); p.set(osc(0, LY_OSC_WIDTH), 0.95)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.45); p.set(osc(1, LY_OSC_WTPOS), 0.3); p.set(osc(1, LY_OSC_UNISON), 4); p.set(osc(1, LY_OSC_DETUNE), 0.3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.58); p.set(LY_FILTER_RES, 0.2); p.set(LY_FILTER_ENVAMT, 0.12)
            p.set(LY_ENV1_A, 0.55); p.set(LY_ENV1_D, 0.6); p.set(LY_ENV1_S, 0.85); p.set(LY_ENV1_R, 0.62)
            p.set(LY_ENV2_A, 0.5); p.set(LY_ENV2_D, 0.7); p.set(LY_ENV2_S, 0.4); p.set(LY_ENV2_R, 0.6)
            p.set(lfo(0, LY_LFO1_RATE), 0.22); p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.22)
            p.set(lfo(1, LY_LFO1_SHAPE), Float(LY_LFO_SMOOTH_RANDOM)); p.set(lfo(1, LY_LFO1_RATE), 0.3); p.route(source: LY_SRC_LFO2, destination: LY_DST_CUTOFF, amount: 0.05)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_CUTOFF, amount: 0.35)
            p.set(LY_CHORUS_ON, 1); p.set(LY_CHORUS_MIX, 0.35)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MODE, 1); p.set(LY_REVERB_SIZE, 0.6); p.set(LY_REVERB_DECAY, 0.5); p.set(LY_REVERB_MIX, 0.3)
            p.set(LY_MASTER, 0.6)
        },
        make("LUNAR SUPERSAW", tableA: LY_TABLE_ANALOG, tableB: LY_TABLE_ANALOG) { p in
            p.set(osc(0, LY_OSC_WTPOS), 1); p.set(osc(0, LY_OSC_UNISON), 9); p.set(osc(0, LY_OSC_DETUNE), 0.42); p.set(osc(0, LY_OSC_UNIMODE), Float(LY_UNI_SUPER)); p.set(osc(0, LY_OSC_WIDTH), 1)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.4); p.set(osc(1, LY_OSC_WTPOS), 1); p.set(osc(1, LY_OSC_UNISON), 5)
            p.set(osc(1, LY_OSC_STACK), Float(LY_STACK_OCTAVE)); p.set(osc(1, LY_OSC_DETUNE), 0.3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.72); p.set(LY_FILTER_RES, 0.1)
            p.set(LY_ENV1_A, 0.12); p.set(LY_ENV1_D, 0.5); p.set(LY_ENV1_S, 0.85); p.set(LY_ENV1_R, 0.5)
            p.set(LY_HYPER_ON, 1); p.set(LY_HYPER_MIX, 0.35); p.set(LY_HYPER_DIM_MIX, 0.4)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MODE, 1); p.set(LY_REVERB_SIZE, 0.7); p.set(LY_REVERB_MIX, 0.25)
            p.set(LY_DELAY_ON, 1); p.set(LY_DELAY_TIME, division("3/16")); p.set(LY_DELAY_PINGPONG, 1); p.set(LY_DELAY_MIX, 0.18)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_CUTOFF, amount: 0.3)
            p.set(LY_MASTER, 0.5)
        },
        make("ECLIPSE ARP", tableA: LY_TABLE_GLASS, tableB: LY_TABLE_FM_BELL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.35); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.14)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_OCTAVE), 1)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.55); p.set(LY_FILTER_RES, 0.3); p.set(LY_FILTER_ENVAMT, 0.3)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.4); p.set(LY_ENV1_S, 0.1); p.set(LY_ENV1_R, 0.4)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.35); p.set(LY_ENV2_S, 0.05)
            p.set(LY_ARP_ON, 1); p.set(LY_ARP_MODE, Float(LY_ARP_UPDOWN)); p.set(LY_ARP_RATE, division("1/16")); p.set(LY_ARP_OCTAVES, 2); p.set(LY_ARP_GATE, 0.45)
            p.set(LY_DELAY_ON, 1); p.set(LY_DELAY_TIME, division("3/16")); p.set(LY_DELAY_PINGPONG, 1); p.set(LY_DELAY_FEEDBACK, 0.45); p.set(LY_DELAY_MIX, 0.3)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MIX, 0.2)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.12); p.set(lfo(0, LY_LFO1_RATE), 0.2)
            p.set(LY_MASTER, 0.62)
        },
        make("CRATER BASS", tableA: LY_TABLE_BASIC, tableB: LY_TABLE_GROWL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.66); p.set(osc(0, LY_OSC_LEVEL), 0.8)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.35); p.set(osc(1, LY_OSC_WTPOS), 0.4)
            p.set(LY_SUB_ON, 1); p.set(LY_SUB_SHAPE, 3); p.set(LY_SUB_LEVEL, 0.45); p.set(LY_FILTER_ROUTE_SUB, 0)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LADDER)); p.set(LY_FILTER_CUTOFF, 0.34); p.set(LY_FILTER_RES, 0.35); p.set(LY_FILTER_ENVAMT, 0.32); p.set(LY_FILTER_DRIVE, 0.35)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.4); p.set(LY_ENV1_S, 0.9); p.set(LY_ENV1_R, 0.2)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_H, 0.2); p.set(LY_ENV2_D, 0.38); p.set(LY_ENV2_S, 0.1)
            p.set(LY_DIST_ON, 1); p.set(LY_DIST_MODE, Float(LY_DIST_TUBE)); p.set(LY_DIST_DRIVE, 0.35); p.set(LY_DIST_MIX, 0.6)
            p.set(LY_COMP_ON, 1); p.set(LY_COMP_MODE, Float(LY_COMP_MULTIBAND)); p.set(LY_COMP_DEPTH, 0.4)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_DIST_DRIVE, amount: 0.5)
            p.set(LY_VOICES, 1); p.set(LY_LEGATO, 1); p.set(LY_GLIDE, 0.05); p.set(LY_GLIDE_ALWAYS, 0)
            p.set(LY_MASTER, 0.6)
        },
        make("OTT GROWL", tableA: LY_TABLE_GROWL, tableB: LY_TABLE_VOID_FOLD) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.2); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.12)
            p.set(osc(0, LY_OSC_WARPMODE2), Float(LY_WARP_FOLD)); p.set(osc(0, LY_OSC_WARPAMT2), 0.2)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.5); p.set(osc(1, LY_OSC_OCTAVE), -1)
            p.set(LY_SUB_ON, 1); p.set(LY_SUB_LEVEL, 0.45)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.46); p.set(LY_FILTER_RES, 0.3); p.set(LY_FILTER_DRIVE, 0.5)
            p.set(lfo(0, LY_LFO1_SHAPE), Float(LY_LFO_SAW_DOWN)); p.set(lfo(0, LY_LFO1_SYNC), 1); p.set(lfo(0, LY_LFO1_RATE), division("1/8")); p.set(lfo(0, LY_LFO1_RETRIG), Float(LY_LFOMODE_TRIG))
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.6)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WARP2, amount: 0.5)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.16)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_DRIVE, amount: 0.5)
            p.set(LY_DIST_ON, 1); p.set(LY_DIST_MODE, Float(LY_DIST_SINFOLD)); p.set(LY_DIST_DRIVE, 0.2); p.set(LY_DIST_MIX, 0.5)
            p.set(LY_COMP_ON, 1); p.set(LY_COMP_MODE, Float(LY_COMP_MULTIBAND)); p.set(LY_COMP_DEPTH, 0.8); p.set(LY_COMP_GAIN, 0.15)
            p.set(LY_VOICES, 1); p.set(LY_MASTER, 0.5)
        },
        make("TIDE PAD", tableA: LY_TABLE_HARMONIC_SWEEP, tableB: LY_TABLE_SPECTRAL_COMB) { p in
            p.set(osc(0, LY_OSC_UNISON), 6); p.set(osc(0, LY_OSC_DETUNE), 0.3); p.set(osc(0, LY_OSC_WTPOS), 0.4)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.45); p.set(osc(1, LY_OSC_UNISON), 4)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.55); p.set(LY_FILTER_RES, 0.25)
            p.set(LY_F2_ON, 1); p.set(LY_F2_TYPE, Float(LY_FILTER_BP)); p.set(LY_F2_CUTOFF, 0.6); p.set(LY_F2_RES, 0.5); p.set(LY_FILTER_ROUTING, 1)
            p.set(LY_ENV1_A, 0.6); p.set(LY_ENV1_S, 0.85); p.set(LY_ENV1_R, 0.7)
            p.set(lfo(0, LY_LFO1_RATE), 0.15); p.set(lfo(0, LY_LFO1_DELAY), 0.2); p.set(lfo(0, LY_LFO1_RISE), 0.4); p.set(lfo(0, LY_LFO1_RETRIG), Float(LY_LFOMODE_TRIG))
            p.route(source: LY_SRC_LFO1, destination: LY_DST_F2_CUTOFF, amount: 0.3)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.3)
            p.set(LY_PHASER_ON, 1); p.set(LY_PHASER_MIX, 0.4); p.set(LY_PHASER_RATE, 0.15)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MODE, 1); p.set(LY_REVERB_SIZE, 0.8); p.set(LY_REVERB_DECAY, 0.6); p.set(LY_REVERB_MIX, 0.35)
            p.set(LY_MASTER, 0.55)
        },
        make("GLASS ARP", tableA: LY_TABLE_GLASS, tableB: LY_TABLE_FM_BELL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.3); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.14)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.32); p.set(osc(1, LY_OSC_OCTAVE), 1); p.set(osc(1, LY_OSC_WTPOS), 0.25)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.62); p.set(LY_FILTER_RES, 0.25); p.set(LY_FILTER_ENVAMT, 0.28)
            p.set(LY_ENV1_A, 0.02); p.set(LY_ENV1_D, 0.45); p.set(LY_ENV1_S, 0.18); p.set(LY_ENV1_R, 0.42)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.36); p.set(LY_ENV2_S, 0.05)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WTPOS, amount: 0.35)
            p.route(source: LY_SRC_VELOCITY, destination: LY_DST_CUTOFF, amount: 0.15)
            p.set(LY_DELAY_ON, 1); p.set(LY_DELAY_MIX, 0.22); p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MIX, 0.2)
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
            p.set(osc(0, LY_OSC_WARPMODE), Float(LY_WARP_SYNC)); p.set(osc(0, LY_OSC_WARPAMT), 0.2)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.35); p.set(osc(1, LY_OSC_OCTAVE), -1); p.set(osc(1, LY_OSC_WTPOS), 0.8)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LADDER)); p.set(LY_FILTER_CUTOFF, 0.62); p.set(LY_FILTER_RES, 0.32); p.set(LY_FILTER_DRIVE, 0.4); p.set(LY_FILTER_ENVAMT, 0.18)
            p.set(LY_ENV2_A, 0.08); p.set(LY_ENV2_D, 0.5); p.set(LY_ENV2_S, 0.2)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WARP, amount: 0.5)
            p.set(lfo(0, LY_LFO1_SHAPE), Float(LY_LFO_TRIANGLE)); p.set(lfo(0, LY_LFO1_RATE), 0.62); p.set(lfo(0, LY_LFO1_DELAY), 0.1); p.set(lfo(0, LY_LFO1_RISE), 0.15)
            p.set(lfo(0, LY_LFO1_RETRIG), Float(LY_LFOMODE_TRIG))
            p.route(source: LY_SRC_LFO1, destination: LY_DST_PITCH, amount: 0.004)
            p.route(source: LY_SRC_MODWHEEL, destination: LY_DST_A_WARP, amount: 0.6)
            p.set(LY_DIST_ON, 1); p.set(LY_DIST_MODE, Float(LY_DIST_SOFT)); p.set(LY_DIST_DRIVE, 0.2); p.set(LY_DIST_MIX, 0.5)
            p.set(LY_DELAY_ON, 1); p.set(LY_DELAY_MIX, 0.15)
            p.set(LY_VOICES, 1); p.set(LY_LEGATO, 1); p.set(LY_GLIDE, 0.08)
            p.set(LY_MASTER, 0.5)
        },
        make("VOID GROWL", tableA: LY_TABLE_GROWL, tableB: LY_TABLE_VOID_FOLD) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.2); p.set(osc(0, LY_OSC_UNISON), 3); p.set(osc(0, LY_OSC_DETUNE), 0.12)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.5); p.set(osc(1, LY_OSC_OCTAVE), -1)
            p.set(LY_SUB_ON, 1); p.set(LY_SUB_LEVEL, 0.45)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP24)); p.set(LY_FILTER_CUTOFF, 0.46); p.set(LY_FILTER_RES, 0.3); p.set(LY_FILTER_DRIVE, 0.5)
            p.set(lfo(0, LY_LFO1_SHAPE), Float(LY_LFO_SAW_DOWN)); p.set(lfo(0, LY_LFO1_SYNC), 1); p.set(lfo(0, LY_LFO1_RATE), division("1/8")); p.set(lfo(0, LY_LFO1_RETRIG), 1)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.6)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_B_WTPOS, amount: 0.4)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.16)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_DRIVE, amount: 0.5)
            p.set(LY_VOICES, 1); p.set(LY_MASTER, 0.55)
        },
        make("FORMANT CHOIR", tableA: LY_TABLE_FORMANT, tableB: LY_TABLE_CHOIR) { p in
            p.set(osc(0, LY_OSC_UNISON), 5); p.set(osc(0, LY_OSC_DETUNE), 0.3)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.4); p.set(osc(1, LY_OSC_OCTAVE), 1); p.set(osc(1, LY_OSC_UNISON), 3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_FORMANT)); p.set(LY_FILTER_CUTOFF, 0.4); p.set(LY_FILTER_RES, 0.4); p.set(LY_FILTER_MIX, 0.8)
            p.set(LY_ENV1_A, 0.45); p.set(LY_ENV1_S, 0.9); p.set(LY_ENV1_R, 0.6)
            p.set(lfo(0, LY_LFO1_RATE), 0.18); p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.3)
            p.set(lfo(1, LY_LFO1_RATE), 0.24); p.set(lfo(1, LY_LFO1_SHAPE), Float(LY_LFO_TRIANGLE)); p.route(source: LY_SRC_LFO2, destination: LY_DST_B_WTPOS, amount: 0.4)
            p.route(source: LY_SRC_MACRO1, destination: LY_DST_CUTOFF, amount: 0.6)
            p.set(LY_CHORUS_ON, 1); p.set(LY_CHORUS_MIX, 0.4); p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MODE, 1); p.set(LY_REVERB_MIX, 0.3)
            p.set(LY_MASTER, 0.6)
        },
        make("COMB BELL", tableA: LY_TABLE_FM_BELL, tableB: LY_TABLE_GLASS) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.5); p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_OCTAVE), 2)
            p.set(LY_NOISE_ON, 1); p.set(LY_NOISE_TYPE, Float(LY_NOISE_METAL)); p.set(LY_NOISE_LEVEL, 0.2)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_COMB_POS)); p.set(LY_FILTER_CUTOFF, 0.55); p.set(LY_FILTER_RES, 0.75); p.set(LY_FILTER_KEYTRACK, 1)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.6); p.set(LY_ENV1_S, 0); p.set(LY_ENV1_R, 0.6)
            p.set(LY_EQ_ON, 1); p.set(LY_EQ_HIGH_GAIN, 0.3); p.set(LY_EQ_LOW_GAIN, -0.3)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MIX, 0.35)
            p.set(LY_MASTER, 0.6)
        },
        make("NIGHT KEYS", tableA: LY_TABLE_ORGAN, tableB: LY_TABLE_FM_BELL) { p in
            p.set(osc(0, LY_OSC_WTPOS), 0.3); p.set(osc(0, LY_OSC_UNISON), 2); p.set(osc(0, LY_OSC_DETUNE), 0.08)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_WTPOS), 0.2)
            p.set(LY_NOISE_ON, 1); p.set(LY_NOISE_TYPE, Float(LY_NOISE_VINYL)); p.set(LY_NOISE_LEVEL, 0.35); p.set(LY_FILTER_ROUTE_NOISE, 0)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.6); p.set(LY_FILTER_ENVAMT, 0.14)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.52); p.set(LY_ENV1_S, 0.45); p.set(LY_ENV1_R, 0.36)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_B_LEVEL, amount: 0.4)
            p.set(LY_CHORUS_ON, 1); p.set(LY_CHORUS_MIX, 0.3)
            p.set(LY_EQ_ON, 1); p.set(LY_EQ_HIGH_GAIN, -0.35); p.set(LY_EQ_MID_GAIN, 0.15)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MIX, 0.22)
            p.set(LY_MASTER, 0.64)
        },
        make("DIGITAL RAIN", tableA: LY_TABLE_DIGITAL, tableB: LY_TABLE_PWM) { p in
            p.set(osc(0, LY_OSC_UNISON), 2); p.set(osc(0, LY_OSC_DETUNE), 0.1)
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.3); p.set(osc(1, LY_OSC_OCTAVE), 1)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_LP12)); p.set(LY_FILTER_CUTOFF, 0.66); p.set(LY_FILTER_RES, 0.3)
            p.set(LY_ENV1_A, 0.01); p.set(LY_ENV1_D, 0.35); p.set(LY_ENV1_S, 0.0); p.set(LY_ENV1_R, 0.35)
            p.set(LY_ENV2_A, 0.01); p.set(LY_ENV2_D, 0.3); p.set(LY_ENV2_S, 0)
            p.route(source: LY_SRC_ENV2, destination: LY_DST_A_WTPOS, amount: 0.8)
            p.route(source: LY_SRC_RANDOM, destination: LY_DST_B_WTPOS, amount: 0.5)
            p.set(LY_DIST_ON, 1); p.set(LY_DIST_MODE, Float(LY_DIST_BITCRUSH)); p.set(LY_DIST_DRIVE, 0.35); p.set(LY_DIST_MIX, 0.5)
            p.set(LY_DELAY_ON, 1); p.set(LY_DELAY_PINGPONG, 1); p.set(LY_DELAY_MIX, 0.25)
            p.set(LY_MASTER, 0.62)
        },
        make("SPECTRAL DRIFT", tableA: LY_TABLE_SPECTRAL_COMB, tableB: LY_TABLE_HARMONIC_SWEEP) { p in
            p.set(osc(0, LY_OSC_UNISON), 6); p.set(osc(0, LY_OSC_DETUNE), 0.3); p.set(osc(0, LY_OSC_UNIMODE), Float(LY_UNI_RANDOM))
            p.set(osc(1, LY_OSC_ON), 1); p.set(osc(1, LY_OSC_LEVEL), 0.35); p.set(osc(1, LY_OSC_OCTAVE), 1)
            p.set(LY_NOISE_ON, 1); p.set(LY_NOISE_TYPE, Float(LY_NOISE_BREATH)); p.set(LY_NOISE_LEVEL, 0.25); p.set(LY_NOISE_COLOR, 0.3)
            p.set(LY_FILTER_TYPE, Float(LY_FILTER_PHASER)); p.set(LY_FILTER_CUTOFF, 0.55); p.set(LY_FILTER_RES, 0.6)
            p.set(LY_ENV1_A, 0.6); p.set(LY_ENV1_S, 0.8); p.set(LY_ENV1_R, 0.7)
            p.set(lfo(0, LY_LFO1_SHAPE), Float(LY_LFO_SMOOTH_RANDOM)); p.set(lfo(0, LY_LFO1_RATE), 0.35)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_A_WTPOS, amount: 0.6)
            p.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.2)
            p.set(LY_FLANGER_ON, 1); p.set(LY_FLANGER_MIX, 0.3); p.set(LY_FLANGER_RATE, 0.1)
            p.set(LY_REVERB_ON, 1); p.set(LY_REVERB_MODE, 1); p.set(LY_REVERB_SIZE, 0.9); p.set(LY_REVERB_MIX, 0.4)
            p.set(LY_MASTER, 0.55)
        }
    ]

    static func factory(named name: String) -> LYSynthPatch? {
        factory.first { $0.name == name }
    }
}
