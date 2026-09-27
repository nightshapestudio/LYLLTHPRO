"""EXPANSION 02 / INDUSTRIAL MONSTER BASSES. Every sub is its own unfiltered
sine or triangle; the violence is in two or more competing upper layers."""

from bank2._common import velocity
from bank2._showcase import drift, fsat, ladder, punch, vintage
from bank2._x2 import N, bass_space, burn, dc_guard, mono


def B(name, a="ANALOG", b="BASIC"):
    return N(name, "BASS", a, b)


def sub(p, level=0.55, shape="SINE"):
    return p.sub(level, shape, octave=1, pan=0.0, filtered=False)


def presets():
    out = []

    # 01 REACTOR TEETH: two competing upper layers, a linear folder on A and
    # a ring-modulated saw on B, their drive swapped by one slow asymmetric
    # (saw-down) LFO, so one grows as the other recedes.
    p = B("REACTOR TEETH", "NS OBSIDIAN", "ANALOG")
    p.osc(0, level=0.55, wt=0.5)
    p.osc(1, level=0.35, wt=1.0, octave=1, warp="RM", warp_amt=0.35)
    sub(p, 0.6)
    p.insert(1, "FOLD", amount=0.35, mix=0.6)
    p.filter("LP24", hz=720, res=0.28, keytrack=0.45, env=0.35)
    fsat(p, "HARD", drive=0.45)
    p.env(1, a=0.001, d=0.5, s=0.88, r=0.07)
    p.env(2, a=0.001, d=0.18, s=0.35, r=0.08)
    mono(p)
    velocity(p, 0.45, 0.2)
    p.lfo(1, "SAW_DOWN", hz=0.37, mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "INS1_AMOUNT", 0.35)
    p.motion("LFO1", "B_LEVEL", -0.25)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "LINFOLD", drive=0.35, base=0.25)
    dc_guard(p)
    p.doc("Two upper layers at war (a folded obsidian wave and a ring-modulated saw) trading dominance on a slow asymmetric cycle over an unmoving sine",
          "E0–E2", "Industrial, EBM, trailers", "Roots and riffs", "FOREGROUND",
          "The fold and the ring never peak together, so it stays thick without turning to mush")
    out.append(p)

    # 02 MECHANICAL ORGANISM: FM from B into A (warp FM) whose index is
    # driven by velocity and by a TRIG smooth random (biology), with a
    # tempo-locked performer ticking the ring (machine).
    p = B("MECHANICAL ORGANISM", "ANALOG", "NS THROAT")
    p.osc(0, level=0.6, wt=0.9, warp="FM", warp_amt=0.15)
    p.osc(1, level=0.3, wt=0.3)
    sub(p, 0.55)
    p.insert(2, "RING", after=True, amount=0.4, freq=0.5, mix=0.15)
    p.filter("FORMANT", hz=650, res=0.35, keytrack=0.3, mix=0.5)
    p.filter2("LP24", hz=1500, res=0.15, drive=0.35)
    p.env(1, a=0.002, d=0.5, s=0.88, r=0.08)
    mono(p)
    velocity(p, 0.45, 0.0)
    p.mod("VELOCITY", "A_WARP", 0.4, curve=0.4)
    p.mod("VELOCITY", "F2_CUTOFF", 0.25)
    p.lfo(1, "SMOOTH_RANDOM", hz=1.4, mode="TRIG")
    p.set("macro2", 0.4)
    p.motion("LFO1", "B_WTPOS", 0.45)
    p.motion("LFO1", "CUTOFF", 0.1)
    p.performer(1, {0: [(0.8, "DECAY"), (0.0, "HOLD"), (0.3, "DECAY"), (0.0, "HOLD")] * 4}, mode="SONG", rate="1/16")
    p.mod("PERF1", "INS2_AMOUNT", 0.35, aux="MACRO2")
    p.tone("F2_CUTOFF", 0.16)
    bass_space(p)
    burn(p, "TUBE", drive=0.45, base=0.2)
    dc_guard(p)
    p.doc("A growl that breathes (a vowel filter walked by a random) with a machine ticking inside it; velocity drives the FM index",
          "E0–E2", "Industrial, alt-electronic, film", "Held notes; dig in for teeth", "FOREGROUND",
          "Hard notes add FM sidebands, not level; the tick follows the tempo")
    out.append(p)

    # 03 CONCRETE EATER: a dense 150-400 Hz body from a stacked, 2-voice
    # saw into the ladder with bass loss; the top is bitcrush + zero-square,
    # and a slow random nudges the crush amount.
    p = B("CONCRETE EATER", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.6, wt=1.0, unison=2, detune=0.04, width=0.05)
    p.osc(1, level=0.25, wt=0.55, octave=1)
    sub(p, 0.6, "TRI")
    p.insert(2, "BITCRUSH", after=True, amount=0.5, mix=0.25)
    p.filter("LADDER", hz=520, res=0.3, keytrack=0.4, env=0.25)
    ladder(p, bass_loss=0.3)
    fsat(p, "SOFT", drive=0.5)
    p.env(1, a=0.002, d=0.6, s=0.9, r=0.07)
    p.env(2, a=0.001, d=0.2, s=0.4, r=0.08)
    mono(p)
    velocity(p, 0.45, 0.16)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.5, mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "INS2_AMOUNT", 0.25)
    p.motion("LFO1", "B_WTPOS", 0.3)
    p.motion("LFO1", "CUTOFF", 0.06)
    p.eq(mid=2.0, mid_hz=260, q=0.45)
    p.tone("CUTOFF", 0.16)
    burn(p, "ZEROSQUARE", drive=0.3, base=0.18)
    dc_guard(p)
    p.doc("Heavy concrete at 150–400 Hz with a crushed, zero-squared crust that crawls; the triangle sub never moves",
          "E0–E2", "Industrial rock, metal-electronic", "Riffs under huge drums", "FOREGROUND",
          "Built to leave the kick's 60 Hz and the snare's 2 kHz alone")
    out.append(p)

    # 04 FRACTURED ENGINE: layer A pulses on a 1/8 gate-shaped performer into
    # its warp; layer B's distortion character morphs slowly (sine folder mix
    # via a 0.13 Hz triangle). Two clocks, no wobble.
    p = B("FRACTURED ENGINE", "NS SCAR PULSE", "NS TENDON")
    p.osc(0, level=0.55, wt=0.3, warp="QUANTIZE", warp_amt=0.0)
    p.osc(1, level=0.35, wt=0.3)
    sub(p, 0.55)
    p.filter("LP24", hz=800, res=0.25, keytrack=0.45, env=0.3)
    p.env(1, a=0.002, d=0.5, s=0.88, r=0.07)
    mono(p)
    velocity(p, 0.45, 0.18)
    p.performer(1, {0: [(1.0, "PULSE"), (0.2, "HOLD"), (0.7, "PULSE"), (0.0, "HOLD"), (1.0, "PULSE"), (0.3, "HOLD"), (0.5, "DECAY"), (0.0, "HOLD")] * 2},
                mode="SONG", rate="1/8")
    p.set("macro2", 0.4)
    p.mod("PERF1", "A_WARP", 0.45, aux="MACRO2")
    p.lfo(1, "TRIANGLE", hz=0.13, mode="FREE")
    p.motion("LFO1", "B_WTPOS", 0.5)
    p.motion("LFO1", "DIST_MIX", 0.2)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "SINFOLD", drive=0.35, base=0.2)
    dc_guard(p)
    p.doc("Two clocks: the scarred pulse stutters its quantize on the eighth while the tendon layer slowly changes how it distorts",
          "E0–E2", "Industrial, breakbeat, dark electro", "Held notes and riffs", "FOREGROUND",
          "No LFO on the cutoff: the rhythm is in the waveform, so it never sounds like a wobble")
    out.append(p)

    # 05 BLACK MASS: round at low velocity; above ~90 velocity a rectify
    # insert, a growl layer and diode drive come in on steep curves.
    p = B("BLACK MASS", "BASIC", "GROWL")
    p.osc(0, level=0.62, wt=0.0)
    p.osc(1, level=0.0, wt=0.6, octave=1)
    sub(p, 0.5)
    p.insert(1, "RECTIFY", amount=0.0, mix=0.6)
    p.filter("LP24", hz=420, res=0.2, keytrack=0.45, env=0.2)
    p.env(1, a=0.003, d=0.6, s=0.9, r=0.08)
    mono(p)
    p.set("velSens", 0.25)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.6, curve=0.75)
    p.mod("VELOCITY", "B_LEVEL", 0.45, curve=0.7)
    p.mod("VELOCITY", "CUTOFF", 0.35, curve=0.6)
    p.mod("VELOCITY", "DIST_MIX", 0.4, curve=0.7)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.6, mode="FREE")
    p.set("macro2", 0.3)
    p.motion("LFO1", "B_WTPOS", 0.4)
    p.motion("LFO1", "CUTOFF", 0.08)
    fsat(p, "LIGHT", drive=0.35)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "DIODE", drive=0.5, base=0.0)
    dc_guard(p)
    p.doc("A smooth, oppressive sine bass that turns frightening only at the top of the velocity range: rectified octave, growl and diode burn",
          "E0–E2", "Dark pop, trailers, film", "Keep it soft, then hit one note hard", "FOREGROUND",
          "Curves are steep: velocity 60 is polite, 110 is hostile")
    out.append(p)

    # 06 VOLTAGE COLLAPSE: two bandpass-ish resonant peaks (filter BP24 and
    # a parallel comb) whose tunings drift apart; PUNCH keeps the front hard.
    p = B("VOLTAGE COLLAPSE", "ANALOG", "DIGITAL")
    p.osc(0, level=0.62, wt=1.0)
    p.osc(1, level=0.28, wt=0.6)
    sub(p, 0.55)
    p.filter("BP24", hz=700, res=0.45, keytrack=0.5, env=0.3, mix=0.6)
    p.filter2("COMB_NEG", hz=900, res=0.4, keytrack=1.0, mix=0.3)
    p.set("filter.routing", 1)
    p.env(1, a=0.001, d=0.45, s=0.85, r=0.07)
    p.env(2, a=0.001, d=0.12, s=0.3, r=0.07)
    punch(p, 0.55)
    mono(p)
    velocity(p, 0.8, 0.35)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.8, mode="FREE")
    p.lfo(2, "SAMPLE_HOLD", hz=6.0, mode="FREE", smooth=True)
    p.set("macro2", 0.35)
    p.motion("LFO1", "CUTOFF", 0.12)
    p.motion("LFO2", "F2_CUTOFF", 0.05)
    p.motion("LFO1", "B_WTPOS", 0.3)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "HARD", drive=0.5, base=0.25)
    dc_guard(p)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("Components under impossible load: a band-pass peak and a negative comb drifting against each other, sparking in small steps; a hard punched front",
          "E0–E2", "Industrial, cyberpunk scores, EBM", "Riffs and held notes", "FOREGROUND",
          "The comb twitches in tiny steps; MOTION 0 holds both peaks still")
    out.append(p)

    # 07 TITANIUM ROT: the metal is harmonic (CATHEDRAL METAL table + comb at
    # the octave), not a bell: filtered hard and saturated so it reads as grit.
    p = B("TITANIUM ROT", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.6, wt=0.95)
    p.osc(1, level=0.32, wt=0.4)
    sub(p, 0.55)
    p.insert(2, "COMB", after=True, amount=0.45, freq=0.75, mix=0.2)
    p.filter("LP24", hz=950, res=0.22, keytrack=0.45, env=0.25, drive=0.4)
    p.env(1, a=0.002, d=0.5, s=0.88, r=0.07)
    mono(p)
    velocity(p, 0.45, 0.16)
    p.mod("VELOCITY", "B_WTPOS", 0.3)
    p.lfo(1, "TRIANGLE", hz=0.21, mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "B_WTPOS", 0.4)
    p.motion("LFO1", "INS2_FREQ", 0.01)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "TUBE", drive=0.5, base=0.25)
    dc_guard(p)
    p.doc("A dense analog saw with a rotting titanium skin: harmonic metal clusters climbing through a driven filter, never a bell",
          "E0–E2", "Industrial, metal-electronic, trailers", "Held notes and slow riffs", "FOREGROUND",
          "The metal is filtered below 1 kHz, so it reads as texture, not a ring")
    out.append(p)

    # 08 BEDROCK: psychoacoustic weight: the sub is small; a rectified,
    # multiband-compressed 2nd/3rd harmonic stack makes the size.
    p = B("BEDROCK", "NS RADIANT", "BASIC")
    p.osc(0, level=0.6, wt=0.25)
    p.osc(1, level=0.25, wt=0.0, octave=1)
    sub(p, 0.38)
    p.insert(1, "RECTIFY", amount=0.35, mix=0.3)
    p.insert(2, "SINE", amount=0.35, mix=0.35)
    p.filter("LP24", hz=650, res=0.15, keytrack=0.45)
    fsat(p, "SHAPER", drive=0.35, mix=0.7)
    p.env(1, a=0.003, d=0.6, s=0.9, r=0.08)
    mono(p)
    velocity(p, 0.45, 0.18)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.35, mode="FREE")
    p.set("macro2", 0.3)
    p.motion("LFO1", "A_WTPOS", 0.35)
    p.motion("LFO1", "INS2_AMOUNT", 0.15)
    p.comp(mode="MULTIBAND", threshold=0.5, ratio=0.4, attack=0.3, release=0.35, gain=0.2, depth=0.55, mix=1.0)
    p.eq(low=-2, low_hz=40, mid=1.5, mid_hz=160)
    p.tone("A_WTPOS", 0.2)
    bass_space(p)
    burn(p, "SOFT", drive=0.4, base=0.16)
    dc_guard(p)
    p.doc("Overwhelming weight with modest real sub: rectified and sine-shaped harmonics, band-compressed, do the heavy lifting",
          "E0–E2", "Dark pop, film, trap-adjacent industrial", "Long roots", "FOREGROUND",
          "Measures lighter than it sounds; leaves the kick room at 50 Hz")
    out.append(p)

    # 09 SERPENT MACHINE: the SERPENT sync table scanned by two envelopes and
    # a free LFO; FLIP warp on B rolls its phase. Constant slither, fixed pitch.
    p = B("SERPENT MACHINE", "NS SERPENT", "ANALOG")
    p.osc(0, level=0.58, wt=0.1)
    p.osc(1, level=0.3, wt=0.9, warp="FLIP", warp_amt=0.2)
    sub(p, 0.55)
    p.filter("LP24", hz=1100, res=0.25, keytrack=0.5, env=0.3)
    p.env(1, a=0.002, d=0.5, s=0.88, r=0.08)
    p.env(3, a=0.001, d=0.4, s=0.3, r=0.1)
    p.env(4, a=1.5, d=0.1, s=1.0, r=0.1)
    p.mod("ENV3", "A_WTPOS", 0.3)
    p.mod("ENV4", "A_WTPOS", 0.25)
    mono(p, glide=0.05)
    velocity(p, 0.45, 0.16)
    p.lfo(1, "SINE", hz=0.43, mode="FREE")
    p.set("macro2", 0.4)
    p.motion("LFO1", "A_WTPOS", 0.25)
    p.motion("LFO1", "B_WARP", 0.2)
    fsat(p, "DIODE", drive=0.4)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "TUBE", drive=0.45, base=0.2)
    dc_guard(p)
    p.doc("A bass that slithers: the sync serpent is scanned by a snap envelope, a slow rise and a free sine, while a flipped saw rolls under it",
          "E0–E2", "Dark electro, industrial pop", "Held notes and legato slides", "FOREGROUND",
          "The fundamental stays put; every movement is in the sync ratio")
    out.append(p)

    # 10 THE DEVOURER: the flagship. Three upper layers (grindstone FM table,
    # folded saw, rectified octave), filter feedback, diode saturation, a
    # punched attack; wheel opens the grindstone, pressure feeds the loop.
    p = B("THE DEVOURER", "NS GRINDSTONE", "ANALOG")
    p.osc(0, level=0.52, wt=0.35)
    p.osc(1, level=0.34, wt=1.0, unison=2, detune=0.05, width=0.08)
    sub(p, 0.6)
    p.insert(1, "FOLD", after=True, amount=0.3, mix=0.4)
    p.insert(2, "RECTIFY", after=True, amount=0.3, mix=0.2)
    p.filter("LADDER", hz=850, res=0.3, keytrack=0.45, env=0.4)
    fsat(p, "DIODE", drive=0.45)
    p.feedback(amount=0.14, drive=0.65, tone=0.4)
    p.env(1, a=0.001, d=0.6, s=0.88, r=0.08)
    p.env(2, a=0.001, d=0.25, s=0.35, r=0.1)
    punch(p, 0.4)
    mono(p)
    velocity(p, 0.45, 0.22)
    p.mod("VELOCITY", "A_WTPOS", 0.3)
    p.mod("MODWHEEL", "A_WTPOS", 0.45)
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.3)
    p.mod("PRESSURE", "FEEDBACK", 0.25)
    p.mod("PRESSURE", "RES", 0.12)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.55, mode="FREE")
    p.lfo(2, "TRIANGLE", hz=0.17, mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "A_WTPOS", 0.25)
    p.motion("LFO2", "INS2_AMOUNT", 0.2)
    p.motion("LFO1", "CUTOFF", 0.06)
    vintage(p, 0.15)
    p.tone("CUTOFF", 0.16)
    bass_space(p)
    burn(p, "HARD", drive=0.55, base=0.3)
    dc_guard(p)
    p.doc("The flagship industrial bass: grindstone FM, a folded saw and a rectified octave fed through a diode ladder loop; wheel and pressure make it perform",
          "E0–E2", "Industrial, trailers, dark pop choruses", "One note is the demo; the wheel is the chorus", "FOREGROUND",
          "Below 100 Hz it is only the clean sine; everything that devours is above")
    out.append(p)

    return out
