"""EXPANSION 02 / CINEMATIC INDUSTRIAL DRONES. A pitched centre that never
leaves; above it, harmonic structures on independent slow clocks and
saturation that changes form. Lows are mono; width lives above 200 Hz."""

from bank2._showcase import drift, fsat, morph, vintage
from bank2._x2 import N, burn, dc_guard, hall, poly


def D(name, a="ANALOG", b="BASIC"):
    return N(name, "DRONE", a, b)


def swell(p, a=2.0, r=3.0):
    p.env(1, a=a, d=1.0, s=1.0, r=r)
    return poly(p, voices=6, vel=0.2)


def presets():
    out = []

    # 51 REACTOR CHAMBER: two filter-loop resonances beating a few cents
    # apart (A/B fine), a growl layer rising under a slow random; mono floor.
    p = D("REACTOR CHAMBER", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.3, wt=0.3, octave=1, fine=7, unison=3, detune=0.08, width=0.35)
    p.filter("LP24", hz=700, res=0.4, keytrack=0.4, drive=0.4)
    p.feedback(amount=0.18, drive=0.6, tone=0.5)
    p.filter2("HP12", hz=45)
    swell(p)
    p.set("macro2", 0.5)
    drift(p, 1, 0.23, [("B_WTPOS", 0.4), ("CUTOFF", 0.08)])
    drift(p, 2, 0.061, [("FB_TONE", 0.2)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.45, size=0.8, width=0.25)
    burn(p, "TUBE", drive=0.45, base=0.2)
    dc_guard(p)
    p.doc("A reactor breathing: a resonant filter loop around a saw, a grindstone layer seven cents sharp beating against it, pressure rising and falling",
          "D1–D3", "Film, industrial, trailers", "Single notes or fifths held for bars", "TEXTURE",
          "Below 150 Hz it is one mono saw; the menace is above")
    out.append(p)

    # 52 THE ABYSS ENGINE: machinery via four independent modulators on four
    # dimensions (table, ring freq, cutoff, pan), none tempo-locked.
    p = D("THE ABYSS ENGINE", "PWM", "NS SCAR PULSE")
    p.osc(0, level=0.55, wt=0.4)
    p.osc(1, level=0.3, wt=0.3, octave=1, unison=2, detune=0.05, width=0.35)
    p.insert(2, "RING", after=True, amount=0.4, freq=0.55, mix=0.18)
    p.filter("LADDER", hz=900, res=0.3, keytrack=0.4)
    p.filter2("HP12", hz=45)
    swell(p)
    p.set("macro2", 0.5)
    drift(p, 1, 0.29, [("B_WTPOS", 0.4)], shape="TRIANGLE")
    drift(p, 2, 0.13, [("INS2_FREQ", 0.03)])
    drift(p, 3, 0.071, [("CUTOFF", 0.12)])
    drift(p, 4, 0.043, [("B_PAN", 0.4)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.42, size=0.8, width=0.25)
    burn(p, "DIODE", drive=0.4, base=0.18)
    dc_guard(p)
    p.doc("Enormous machinery without sound effects: a scarred pulse, a ring stage and a ladder filter, each turned by its own unsynchronized modulator",
          "D1–D3", "Film, dark ambient, industrial", "Single held notes", "TEXTURE",
          "Four rates that never line up: it does not loop within a minute")
    out.append(p)

    # 53 BLACK ATMOSPHERE: spectral density rising (DUST ORACLE scanned by a
    # 10 s envelope), a subtle minor-second ghost via SHIFT, LINFOLD drive.
    p = D("BLACK ATMOSPHERE", "NS DUST ORACLE", "ANALOG")
    p.osc(0, level=0.55, wt=0.1)
    p.osc(1, level=0.3, wt=0.8, octave=-1)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.53, mix=0.12)
    p.filter("LP24", hz=1400, res=0.2, keytrack=0.4)
    p.filter2("HP12", hz=45)
    swell(p, a=3.0)
    p.env(3, a=10.0, d=0.1, s=1.0, r=3.0)
    p.mod("ENV3", "A_WTPOS", 0.7)
    p.mod("ENV3", "DIST_MIX", 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.27, [("A_WTPOS", 0.25), ("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.5, size=0.85, width=0.25)
    burn(p, "LINFOLD", drive=0.35, base=0.16)
    p.doc("An atmosphere thickening: a dust-oracle spectrum growing denser over ten seconds, a faint shifted ghost, a folded edge",
          "D1–D3", "Film transitions, dark ambient", "Held notes across sections", "TEXTURE",
          "The dissonance is a small shifted copy; it unsettles without clashing")
    out.append(p)

    # 54 CORRUPTED ORBIT: rotation from B_PAN and FILTER_PAN sines 90° apart,
    # beating from unison, saturation growing via ENV4 (ZEROSQUARE).
    p = D("CORRUPTED ORBIT", "ANALOG", "ANALOG")
    p.osc(0, level=0.55, wt=0.9)
    p.osc(1, level=0.3, wt=0.9, octave=1, unison=3, detune=0.12, width=0.3)
    p.filter("LP24", hz=1100, res=0.3, keytrack=0.4, drive=0.3)
    p.filter2("HP12", hz=45)
    swell(p)
    p.env(4, a=12.0, d=0.1, s=1.0, r=3.0)
    p.mod("ENV4", "DIST_MIX", 0.3)
    p.mod("ENV4", "RES", 0.12)
    p.lfo(1, "SINE", hz=0.19, mode="FREE")
    p.lfo(2, "SINE", hz=0.19, mode="FREE", phase=0.25)
    p.set("macro2", 0.5)
    p.motion("LFO1", "B_PAN", 0.2)
    p.motion("LFO2", "CUTOFF", 0.12)
    p.motion("LFO2", "FILTER_PAN", 0.3)
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.42, width=0.25)
    burn(p, "ZEROSQUARE", drive=0.3, base=0.16)
    p.doc("A harmonic structure in orbit: the upper layer circles the stereo field while the filter follows a quarter-turn behind, the saturation hardening over twelve seconds",
          "D1–D3", "Film, industrial, dark techno breakdowns", "Held notes", "TEXTURE",
          "The circle is two sines a quarter-cycle apart, so it rotates rather than wobbles")
    out.append(p)

    # 55 INDUSTRIAL ECLIPSE: a dense stacked fundamental (octave stack) and an
    # abrasive top (bitcrush + BITS fsat), a dramatic change every ~8 s from a
    # slow square on the crush (smoothed).
    p = D("INDUSTRIAL ECLIPSE", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.55, wt=1.0, stack="OCTAVE")
    p.osc(1, level=0.28, wt=0.4, octave=1)
    p.insert(2, "BITCRUSH", after=True, amount=0.45, mix=0.25)
    p.filter("LP24", hz=1300, res=0.2, keytrack=0.4)
    fsat(p, "BITS", drive=0.3, mix=0.3)
    p.filter2("HP12", hz=45)
    swell(p)
    p.lfo(1, "SQUARE", hz=0.063, mode="FREE", smooth=True)
    p.set("macro2", 0.5)
    p.motion("LFO1", "INS2_AMOUNT", 0.3)
    p.motion("LFO1", "B_WTPOS", 0.4)
    drift(p, 2, 0.31, [("CUTOFF", 0.08)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.42)
    burn(p, "HARD", drive=0.35, base=0.16)
    p.doc("An eclipse every eight seconds: an octave-stacked saw holds the centre while the crushed fracture layer swings between two states",
          "D1–D3", "Film, industrial", "Held notes", "TEXTURE",
          "The swing is a smoothed square: dramatic, but it glides rather than jumps")
    out.append(p)

    # 56 STATIC UNIVERSE: electrical texture from DIGITAL noise gated by an
    # S&H whose rate drifts; slow table transformation; controlled pan.
    p = D("STATIC UNIVERSE", "NS HOLLOW BONE", "GLASS")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.25, wt=0.6, octave=1, unison=2, detune=0.05, width=0.35)
    p.noise(0.045, type="DIGITAL", color=0.6, keytrack=True, pan=0.0)
    p.filter("LP24", hz=2000, res=0.15, keytrack=0.4)
    p.filter2("HP12", hz=45)
    swell(p, a=3.0, r=2.5)
    p.lfo(1, "SAMPLE_HOLD", hz=3.5, mode="FREE", smooth=True)
    p.lfo(2, "SMOOTH_RANDOM", hz=0.11, mode="FREE")
    p.set("macro2", 0.5)
    p.mod("LFO1", "NOISE_LEVEL", 0.06, aux="LFO2")
    p.motion("LFO1", "NOISE_PAN", 0.5)
    p.motion("LFO2", "A_WTPOS", 0.45)
    drift(p, 3, 0.26, [("B_WTPOS", 0.3)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.18, decay=0.42, size=0.8, width=0.25)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("A vast, hollow tone with electricity crackling across it (digital static that jumps between speakers) while the harmonics slowly transform",
          "D1–D3", "Film, sci-fi-leaning scores, ambient", "Held notes", "TEXTURE",
          "The static is sparse and gated by a slow random; it never becomes hiss")
    out.append(p)

    # 57 MACHINE BURIAL: layers that deteriorate: ENV4 (14 s) lowers B's
    # level into a decimated, sagging version of itself while A holds the tone.
    p = D("MACHINE BURIAL", "ORGAN", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=0.6)
    p.osc(1, level=0.32, wt=0.2, octave=1)
    p.insert(2, "DECIMATE", after=True, amount=0.0, mix=0.5)
    p.filter("LP24", hz=1500, res=0.18, keytrack=0.4)
    p.filter2("HP12", hz=45)
    swell(p)
    p.env(4, a=14.0, d=0.1, s=1.0, r=3.0, acurve=0.3)
    p.mod("ENV4", "INS2_AMOUNT", 0.5)
    p.mod("ENV4", "B_WTPOS", 0.6)
    p.mod("ENV4", "B_FINE", -0.08)
    p.mod("ENV4", "CUTOFF", -0.08)
    p.set("macro2", 0.5)
    drift(p, 1, 0.24, [("A_WTPOS", 0.3), ("CUTOFF", 0.06)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.16, decay=0.45, width=0.25)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("A machine being buried alive: an organ tone holds the centre while its obsidian partner decays (decimated, sagging, darkening) over fourteen seconds",
          "D1–D3", "Film, industrial, song endings", "One long note", "TEXTURE",
          "The organ layer is untouched: the tonal centre stays recognisable to the end")
    out.append(p)

    # 58 THE PRESSURE BELOW: low register; the upper harmonics cycle through
    # saturation forms: a TRIG-free triangle moves the MORPH filter (LP-notch-
    # HP) after a SHAPER stage, so the saturation's audible band keeps changing.
    p = D("THE PRESSURE BELOW", "ANALOG", "NS TENDON")
    p.osc(0, level=0.55, wt=0.95)
    p.osc(1, level=0.3, wt=0.3, octave=1)
    p.filter("MORPH", hz=900, res=0.25, keytrack=0.4)
    morph(p, 0.1)
    fsat(p, "SHAPER", drive=0.4, mix=0.7)
    p.filter2("HP12", hz=45)
    swell(p)
    p.lfo(1, "TRIANGLE", hz=0.07, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "MORPH", 0.3)
    p.motion("LFO1", "B_WTPOS", 0.4)
    drift(p, 2, 0.28, [("CUTOFF", 0.1), ("FSAT_DRIVE", 0.12)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.45)
    burn(p, "DIODE", drive=0.35, base=0.16)
    p.doc("Massive pressure from below: a saw and a tendon layer shaped by a saturation stage whose audible band travels from low-pass through notch toward high-pass",
          "D1–D3", "Film, industrial, trailers", "Low held notes", "TEXTURE",
          "The low end stays mono and steady; only the saturated band moves")
    out.append(p)

    # 59 SIGNAL FROM NOTHING: a quiet foundation and resonances that emerge:
    # a comb whose mix ENV3 raises over 8 s, its tuning drifting; VINTAGE.
    p = D("SIGNAL FROM NOTHING", "BASIC", "NS THROAT")
    p.osc(0, level=0.55, wt=0.2)
    p.osc(1, level=0.28, wt=0.2, octave=1)
    p.filter("LP24", hz=1600, res=0.15, keytrack=0.4)
    p.filter2("COMB_POS", hz=600, res=0.5, keytrack=1.0, mix=0.0)
    swell(p, a=3.0)
    p.env(3, a=8.0, d=0.1, s=1.0, r=3.0)
    p.mod("ENV3", "F2_MIX", 0.4)
    vintage(p, 0.4)
    p.set("macro2", 0.5)
    drift(p, 1, 0.26, [("B_WTPOS", 0.45), ("F2_CUTOFF", 0.05)])
    drift(p, 2, 0.09, [("CUTOFF", 0.1)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.2, decay=0.5, size=0.85, width=0.25)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Out of near silence, a signal: a bare tone with a whispering vowel layer, and over eight seconds a comb resonance emerges and wanders",
          "D1–D3", "Film, horror, ambient", "Held notes", "TEXTURE",
          "Starts almost empty; give it time")
    out.append(p)

    # 60 END OF EVERYTHING: flagship drone: stacked fifths centre, three
    # upper structures on unrelated clocks, a 15 s destruction envelope over
    # feedback, fold and diode drive, huge but mono in the lows.
    p = D("END OF EVERYTHING", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=0.2, stack="OCTAVE_FIFTH")
    p.osc(1, level=0.28, wt=0.2, octave=1, unison=4, detune=0.1, width=0.0)
    p.noise(0.03, type="BROWN", color=0.3, keytrack=False)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.3)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=1200, res=0.28, keytrack=0.4)
    fsat(p, "DIODE", drive=0.35)
    p.feedback(amount=0.06, drive=0.5, tone=0.5)
    p.filter2("HP12", hz=45)
    swell(p, a=3.0, r=2.5)
    p.env(4, a=15.0, d=0.1, s=1.0, r=3.0, acurve=0.3)
    p.mod("ENV4", "FEEDBACK", 0.2)
    p.mod("ENV4", "INS1_AMOUNT", 0.35)
    p.mod("ENV4", "B_WTPOS", 0.5)
    p.mod("ENV4", "DIST_MIX", 0.25)
    p.mod("MODWHEEL", "RES", 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.27, [("A_WTPOS", 0.3), ("CUTOFF", 0.07)])
    drift(p, 2, 0.089, [("INS2_FREQ", 0.01)])
    drift(p, 3, 0.037, [("FB_TONE", 0.2)])
    p.tone("CUTOFF", 0.15)
    hall(p, mix=0.14, decay=0.42, size=0.8, width=0.25)
    burn(p, "TUBE", drive=0.45, base=0.18)
    dc_guard(p)
    p.doc("The flagship drone: an octave-and-fifth obsidian centre, a wide grindstone layer, three clocks and a fifteen-second destruction of loop, fold and drive",
          "D1–D3", "Film, trailers, the last minute of a record", "One note; let it end the world", "FOREGROUND",
          "Mono under 150 Hz for all of it; the wheel pushes the resonance")
    out.append(p)

    return out
