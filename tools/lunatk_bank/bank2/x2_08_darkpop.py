"""EXPANSION 02 / DARK POP SIGNATURE SYNTHS. Hook voices first: polished
fundamentals, one memorable harmonic trick each, grit that serves the hook."""

from bank2._common import echo, velocity, vibrato
from bank2._showcase import dimension, drift, fsat, morph, punch, vintage
from bank2._x2 import N, burn, hall, mono, plate, poly


def presets():
    out = []

    # 71 BEAUTIFUL MONSTER (lead): polished saw centre; its trick is AM warp
    # on B (a tremolo-like harmonic sideband) that grows with GRIT and the wheel.
    p = N("BEAUTIFUL MONSTER", "LEAD", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.58, wt=0.9, unison=2, detune=0.04, width=0.15)
    p.osc(1, level=0.28, wt=0.3, octave=1, warp="AM", warp_amt=0.2)
    p.filter("LP24", hz=2600, res=0.18, keytrack=0.6, env=0.25)
    fsat(p, "SOFT", drive=0.4)
    p.filter2("HP12", hz=190)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.25)
    mono(p)
    velocity(p, 0.5, 0.22)
    vibrato(p)
    p.mod("MODWHEEL", "B_WARP", 0.4)
    p.mod("MACRO4", "B_WARP", 0.3)
    p.set("macro2", 0.45)
    drift(p, 1, 0.34, [("B_WTPOS", 0.4), ("CUTOFF", 0.06)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.45, base=0.22)
    p.doc("A hook voice with a monster inside: a polished saw centre and an obsidian octave whose AM sidebands snarl as you push the wheel or GRIT",
          "C3–C5", "Dark pop, alt-pop", "Chorus hooks", "FOREGROUND",
          "Clean enough for a pop hook at rest; the wheel lets the monster out")
    out.append(p)

    # 72 NEON SCARS (keys): poly; distorted upper layer is a separate RECTIFY
    # insert on B only, panned by a triangle; melodic, hooky.
    p = N("NEON SCARS", "KEYS", "PWM", "NS NEON NERVE")
    p.osc(0, level=0.55, wt=0.35)
    p.osc(1, level=0.28, wt=0.5, octave=1)
    p.insert(2, "RECTIFY", after=True, amount=0.45, mix=0.3)
    p.filter("LP24", hz=2600, res=0.18, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.002, d=0.9, s=0.5, r=0.3)
    p.env(2, a=0.001, d=0.25, s=0.3, r=0.2)
    poly(p, vel=0.55)
    velocity(p, 0.55, 0.25)
    p.lfo(1, "TRIANGLE", hz=0.29, mode="FREE")
    p.set("macro2", 0.4)
    p.motion("LFO1", "B_PAN", 0.4)
    p.motion("LFO1", "B_WTPOS", 0.35)
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12, pingpong=True)
    plate(p, 0.1)
    burn(p, "SOFT", drive=0.35, base=0.16)
    p.doc("A pulse-wave hook with neon scars: the upper octave rectified and swinging across the stereo field while its resonance sweeps",
          "C3–C5", "Dark pop, alt-electronic", "Hooks and chord riffs", "FOREGROUND",
          "The scar is only on the upper layer; the pulse carries the melody")
    out.append(p)

    # 73 BLACK PERFUME (keys): intimate: formant + ORGAN body, a faint CRACKLE
    # electrical texture gated by velocity, slow VINTAGE.
    p = N("BLACK PERFUME", "KEYS", "NS THROAT", "ORGAN")
    p.osc(0, level=0.55, wt=0.35)
    p.osc(1, level=0.3, wt=0.5, octave=-1)
    p.noise(0.0, type="CRACKLE", color=0.5, keytrack=False)
    p.filter("LP12", hz=2200, res=0.12, keytrack=0.5, env=0.2)
    fsat(p, "LIGHT", drive=0.35)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.004, d=1.4, s=0.5, r=0.4)
    poly(p, vel=0.45)
    velocity(p, 0.45, 0.2)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.05, curve=0.5)
    vintage(p, 0.3)
    p.set("macro2", 0.4)
    drift(p, 1, 0.27, [("A_WTPOS", 0.4)])
    p.chorus(mode="SUBTLE", mix=0.2, rate=0.25, depth=0.3, width=0.6)
    plate(p, 0.1)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Dark and close: a slow-moving vowel over a low organ, the faintest electrical crackle on firmer notes",
          "C2–C5", "Dark R&B, dark pop, intimate electronic", "Soft chords under a vocal", "SUPPORT",
          "Warm and narrow on purpose; it sits beside a voice")
    out.append(p)

    # 74 GLASS VENOM (lead): bright, memorable; abrasive transient (SYNC +
    # BITS fsat spike via ENV3), then an evolving glass sustain (ENV4 scan).
    p = N("GLASS VENOM", "LEAD", "GLASS", "SYNC_SWEEP")
    p.osc(0, level=0.58, wt=0.45)
    p.osc(1, level=0.2, wt=0.8)
    p.filter("LP24", hz=4000, res=0.15, keytrack=0.5, env=0.2)
    fsat(p, "BITS", drive=0.3, mix=0.3)
    p.filter2("HP12", hz=220)
    p.env(1, a=0.001, d=0.5, s=0.85, r=0.25)
    p.env(3, a=0.0005, d=0.05, s=0.0, r=0.03)
    p.env(4, a=1.2, d=0.1, s=1.0, r=0.3)
    p.mod("ENV3", "FSAT_DRIVE", 0.4)
    p.mod("ENV3", "B_LEVEL", 0.3)
    p.mod("ENV4", "A_WTPOS", 0.35)
    punch(p, 0.45)
    mono(p)
    velocity(p, 0.55, 0.2)
    vibrato(p)
    p.set("macro2", 0.45)
    drift(p, 1, 0.37, [("A_WTPOS", 0.2), ("CUTOFF", 0.08)])
    p.eq(high=-3, high_hz=9000)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12, pingpong=True)
    plate(p, 0.1)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Bright and poisonous: a bit-crushed sync sting on every note, then a glass sustain that keeps turning",
          "C4–C6", "Dark pop, alt-pop, electronica", "Hooks", "FOREGROUND",
          "The sting is 50 ms and the air above 9 kHz is trimmed: bright, not piercing")
    out.append(p)

    # 75 AFTER MIDNIGHT (lead): strong melodic definition from a 2-pole
    # ladder saw with rich low mids (B -1 oct); upper harmonics shifting via
    # MORPH filter2 notch sweep. No retro chorus, no gated verb.
    p = N("AFTER MIDNIGHT", "LEAD", "ANALOG", "NS HOLLOW BONE")
    p.osc(0, level=0.58, wt=0.95)
    p.osc(1, level=0.3, wt=0.4, octave=-1)
    p.filter("LADDER", hz=1800, res=0.22, keytrack=0.6, env=0.25)
    p.set("ladder.poles", 1)
    p.filter2("MORPH", hz=2400, res=0.2)
    morph(p, 0.5, second=True)
    fsat(p, "SOFT", drive=0.35)
    p.env(1, a=0.003, d=0.5, s=0.9, r=0.25)
    mono(p, glide=0.04)
    velocity(p, 0.5, 0.22)
    vibrato(p)
    p.set("macro2", 0.45)
    drift(p, 1, 0.31, [("F2_MORPH", 0.25), ("F2_CUTOFF", 0.12)])
    drift(p, 2, 0.13, [("B_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.12)
    burn(p, "TUBE", drive=0.4, base=0.18)
    p.doc("A nocturnal melody voice: a two-pole ladder saw over a hollow low octave, a notch drifting through its upper harmonics",
          "C3–C5", "Dark pop, alt-electronic", "Verse and chorus melodies", "FOREGROUND",
          "No retro chorus, no gated reverb: the movement is a notch, which reads as modern")
    out.append(p)

    # 76 SOFT DESTRUCTION (keys): restrained at rest; the wheel walks it
    # through three destruction stages: fold, then crush, then drive.
    p = N("SOFT DESTRUCTION", "KEYS", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.55, wt=0.8)
    p.osc(1, level=0.28, wt=0.0, octave=1)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.insert(2, "BITCRUSH", after=True, amount=0.0, mix=0.4)
    p.filter("LP24", hz=2200, res=0.15, keytrack=0.5, env=0.3)
    fsat(p, "SOFT", drive=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=1.1, s=0.5, r=0.35)
    poly(p, vel=0.5)
    velocity(p, 0.5, 0.22)
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.45, curve=-0.4)
    p.mod("MODWHEEL", "INS2_AMOUNT", 0.45, curve=0.2)
    p.mod("MODWHEEL", "B_WTPOS", 0.6, curve=0.2)
    p.mod("MODWHEEL", "DIST_MIX", 0.4, curve=0.6)
    p.mod("MODWHEEL", "MASTER", -0.12)
    p.set("macro2", 0.4)
    drift(p, 1, 0.3, [("A_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.18)
    plate(p, 0.1)
    burn(p, "HARD", drive=0.45, base=0.16)
    p.doc("Beautiful at rest; the mod wheel destroys it in three stages: first a fold, then the fracture layer crushes, and last the hard drive",
          "C2–C5", "Dark pop, industrial pop", "Ride the wheel through a section", "FOREGROUND",
          "Curves are staggered so each stage arrives in turn; level is trimmed as it goes")
    out.append(p)

    # 77 DIGITAL OBSESSION (lead): rhythmic texture from a TRIG performer on
    # QUANTIZE warp (a digital stutter inside each note), memorable, precise.
    p = N("DIGITAL OBSESSION", "LEAD", "DIGITAL", "ANALOG")
    p.osc(0, level=0.58, wt=0.4, warp="QUANTIZE", warp_amt=0.12)
    p.osc(1, level=0.28, wt=0.95)
    p.filter("LP24", hz=2800, res=0.2, keytrack=0.6, env=0.25)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.002, d=0.5, s=0.88, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.22)
    vibrato(p)
    p.performer(1, {0: [(0.8, "DECAY"), (0.0, "HOLD"), (0.4, "DECAY"), (0.0, "HOLD"), (0.6, "DECAY"), (0.2, "HOLD"), (1.0, "DECAY"), (0.0, "HOLD")] * 2},
                mode="TRIG", rate="1/16")
    p.set("macro2", 0.45)
    p.mod("PERF1", "A_WARP", 0.35, aux="MACRO2")
    drift(p, 1, 0.36, [("A_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    burn(p, "BITCRUSH", drive=0.25, base=0.16)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.lfo(2, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO2", "CUTOFF", 0.2)
    p.motion("LFO2", "A_WTPOS", 0.4)
    p.doc("An obsessive hook voice: every note carries a sixteenth-note digital stutter in its waveform, restarting with each note",
          "C3–C5", "Glitch pop, dark pop, electronica", "Held notes and hooks", "FOREGROUND",
          "The stutter restarts per note (TRIG), so it follows the melody, not the bar")
    out.append(p)

    # 78 COLD LUXURY (pad): sleek dense foundation (EXP unison), abrasive
    # movement: a slow random on a phaser and a BITS fsat at 20%; distant.
    p = N("COLD LUXURY", "PAD", "ANALOG", "GLASS")
    p.osc(0, level=0.55, wt=0.8, unison=5, detune=0.08, width=0.5, unimode="EXP")
    p.osc(1, level=0.28, wt=0.5, octave=1, unison=3, detune=0.06, width=0.9)
    p.filter("LP24", hz=2400, res=0.12, keytrack=0.35)
    fsat(p, "BITS", drive=0.3, mix=0.3)
    p.filter2("HP24", hz=160)
    p.env(1, a=0.6, d=3.0, s=0.9, r=1.8)
    poly(p, vel=0.3)
    p.set("macro2", 0.5)
    drift(p, 1, 0.33, [("B_WTPOS", 0.35), ("CUTOFF", 0.06)])
    p.phaser(mix=0.2, rate=0.12, depth=0.5, freq=0.5, feedback=0.3)
    drift(p, 2, 0.071, [("PHASER_FREQ", 0.2)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.4)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Sleek and emotionally distant: an exponential unison bed with a glass top, a fine bit-grit in the filter and a phaser moving under a random",
          "C3–C5", "Dark pop, electronica", "Chords", "SUPPORT",
          "Expensive through restraint: the grit is felt more than heard")
    out.append(p)

    # 79 THE BEAUTIFUL DISEASE (keys): appealing tone, unusual imperfections:
    # a RING at a non-integer ratio whose amount is velocity-random per note.
    p = N("THE BEAUTIFUL DISEASE", "KEYS", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.55, wt=0.85)
    p.osc(1, level=0.28, wt=0.4, octave=1)
    p.insert(1, "RING", after=True, amount=0.35, freq=0.58, mix=0.0)
    p.filter("LP24", hz=2600, res=0.15, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=1.2, s=0.5, r=0.4)
    poly(p, vel=0.5)
    velocity(p, 0.5, 0.22)
    p.mod("RANDOM", "INS1_AMOUNT", 0.3)
    p.set("ins1.mix", 0.18)
    p.mod("RANDOM", "INS1_FREQ", 0.01)
    vintage(p, 0.25)
    p.set("macro2", 0.4)
    drift(p, 1, 0.3, [("B_WTPOS", 0.35)])
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.35, base=0.16)
    fsat(p, "LIGHT", drive=0.3)
    p.doc("Immediately lovely, then you notice the infection: each note carries its own slightly different off-ratio ring, never twice the same",
          "C3–C5", "Dark pop, art pop", "Chords and melodies", "FOREGROUND",
          "The ring's pitch and depth are drawn per note; subtle, and unmistakable once heard")
    out.append(p)

    # 80 NIGHTSHAPE SIGNATURE (lead): flagship dark-pop voice: polished
    # obsidian centre, a radiant octave that blooms (ENV4), AM snarl on the
    # wheel, diode fsat on pressure, MPE timbre on the bloom.
    p = N("NIGHTSHAPE SIGNATURE", "LEAD", "NS OBSIDIAN", "NS RADIANT")
    p.osc(0, level=0.56, wt=0.2, unison=2, detune=0.04, width=0.12)
    p.osc(1, level=0.24, wt=0.1, octave=1, unison=3, detune=0.07, width=0.9, warp="AM", warp_amt=0.0)
    p.sub(0.12, "SINE", octave=1)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.3)
    p.filter("LADDER", hz=2200, res=0.25, keytrack=0.6, env=0.3)
    fsat(p, "DIODE", drive=0.35)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.002, d=0.6, s=0.9, r=0.3)
    p.env(2, a=0.001, d=0.2, s=0.45, r=0.3)
    p.env(4, a=1.8, d=0.1, s=1.0, r=0.4, acurve=0.35)
    p.mod("ENV4", "B_WTPOS", 0.55)
    p.mod("ENV4", "DIM_MIX", 0.3)
    punch(p, 0.4)
    mono(p, glide=0.04)
    velocity(p, 0.8, 0.35)
    vibrato(p, depth=0.012)
    p.mod("MODWHEEL", "B_WARP", 0.4)
    p.mod("PRESSURE", "FSAT_DRIVE", 0.25)
    p.mod("TIMBRE", "B_WTPOS", 0.35)
    vintage(p, 0.15)
    p.set("macro2", 0.45)
    drift(p, 1, 0.33, [("A_WTPOS", 0.25), ("CUTOFF", 0.07)])
    dimension(p, mix=0.0, size=0.6)
    p.tone("CUTOFF", 0.2)
    echo(p, time="3/16", mix=0.11, feedback=0.3, amount=0.12)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.45, base=0.22)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("The dark-pop signature: a punched, folded obsidian centre and a radiant octave that blooms wide after two seconds; the wheel snarls, pressure burns",
          "C3–C5", "Dark pop, alt-pop, anything with a hook", "Hooks; every expression input does something", "FOREGROUND",
          "Mono centre, bloom above; built to sit above a vocal-free chorus")
    out.append(p)

    return out
