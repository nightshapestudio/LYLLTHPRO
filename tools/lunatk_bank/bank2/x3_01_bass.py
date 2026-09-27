"""ADD-ON 03 / RAZOR BASSLINES. Fast-line basses for four-on-the-floor:
a centred unfiltered sub, a serrated mid layer, short envelopes, and a mod
wheel that turns each one from verse bass into chorus monster."""

from bank2._common import velocity
from bank2._showcase import drift, fsat, ladder, punch, vintage
from bank2._x3 import N3, burn, dc_guard, mono, sub, tight, wheel


def B(name, a="ANALOG", b="BASIC"):
    return N3(name, "BASS", a, b)


def dry(p, amount=0.14):
    p.delay(time="1/16", mix=0.0, feedback=0.2, lowcut=0.8, highcut=0.45, width=0.2)
    return p.space(reverb=0, delay=amount)


def presets():
    out = []

    # 01 RAZORBLADE: serrated mids from a sync-sweep table and a fold; a TRIG
    # random nudges the table per note so repeats differ; wheel opens the
    # table, the fold and a resonant snarl, never the sub.
    p = B("RAZORBLADE", "SYNC_SWEEP", "ANALOG")
    p.osc(0, level=0.58, wt=0.35)
    p.osc(1, level=0.3, wt=1.0, fine=5)
    sub(p, 0.6)
    p.insert(1, "FOLD", amount=0.2, mix=0.5)
    p.filter("LP24", hz=900, res=0.2, keytrack=0.45, env=0.45)
    fsat(p, "HARD", drive=0.4)
    tight(p, d=0.3, s=0.7)
    p.env(2, a=0.001, d=0.1, s=0.3, r=0.06)
    punch(p, 0.5)
    mono(p, glide=0.0, legato=False)
    velocity(p, 0.55, 0.25)
    p.lfo(1, "SMOOTH_RANDOM", hz=2.2, mode="TRIG")
    p.set("macro2", 0.35)
    p.motion("LFO1", "A_WTPOS", 0.25)
    p.motion("LFO1", "CUTOFF", 0.05)
    wheel(p, ("A_WTPOS", 0.45), ("INS1_AMOUNT", 0.4), ("RES", 0.25), ("CUTOFF", 0.2), ("DIST_MIX", 0.3))
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "HARD", drive=0.45, base=0.25)
    dc_guard(p)
    p.doc("A serrated line bass for eighths and sixteenths: sync edges and a fold over a rock-solid sine; each repeat lands a little differently",
          "E0–E2", "Industrial pop, EBM, dark dance", "Fast eighth and sixteenth lines", "FOREGROUND",
          "Wheel: the sync opens, the fold digs in and a resonant snarl rises, and the sub never moves")
    out.append(p)

    # 02 TEETH ON STEEL: attack spike from ENV3 into RING + FM warp; metal
    # body from the CATHEDRAL METAL table filtered low; round sine underneath.
    p = B("TEETH ON STEEL", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.58, wt=0.9, warp="FM", warp_amt=0.0)
    p.osc(1, level=0.3, wt=0.35)
    sub(p, 0.6)
    p.insert(2, "RING", after=True, amount=0.4, freq=0.75, mix=0.0)
    p.filter("LP24", hz=850, res=0.22, keytrack=0.45, env=0.35)
    fsat(p, "DIODE", drive=0.4)
    tight(p, d=0.35, s=0.75)
    p.env(3, a=0.0005, d=0.04, s=0.0, r=0.03)
    p.mod("ENV3", "A_WARP", 0.5)
    p.mod("ENV3", "INS2_AMOUNT", 0.4)
    p.set("ins2.mix", 0.25)
    mono(p, glide=0.0, legato=False)
    velocity(p, 0.55, 0.22)
    p.set("macro2", 0.35)
    drift(p, 1, 0.6, [("B_WTPOS", 0.35)])
    wheel(p, ("B_WTPOS", 0.4), ("B_LEVEL", 0.2), ("RES", 0.2), ("DIST_MIX", 0.35), ("ENV2_DECAY", -0.3))
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "TUBE", drive=0.5, base=0.25)
    dc_guard(p)
    p.doc("Teeth on every note (a 40 ms FM-and-ring spike) over a metal-cored saw and a round sine; distortion builds harmonics, not fuzz",
          "E0–E2", "Industrial pop, alt-rock electronics", "Syncopated riffs", "FOREGROUND",
          "Wheel: more metal, more resonance, more drive, and a shorter, more violent filter snap")
    out.append(p)

    # 03 IRON TREADMILL (brief: BLACK CONVEYOR, a name already in the bank):
    # constant eighths: a SONG performer ticks the ladder so the line moves
    # without the player; wheel adds an octave layer and rhythmic upper motion.
    p = B("IRON TREADMILL", "PWM", "ANALOG")
    p.osc(0, level=0.6, wt=0.3)
    p.osc(1, level=0.0, wt=1.0, octave=1)
    sub(p, 0.6)
    p.filter("LADDER", hz=750, res=0.3, keytrack=0.45, env=0.35)
    ladder(p, bass_loss=0.2)
    tight(p, d=0.3, s=0.75)
    mono(p, glide=0.0, legato=False)
    velocity(p, 0.55, 0.22)
    p.performer(1, {0: [(0.5, "DECAY"), (0.0, "HOLD"), (0.3, "DECAY"), (0.1, "HOLD")] * 4}, mode="SONG", rate="1/16")
    p.set("macro2", 0.4)
    p.mod("PERF1", "CUTOFF", 0.08, aux="MACRO2")
    drift(p, 1, 0.35, [("A_WTPOS", 0.3)])
    wheel(p, ("B_LEVEL", 0.35), ("DIST_MIX", 0.3))
    p.mod("PERF1", "B_WTPOS", 0.5, aux="MODWHEEL")
    p.tone("CUTOFF", 0.16)
    fsat(p, "SOFT", drive=0.4)
    dry(p)
    burn(p, "DIODE", drive=0.4, base=0.22)
    dc_guard(p)
    p.doc("A relentless eighth-note bass: a pulse-wave ladder with a sixteenth tick in its filter that keeps long runs alive",
          "E0–E2", "Dark dance, industrial pop, techno-rock", "Straight eighths under a four-on-the-floor", "FOREGROUND",
          "Wheel: an octave saw joins and its brightness starts moving in sixteenths")
    out.append(p)

    # 04 KNIFE MOTOR: compressed centre (MULTIBAND) + razor upper mids; the
    # motor is harmonic beating (B 9 cents sharp) plus a fast smooth S&H on
    # the fold. Wheel tears the mids apart.
    p = B("KNIFE MOTOR", "ANALOG", "ANALOG")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.32, wt=1.0, fine=9)
    sub(p, 0.55)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.4)
    p.filter("BP", hz=1300, res=0.3, keytrack=0.5, mix=0.4)
    tight(p, d=0.4, s=0.8)
    mono(p)
    velocity(p, 0.85, 0.35)
    p.lfo(1, "SAMPLE_HOLD", hz=9.0, mode="FREE", smooth=True)
    p.set("macro2", 0.35)
    p.motion("LFO1", "INS1_AMOUNT", 0.15)
    wheel(p, ("INS1_AMOUNT", 0.45), ("B_FINE", 0.1), ("FILTER_MIX", 0.4), ("DIST_MIX", 0.35))
    p.mod("LFO1", "INS1_AMOUNT", 0.25, aux="MODWHEEL")
    fsat(p, "SOFT", drive=0.45)
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "HARD", drive=0.45, base=0.22)
    dc_guard(p)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.25, curve=0.4)
    p.doc("A saturated, dense centre with a razor spinning in the mids: two saws beating nine cents apart, a folder flickering at nine hertz",
          "E0–E2", "Industrial, EBM, dark dance", "Held notes and eighths", "FOREGROUND",
          "Wheel: the beating widens, the band-pass steps forward and the fold nearly tears; sub untouched")
    out.append(p)

    # 05 SHOCK COLLAR: short; velocity raises harmonics (FOLD, cutoff), not
    # level; wheel adds a resonant bite + a compressed ZEROSQUARE layer.
    p = B("SHOCK COLLAR", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.25, wt=0.3)
    sub(p, 0.6)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.filter("LP24", hz=750, res=0.2, keytrack=0.45, env=0.5)
    tight(p, d=0.22, s=0.45, r=0.05)
    p.env(2, a=0.001, d=0.08, s=0.15, r=0.04)
    punch(p, 0.3)
    mono(p, glide=0.0, legato=False)
    p.set("velSens", 0.3)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.45, curve=0.5)
    p.mod("VELOCITY", "CUTOFF", 0.25)
    p.set("macro2", 0.3)
    drift(p, 1, 0.7, [("B_WTPOS", 0.3)])
    wheel(p, ("RES", 0.3), ("B_LEVEL", 0.25), ("B_WTPOS", 0.4), ("DIST_MIX", 0.4), trim=-0.06)
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "ZEROSQUARE", drive=0.35, base=0.2)
    dc_guard(p)
    p.doc("A short, nasty hook bass: an instant punched strike, a dense short body, and harder playing folds it rather than turning it up",
          "E0–E2", "Industrial pop, electro-punk", "Punchy bass hooks", "FOREGROUND",
          "Wheel: a resonant bite and a scarred-pulse layer through zero-square drive make it feel electrically charged")
    out.append(p)

    # 06 CUTTHROAT: mid-forward for small speakers: rectified octave + a
    # 700 Hz-1.5 kHz band carrying the note; modest sub.
    p = B("CUTTHROAT", "NS OBSIDIAN", "BASIC")
    p.osc(0, level=0.6, wt=0.45)
    p.osc(1, level=0.2, wt=0.0, octave=1)
    sub(p, 0.4)
    p.insert(1, "RECTIFY", amount=0.35, mix=0.35)
    p.filter("LP24", hz=1300, res=0.2, keytrack=0.5, env=0.3)
    fsat(p, "SOFT", drive=0.4)
    tight(p, d=0.4, s=0.8)
    mono(p)
    velocity(p, 0.55, 0.22)
    p.set("macro2", 0.35)
    drift(p, 1, 0.5, [("A_WTPOS", 0.3)])
    p.eq(mid=3.0, mid_hz=900, q=0.4)
    wheel(p, ("A_WTPOS", 0.45), ("FSAT_DRIVE", 0.4), ("DIST_MIX", 0.45), ("INS1_AMOUNT", 0.3))
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "DIODE", drive=0.45, base=0.2)
    dc_guard(p)
    p.doc("A bass that survives a phone speaker: a rectified octave and a 900 Hz lift carry the pitch; the real sub is modest",
          "E0–E2", "Industrial pop, alt-dance", "Any line; it reads anywhere", "FOREGROUND",
          "Wheel: from controlled and punchy to snarling diode-and-obsidian distortion")
    out.append(p)

    # 07 CHROME ARTERY (brief: STEEL VEIN, too close to STEEL VEINS): metal
    # layer from a keytracked comb that moves slowly on held notes (ENV4)
    # and snaps on short ones (ENV3); wheel widens metal above the bass.
    p = B("CHROME ARTERY", "ANALOG", "NS HOLLOW BONE")
    p.osc(0, level=0.58, wt=0.9)
    p.osc(1, level=0.3, wt=0.5)
    sub(p, 0.6)
    p.insert(2, "COMB", after=True, amount=0.45, freq=0.75, mix=0.2)
    p.filter("LP24", hz=900, res=0.22, keytrack=0.45, env=0.3)
    tight(p, d=0.4, s=0.85)
    p.env(3, a=0.001, d=0.08, s=0.0, r=0.04)
    p.env(4, a=1.5, d=0.1, s=1.0, r=0.1)
    p.mod("ENV3", "INS2_FREQ", 0.02)
    p.mod("ENV4", "B_WTPOS", 0.4)
    mono(p)
    velocity(p, 0.55, 0.22)
    p.set("macro2", 0.35)
    drift(p, 1, 0.45, [("INS2_FREQ", 0.008), ("B_WTPOS", 0.2)])
    wheel(p, ("INS2_AMOUNT", 0.5), ("FSAT_DRIVE", 0.4), ("B_WTPOS", 0.45), ("RES", 0.2), ("DIST_MIX", 0.3))
    p.mod("MODWHEEL", "B_WIDTH", 0.5)
    p.set("b.unison", 2)
    p.set("b.width", 0.0)
    fsat(p, "SOFT", drive=0.35)
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "TUBE", drive=0.45, base=0.22)
    dc_guard(p)
    p.doc("A thick clean low note wrapped in a chrome artery: a comb that flicks on short notes and slowly slides through held ones",
          "E0–E2", "Industrial pop, dark dance, electro-rock", "Short notes and held roots", "FOREGROUND",
          "Wheel: more metal, more resonance, and the metal layer (only) spreads in stereo")
    out.append(p)

    # 08 DEADLY SIMPLE: one saw + sub; the size is transient shaping (PUNCH),
    # filter saturation, a single compressor; wheel = drive and fold.
    p = B("DEADLY SIMPLE", "ANALOG", "BASIC")
    p.osc(0, level=0.62, wt=1.0)
    p.osc(1, on=False)
    sub(p, 0.6)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.filter("LP24", hz=700, res=0.18, keytrack=0.45, env=0.35)
    fsat(p, "LIGHT", drive=0.45)
    tight(p, d=0.4, s=0.8)
    p.env(2, a=0.001, d=0.14, s=0.3, r=0.06)
    punch(p, 0.55)
    mono(p)
    velocity(p, 0.55, 0.22)
    p.set("macro2", 0.25)
    drift(p, 1, 0.5, [("CUTOFF", 0.04)])
    wheel(p, ("INS1_AMOUNT", 0.45), ("FSAT_DRIVE", 0.4), ("CUTOFF", 0.25), ("DIST_MIX", 0.45))
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "TUBE", drive=0.5, base=0.22)
    dc_guard(p)
    p.doc("One saw and a sine, made enormous by a punched attack and filter saturation: sleek at rest",
          "E0–E2", "Dark pop, industrial pop, anything", "Anything", "FOREGROUND",
          "Wheel: sleek to filthy: the filter opens into a fold and the tube stage overdrives")
    out.append(p)

    # 09 CRUSH LINE: root/octave patterns; accents hit harder through
    # velocity-driven transient (ENV2 depth) and fold, not level.
    p = B("CRUSH LINE", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.58, wt=0.95)
    p.osc(1, level=0.0, wt=0.4, octave=1)
    sub(p, 0.6)
    p.insert(2, "BITCRUSH", after=True, amount=0.45, mix=0.2)
    p.filter("LP24", hz=800, res=0.22, keytrack=0.5, env=0.3)
    tight(p, d=0.35, s=0.75)
    p.env(2, a=0.001, d=0.12, s=0.3, r=0.06)
    mono(p, glide=0.0, legato=False)
    p.set("velSens", 0.3)
    p.mod("VELOCITY", "CUTOFF", 0.3, curve=0.4)
    p.mod("VELOCITY", "B_LEVEL", 0.2, curve=0.5)
    p.set("macro2", 0.35)
    drift(p, 1, 0.55, [("B_WTPOS", 0.3)])
    wheel(p, ("B_LEVEL", 0.35), ("B_WTPOS", 0.45), ("DIST_MIX", 0.35))
    fsat(p, "HARD", drive=0.35)
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "HARD", drive=0.45, base=0.22)
    dc_guard(p)
    p.doc("A root-octave bass: accents open the filter and bring in a crushed grindstone octave, so they hit harder without jumping in level",
          "E0–E2", "Industrial pop, EBM, electro-rock", "Root-octave eighths", "FOREGROUND",
          "Wheel: the octave layer comes all the way in, harder: the chorus version of the same line")
    out.append(p)

    # 10 BODY MACHINE: flagship: sub rock-solid; mid motion from two tables
    # (OBSIDIAN + GRINDSTONE) moving against each other; PUNCH tuned to not
    # click; velocity, wheel, pressure all transform.
    p = B("BODY MACHINE", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=0.35)
    p.osc(1, level=0.3, wt=0.2, octave=1)
    sub(p, 0.62)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.35)
    p.filter("LADDER", hz=800, res=0.28, keytrack=0.45, env=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.feedback(amount=0.08, drive=0.6, tone=0.45)
    tight(p, d=0.4, s=0.8)
    p.env(2, a=0.001, d=0.18, s=0.35, r=0.07)
    punch(p, 0.4)
    mono(p)
    velocity(p, 0.55, 0.25)
    p.mod("VELOCITY", "A_WTPOS", 0.25)
    p.lfo(1, "TRIANGLE", hz=0.41, mode="FREE")
    p.lfo(2, "SMOOTH_RANDOM", hz=0.73, mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "A_WTPOS", 0.3)
    p.motion("LFO2", "B_WTPOS", 0.3)
    wheel(p, ("B_WTPOS", 0.5), ("INS1_AMOUNT", 0.4), ("FEEDBACK", 0.2), ("RES", 0.15), ("DIST_MIX", 0.35))
    p.mod("PRESSURE", "FSAT_DRIVE", 0.25)
    vintage(p, 0.1)
    p.tone("CUTOFF", 0.16)
    dry(p)
    burn(p, "TUBE", drive=0.5, base=0.25)
    dc_guard(p)
    p.doc("The flagship industrial-pop bass: obsidian and grindstone tables moving against each other through a diode ladder loop, a punch that fights the kick without clicking",
          "E0–E2", "Industrial pop, dark dance, electro-rock", "Verse bass that becomes the chorus", "FOREGROUND",
          "Wheel: the grindstone opens, the fold and the loop dig in: a filthy chorus monster, still on pitch")
    out.append(p)

    return out
