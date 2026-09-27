"""EXPANSION 02 / HYBRID SYNTH-GUITAR TEXTURES. No samples and no cabinet
model exist in LUNATK: guitar character comes from a pick transient (noise +
PUNCH), a comb-filter string, amp-style drive, and EQ voicing that stands
in for a cabinet (a 1.5–2 kHz bump, a roll-off above 5 kHz)."""

from bank2._common import echo, velocity, vibrato
from bank2._showcase import drift, fsat, punch, vintage
from bank2._x2 import N, burn, mono, plate, poly


def cab(p, bump=2.5, hz=1700, roll=-8):
    """Cabinet voicing through the EQ: presence bump, top roll-off."""
    return p.eq(low=-1.5, low_hz=90, mid=bump, mid_hz=hz, q=0.45, high=roll, high_hz=5500)


def pick(p, level=0.2):
    """A pick transient: a 12 ms burst of bright noise."""
    p.noise(0.0, type="WHITE", color=0.8, keytrack=True)
    p.env(3, a=0.0005, d=0.012, s=0.0, r=0.01)
    return p.mod("ENV3", "NOISE_LEVEL", level)


def presets():
    out = []

    # 61 STEEL VEINS (lead): comb string + pick + HARD drive + cab voicing;
    # the comb resonance is swept by a slow random (the "amp" breathing).
    p = N("STEEL VEINS", "LEAD", "ANALOG", "NS SERPENT")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.25, wt=0.3, fine=6)
    pick(p, 0.2)
    p.insert(1, "COMB", after=False, amount=0.5, freq=0.5, mix=0.35)
    p.filter("LP24", hz=3000, res=0.2, keytrack=0.6, env=0.3)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.001, d=0.8, s=0.8, r=0.2)
    p.env(2, a=0.001, d=0.25, s=0.4, r=0.2)
    punch(p, 0.5)
    mono(p, glide=0.02)
    velocity(p, 0.8, 0.35)
    vibrato(p, hz=5.6, depth=0.01, delay=0.3, rise=0.3)
    p.set("macro2", 0.45)
    drift(p, 1, 0.43, [("INS1_FREQ", 0.006), ("B_WTPOS", 0.35)])
    cab(p)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.6, base=0.45)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("Heavily processed guitar made of synthesis: a picked comb string, amp-hard drive, cabinet-style voicing, the string resonance breathing",
          "C3–C5", "Industrial rock, synth metal", "Riffs and single-note lines", "FOREGROUND",
          "Layers with real guitars: it sits in the same 1.7 kHz pocket")
    out.append(p)

    # 62 BLACK AMPLIFIER (lead): amp-like compression (FET-ish SINGLE comp
    # before DIST via fx order), tube drive, cab voicing; thick, not fizzy.
    p = N("BLACK AMPLIFIER", "LEAD", "ANALOG", "ANALOG")
    p.osc(0, level=0.58, wt=0.95)
    p.osc(1, level=0.3, wt=0.4, octave=-1)
    p.filter("LP24", hz=2400, res=0.18, keytrack=0.6, drive=0.35)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.002, d=0.5, s=0.9, r=0.2)
    mono(p)
    velocity(p, 0.55, 0.25)
    vibrato(p)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("CUTOFF", 0.1), ("A_WTPOS", 0.25)])
    cab(p, bump=2.0, hz=1500)
    plate(p, 0.06)
    burn(p, "TUBE", drive=0.55, base=0.5)
    p.motion("LFO1", "B_WTPOS", 0.45)
    p.motion("LFO1", "CUTOFF", 0.1)
    p.lfo(2, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO2", "CUTOFF", 0.2)
    p.motion("LFO2", "A_WTPOS", 0.4)
    p.doc("A synth through a black amp: a driven ladder into a tube stage, voiced like a closed-back cabinet; thick for layering with guitars",
          "C2–C5", "Industrial rock, alt-rock, synth rock", "Doubling guitar parts", "FOREGROUND",
          "Velocity sets how hard the amp is hit, as with a pick")
    out.append(p)

    # 63 FRACTURED STRINGS (keys, poly): bowed/struck string-like complexity
    # via COMB inserts on both oscillators at slightly different tunings,
    # unstable overtones from a RING that drifts.
    p = N("FRACTURED STRINGS", "KEYS", "ANALOG", "ANALOG")
    p.osc(0, level=0.5, wt=0.95)
    p.osc(1, level=0.4, wt=0.9, fine=-7)
    p.insert(1, "COMB", after=False, amount=0.5, freq=0.5, mix=0.35)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.75, mix=0.1)
    p.filter("LP24", hz=2800, res=0.18, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=1.0, s=0.4, r=0.4)
    p.env(2, a=0.001, d=0.3, s=0.25, r=0.3)
    punch(p, 0.4)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.8, 0.35)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("INS2_FREQ", 0.01), ("CUTOFF", 0.08)])
    cab(p, bump=1.5, hz=2000, roll=-5)
    plate(p, 0.08)
    burn(p, "HARD", drive=0.45, base=0.3)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.motion("LFO1", "B_WTPOS", 0.4)
    p.lfo(2, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO2", "CUTOFF", 0.2)
    p.motion("LFO2", "A_WTPOS", 0.4)
    p.doc("Aggressive poly strings: two comb-string oscillators seven cents apart, a drifting ring adding unstable overtones, all driven hard",
          "C2–C5", "Industrial rock, synth metal, film", "Chords and double stops", "FOREGROUND",
          "The detune makes the strings rub; the ring is kept at 10%")
    out.append(p)

    # 64 INDUSTRIAL CHORDS (keys): chord stabs: fast ladder envelope, dense
    # saturation (DIODE fsat + TUBE), low mids controlled by EQ, evolving
    # distortion via S&H on dist drive.
    p = N("INDUSTRIAL CHORDS", "KEYS", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.06, width=0.12)
    p.osc(1, level=0.3, wt=0.4)
    p.filter("LADDER", hz=1400, res=0.25, keytrack=0.5, env=0.5)
    fsat(p, "DIODE", drive=0.45)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.5, s=0.35, r=0.2)
    p.env(2, a=0.001, d=0.15, s=0.25, r=0.15)
    punch(p, 0.5)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.55, 0.28)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE", smooth=True)
    p.set("macro2", 0.4)
    p.motion("LFO1", "DIST_DRIVE", 0.15)
    p.motion("LFO1", "B_WTPOS", 0.3)
    p.eq(low=-2, low_hz=220, mid=1.5, mid_hz=1600, high=-4, high_hz=6000)
    plate(p, 0.06)
    burn(p, "TUBE", drive=0.5, base=0.4)
    p.doc("Huge aggressive stabs: a punched diode-saturated ladder chord whose drive shifts on every eighth; low mids tidied so chords stay clear",
          "C3–C5", "Industrial rock, EBM, trailers", "Stabs and short chords", "FOREGROUND",
          "Tuned for power chords and triads; four-note clusters get dense fast")
    out.append(p)

    # 65 BURNING METAL (lead): metallic resonance (CATHEDRAL METAL table +
    # comb) + amp saturation + expressive pitch (pressure bend, wide vibrato).
    p = N("BURNING METAL", "LEAD", "NS CATHEDRAL METAL", "ANALOG")
    p.osc(0, level=0.52, wt=0.5)
    p.osc(1, level=0.35, wt=1.0)
    pick(p, 0.15)
    p.insert(1, "COMB", after=True, amount=0.4, freq=0.75, mix=0.15)
    p.filter("LP24", hz=2800, res=0.22, keytrack=0.6, env=0.25)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.001, d=0.6, s=0.85, r=0.2)
    punch(p, 0.4)
    mono(p, glide=0.04)
    velocity(p, 0.55, 0.22)
    vibrato(p, hz=5.8, depth=0.018)
    p.mod("PRESSURE", "PITCH", 0.01)
    p.mod("PRESSURE", "A_WTPOS", 0.3)
    p.set("macro2", 0.45)
    drift(p, 1, 0.39, [("A_WTPOS", 0.35)])
    cab(p)
    plate(p, 0.08)
    burn(p, "DIODE", drive=0.55, base=0.4)
    p.doc("Burning metal on an amp: cathedral-metal partials and a picked saw through diode drive; pressure bends up like a string and heats the metal",
          "C3–C5", "Industrial rock, synth metal", "Lead lines; bend with pressure", "FOREGROUND",
          "Pressure bends up about a quarter-tone; the wheel adds a wide vibrato")
    out.append(p)

    # 66 MACHINE GUITAR (lead): guitar-like articulation: pick, fast decay to
    # sustain, legato slides (glide always off, legato on), fret-like
    # vibrato late; not an imitation.
    p = N("MACHINE GUITAR", "LEAD", "ANALOG", "PWM")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.25, wt=0.3, octave=1)
    pick(p, 0.22)
    p.insert(1, "COMB", after=False, amount=0.45, freq=0.5, mix=0.25)
    p.filter("LP24", hz=2600, res=0.2, keytrack=0.6, env=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.35, s=0.7, r=0.15)
    p.env(2, a=0.001, d=0.2, s=0.35, r=0.15)
    punch(p, 0.5)
    mono(p, glide=0.06)
    velocity(p, 0.8, 0.35)
    vibrato(p, hz=5.4, depth=0.014, delay=0.5, rise=0.4)
    p.set("macro2", 0.4)
    drift(p, 1, 0.45, [("INS1_FREQ", 0.004), ("B_WTPOS", 0.3)])
    cab(p)
    echo(p, time="1/8", mix=0.08, feedback=0.2, amount=0.1)
    burn(p, "HARD", drive=0.55, base=0.45)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("A synth that phrases like a guitar: a pick on every note, fast decay to a driven sustain, legato slides and late vibrato",
          "C3–C5", "Synth rock, industrial, solos", "Legato lines; overlap to slide", "FOREGROUND",
          "Not an imitation: the body is a comb string on a saw, and it says so")
    out.append(p)

    # 67 DISTORTION BLOOM (keys, poly): tight distorted transient (ENV3 drive
    # spike) expanding into a complex sustain (ENV4 opens B + width over 1.5 s).
    p = N("DISTORTION BLOOM", "KEYS", "ANALOG", "NS DUST ORACLE")
    p.osc(0, level=0.55, wt=0.95)
    p.osc(1, level=0.0, wt=0.3, octave=1, unison=4, detune=0.1, width=0.0)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.5, env=0.3)
    fsat(p, "HARD", drive=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=1.2, s=0.6, r=0.5)
    p.env(3, a=0.0005, d=0.08, s=0.0, r=0.05)
    p.env(4, a=1.5, d=0.1, s=1.0, r=0.5)
    p.mod("ENV3", "FSAT_DRIVE", 0.4)
    p.mod("ENV4", "B_LEVEL", 0.3)
    p.mod("ENV4", "B_WIDTH", 0.9)
    p.mod("ENV4", "B_WTPOS", 0.5)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.55, 0.25)
    p.set("macro2", 0.4)
    drift(p, 1, 0.35, [("B_WTPOS", 0.25), ("CUTOFF", 0.06)])
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.45, base=0.3)
    p.doc("A tight, distorted chord hit that blooms: over a second and a half a wide dust-oracle layer rises out of the saturated saw",
          "C3–C5", "Industrial pop, synth rock, film", "Chords held a beat or more", "FOREGROUND",
          "Stabs stay tight and mono; held chords open up")
    out.append(p)

    # 68 CHROME FEEDBACK (lead): amp feedback: a filter loop tuned by
    # keytrack that swells in over 1.5 s (ENV4 -> FEEDBACK), pushing toward
    # the octave harmonic (B an octave up rising), wide vibrato on the wheel.
    p = N("CHROME FEEDBACK", "LEAD", "ANALOG", "BASIC")
    p.osc(0, level=0.58, wt=1.0)
    p.osc(1, level=0.0, wt=0.0, octave=1)
    p.filter("LP24", hz=1800, res=0.35, keytrack=0.9)
    p.feedback(amount=0.08, drive=0.6, tone=0.65)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.002, d=0.6, s=0.9, r=0.25)
    p.env(4, a=1.5, d=0.1, s=1.0, r=0.3, acurve=0.3)
    p.mod("ENV4", "FEEDBACK", 0.18)
    p.mod("ENV4", "B_LEVEL", 0.35)
    p.mod("ENV4", "A_LEVEL", -0.15)
    mono(p, glide=0.05)
    velocity(p, 0.55, 0.22)
    vibrato(p, hz=5.2, depth=0.02, delay=0.6, rise=0.5)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("FB_TONE", 0.25), ("CUTOFF", 0.08)])
    cab(p, bump=2.0, hz=2000)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.5, base=0.4)
    p.doc("Controlled amp feedback: hold a note and the loop swells in, the tone tipping toward its octave the way a guitar does in front of a stack",
          "C3–C5", "Industrial rock, film, noise pop", "Long held notes", "FOREGROUND",
          "The feedback is keytracked and capped, so it blooms on the note's octave, not a random squeal")
    out.append(p)

    # 69 DEAD AMPLIFIER (keys): unstable colour from a slow random on the
    # fsat mix + ASYM warp; aggressive compression (MULTIBAND) glues it.
    p = N("DEAD AMPLIFIER", "KEYS", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.55, wt=0.9, warp="ASYM_NEG", warp_amt=0.15)
    p.osc(1, level=0.3, wt=0.4)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.5, env=0.35)
    fsat(p, "RECTIFY", drive=0.35, mix=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.9, s=0.45, r=0.3)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.8, 0.35)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("FSAT_DRIVE", 0.15), ("A_WARP", 0.2), ("B_WTPOS", 0.3)])
    p.comp(mode="MULTIBAND", threshold=0.5, ratio=0.45, attack=0.25, release=0.3, gain=0.15, depth=0.6, mix=1.0)
    cab(p, bump=2.0, hz=1300, roll=-9)
    plate(p, 0.06)
    burn(p, "HARD", drive=0.45, base=0.35)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("A dying amp, professionally recorded: a rectifying filter stage and a bent saw whose colour won't stay put, squeezed by band compression",
          "C2–C5", "Alt-rock, noise pop, industrial", "Chords and riffs", "FOREGROUND",
          "Damaged-sounding, but the compressor keeps it controlled")
    out.append(p)

    # 70 ELECTRIC TITAN (keys, poly): flagship hybrid: chords and lines;
    # pick + comb-string + growl layer, diode ladder, amp comp -> drive,
    # cab voicing; wheel opens growl, pressure feedback.
    p = N("ELECTRIC TITAN", "KEYS", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.52, wt=1.0, unison=2, detune=0.05, width=0.35)
    p.osc(1, level=0.28, wt=0.3)
    pick(p, 0.18)
    p.insert(1, "COMB", after=False, amount=0.45, freq=0.5, mix=0.25)
    p.filter("LADDER", hz=2000, res=0.25, keytrack=0.5, env=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.feedback(amount=0.05, drive=0.5, tone=0.55)
    p.filter2("HP12", hz=140)
    p.env(1, a=0.001, d=0.9, s=0.6, r=0.3)
    p.env(2, a=0.001, d=0.25, s=0.35, r=0.25)
    punch(p, 0.45)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.8, 0.35)
    p.mod("MODWHEEL", "B_WTPOS", 0.5)
    p.mod("MODWHEEL", "B_LEVEL", 0.15)
    p.mod("PRESSURE", "FEEDBACK", 0.15)
    p.set("macro2", 0.4)
    drift(p, 1, 0.39, [("B_WTPOS", 0.3), ("INS1_FREQ", 0.004)])
    p.comp(mode="SINGLE", threshold=0.6, ratio=0.4, attack=0.25, release=0.3, gain=0.1, depth=0.55, mix=1.0)
    p.order("COMP", "DIST", "EQ")
    cab(p)
    plate(p, 0.08)
    burn(p, "TUBE", drive=0.55, base=0.45)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("The flagship hybrid: picked comb strings and a grindstone layer through a diode ladder, compressed into a tube amp and voiced like a cabinet",
          "C2–C5", "Industrial rock, synth metal, trailers", "Enormous chords and aggressive lines; wheel for growl", "FOREGROUND",
          "It is not a guitar and does not pretend; it lives where the guitars do")
    out.append(p)

    return out
