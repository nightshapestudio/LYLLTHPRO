"""SHOWCASE PADS: the flagship bed sounds. Every one holds a stable, centred
fundamental and does its moving above it: slow envelopes (ENV3/ENV4) that
take ten seconds or more, free-running random wanders at unrelated rates, and
VINTAGE per-note drift, so a held chord keeps changing and never shows its loop.
Lows are high-passed and mono; width comes from the upper layers."""

from lunatk import Preset
from bank2._common import grit, space, velocity
from bank2._showcase import dimension, drift, fsat, morph, vintage


def P(name, a="ANALOG", b="ANALOG"):
    return Preset(name, "PAD", a, b)


def bed(p, a=0.5, d=2.0, s=0.9, r=1.6, vel=0.3, voices=8):
    p.env(1, a=a, d=d, s=s, r=r)
    return p.voice(voices=voices, glide=0.0, vel=vel, bend=2)


def hall(p, mix=0.2, decay=0.4, size=0.7, amount=0.16, damp=0.55, predelay=0.1):
    return space(p, mix, mode="HALL", size=size, decay=decay, damp=damp, predelay=predelay, width=0.95, amount=amount)


def plate(p, mix=0.16, decay=0.4, amount=0.15):
    return space(p, mix, mode="PLATE", size=0.5, decay=decay, damp=0.5, predelay=0.08, width=0.9, amount=amount)


def presets():
    out = []

    # 01 BLACK GLASS: a warm centred core; the damage lives in an upper wide
    # layer whose fold and cutoff wander at two unrelated slow rates.
    p = P("BLACK GLASS", "NS OBSIDIAN", "GLASS")
    p.osc(0, level=0.62, wt=0.85, unison=3, detune=0.08, width=0.25)
    p.osc(1, level=0.34, wt=0.55, octave=1, unison=6, detune=0.14, width=1.0, warp="ASYM_POS", warp_amt=0.2)
    p.insert(1, "FOLD", after=True, amount=0.22, mix=0.3)
    p.filter("LP24", hz=2300, res=0.14, keytrack=0.35, env=0.1)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP24", hz=150)
    bed(p, a=0.7, d=3.0, s=0.9, r=2.0)
    p.env(2, a=1.5, d=4.0, s=0.6, r=1.5)
    vintage(p, 0.25)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.07, [("B_WARP", 0.3), ("INS1_AMOUNT", 0.2)])
    drift(p, 2, 0.113, [("CUTOFF", 0.08), ("B_WTPOS", 0.25)])
    dimension(p, mix=0.35, size=0.6)
    hall(p, mix=0.2, decay=0.42)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.4, base=0.18)
    p.env(4, a=9.0, d=0.1, s=1.0, r=2.0)
    p.mod("ENV4", "A_WTPOS", 0.35)
    p.set("a.unimode", 1)
    p.set("a.wtpos", 0.12)
    p.doc("A warm, dead-steady core under a wide glass layer that folds and frays at two slow, unrelated rates",
          "C3–C5", "Dark pop, industrial ballads, film", "Minor chords held for bars", "SUPPORT",
          "The low end is one centred voice; widen with SPACE, not by stacking. GRIT roughens only the upper layer's edge")
    out.append(p)

    # 02 COLD CATHEDRAL: analog core, a metallic ring layer, and filtered
    # noise and a tritone ring that only arrive as the chord holds (ENV3).
    p = P("COLD CATHEDRAL", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.62, wt=0.75, unison=3, detune=0.1, width=0.3)
    p.osc(1, level=0.28, wt=0.4, octave=1, unison=4, detune=0.1, width=0.9)
    p.noise(0.06, type="METAL", color=0.7, keytrack=True)
    p.insert(1, "RING", after=True, amount=0.5, freq=0.646, mix=0.0)
    p.filter("LP24", hz=1900, res=0.18, keytrack=0.35)
    p.filter2("HP24", hz=160)
    bed(p, a=1.0, d=3.0, s=0.9, r=2.2)
    p.env(3, a=7.0, d=0.1, s=1.0, r=2.0)
    p.mod("ENV3", "NOISE_LEVEL", 0.12)
    p.mod("ENV3", "B_LEVEL", 0.18)
    p.mod("ENV3", "EQ_HIGH", 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.45)
    drift(p, 1, 0.05, [("B_WTPOS", 0.3), ("NOISE_COLOR", 0.2)])
    drift(p, 2, 0.083, [("INS1_FREQ", 0.01)])
    p.eq(low=0, mid=-1.5, mid_hz=450, high=0)
    hall(p, mix=0.24, decay=0.5, size=0.85, predelay=0.16)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.35, base=0.1)
    p.mod("ENV3", "B_WTPOS", 0.55)
    p.phaser(mix=0.15, rate=0.1, depth=0.5, freq=0.55, feedback=0.3)
    p.set("dist.mix", 0.16)
    drift(p, 3, 0.27, [("CUTOFF", 0.07), ("A_WTPOS", 0.25)])
    p.doc("An analog core that grows a cold metal atmosphere as it holds: comb shimmer, metal noise, a distant air",
          "C3–C5", "Film, industrial, dark ambient", "Chords held four bars or more; the cold arrives after five seconds",
          "TEXTURE", "The core stays dry enough to read; the scale comes from predelay, not a longer tail")
    out.append(p)

    # 03 BEAUTIFUL DAMAGE: lush and clean at the attack; ENV3 slowly brings
    # in the bitcrush, the distortion and a detune drift around the edges.
    p = P("BEAUTIFUL DAMAGE", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.6, wt=0.8, unison=5, detune=0.1, width=0.6)
    p.osc(1, level=0.3, wt=0.3, octave=1, unison=3, detune=0.08, width=0.8)
    p.insert(1, "BITCRUSH", after=True, amount=0.45, mix=0.0)
    p.filter("LP24", hz=2600, res=0.1, keytrack=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=0.6, d=3.0, s=0.92, r=1.8)
    p.env(3, a=8.0, d=0.1, s=1.0, r=1.5)
    p.mod("ENV3", "INS1_AMOUNT", 0.25)
    p.mod("ENV3", "B_DETUNE", 0.25)
    p.mod("ENV3", "DIST_MIX", 0.3)
    vintage(p, 0.3)
    p.set("ins1.mix", 0.35)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.09, [("B_FINE", 0.08), ("B_WTPOS", 0.2)])
    p.chorus(mode="WIDE", mix=0.25, rate=0.25, depth=0.4, width=0.7)
    hall(p, mix=0.2, decay=0.4)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.3, base=0.0)
    p.set("b.wtpos", 0.0)
    p.mod("ENV3", "B_WTPOS", 0.6)
    p.set("env3.slope", 0.5)
    p.doc("Lush and whole when struck, then the edges fracture: crush, drive and a wandering detune arrive over eight seconds",
          "C3–C5", "Dark pop, ballads, film", "Long chords; retrigger to start clean again", "SUPPORT",
          "The chord never smears: damage rides the upper octave and the crush mix tops out at a third")
    out.append(p)

    # 04 DEAD AIR: a dry warm centre; breath noise and a folded distant
    # layer panned to the edges; a vocal-shaped hole at 1.5 kHz.
    p = P("DEAD AIR", "NS THROAT", "FORMANT")
    p.osc(0, level=0.62, wt=0.6, pan=0.0)
    p.osc(1, level=0.26, wt=0.5, octave=1, unison=4, detune=0.12, width=1.0, warp="FOLD", warp_amt=0.25)
    p.noise(0.1, type="BREATH", color=0.45, keytrack=True)
    p.filter("LP12", hz=2000, res=0.1, keytrack=0.3)
    fsat(p, "LIGHT", drive=0.3)
    p.filter2("HP24", hz=170)
    bed(p, a=0.9, d=2.0, s=0.9, r=1.8)
    vintage(p, 0.2)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.5)
    drift(p, 1, 0.06, [("B_PAN", 0.35), ("NOISE_LEVEL", 0.08)])
    drift(p, 2, 0.1, [("B_WARP", 0.25)], shape="TRIANGLE")
    p.eq(mid=-3, mid_hz=1500, q=0.35)
    plate(p, mix=0.14, decay=0.35)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.3, base=0.12)
    p.set("a.wtpos", 0.15)
    p.motion("LFO1", "A_WTPOS", 0.2)
    p.doc("An intimate, dry-centred bed breathing at the edges, with distant folded movement and a hole cut for a voice",
          "C3–C5", "Intimate electronic, dark pop verses, film", "Chords under a vocal", "SUPPORT",
          "Already scooped at 1.5 kHz; leave the vocal's EQ alone. MOTION 0 stills the edges")
    out.append(p)

    # 05 NEON FUNERAL: a thick low-mid foundation, and an upper octave layer
    # that ENV3 opens and the fold roughens over the length of the chord.
    p = P("NEON FUNERAL", "PWM", "NS NEON NERVE")
    p.osc(0, level=0.62, wt=0.35, unison=4, detune=0.1, width=0.35)
    p.osc(1, level=0.3, wt=0.1, octave=1, unison=7, detune=0.16, width=1.0)
    p.filter("LP24", hz=1500, res=0.2, keytrack=0.35, drive=0.3)
    p.filter2("HP24", hz=140)
    bed(p, a=0.8, d=3.0, s=0.9, r=2.0)
    p.env(3, a=6.0, d=0.1, s=1.0, r=2.0)
    p.mod("ENV3", "B_WTPOS", 0.55)
    p.mod("ENV3", "CUTOFF", 0.12)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.07, [("B_WTPOS", 0.15), ("B_WIDTH", 0.2)])
    dimension(p, mix=0.4, size=0.7)
    hall(p, mix=0.2, decay=0.45)
    grit(p, mode="DIODE", drive=0.4, tone=0.45, amount=0.4, base=0.15)
    p.set("b.unimode", 2)
    drift(p, 3, 0.31, [("CUTOFF", 0.07), ("A_WTPOS", 0.25)])
    p.doc("A dense pulse-wave foundation under an eerie upper layer that opens into a fold over six seconds",
          "C3–C5", "Dark pop, synth rock, film", "Minor chords; the threat builds while you hold", "SUPPORT",
          "Very wide above 300 Hz and mono below it; in a busy chorus pull SPACE down, not the width")
    out.append(p)

    # 06 MACHINES DREAMING: four modulators at unrelated rates (0.031, 0.047,
    # 0.071 Hz and a 16th-note sample-and-hold held down low) so the timbre
    # never repeats inside twenty seconds; pitch never moves.
    p = P("MACHINES DREAMING", "NS DUST ORACLE", "HARMONIC_SWEEP")
    p.osc(0, level=0.55, wt=0.3, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.4, wt=0.5, unison=4, detune=0.1, width=0.9, warp="MIRROR", warp_amt=0.2)
    p.insert(1, "COMB", after=True, amount=0.35, freq=0.75, mix=0.25)
    p.filter("MORPH", hz=2400, res=0.2, keytrack=0.3)
    morph(p, 0.2)
    p.filter2("HP24", hz=160)
    bed(p, a=1.2, d=3.0, s=0.9, r=2.0)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.55)
    drift(p, 1, 0.13, [("A_WTPOS", 0.35)])
    drift(p, 2, 0.19, [("B_WTPOS", 0.35), ("MORPH", 0.12)])
    drift(p, 3, 0.071, [("INS1_FREQ", 0.04), ("B_WARP", 0.2)])
    p.lfo(4, "SAMPLE_HOLD", sync="1/16", mode="FREE")
    p.motion("LFO4", "INS1_AMOUNT", 0.06)
    dimension(p, mix=0.3, size=0.5)
    hall(p, mix=0.2, decay=0.42)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.15)
    p.tracker(1, "NOTE", [0.2, 0.25, 0.3, 0.38, 0.45, 0.5, 0.55, 0.6, 0.62, 0.66, 0.7, 0.72, 0.75, 0.78, 0.8, 0.82])
    p.mod("TRACK1", "A_WTPOS", 0.25)
    p.doc("Harmonics that never settle: four slow modulators at unrelated rates, a faint digital flicker, a pitch that never moves",
          "C3–C5", "Ambient pop, film, electronica", "Held chords of ten to twenty seconds", "TEXTURE",
          "Nothing loops audibly; MOTION 0 freezes it into a single glassy chord")
    out.append(p)

    # 07 VELVET STATIC: velocity drives the grit, not the level. Soft is
    # lush; hard exposes the rectified edge and the crush on the harmonics.
    p = P("VELVET STATIC", "ANALOG", "NS TENDON")
    p.osc(0, level=0.62, wt=0.9, unison=4, detune=0.09, width=0.5)
    p.osc(1, level=0.28, wt=0.9, octave=1, unison=3, detune=0.1, width=0.8)
    p.noise(0.04, type="CRACKLE", color=0.6, keytrack=False)
    p.insert(1, "RECTIFY", after=True, amount=0.4, mix=0.1)
    p.filter("LP24", hz=2100, res=0.12, keytrack=0.3)
    fsat(p, "SHAPER", drive=0.3, mix=0.6)
    p.filter2("HP24", hz=150)
    bed(p, a=0.5, d=2.5, s=0.9, r=1.6, vel=0.15)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.35)
    p.mod("VELOCITY", "DIST_MIX", 0.35)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.08)
    p.mod("VELOCITY", "CUTOFF", 0.08)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.45)
    drift(p, 1, 0.08, [("INS1_AMOUNT", 0.12), ("CUTOFF", 0.05)])
    p.chorus(mode="SUBTLE", mix=0.3, rate=0.3, depth=0.4, width=0.7)
    hall(p, mix=0.17, decay=0.38)
    grit(p, mode="TUBE", drive=0.4, tone=0.4, amount=0.3, base=0.0)
    p.set("b.wtpos", 0.1)
    p.mod("VELOCITY", "B_WTPOS", 0.5, curve=0.4)
    drift(p, 2, 0.29, [("CUTOFF", 0.06), ("B_WTPOS", 0.3)])
    p.doc("Warm and luxurious played softly; dig in and an electrical edge comes up through the harmonics, not the lows",
          "C3–C5", "Dark pop, R&B-leaning electronic, film", "Velocity is the performance: soft verses, hard choruses",
          "SUPPORT", "The fundamental never distorts; GRIT and velocity only touch the upper partials")
    out.append(p)

    # 08 AFTER THE FIRE: a defined attack (ENV2 filter spit) that falls into
    # a long release where the tail degrades (decimate + drift on release).
    p = P("AFTER THE FIRE", "ANALOG", "FM_BELL")
    p.osc(0, level=0.6, wt=0.7, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.35, octave=1, unison=2, detune=0.06, width=0.8)
    p.insert(1, "DECIMATE", after=True, amount=0.3, mix=0.15)
    p.filter("LP24", hz=1500, res=0.18, keytrack=0.35, env=0.35)
    p.filter2("HP24", hz=150)
    p.env(1, a=0.01, d=2.5, s=0.65, r=3.0)
    p.env(2, a=0.005, d=0.9, s=0.25, r=2.0)
    p.voice(voices=8, glide=0.0, vel=0.35, bend=2)
    p.env(3, a=3.0, d=0.1, s=1.0, r=3.0)
    p.mod("ENV3", "INS1_AMOUNT", 0.3)
    p.mod("VELOCITY", "CUTOFF", 0.1)
    vintage(p, 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.5)
    drift(p, 1, 0.12, [("A_FINE", 0.05), ("B_FINE", 0.07)])
    hall(p, mix=0.26, decay=0.5, size=0.8)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.35, base=0.15)
    p.set("b.warpmode", 6)
    p.set("b.warp", 0.15)
    p.mod("ENV2", "B_WARP", 0.3)
    p.doc("A struck chord with a bell edge that burns down into a long, slowly degrading atmosphere",
          "C3–C5", "Film, ballads, dark ambient", "Chord hits with space after them", "SUPPORT",
          "The attack reads through a band; behind a vocal, play it softly and let the tail do the work")
    out.append(p)

    # 09 ASHEN HALO: dense dark body; a soft glow two octaves up that is
    # never perfect: each note's glow is detuned and filtered differently.
    p = P("ASHEN HALO", "CHOIR", "NS RADIANT")
    p.osc(0, level=0.62, wt=0.35, unison=3, detune=0.1, width=0.4)
    p.osc(1, level=0.2, wt=0.25, octave=2, unison=3, detune=0.05, width=0.9, rand=1.0)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.508, mix=0.2)
    p.filter("LP24", hz=1400, res=0.12, keytrack=0.4)
    p.filter2("HP24", hz=160)
    p.route_filter(a=True, b=False)
    bed(p, a=1.0, d=3.0, s=0.9, r=2.0)
    vintage(p, 0.4)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.45)
    drift(p, 1, 0.09, [("B_LEVEL", 0.08), ("INS2_FREQ", 0.01)])
    drift(p, 2, 0.13, [("B_WTPOS", 0.2)])
    p.eq(high=-2.5, high_hz=7000)
    hall(p, mix=0.22, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.35, amount=0.3, base=0.1)
    p.set("b.wtpos", 0.55)
    p.set("dist.mix", 0.16)
    p.doc("A shadowy choir body with a faint glow floating two octaves above, each note's glow a little wrong",
          "C3–C5", "Film, dark pop, ambient", "Chords, slowly", "TEXTURE",
          "The halo is quiet by design; TONE brings it forward without brightening the body")
    out.append(p)

    # 10 EMPTY BUILDING: sparse on purpose: a hollow notch-filtered core,
    # a quiet fifth that surfaces and sinks, distant comb harmonics.
    p = P("EMPTY BUILDING", "NS HOLLOW BONE", "SPECTRAL_COMB")
    p.osc(0, level=0.62, wt=0.2)
    p.osc(1, level=0.2, wt=0.6, semi=7, unison=2, detune=0.06, width=1.0)
    p.filter("NOTCH", hz=900, res=0.3, keytrack=0.3)
    p.filter2("LP24", hz=2400, res=0.1)
    p.insert(1, "COMB", after=True, amount=0.55, freq=0.75, mix=0.2)
    bed(p, a=1.5, d=3.0, s=0.85, r=2.5)
    p.tone("F2_CUTOFF", 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.043, [("CUTOFF", 0.2)])
    drift(p, 2, 0.067, [("B_LEVEL", 0.15), ("INS1_AMOUNT", 0.15)])
    p.eq(low=-3, low_hz=180)
    hall(p, mix=0.2, decay=0.5, size=0.9, predelay=0.2)
    grit(p, mode="SOFT", drive=0.25, tone=0.35, amount=0.3, base=0.0)
    p.set("a.wtpos", 0.3)
    p.motion("LFO1", "A_WTPOS", 0.35)
    p.set("dist.mix", 0.16)
    drift(p, 3, 0.23, [("A_WTPOS", 0.25), ("CUTOFF", 0.05)])
    p.doc("A sparse, hollow bed with a notch drifting through it and a far-off fifth surfacing and sinking",
          "C3–C5", "Film, horror, ambient", "Single notes or open fifths work as well as chords", "TEXTURE",
          "The emptiness is in the synth: the notch keeps the mids open, so it can sit under almost anything")
    out.append(p)

    # 11 MERCURY SKIN: comb and phaser filters in parallel whose tunings
    # wander, so the chord seems to change material while its pitch holds.
    p = P("MERCURY SKIN", "GLASS", "NS SERPENT")
    p.osc(0, level=0.58, wt=0.5, unison=3, detune=0.08, width=0.5)
    p.osc(1, level=0.3, wt=0.8, unison=3, detune=0.06, width=0.7)
    p.filter("COMB_POS", hz=900, res=0.55, keytrack=1.0, mix=0.45)
    p.filter2("PHASER", hz=1400, res=0.4, mix=0.5)
    p.set("filter.routing", 1)
    bed(p, a=0.7, d=3.0, s=0.9, r=1.8)
    p.tone("F2_CUTOFF", 0.2)
    p.set("macro2", 0.5)
    drift(p, 1, 0.06, [("F2_CUTOFF", 0.25)])
    drift(p, 2, 0.089, [("RES", 0.12), ("A_WTPOS", 0.25)])
    p.eq(low=-4, low_hz=160)
    plate(p, mix=0.18, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35, base=0.1)
    p.set("b.wtpos", 0.3)
    p.motion("LFO2", "B_WTPOS", 0.3)
    p.doc("A sleek chord in liquid metal: two resonant filters sliding against each other so the material keeps changing",
          "C3–C5", "Electronica, dark pop, film", "Held chords", "TEXTURE",
          "The comb follows the key, so it stays in tune; a low shelf is already taken out")
    out.append(p)

    # 12 STATIC HEART: the texture comes in bursts: a sample-and-hold into a
    # smoothed noise gate and crush, so the grit sparks and dies organically.
    p = P("STATIC HEART", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.62, wt=0.8, unison=4, detune=0.08, width=0.5)
    p.osc(1, level=0.26, wt=0.4, octave=1, unison=2, detune=0.08, width=0.7)
    p.noise(0.0, type="DIGITAL", color=0.6, keytrack=True)
    p.insert(1, "BITCRUSH", after=True, amount=0.55, mix=0.0)
    p.filter("LP24", hz=2000, res=0.12, keytrack=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=0.5, d=2.5, s=0.9, r=1.6)
    p.lfo(1, "SAMPLE_HOLD", hz=2.3, mode="FREE", smooth=True)
    p.lfo(2, "SMOOTH_RANDOM", hz=0.21, mode="FREE")
    p.set("macro2", 0.5)
    p.mod("LFO1", "NOISE_LEVEL", 0.08, aux="LFO2")
    p.motion("LFO1", "INS1_AMOUNT", 0.2)
    p.motion("LFO2", "NOISE_LEVEL", 0.07)
    p.set("ins1.mix", 0.3)
    p.tone("CUTOFF", 0.16)
    p.chorus(mode="SUBTLE", mix=0.3, rate=0.3, depth=0.4, width=0.7)
    hall(p, mix=0.18, decay=0.4)
    grit(p, mode="TUBE", drive=0.35, tone=0.4, amount=0.3, base=0.1)
    p.set("b.wtpos", 0.2)
    p.motion("LFO1", "B_WTPOS", 0.15)
    p.doc("A warm chord with electrical life inside it: static that sparks, swells and dies away on its own",
          "C3–C5", "Dark pop, alt-R&B, film", "Chords held for bars", "SUPPORT",
          "The static is gated by a slow random, so it comes and goes rather than sitting on top")
    out.append(p)

    # 13 UNDERGROUND SUN: restrained dark bed; ENV3 over nine seconds opens
    # a harmonic-sweep layer into a radiant top, never into a fanfare.
    p = P("UNDERGROUND SUN", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.62, wt=0.75, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.05, octave=1, unison=5, detune=0.1, width=0.9)
    p.filter("LP24", hz=1200, res=0.15, keytrack=0.35)
    fsat(p, "SOFT", drive=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=1.0, d=3.0, s=0.92, r=2.0)
    p.env(3, a=9.0, d=0.1, s=1.0, r=2.5, acurve=0.4)
    p.mod("ENV3", "B_WTPOS", 0.6)
    p.mod("ENV3", "CUTOFF", 0.16)
    p.mod("ENV3", "B_LEVEL", 0.1)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.45)
    drift(p, 1, 0.08, [("B_WTPOS", 0.12)])
    dimension(p, mix=0.3, size=0.6)
    hall(p, mix=0.2, decay=0.45)
    grit(p, mode="SOFT", drive=0.35, tone=0.45, amount=0.35, base=0.12)
    p.set("b.wtpos", 0.0)
    p.set("dist.mix", 0.16)
    drift(p, 2, 0.26, [("CUTOFF", 0.09), ("A_WTPOS", 0.35)])
    p.doc("A dark bed with a radiant layer buried inside that rises over nine seconds, more ache than triumph",
          "C3–C5", "Film, dark pop builds, ambient", "Long chords; let it bloom", "SUPPORT",
          "Short chords stay dark; the light only arrives if you hold")
    out.append(p)

    # 14 SLOW COLLAPSE: ENV4 over twelve seconds pulls pitch flat by a few
    # cents on B, closes the filter, raises drive and feedback: failure, not noise.
    p = P("SLOW COLLAPSE", "ANALOG", "NS TENDON")
    p.osc(0, level=0.6, wt=0.9, unison=4, detune=0.08, width=0.5)
    p.osc(1, level=0.32, wt=0.95, unison=4, detune=0.1, width=0.8)
    p.filter("LP24", hz=2600, res=0.18, keytrack=0.3)
    p.feedback(amount=0.08, drive=0.4, tone=0.5)
    p.filter2("HP24", hz=150)
    bed(p, a=0.6, d=3.0, s=0.92, r=2.0)
    p.env(4, a=12.0, d=0.1, s=1.0, r=3.0, acurve=0.5)
    p.mod("ENV4", "B_FINE", -0.18)
    p.mod("ENV4", "CUTOFF", -0.15)
    p.mod("ENV4", "FEEDBACK", 0.25)
    p.mod("ENV4", "DIST_MIX", 0.35)
    p.mod("ENV4", "A_DETUNE", 0.2)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.45)
    drift(p, 1, 0.1, [("B_FINE", 0.05)])
    hall(p, mix=0.2, decay=0.42)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.3, base=0.0)
    p.set("b.wtpos", 0.0)
    p.mod("ENV4", "B_WTPOS", 0.55)
    p.set("env4.slope", 0.6)
    p.doc("Beautiful when struck; over twelve seconds it sags flat, darkens and starts to overload, like something huge failing",
          "C3–C5", "Film, industrial ballads, ends of songs", "One long chord", "TEXTURE",
          "Short chords never reach the collapse; hold for the full effect")
    out.append(p)

    # 15 VANTA: dark by harmonic structure, not a closed filter: a formant
    # body, a low-passed noise skin, fine upper detail kept at -20 dB.
    p = P("VANTA", "NS THROAT", "BASIC")
    p.osc(0, level=0.6, wt=0.2, unison=3, detune=0.06, width=0.4)
    p.osc(1, level=0.3, wt=0.0, octave=-1)
    p.noise(0.05, type="BROWN", color=0.3, keytrack=False)
    p.filter("FORMANT", hz=600, res=0.4, keytrack=0.2)
    p.filter2("HP24", hz=140)
    p.insert(1, "SINE", after=True, amount=0.2, mix=0.25)
    bed(p, a=1.0, d=3.0, s=0.9, r=2.0)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.5)
    drift(p, 1, 0.05, [("CUTOFF", 0.1)])
    drift(p, 2, 0.077, [("A_WTPOS", 0.25), ("INS1_AMOUNT", 0.15)])
    p.eq(high=-3, high_hz=5000, mid=1.5, mid_hz=320)
    hall(p, mix=0.18, decay=0.42, damp=0.7)
    grit(p, mode="SOFT", drive=0.3, tone=0.3, amount=0.3, base=0.1)
    p.set("a.wtpos", 0.05)
    p.set("b.warpmode", 7)
    p.set("b.warp", 0.2)
    drift(p, 3, 0.3, [("CUTOFF", 0.1), ("A_WTPOS", 0.2)])
    p.doc("Darkness with detail in it: a moving vowel body and a faint wrinkled skin instead of a shut filter",
          "C3–C5", "Dark ambient, industrial, film", "Low chords and clusters", "TEXTURE",
          "Its brightness is in the vowel; TONE moves the vowel, it does not open a lid")
    out.append(p)

    # 16 CHROME GRIEF: FM-bell metal partials over a warm pulse body; the
    # metal fades as the note holds, leaving the warmth exposed.
    p = P("CHROME GRIEF", "FM_BELL", "NS OBSIDIAN")
    p.osc(0, level=0.4, wt=0.6, octave=1, unison=3, detune=0.05, width=0.8)
    p.osc(1, level=0.58, wt=0.4, unison=4, detune=0.08, width=0.4)
    p.insert(1, "RING", after=True, amount=0.4, freq=0.75, mix=0.15)
    p.filter("LP24", hz=2200, res=0.14, keytrack=0.35)
    p.filter2("HP24", hz=150)
    bed(p, a=0.3, d=3.0, s=0.9, r=1.8)
    p.env(3, a=0.01, d=5.0, s=0.3, r=1.5)
    p.mod("ENV3", "A_LEVEL", 0.35)
    p.mod("ENV3", "INS1_AMOUNT", 0.2)
    vintage(p, 0.2)
    p.tone("CUTOFF", 0.09)
    p.set("macro2", 0.45)
    drift(p, 1, 0.09, [("A_WTPOS", 0.2), ("B_WTPOS", 0.15)])
    plate(p, mix=0.18, decay=0.4)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35, base=0.12)
    p.set("b.wtpos", 0.05)
    p.set("a.warpmode", 12)
    p.set("a.warp", 0.2)
    drift(p, 2, 0.28, [("CUTOFF", 0.06), ("A_WTPOS", 0.15)])
    p.doc("Polished chrome partials over a warm pulse body; the metal fades as it holds and leaves the warmth bare",
          "C3–C5", "Dark pop, electronica, film", "Chords, restruck every bar or two", "SUPPORT",
          "Restriking brings the chrome back; long holds turn it tender")
    out.append(p)

    # 17 BURIED LIGHT: a muted body and a bright layer gated by a slow,
    # random-rate window, so light surfaces only now and then.
    p = P("BURIED LIGHT", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.62, wt=0.85, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.0, wt=0.6, octave=1, unison=4, detune=0.08, width=0.9)
    p.filter("LP24", hz=900, res=0.15, keytrack=0.35)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP24", hz=150)
    p.route_filter(a=True, b=False)
    bed(p, a=0.8, d=3.0, s=0.9, r=2.0)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.19, mode="FREE")
    p.lfo(2, "SMOOTH_RANDOM", hz=0.043, mode="FREE")
    p.set("macro2", 0.5)
    p.mod("LFO1", "B_LEVEL", 0.34, aux="LFO2", curve=0.6)
    p.motion("LFO2", "B_LEVEL", 0.12)
    p.motion("LFO1", "CUTOFF", 0.06)
    p.tone("CUTOFF", 0.16)
    p.eq(high=-2, high_hz=8000)
    hall(p, mix=0.2, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.3, base=0.1)
    p.set("b.wtpos", 0.7)
    p.motion("LFO2", "B_WTPOS", 0.25)
    p.set("dist.mix", 0.16)
    p.doc("A muted, opaque chord with light moving underneath: a bright layer that surfaces only now and then",
          "C3–C5", "Film, ambient pop, dark pop verses", "Held chords", "TEXTURE",
          "The glints are unpredictable but never loud; MOTION 0 keeps the lid closed")
    out.append(p)

    # 18 FALSE MEMORY: soft attacks, a few cents of VINTAGE and a slow
    # wow on the upper layer, and a tape-like top that dulls as it holds.
    p = P("FALSE MEMORY", "ANALOG", "NS HOLLOW BONE")
    p.osc(0, level=0.6, wt=0.7, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.6, octave=1, unison=2, detune=0.06, width=0.8)
    p.noise(0.035, type="VINYL", color=0.5, keytrack=False)
    p.insert(1, "DECIMATE", after=True, amount=0.2, mix=0.3)
    p.filter("LP12", hz=2600, res=0.08, keytrack=0.3)
    p.filter2("HP24", hz=160)
    bed(p, a=1.2, d=3.0, s=0.9, r=1.8)
    p.env(3, a=6.0, d=0.1, s=1.0, r=1.5)
    p.mod("ENV3", "CUTOFF", -0.1)
    vintage(p, 0.45)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.5)
    drift(p, 1, 0.33, [("B_FINE", 0.06)], shape="SINE")
    drift(p, 2, 0.071, [("B_WTPOS", 0.2)])
    hall(p, mix=0.2, decay=0.4)
    grit(p, mode="SOFT", drive=0.3, tone=0.35, amount=0.3, base=0.12)
    p.set("b.wtpos", 0.4)
    p.flanger(mix=0.12, rate=0.08, depth=0.35, feedback=0.3)
    p.set("dist.mix", 0.16)
    p.doc("A chord remembered slightly wrong: soft edges, a faint wow, a top that dulls the longer you hold it",
          "C3–C5", "Dark pop, dream pop, film", "Slow chords", "SUPPORT",
          "Not an 80s pad: no brass, no bright saws; the nostalgia is in the drift")
    out.append(p)

    # 19 NIGHT BLOOM: starts narrow; ENV3 opens unison width, the wide
    # upper layer and the dimension stage over five seconds.
    p = P("NIGHT BLOOM", "ANALOG", "CHOIR")
    p.osc(0, level=0.6, wt=0.8, unison=5, detune=0.1, width=0.0)
    p.osc(1, level=0.18, wt=0.5, octave=1, unison=6, detune=0.12, width=0.0)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.51, mix=0.15)
    p.filter("LP24", hz=1800, res=0.12, keytrack=0.3)
    p.filter2("HP24", hz=160)
    bed(p, a=0.4, d=3.0, s=0.9, r=2.0)
    p.env(3, a=5.0, d=0.1, s=1.0, r=2.0, acurve=0.3)
    p.mod("ENV3", "A_WIDTH", 0.7)
    p.mod("ENV3", "B_WIDTH", 1.0)
    p.mod("ENV3", "B_LEVEL", 0.14)
    p.mod("ENV3", "DIM_MIX", 0.4)
    p.mod("ENV3", "CUTOFF", 0.08)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.45)
    drift(p, 1, 0.08, [("INS1_FREQ", 0.01)])
    dimension(p, mix=0.0, size=0.7)
    hall(p, mix=0.2, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.3, base=0.12)
    p.set("b.unimode", 3)
    p.set("a.stack", 1)
    p.set("dist.mix", 0.16)
    p.doc("Starts narrow and close, then flowers into a huge stereo image over five seconds",
          "C3–C5", "Dark pop, film, builds", "Chords held a bar or more", "SUPPORT",
          "Short stabs stay mono; the width is a reward for holding")
    out.append(p)

    # 20 SOFT MACHINE: a breathing organic swell (slow random on level and
    # cutoff) with a faint tempo-locked mechanical tick in the comb insert.
    p = P("SOFT MACHINE", "ANALOG", "NS SCAR PULSE")
    p.osc(0, level=0.62, wt=0.8, unison=4, detune=0.08, width=0.5)
    p.osc(1, level=0.24, wt=0.4, octave=1, unison=2, detune=0.08, width=0.8)
    p.insert(1, "COMB", after=True, amount=0.4, freq=0.75, mix=0.18)
    p.filter("LP24", hz=1900, res=0.14, keytrack=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=0.6, d=3.0, s=0.9, r=1.8)
    p.lfo(1, "SMOOTH_RANDOM", hz=0.23, mode="FREE")
    p.lfo(2, "CUSTOM", sync="1/8", mode="FREE", smooth=True,
          points=[1.0 if i in (0, 1) else (0.4 if i in (16, 17) else -0.2) for i in range(32)])
    p.set("macro2", 0.5)
    p.motion("LFO1", "CUTOFF", 0.08)
    p.motion("LFO1", "AMP", 0.08)
    p.motion("LFO2", "INS1_AMOUNT", 0.18)
    p.motion("LFO2", "B_WTPOS", 0.08)
    p.tone("CUTOFF", 0.16)
    hall(p, mix=0.18, decay=0.4)
    grit(p, mode="SOFT", drive=0.3, tone=0.45, amount=0.3, base=0.12)
    p.set("b.wtpos", 0.15)
    p.motion("LFO2", "B_WTPOS", 0.2)
    p.doc("A warm chord that breathes like something alive, with the faint tick of machinery under the skin",
          "C3–C5", "Electronica, dark pop, film", "Chords on the grid; the tick follows the tempo", "SUPPORT",
          "The machinery is an eighth-note comb flicker at -20 dB; MOTION takes it away")
    out.append(p)

    # 21 BLACK WATER: slow waves in the harmonics and the stereo field from
    # PAN-spread wandering, not a chorus; the fundamental stays centred.
    p = P("BLACK WATER", "ANALOG", "NS SERPENT")
    p.osc(0, level=0.62, wt=0.7, unison=2, detune=0.05, width=0.2)
    p.osc(1, level=0.3, wt=0.3, octave=1, unison=4, detune=0.08, width=0.8)
    p.filter("LP24", hz=1300, res=0.2, keytrack=0.35, drive=0.3)
    p.filter2("HP24", hz=150)
    bed(p, a=1.0, d=3.0, s=0.9, r=2.0)
    p.lfo(1, "SINE", hz=0.061, mode="FREE")
    p.lfo(2, "SINE", hz=0.097, mode="FREE", phase=0.3)
    p.lfo(3, "SMOOTH_RANDOM", hz=0.14, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "B_PAN", 0.45)
    p.motion("LFO2", "B_WTPOS", 0.35)
    p.motion("LFO3", "CUTOFF", 0.08)
    p.motion("LFO2", "FILTER_PAN", 0.2)
    p.tone("CUTOFF", 0.16)
    hall(p, mix=0.2, decay=0.45, damp=0.65)
    grit(p, mode="SOFT", drive=0.3, tone=0.35, amount=0.3, base=0.12)
    p.set("b.wtpos", 0.15)
    p.doc("A deep, fluid bed: slow waves roll through the harmonics and across the stereo field while the root stays put",
          "C3–C5", "Film, dark ambient, trip-hop", "Slow chords", "TEXTURE",
          "No chorus: the movement is two slow sines and a random, so it never beats in time")
    out.append(p)

    # 22 VEINS OF LIGHT: thin bright strands two octaves up, each gated by
    # its own free LFO so they weave in and out of a dark body.
    p = P("VEINS OF LIGHT", "ANALOG", "NS NEON NERVE")
    p.osc(0, level=0.62, wt=0.8, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.12, wt=0.8, octave=2, unison=2, detune=0.04, width=1.0)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.75, mix=0.12)
    p.filter("LP24", hz=1100, res=0.15, keytrack=0.35)
    fsat(p, "SOFT", drive=0.3)
    p.filter2("HP24", hz=150)
    p.route_filter(a=True, b=False)
    bed(p, a=0.9, d=3.0, s=0.9, r=2.0)
    p.lfo(1, "SINE", hz=0.17, mode="FREE")
    p.lfo(2, "SMOOTH_RANDOM", hz=0.29, mode="FREE")
    p.lfo(3, "TRIANGLE", hz=0.053, mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "B_PAN", 0.6)
    p.mod("LFO2", "B_LEVEL", 0.12, aux="LFO3")
    p.motion("LFO3", "B_WTPOS", 0.3)
    p.motion("LFO2", "INS2_AMOUNT", 0.15)
    p.tone("CUTOFF", 0.16)
    p.eq(high=-2, high_hz=9000)
    hall(p, mix=0.2, decay=0.45)
    grit(p, mode="SOFT", drive=0.3, tone=0.4, amount=0.3, base=0.1)
    p.set("b.wtpos", 0.6)
    p.motion("LFO3", "B_WTPOS", 0.3)
    p.doc("Thin bright strands weaving through a dark body, each on its own clock, so held chords keep revealing detail",
          "C3–C5", "Film, dark pop, ambient", "Chords held for bars", "TEXTURE",
          "The strands are quiet and high; they shine through a mix without adding mud")
    out.append(p)

    # 23 PRESSURE ROOM: beating from a detuned second layer and a
    # tight-resonance feedback loop; tension, but every note stays in tune.
    p = P("PRESSURE ROOM", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=0.95, unison=2, detune=0.04, width=0.3)
    p.osc(1, level=0.34, wt=0.95, fine=9, unison=2, detune=0.04, width=0.7)
    p.filter("LP24", hz=1100, res=0.4, keytrack=0.5, drive=0.35)
    p.feedback(amount=0.1, drive=0.5, tone=0.55)
    p.filter2("HP24", hz=160)
    bed(p, a=1.2, d=3.0, s=0.9, r=1.6)
    p.env(3, a=6.0, d=0.1, s=1.0, r=1.5)
    p.mod("ENV3", "FEEDBACK", 0.1)
    p.mod("ENV3", "RES", 0.1)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.5)
    drift(p, 1, 0.11, [("FB_TONE", 0.2), ("CUTOFF", 0.06)])
    plate(p, mix=0.12, decay=0.35)
    grit(p, mode="TUBE", drive=0.45, tone=0.4, amount=0.35, base=0.15)
    p.set("a.warpmode", 7)
    p.set("a.warp", 0.12)
    p.fxfilter(type="NOTCH", cut=0.55, res=0.2, mix=0.35)
    p.motion("LFO1", "FXF_CUTOFF", 0.1)
    p.doc("Physical tension: two layers beating a few cents apart and a filter loop tightening as the chord holds",
          "C3–C5", "Industrial, film, dark techno breakdowns", "Held chords under a build", "SUPPORT",
          "The beating is fixed at 9 cents so chords stay in tune; MOTION only moves the loop's colour")
    out.append(p)

    # 24 END CREDITS FOR THE APOCALYPSE: a full-range electronic swell:
    # stacked fifths above a steady root, slow opening, a restrained wall.
    p = P("END CREDITS FOR THE APOCALYPSE", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.58, wt=0.85, unison=5, detune=0.1, width=0.5, stack="OCTAVE")
    p.osc(1, level=0.3, wt=0.2, octave=1, unison=5, detune=0.12, width=1.0, warp="FOLD", warp_amt=0.15)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.506, mix=0.12)
    p.filter("LP24", hz=1400, res=0.16, keytrack=0.35, env=0.25)
    fsat(p, "SOFT", drive=0.35)
    p.filter2("HP24", hz=140)
    bed(p, a=1.5, d=4.0, s=0.95, r=2.5)
    p.env(2, a=6.0, d=4.0, s=0.8, r=2.0)
    p.env(3, a=10.0, d=0.1, s=1.0, r=2.5)
    p.mod("ENV3", "B_WTPOS", 0.5)
    p.mod("ENV3", "B_WARP", 0.2)
    p.mod("ENV3", "DIM_MIX", 0.3)
    vintage(p, 0.25)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.5)
    drift(p, 1, 0.06, [("B_WTPOS", 0.12), ("INS1_FREQ", 0.008)])
    dimension(p, mix=0.2, size=0.8)
    hall(p, mix=0.22, decay=0.5, size=0.85)
    grit(p, mode="TUBE", drive=0.4, tone=0.45, amount=0.35, base=0.15)
    p.set("b.wtpos", 0.1)
    p.set("b.unimode", 1)
    drift(p, 3, 0.27, [("CUTOFF", 0.06), ("A_WTPOS", 0.2)])
    p.doc("A chord big enough to carry a song: octave-stacked body, an upper fold that climbs for ten seconds, no orchestra",
          "C3–C5", "Film, dark pop finales, post-rock electronics", "Whole-bar chords; one chord can be a section",
          "FOREGROUND", "It fills the range above 140 Hz; give it the space a string section would get")
    out.append(p)

    # 25 THE SHAPE IN THE DARK: the flagship. A velocity-sensitive, centred
    # analog core; a growl-table upper layer that ENV3 unfurls; a comb shadow
    # an octave up; three unrelated wanders; filter saturation and a measured wall.
    p = P("THE SHAPE IN THE DARK", "NS OBSIDIAN", "NS TENDON")
    p.osc(0, level=0.6, wt=0.85, unison=3, detune=0.07, width=0.3)
    p.osc(1, level=0.3, wt=0.15, octave=1, unison=6, detune=0.13, width=1.0, warp="ASYM_NEG", warp_amt=0.2)
    p.noise(0.04, type="BREATH", color=0.5, keytrack=True, pan=0.0)
    p.insert(1, "COMB", after=True, amount=0.45, freq=0.75, mix=0.18)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.507, mix=0.12)
    p.filter("LADDER", hz=1600, res=0.22, keytrack=0.35, env=0.18)
    fsat(p, "SOFT", drive=0.4)
    p.filter2("HP24", hz=145)
    bed(p, a=0.6, d=4.0, s=0.92, r=2.2, vel=0.25)
    p.env(2, a=2.0, d=5.0, s=0.7, r=2.0)
    p.env(3, a=8.0, d=0.1, s=1.0, r=2.5, acurve=0.35)
    p.mod("ENV3", "B_WTPOS", 0.5)
    p.mod("ENV3", "B_WARP", 0.25)
    p.mod("ENV3", "DIST_MIX", 0.2)
    p.mod("VELOCITY", "B_LEVEL", 0.12)
    p.mod("VELOCITY", "CUTOFF", 0.08)
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.35)
    p.mod("MODWHEEL", "FEEDBACK", 0.15)
    vintage(p, 0.25)
    p.tone("CUTOFF", 0.16)
    p.set("macro2", 0.5)
    drift(p, 1, 0.037, [("B_WTPOS", 0.2)])
    drift(p, 2, 0.061, [("INS1_FREQ", 0.015), ("B_PAN", 0.2)])
    drift(p, 3, 0.097, [("CUTOFF", 0.05)])
    dimension(p, mix=0.3, size=0.7)
    hall(p, mix=0.22, decay=0.48, size=0.8)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.35, base=0.15)
    p.set("a.wtpos", 0.1)
    p.set("b.wtpos", 0.05)
    p.mod("TIMBRE", "B_WTPOS", 0.4)
    p.set("env3.slope", 0.4)
    drift(p, 4, 0.34, [("CUTOFF", 0.14), ("A_WTPOS", 0.55)])
    p.doc("The flagship pad: a steady analog heart, a growl layer that unfurls over eight seconds, a comb shadow and three slow wanders",
          "C3–C5", "Dark pop, industrial, film", "Chords of any length; velocity and mod wheel reshape it", "FOREGROUND",
          "Mod wheel pushes the comb and the filter loop; everything under 145 Hz is one clean centred voice")
    out.append(p)

    return out
