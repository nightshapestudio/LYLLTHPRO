"""EXPANSION 02 / AGGRESSIVE INDUSTRIAL LEADS. Mono, a dense centre, the
aggression in harmonics that move. Each uses a different nonlinearity."""

from bank2._common import echo, velocity, vibrato
from bank2._showcase import dimension, drift, fsat, morph, punch, vintage
from bank2._x2 import N, burn, mono, plate


def L(name, a="ANALOG", b="BASIC"):
    return N(name, "LEAD", a, b)


def presets():
    out = []

    # 21 RAZOR CROWN: dense centre from STACK OCTAVE_FIFTH on A (centred),
    # evolving grit from an ASYM warp driven by a free triangle; band-limited top.
    p = L("RAZOR CROWN", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=1.0, stack="OCTAVE_FIFTH", warp="ASYM_POS", warp_amt=0.15)
    p.osc(1, level=0.28, wt=0.35)
    p.filter("LP24", hz=2600, res=0.22, keytrack=0.6, env=0.2)
    fsat(p, "HARD", drive=0.4)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.18)
    mono(p)
    velocity(p, 0.5, 0.25)
    vibrato(p)
    p.lfo(1, "TRIANGLE", hz=0.41, mode="FREE")
    p.set("macro2", 0.45)
    p.motion("LFO1", "A_WARP", 0.25)
    p.motion("LFO1", "B_WTPOS", 0.35)
    p.eq(mid=2.0, mid_hz=1800, high=-3, high_hz=7000)
    p.tone("CUTOFF", 0.2)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.45, base=0.3)
    p.doc("A crown of octave and fifth stacked on one centred saw, its asymmetry and a grindstone layer shifting; lifted at 1.8 kHz, trimmed above 7",
          "C3–C5", "Industrial rock, synth metal", "Riffs over guitars", "FOREGROUND",
          "Cuts through guitars at 1.8 kHz rather than above 5 kHz, so it never stings")
    out.append(p)

    # 22 BROKEN TRANSMISSION: centre stays clean-ish; destruction from the
    # filter's RATE saturation (sample-rate reduction inside the filter) with
    # a band-pass peak that drifts.
    p = L("BROKEN TRANSMISSION", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.6, wt=0.85)
    p.osc(1, level=0.25, wt=0.4)
    p.filter("BP", hz=1500, res=0.4, keytrack=0.6, mix=0.5)
    fsat(p, "RATE", drive=0.35, mix=0.5)
    p.filter2("HP12", hz=220)
    p.env(1, a=0.003, d=0.5, s=0.88, r=0.2)
    mono(p)
    velocity(p, 0.8, 0.35)
    p.mod("VELOCITY", "FSAT_DRIVE", 0.2)
    vibrato(p)
    p.set("macro2", 0.45)
    drift(p, 1, 0.47, [("CUTOFF", 0.1), ("B_WTPOS", 0.35)])
    p.lfo(2, "SAMPLE_HOLD", hz=5.0, mode="FREE", smooth=True)
    p.motion("LFO2", "FSAT_DRIVE", 0.12)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    burn(p, "BITCRUSH", drive=0.25, base=0.16)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("A melody arriving through a failing link: sample-rate damage inside the filter, a drifting band-pass resonance, a solid saw centre",
          "C3–C5", "Industrial, dark pop, film", "Melodies", "FOREGROUND",
          "The damage lives in the filter stage, so the centre saw keeps its pitch")
    out.append(p)

    # 23 WHITE VIOLENCE: density from RANDOM unison (not super) at low width,
    # plus a fifth-stacked B, through multiband compression and LINFOLD drive.
    p = L("WHITE VIOLENCE", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=1.0, unison=5, detune=0.07, width=0.25, unimode="RANDOM")
    p.osc(1, level=0.28, wt=0.5, stack="FIFTH")
    p.sub(0.2, "SINE", octave=1)
    p.filter("LP24", hz=3000, res=0.2, keytrack=0.6, drive=0.4)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.003, d=0.5, s=0.92, r=0.2)
    mono(p)
    velocity(p, 0.5, 0.2)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("B_WTPOS", 0.35), ("A_DETUNE", 0.1)])
    p.comp(mode="MULTIBAND", threshold=0.5, ratio=0.4, attack=0.3, release=0.35, gain=0.15, depth=0.55, mix=1.0)
    p.tone("CUTOFF", 0.2)
    plate(p, 0.08)
    burn(p, "LINFOLD", drive=0.4, base=0.28)
    p.doc("A physically powerful chorus lead: random-spread unison held narrow, an obsidian fifth, band-compressed and folded: dense, not a supersaw",
          "C3–C5", "Industrial pop choruses, synth rock", "Chorus hooks", "FOREGROUND",
          "Unison width is only 25%: the power is harmonic density, not a stereo smear")
    out.append(p)

    # 24 GLASS EXECUTION: vicious 30 ms attack (RECTIFY + metal noise +
    # FM warp spike via ENV3), then an elegant glass sustain.
    p = L("GLASS EXECUTION", "GLASS", "NS CATHEDRAL METAL")
    p.osc(0, level=0.6, wt=0.5, warp="FM", warp_amt=0.0)
    p.osc(1, level=0.2, wt=0.6, octave=1)
    p.noise(0.0, type="METAL", color=0.7, keytrack=True)
    p.insert(1, "RECTIFY", after=True, amount=0.6, mix=0.0)
    p.filter("LP24", hz=4200, res=0.15, keytrack=0.5)
    p.filter2("HP12", hz=220)
    p.env(1, a=0.001, d=0.6, s=0.85, r=0.3)
    p.env(3, a=0.0005, d=0.03, s=0.0, r=0.02)
    p.mod("ENV3", "A_WARP", 0.6)
    p.mod("ENV3", "NOISE_LEVEL", 0.15)
    p.mod("ENV3", "INS1_AMOUNT", 0.4)
    p.set("ins1.mix", 0.3)
    punch(p, 0.5)
    mono(p)
    velocity(p, 0.5, 0.15)
    p.mod("VELOCITY", "B_LEVEL", 0.15)
    vibrato(p)
    p.set("macro2", 0.45)
    drift(p, 1, 0.36, [("B_WTPOS", 0.35), ("A_WTPOS", 0.2)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="1/4", mix=0.14, feedback=0.3, amount=0.12, pingpong=True)
    plate(p, 0.1)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("A 30 ms execution (an FM spike, a rectified snap and a spray of metal noise), then an elegant glass sustain with metal harmonics drifting behind it",
          "C4–C6", "Dark pop, electronica, film", "Melodies with space", "FOREGROUND",
          "The violence is all in the attack; the sustain is beautiful on purpose")
    out.append(p)

    # 25 HUMAN MACHINE: organic pitch (VINTAGE + trig random), aggressive
    # distortion only when you push: pressure and wheel drive the DIODE mix.
    p = L("HUMAN MACHINE", "NS THROAT", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.3, wt=0.9, fine=4)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.6, env=0.25)
    p.filter2("HP12", hz=190)
    fsat(p, "LIGHT", drive=0.35)
    p.env(1, a=0.006, d=0.5, s=0.9, r=0.25)
    mono(p, glide=0.07)
    velocity(p, 0.5, 0.2)
    vintage(p, 0.45)
    vibrato(p, hz=4.9, depth=0.013, delay=0.4, rise=0.5)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.8, mode="TRIG")
    p.set("macro2", 0.45)
    p.motion("LFO1", "PITCH", 0.002)
    p.motion("LFO1", "A_WTPOS", 0.45)
    p.mod("PRESSURE", "DIST_MIX", 0.45)
    p.mod("MODWHEEL", "DIST_MIX", 0.35)
    p.mod("PRESSURE", "A_WTPOS", 0.25)
    p.mod("TIMBRE", "CUTOFF", 0.2)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.1)
    burn(p, "DIODE", drive=0.5, base=0.16)
    p.doc("A vowel lead that behaves like a singer (drift, random pitch breath, late vibrato) and snarls only when you lean on it: pressure and wheel open the diode",
          "C3–C5", "Dark pop, art pop, industrial ballads", "Play it; press into held notes", "FOREGROUND",
          "Without pressure it is intimate; the aggression is entirely under your hands")
    out.append(p)

    # 26 BURNING HALO: sustained notes burn: ENV4 over 3 s raises the SHAPER
    # drive and the radiant layer; the fundamental stays on its own saw.
    p = L("BURNING HALO", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.6, wt=0.95)
    p.osc(1, level=0.25, wt=0.2, octave=1)
    p.filter("LP24", hz=2600, res=0.16, keytrack=0.6)
    fsat(p, "SHAPER", drive=0.3, mix=0.7)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.006, d=0.6, s=0.92, r=0.25)
    p.env(4, a=3.0, d=0.1, s=1.0, r=0.3, acurve=0.35)
    p.mod("ENV4", "FSAT_DRIVE", 0.4)
    p.mod("ENV4", "B_WTPOS", 0.55)
    p.mod("ENV4", "B_LEVEL", 0.12)
    mono(p, glide=0.05)
    velocity(p, 0.5, 0.2)
    vibrato(p, depth=0.011)
    p.set("macro2", 0.45)
    drift(p, 1, 0.39, [("CUTOFF", 0.1), ("B_WTPOS", 0.2)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12)
    plate(p, 0.12)
    burn(p, "TUBE", drive=0.4, base=0.18)
    p.doc("A soaring saw whose halo catches fire the longer you hold: the shaper and a radiant octave climb over three seconds",
          "C3–C5", "Dark pop choruses, film", "Long notes at the top of phrases", "FOREGROUND",
          "Short notes stay clean and rich; the burn is a reward for holding")
    out.append(p)

    # 27 CONTROLLED DEMOLITION: competing modulators: a performer on
    # resonance, a free random on feedback, ENV2 on cutoff; loop below
    # self-oscillation so pitch holds.
    p = L("CONTROLLED DEMOLITION", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=1.0)
    p.osc(1, level=0.3, wt=0.4, fine=-8)
    p.filter("LADDER", hz=1500, res=0.35, keytrack=0.6, env=0.35)
    p.feedback(amount=0.18, drive=0.7, tone=0.6)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.2)
    p.env(2, a=0.001, d=0.3, s=0.4, r=0.2)
    mono(p)
    velocity(p, 0.5, 0.22)
    vibrato(p)
    p.performer(1, {0: [(0.6, "DECAY"), (0.0, "HOLD"), (0.9, "DECAY"), (0.2, "HOLD")] * 4}, mode="TRIG", rate="1/16")
    p.set("macro2", 0.45)
    p.mod("PERF1", "RES", 0.18, aux="MACRO2")
    drift(p, 1, 0.52, [("FEEDBACK", 0.12), ("FB_TONE", 0.25)])
    p.tone("CUTOFF", 0.2)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.5, base=0.3)
    p.doc("Three modulators pulling at one resonant loop (a sixteenth performer on resonance, a random on feedback, the filter envelope), each note dangerous and on pitch",
          "C3–C5", "Industrial, noise pop, trailers", "Riffs and held notes", "FOREGROUND",
          "The loop is kept below self-oscillation, so nothing screams off-key")
    out.append(p)

    # 28 BLACK LIGHTNING: fast, articulate: PUNCH, sync-sweep attack from
    # ENV3, a short FLIP-warped B; legato off so hooks articulate.
    p = L("BLACK LIGHTNING", "SYNC_SWEEP", "ANALOG")
    p.osc(0, level=0.6, wt=0.5)
    p.osc(1, level=0.28, wt=0.9, warp="FLIP", warp_amt=0.2)
    p.filter("LP24", hz=2400, res=0.22, keytrack=0.6, env=0.45)
    fsat(p, "DIODE", drive=0.35)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.001, d=0.3, s=0.75, r=0.12)
    p.env(2, a=0.001, d=0.12, s=0.35, r=0.1)
    p.env(3, a=0.001, d=0.07, s=0.0, r=0.05)
    p.mod("ENV3", "A_WTPOS", 0.45)
    punch(p, 0.65)
    mono(p, glide=0.0, legato=False)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.44, [("B_WARP", 0.25), ("A_WTPOS", 0.2)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="1/8", mix=0.08, feedback=0.2, amount=0.1)
    burn(p, "HARD", drive=0.45, base=0.22)
    p.doc("Fast and articulate: each note strikes with a punched sync bolt, then a flipped saw churns in the body",
          "C3–C5", "Synth rock, industrial pop, electro", "Fast hooks and riffs", "FOREGROUND",
          "Retriggers every note (no legato) so fast lines articulate")
    out.append(p)

    # 29 METALLIC NERVE: metallic colour from a keytracked positive comb at
    # the note plus a RING at a fifth-ish ratio; rich saw fundamental; not an FX.
    p = L("METALLIC NERVE", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.6, wt=0.9)
    p.osc(1, level=0.22, wt=0.5)
    p.insert(1, "RING", after=True, amount=0.3, freq=0.66, mix=0.12)
    p.filter("COMB_POS", hz=700, res=0.45, keytrack=1.0, mix=0.35)
    p.filter2("LP24", hz=3000, res=0.15)
    p.env(1, a=0.003, d=0.5, s=0.88, r=0.2)
    mono(p)
    velocity(p, 0.5, 0.0)
    p.mod("VELOCITY", "F2_CUTOFF", 0.25)
    vibrato(p)
    p.set("macro2", 0.45)
    drift(p, 1, 0.38, [("B_WTPOS", 0.4), ("RES", 0.08)])
    p.tone("F2_CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.08)
    burn(p, "SOFT", drive=0.4, base=0.2)
    p.doc("A focused saw with a nerve of metal through it: a keytracked comb and a light ring, cathedral-metal partials shifting above",
          "C3–C5", "Industrial, dark pop, electro", "Melodies", "FOREGROUND",
          "The comb follows the note, so the metal is always in tune with the melody")
    out.append(p)

    # 30 GOD COMPLEX: flagship lead: obsidian A with FM from B, grindstone B
    # stacked an octave, fold + comb inserts, ladder with loop, filter
    # saturation; ENV4 unfurls; every performance input has a job.
    p = L("GOD COMPLEX", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.56, wt=0.25, unison=2, detune=0.04, width=0.12, warp="FM", warp_amt=0.08)
    p.osc(1, level=0.26, wt=0.2, octave=1, unison=3, detune=0.08, width=0.9)
    p.sub(0.15, "SINE", octave=1)
    p.insert(1, "FOLD", after=True, amount=0.22, mix=0.3)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=2000, res=0.28, keytrack=0.6, env=0.35)
    fsat(p, "SHAPER", drive=0.35, mix=0.6)
    p.filter2("HP12", hz=170)
    p.feedback(amount=0.08, drive=0.5, tone=0.6)
    p.env(1, a=0.002, d=0.6, s=0.9, r=0.3)
    p.env(2, a=0.001, d=0.2, s=0.45, r=0.3)
    p.env(4, a=2.2, d=0.1, s=1.0, r=0.4, acurve=0.35)
    p.mod("ENV4", "B_WTPOS", 0.45)
    p.mod("ENV4", "A_WARP", 0.15)
    p.mod("ENV4", "DIM_MIX", 0.3)
    punch(p, 0.4)
    mono(p, glide=0.04)
    velocity(p, 0.5, 0.22)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.2)
    vibrato(p, depth=0.012)
    p.mod("PRESSURE", "FEEDBACK", 0.2)
    p.mod("PRESSURE", "FSAT_DRIVE", 0.2)
    p.mod("MODWHEEL", "A_WARP", 0.3)
    p.mod("TIMBRE", "B_WTPOS", 0.35)
    vintage(p, 0.2)
    p.set("macro2", 0.45)
    drift(p, 1, 0.34, [("A_WTPOS", 0.25), ("CUTOFF", 0.07)])
    drift(p, 2, 0.13, [("B_PAN", 0.15), ("INS2_FREQ", 0.008)])
    dimension(p, mix=0.0, size=0.6)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.5, base=0.25)
    p.doc("The flagship lead: obsidian and grindstone tables cross-modulated, folded, combed and saturated inside a ladder loop, unfurling wide after two seconds",
          "C3–C5", "Everything NIGHTSHAPE makes", "Hooks; pressure, wheel and MPE timbre all reshape it", "FOREGROUND",
          "Mono centre for the melody; width only in the upper layer after the attack")
    out.append(p)

    return out
