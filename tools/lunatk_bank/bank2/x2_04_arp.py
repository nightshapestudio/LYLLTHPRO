"""EXPANSION 02 / CHAOTIC MELODIC ARPEGGIATORS. The step pattern (level,
length, transpose, rests, pattern length) is the composition; the performers,
which run their own step counts, supply cross-rhythms the arp alone cannot."""

from bank2._common import echo, velocity
from bank2._showcase import dimension, drift, fsat, punch, vintage
from bank2._x2 import N, burn, plate, poly
from bank2.show_arp import S, pattern


def A(name, a="ANALOG", b="BASIC"):
    return N(name, "ARP", a, b)


def presets():
    out = []

    # 31 FRACTURED PULSE: 15 steps (one short of the bar), octave displacement
    # on irregular steps; accents drive a LINFOLD via velocity.
    p = A("FRACTURED PULSE", "NS OBSIDIAN", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.3, wt=1.0, octave=-1)
    p.filter("LP24", hz=1600, res=0.3, keytrack=0.5, env=0.45, drive=0.4)
    p.filter2("HP12", hz=140)
    p.env(1, a=0.001, d=0.22, s=0.35, r=0.07)
    p.env(2, a=0.001, d=0.1, s=0.15, r=0.06)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AbcAxbAcOAbxcAo", {"A": (1.0, 0.5, 0), "b": (0.45, 0.3, 0), "c": (0.65, 0.4, 0),
                                    "x": (0.8, 0.35, -12), "O": (0.95, 0.6, 12), "o": (0.55, 0.3, 12)}))
    velocity(p, 0.6, 0.3)
    p.mod("VELOCITY", "A_WTPOS", 0.4)
    p.set("macro2", 0.45)
    drift(p, 1, 0.33, [("A_WTPOS", 0.3), ("CUTOFF", 0.1)])
    p.tone("CUTOFF", 0.18)
    plate(p, 0.06)
    burn(p, "LINFOLD", drive=0.45, base=0.3)
    p.doc("Fifteen steps against sixteen with octave jumps in odd places; accents fold the obsidian table harder. Unstable, and it still grooves",
          "C3–C5", "Industrial, dark electro", "Hold a note or a fifth", "FOREGROUND",
          "The phrase drifts a sixteenth each bar and lines up again after fifteen bars")
    out.append(p)

    # 32 BLACK ALGORITHM: a 16-step motif; a TRIG performer with 12 steps
    # re-colours the timbre so each pass differs.
    p = A("BLACK ALGORITHM", "NS DUST ORACLE", "BASIC")
    p.osc(0, level=0.58, wt=0.35)
    p.osc(1, level=0.2, wt=0.0, octave=-1)
    p.filter("LP24", hz=2000, res=0.22, keytrack=0.5, env=0.35)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=0.28, s=0.3, r=0.12)
    poly(p, vel=0.6)
    p.arp(mode="UP", rate="1/16", octaves=1, gate=0.75)
    pattern(p, [(1.0, 0.6, 0), (0.5, 0.3, 0), (0.7, 0.4, 0), (0.85, 0.7, 7), None, (0.5, 0.3, 0), (0.75, 0.5, 12), (0.5, 0.3, 0),
                (0.9, 0.6, 0), (0.5, 0.3, 0), (0.7, 0.4, 0), (0.85, 0.7, 5), None, (0.55, 0.3, 0), (0.8, 0.5, -12), (0.45, 0.3, 0)])
    velocity(p, 0.6, 0.25)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.4, -0.3, 0.8, 0.1, -0.6, 0.5, 0.9, -0.2, 0.3, -0.8, 0.6)]}, mode="SONG", rate="1/16", steps=12)
    p.set("macro2", 0.45)
    p.mod("PERF1", "A_WTPOS", 0.35, aux="MACRO2")
    drift(p, 1, 0.29, [("CUTOFF", 0.1)])
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.08)
    burn(p, "SOFT", drive=0.35, base=0.18)
    p.context(unpitched=True)
    p.doc("A hypnotic sixteen-step motif (up a fifth, an octave, a fourth, down an octave) re-coloured by a twelve-step timbre performer, so no two bars sound the same",
          "C3–C5", "Dark pop, electronica", "Hold chords", "FOREGROUND",
          "The notes repeat every bar; the colour pattern repeats every three quarters: 12 against 16")
    out.append(p)

    # 33 ELECTRIC PARASITE: competing rhythm (arp, 1/16) vs harmonic motion
    # (performer, 1/8 triplet-ish 1/12 rate) on the ring insert.
    p = A("ELECTRIC PARASITE", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.3, wt=0.4)
    p.insert(1, "RING", after=True, amount=0.4, freq=0.62, mix=0.0)
    p.filter("LP24", hz=1800, res=0.3, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.2, s=0.3, r=0.07)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.85)
    pattern(p, [(1.0, 0.8, 0), (0.5, 0.25, 0), (0.7, 0.4, 12), (0.5, 0.25, 0), (0.9, 0.9, 0), (0.5, 0.2, 0), (0.65, 0.35, 0), (1.0, 0.2, 12),
                (0.5, 0.25, 0), (0.8, 0.6, -12), (0.5, 0.25, 0), (0.7, 0.4, 0)])
    velocity(p, 0.6, 0.25)
    p.performer(1, {0: [(1.0, "DECAY"), (0.0, "HOLD"), (0.6, "DECAY")] * 5 + [(0.0, "HOLD")]}, mode="SONG", rate="1/12", steps=16)
    p.set("macro2", 0.45)
    p.mod("PERF1", "INS1_AMOUNT", 0.45, aux="MACRO2")
    p.set("ins1.mix", 0.3)
    drift(p, 1, 0.31, [("B_WTPOS", 0.3), ("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.18)
    burn(p, "DIODE", drive=0.45, base=0.25)
    p.doc("A parasite feeding on the rhythm: sixteenth steps with changing lengths and octave jumps, and a ring modulation pulsing in triplets against them",
          "C3–C5", "Industrial, EBM, alt-electronic", "Hold single notes", "FOREGROUND",
          "Triplets against sixteenths: tension without a single wrong note")
    out.append(p)

    # 34 MACHINE LANGUAGE: a phrase in two halves (question 7 steps, answer
    # 6 steps), a FORMANT filter stepped per note by the performer (it "speaks").
    p = A("MACHINE LANGUAGE", "NS THROAT", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.3, wt=0.9)
    p.filter("FORMANT", hz=700, res=0.4, keytrack=0.3, mix=0.6)
    p.filter2("LP24", hz=2600, res=0.15, drive=0.35)
    p.env(1, a=0.001, d=0.22, s=0.35, r=0.08)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(1.0, 0.4, 0), (0.6, 0.3, 0), (0.7, 0.3, 7), (0.5, 0.3, 0), (0.9, 0.7, 12), None, None,
                (0.8, 0.4, 0), (0.6, 0.3, -5), (0.7, 0.3, 0), (0.55, 0.3, 0), (0.95, 0.8, -12), None])
    velocity(p, 0.6, 0.0)
    p.mod("VELOCITY", "F2_CUTOFF", 0.3)
    p.performer(1, {0: [(v, "HOLD") for v in (0.0, 0.6, -0.5, 0.3, 0.9, -0.8, 0.2, -0.3, 0.7, -0.6, 0.5, -0.1, 0.8)]}, mode="SONG", rate="1/16", steps=13)
    p.set("macro2", 0.45)
    p.mod("PERF1", "CUTOFF", 0.2, aux="MACRO2")
    p.mod("PERF1", "A_WTPOS", 0.35, aux="MACRO2")
    p.tone("F2_CUTOFF", 0.18)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.4, base=0.22)
    p.doc("Machines talking: a thirteen-step question-and-answer phrase with a vowel that changes on every step, locked to the notes",
          "C3–C5", "Industrial pop, electronica, art pop", "Hold single notes", "FOREGROUND",
          "The vowel performer shares the arp's thirteen steps, so each syllable belongs to its note")
    out.append(p)

    # 35 SHATTERED CLOCKWORK: 10 steps, rests on 3 and 8, extreme level and
    # length contrast; a S&H on decimate for broken gears.
    p = A("SHATTERED CLOCKWORK", "NS HOLLOW BONE", "ANALOG")
    p.osc(0, level=0.58, wt=0.4)
    p.osc(1, level=0.3, wt=0.9)
    p.insert(1, "DECIMATE", after=True, amount=0.3, mix=0.3)
    p.filter("LP24", hz=2400, res=0.25, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.2, s=0.25, r=0.08)
    poly(p, vel=0.6)
    p.arp(mode="UPDOWN", rate="1/16", octaves=2, gate=0.8, swing=0.1)
    pattern(p, [(1.0, 1.0, 0), (0.35, 0.15, 0), None, (0.9, 0.3, 12), (0.4, 0.15, 0), (0.75, 0.8, 0), (0.35, 0.15, 7), None, (1.0, 0.25, 0), (0.5, 0.6, -12)])
    velocity(p, 0.6, 0.25)
    p.lfo(1, "SAMPLE_HOLD", sync="1/16", mode="FREE", smooth=False)
    p.set("macro2", 0.45)
    p.motion("LFO1", "INS1_AMOUNT", 0.25)
    drift(p, 2, 0.27, [("A_WTPOS", 0.35), ("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.18)
    echo(p, time="1/8", mix=0.08, feedback=0.2, amount=0.1)
    burn(p, "BITCRUSH", drive=0.25, base=0.16)
    p.doc("Broken clockwork: ten steps with two holes, whiplash contrast between loud long notes and ghost ticks, gears grinding in random steps",
          "C3–C5", "Glitch pop, art pop, film", "Hold chords", "RHYTHM",
          "Every irregularity repeats every ten steps; it is broken on purpose, not at random")
    out.append(p)

    # 36 DIGITAL PREDATOR: thick voice (unison + sub) and a small memorable
    # motif (0, 3 up... kept to octave/fifth for key safety), accents open drive.
    p = A("DIGITAL PREDATOR", "NS GRINDSTONE", "ANALOG")
    p.osc(0, level=0.55, wt=0.4, unison=3, detune=0.06, width=0.3)
    p.osc(1, level=0.3, wt=1.0, octave=-1)
    p.sub(0.15, "SINE", filtered=False)
    p.filter("LP24", hz=1500, res=0.28, keytrack=0.5, env=0.4)
    fsat(p, "HARD", drive=0.4)
    p.filter2("HP12", hz=110)
    p.env(1, a=0.001, d=0.25, s=0.35, r=0.08)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("A.aA.aO.A.ax.a.", {"A": (1.0, 0.5, 0), "a": (0.5, 0.3, 0), "O": (0.9, 0.6, 12), "x": (0.85, 0.5, 7)}))
    velocity(p, 0.6, 0.28)
    p.mod("VELOCITY", "A_WTPOS", 0.4)
    p.set("macro2", 0.45)
    drift(p, 1, 0.35, [("A_WTPOS", 0.3), ("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.18)
    burn(p, "TUBE", drive=0.5, base=0.28)
    p.doc("A menacing thick voice with a small, sparse motif: stalk, stalk, leap an octave, a fifth, silence",
          "C2–C4", "Industrial, dark pop, trailers", "Hold a root", "FOREGROUND",
          "Half the steps are rests: it hunts rather than runs")
    out.append(p)

    # 37 CORRUPTED SIGNAL: recognizable 8-step pattern; timbre changes
    # constantly: 3 modulators at 0.23, 0.61 and 1/8 S&H across 3 destinations.
    p = A("CORRUPTED SIGNAL", "NS FRACTURE", "DIGITAL")
    p.osc(0, level=0.58, wt=0.2)
    p.osc(1, level=0.28, wt=0.5, warp="QUANTIZE", warp_amt=0.15)
    p.filter("LP24", hz=2200, res=0.25, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.22, s=0.3, r=0.08)
    poly(p, vel=0.6)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.7)
    pattern(p, [(1.0, 0.5, 0), (0.5, 0.3, 0), (0.7, 0.4, 0), (0.55, 0.3, 12), (0.9, 0.5, 0), (0.5, 0.3, 0), (0.75, 0.5, 7), (0.45, 0.3, 0)])
    velocity(p, 0.6, 0.25)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.23, mode="FREE")
    p.lfo(2, "TRIANGLE", hz=0.61, mode="FREE")
    p.lfo(3, "SAMPLE_HOLD", sync="1/8", mode="FREE", smooth=True)
    p.set("macro2", 0.45)
    p.motion("LFO1", "A_WTPOS", 0.4)
    p.motion("LFO2", "B_WARP", 0.25)
    p.motion("LFO3", "CUTOFF", 0.1)
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    burn(p, "DOWNSAMPLE", drive=0.3, base=0.18)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.lfo(4, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO4", "CUTOFF", 0.2)
    p.motion("LFO4", "A_WTPOS", 0.4)
    p.doc("A simple, recognizable eight-step figure whose signal is always being corrupted: fracture scan, quantize warp and filter each on a different clock",
          "C3–C5", "Glitch pop, electronica, dark pop", "Hold chords", "RHYTHM",
          "The notes never change; only the corruption does")
    out.append(p)

    # 38 DARK MATHEMATICS: polyrhythm from verified controls: arp 16 steps,
    # PERF1 5 steps on cutoff, PERF2 7 steps on wavetable (independent step
    # counts are supported by the performers, not by the arp itself).
    p = A("DARK MATHEMATICS", "NS NEON NERVE", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.28, wt=0.9, octave=-1)
    p.filter("LP24", hz=1800, res=0.28, keytrack=0.5, env=0.3)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.25, s=0.35, r=0.1)
    poly(p, vel=0.6)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.75)
    pattern(p, [(0.9, 0.5, 0), (0.5, 0.3, 0), (0.6, 0.4, 0), (0.5, 0.3, 0)] * 3 + [(0.9, 0.5, 12), (0.5, 0.3, 0), (0.7, 0.5, 7), (0.5, 0.3, 0)])
    velocity(p, 0.6, 0.25)
    p.performer(1, {0: [(1.0, "DECAY"), (0.2, "HOLD"), (0.5, "DECAY"), (0.0, "HOLD"), (0.3, "HOLD")]}, mode="SONG", rate="1/16", steps=5)
    p.performer(2, {0: [(v, "GLIDE") for v in (0.0, 0.7, -0.4, 0.9, -0.8, 0.4, -0.2)]}, mode="SONG", rate="1/16", steps=7)
    p.set("macro2", 0.45)
    p.mod("PERF1", "CUTOFF", 0.2, aux="MACRO2")
    p.mod("PERF2", "A_WTPOS", 0.4, aux="MACRO2")
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    burn(p, "SOFT", drive=0.35, base=0.18)
    p.doc("Three cycles at once: a sixteen-step arp, a five-step filter accent and a seven-step wavetable walk; they only realign every 560 steps",
          "C3–C5", "Electronica, film, dark techno", "Hold chords for a long section", "RHYTHM",
          "The arp has one pattern length; the cross-rhythm comes from two performers with their own step counts")
    out.append(p)

    # 39 PRESSURE FRACTURE: intensity ramps within the pattern: lengths shrink,
    # levels and transposes climb; velocity-driven drive makes the end burn.
    p = A("PRESSURE FRACTURE", "ANALOG", "NS TENDON")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.3, wt=0.2)
    p.filter("LP24", hz=1500, res=0.3, keytrack=0.5, env=0.45)
    p.feedback(amount=0.1, drive=0.6, tone=0.5)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.2, s=0.3, r=0.07)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.85)
    pattern(p, [(0.5, 0.9, 0), (0.45, 0.8, 0), (0.55, 0.8, 0), (0.5, 0.7, 0), (0.6, 0.6, 0), (0.55, 0.6, 7), (0.65, 0.5, 0), (0.6, 0.5, 0),
                (0.7, 0.4, 12), (0.65, 0.4, 0), (0.8, 0.35, 0), (0.75, 0.3, 7), (0.85, 0.25, 12), (0.9, 0.2, 0), (1.0, 0.2, 12), (1.0, 0.15, 19)])
    velocity(p, 0.6, 0.3)
    p.mod("VELOCITY", "B_WTPOS", 0.5)
    p.mod("VELOCITY", "FEEDBACK", 0.12)
    p.set("macro2", 0.45)
    drift(p, 1, 0.3, [("B_WTPOS", 0.25), ("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.18)
    burn(p, "HARD", drive=0.5, base=0.28)
    p.doc("Pressure building every bar: notes shorten, accents rise and the steps climb to an octave and a twelfth, each accent folding the tendon table harder",
          "C3–C5", "Industrial, trailers, pre-choruses", "Hold a note or a fifth", "FOREGROUND",
          "The same bar every time; the tension is written into it, not into automation")
    out.append(p)

    # 40 NIGHTSHAPE PROTOCOL: flagship. 14 steps with rests, a tie, displaced
    # octaves and a fifth; PERF1 (9 steps) morphs the obsidian table, PERF2
    # (16) accents the fold; wheel = loop, pressure = drive.
    p = A("NIGHTSHAPE PROTOCOL", "NS OBSIDIAN", "NS SERPENT")
    p.osc(0, level=0.56, wt=0.25, unison=2, detune=0.05, width=0.2)
    p.osc(1, level=0.26, wt=0.2, octave=-1)
    p.sub(0.12, "SINE", filtered=False)
    p.insert(1, "FOLD", after=True, amount=0.25, mix=0.3)
    p.filter("LADDER", hz=1600, res=0.3, keytrack=0.5, env=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.filter2("HP12", hz=120)
    p.feedback(amount=0.08, drive=0.5, tone=0.6)
    p.env(1, a=0.001, d=0.28, s=0.35, r=0.12)
    p.env(2, a=0.001, d=0.14, s=0.2, r=0.1)
    punch(p, 0.35)
    poly(p, vel=0.6)
    p.arp(mode="PLAYED", rate="1/16", octaves=2, gate=0.85, swing=0.05)
    pattern(p, [(1.0, 0.55, 0), (0.45, 0.3, 0), (0.75, 0.45, 12), None, (0.85, 1.0, 0), (0.5, 0.3, 7), (0.6, 0.35, 0), (1.0, 0.6, 12),
                (0.5, 0.3, -12), None, (0.8, 0.5, 0), (0.55, 0.3, 19), (0.95, 0.8, 24), (0.5, 0.35, 12)])
    velocity(p, 0.8, 0.35)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.5, -0.3, 0.8, 0.2, -0.6, 0.6, -0.1, 0.9)]}, mode="SONG", rate="1/16", steps=9)
    p.performer(2, {0: [(1.0, "DECAY"), (0.0, "HOLD"), (0.4, "DECAY"), (0.0, "HOLD")] * 4}, mode="SONG", rate="1/16", steps=16)
    p.set("macro2", 0.45)
    p.mod("PERF1", "A_WTPOS", 0.35, aux="MACRO2")
    p.mod("PERF2", "INS1_AMOUNT", 0.3, aux="MACRO2")
    p.mod("MODWHEEL", "FEEDBACK", 0.2)
    p.mod("PRESSURE", "FSAT_DRIVE", 0.25)
    p.mod("MODWHEEL", "B_WTPOS", 0.5)
    drift(p, 1, 0.21, [("CUTOFF", 0.06)])
    dimension(p, mix=0.25, size=0.6)
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12, pingpong=True)
    plate(p, 0.08)
    burn(p, "TUBE", drive=0.5, base=0.25)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("The flagship sequence: fourteen programmed steps (rests, a tie, octave and twelfth leaps) against a nine-step timbre walk and a sixteen-step fold accent",
          "C3–C5", "Everything NIGHTSHAPE makes", "One held chord; wheel for the loop, pressure for drive", "FOREGROUND",
          "14 against 9 against 16: it keeps developing for a long time before it repeats exactly")
    out.append(p)

    return out
