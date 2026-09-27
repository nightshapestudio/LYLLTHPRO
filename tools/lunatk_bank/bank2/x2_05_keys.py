"""EXPANSION 02 / DISTORTED EMOTIONAL KEYS. Struck, decaying keyboard
voices; the distortion is revealed by velocity or by holding, and every one
uses a different struck-body model (FM bell, comb string, formant, fold)."""

from bank2._common import echo, velocity
from bank2._showcase import drift, fsat, punch, vintage
from bank2._x2 import N, burn, hall, plate, poly


def K(name, a="ANALOG", b="BASIC"):
    return N(name, "KEYS", a, b)


def struck(p, d=1.2, s=0.25, r=0.5, vel=0.55):
    p.env(1, a=0.001, d=d, s=s, r=r)
    return poly(p, voices=10, vel=vel)


def presets():
    out = []

    # 41 BROKEN PORCELAIN: FM bell attack; velocity (steep curve) raises a
    # rectify insert and a slowly emerging (ENV3) fold on sustained notes.
    p = K("BROKEN PORCELAIN", "FM_BELL", "GLASS")
    p.osc(0, level=0.55, wt=0.35)
    p.osc(1, level=0.28, wt=0.5, octave=1)
    p.insert(1, "RECTIFY", after=True, amount=0.0, mix=0.4)
    p.insert(2, "FOLD", after=True, amount=0.0, mix=0.35)
    p.filter("LP24", hz=3600, res=0.12, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=180)
    p.env(2, a=0.001, d=0.5, s=0.2, r=0.4)
    p.env(3, a=2.0, d=0.1, s=1.0, r=0.4)
    struck(p, d=1.6, s=0.3, r=0.6)
    velocity(p, 0.55, 0.2)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.5, curve=0.7)
    p.mod("ENV3", "INS2_AMOUNT", 0.3)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.31, [("A_WTPOS", 0.3)])
    plate(p, 0.14, decay=0.35)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Porcelain bells with hairline cracks: gentle playing is delicate; hard hits rectify, and held notes slowly fold",
          "C3–C6", "Ballads, dark pop, film", "Chords and melodies with dynamics", "FOREGROUND",
          "The cracks only show above velocity 90 or after two seconds")
    out.append(p)

    # 42 DEAD ROMANCE: warm pulse + comb-string body; controlled filter
    # saturation; VINTAGE per-note detune for the intimacy.
    p = K("DEAD ROMANCE", "PWM", "ANALOG")
    p.osc(0, level=0.58, wt=0.3)
    p.osc(1, level=0.25, wt=0.9, fine=5)
    p.insert(1, "COMB", after=True, amount=0.45, freq=0.5, mix=0.25)
    p.filter("LP24", hz=1900, res=0.15, keytrack=0.5, env=0.35)
    fsat(p, "SOFT", drive=0.4)
    p.filter2("HP12", hz=150)
    p.env(2, a=0.001, d=0.6, s=0.25, r=0.4)
    struck(p, d=1.4, s=0.35, r=0.5)
    vintage(p, 0.35)
    velocity(p, 0.5, 0.2)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.27, [("A_WTPOS", 0.3), ("CUTOFF", 0.05)])
    plate(p, 0.12)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("An intimate dark keyboard: pulse and a comb-string body, each note detuned its own way, warm saturation in the filter",
          "C2–C5", "Dark pop, singer-songwriter electronic", "Exposed chords under a vocal", "SUPPORT",
          "Leaves 2–5 kHz open for the voice")
    out.append(p)

    # 43 MERCURY TEARS: shimmering resonant partials from a parallel keytracked
    # positive comb; BITS saturation adds controlled digital grit; sustained
    # notes transform via ENV3 scanning SERPENT.
    p = K("MERCURY TEARS", "GLASS", "NS SERPENT")
    p.osc(0, level=0.55, wt=0.6)
    p.osc(1, level=0.25, wt=0.0, octave=1)
    p.filter("COMB_POS", hz=800, res=0.45, keytrack=1.0, mix=0.4)
    fsat(p, "BITS", drive=0.3, mix=0.35)
    p.filter2("LP24", hz=4200, res=0.1)
    p.env(3, a=2.5, d=0.1, s=1.0, r=0.5)
    p.mod("ENV3", "B_WTPOS", 0.5)
    struck(p, d=1.8, s=0.3, r=0.6)
    velocity(p, 0.5, 0.0)
    p.mod("VELOCITY", "F2_CUTOFF", 0.25)
    p.tone("F2_CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("CUTOFF", 0.08), ("A_WTPOS", 0.25)])
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12, pingpong=True)
    plate(p, 0.12)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("Shimmering liquid keys: comb resonances ringing at the note, a fine bit-grit in the filter, and held notes melting into a serpent sync layer",
          "C3–C6", "Electronica, dark pop, film", "Arpeggiated chords, sustained notes", "FOREGROUND",
          "The comb follows the key, so the shimmer is always in tune")
    out.append(p)

    # 44 STATIC PIANO: amplified-piano presence from: a hammer (noise burst +
    # punch), a bright FM partial layer that decays fast, a slower comb string,
    # uneven harmonic distortion via RANDOM on the fold.
    p = K("STATIC PIANO", "FM_BELL", "ANALOG")
    p.osc(0, level=0.5, wt=0.2)
    p.osc(1, level=0.35, wt=0.95)
    p.noise(0.0, type="CRACKLE", color=0.6, keytrack=True)
    p.insert(1, "COMB", after=True, amount=0.5, freq=0.5, mix=0.3)
    p.insert(2, "FOLD", after=True, amount=0.2, mix=0.25)
    p.filter("LP24", hz=2800, res=0.15, keytrack=0.6, env=0.45)
    p.filter2("HP12", hz=120)
    p.env(2, a=0.001, d=0.35, s=0.15, r=0.3)
    p.env(3, a=0.0005, d=0.015, s=0.0, r=0.01)
    p.mod("ENV3", "NOISE_LEVEL", 0.25)
    p.env(4, a=0.001, d=0.4, s=0.0, r=0.2)
    p.mod("ENV4", "A_LEVEL", 0.3)
    punch(p, 0.5)
    struck(p, d=2.2, s=0.0, r=0.5, vel=0.6)
    velocity(p, 0.6, 0.25)
    p.mod("RANDOM", "INS2_AMOUNT", 0.2)
    p.mod("RANDOM", "INS1_FREQ", 0.004)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.29, [("B_WTPOS", 0.25)])
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.4, base=0.18)
    p.motion("LFO1", "CUTOFF", 0.14)
    p.lfo(2, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO2", "CUTOFF", 0.2)
    p.motion("LFO2", "A_WTPOS", 0.4)
    p.doc("An amplified piano built from synthesis: a crackle hammer, a fast FM partial layer, a comb string decaying under it, and fold distortion different on every key",
          "C2–C6", "Industrial ballads, dark pop, alt-rock", "Piano parts, chords and octaves", "FOREGROUND",
          "Random per note: no two strikes distort identically")
    out.append(p)

    # 45 VELVET DAMAGE: two personalities split by velocity: soft = warm
    # two-pole ladder; hard = HARD fsat + ZEROSQUARE + rectified octave.
    p = K("VELVET DAMAGE", "ANALOG", "NS TENDON")
    p.osc(0, level=0.58, wt=0.8, unison=2, detune=0.05, width=0.3, warp="ASYM_POS", warp_amt=0.12)
    p.osc(1, level=0.0, wt=0.5, octave=1)
    p.filter("LADDER", hz=1500, res=0.2, keytrack=0.5, env=0.35)
    p.set("ladder.poles", 1)
    fsat(p, "HARD", drive=0.3, mix=0.4)
    p.filter2("HP12", hz=150)
    p.env(2, a=0.001, d=0.7, s=0.3, r=0.4)
    struck(p, d=1.5, s=0.4, r=0.5, vel=0.35)
    p.mod("VELOCITY", "B_LEVEL", 0.4, curve=0.6)
    p.mod("VELOCITY", "B_WTPOS", 0.5, curve=0.6)
    p.mod("VELOCITY", "FSAT_DRIVE", 0.35, curve=0.6)
    p.mod("VELOCITY", "CUTOFF", 0.25)
    p.mod("VELOCITY", "DIST_MIX", 0.35, curve=0.7)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.3, [("A_WTPOS", 0.25)])
    p.chorus(mode="SUBTLE", mix=0.18, rate=0.3, depth=0.3, width=0.6)
    plate(p, 0.1)
    burn(p, "ZEROSQUARE", drive=0.3, base=0.0)
    p.doc("Two keyboards in one: a warm two-pole velvet at low velocity, a hard-saturated, zero-squared tendon layer at the top",
          "C2–C5", "Dark pop, R&B-leaning electronic, industrial pop", "Dynamics are everything", "FOREGROUND",
          "Around velocity 85 it changes character, not just loudness")
    out.append(p)

    # 46 CRUSHED MEMORY: degraded but not lo-fi cliché (no vinyl crackle):
    # DECIMATE on B only, a slow pitch sag per note (ENV3 -> B_FINE), RATE fsat.
    p = K("CRUSHED MEMORY", "ORGAN", "NS HOLLOW BONE")
    p.osc(0, level=0.55, wt=0.4)
    p.osc(1, level=0.3, wt=0.3)
    p.insert(2, "DECIMATE", after=True, amount=0.3, mix=0.4)
    p.filter("LP12", hz=2400, res=0.1, keytrack=0.5, env=0.25)
    fsat(p, "RATE", drive=0.3, mix=0.3)
    p.filter2("HP12", hz=160)
    p.env(3, a=0.001, d=1.5, s=0.0, r=0.3)
    p.mod("ENV3", "B_FINE", 0.06)
    struck(p, d=1.4, s=0.3, r=0.5)
    vintage(p, 0.3)
    velocity(p, 0.5, 0.2)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.27, [("B_WTPOS", 0.35)])
    plate(p, 0.12)
    burn(p, "SOFT", drive=0.3, base=0.16)
    p.doc("A keyboard you half remember: organ and hollow-bone tones, one layer decimated and sagging into pitch as it sounds; no vinyl, no hiss",
          "C3–C5", "Dream pop, dark pop, film", "Slow chords", "SUPPORT",
          "The sag is six cents and settles; it colours, never detunes the chord")
    out.append(p)

    # 47 GLASS HEART: rich fundamental (triangle-ish BASIC) + GLASS partials
    # evolving through a TRIG LFO on the table; distinctive attack via ENV3 on FM.
    p = K("GLASS HEART", "BASIC", "GLASS")
    p.osc(0, level=0.55, wt=0.35, warp="FM", warp_amt=0.0)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.filter("LP24", hz=3800, res=0.12, keytrack=0.5, env=0.25)
    p.filter2("HP12", hz=160)
    p.insert(2, "SHIFT", after=True, amount=1.0, freq=0.506, mix=0.12)
    p.env(3, a=0.0005, d=0.08, s=0.0, r=0.05)
    p.mod("ENV3", "A_WARP", 0.4)
    struck(p, d=1.8, s=0.35, r=0.6)
    velocity(p, 0.55, 0.2)
    p.mod("VELOCITY", "B_LEVEL", 0.12)
    p.lfo(1, "SINE", hz=0.35, mode="TRIG")
    p.set("macro2", 0.4)
    p.motion("LFO1", "B_WTPOS", 0.45)
    p.tone("CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.12)
    burn(p, "SOFT", drive=0.3, base=0.16)
    fsat(p, "LIGHT", drive=0.3)
    p.doc("A glass heart with a warm core: an FM flick on the attack, glass partials that turn slowly inside each held note",
          "C3–C6", "Dark pop, ballads, electronica", "Melodies and open chords", "FOREGROUND",
          "The attack is 80 ms of FM, distinctive but soft")
    out.append(p)

    # 48 EMPTY PROMISE: restrained: a low-passed pulse, slow harmonic movement,
    # distortion only in the sustain (ENV3 on DIST_MIX, not the attack).
    p = K("EMPTY PROMISE", "PWM", "NS THROAT")
    p.osc(0, level=0.58, wt=0.5)
    p.osc(1, level=0.2, wt=0.2)
    p.filter("LP24", hz=1300, res=0.15, keytrack=0.5, env=0.2)
    fsat(p, "LIGHT", drive=0.3)
    p.filter2("HP12", hz=160)
    p.env(3, a=1.5, d=0.1, s=1.0, r=0.4)
    p.mod("ENV3", "DIST_MIX", 0.25)
    struck(p, d=2.0, s=0.45, r=0.5)
    velocity(p, 0.45, 0.2)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.25, [("A_WTPOS", 0.35), ("B_WTPOS", 0.3)])
    p.eq(mid=-2.5, mid_hz=1800, q=0.4)
    plate(p, 0.1)
    burn(p, "TUBE", drive=0.35, base=0.16)
    p.doc("A dark, restrained keyboard whose sustain turns faintly distorted while the attack stays clean; scooped for the vocal",
          "C3–C5", "Dark pop verses, ballads", "Sparse chords under a voice", "SUPPORT",
          "Cut at 1.8 kHz on purpose; the voice goes there")
    out.append(p)

    # 49 BLACK DIAMONDS: bright transient (sync ENV3 + punch) over an enormous
    # warm body (unison saw + octave sub layer + multiband comp).
    p = K("BLACK DIAMONDS", "SYNC_SWEEP", "ANALOG")
    p.osc(0, level=0.45, wt=0.3)
    p.osc(1, level=0.45, wt=0.9, unison=4, detune=0.08, width=0.6)
    p.sub(0.15, "SINE", octave=1)
    p.filter("LP24", hz=2400, res=0.15, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=110)
    p.env(2, a=0.001, d=0.4, s=0.3, r=0.4)
    p.env(3, a=0.001, d=0.05, s=0.0, r=0.03)
    p.mod("ENV3", "A_WTPOS", 0.5)
    punch(p, 0.45)
    struck(p, d=1.6, s=0.4, r=0.5)
    velocity(p, 0.8, 0.35)
    p.comp(mode="MULTIBAND", threshold=0.55, ratio=0.35, attack=0.35, release=0.4, gain=0.1, depth=0.5, mix=1.0)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.35)
    drift(p, 1, 0.3, [("B_WTPOS", 0.2), ("A_WTPOS", 0.2)])
    hall(p, mix=0.12, decay=0.35)
    burn(p, "DIODE", drive=0.35, base=0.18)
    fsat(p, "SOFT", drive=0.32)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("Cut and polished: a sharp sync flash on every strike over a big, warm, band-compressed body",
          "C2–C5", "Dark pop, synth pop, film", "Chord stabs and sustained chords", "FOREGROUND",
          "The flash is 50 ms; the body carries the chord")
    out.append(p)

    # 50 BEAUTIFUL RUIN: flagship keys: intimate at low velocity; velocity,
    # wheel and pressure each open a different damage stage (fold, diode
    # fsat, feedback), so performance travels from beauty to ruin.
    p = K("BEAUTIFUL RUIN", "NS RADIANT", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.28, wt=0.05, octave=1)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.filter("LADDER", hz=2200, res=0.2, keytrack=0.5, env=0.35)
    fsat(p, "DIODE", drive=0.3, mix=0.5)
    p.feedback(amount=0.0, drive=0.6, tone=0.5)
    p.filter2("HP12", hz=150)
    p.env(2, a=0.001, d=0.6, s=0.3, r=0.4)
    struck(p, d=1.8, s=0.35, r=0.6, vel=0.4)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.4, curve=0.6)
    p.mod("VELOCITY", "B_WTPOS", 0.45, curve=0.6)
    p.mod("VELOCITY", "CUTOFF", 0.22)
    p.mod("MODWHEEL", "FSAT_DRIVE", 0.45)
    p.mod("PRESSURE", "FEEDBACK", 0.25)
    vintage(p, 0.2)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.4)
    drift(p, 1, 0.31, [("A_WTPOS", 0.35)])
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    plate(p, 0.12)
    burn(p, "TUBE", drive=0.4, base=0.16)
    p.doc("The flagship keys: a radiant, intimate keyboard; velocity folds it and scars the obsidian octave, the wheel drives the diode, pressure feeds the loop",
          "C2–C5", "Dark pop, ballads, industrial", "Play softly, then let it fall apart", "FOREGROUND",
          "Each performance control opens a different kind of damage")
    out.append(p)

    return out
