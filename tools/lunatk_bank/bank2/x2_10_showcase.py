"""EXPANSION 02 / EXPERIMENTAL BUT MUSICAL SHOWCASES. Each one leans on a
different corner of the engine: trackers, env slopes, cross-modulated
LFO rates, dual-warp oscillators, parallel filter routing, MPE."""

from bank2._common import echo, velocity, vibrato
from bank2._showcase import dimension, drift, fsat, morph, punch, vintage
from bank2._x2 import N, burn, dc_guard, hall, mono, plate, poly


def presets():
    out = []

    # 91 HARMONIC PARASITE (pad): two tables feeding on each other: A FMs
    # with warp FM, B ring-modulates with RM warp; each warp depth is driven
    # by an LFO whose rate the other LFO modulates.
    p = N("HARMONIC PARASITE", "PAD", "NS DUST ORACLE", "NS HOLLOW BONE")
    p.osc(0, level=0.55, wt=0.3, unison=3, detune=0.07, width=0.4, warp="FM", warp_amt=0.08)
    p.osc(1, level=0.3, wt=0.4, octave=1, unison=3, detune=0.06, width=0.9, warp="RM", warp_amt=0.1)
    p.filter("LP24", hz=2200, res=0.15, keytrack=0.35)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP24", hz=150)
    p.env(1, a=0.8, d=3.0, s=0.9, r=1.8)
    poly(p, vel=0.3)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.31, mode="FREE")
    p.lfo(2, "SMOOTH_RANDOM", hz=0.17, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "A_WARP", 0.15)
    p.motion("LFO2", "B_WARP", 0.2)
    p.mod("LFO1", "LFO2_RATE", 0.3)
    p.mod("LFO2", "LFO1_RATE", 0.3)
    p.motion("LFO1", "A_WTPOS", 0.35)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.42)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Two harmonic structures feeding on each other: an FM layer and a ring layer, each driven by a wander whose speed the other controls",
          "C3–C5", "Film, experimental pop, ambient", "Chords", "TEXTURE",
          "Mutates constantly but the chord never changes; MOTION 0 freezes the feeding")
    out.append(p)

    # 92 DIGITAL ORGANISM (lead): organic movement from TRACKERS: tracker 1
    # maps velocity to a curve on the table, tracker 2 maps a random to FM;
    # env slopes shape an animal-like attack.
    p = N("DIGITAL ORGANISM", "LEAD", "NS THROAT", "DIGITAL")
    p.osc(0, level=0.58, wt=0.3, warp="FM", warp_amt=0.05)
    p.osc(1, level=0.25, wt=0.5)
    p.filter("LP24", hz=2400, res=0.2, keytrack=0.6, env=0.3)
    fsat(p, "SHAPER", drive=0.3, mix=0.6)
    p.filter2("HP12", hz=190)
    p.env(1, a=0.02, d=0.6, s=0.88, r=0.25)
    p.set("env1.slope", 0.4)
    p.env(2, a=0.004, d=0.4, s=0.35, r=0.2)
    p.set("env2.slope", -0.4)
    mono(p, glide=0.06)
    velocity(p, 0.5, 0.2)
    vibrato(p)
    p.tracker(1, "VELOCITY", [0.0, 0.05, 0.1, 0.2, 0.35, 0.3, 0.25, 0.4, 0.6, 0.55, 0.5, 0.7, 0.85, 0.8, 0.9, 1.0])
    p.mod("TRACK1", "A_WTPOS", 0.4)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.9, mode="TRIG")
    p.tracker(2, "LFO1", [0.5, 0.45, 0.3, 0.2, 0.35, 0.6, 0.8, 0.7, 0.4, 0.3, 0.5, 0.7, 0.9, 0.6, 0.4, 0.5])
    p.set("macro2", 0.45)
    p.mod("TRACK2", "A_WARP", 0.25, aux="MACRO2")
    p.motion("LFO1", "B_WTPOS", 0.35)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.4, base=0.2)
    p.doc("A digital creature that moves like something alive: trackers bend velocity and a random through drawn curves into the vowel table and the FM",
          "C3–C5", "Art pop, electronica, film", "Melodies", "FOREGROUND",
          "The trackers make the response non-linear: similar velocities can sound quite different")
    out.append(p)

    # 93 BLACK MATTER (drone): extreme density: both oscillators with
    # STACK OCTAVE_FIFTH, B shifted a few Hz (controlled inharmonicity),
    # mono lows, a slow wander on the shift.
    p = N("BLACK MATTER", "DRONE", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.5, wt=0.95, stack="OCTAVE_FIFTH")
    p.osc(1, level=0.28, wt=0.2, octave=1, stack="OCTAVE", unison=2, detune=0.05, width=0.35)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.52, mix=0.12)
    p.filter("LP24", hz=1100, res=0.2, keytrack=0.4, drive=0.35)
    p.filter2("HP12", hz=45)
    p.env(1, a=2.0, d=1.0, s=1.0, r=3.0)
    poly(p, voices=6, vel=0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.26, [("B_WTPOS", 0.4), ("INS2_FREQ", 0.008)])
    drift(p, 2, 0.07, [("CUTOFF", 0.1)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.45, width=0.25)
    burn(p, "TUBE", drive=0.4, base=0.18)
    dc_guard(p)
    p.doc("Extremely dense: octave-and-fifth stacks on both oscillators, the upper one shifted a few hertz off the series for a dark, controlled inharmonicity",
          "D1–D3", "Film, industrial, dark ambient", "Single held notes", "TEXTURE",
          "The shift is small and slow; it thickens rather than detunes")
    out.append(p)

    # 94 THE MACHINE IS ALIVE (motion): a mechanical organism: a TRIG
    # performer (the machine) whose depth breathes on a slow random (the
    # organism), modulating a formant filter and fold.
    p = N("THE MACHINE IS ALIVE", "MOTION", "NS GRINDSTONE", "NS THROAT")
    p.osc(0, level=0.5, wt=0.3)
    p.osc(1, level=0.32, wt=0.4)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.4)
    p.filter("FORMANT", hz=650, res=0.35, keytrack=0.3, mix=0.5)
    p.filter2("LP24", hz=2600, res=0.12, drive=0.3)
    p.env(1, a=0.02, d=1.0, s=1.0, r=0.4)
    poly(p, vel=0.35)
    p.performer(1, {0: [(1.0, "DECAY"), (0.2, "HOLD"), (0.6, "DECAY"), (0.0, "HOLD"), (0.8, "RISE"), (0.3, "HOLD"), (0.5, "DECAY"), (0.0, "HOLD")] * 2},
                mode="SONG", rate="1/16")
    p.lfo(1, "SMOOTH_RANDOM", hz=0.25, mode="FREE")
    p.set("macro2", 0.6)
    p.mod("PERF1", "INS1_AMOUNT", 0.45, aux="LFO1")
    p.motion("PERF1", "CUTOFF", 0.2)
    p.motion("LFO1", "B_WTPOS", 0.45)
    p.tone("F2_CUTOFF", 0.16)
    plate(p, 0.08)
    burn(p, "TUBE", drive=0.45, base=0.22)
    p.doc("A mechanical organism: a sixteenth-note machine working a vowel filter and a fold, its effort rising and falling on a slow random breath",
          "C3–C5", "Industrial, art pop, film", "Hold chords", "RHYTHM",
          "The machine keeps time; the breath decides how hard it works")
    out.append(p)

    # 95 BEAUTIFUL MALFUNCTION (keys): instability as a feature: a per-note
    # RANDOM on pitch (tiny), fold and table; a stumbling S&H on decimation.
    p = N("BEAUTIFUL MALFUNCTION", "KEYS", "NS RADIANT", "NS FRACTURE")
    p.osc(0, level=0.55, wt=0.5)
    p.osc(1, level=0.25, wt=0.1, octave=1)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.3)
    p.filter("LP24", hz=2800, res=0.15, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=1.3, s=0.45, r=0.45)
    poly(p, vel=0.5)
    velocity(p, 0.5, 0.22)
    p.mod("RANDOM", "PITCH", 0.0015)
    p.mod("RANDOM", "INS1_AMOUNT", 0.2)
    p.mod("RANDOM", "B_WTPOS", 0.3)
    p.lfo(1, "SAMPLE_HOLD", hz=3.0, mode="TRIG", smooth=True)
    p.set("macro2", 0.4)
    p.motion("LFO1", "B_WTPOS", 0.2)
    drift(p, 2, 0.29, [("A_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.12)
    burn(p, "SOFT", drive=0.3, base=0.16)
    fsat(p, "LIGHT", drive=0.3)
    p.doc("An emotional keyboard that malfunctions beautifully: every note lands a hair off, folds a little differently, and its fracture layer stumbles",
          "C3–C5", "Art pop, dark pop, film", "Chords and melodies", "FOREGROUND",
          "The pitch randomness is a fraction of a cent; it reads as alive, not out of tune")
    out.append(p)

    # 96 FRACTURED REALITY (pad): parallel filter routing: layer A through a
    # comb, layer B through a phaser, controlled dissonance from a +1 semitone
    # ghost (-24 dB) and opposite-phase pan sines.
    p = N("FRACTURED REALITY", "PAD", "ANALOG", "NS SERPENT")
    p.osc(0, level=0.55, wt=0.85, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.3, octave=1, unison=3, detune=0.06, width=0.9)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.57, mix=0.08)
    p.filter("COMB_POS", hz=700, res=0.4, keytrack=1.0, mix=0.35)
    p.filter2("PHASER", hz=1400, res=0.35, mix=0.45)
    p.set("filter.routing", 1)
    p.env(1, a=0.8, d=3.0, s=0.9, r=1.8)
    poly(p, vel=0.3)
    p.lfo(1, "SINE", hz=0.13, mode="FREE")
    p.lfo(2, "SINE", hz=0.13, mode="FREE", phase=0.5)
    p.set("macro2", 0.5)
    p.motion("LFO1", "A_PAN", 0.35)
    p.motion("LFO2", "B_PAN", 0.35)
    drift(p, 3, 0.31, [("F2_CUTOFF", 0.25), ("B_WTPOS", 0.35)])
    p.eq(low=-3, low_hz=170)
    p.tone("F2_CUTOFF", 0.2)
    hall(p, mix=0.16, decay=0.42)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Reality split in two: one layer through a comb, the other through a phaser, the two swinging to opposite speakers, a faint shifted ghost between them",
          "C3–C5", "Film, experimental pop, ambient", "Chords held for bars", "TEXTURE",
          "The dissonance is a single shifted copy at 8%: felt, not heard as wrong")
    out.append(p)

    # 97 CONTROLLED CHAOS (lead): four modulators into interacting targets
    # (feedback, fold, table, resonance), each bounded, level-compensated.
    p = N("CONTROLLED CHAOS", "LEAD", "ANALOG", "NS TENDON")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.28, wt=0.3)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.35)
    p.filter("LADDER", hz=1800, res=0.3, keytrack=0.6, env=0.3)
    p.feedback(amount=0.1, drive=0.6, tone=0.6)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.002, d=0.5, s=0.9, r=0.2)
    mono(p)
    velocity(p, 0.5, 0.22)
    vibrato(p)
    p.lfo(1, "SAMPLE_HOLD", hz=4.1, mode="FREE", smooth=True)
    p.lfo(2, "SMOOTH_RANDOM", hz=0.47, mode="FREE")
    p.lfo(3, "TRIANGLE", hz=0.23, mode="FREE")
    p.set("macro2", 0.45)
    p.motion("LFO1", "INS1_AMOUNT", 0.15)
    p.motion("LFO2", "FEEDBACK", 0.1)
    p.motion("LFO3", "B_WTPOS", 0.4)
    p.motion("LFO2", "RES", 0.06)
    p.mod("MODWHEEL", "LFO1_RATE", 0.4)
    p.tone("CUTOFF", 0.2)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.5, base=0.28)
    p.doc("Chaos on a leash: a stepped random on the fold, a smooth random on the loop, a triangle on the tendon table; the wheel speeds the chaos up",
          "C3–C5", "Industrial, noise pop", "Held notes and riffs", "FOREGROUND",
          "Each modulator is bounded; nothing runs away from the pitch")
    out.append(p)

    # 98 ELECTRIC PHANTOM (lead): eerie: dual-warp oscillator (MIRROR then
    # BEND) scanned; VINTAGE drift; faint BREATH noise; late vibrato.
    p = N("ELECTRIC PHANTOM", "LEAD", "NS HOLLOW BONE", "GLASS")
    p.osc(0, level=0.58, wt=0.4, warp="MIRROR", warp_amt=0.15, warp2="BEND_POS", warp2_amt=0.15)
    p.osc(1, level=0.18, wt=0.5, octave=1)
    p.noise(0.04, type="BREATH", color=0.55, keytrack=True)
    p.filter("LP24", hz=2600, res=0.15, keytrack=0.6)
    p.filter2("HP12", hz=210)
    p.env(1, a=0.02, d=0.6, s=0.88, r=0.35)
    mono(p, glide=0.08)
    velocity(p, 0.5, 0.2)
    vintage(p, 0.4)
    vibrato(p, hz=4.4, depth=0.014, delay=0.7, rise=0.8)
    p.set("macro2", 0.45)
    drift(p, 1, 0.33, [("A_WARP", 0.15), ("A_WTPOS", 0.3)])
    drift(p, 2, 0.15, [("A_WARP2", 0.15)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/8", mix=0.1, feedback=0.25, amount=0.12, pingpong=True)
    plate(p, 0.12)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("An eerie melodic ghost: a hollow table mirrored and bent by two warps that drift on their own, breath around it, a pitch that never quite settles",
          "C3–C5", "Film, dark pop, horror", "Slow melodies", "FOREGROUND",
          "Two warps in series; each drifts on its own clock, so the shape keeps shifting")
    out.append(p)

    # 99 THE IMPOSSIBLE ENGINE (pad): everything at once, playable: 2 custom
    # tables with dual warps, both inserts, parallel comb + morph filters,
    # fsat + loop, 4 envelopes, 4 LFOs, both performers, a tracker, env slopes.
    p = N("THE IMPOSSIBLE ENGINE", "PAD", "NS NEON NERVE", "NS DUST ORACLE")
    p.osc(0, level=0.52, wt=0.3, unison=4, detune=0.08, width=0.4, warp="SYNC", warp_amt=0.1, warp2="FOLD", warp2_amt=0.1)
    p.osc(1, level=0.28, wt=0.4, octave=1, unison=4, detune=0.08, width=0.9, warp="PWM", warp_amt=0.15)
    p.insert(1, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.66, mix=0.08)
    p.filter("MORPH", hz=1800, res=0.2, keytrack=0.35)
    morph(p, 0.15)
    p.filter2("COMB_POS", hz=800, res=0.35, keytrack=1.0, mix=0.25)
    p.set("filter.routing", 1)
    fsat(p, "SOFT", drive=0.35)
    p.feedback(amount=0.05, drive=0.5, tone=0.5)
    p.env(1, a=0.9, d=3.0, s=0.9, r=2.0)
    p.env(3, a=6.0, d=0.1, s=1.0, r=2.0)
    p.env(4, a=12.0, d=0.1, s=1.0, r=2.0)
    p.set("env3.slope", 0.3)
    p.set("env4.slope", 0.5)
    p.mod("ENV3", "A_WTPOS", 0.4)
    p.mod("ENV4", "B_WTPOS", 0.5)
    p.mod("ENV4", "DIST_MIX", 0.2)
    poly(p, vel=0.3)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.3, -0.2, 0.5, 0.1, -0.4, 0.4, 0.2, -0.1)]}, mode="SONG", rate="1/8", steps=9)
    p.performer(2, {0: [(v, "GLIDE") for v in (0.2, -0.3, 0.6, -0.1, 0.4, -0.5, 0.3)]}, mode="SONG", rate="1/4", steps=7)
    p.tracker(1, "NOTE", [0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.72, 0.75, 0.78, 0.8, 0.82, 0.85])
    p.set("macro2", 0.5)
    p.mod("PERF1", "MORPH", 0.15, aux="MACRO2")
    p.mod("PERF2", "F2_CUTOFF", 0.15, aux="MACRO2")
    p.mod("TRACK1", "INS1_AMOUNT", 0.3)
    drift(p, 1, 0.31, [("A_WARP", 0.1), ("CUTOFF", 0.07)])
    drift(p, 2, 0.11, [("B_PAN", 0.35)])
    drift(p, 3, 0.053, [("INS2_FREQ", 0.01)])
    p.mod("MODWHEEL", "FEEDBACK", 0.15)
    p.mod("PRESSURE", "B_WARP", 0.2)
    dimension(p, mix=0.25, size=0.7)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.45)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("The engine at its limit and still playable: dual-warped custom tables, comb and ring inserts, parallel morph and comb filters, a loop, two slow envelopes, two performers, a tracker",
          "C3–C5", "Film, experimental pop", "Chords held for bars", "TEXTURE",
          "Every module is working, each gently; the result is dense, not chaotic")
    out.append(p)

    # 100 NIGHTSHAPE: TOTAL SYSTEM (pad): the ultimate showcase, poly and
    # playable as chords or a line.
    p = N("NIGHTSHAPE: TOTAL SYSTEM", "PAD", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.52, wt=0.2, unison=3, detune=0.07, width=0.3, warp="FM", warp_amt=0.05)
    p.osc(1, level=0.28, wt=0.15, octave=1, unison=5, detune=0.1, width=1.0, warp="ASYM_NEG", warp_amt=0.12)
    p.noise(0.03, type="BREATH", color=0.5, keytrack=True)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.25)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=1700, res=0.25, keytrack=0.35, env=0.2)
    fsat(p, "DIODE", drive=0.35)
    p.feedback(amount=0.05, drive=0.5, tone=0.55)
    p.filter2("HP24", hz=140)
    p.env(1, a=0.5, d=4.0, s=0.92, r=2.2)
    p.env(2, a=1.5, d=5.0, s=0.7, r=2.0)
    p.env(3, a=7.0, d=0.1, s=1.0, r=2.5, acurve=0.35)
    p.env(4, a=0.001, d=0.08, s=0.0, r=0.05)
    p.mod("ENV3", "B_WTPOS", 0.55)
    p.mod("ENV3", "DIM_MIX", 0.3)
    p.mod("ENV3", "INS1_AMOUNT", 0.15)
    p.mod("ENV4", "A_WARP", 0.25)
    poly(p, vel=0.3)
    p.mod("VELOCITY", "B_LEVEL", 0.12)
    p.mod("VELOCITY", "A_WTPOS", 0.25)
    p.mod("MODWHEEL", "FEEDBACK", 0.18)
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.25)
    p.mod("PRESSURE", "FSAT_DRIVE", 0.25)
    p.mod("TIMBRE", "B_WTPOS", 0.35)
    vintage(p, 0.2)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.4, -0.2, 0.6, 0.1, -0.5, 0.3, 0.8, -0.1, 0.5, 0.2)]}, mode="SONG", rate="1/8", steps=11)
    p.set("macro2", 0.5)
    p.mod("PERF1", "A_WTPOS", 0.2, aux="MACRO2")
    drift(p, 1, 0.32, [("CUTOFF", 0.07), ("B_WARP", 0.1)])
    drift(p, 2, 0.089, [("B_PAN", 0.2), ("INS2_FREQ", 0.008)])
    drift(p, 3, 0.041, [("FB_TONE", 0.2)])
    dimension(p, mix=0.0, size=0.8)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.46, size=0.8)
    burn(p, "TUBE", drive=0.45, base=0.18)
    p.doc("The whole system in one sound: FM-flicked obsidian over a wide grindstone layer, fold and comb, a diode ladder loop, an 11-step timbre walk, three clocks, blooming after seven seconds",
          "C3–C5", "Everything NIGHTSHAPE makes", "Chords or lines; velocity, wheel, pressure and MPE timbre all transform it", "FOREGROUND",
          "Centre and lows mono and steady; the width, the growl and the bloom are all above")
    out.append(p)

    return out
