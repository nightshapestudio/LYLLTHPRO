"""ADD-ON 03 / METALLIC SYNTH GUITARS. The function of a rhythm guitar
(dense mids, a pick-hard attack, controlled sustain, width only up top),
not an imitation. Low end is high-passed so power chords never pile up
under the bass. Cabinet voicing is EQ; LUNATK has no cab model."""

from bank2._common import velocity, vibrato
from bank2._showcase import drift, fsat, punch, vintage
from bank2._x3 import N3, burn, mono, poly, room, wheel


def G(name, a="ANALOG", b="ANALOG"):
    return N3(name, "KEYS", a, b)


def rig(p, hp=140, bump=2.0, hz=1600, roll=-7):
    """Guitar-rig voicing: high-pass, presence bump, cab-style roll-off."""
    p.filter2("HP12", hz=hp)
    return p.eq(low=-1.5, low_hz=110, mid=bump, mid_hz=hz, q=0.45, high=roll, high_hz=5500)


def pick(p, level=0.15):
    p.noise(0.0, type="WHITE", color=0.8, keytrack=True)
    p.env(3, a=0.0005, d=0.012, s=0.0, r=0.01)
    return p.mod("ENV3", "NOISE_LEVEL", level)


def presets():
    out = []

    # 21 STEEL WALL: two saws + comb-string on A, octave stack for power,
    # upper layer B wide only; HARD dist.
    p = G("STEEL WALL", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.0)
    p.osc(1, level=0.28, wt=0.4, octave=1, unison=3, detune=0.08, width=0.4)
    pick(p)
    p.insert(1, "COMB", after=False, amount=0.4, freq=0.5, mix=0.25)
    p.filter("LP24", hz=2800, res=0.2, keytrack=0.5, env=0.3)
    rig(p)
    p.env(1, a=0.001, d=0.9, s=0.7, r=0.15)
    p.env(2, a=0.001, d=0.2, s=0.4, r=0.15)
    punch(p, 0.45)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("INS1_FREQ", 0.004)])
    wheel(p, ("DIST_MIX", 0.35), ("DIST_DRIVE", 0.25), ("B_WIDTH", 0.3), ("B_LEVEL", 0.15), ("EQ_MID", 0.25))
    room(p)
    burn(p, "HARD", drive=0.55, base=0.45)
    p.doc("A synth that does a rhythm guitar's job: picked comb-string saws, a wide obsidian octave, hard drive and a cab-style voice. Power chords land huge",
          "C2–C5", "Industrial rock, electro-rock", "Power chords and chugs", "FOREGROUND",
          "High-passed at 140 Hz so the bass keeps its space. Wheel: harder drive, wider top, more upper-mid bite")
    out.append(p)

    # 22 CHROME GUITAR: detuned saws with RANDOM unison (not supersaw),
    # metallic comb at +octave, complex saturation (fsat SHAPER + TUBE).
    p = G("CHROME GUITAR", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.52, wt=1.0, unison=4, detune=0.07, width=0.35, unimode="RANDOM")
    p.osc(1, level=0.22, wt=0.5)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.15)
    p.filter("LP24", hz=3000, res=0.2, keytrack=0.5, env=0.25)
    fsat(p, "SHAPER", drive=0.35, mix=0.6)
    rig(p, hz=1900)
    p.env(1, a=0.001, d=0.8, s=0.7, r=0.15)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.25)
    p.set("macro2", 0.4)
    drift(p, 1, 0.35, [("B_WTPOS", 0.4), ("CUTOFF", 0.06)])
    wheel(p, ("FSAT_DRIVE", 0.45), ("DIST_MIX", 0.4), ("INS2_AMOUNT", 0.35), ("RES", 0.2), ("A_WIDTH", 0.4))
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.35)
    p.doc("Polished chrome rhythm: random-spread saws (not a supersaw), a metal comb an octave up, a shaper stage and a tube",
          "C2–C5", "Industrial pop, synth rock", "Rhythmic chord patterns", "FOREGROUND",
          "Wheel: from controlled rhythm tone to a screaming, damaged wall")
    out.append(p)

    # 23 SAW BLADE WALL: tight attack via PUNCH + short ENV2; sustain held
    # up by filter feedback so it doesn't mush.
    p = G("SAW BLADE WALL", "ANALOG", "ANALOG")
    p.osc(0, level=0.52, wt=1.0, unison=3, detune=0.06, width=0.3)
    p.osc(1, level=0.3, wt=1.0, octave=1, fine=-6, unison=2, detune=0.05, width=0.8)
    p.filter("LP24", hz=2600, res=0.25, keytrack=0.5, env=0.35)
    p.feedback(amount=0.08, drive=0.6, tone=0.6)
    rig(p)
    p.env(1, a=0.001, d=0.7, s=0.75, r=0.15)
    p.env(2, a=0.001, d=0.12, s=0.35, r=0.15)
    punch(p, 0.55)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.43, [("FB_TONE", 0.2), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_DRIVE", 0.35), ("RES", 0.25), ("FEEDBACK", 0.15), ("DIST_MIX", 0.35))
    room(p)
    burn(p, "HARD", drive=0.5, base=0.4)
    p.doc("Layered saw blades through expensive processing: a tight punched attack, an octave pair six cents apart, a filter loop holding the sustain up",
          "C2–C5", "Industrial rock, trailers", "Chord hits and sustained walls", "FOREGROUND",
          "Wheel: drive and resonant upper harmonics rise; the loop starts to sing")
    out.append(p)

    # 24 MACHINE RIFF: short notes punch, long notes grow (ENV4 into table
    # + feedback); poly-capable with 4 voices for power intervals.
    p = G("MACHINE RIFF", "ANALOG", "NS TENDON")
    p.osc(0, level=0.56, wt=1.0)
    p.osc(1, level=0.3, wt=0.1)
    pick(p, 0.18)
    p.filter("LADDER", hz=2000, res=0.28, keytrack=0.5, env=0.4)
    rig(p, hp=120)
    p.env(1, a=0.001, d=0.6, s=0.75, r=0.12)
    p.env(4, a=1.2, d=0.1, s=1.0, r=0.2)
    p.mod("ENV4", "B_WTPOS", 0.55)
    p.mod("ENV4", "FEEDBACK", 0.12)
    p.feedback(amount=0.04, drive=0.6, tone=0.55)
    punch(p, 0.55)
    poly(p, voices=4, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.39, [("B_WTPOS", 0.2), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_MIX", 0.4), ("DIST_DRIVE", 0.12), ("B_WTPOS", 0.4), trim=-0.05)
    p.lfo(2, "SMOOTH_RANDOM", hz=3.0, mode="FREE")
    p.mod("LFO2", "B_WTPOS", 0.15, aux="MODWHEEL")
    room(p)
    burn(p, "LINFOLD", drive=0.45, base=0.35)
    p.doc("For riffs: short notes punch with a pick; long notes grow as the tendon table folds and the loop rises. Single notes or power intervals",
          "C2–C4", "Industrial rock, EBM, electro-rock", "Riffs and two-note power intervals", "FOREGROUND",
          "Four voices: enough for fifths and octaves. Wheel: a savage fold stage and a shiver of instability")
    out.append(p)

    # 25 METAL HALO: dense heavy centre (A narrow), shimmering moving upper
    # harmonics (B two octaves up, metal table, wide + pan drift).
    p = G("METAL HALO", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.1)
    p.osc(1, level=0.18, wt=0.6, octave=2, unison=3, detune=0.06, width=0.8)
    p.filter("LP24", hz=2600, res=0.2, keytrack=0.5, env=0.3)
    p.route_filter(a=True, b=False)
    rig(p, bump=1.5)
    p.env(1, a=0.002, d=1.0, s=0.8, r=0.3)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.25)
    p.set("macro2", 0.45)
    drift(p, 1, 0.33, [("B_WTPOS", 0.45), ("B_PAN", 0.3)])
    wheel(p, ("B_WIDTH", 0.2), ("B_LEVEL", 0.15), ("DIST_MIX", 0.35), ("B_WTPOS", 0.3))
    fsat(p, "SOFT", drive=0.35)
    room(p, mix=0.1, decay=0.3)
    burn(p, "TUBE", drive=0.5, base=0.35)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("Rhythm-guitar weight in the centre, a halo of moving metal two octaves up at the edges: a lush, heavy chord synth",
          "C2–C5", "Industrial pop, synth rock, cinematic rock", "Sustained power chords", "FOREGROUND",
          "Wheel: the halo widens and brightens and the centre drives harder")
    out.append(p)

    # 26 FERROUS: metal without bells: RING at a low non-integer ratio
    # (inharmonic grit), filtered below 3 kHz, DIODE fsat.
    p = G("FERROUS", "ANALOG", "PWM")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.3, wt=0.4, fine=-5)
    p.insert(1, "RING", after=True, amount=0.4, freq=0.56, mix=0.18)
    p.filter("LP24", hz=2400, res=0.28, keytrack=0.5, env=0.3)
    fsat(p, "DIODE", drive=0.4)
    rig(p, hz=1300, roll=-9)
    p.env(1, a=0.001, d=0.8, s=0.7, r=0.15)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.25)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("INS1_FREQ", 0.01), ("CUTOFF", 0.08)])
    wheel(p, ("RES", 0.3), ("FSAT_DRIVE", 0.35), ("INS1_AMOUNT", 0.35), ("DIST_MIX", 0.35))
    room(p)
    burn(p, "HARD", drive=0.5, base=0.35)
    p.doc("Metal as part of the instrument, not a bell: a low off-ratio ring through a diode filter stage, voiced dark",
          "C2–C5", "Industrial, metal-electronic", "Chords and riffs", "FOREGROUND",
          "Wheel: resonance and drive climb until the ring's harmonics scream")
    out.append(p)

    # 27 BURNING SAW: an expensive oscillator first (5-voice EXP unison,
    # warm ladder), then saturation that moves (S&H 1/8 on drive).
    p = G("BURNING SAW", "ANALOG", "ANALOG")
    p.osc(0, level=0.52, wt=1.0, unison=5, detune=0.07, width=0.35, unimode="EXP")
    p.osc(1, level=0.25, wt=0.95, octave=-1)
    p.filter("LADDER", hz=2200, res=0.25, keytrack=0.5, env=0.35)
    rig(p)
    p.env(1, a=0.001, d=0.6, s=0.7, r=0.15)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE", smooth=True)
    p.set("macro2", 0.4)
    p.motion("LFO1", "DIST_DRIVE", 0.15)
    p.motion("LFO1", "RES", 0.06)
    wheel(p, ("DIST_DRIVE", 0.35), ("DIST_MIX", 0.35), ("RES", 0.2), ("CUTOFF", 0.2), trim=0.05)
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.35)
    p.doc("An expensive saw before anything touches it, then a tube stage whose heat shifts every eighth: made for driving eighth-note chords",
          "C2–C5", "Industrial pop, synth rock", "Eighth-note chord patterns", "FOREGROUND",
          "Wheel: a screaming climax version of the same chord")
    out.append(p)

    # 28 INDUSTRIAL POWER CHORD: root/fifth/octave voicings: steep HP at
    # 180 Hz, stack FIFTH on B for reinforcement on the wheel.
    p = G("INDUSTRIAL POWER CHORD", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.15)
    p.osc(1, level=0.0, wt=0.4, octave=1, stack="OCTAVE", unison=2, detune=0.05, width=0.8)
    pick(p, 0.15)
    p.filter("LP24", hz=2600, res=0.22, keytrack=0.5, env=0.3)
    rig(p, hp=180)
    p.env(1, a=0.001, d=0.8, s=0.75, r=0.15)
    punch(p, 0.5)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("CUTOFF", 0.08)])
    wheel(p, ("B_LEVEL", 0.35), ("DIST_MIX", 0.35), ("DIST_DRIVE", 0.25))
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "HARD", drive=0.55, base=0.4)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("Built for root-fifth-octave voicings: high-passed at 180 Hz so stacked notes never mud up, a picked, punched front",
          "C2–C5", "Industrial rock, electro-rock", "Power chords", "FOREGROUND",
          "Wheel: a grindstone octave-stack reinforces every chord and the drive climbs")
    out.append(p)

    # 29 HOT TUBES (brief: BLACK AMPLIFIER, a name already in the bank):
    # an overdriven amp that responds to touch: velocity -> drive and fold.
    p = G("HOT TUBES", "ANALOG", "ANALOG")
    p.osc(0, level=0.56, wt=0.95)
    p.osc(1, level=0.28, wt=0.4, octave=-1)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.4)
    p.filter("LP24", hz=2400, res=0.2, keytrack=0.5, env=0.3, drive=0.3)
    rig(p)
    p.env(1, a=0.001, d=0.8, s=0.75, r=0.15)
    poly(p, voices=10, vel=0.35)
    p.mod("VELOCITY", "DIST_MIX", 0.4, curve=0.4)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.35, curve=0.5)
    p.mod("VELOCITY", "CUTOFF", 0.2)
    p.set("macro2", 0.4)
    drift(p, 1, 0.39, [("A_WTPOS", 0.3), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_DRIVE", 0.45), ("DRIVE", 0.35), ("INS1_AMOUNT", 0.25))
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.2)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("An overdriven instrument that answers the hands: soft playing is dense and controlled, hard playing breaks up and bites",
          "C2–C5", "Industrial rock, alt-rock", "Dynamic chord playing", "FOREGROUND",
          "Wheel: the virtual amp pushed far past its limit; pitch stays clear")
    out.append(p)

    # 30 GOD GUITAR: flagship: picked comb-string pair + obsidian wide
    # octave; ENV2 short so low-velocity playing sounds palm-muted (filter
    # closes fast), high velocity opens it; diode + tube; wheel = wall.
    p = G("GOD GUITAR", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.52, wt=1.0, unison=2, detune=0.05, width=0.0)
    p.osc(1, level=0.26, wt=0.3, octave=1, unison=3, detune=0.07, width=0.4)
    pick(p, 0.18)
    p.insert(1, "COMB", after=False, amount=0.45, freq=0.5, mix=0.25)
    p.filter("LADDER", hz=1600, res=0.25, keytrack=0.5, env=0.55)
    fsat(p, "DIODE", drive=0.4)
    p.feedback(amount=0.05, drive=0.6, tone=0.6)
    rig(p)
    p.env(1, a=0.001, d=0.9, s=0.75, r=0.15)
    p.env(2, a=0.001, d=0.15, s=0.2, r=0.12)
    punch(p, 0.5)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.0)
    p.mod("VELOCITY", "ENV2_DECAY", 0.4, curve=0.4)
    p.mod("VELOCITY", "CUTOFF", 0.25)
    p.mod("PRESSURE", "PITCH", 0.008)
    vibrato(p, hz=5.6, depth=0.012)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("INS1_FREQ", 0.004)])
    wheel(p, ("DIST_MIX", 0.35), ("DIST_DRIVE", 0.3), ("FEEDBACK", 0.15), ("B_WIDTH", 0.1), ("B_WTPOS", 0.4), ("EQ_MID", 0.2))
    room(p)
    burn(p, "TUBE", drive=0.55, base=0.45)
    p.doc("The ultimate synth-guitar: picked comb strings and a wide obsidian octave through a diode ladder loop and a tube amp; soft playing closes up like palm-muting",
          "C2–C5", "Electronic rock, industrial, trailers", "Power chords, chugs, screaming single notes; pressure bends", "FOREGROUND",
          "Wheel: rhythm tone into a screaming wall of harmonic distortion")
    out.append(p)

    return out
