"""SHOWCASE ARPS: sequences that perform. Every one programs the step
pattern: its own length (often not 16, so the phrase turns against the bar),
a level per step for accents and ghosts, a length per step for breath and
ties, rests, and per-step transposes that stay key-safe (octaves, fifths,
fourths) unless the preset is a signature line. Velocity routes make the
accents change tone, not just level."""

from lunatk import Preset
from bank2._common import echo, grit, space, velocity
from bank2._showcase import dimension, drift, fsat, morph, punch, vintage


def A(name, a="ANALOG", b="BASIC"):
    return Preset(name, "ARP", a, b)


def poly(p, vel=0.55):
    return p.voice(voices=8, glide=0.0, vel=vel, bend=2)


def pattern(p, steps):
    """steps: a list of (level, length, transpose), or None for a rest.
    Level also scales the note's velocity, so accents reach every velocity route."""
    p.set("arp.steps", len(steps))
    for i in range(16):
        step = steps[i] if i < len(steps) else None
        level, length, transpose = step if step else (0.0, 0.5, 0)
        p.set(f"arp.level{i}", level).set(f"arp.length{i}", max(0.05, min(1.0, length))).set(f"arp.transpose{i}", transpose)
    return p


def S(spec, table):
    """A pattern from a compact string: each character is a key in `table`
    -> (level, length, transpose); '.' is a rest."""
    return [None if c == "." else table[c] for c in spec]


def room(p, mix=0.12, decay=0.32, amount=0.14):
    return space(p, mix, mode="PLATE", size=0.5, decay=decay, damp=0.5, predelay=0.05, width=0.85, amount=amount)


def presets():
    out = []

    # 01 OBSIDIAN PULSE: a central note hammered with uneven weight, and two
    # octave jumps placed where a hook would put them (step 7 and step 13).
    p = A("OBSIDIAN PULSE", "NS OBSIDIAN", "ANALOG")
    p.osc(0, level=0.62, wt=0.35)
    p.osc(1, level=0.3, wt=0.9, octave=-1)
    p.insert(1, "FOLD", after=True, amount=0.3, mix=0.35)
    p.filter("LADDER", hz=1400, res=0.3, keytrack=0.5, env=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.filter2("HP12", hz=140)
    p.env(1, a=0.001, d=0.25, s=0.4, r=0.08)
    p.env(2, a=0.001, d=0.12, s=0.2, r=0.08)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AbcAbcOaAbcAbOcx", {
        "A": (1.0, 0.55, 0), "b": (0.55, 0.3, 0), "c": (0.7, 0.4, 0), "a": (0.8, 0.5, 0),
        "O": (1.0, 0.7, 12), "x": (0.45, 0.25, -12)}))
    velocity(p, 0.9, 0.35)
    p.mod("VELOCITY", "A_WTPOS", 0.35)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.21, [("A_WTPOS", 0.2), ("INS1_AMOUNT", 0.12)])
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    room(p, 0.08)
    grit(p, mode="TUBE", drive=0.5, tone=0.45, amount=0.4, base=0.3)
    p.doc("A dark electronic hook: one note hammered with uneven weight, octave leaps on the 7th and 13th steps, obsidian-folded edges",
          "C3–C5", "Industrial pop, dark pop, synth rock", "Hold one note or a triad", "FOREGROUND",
          "Loud accents change the wavetable, not just the level; it sits in front without being turned up")
    out.append(p)

    # 02 COLD BLOOM: starts tight, gets longer and more luminous: step
    # lengths grow through the 16 and a slow ENV3 opens the radiant table.
    p = A("COLD BLOOM", "NS RADIANT", "GLASS")
    p.osc(0, level=0.6, wt=0.1)
    p.osc(1, level=0.22, wt=0.5, octave=1, unison=3, detune=0.08, width=0.9)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.507, mix=0.12)
    p.filter("LP24", hz=2600, res=0.15, keytrack=0.4, env=0.25)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.002, d=0.35, s=0.3, r=0.25)
    p.env(2, a=0.001, d=0.2, s=0.2, r=0.2)
    p.env(3, a=4.0, d=0.1, s=1.0, r=0.5)
    p.mod("ENV3", "A_WTPOS", 0.6)
    p.mod("ENV3", "B_WIDTH", 0.6)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.9)
    pattern(p, [(0.9, 0.2, 0), (0.5, 0.2, 0), (0.7, 0.25, 0), (0.5, 0.3, 0), (0.9, 0.35, 0), None, (0.65, 0.45, 0), (0.55, 0.5, 0),
                (1.0, 0.6, 12), (0.5, 0.4, 0), (0.7, 0.7, 0), None, (0.85, 0.85, 7), (0.5, 0.5, 0), (0.75, 1.0, 0), (0.4, 0.3, 12)])
    velocity(p, 0.5, 0.15)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.17, [("B_WTPOS", 0.2)])
    echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12, pingpong=True)
    room(p, 0.12)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.12)
    p.set("dist.mix", 0.16)
    p.doc("A tight pattern that breathes out: notes lengthen through the bar while the radiant table and the width open over four seconds",
          "C3–C5", "Dark pop, art pop, film", "Held chords, verses into choruses", "FOREGROUND",
          "Emotional without sugar: the long steps land on the fifth and the octave, never a pretty third")
    out.append(p)

    # 03 MACHINE PRAYER: a 7-step motif against the 16th grid, with a
    # fourth-down interruption; minimal enough for a vocal.
    p = A("MACHINE PRAYER", "NS HOLLOW BONE", "BASIC")
    p.osc(0, level=0.6, wt=0.25)
    p.osc(1, level=0.2, wt=0.0, octave=-1)
    p.insert(1, "COMB", after=True, amount=0.4, freq=0.75, mix=0.2)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.3, s=0.2, r=0.15)
    p.env(2, a=0.001, d=0.15, s=0.1, r=0.1)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.7)
    pattern(p, [(1.0, 0.5, 0), (0.45, 0.3, 0), None, (0.7, 0.5, 0), (0.45, 0.3, 0), (0.8, 0.5, -5), None])
    velocity(p, 0.5, 0.15)
    p.mod("VELOCITY", "A_WTPOS", 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.13, [("A_WTPOS", 0.25), ("INS1_FREQ", 0.01)])
    echo(p, time="1/4", mix=0.1, feedback=0.3, amount=0.12)
    room(p, 0.1)
    grit(p, mode="SOFT", drive=0.35, tone=0.45, amount=0.35, base=0.15)
    p.doc("A seven-step prayer turning against the bar, interrupted each cycle by a drop of a fourth; hollow-bone tone",
          "C3–C5", "Dark pop verses, film, electronica", "Hold a note or a chord for bars", "RHYTHM",
          "Seven steps means the accent lands somewhere new each bar: hypnotic, never static")
    out.append(p)

    # 04 GLASS ENGINE: a small melodic machine; +24 flashes on selected steps.
    p = A("GLASS ENGINE", "GLASS", "NS CATHEDRAL METAL")
    p.osc(0, level=0.6, wt=0.5)
    p.osc(1, level=0.25, wt=0.3, octave=-1)
    p.filter("LP24", hz=3600, res=0.15, keytrack=0.5, env=0.25)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.001, d=0.22, s=0.15, r=0.2)
    p.env(2, a=0.001, d=0.08, s=0.2, r=0.15)
    punch(p, 0.35)
    poly(p)
    p.arp(mode="UPDOWN", rate="1/16", octaves=1, gate=0.6)
    pattern(p, S("aba+aba7ab+abaxa", {
        "a": (0.8, 0.4, 0), "b": (0.5, 0.3, 0), "+": (0.9, 0.25, 24), "7": (0.7, 0.4, 7), "x": (0.6, 0.5, 12)}))
    velocity(p, 0.5, 0.12)
    p.mod("VELOCITY", "B_WTPOS", 0.4)
    p.eq(high=-2, high_hz=9000)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.19, [("B_WTPOS", 0.2)])
    echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12, pingpong=True)
    room(p, 0.1)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.3, base=0.12)
    p.set("dist.mix", 0.16)
    fsat(p, "SOFT", drive=0.32)
    p.doc("A small glass machine: up-and-down steps with two-octave flashes of metal light over a deeper core",
          "C3–C5", "Dark pop, electronica, film", "Held chords", "RHYTHM",
          "The flashes are short and quieter than the core; the top is already rolled off at 9 kHz")
    out.append(p)

    # 05 STATIC HEARTBEAT: lub-dub accents with human variation in level and
    # length; warm, damaged, close.
    p = A("STATIC HEARTBEAT", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.6, wt=0.8)
    p.osc(1, level=0.25, wt=0.25)
    p.noise(0.04, type="VINYL", color=0.5, keytrack=False)
    p.insert(1, "DECIMATE", after=True, amount=0.2, mix=0.25)
    p.filter("LP24", hz=1800, res=0.18, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.002, d=0.3, s=0.25, r=0.15)
    p.env(2, a=0.001, d=0.15, s=0.15, r=0.1)
    poly(p)
    vintage(p, 0.35)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(1.0, 0.45, 0), (0.62, 0.35, 0), None, None, (0.35, 0.2, 0), None, (0.5, 0.3, 12), None,
                (0.95, 0.5, 0), (0.58, 0.3, 0), None, (0.3, 0.2, 0), None, (0.42, 0.25, 0), (0.55, 0.4, 7), None])
    velocity(p, 0.65, 0.32)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.23, [("B_WTPOS", 0.25), ("INS1_AMOUNT", 0.1)])
    room(p, 0.12)
    grit(p, mode="TUBE", drive=0.4, tone=0.45, amount=0.35, base=0.18)
    p.doc("A pulse like a heartbeat, lub-dub with ghost notes between, each beat a little different in weight and length",
          "C3–C5", "Dark pop, alt-R&B, intimate electronic", "Held notes or chords", "FOREGROUND",
          "Warm and a little broken; the gaps leave room for a vocal")
    out.append(p)

    # 06 BURNING CIRCUIT: a 12-step industrial motif with irregular octave
    # displacement; the last three steps shorten and hit harder.
    p = A("BURNING CIRCUIT", "NS GRINDSTONE", "ANALOG")
    p.osc(0, level=0.58, wt=0.45)
    p.osc(1, level=0.3, wt=1.0, octave=-1)
    p.sub(0.2, "SINE", filtered=False)
    p.filter("LP24", hz=1500, res=0.28, keytrack=0.5, env=0.45, drive=0.4)
    p.filter2("HP12", hz=110)
    p.env(1, a=0.001, d=0.2, s=0.35, r=0.06)
    p.env(2, a=0.001, d=0.1, s=0.15, r=0.06)
    punch(p, 0.5)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.85)
    pattern(p, [(0.9, 0.6, 0), (0.5, 0.35, 0), (0.7, 0.5, 12), (0.5, 0.35, 0), (0.9, 0.6, 0), None,
                (0.6, 0.4, -12), (0.8, 0.5, 0), (0.55, 0.3, 12), (1.0, 0.3, 0), (1.0, 0.25, 0), (1.0, 0.2, 12)])
    velocity(p, 0.5, 0.2)
    p.mod("VELOCITY", "A_WTPOS", 0.4)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.29, [("A_WTPOS", 0.2)])
    grit(p, mode="HARD", drive=0.55, tone=0.45, amount=0.4, base=0.35)
    p.doc("An industrial motif that turns every twelve steps and tightens into three hard stabs; grindstone mids over a clean root",
          "C2–C4", "Industrial rock, EBM, trailers", "Hold a root or a power chord", "FOREGROUND",
          "Not a dance arp: the motif is irregular and the accents are distortion, not level")
    out.append(p)

    # 07 GHOST PATTERN: sparse; silence is the groove.
    p = A("GHOST PATTERN", "NS THROAT", "BASIC")
    p.osc(0, level=0.6, wt=0.2)
    p.osc(1, level=0.15, wt=0.0, octave=1)
    p.noise(0.05, type="BREATH", color=0.5, keytrack=True)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.51, mix=0.15)
    p.filter("LP12", hz=2200, res=0.12, keytrack=0.5)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.004, d=0.6, s=0.3, r=0.35)
    poly(p)
    p.arp(mode="PLAYED", rate="1/8", octaves=1, gate=0.9)
    pattern(p, [(0.8, 0.9, 0), None, None, (0.45, 0.5, 12), None, None, None, (0.6, 0.7, 7),
                None, (0.35, 0.4, 0), None, None, (0.7, 1.0, -5), None, None, None])
    velocity(p, 0.5, 0.12)
    p.mod("VELOCITY", "A_WTPOS", 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.11, [("A_WTPOS", 0.3), ("INS1_FREQ", 0.01)])
    echo(p, time="3/8", mix=0.14, feedback=0.22, amount=0.12, pingpong=True)
    room(p, 0.16, decay=0.4)
    grit(p, mode="SOFT", drive=0.3, tone=0.45, amount=0.3, base=0.1)
    p.doc("A haunted, sparse phrase: five notes over two bars, a whispering vowel tone, the silence doing the rest",
          "C3–C5", "Film, dark pop, horror", "Hold a chord for two bars or more", "TEXTURE",
          "The echo fills the gaps faintly; SPACE down makes the silence starker")
    out.append(p)

    # 08 NEON WOUND: a wide contour spread over three octaves, tight rhythm.
    p = A("NEON WOUND", "NS NEON NERVE", "ANALOG")
    p.osc(0, level=0.58, wt=0.35)
    p.osc(1, level=0.28, wt=0.95, unison=4, detune=0.1, width=0.9)
    p.filter("LP24", hz=2400, res=0.2, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.001, d=0.25, s=0.3, r=0.15)
    p.env(2, a=0.001, d=0.14, s=0.2, r=0.1)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=3, gate=0.7)
    pattern(p, S("AabAabcaAabxAbca", {
        "A": (1.0, 0.5, 0), "a": (0.55, 0.35, 0), "b": (0.7, 0.4, 0), "c": (0.85, 0.6, 7), "x": (0.9, 0.5, -12)}))
    velocity(p, 0.65, 0.32)
    p.mod("VELOCITY", "A_WTPOS", 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.19, [("A_WTPOS", 0.3)])
    dimension(p, mix=0.25, size=0.6)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    room(p, 0.1)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.35, base=0.2)
    fsat(p, "SOFT", drive=0.32)
    p.doc("A chorus-sized contour climbing three octaves with a fifth and a drop placed like a melody, over a neon resonance sweep",
          "C3–C5", "Dark pop choruses, synth rock", "Held triads", "FOREGROUND",
          "Wide from its detuned layer; the contour, not density, gives it size")
    out.append(p)

    # 09 SECONDHAND LIGHT: a nostalgic pattern without retro tone: soft
    # attacks, uneven dynamics, a small familiar-feeling turn.
    p = A("SECONDHAND LIGHT", "NS HOLLOW BONE", "ANALOG")
    p.osc(0, level=0.58, wt=0.45)
    p.osc(1, level=0.28, wt=0.7, fine=6)
    p.insert(1, "DECIMATE", after=True, amount=0.2, mix=0.25)
    p.filter("LP12", hz=2400, res=0.1, keytrack=0.4)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.02, d=0.4, s=0.35, r=0.3)
    poly(p)
    vintage(p, 0.45)
    p.arp(mode="UPDOWN", rate="1/8", octaves=2, gate=0.9)
    pattern(p, [(0.8, 0.8, 0), (0.5, 0.6, 0), (0.65, 0.9, 0), (0.45, 0.5, 0), (0.75, 0.8, 12), (0.5, 0.6, 0), (0.6, 1.0, 7), None])
    velocity(p, 0.5, 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.33, [("A_FINE", 0.04), ("B_FINE", 0.06)], shape="SINE")
    drift(p, 2, 0.12, [("A_WTPOS", 0.25)])
    p.chorus(mode="SUBTLE", mix=0.2, rate=0.3, depth=0.35, width=0.6)
    room(p, 0.14)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.3, base=0.1)
    p.set("dist.mix", 0.16)
    p.doc("Feels like something you have heard before and cannot place: soft eighths, a turn at the top, a faint tape wow",
          "C3–C5", "Dream pop, dark pop, film", "Slow chords", "SUPPORT",
          "No saws, no gated reverb: the nostalgia is in the drift and the uneven hands")
    out.append(p)

    # 10 PRESSURE SYSTEM: repeated tones, a tritone and minor-second push,
    # accents that lean.
    p = A("PRESSURE SYSTEM", "ANALOG", "NS TENDON")
    p.osc(0, level=0.6, wt=0.95)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LP24", hz=1300, res=0.35, keytrack=0.5, env=0.4, drive=0.35)
    p.feedback(amount=0.15, drive=0.5, tone=0.5)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.2, s=0.4, r=0.08)
    p.env(2, a=0.001, d=0.12, s=0.2, r=0.08)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AaaAaaTaAaaAaSOa", {
        "A": (1.0, 0.5, 0), "a": (0.45, 0.3, 0), "T": (0.85, 0.5, 6), "S": (0.8, 0.4, 1), "O": (1.0, 0.6, 12)}))
    velocity(p, 0.55, 0.22)
    p.mod("VELOCITY", "B_WTPOS", 0.4)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.27, [("FB_TONE", 0.2), ("B_WTPOS", 0.2)])
    room(p, 0.06)
    grit(p, mode="TUBE", drive=0.5, tone=0.45, amount=0.4, base=0.25)
    p.doc("Pressure in sixteenths: a note hammered in threes, a tritone and a semitone pushing against it, never resolving",
          "C2–C4", "Industrial, film, dark techno", "Hold single notes", "FOREGROUND",
          "A signature pattern: the tritone and semitone are fixed, so hold roots rather than chords")
    out.append(p)

    # 11 RESIDUE: short notes, then a long held step whose comb tail lingers.
    p = A("RESIDUE", "ANALOG", "SPECTRAL_COMB")
    p.osc(0, level=0.6, wt=0.85)
    p.osc(1, level=0.25, wt=0.5, octave=1)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.5, env=0.35)
    p.filter2("COMB_POS", hz=700, res=0.55, keytrack=1.0, mix=0.3)
    p.env(1, a=0.001, d=0.3, s=0.4, r=0.9)
    p.env(2, a=0.001, d=0.15, s=0.2, r=0.4)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.6)
    pattern(p, [(0.8, 0.2, 0), (0.55, 0.2, 0), (0.7, 0.2, 0), (1.0, 1.0, 12), None, None, (0.6, 0.2, 0), (0.5, 0.2, 0),
                (0.75, 0.2, 7), (0.9, 1.0, 0), None, None, (0.5, 0.2, 0), (0.65, 0.2, 0), (0.85, 1.0, 12), None])
    velocity(p, 0.5, 0.15)
    p.lfo(1, "SINE", hz=0.3, mode="FREE")
    p.set("macro2", 0.45)
    p.motion("LFO1", "F2_CUTOFF", 0.12)
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12)
    room(p, 0.12)
    grit(p, mode="SOFT", drive=0.35, tone=0.45, amount=0.35, base=0.15)
    p.doc("Three short notes, then a held one whose comb tail keeps ringing and shifting under the next run",
          "C3–C5", "Dark pop, electronica, film", "Held chords", "FOREGROUND",
          "The long steps overlap into the next phrase, so the arp builds its own harmony")
    out.append(p)

    # 12 BLACK ICE: precise, cold; octave peaks as punctuation.
    p = A("BLACK ICE", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.58, wt=0.75)
    p.osc(1, level=0.22, wt=0.85, octave=2)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.75, mix=0.12)
    p.filter("LP24", hz=1700, res=0.2, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=170)
    p.route_filter(a=True, b=False)
    p.env(1, a=0.001, d=0.25, s=0.3, r=0.12)
    p.env(2, a=0.001, d=0.12, s=0.2, r=0.1)
    poly(p)
    p.arp(mode="DOWN", rate="1/16", octaves=2, gate=0.65)
    pattern(p, S("AbaBabaPAbaBabP.", {
        "A": (0.95, 0.45, 0), "a": (0.45, 0.3, 0), "b": (0.6, 0.35, 0), "B": (0.75, 0.4, 0), "P": (1.0, 0.7, 12)}))
    velocity(p, 0.5, 0.15)
    p.mod("VELOCITY", "B_LEVEL", 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.21, [("B_WTPOS", 0.15)])
    room(p, 0.1)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.3, base=0.12)
    p.set("dist.mix", 0.16)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("Cold and exact: a descending line with a dark body, icy radiant partials two octaves up, octave peaks as punctuation",
          "C3–C5", "Dark pop, electronica, film", "Held chords", "RHYTHM",
          "Velocity shapes it, so programming a single velocity still sounds phrased")
    out.append(p)

    # 13 SOFT VIOLENCE: velocity is the performance: soft is intimate, hard
    # exposes fold, drive and transient bite.
    p = A("SOFT VIOLENCE", "NS TENDON", "ANALOG")
    p.osc(0, level=0.6, wt=0.05)
    p.osc(1, level=0.0, wt=1.0, octave=-1)
    p.filter("LP24", hz=1500, res=0.2, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=0.3, s=0.35, r=0.12)
    p.env(2, a=0.001, d=0.12, s=0.2, r=0.1)
    poly(p, vel=0.35)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.75)
    pattern(p, [(0.8, 0.5, 0), (0.4, 0.3, 0), (0.6, 0.4, 0), None, (0.75, 0.5, 12), (0.4, 0.3, 0), (0.55, 0.4, 0), (0.4, 0.3, 0)])
    p.mod("VELOCITY", "A_WTPOS", 0.7, curve=0.5)
    p.mod("VELOCITY", "B_LEVEL", 0.3, curve=0.5)
    p.mod("VELOCITY", "DIST_MIX", 0.4, curve=0.5)
    p.mod("VELOCITY", "CUTOFF", 0.2)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.23, [("A_WTPOS", 0.1)])
    room(p, 0.1)
    grit(p, mode="HARD", drive=0.5, tone=0.45, amount=0.35, base=0.0)
    p.set("dist.mix", 0.16)
    p.doc("Played softly, an intimate pulse; played hard, the tendon table folds, a saw growls in underneath and it bites",
          "C3–C5", "Dark pop, industrial pop", "Velocity is the arrangement: verses soft, choruses hard", "FOREGROUND",
          "The change is in timbre far more than level")
    out.append(p)

    # 14 SHADOW MELODY: a short motif under a vocal: 10 steps with a fall
    # of a fourth that makes held harmony feel charged.
    p = A("SHADOW MELODY", "NS DUST ORACLE", "BASIC")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.2, wt=0.0, octave=-1)
    p.filter("LP24", hz=2000, res=0.15, keytrack=0.5, env=0.25)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.003, d=0.35, s=0.35, r=0.25)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(0.8, 0.6, 0), (0.45, 0.35, 0), (0.6, 0.4, 0), (0.9, 0.8, 12), None, (0.5, 0.4, 0), (0.7, 0.6, -5), (0.45, 0.35, 0),
                (0.55, 0.5, 0), None])
    velocity(p, 0.5, 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.09, [("A_WTPOS", 0.35)])
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12)
    room(p, 0.12)
    grit(p, mode="SOFT", drive=0.3, tone=0.45, amount=0.3, base=0.1)
    p.set("dist.mix", 0.16)
    fsat(p, "SOFT", drive=0.32)
    p.doc("A shadow of a tune under the vocal: a ten-step motif with a reach up and a fall of a fourth, its colour drifting slowly",
          "C3–C5", "Dark pop, art pop, ballads", "Held chords under a voice", "SUPPORT",
          "Short enough to stay a texture; the dust-oracle table keeps each pass a different colour")
    out.append(p)

    # 15 BROKEN CLOCK: uneven on purpose: 11 steps, mixed lengths, rests
    # placed off the beat; it still grooves.
    p = A("BROKEN CLOCK", "NS FRACTURE", "ANALOG")
    p.osc(0, level=0.58, wt=0.25)
    p.osc(1, level=0.28, wt=0.9)
    p.insert(1, "COMB", after=True, amount=0.35, freq=0.75, mix=0.15)
    p.filter("LP24", hz=2200, res=0.25, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.2, s=0.3, r=0.1)
    p.env(2, a=0.001, d=0.1, s=0.2, r=0.08)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8, swing=0.12)
    pattern(p, [(1.0, 0.9, 0), (0.5, 0.2, 0), None, (0.8, 0.5, 12), (0.45, 0.2, 0), (0.7, 0.9, 0), None, None,
                (0.9, 0.3, 7), (0.55, 0.2, 0), (0.65, 0.6, -12)])
    velocity(p, 0.65, 0.32)
    p.mod("VELOCITY", "A_WTPOS", 0.35)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.31, [("A_WTPOS", 0.15)])
    echo(p, time="1/8", mix=0.08, feedback=0.25, amount=0.1)
    room(p, 0.1)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.35, base=0.2)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("An eleven-step clock with a limp: long and short steps, off-beat holes, a little swing, and it still grooves",
          "C3–C5", "Alt-electronic, art pop, glitch pop", "Held notes and chords", "RHYTHM",
          "Nothing is random: the same stumble every eleven steps, so the ear learns it")
    out.append(p)

    # 16 VELVET MACHINE: smooth, luxurious, gentle octave changes.
    p = A("VELVET MACHINE", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.6, wt=0.8, unison=3, detune=0.07, width=0.5)
    p.osc(1, level=0.22, wt=0.05, octave=-1)
    p.filter("LP24", hz=1600, res=0.15, keytrack=0.5, env=0.25)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.006, d=0.4, s=0.45, r=0.25)
    poly(p)
    p.arp(mode="UPDOWN", rate="1/16", octaves=2, gate=0.9)
    pattern(p, [(0.75, 0.8, 0), (0.5, 0.7, 0), (0.6, 0.8, 0), (0.5, 0.7, 0), (0.7, 0.9, 12), (0.5, 0.7, 0), (0.6, 0.8, 0), (0.45, 0.6, 0),
                (0.75, 0.8, 0), (0.5, 0.7, 0), (0.6, 0.8, 0), (0.5, 0.7, 0), (0.65, 1.0, -12), (0.5, 0.7, 0), (0.55, 0.8, 0), (0.4, 0.6, 0)])
    velocity(p, 0.45, 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.13, [("B_WTPOS", 0.2), ("CUTOFF", 0.04)])
    p.chorus(mode="WIDE", mix=0.2, rate=0.25, depth=0.35, width=0.6)
    room(p, 0.12)
    grit(p, mode="SOFT", drive=0.35, tone=0.4, amount=0.3, base=0.12)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("A luxurious, legato-leaning sequence with a warm saw and an obsidian shadow; gentle octave turns, soft mechanics",
          "C3–C5", "Dark pop verses, bridges, R&B-leaning electronic", "Held chords", "SUPPORT",
          "Long steps and a soft attack: it flows rather than ticks")
    out.append(p)

    # 17 RAZOR PULSE: high definition, strong transient, controlled decay.
    p = A("RAZOR PULSE", "NS SERPENT", "ANALOG")
    p.osc(0, level=0.6, wt=0.12)
    p.osc(1, level=0.25, wt=0.95)
    p.filter("LP24", hz=2600, res=0.2, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.0005, d=0.15, s=0.15, r=0.06)
    p.env(2, a=0.0005, d=0.06, s=0.1, r=0.05)
    p.env(3, a=0.0005, d=0.03, s=0.0, r=0.02)
    p.mod("ENV3", "A_WTPOS", 0.3)
    punch(p, 0.6)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.6)
    pattern(p, S("AaBaAa7aAaBaAxOa", {
        "A": (1.0, 0.4, 0), "a": (0.5, 0.25, 0), "B": (0.8, 0.35, 0), "7": (0.85, 0.35, 7), "x": (0.7, 0.3, -12), "O": (0.9, 0.35, 12)}))
    velocity(p, 0.65, 0.32)
    p.eq(mid=1.5, mid_hz=2500, high=-2.5, high_hz=8000)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.23, [("A_WTPOS", 0.15)])
    room(p, 0.06)
    grit(p, mode="HARD", drive=0.45, tone=0.45, amount=0.35, base=0.2)
    p.context(unpitched=True)
    p.doc("A razor-sharp pulse: a 30 ms sync snap per note, short decay, placed accents; cuts through guitars without shrillness",
          "C3–C5", "Synth rock, industrial pop, electro", "Held notes and chords", "RHYTHM",
          "The bite is at 2.5 kHz and the air is trimmed; it cuts by shape, not treble")
    out.append(p)

    # 18 WIRETAP: narrow, tense transmission; simple core, small deviations.
    p = A("WIRETAP", "ANALOG", "NS THROAT")
    p.osc(0, level=0.6, wt=0.9)
    p.osc(1, level=0.25, wt=0.6)
    p.filter("BP24", hz=1400, res=0.35, keytrack=0.5)
    fsat(p, "HARD", drive=0.45)
    p.filter2("HP12", hz=300)
    p.env(1, a=0.001, d=0.2, s=0.35, r=0.08)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.7)
    pattern(p, S("AaaaAaaaAaahAaa.", {"A": (0.9, 0.45, 0), "a": (0.5, 0.3, 0), "h": (0.75, 0.35, 12)}))
    velocity(p, 0.5, 0.15)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.6, mode="FREE")
    p.lfo(2, "SMOOTH_RANDOM", hz=3.3, mode="FREE")
    p.set("macro2", 0.45)
    p.motion("LFO1", "CUTOFF", 0.08)
    p.motion("LFO2", "AMP", 0.05)
    p.motion("LFO1", "B_WTPOS", 0.3)
    p.tone("CUTOFF", 0.18)
    room(p, 0.06)
    grit(p, mode="DIODE", drive=0.45, tone=0.45, amount=0.35, base=0.25)
    p.doc("A narrow band of signal ticking along, one high note slipping in near the end of each bar, the band drifting and fluttering",
          "C3–C5", "Industrial, film, dark pop verses", "Hold a note for long sections", "RHYTHM",
          "Simple on purpose: it can run for sixteen bars without wearing out")
    out.append(p)

    # 19 NIGHT DRIVE: syncopated, forward, bass-heavy; not synthwave.
    p = A("NIGHT DRIVE", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.62, wt=0.9)
    p.osc(1, level=0.28, wt=0.3, octave=-1)
    p.filter("LADDER", hz=900, res=0.3, keytrack=0.5, env=0.45)
    p.filter2("HP12", hz=95)
    p.env(1, a=0.001, d=0.2, s=0.35, r=0.07)
    p.env(2, a=0.001, d=0.12, s=0.15, r=0.07)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(1.0, 0.6, -12), None, (0.6, 0.4, 0), (0.8, 0.5, 0), None, (0.55, 0.35, 0), (0.9, 0.6, -12), (0.5, 0.3, 0),
                None, (0.7, 0.5, 12), (0.55, 0.35, 0), None, (0.95, 0.6, -12), (0.5, 0.3, 0), (0.75, 0.5, 7), (0.6, 0.4, 0)])
    velocity(p, 0.9, 0.35)
    p.mod("VELOCITY", "B_WTPOS", 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.19, [("B_WTPOS", 0.2)])
    room(p, 0.05)
    grit(p, mode="TUBE", drive=0.5, tone=0.45, amount=0.4, base=0.25)
    p.doc("Forward motion for a bass-heavy track: syncopated sixteenths dropping an octave on the push beats, ladder-filtered",
          "C2–C4", "Dark electronic, alt-pop, techno-leaning", "Hold one note per chord", "FOREGROUND",
          "It is half a bass line: leave the real bass on long notes or let this carry it")
    out.append(p)

    # 20 SLOW PANIC: denser and shorter toward the end, tension intervals late.
    p = A("SLOW PANIC", "NS DUST ORACLE", "ANALOG")
    p.osc(0, level=0.58, wt=0.4)
    p.osc(1, level=0.28, wt=0.95)
    p.filter("LP24", hz=1700, res=0.3, keytrack=0.5, env=0.4)
    p.feedback(amount=0.1, drive=0.5, tone=0.5)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.2, s=0.3, r=0.08)
    p.env(2, a=0.001, d=0.1, s=0.15, r=0.06)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(0.8, 0.9, 0), None, None, (0.5, 0.6, 0), (0.7, 0.8, 0), None, (0.55, 0.5, 0), (0.6, 0.5, 12),
                (0.75, 0.4, 0), (0.6, 0.35, 0), (0.8, 0.3, 1), (0.65, 0.3, 0), (0.9, 0.25, 6), (0.8, 0.2, 0), (1.0, 0.2, 12), (1.0, 0.15, 1)])
    velocity(p, 0.55, 0.22)
    p.mod("VELOCITY", "FEEDBACK", 0.1)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.23, [("A_WTPOS", 0.25)])
    room(p, 0.08)
    grit(p, mode="TUBE", drive=0.5, tone=0.45, amount=0.35, base=0.2)
    p.doc("Calm at the top of the bar, frantic by the end: steps get denser and shorter and the intervals slide to a semitone and a tritone",
          "C3–C5", "Film, industrial, dark pop pre-choruses", "Hold single notes", "FOREGROUND",
          "A signature pattern; the semitones are baked in, so play roots")
    out.append(p)

    # 21 SILVER VEINS: warm midrange pattern with thin +24 flashes.
    p = A("SILVER VEINS", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.6, wt=0.85)
    p.osc(1, level=0.2, wt=0.7, octave=1)
    p.filter("LP24", hz=1500, res=0.18, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.002, d=0.25, s=0.3, r=0.15)
    p.env(2, a=0.001, d=0.12, s=0.15, r=0.1)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=1, gate=0.75)
    pattern(p, S("aba+abab+aba+ab.", {"a": (0.8, 0.5, 0), "b": (0.55, 0.4, 0), "+": (0.6, 0.2, 24)}))
    velocity(p, 0.9, 0.35)
    p.mod("VELOCITY", "B_WTPOS", 0.35)
    p.eq(high=-2, high_hz=9000)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.17, [("B_WTPOS", 0.25)])
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12, pingpong=True)
    room(p, 0.1)
    grit(p, mode="SOFT", drive=0.35, tone=0.45, amount=0.3, base=0.12)
    p.set("dist.mix", 0.16)
    fsat(p, "SOFT", drive=0.32)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("A warm mid-register run with thin silver flashes two octaves up, spaced so they read as veins, not a layer",
          "C3–C5", "Dark pop, electronica, film", "Held chords", "RHYTHM",
          "The flashes are short and a little quieter; they catch light without adding harshness")
    out.append(p)

    # 22 EMPTY ROOM: very few notes, strong personality.
    p = A("EMPTY ROOM", "NS HOLLOW BONE", "BASIC")
    p.osc(0, level=0.6, wt=0.6)
    p.osc(1, level=0.2, wt=0.0, octave=-1)
    p.insert(1, "COMB", after=True, amount=0.45, freq=0.75, mix=0.2)
    p.filter("LP24", hz=2200, res=0.15, keytrack=0.5)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.002, d=0.8, s=0.3, r=0.45)
    poly(p)
    p.arp(mode="PLAYED", rate="1/8", octaves=1, gate=1.0)
    pattern(p, [(0.9, 1.0, 0), None, None, None, (0.5, 0.6, 12), None, None, (0.7, 1.0, 7), None, None, None, None])
    velocity(p, 0.5, 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.1, [("A_WTPOS", 0.3), ("INS1_FREQ", 0.01)])
    echo(p, time="3/8", mix=0.12, feedback=0.22, amount=0.12, pingpong=True)
    room(p, 0.16, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.45, amount=0.3, base=0.1)
    p.set("dist.mix", 0.16)
    p.doc("Three notes in a twelve-step cycle: long, an octave, a fifth, and silence; proof an arp does not need to be busy",
          "C3–C5", "Film, ballads, ambient pop", "Hold one chord for a long time", "TEXTURE",
          "Twelve eighths against a 4/4 bar: the notes drift across the beat over three bars")
    out.append(p)

    # 23 OVERRIDE: a high-end synth pushed past safe limits: asymmetric
    # 13-step phrase, accents into feedback and fold, octave instability.
    p = A("OVERRIDE", "NS GRINDSTONE", "ANALOG")
    p.osc(0, level=0.58, wt=0.55)
    p.osc(1, level=0.3, wt=1.0, fine=7)
    p.filter("LP24", hz=1800, res=0.45, keytrack=0.5, env=0.35, drive=0.45)
    p.feedback(amount=0.25, drive=0.7, tone=0.6)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.2, s=0.4, r=0.08)
    p.env(2, a=0.001, d=0.1, s=0.2, r=0.08)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.85)
    pattern(p, [(1.0, 0.5, 0), (0.5, 0.3, 12), (0.7, 0.4, 0), (0.9, 0.6, -12), (0.5, 0.3, 0), (1.0, 0.3, 12), None,
                (0.8, 0.5, 0), (0.6, 0.3, 7), (1.0, 0.7, 0), (0.5, 0.3, 24), (0.7, 0.4, 0), (1.0, 0.25, -12)])
    velocity(p, 0.55, 0.2)
    p.mod("VELOCITY", "FEEDBACK", 0.15)
    p.mod("VELOCITY", "A_WTPOS", 0.35)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.37, [("RES", 0.06), ("A_WTPOS", 0.15)])
    grit(p, mode="HARD", drive=0.55, tone=0.45, amount=0.35, base=0.35)
    p.doc("An expensive synth past its limits: a thirteen-step phrase lurching between octaves, accents that overload the filter loop",
          "C3–C5", "Industrial, noise pop, trailers", "Hold single notes or fifths", "FOREGROUND",
          "Chaos with a map: the same thirteen steps every time, and the loop never runs away")
    out.append(p)

    # 24 LAST LIGHT: a clear rise and fall across 16 steps; emotional, flexible.
    p = A("LAST LIGHT", "NS RADIANT", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.25, wt=0.8, unison=3, detune=0.08, width=0.7)
    p.filter("LP24", hz=2400, res=0.15, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.003, d=0.4, s=0.4, r=0.3)
    p.env(2, a=0.001, d=0.2, s=0.2, r=0.2)
    poly(p)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.85)
    pattern(p, [(0.6, 0.4, 0), (0.65, 0.4, 0), (0.7, 0.45, 0), (0.75, 0.5, 0), (0.8, 0.55, 0), (0.85, 0.6, 0), (0.95, 0.8, 12), (1.0, 0.9, 12),
                (0.85, 0.7, 7), (0.75, 0.6, 0), (0.7, 0.5, 0), (0.6, 0.45, 0), (0.55, 0.4, 0), (0.5, 0.4, -5), (0.45, 0.6, 0), None])
    velocity(p, 0.5, 0.15)
    p.mod("VELOCITY", "A_WTPOS", 0.4)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.15, [("B_WTPOS", 0.2)])
    echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12, pingpong=True)
    room(p, 0.14)
    grit(p, mode="SOFT", drive=0.35, tone=0.45, amount=0.3, base=0.12)
    p.set("dist.mix", 0.16)
    fsat(p, "SOFT", drive=0.32)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("A phrase with a shape: it climbs, swells into the octave, and falls back with a sigh; the radiant table brightens with each accent",
          "C3–C5", "Film, dark pop finales, ballads", "Held chords", "FOREGROUND",
          "Uses only octaves, a fifth and a fourth, so it fits any key")
    out.append(p)

    # 25 NIGHTSHAPE SEQUENCE: the flagship arp.
    p = A("NIGHTSHAPE SEQUENCE", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.58, wt=0.25, unison=2, detune=0.05, width=0.2)
    p.osc(1, level=0.26, wt=0.2, octave=-1)
    p.sub(0.15, "SINE", filtered=False)
    p.insert(1, "FOLD", after=True, amount=0.25, mix=0.3)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=1700, res=0.3, keytrack=0.5, env=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.filter2("HP12", hz=120)
    p.feedback(amount=0.08, drive=0.5, tone=0.6)
    p.env(1, a=0.001, d=0.28, s=0.35, r=0.12)
    p.env(2, a=0.001, d=0.14, s=0.2, r=0.1)
    p.env(3, a=6.0, d=0.1, s=1.0, r=0.5, acurve=0.35)
    p.mod("ENV3", "A_WTPOS", 0.35)
    p.mod("ENV3", "DIM_MIX", 0.3)
    punch(p, 0.4)
    poly(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=2, gate=0.85, swing=0.06)
    pattern(p, [(1.0, 0.55, 0), (0.45, 0.3, 0), (0.7, 0.45, 12), None, (0.85, 0.6, 0), (0.5, 0.3, 7), (0.6, 0.35, 0), (1.0, 0.9, 12),
                (0.5, 0.3, 0), None, (0.8, 0.5, -12), (0.55, 0.3, 0), (0.95, 0.7, 24), (0.5, 0.35, 12)])
    velocity(p, 0.9, 0.35)
    p.mod("VELOCITY", "A_WTPOS", 0.3)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.2)
    p.mod("MODWHEEL", "FEEDBACK", 0.2)
    p.mod("MODWHEEL", "B_WTPOS", 0.5)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.13, [("B_WTPOS", 0.2), ("INS2_FREQ", 0.01)])
    drift(p, 2, 0.21, [("CUTOFF", 0.05)])
    dimension(p, mix=0.0, size=0.6)
    echo(p, time="3/16", mix=0.1, feedback=0.3, amount=0.12, pingpong=True)
    room(p, 0.1)
    grit(p, mode="TUBE", drive=0.5, tone=0.45, amount=0.35, base=0.25)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.doc("The flagship sequence: a fourteen-step phrase with accents, rests, a tie and leaps of an octave, a fifth and two octaves, on obsidian and grindstone tables that open over six seconds",
          "C3–C5", "Everything NIGHTSHAPE makes", "One held chord is a finished idea; the wheel pushes the loop and the growl",
          "FOREGROUND", "Fourteen steps against sixteen: the phrase lands differently each bar for seven bars before it repeats")
    out.append(p)

    return out
