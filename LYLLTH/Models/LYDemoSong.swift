import Foundation
import NightshapeAudioEngine

/// The demo song a new LYLLTH project opens with: a dark synth-pop track in
/// F minor at 112 BPM, with an intro, two verses, pre-choruses, three
/// choruses, an industrial bridge and an outro. Drums are DrumKit drum tracks
/// playing DrumKit's drum bank from step patterns; every other part is a
/// piano-roll clip played by a LUNATK factory sound.
enum LYDemoSong {
    static let bpm = 112.0
    static let title = "NIGHT SIGNAL"

    /// Sections in bars.
    static let sections: [(name: String, bar: Int, bars: Int)] = [
        ("INTRO", 0, 8), ("VERSE 1", 8, 16), ("PRE 1", 24, 8), ("CHORUS 1", 32, 16), ("VERSE 2", 48, 8),
        ("PRE 2", 56, 8), ("CHORUS 2", 64, 16), ("BRIDGE", 80, 8), ("CHORUS 3", 88, 16), ("OUTRO", 104, 8),
    ]
    static var bars: Int { sections.last.map { $0.bar + $0.bars } ?? 0 }

    // MARK: Harmony (F minor)

    /// Chords as pad voicings (F3–D♭4 area) and bass roots (B♭1–A♭2).
    struct Chord { let voicing: [Int]; let root: Int }
    static let Fm = Chord(voicing: [53, 56, 60], root: 41)
    static let Db = Chord(voicing: [53, 56, 61], root: 37)
    static let Ab = Chord(voicing: [51, 56, 60], root: 44)
    static let Eb = Chord(voicing: [51, 55, 58], root: 39)
    static let Bbm = Chord(voicing: [53, 58, 61], root: 34)
    static let Cm = Chord(voicing: [51, 55, 60], root: 36)

    static let verseChords = [Fm, Db, Ab, Eb]
    static let preChords = [Bbm, Bbm, Db, Eb]
    static let chorusChords = [Db, Ab, Eb, Fm]
    static let bridgeChords = [Db, Eb, Cm, Fm]

    /// The chord playing in `bar` (0-based song bar).
    static func chord(at bar: Int) -> Chord {
        guard let section = sections.last(where: { $0.bar <= bar }) else { return Fm }
        let local = bar - section.bar
        let name = section.name
        if name.hasPrefix("PRE") { return preChords[local % 4] }
        if name.hasPrefix("CHORUS") { return chorusChords[local % 4] }
        if name == "BRIDGE" { return bridgeChords[(local / 2) % 4] }
        return verseChords[local % 4]
    }

    // MARK: Parts

    /// One track's notes in song beats, before they are cut into section clips.
    struct Part {
        let name: String
        let sound: String
        var volumeDB: Double
        var pan: Double = 0
        /// LUNATK's MACRO 4 (GRIT): 0 is the preset as designed.
        var grit: Float = 0
        var fx: LYFXRack? = nil
        var notes: [LYNote] = []

        mutating func add(_ pitch: Int, at beat: Double, length: Double, velocity: Int = 100) {
            notes.append(LYNote(start: beat, length: length, pitch: min(max(pitch, 0), 127), velocity: min(max(velocity, 1), 127)))
        }
        mutating func chord(_ pitches: [Int], at beat: Double, length: Double, velocity: Int = 90) {
            for p in pitches { add(p, at: beat, length: length, velocity: velocity) }
        }
    }

    static func beat(_ bar: Int, _ offset: Double = 0) -> Double { Double(bar) * 4 + offset }
    static func section(_ name: String) -> (bar: Int, bars: Int) {
        let s = sections.first { $0.name == name }!
        return (s.bar, s.bars)
    }
    static func barsOf(_ names: [String]) -> [Int] {
        names.flatMap { name -> [Int] in let s = section(name); return Array(s.bar ..< s.bar + s.bars) }
    }

    // MARK: Drums (DrumKit)

    /// A DrumKit drum track: hits on the sixteenth grid, played by a sound
    /// from DrumKit's drum bank.
    struct DrumPart {
        let name: String
        let preset: String
        var volumeDB: Double
        var pan: Double = 0
        var chokeGroup: Int? = nil
        var fx: LYFXRack? = nil
        /// Velocity (0…1) by song step (a sixteenth).
        var hits: [Int: Double] = [:]

        mutating func add(_ pitch: Int = 0, at beat: Double, length: Double = 0.25, velocity: Int = 100) {
            let step = Int((beat * 4).rounded())
            hits[step] = max(hits[step] ?? 0, Double(min(max(velocity, 1), 127)) / 127)
        }
    }

    static func drums() -> [DrumPart] {
        var kick = DrumPart(name: "KICK", preset: "user_nit_kick", volumeDB: -9, fx: FX.kick)       // CHARGED KICK
        var snare = DrumPart(name: "SNARE", preset: "user_nit_snare", volumeDB: -12, fx: FX.snare)  // CHARGED SNARE
        var clap = DrumPart(name: "CLAP", preset: "clap_012", volumeDB: -15, pan: 0.05, fx: FX.tape(0.5))   // DARK CLAP
        var hats = DrumPart(name: "HATS", preset: "closedhat_006", volumeDB: -20, pan: 0.2, fx: FX.tape(0.45))  // CHARCOAL
        var shaker = DrumPart(name: "CHAINS", preset: "closedhat_017", volumeDB: -24, pan: -0.25)  // CHAINLINK
        var metal = DrumPart(name: "METAL", preset: "perc_010", volumeDB: -19, pan: -0.1, fx: FX.decimated(0.35))   // METAL STAB
        var impact = DrumPart(name: "IMPACT", preset: "tom_003", volumeDB: -14, fx: FX.tape(0.6))       // THUNDER

        // Intro: the kick arrives half-way, then a pulse of hats.
        for bar in 4..<8 {
            kick.add(36, at: beat(bar), length: 0.25, velocity: 96)
            if bar >= 6 { kick.add(36, at: beat(bar, 2.5), length: 0.25, velocity: 80) }
            for e in 0..<8 { hats.add(60, at: beat(bar, Double(e) * 0.5), length: 0.1, velocity: e % 2 == 0 ? 48 : 30) }
        }

        // Verses: half-time: kick on 1 and the and-of-3, snare on 3.
        for bar in barsOf(["VERSE 1", "VERSE 2"]) {
            let inPhrase = (bar - 8) % 4
            let two = bar >= section("VERSE 2").bar
            kick.add(36, at: beat(bar), length: 0.25, velocity: 110)
            kick.add(36, at: beat(bar, 2.5), length: 0.25, velocity: 92)
            if inPhrase == 3 { kick.add(36, at: beat(bar, 3.5), length: 0.25, velocity: 78) }
            snare.add(50, at: beat(bar, 2), length: 0.25, velocity: 108)
            if two { clap.add(60, at: beat(bar, 2), length: 0.25, velocity: 80) }
            for e in 0..<8 {
                hats.add(60, at: beat(bar, Double(e) * 0.5), length: 0.1, velocity: e % 2 == 0 ? 78 : 44)
            }
            if inPhrase == 3 {
                hats.add(60, at: beat(bar, 3.25), length: 0.1, velocity: 56)
                hats.add(60, at: beat(bar, 3.75), length: 0.1, velocity: 64)
            }
            if two { for s in stride(from: 0.25, to: 4, by: 0.5) { shaker.add(60, at: beat(bar, s), length: 0.1, velocity: 40) } }
        }

        // Pre-choruses: four on the floor, backbeat, and a snare roll into the chorus.
        for name in ["PRE 1", "PRE 2"] {
            let s = section(name)
            for bar in s.bar ..< s.bar + s.bars {
                let last = bar == s.bar + s.bars - 1
                for q in 0..<4 { kick.add(36, at: beat(bar, Double(q)), length: 0.25, velocity: last ? 100 : 104) }
                if !last {
                    snare.add(50, at: beat(bar, 1), length: 0.25, velocity: 100)
                    snare.add(50, at: beat(bar, 3), length: 0.25, velocity: 104)
                    for e in 0..<16 { hats.add(60, at: beat(bar, Double(e) * 0.25), length: 0.08, velocity: e % 4 == 2 ? 70 : 36) }
                } else {
                    // A sixteenth roll that grows into the downbeat.
                    for e in 0..<16 { snare.add(50, at: beat(bar, Double(e) * 0.25), length: 0.2, velocity: 36 + e * 5) }
                }
            }
        }

        // Choruses: four on the floor, clap and snare on 2 and 4, off-beat hats.
        for bar in barsOf(["CHORUS 1", "CHORUS 2", "CHORUS 3"]) {
            let inPhrase = bar % 4
            for q in 0..<4 { kick.add(36, at: beat(bar, Double(q)), length: 0.25, velocity: q == 0 ? 118 : 106) }
            for q in [1.0, 3.0] {
                snare.add(50, at: beat(bar, q), length: 0.25, velocity: 110)
                clap.add(60, at: beat(bar, q), length: 0.25, velocity: 100)
            }
            for q in 0..<4 { hats.add(60, at: beat(bar, Double(q) + 0.5), length: 0.2, velocity: 92) }
            for s in 0..<16 where s % 2 == 1 { shaker.add(60, at: beat(bar, Double(s) * 0.25), length: 0.1, velocity: 44 + (s % 4 == 3 ? 16 : 0)) }
            if inPhrase == 3 { clap.add(60, at: beat(bar, 3.75), length: 0.2, velocity: 70) }
        }

        // Bridge: half-time and heavy, metal instead of hats.
        let bridge = section("BRIDGE")
        for bar in bridge.bar ..< bridge.bar + bridge.bars {
            let odd = (bar - bridge.bar) % 2 == 0
            kick.add(36, at: beat(bar), length: 0.25, velocity: 118)
            kick.add(36, at: beat(bar, 0.75), length: 0.25, velocity: 84)
            kick.add(36, at: beat(bar, 2.5), length: 0.25, velocity: 104)
            snare.add(50, at: beat(bar, 2), length: 0.25, velocity: 120)
            clap.add(60, at: beat(bar, 2), length: 0.25, velocity: 92)
            if odd { metal.add(60, at: beat(bar), length: 0.5, velocity: 112) }
            metal.add(64, at: beat(bar, 1.5), length: 0.5, velocity: 76)
            if !odd { impact.add(40, at: beat(bar, 3.5), length: 0.4, velocity: 100) }
            for e in 0..<8 { shaker.add(60, at: beat(bar, Double(e) * 0.5), length: 0.1, velocity: e % 2 == 0 ? 60 : 36) }
        }
        // Into the last chorus: everything lands together.
        metal.add(60, at: beat(section("CHORUS 3").bar), length: 0.6, velocity: 120)
        impact.add(40, at: beat(section("CHORUS 1").bar), length: 0.4, velocity: 110)
        impact.add(40, at: beat(section("CHORUS 3").bar), length: 0.4, velocity: 120)

        // Outro: the beat thins to a half-time pulse and stops.
        let outro = section("OUTRO")
        for bar in outro.bar ..< outro.bar + 4 {
            kick.add(36, at: beat(bar), length: 0.25, velocity: 96 - (bar - outro.bar) * 10)
            snare.add(50, at: beat(bar, 2), length: 0.25, velocity: 90 - (bar - outro.bar) * 10)
        }
        return [kick, snare, clap, hats, shaker, metal, impact]
    }

    /// A drum part as DrumKit pattern clips: a 4-bar (64-step) pattern per
    /// block of each section; identical blocks in a row become one clip that
    /// repeats its pattern.
    static func drumTrack(_ part: DrumPart, accent: LYAccent) -> LYTrack {
        var clips: [LYClip] = []
        let stepsPerBlock = 64
        for s in sections {
            var block = 0
            var previous: (steps: [Bool], locks: [LYStepParameters])?
            while block * 4 < s.bars {
                let firstBar = s.bar + block * 4
                let bars = min(4, s.bars - block * 4)
                var steps = Array(repeating: false, count: stepsPerBlock)
                var locks = Array(repeating: LYStepParameters.default, count: stepsPerBlock)
                for i in 0..<(bars * 16) {
                    if let velocity = part.hits[firstBar * 16 + i] {
                        steps[i] = true
                        locks[i].velocity = velocity
                    }
                }
                block += 1
                guard steps.contains(true) else { previous = nil; continue }
                if let previous, previous.steps == steps, previous.locks == locks, var last = clips.popLast(),
                   last.startBeat + last.lengthBeats == Double(firstBar) * 4 {
                    last.lengthBeats += Double(bars) * 4
                    clips.append(last)
                } else {
                    clips.append(LYClip(name: s.name, kind: .pattern, startBeat: Double(firstBar) * 4, lengthBeats: Double(bars) * 4,
                                        steps: steps, stepParameters: locks))
                }
                previous = (steps, locks)
            }
        }
        var track = LYTrack(name: part.name, kind: .drumkit, accent: accent, volumeDB: part.volumeDB, pan: part.pan, clips: clips)
        track.drumPresetID = part.preset
        track.chokeGroup = part.chokeGroup
        track.fx = part.fx
        return track
    }

    // MARK: Bass

    static func bass() -> [Part] {
        var sub = Part(name: "SUB", sound: "WOUND SUB", volumeDB: -12, fx: FX.tape(0.35))
        var drive = Part(name: "BASS", sound: "RUSTED PISTON", volumeDB: -13, grit: 0.45, fx: FX.amp(0.55))
        var stutter = Part(name: "STUTTER", sound: "SEIZURE", volumeDB: -16, grit: 0.5)

        func subRoot(_ root: Int) -> Int { root - 12 >= 26 ? root - 12 : root }

        // Verses: long sub notes that push into the next bar.
        for bar in barsOf(["VERSE 1", "VERSE 2"]) {
            let root = chord(at: bar).root
            sub.add(subRoot(root), at: beat(bar), length: 3.4, velocity: 100)
            sub.add(subRoot(root), at: beat(bar, 3.5), length: 0.45, velocity: 80)
        }
        // Pre-choruses: eighth-note drive builds under the sub.
        for bar in barsOf(["PRE 1", "PRE 2"]) {
            let root = chord(at: bar).root
            sub.add(subRoot(root), at: beat(bar), length: 3.9, velocity: 100)
            for e in 0..<8 { drive.add(root, at: beat(bar, Double(e) * 0.5), length: 0.4, velocity: 70 + e * 3) }
        }
        // Choruses: the driving eighths, octave on the and-of-4.
        for bar in barsOf(["CHORUS 1", "CHORUS 2", "CHORUS 3"]) {
            let root = chord(at: bar).root
            sub.add(subRoot(root), at: beat(bar), length: 3.9, velocity: 104)
            for e in 0..<8 {
                let octave = e == 7 || e == 3
                drive.add(root + (octave ? 12 : 0), at: beat(bar, Double(e) * 0.5), length: 0.42, velocity: e % 2 == 0 ? 104 : 84)
            }
        }
        // Bridge: the stuttering bass carries it, two bars a chord.
        let bridge = section("BRIDGE")
        for bar in stride(from: bridge.bar, to: bridge.bar + bridge.bars, by: 2) {
            let root = chord(at: bar).root
            stutter.add(root, at: beat(bar), length: 7.9, velocity: 112)
            sub.add(subRoot(root), at: beat(bar), length: 7.9, velocity: 96)
        }
        // Outro: the last roots, then silence.
        let outro = section("OUTRO")
        for bar in outro.bar ..< outro.bar + 4 {
            sub.add(subRoot(chord(at: bar).root), at: beat(bar), length: 3.8, velocity: 90 - (bar - outro.bar) * 8)
        }
        return [sub, drive, stutter]
    }

    // MARK: Chords, arp, pluck

    static func harmony() -> [Part] {
        var pad = Part(name: "PAD", sound: "WET CONCRETE", volumeDB: -15, grit: 0.3, fx: FX.tape(0.4))
        var saws = Part(name: "SAWS", sound: "NERVE FIELD", volumeDB: -11, grit: 0.55, fx: FX.tape(0.5))
        var arp = Part(name: "ARP", sound: "MACHINE LOOM", volumeDB: -16, pan: 0.2, grit: 0.4)
        var pluck = Part(name: "GLASS", sound: "RAZOR PLUCK", volumeDB: -15, pan: -0.25, grit: 0.4, fx: FX.decimated(0.25))

        // Pad: under intro, verses, bridge and outro, a bar per chord.
        for bar in barsOf(["INTRO", "VERSE 1", "VERSE 2", "OUTRO"]) {
            pad.chord(chord(at: bar).voicing, at: beat(bar), length: 3.95, velocity: 80)
        }
        let bridge = section("BRIDGE")
        for bar in stride(from: bridge.bar, to: bridge.bar + bridge.bars, by: 2) {
            pad.chord(chord(at: bar).voicing, at: beat(bar), length: 7.9, velocity: 84)
        }
        // Big saws: pre-choruses and choruses, doubled an octave up in the choruses.
        for bar in barsOf(["PRE 1", "PRE 2"]) {
            saws.chord(chord(at: bar).voicing, at: beat(bar), length: 3.95, velocity: 76)
        }
        for bar in barsOf(["CHORUS 1", "CHORUS 2", "CHORUS 3"]) {
            let c = chord(at: bar)
            saws.chord(c.voicing + [c.voicing[0] + 12], at: beat(bar), length: 3.95, velocity: 96)
        }
        // Arp: the chord held a bar at a time; the arpeggiator plays it on the grid.
        for bar in barsOf(["INTRO", "VERSE 1", "PRE 1", "VERSE 2", "PRE 2", "OUTRO"]) where !(bar < 2) {
            arp.chord(chord(at: bar).voicing, at: beat(bar), length: 3.98, velocity: bar < 8 ? 70 : 92)
        }
        // Glass counter-line in the choruses: an eighth-note ostinato on the chord tones.
        for bar in barsOf(["CHORUS 1", "CHORUS 2", "CHORUS 3"]) {
            let v = chord(at: bar).voicing
            let line = [v[2] + 12, v[1] + 12, v[0] + 12, v[1] + 12, v[2] + 12, v[1] + 12, v[0] + 24, v[1] + 12]
            for (e, pitch) in line.enumerated() {
                pluck.add(pitch, at: beat(bar, Double(e) * 0.5), length: 0.4, velocity: e % 2 == 0 ? 96 : 72)
            }
        }
        return [pad, saws, arp, pluck]
    }

    // MARK: Melody

    typealias Phrase = [(Double, Double, Int)]      // beat in the phrase, length, pitch

    /// Verse melody, 8 bars: F minor, around the fifth, falling to the root.
    static let verseA: Phrase = [
        (0.5, 0.5, 72), (1, 0.5, 72), (1.5, 1, 70), (2.5, 1.5, 68),
        (4.5, 0.5, 68), (5, 0.5, 70), (5.5, 1, 72), (6.5, 1.5, 68),
        (8.5, 0.5, 67), (9, 0.5, 68), (9.5, 1, 70), (10.5, 0.5, 68), (11, 1, 67),
        (12, 2.5, 63),
        (16.5, 0.5, 72), (17, 0.5, 72), (17.5, 1, 75), (18.5, 1.5, 72),
        (20.5, 0.5, 73), (21, 0.5, 72), (21.5, 1, 70), (22.5, 1.5, 68),
        (24.5, 0.5, 67), (25, 0.5, 68), (25.5, 0.5, 70), (26, 1, 72), (27, 1, 70),
        (28, 3, 67),
    ]
    /// Pre-chorus: a stepwise climb, twice, the second time reaching higher.
    static let pre: Phrase = [
        (0, 1, 65), (1, 1, 68), (2, 2, 70),
        (4, 1, 70), (5, 1, 72), (6, 2, 73),
        (8, 1, 72), (9, 1, 73), (10, 2, 75),
        (12, 3.5, 75),
        (16, 1, 70), (17, 1, 72), (18, 2, 73),
        (20, 1, 73), (21, 1, 75), (22, 2, 77),
        (24, 2, 77), (26, 2, 75),
        (28, 1, 73), (29, 1, 75), (30, 1.5, 77),
    ]
    /// Chorus hook, 8 bars: a falling syncopated figure repeated, landing on
    /// the root, then on the third for the lift.
    static let hook: Phrase = [
        (0, 0.75, 77), (0.75, 0.75, 75), (1.5, 0.5, 73), (2, 1, 72), (3, 1, 73),
        (4, 0.75, 72), (4.75, 0.75, 70), (5.5, 0.5, 68), (6, 2, 72),
        (8, 0.75, 77), (8.75, 0.75, 75), (9.5, 0.5, 73), (10, 1, 72), (11, 1, 70),
        (12, 1.5, 68), (13.5, 0.5, 67), (14, 2, 65),
        (16, 0.75, 77), (16.75, 0.75, 75), (17.5, 0.5, 73), (18, 1, 72), (19, 1, 73),
        (20, 0.75, 72), (20.75, 0.75, 70), (21.5, 0.5, 68), (22, 2, 72),
        (24, 0.75, 77), (24.75, 0.75, 75), (25.5, 0.5, 73), (26, 1, 75), (27, 1, 77),
        (28, 1, 72), (29, 1, 70), (30, 2, 68),
    ]
    /// The intro and outro motif on piano.
    static let pianoMotif: Phrase = [
        (0, 2, 72), (2, 2, 68), (4, 4, 65),
        (8, 2, 72), (10, 2, 75), (12, 4, 70),
        (16, 2, 72), (18, 2, 68), (20, 4, 65),
        (24, 2, 68), (26, 2, 67), (28, 4, 63),
    ]

    static func melody() -> [Part] {
        var voice = Part(name: "LEAD", sound: "DEAD FREQUENCY", volumeDB: -10, grit: 0.35)
        var hookLead = Part(name: "HOOK", sound: "TORN SIREN", volumeDB: -5, grit: 0.45, fx: FX.amp(0.4))
        var hookHigh = Part(name: "HOOK HIGH", sound: "CATHODE", volumeDB: -16, pan: 0.15, grit: 0.4)
        var scream = Part(name: "SCREAM", sound: "SCREAMING WIRE", volumeDB: -14, grit: 0.6)
        var piano = Part(name: "PIANO", sound: "SCORCHED EP", volumeDB: -15, pan: -0.1, grit: 0.35)

        func play(_ phrase: Phrase, into part: inout Part, at bar: Int, transpose: Int = 0, velocity: Int = 100, until: Double = .infinity) {
            for (start, length, pitch) in phrase where start < until {
                part.add(pitch + transpose, at: beat(bar, start), length: length, velocity: velocity - (Int(start * 7) % 3) * 6)
            }
        }
        // Verses: the melody twice in verse 1, once in verse 2.
        play(verseA, into: &voice, at: section("VERSE 1").bar)
        play(verseA, into: &voice, at: section("VERSE 1").bar + 8)
        play(verseA, into: &voice, at: section("VERSE 2").bar, velocity: 108)
        // Pre-choruses on the same voice.
        play(pre, into: &voice, at: section("PRE 1").bar)
        play(pre, into: &voice, at: section("PRE 2").bar, velocity: 108)
        // Choruses: the hook twice each; the last chorus doubles it an octave up.
        for name in ["CHORUS 1", "CHORUS 2", "CHORUS 3"] {
            play(hook, into: &hookLead, at: section(name).bar)
            play(hook, into: &hookLead, at: section(name).bar + 8)
        }
        play(hook, into: &hookHigh, at: section("CHORUS 3").bar, transpose: 12, velocity: 90)
        play(hook, into: &hookHigh, at: section("CHORUS 3").bar + 8, transpose: 12, velocity: 96)
        // Bridge: the screaming lead climbs over two-bar chords.
        let bridge = section("BRIDGE").bar
        for (i, pitch) in [65, 68, 67, 72].enumerated() {
            scream.add(pitch, at: beat(bridge + i * 2), length: 7.8, velocity: 90 + i * 8)
        }
        // Piano: the motif in the intro and outro, root notes in the bridge.
        play(pianoMotif, into: &piano, at: section("INTRO").bar, velocity: 84)
        for bar in 0..<8 where bar % 2 == 0 {
            piano.add(chord(at: bar).root, at: beat(bar), length: 7.5, velocity: 70)
        }
        play(pianoMotif, into: &piano, at: section("OUTRO").bar, velocity: 72)
        for bar in stride(from: bridge, to: bridge + 8, by: 2) {
            piano.add(chord(at: bar).root + 12, at: beat(bar), length: 7.5, velocity: 88)
        }
        return [voice, hookLead, hookHigh, scream, piano]
    }

    // MARK: FX

    static func effects() -> [Part] {
        var ghosts = Part(name: "RADIO", sound: "RADIO GHOSTS", volumeDB: -23, pan: 0.1)
        var riser = Part(name: "RISER", sound: "TENSION RISER", volumeDB: -18)
        var stop = Part(name: "TAPE STOP", sound: "TAPE STOP", volumeDB: -19)

        ghosts.add(60, at: 0, length: beat(8) - 0.5, velocity: 90)
        ghosts.add(60, at: beat(section("OUTRO").bar), length: beat(8) - 0.5, velocity: 80)
        for name in ["PRE 1", "PRE 2"] {
            let s = section(name)
            riser.add(60, at: beat(s.bar + s.bars - 2), length: 8, velocity: 110)
        }
        // Chorus 2 grinds to a halt into the bridge.
        stop.chord(Fm.voicing, at: beat(section("BRIDGE").bar - 1, 2), length: 1.95, velocity: 100)
        return [ghosts, riser, stop]
    }

    // MARK: Session

    /// Each part cut into one clip per section it plays in.
    static func track(_ part: Part, accent: LYAccent) -> LYTrack {
        var clips: [LYClip] = []
        for s in sections {
            let start = Double(s.bar) * 4, end = Double(s.bar + s.bars) * 4
            let inside = part.notes.filter { $0.start >= start - 0.0001 && $0.start < end - 0.0001 }
            guard !inside.isEmpty else { continue }
            let notes = inside.map { note -> LYNote in
                var n = note
                n.start -= start
                n.length = min(n.length, end - note.start)
                return n
            }
            clips.append(LYClip(name: s.name, kind: .notes, startBeat: start, lengthBeats: end - start, notes: notes, noteLoopBeats: end - start))
        }
        var track = LYTrack(name: part.name, kind: .instrument, accent: accent, volumeDB: part.volumeDB, pan: part.pan, clips: clips)
        var patch = LYSynthPatch.factory(named: part.sound)
        if part.grit > 0 { patch?.set(LY_MACRO4, part.grit) }
        track.synth = patch
        track.fx = part.fx
        return track
    }

    static var parts: [Part] { bass() + harmony() + melody() + effects() }
    static var drumParts: [DrumPart] { drums() }

    static func session() -> LYLLTHSession {
        let accents: [LYAccent] = [.teal, .teal, .indigo, .indigo, .purple, .purple]
        var tracks = drumParts.enumerated().map { index, part in drumTrack(part, accent: accents[index % accents.count]) }
        let first = tracks.count
        tracks += parts.enumerated().map { index, part in track(part, accent: accents[(first + index) % accents.count]) }
        tracks.append(LYTrack(name: "VOCAL", kind: .audio, accent: accents[tracks.count % accents.count], volumeDB: -6, inputName: "INPUT 1"))
        var session = LYLLTHSession(
            name: title,
            bpm: bpm,
            numerator: 4,
            denominator: 4,
            sampleRate: 48_000,
            bitDepth: 24,
            loopRange: nil,
            activePatternIndex: nil,
            songKey: SongKey(root: 5, isMinor: true),
            arrangementEditor: .default,
            tracks: tracks
        )
        session.mainFX = FX.main
        return session
    }

    // MARK: Effects

    /// The inserts that take the demo off the clean synth-pop shelf: tape and
    /// amp drive on the parts, glue and loudness on MAIN.
    enum FX {
        static func tape(_ drive: Float, mix: Float = 0.9) -> LYFXRack {
            var rack = LYFXRack()
            var tape = TapeSaturationState()
            tape.tapeType = 2
            tape.drive = drive
            tape.mix = mix
            tape.isBypassed = false
            rack.tape = tape
            rack.order = [.eq, .comp, .tape, .reverb]
            return rack
        }

        /// Amp and cabinet, blended so the part keeps its low end.
        static func amp(_ mix: Float) -> LYFXRack {
            var rack = LYFXRack()
            var cab = CabinetState()
            cab.voice = 2
            cab.cab = 1
            cab.drive = 0.55
            cab.mix = mix
            cab.isBypassed = false
            rack.cabinet = cab
            rack.order = [.eq, .comp, .cabinet, .reverb]
            return rack
        }

        static func decimated(_ amount: Float) -> LYFXRack {
            var rack = tape(0.35)
            var decimator = DecimatorState()
            decimator.destroy = amount
            decimator.crush = amount * 0.6
            decimator.isBypassed = false
            rack.decimator = decimator
            rack.order = [.eq, .comp, .tape, .decim, .reverb]
            return rack
        }

        static var kick: LYFXRack {
            var rack = tape(0.55, mix: 1)
            rack.compressor = punch(threshold: -10, attack: 18, release: 90, distortion: .soft)
            return rack
        }

        static var snare: LYFXRack {
            var rack = tape(0.6, mix: 1)
            rack.compressor = punch(threshold: -14, attack: 6, release: 110, distortion: .hard)
            return rack
        }

        static func punch(threshold: Float, attack: Float, release: Float,
                          distortion: CompressorCharacter.Distortion) -> CompressorState {
            var comp = CompressorState()
            comp.threshold = threshold
            comp.ratio = 4
            comp.attackMilliseconds = attack
            comp.releaseMilliseconds = release
            comp.circuit = .fet
            comp.distortion = distortion
            comp.makeup = 3
            comp.isBypassed = false
            return comp
        }

        /// MAIN: mud out, air in, glued by the bus compressor, driven into
        /// tape and brought up to level by the limiter.
        static var main: LYFXRack {
            var rack = tape(0.3, mix: 0.7)
            var bands = LYFXRack.defaultBands
            bands[0].gain = 1.5
            bands[1].gain = -2.5
            bands[3].gain = 1.5
            bands[4].gain = 3
            rack.eqBands = bands
            var comp = punch(threshold: -18, attack: 20, release: 160, distortion: .off)
            comp.ratio = 2
            comp.circuit = .vca
            comp.makeup = 2
            rack.compressor = comp
            var finale = FinaleState()
            finale.mode = 2
            finale.gainDb = 3
            finale.isBypassed = false
            rack.finale = finale
            rack.order = [.eq, .comp, .tape, .reverb, .finale]
            return rack
        }
    }
}

extension LYLLTHSession {
    /// A new project: the demo song. `starter()` stays the plain scaffold the
    /// tests build on.
    static func demoSong() -> LYLLTHSession { LYDemoSong.session() }
}
