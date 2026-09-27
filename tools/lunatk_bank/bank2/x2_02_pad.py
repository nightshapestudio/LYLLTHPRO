"""EXPANSION 02 / CORRUPTED CINEMATIC PADS. A warm, centred chord; the
corruption moves independently around it. Each pad pairs one slow evolution
(an envelope over 6–15 s) with one audible wander (0.25–0.45 Hz), and each
uses a different damage mechanism."""

from bank2._common import velocity
from bank2._showcase import dimension, drift, fsat, morph, vintage
from bank2._x2 import N, burn, hall, plate, poly


def P(name, a="ANALOG", b="ANALOG"):
    return N(name, "PAD", a, b)


def bed(p, a=0.7, d=3.0, s=0.9, r=1.8, vel=0.3):
    p.env(1, a=a, d=d, s=s, r=r)
    return poly(p, vel=vel)


def presets():
    out = []

    # 11 CINDER BASILICA (brief: ASH CATHEDRAL, a name already in the bank):
    # warm core; abrasive spectral detail from a DOWNSAMPLE distortion on a
    # parallel band-pass layer that pans independently.
    p = P("CINDER BASILICA", "ANALOG", "NS DUST ORACLE")
    p.osc(0, level=0.6, wt=0.8, unison=3, detune=0.08, width=0.3)
    p.osc(1, level=0.3, wt=0.4, octave=1, unison=4, detune=0.1, width=1.0)
    p.filter("LP24", hz=1700, res=0.12, keytrack=0.35)
    p.filter2("BP", hz=2600, res=0.35, mix=0.35)
    p.set("filter.routing", 1)
    bed(p, a=0.9, r=2.0)
    p.env(3, a=8.0, d=0.1, s=1.0, r=2.0)
    p.mod("ENV3", "DIST_MIX", 0.2)
    p.mod("ENV3", "F2_MIX", 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.33, [("F2_CUTOFF", 0.2), ("B_WTPOS", 0.35)])
    drift(p, 2, 0.071, [("FILTER_PAN", 0.4)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.42)
    burn(p, "DOWNSAMPLE", drive=0.3, base=0.16)
    p.insert(2, "DECIMATE", after=True, amount=0.2, mix=0.2)
    p.doc("A warm chord inside a cinder shell: a band-passed dust layer, sample-rate-crushed, drifting across the stereo field on its own clock",
          "C3–C5", "Film, industrial ballads", "Chords held for bars", "SUPPORT",
          "The abrasion is a parallel band at 2.6 kHz; the chord below it is untouched")
    out.append(p)

    # 12 BEAUTIFUL DECAY: FRACTURE table scanned over 12 s (clean sine to
    # stepped), VINTAGE drift growing, saturation rising.
    p = P("BEAUTIFUL DECAY", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.58, wt=0.85, unison=4, detune=0.09, width=0.5)
    p.osc(1, level=0.32, wt=0.0, octave=1, unison=2, detune=0.06, width=0.8)
    p.filter("LP24", hz=2300, res=0.12, keytrack=0.35)
    fsat(p, "SOFT", drive=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=0.8, r=2.0)
    p.env(4, a=12.0, d=0.1, s=1.0, r=2.0, acurve=0.4)
    p.mod("ENV4", "B_WTPOS", 0.55)
    p.mod("ENV4", "FSAT_DRIVE", 0.3)
    p.mod("ENV4", "A_DETUNE", 0.15)
    vintage(p, 0.3)
    p.set("macro2", 0.5)
    drift(p, 1, 0.29, [("CUTOFF", 0.07), ("A_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.42)
    burn(p, "SOFT", drive=0.35, base=0.16)
    p.doc("Lush at the start; over twelve seconds its upper octave is ground from a pure tone into stepped digital decay while the saturation climbs",
          "C3–C5", "Film, dark pop ballads", "One long chord", "SUPPORT",
          "The harmony never blurs: decay happens to one layer, an octave up")
    out.append(p)

    # 13 BLACK AURORA: luminous distorted top (RADIANT two octaves up through a
    # SHAPER stage), irregular: three wanders at unrelated rates.
    p = P("BLACK AURORA", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.6, wt=0.9, unison=3, detune=0.08, width=0.35)
    p.osc(1, level=0.2, wt=0.6, octave=2, unison=3, detune=0.05, width=1.0)
    p.insert(2, "SINE", after=True, amount=0.3, mix=0.35)
    p.filter("LP24", hz=1300, res=0.15, keytrack=0.35)
    p.route_filter(a=True, b=False)
    p.filter2("HP24", hz=150)
    bed(p, a=1.0, r=2.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("INS2_AMOUNT", 0.2)])
    drift(p, 2, 0.11, [("B_PAN", 0.5)])
    drift(p, 3, 0.053, [("B_LEVEL", 0.08)])
    p.eq(high=-2, high_hz=8000)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.45)
    burn(p, "SINFOLD", drive=0.3, base=0.16)
    p.doc("A black body with an aurora above it: a radiant layer two octaves up, sine-shaped and folded, flickering in brightness, place and level on three clocks",
          "C3–C5", "Film, dark pop, ambient", "Chords", "TEXTURE",
          "The aurora is thin and high; it never thickens the chord")
    out.append(p)

    # 14 MACHINE HEAVEN: a clean layer (A, filter 1) and a damaged layer (B,
    # bitcrush + ring through filter 2) in parallel; a slow crossfade trades them.
    p = P("MACHINE HEAVEN", "ANALOG", "NS HOLLOW BONE")
    p.osc(0, level=0.5, wt=0.8, unison=4, detune=0.08, width=0.6)
    p.osc(1, level=0.4, wt=0.3, unison=3, detune=0.06, width=0.8)
    p.insert(2, "BITCRUSH", after=True, amount=0.5, mix=0.35)
    p.insert(1, "RING", after=True, amount=0.4, freq=0.75, mix=0.2)
    p.filter("LP24", hz=2200, res=0.12, keytrack=0.35)
    p.filter2("HP24", hz=160)
    bed(p, a=0.8, r=2.0)
    p.lfo(1, "SINE", hz=0.047, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "A_LEVEL", 0.2)
    p.motion("LFO1", "B_LEVEL", -0.2)
    drift(p, 2, 0.31, [("B_WTPOS", 0.35), ("CUTOFF", 0.06)])
    p.tone("CUTOFF", 0.15)
    dimension(p, mix=0.3, size=0.6)
    hall(p, mix=0.18, decay=0.4)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("Beautiful synths passing through a factory: a clean analog layer and a crushed, ring-scarred hollow layer trade places over twenty seconds",
          "C3–C5", "Film, industrial pop, ambient", "Long chords", "SUPPORT",
          "The trade is slow and complementary, so the level never swells")
    out.append(p)

    # 15 VELVET CORROSION: granular-feeling grain without a granular engine:
    # a fast smoothed sample-and-hold scrubs the wavetable position and the
    # crush amount in tiny steps (a grain cloud), over a warm body.
    p = P("VELVET CORROSION", "ANALOG", "NS DUST ORACLE")
    p.osc(0, level=0.6, wt=0.8, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.5, octave=1, unison=2, detune=0.05, width=0.9)
    p.insert(2, "DECIMATE", after=True, amount=0.25, mix=0.3)
    p.filter("LP24", hz=2000, res=0.1, keytrack=0.35)
    p.filter2("HP24", hz=150)
    bed(p, a=0.9, r=2.0)
    p.lfo(1, "SAMPLE_HOLD", hz=17.0, mode="FREE", smooth=True)
    p.lfo(2, "SMOOTH_RANDOM", hz=0.27, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "B_WTPOS", 0.18)
    p.motion("LFO1", "INS2_AMOUNT", 0.12)
    p.motion("LFO2", "B_WTPOS", 0.3)
    p.motion("LFO2", "CUTOFF", 0.06)
    p.chorus(mode="SUBTLE", mix=0.2, rate=0.3, depth=0.3, width=0.7)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.4)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Velvet with corrosion in the weave: a 17 Hz smoothed random scrubs a wavetable and a decimator in tiny grains, like a granular cloud, built from oscillators",
          "C3–C5", "Film, dark pop, ambient", "Chords", "SUPPORT",
          "There is no granular engine; the grain is table scrubbing, so it stays in tune")
    out.append(p)

    # 16 DEAD CONSTELLATION: controlled inharmonic partials from the SHIFT
    # insert (a few Hz off-harmonic) on one layer and RING at a non-integer
    # ratio on another, each drifting at its own rate; chord stays clear.
    p = P("DEAD CONSTELLATION", "GLASS", "NS HOLLOW BONE")
    p.osc(0, level=0.55, wt=0.5, unison=3, detune=0.06, width=0.6)
    p.osc(1, level=0.3, wt=0.6, octave=1, unison=3, detune=0.05, width=1.0)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.54, mix=0.15)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.62, mix=0.12)
    p.filter("LP24", hz=2600, res=0.12, keytrack=0.35)
    p.filter2("HP24", hz=170)
    bed(p, a=1.2, r=2.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.26, [("INS1_FREQ", 0.01), ("A_WTPOS", 0.3)])
    drift(p, 2, 0.083, [("B_PAN", 0.45), ("INS2_FREQ", 0.01)])
    drift(p, 3, 0.041, [("B_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.2, decay=0.45)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Cold stars: a shifted glass layer and a ring-scarred hollow layer, each slightly off the harmonic series and drifting on its own clock",
          "C3–C5", "Film, sci-fi-leaning scores, ambient", "Open voicings", "TEXTURE",
          "Inharmonic detail is held under 15% so the chord reads clearly")
    out.append(p)

    # 17 THE LAST MACHINE: 15-second evolution: ENV4 (15 s) raises drive,
    # feedback and the growl table, closing slightly; a mid-rate wander on top.
    p = P("THE LAST MACHINE", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.58, wt=0.95, unison=4, detune=0.09, width=0.5)
    p.osc(1, level=0.28, wt=0.0, octave=1, unison=2, detune=0.05, width=0.7)
    p.filter("LP24", hz=2000, res=0.18, keytrack=0.35, drive=0.3)
    p.feedback(amount=0.05, drive=0.5, tone=0.5)
    p.filter2("HP24", hz=150)
    bed(p, a=0.9, r=2.0)
    p.env(4, a=15.0, d=0.1, s=1.0, r=2.0, acurve=0.3)
    p.mod("ENV4", "B_WTPOS", 0.6)
    p.mod("ENV4", "FEEDBACK", 0.2)
    p.mod("ENV4", "DIST_MIX", 0.3)
    p.mod("ENV4", "CUTOFF", -0.08)
    p.set("macro2", 0.5)
    drift(p, 1, 0.3, [("A_WTPOS", 0.3), ("CUTOFF", 0.06)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.42)
    burn(p, "DIODE", drive=0.4, base=0.16)
    p.doc("Rich and warm when struck; over fifteen seconds a grindstone layer, the filter loop and the diode drive all rise: a machine running itself down",
          "C3–C5", "Film, industrial, song endings", "One chord held a long time", "TEXTURE",
          "Short chords never reach the burn; that is by design")
    out.append(p)

    # 18 SILICON GHOSTS: warm fundamentals; digital-feeling harmonics from the
    # QUANTIZE warp on B, driven by a sample-and-hold whose rate is itself
    # modulated (unpredictable but deliberate).
    p = P("SILICON GHOSTS", "ANALOG", "DIGITAL")
    p.osc(0, level=0.6, wt=0.75, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.28, wt=0.4, octave=1, unison=2, detune=0.06, width=0.9, warp="QUANTIZE", warp_amt=0.15)
    p.filter("LP24", hz=2200, res=0.12, keytrack=0.35)
    p.filter2("HP24", hz=160)
    bed(p, a=0.8, r=2.0)
    p.lfo(1, "SAMPLE_HOLD", hz=2.5, mode="FREE", smooth=True)
    p.lfo(2, "SMOOTH_RANDOM", hz=0.19, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "B_WARP", 0.3)
    p.mod("LFO2", "LFO1_RATE", 0.4)
    p.motion("LFO2", "B_WTPOS", 0.35)
    p.motion("LFO2", "CUTOFF", 0.07)
    vintage(p, 0.2)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.4)
    burn(p, "BITCRUSH", drive=0.25, base=0.16)
    p.motion("LFO2", "CUTOFF", 0.1)
    p.doc("Warm tones haunted by digital ghosts: a quantized upper layer that steps and settles, its pace itself drifting",
          "C3–C5", "Dark pop, electronica, film", "Chords", "TEXTURE",
          "The stepping speeds up and slows down on its own; MOTION 0 lays the ghosts to rest")
    out.append(p)

    # 19 HOLLOW EMPIRE: depth from resonance, not reverb: a keytracked negative
    # comb (hollow) and a phaser filter in parallel, their resonances sweeping
    # apart; the room is small.
    p = P("HOLLOW EMPIRE", "ANALOG", "ORGAN")
    p.osc(0, level=0.6, wt=0.9, unison=3, detune=0.08, width=0.5)
    p.osc(1, level=0.3, wt=0.5, octave=-1)
    p.filter("COMB_NEG", hz=500, res=0.5, keytrack=1.0, mix=0.45)
    p.filter2("PHASER", hz=1200, res=0.4, mix=0.45)
    p.set("filter.routing", 1)
    bed(p, a=1.0, r=2.0)
    p.set("macro2", 0.5)
    drift(p, 1, 0.28, [("F2_CUTOFF", 0.3), ("RES", 0.08)])
    drift(p, 2, 0.067, [("CUTOFF", 0.1)])
    p.eq(low=-4, low_hz=180)
    p.tone("F2_CUTOFF", 0.2)
    plate(p, mix=0.12, decay=0.35)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("An empire with nobody in it: a hollow comb and a phaser in parallel, their resonances sweeping apart to suggest depth without a big reverb",
          "C3–C5", "Film, industrial, dark ambient", "Chords held for bars", "TEXTURE",
          "The reverb is a small plate; the depth is in the resonances")
    out.append(p)

    # 20 COLLAPSE INTO LIGHT: flagship pad: dark to bloom over 10 s. ENV3 opens
    # the MORPH filter from low-pass toward notch, scans RADIANT, widens, and
    # lifts the fold; grit persists throughout.
    p = P("COLLAPSE INTO LIGHT", "NS OBSIDIAN", "NS RADIANT")
    p.osc(0, level=0.58, wt=0.2, unison=4, detune=0.09, width=0.3)
    p.osc(1, level=0.3, wt=0.0, octave=1, unison=5, detune=0.1, width=0.3)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.25)
    p.filter("MORPH", hz=900, res=0.2, keytrack=0.35)
    morph(p, 0.0)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP24", hz=140)
    bed(p, a=1.2, d=4.0, s=0.95, r=2.5)
    p.env(3, a=10.0, d=0.1, s=1.0, r=2.5, acurve=0.35)
    p.mod("ENV3", "B_WTPOS", 0.75)
    p.mod("ENV3", "CUTOFF", 0.3)
    p.mod("ENV3", "MORPH", 0.25)
    p.mod("ENV3", "B_WIDTH", 0.7)
    p.mod("ENV3", "A_WIDTH", 0.4)
    p.mod("ENV3", "DIM_MIX", 0.35)
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.3)
    vintage(p, 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.31, [("A_WTPOS", 0.3), ("CUTOFF", 0.06)])
    drift(p, 2, 0.089, [("B_PAN", 0.2)])
    dimension(p, mix=0.0, size=0.8)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.2, decay=0.48, size=0.85)
    burn(p, "TUBE", drive=0.4, base=0.18)
    p.doc("The flagship pad: oppressive, narrow and folded when struck, then over ten seconds the morph filter opens, the radiant layer blooms and the image goes enormous",
          "C3–C5", "Film, dark pop finales, builds", "Hold the chord; let it arrive", "FOREGROUND",
          "The grit never leaves; the light arrives through it. Mod wheel adds fold")
    out.append(p)

    return out
