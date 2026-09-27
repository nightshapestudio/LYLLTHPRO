"""ADD-ON 03 / SCREAMING LEADS AND HOOK SYNTHS. Mono voices with a thick
body; the scream is resonance, feedback and upper-mid distortion that the
wheel pushes to the edge of control while the pitch holds."""

from bank2._common import echo, velocity, vibrato
from bank2._showcase import dimension, drift, fsat, punch, vintage
from bank2._x3 import N3, burn, dc_guard, mono, room, wheel


def L(name, a="ANALOG", b="BASIC"):
    return N3(name, "LEAD", a, b)


def body(p, hp=190):
    return p.filter2("HP12", hz=hp)


def presets():
    out = []

    # 31 SCREAM CIRCUIT: resonant LP with the loop just below oscillation;
    # the wheel takes the loop and resonance toward controlled feedback.
    p = L("SCREAM CIRCUIT", "ANALOG", "ANALOG")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.3, wt=0.4, fine=6)
    p.filter("LP24", hz=1800, res=0.35, keytrack=0.8, env=0.3)
    p.feedback(amount=0.12, drive=0.7, tone=0.65)
    body(p)
    p.env(1, a=0.002, d=0.5, s=0.9, r=0.2)
    p.env(2, a=0.01, d=0.5, s=0.45, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.43, [("FB_TONE", 0.2), ("CUTOFF", 0.08)])
    wheel(p, ("FEEDBACK", 0.2), ("RES", 0.18), ("DIST_MIX", 0.35), ("DIST_DRIVE", 0.25))
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.3)
    p.doc("A synth screaming on pitch: a resonant ladder with a feedback loop keytracked to the note, just below oscillation",
          "C3–C5", "Industrial rock, synth metal", "Held notes and bends", "FOREGROUND",
          "Wheel: the loop and the resonance head toward controlled feedback; the note never wanders")
    out.append(p)

    # 32 RAZOR VOICE: vocal-like articulation without formants: ENV2 on
    # cutoff shaped like a syllable (fast open, slow close), bend 7, glide.
    p = L("RAZOR VOICE", "ANALOG", "PWM")
    p.osc(0, level=0.58, wt=0.9)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LP24", hz=1400, res=0.25, keytrack=0.6, env=0.5)
    body(p)
    p.env(1, a=0.004, d=0.5, s=0.9, r=0.2)
    p.env(2, a=0.02, d=0.6, s=0.35, r=0.2, acurve=0.3)
    p.set("env2.slope", -0.3)
    mono(p, glide=0.08)
    p.set("bendRange", 7)
    velocity(p, 0.55, 0.28)
    vibrato(p, hz=5.4, depth=0.014, delay=0.3, rise=0.4)
    p.set("macro2", 0.4)
    drift(p, 1, 0.47, [("B_WTPOS", 0.3), ("CUTOFF", 0.08)])
    wheel(p, ("RES", 0.25), ("DIST_MIX", 0.35), ("FSAT_DRIVE", 0.3))
    p.lfo(2, "SMOOTH_RANDOM", hz=2.5, mode="FREE")
    p.mod("LFO2", "PITCH", 0.003, aux="MODWHEEL")
    fsat(p, "DIODE", drive=0.35)
    echo(p, time="3/16", mix=0.08, feedback=0.22, amount=0.1)
    burn(p, "HARD", drive=0.45, base=0.25)
    p.doc("A lead that articulates like a voice without a formant trick: each note's filter opens and closes like a syllable; wide bends, dramatic glide",
          "C3–C5", "Dark pop, industrial pop", "Expressive melodies; bend a fifth", "FOREGROUND",
          "Bend range is seven semitones. Wheel: scream, resonance, saturation and a hint of pitch instability")
    out.append(p)

    # 33 SOLAR WOUND (brief: BURN HALO, too close to two bank names): strong
    # centre, burning wide edges (B unison), wheel drives both.
    p = L("SOLAR WOUND", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.24, wt=0.5, octave=1, unison=4, detune=0.1, width=0.8)
    p.filter("LP24", hz=2800, res=0.2, keytrack=0.6, env=0.2)
    fsat(p, "SHAPER", drive=0.35, mix=0.6)
    body(p)
    p.env(1, a=0.004, d=0.6, s=0.9, r=0.25)
    mono(p, glide=0.04)
    velocity(p, 0.85, 0.35)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.4), ("CUTOFF", 0.07)])
    wheel(p, ("B_WIDTH", 0.2), ("B_WTPOS", 0.35), ("FSAT_DRIVE", 0.4), ("DIST_MIX", 0.3))
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.25)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("A chorus-sized emotional lead: a strong centre saw and burning radiant edges an octave up, shaped and saturated",
          "C3–C5", "Industrial pop choruses", "Big melodies", "FOREGROUND",
          "Wheel: the edges widen and brighten while the centre is pushed harder into saturation")
    out.append(p)

    # 34 ELECTRIC KNIFE: thick low body (B -1 oct) + concentrated 2-3 kHz
    # (BP parallel) and a roll-off above 7 kHz.
    p = L("ELECTRIC KNIFE", "ANALOG", "ANALOG")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.3, wt=0.4, octave=-1)
    p.filter("BP", hz=2400, res=0.35, keytrack=0.5, mix=0.35)
    fsat(p, "HARD", drive=0.35)
    body(p, hp=150)
    p.env(1, a=0.002, d=0.5, s=0.9, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("CUTOFF", 0.1), ("A_WTPOS", 0.25)])
    p.eq(high=-4, high_hz=7000)
    wheel(p, ("FILTER_MIX", 0.35), ("RES", 0.2), ("DIST_MIX", 0.35), ("FSAT_DRIVE", 0.3))
    room(p)
    burn(p, "DIODE", drive=0.45, base=0.25)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("Cuts through a full band by focus: an octave-down body, a band-passed blade at 2.4 kHz, the painful top rolled off",
          "C3–C5", "Industrial rock, electro-rock", "Riffs and hooks over guitars", "FOREGROUND",
          "Wheel: more blade, more bite, more harmonics, not more treble")
    out.append(p)

    # 35 SHOCK ANGEL: luminous at rest (RADIANT, clean-ish); the wheel folds,
    # rectifies and diode-drives it into something feral.
    p = L("SHOCK ANGEL", "NS RADIANT", "GLASS")
    p.osc(0, level=0.58, wt=0.45)
    p.osc(1, level=0.2, wt=0.5, octave=1)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.insert(2, "RECTIFY", after=True, amount=0.0, mix=0.4)
    p.filter("LP24", hz=3200, res=0.15, keytrack=0.6)
    body(p)
    p.env(1, a=0.004, d=0.6, s=0.9, r=0.25)
    mono(p)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("A_WTPOS", 0.35), ("CUTOFF", 0.07)])
    wheel(p, ("INS1_AMOUNT", 0.5), ("INS2_AMOUNT", 0.45), ("DIST_MIX", 0.45), ("A_WTPOS", 0.3))
    fsat(p, "SOFT", drive=0.3)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12, pingpong=True)
    room(p)
    burn(p, "DIODE", drive=0.5, base=0.16)
    p.doc("A luminous, polished lead that the wheel turns feral: fold, rectify and diode drive all arrive at once",
          "C3–C6", "Dark pop, industrial pop", "Melodies that turn on the listener", "FOREGROUND",
          "At rest it is nearly clean; the danger is entirely in the wheel")
    out.append(p)

    # 36 BLACK SIREN: sustained, seductive: slow pitch drift (VINTAGE +
    # delayed vibrato), long bends (12), the wheel adds resonant scream.
    p = L("BLACK SIREN", "NS THROAT", "ANALOG")
    p.osc(0, level=0.56, wt=0.3)
    p.osc(1, level=0.3, wt=0.95, fine=-4)
    p.filter("LP24", hz=2000, res=0.25, keytrack=0.7)
    body(p)
    p.env(1, a=0.03, d=0.6, s=0.95, r=0.25)
    mono(p, glide=0.1)
    p.set("bendRange", 12)
    velocity(p, 0.55, 0.25)
    vintage(p, 0.35)
    vibrato(p, hz=4.6, depth=0.014, delay=0.7, rise=0.8)
    p.set("macro2", 0.4)
    drift(p, 1, 0.29, [("A_WTPOS", 0.4), ("CUTOFF", 0.08)])
    wheel(p, ("RES", 0.3), ("DIST_MIX", 0.4), ("FEEDBACK", 0.12))
    p.feedback(amount=0.03, drive=0.6, tone=0.6)
    fsat(p, "SOFT", drive=0.35)
    echo(p, time="3/8", mix=0.08, feedback=0.14, amount=0.12)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.2)
    p.doc("A dark siren for held notes: a vowel-and-saw voice that drifts, sings a late vibrato and bends an octave",
          "C3–C5", "Dark pop, industrial ballads", "Long notes and octave bends", "FOREGROUND",
          "Seductive rather than sci-fi. Wheel: distortion and a resonant scream rise underneath")
    out.append(p)

    # 37 SIGNAL DAMAGE: corrupted texture inside the tone (FRACTURE table
    # blended + RATE fsat), wheel adds instability (S&H on table) not detune.
    p = L("SIGNAL DAMAGE", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.58, wt=0.95)
    p.osc(1, level=0.25, wt=0.3)
    p.filter("LP24", hz=2600, res=0.2, keytrack=0.6, env=0.25)
    fsat(p, "RATE", drive=0.3, mix=0.35)
    body(p)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("CUTOFF", 0.07)])
    p.lfo(2, "SAMPLE_HOLD", hz=7.0, mode="FREE", smooth=True)
    wheel(p, ("FSAT_DRIVE", 0.4), ("B_LEVEL", 0.2), ("DIST_MIX", 0.35))
    p.mod("LFO2", "B_WTPOS", 0.35, aux="MODWHEEL")
    room(p)
    burn(p, "BITCRUSH", drive=0.3, base=0.18)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("A playable melody voice with corruption built into it: a fracture layer and sample-rate damage inside the filter",
          "C3–C5", "Glitch pop, industrial pop", "Melodies", "FOREGROUND",
          "Wheel: the fracture layer starts stepping and the rate damage deepens; tracking never breaks")
    out.append(p)

    # 38 SHARP OBJECT: very defined attack (sync ENV3 + punch), thick sustain;
    # legato off for rhythmic melodies.
    p = L("SHARP OBJECT", "SYNC_SWEEP", "ANALOG")
    p.osc(0, level=0.56, wt=0.35)
    p.osc(1, level=0.3, wt=1.0, octave=-1)
    p.filter("LP24", hz=2400, res=0.22, keytrack=0.6, env=0.45)
    body(p, hp=160)
    p.env(1, a=0.001, d=0.3, s=0.8, r=0.12)
    p.env(2, a=0.001, d=0.1, s=0.4, r=0.1)
    p.env(3, a=0.001, d=0.05, s=0.0, r=0.03)
    p.mod("ENV3", "A_WTPOS", 0.45)
    punch(p, 0.6)
    mono(p, glide=0.0, legato=False)
    velocity(p, 0.6, 0.3)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("A_WTPOS", 0.2), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_MIX", 0.4), ("B_WIDTH", 0.35), ("B_WTPOS", 0.3))
    p.set("b.unison", 2)
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "HARD", drive=0.45, base=0.25)
    p.doc("A fast lead with a very defined point: a 50 ms sync strike and punch, then a thick octave-down sustain; every note articulates",
          "C3–C5", "Electro-rock, industrial pop", "Rhythmic melodies and hooks", "FOREGROUND",
          "Wheel: aggressive saturation and a wider harmonic layer underneath")
    out.append(p)

    # 39 TUNGSTEN (brief: METAL NERVE, too close to METALLIC NERVE):
    # resonance and oscillator harmonics interacting: keytracked comb filter
    # + A FM-warped by B, both on independent clocks.
    p = L("TUNGSTEN", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.56, wt=1.0, warp="FM", warp_amt=0.08)
    p.osc(1, level=0.25, wt=0.5)
    p.filter("COMB_POS", hz=700, res=0.4, keytrack=1.0, mix=0.3)
    p.filter2("LP24", hz=3200, res=0.15)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.0)
    p.mod("VELOCITY", "F2_CUTOFF", 0.3)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.43, [("A_WARP", 0.1), ("RES", 0.06)])
    drift(p, 2, 0.19, [("B_WTPOS", 0.4)])
    wheel(p, ("A_WARP", 0.25), ("RES", 0.2), ("FILTER_MIX", 0.3), ("DIST_MIX", 0.35))
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.22)
    dc_guard(p)
    p.doc("Dense metal that is sophisticated, not a bell: an FM-flicked saw through a keytracked comb, cathedral-metal partials drifting on a second clock",
          "C3–C5", "Industrial, electro-rock", "Melodies", "FOREGROUND",
          "Wheel: FM depth, comb resonance and saturation tighten the metal's grip")
    out.append(p)

    # 40 NIGHTSHAPE SCREAM: flagship chorus lead; at full wheel the loop,
    # fold, resonance and shaper all rise: barely held, still on pitch.
    p = L("NIGHTSHAPE SCREAM", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=0.3, unison=2, detune=0.04, width=0.12)
    p.osc(1, level=0.25, wt=0.25, octave=1, unison=3, detune=0.08, width=0.8)
    p.sub(0.12, "SINE", octave=1)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.3)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=2200, res=0.3, keytrack=0.7, env=0.35)
    fsat(p, "SHAPER", drive=0.35, mix=0.6)
    body(p, hp=170)
    p.feedback(amount=0.08, drive=0.6, tone=0.6)
    p.env(1, a=0.002, d=0.6, s=0.9, r=0.3)
    p.env(2, a=0.001, d=0.2, s=0.45, r=0.3)
    p.env(4, a=1.8, d=0.1, s=1.0, r=0.4, acurve=0.35)
    p.mod("ENV4", "B_WTPOS", 0.4)
    p.mod("ENV4", "DIM_MIX", 0.25)
    punch(p, 0.4)
    mono(p, glide=0.04)
    velocity(p, 0.85, 0.35)
    vibrato(p, depth=0.012)
    p.mod("PRESSURE", "FEEDBACK", 0.15)
    p.mod("TIMBRE", "B_WTPOS", 0.3)
    vintage(p, 0.15)
    p.set("macro2", 0.45)
    drift(p, 1, 0.35, [("A_WTPOS", 0.25), ("CUTOFF", 0.07)])
    wheel(p, ("FEEDBACK", 0.2), ("INS1_AMOUNT", 0.4), ("RES", 0.18), ("FSAT_DRIVE", 0.35), ("DIST_MIX", 0.3))
    dimension(p, mix=0.0, size=0.6)
    echo(p, time="3/16", mix=0.1, feedback=0.28, amount=0.12)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.25)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("The flagship chorus lead: obsidian and grindstone tables, folded, combed and shaped inside a ladder loop, blooming wide after two seconds",
          "C3–C5", "Industrial pop choruses, anything that needs a scream", "The chorus melody", "FOREGROUND",
          "Wheel: the loop, fold, resonance and shaper all climb: barely under control, still on pitch")
    out.append(p)

    return out
