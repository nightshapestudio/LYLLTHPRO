"""EXPANSION 02 / RHYTHMIC INDUSTRIAL TEXTURES. Held chords that pulse.
The rhythm is in timbre and gating (performers and tempo-synced LFOs), never
a drum transient; every one stays pitched."""

from bank2._common import accents, gate_seq, seq
from bank2._showcase import drift, fsat, morph, vintage
from bank2._x2 import N, burn, plate, poly


def M(name, a="ANALOG", b="BASIC"):
    return N(name, "MOTION", a, b)


def bed(p, a=0.02, r=0.4, vel=0.35):
    p.env(1, a=a, d=1.0, s=1.0, r=r)
    return poly(p, vel=vel)


def presets():
    out = []

    # 81 MECHANICAL HEART: two layers pulsing independently: A's level on a
    # lub-dub performer (soft edges), B's wavetable on a 1/8 dotted LFO.
    p = M("MECHANICAL HEART", "ANALOG", "NS TENDON")
    p.osc(0, level=0.55, wt=0.9)
    p.osc(1, level=0.3, wt=0.2, octave=1)
    p.filter("LP24", hz=1600, res=0.22, keytrack=0.4, drive=0.35)
    p.filter2("HP12", hz=140)
    bed(p)
    p.performer(1, {0: gate_seq("x.--x---x.--x---", shape="RAMP_DOWN")}, mode="SONG", rate="1/16")
    p.lfo(1, "TRIANGLE", sync="3/16", mode="FREE")
    p.set("macro2", 0.6)
    p.motion("PERF1", "A_LEVEL", 0.6)
    p.motion("LFO1", "B_WTPOS", 0.5)
    drift(p, 2, 0.21, [("CUTOFF", 0.06)])
    p.tone("CUTOFF", 0.16)
    plate(p, 0.08)
    burn(p, "TUBE", drive=0.45, base=0.25)
    p.doc("A chord with a mechanical heart: the saw layer beats lub-dub while the tendon layer folds on a dotted eighth: two pulses, one groove",
          "C3–C5", "Industrial pop, EBM, film", "Hold chords on the bar", "RHYTHM",
          "No attack spikes: the pulse is gain and timbre, so it sits under real drums")
    out.append(p)

    # 82 BLACK CONVEYOR: continuous resonant movement: a sixteenth accent
    # performer on RES plus a slow sweep of a keytracked BP peak.
    p = M("BLACK CONVEYOR", "ANALOG", "PWM")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.3, wt=0.4)
    p.filter("BP24", hz=900, res=0.4, keytrack=0.5, mix=0.6)
    fsat(p, "SOFT", drive=0.4)
    p.filter2("HP12", hz=140)
    bed(p)
    p.performer(1, {0: accents("XoxoXoxoXoxoXxoo")}, mode="SONG", rate="1/16")
    p.set("macro2", 0.6)
    p.motion("PERF1", "RES", 0.2)
    p.motion("PERF1", "CUTOFF", 0.12)
    p.lfo(1, "SINE", sync="4 BAR", mode="FREE")
    p.motion("LFO1", "CUTOFF", 0.2)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.08)
    burn(p, "DIODE", drive=0.4, base=0.22)
    p.doc("An endless black belt: a band-pass resonance ticking in sixteenths while it slowly travels up and down over four bars",
          "C3–C5", "Dark techno, industrial, film", "Hold chords for long sections", "RHYTHM",
          "Hypnotic by design; the four-bar sweep keeps it from standing still")
    out.append(p)

    # 83 CORRUPTED RHYTHM: irregular accents from a 13-step performer on the
    # decimator; a 16-step gate on level; the two never align.
    p = M("CORRUPTED RHYTHM", "NS FRACTURE", "ANALOG")
    p.osc(0, level=0.55, wt=0.2)
    p.osc(1, level=0.3, wt=0.95)
    p.insert(1, "DECIMATE", after=True, amount=0.0, mix=0.5)
    p.filter("LP24", hz=2000, res=0.22, keytrack=0.4)
    p.filter2("HP12", hz=150)
    bed(p)
    p.performer(1, {0: [(v, "DECAY") for v in (1.0, 0.0, 0.5, 0.0, 0.0, 0.9, 0.0, 0.3, 0.0, 0.7, 0.0, 0.0, 0.6)]}, mode="SONG", rate="1/16", steps=13)
    p.performer(2, {0: gate_seq("x-x.x--xx-x.x-x-")}, mode="SONG", rate="1/16")
    p.set("macro2", 0.6)
    p.motion("PERF1", "INS1_AMOUNT", 0.5)
    p.motion("PERF1", "A_WTPOS", 0.4)
    p.motion("PERF2", "AMP", 0.5)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "BITCRUSH", drive=0.25, base=0.18)
    p.doc("A gated sixteenth rhythm with a thirteen-step corruption running through it, crushing and fracturing different notes every bar",
          "C3–C5", "Glitch, industrial, alt-electronic", "Hold chords", "RHYTHM",
          "13 against 16: irregular, but it repeats exactly every 13 bars")
    out.append(p)

    # 84 PRESSURE VALVE: physical: a pump-like duck (drawn shape, 1/4) plus a
    # rising filter-drive ramp per eighth (performer RAMP_UP) - valves venting.
    p = M("PRESSURE VALVE", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.3)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LADDER", hz=1300, res=0.3, keytrack=0.4, drive=0.35)
    p.filter2("HP12", hz=130)
    bed(p)
    p.pump(lfo=1, sync="1/4", depth=0.35, default=None)
    p.performer(1, {0: [(1.0, "RAMP_UP"), (0.0, "HOLD")] * 8}, mode="SONG", rate="1/16")
    p.set("macro2", 0.6)
    p.motion("PERF1", "DRIVE", 0.25)
    p.motion("PERF1", "B_WTPOS", 0.35)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "HARD", drive=0.45, base=0.25)
    p.doc("A dense chord that vents pressure: ducking on every beat while its filter drive ramps up through each eighth like a valve about to blow",
          "C3–C5", "Industrial, EBM, dark techno", "Hold chords under a four-on-the-floor", "RHYTHM",
          "The duck only ever pulls level down, so it never jumps in volume")
    out.append(p)

    # 85 ELECTRICAL DAMAGE: irregular electrical textures from DIGITAL noise
    # gated by a 1/32 S&H, ring freq stepped by a performer; tonal saw below.
    p = M("ELECTRICAL DAMAGE", "ANALOG", "DIGITAL")
    p.osc(0, level=0.55, wt=0.9)
    p.osc(1, level=0.25, wt=0.5)
    p.noise(0.03, type="DIGITAL", color=0.6, keytrack=True)
    p.insert(2, "RING", after=True, amount=0.4, freq=0.6, mix=0.25)
    p.filter("LP24", hz=2200, res=0.2, keytrack=0.4)
    p.filter2("HP12", hz=150)
    bed(p)
    p.lfo(1, "SAMPLE_HOLD", sync="1/32", mode="FREE", smooth=False)
    p.performer(1, {0: [(v, "HOLD") for v in (0.0, 0.5, -0.3, 0.8, 0.0, -0.6, 0.3, 1.0) * 2]}, mode="SONG", rate="1/16")
    p.set("macro2", 0.6)
    p.motion("LFO1", "NOISE_LEVEL", 0.06)
    p.motion("PERF1", "INS2_FREQ", 0.03)
    p.motion("LFO1", "B_WTPOS", 0.3)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "DOWNSAMPLE", drive=0.3, base=0.18)
    p.doc("A steady saw chord with electrical damage arcing through it: thirty-second-note static bursts and a ring stepping between tunings",
          "C3–C5", "Industrial, cyberpunk scores, glitch", "Hold chords", "TEXTURE",
          "The saw below never moves; the damage is all around it")
    out.append(p)

    # 86 INDUSTRIAL BLOOD: warm and organic: a smooth RAMP/GLIDE performer on
    # a FORMANT filter (a breathing vowel pulse), tube saturation.
    p = M("INDUSTRIAL BLOOD", "ANALOG", "NS THROAT")
    p.osc(0, level=0.55, wt=0.9)
    p.osc(1, level=0.3, wt=0.4)
    p.filter("FORMANT", hz=600, res=0.35, keytrack=0.3, mix=0.5)
    p.filter2("LP24", hz=2400, res=0.12, drive=0.35)
    bed(p)
    p.performer(1, {0: [(-0.6, "GLIDE"), (0.2, "GLIDE"), (0.8, "GLIDE"), (0.1, "GLIDE"), (-0.4, "GLIDE"), (0.6, "GLIDE"), (-0.2, "GLIDE"), (0.9, "GLIDE")] * 2},
                mode="SONG", rate="1/8")
    p.set("macro2", 0.6)
    p.motion("PERF1", "CUTOFF", 0.2)
    p.motion("PERF1", "B_WTPOS", 0.4)
    drift(p, 1, 0.23, [("F2_CUTOFF", 0.06)])
    p.tone("F2_CUTOFF", 0.16)
    plate(p, 0.08)
    burn(p, "TUBE", drive=0.45, base=0.25)
    p.doc("Warm, muscular and alive: a vowel that flexes on the eighth notes like blood through a machine, tube-saturated",
          "C3–C5", "Alt-electronic, industrial pop, dark R&B", "Hold chords", "RHYTHM",
          "Glides between vowels rather than steps, so it pulses without clicking")
    out.append(p)

    # 87 BROKEN ASSEMBLY: asymmetric: an 11-step gate and a 7-step octave
    # performer on B's level (the octave appears and disappears).
    p = M("BROKEN ASSEMBLY", "NS SCAR PULSE", "ANALOG")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.25, wt=0.9, octave=1)
    p.filter("LP24", hz=1900, res=0.25, keytrack=0.4, drive=0.3)
    p.filter2("HP12", hz=150)
    bed(p)
    p.performer(1, {0: gate_seq("x.x-xx.x-x.-----")}, mode="SONG", rate="1/16", steps=11)
    p.performer(2, {0: [(v, "PULSE") for v in (1.0, -1.0, -1.0, 0.5, -1.0, 1.0, -1.0)]}, mode="SONG", rate="1/16", steps=7)
    p.set("macro2", 0.6)
    p.motion("PERF1", "AMP", 0.5)
    p.motion("PERF2", "B_LEVEL", 0.25)
    p.motion("PERF1", "A_WTPOS", 0.3)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "ZEROSQUARE", drive=0.3, base=0.18)
    p.doc("An assembly line that is out of true: an eleven-step gate and a seven-step octave stamp, strange and very musical",
          "C3–C5", "Art pop, industrial, glitch", "Hold chords", "RHYTHM",
          "11 against 7 against the bar; it never drifts off the grid")
    out.append(p)

    # 88 TENSION GRID (brief: STATIC PRESSURE, a name already in the bank):
    # evolving resonant peaks (two filters in parallel stepping by performer),
    # dense saturation, restrained level so it builds tension under a song.
    p = M("TENSION GRID", "ANALOG", "ANALOG")
    p.osc(0, level=0.55, wt=0.95)
    p.osc(1, level=0.3, wt=0.95, fine=6)
    p.filter("BP", hz=800, res=0.45, keytrack=0.5, mix=0.5)
    p.filter2("BP", hz=1600, res=0.4, mix=0.5)
    p.set("filter.routing", 1)
    fsat(p, "HARD", drive=0.35)
    bed(p)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.4, -0.3, 0.7, 0.1, -0.5, 0.5, 0.9) * 2]}, mode="SONG", rate="1/8")
    p.performer(2, {0: [(v, "HOLD") for v in (0.6, -0.2, 0.3, -0.6, 0.8, 0.0) + (0.0,) * 10]}, mode="SONG", rate="1/8", steps=6)
    p.set("macro2", 0.6)
    p.motion("PERF1", "CUTOFF", 0.2)
    p.motion("PERF2", "F2_CUTOFF", 0.2)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "TUBE", drive=0.4, base=0.22)
    p.doc("A grid of tension: two band-pass peaks on eight- and six-step paths, saturated hard, closing in on each other without resolving",
          "C3–C5", "Film, industrial, pre-choruses", "Hold chords under a build", "TEXTURE",
          "Restrained in level; it creates pressure without taking over")
    out.append(p)

    # 89 MACHINE FEVER: aggressive: strong saw fundamental; a 1/16 performer
    # drives FOLD, a triplet LFO drives B's table: constantly shifting.
    p = M("MACHINE FEVER", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.3, wt=0.3)
    p.insert(1, "FOLD", after=True, amount=0.0, mix=0.5)
    p.filter("LP24", hz=2000, res=0.25, keytrack=0.4, drive=0.35)
    p.filter2("HP12", hz=140)
    bed(p)
    p.performer(1, {0: accents("XxoXxoXxXxoXxoXo")}, mode="SONG", rate="1/16")
    p.lfo(1, "TRIANGLE", sync="1/12", mode="FREE")
    p.set("macro2", 0.6)
    p.motion("PERF1", "INS1_AMOUNT", 0.45)
    p.motion("LFO1", "B_WTPOS", 0.4)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "HARD", drive=0.5, base=0.3)
    p.doc("A fever in the machine: the saw folds on a driving sixteenth accent while the obsidian layer churns in triplets",
          "C3–C5", "Industrial, EBM, trailers", "Hold chords", "RHYTHM",
          "The fundamental never moves; the fever is all harmonics")
    out.append(p)

    # 90 THE FACTORY: flagship: three rhythmic engines: a gate, a 12-step
    # comb tuner, a pump, plus tempo-locked FM; enormous but controlled.
    p = M("THE FACTORY", "NS GRINDSTONE", "ANALOG")
    p.osc(0, level=0.5, wt=0.3, unison=2, detune=0.05, width=0.3)
    p.osc(1, level=0.3, wt=1.0, octave=-1, warp="FM", warp_amt=0.0)
    p.insert(2, "COMB", after=True, amount=0.45, freq=0.75, mix=0.15)
    p.filter("LADDER", hz=1500, res=0.28, keytrack=0.4)
    fsat(p, "DIODE", drive=0.4)
    p.filter2("HP12", hz=110)
    bed(p)
    p.performer(1, {0: gate_seq("x.xxx.x-x.xxx.xx")}, mode="SONG", rate="1/16")
    p.performer(2, {0: [(v, "HOLD") for v in (0.0, 0.5, 0.2, 0.8, -0.3, 0.4, 0.9, -0.1, 0.6, 0.1, -0.5, 0.7)]}, mode="SONG", rate="1/16", steps=12)
    p.lfo(1, "SAW_DOWN", sync="1/8", mode="FREE")
    p.set("macro2", 0.6)
    p.motion("PERF1", "AMP", 0.4)
    p.motion("PERF2", "INS2_FREQ", 0.02)
    p.motion("PERF2", "A_WTPOS", 0.35)
    p.motion("LFO1", "B_WARP", 0.3)
    p.mod("MODWHEEL", "INS2_AMOUNT", 0.3)
    p.tone("CUTOFF", 0.16)
    plate(p, 0.06)
    burn(p, "TUBE", drive=0.5, base=0.3)
    p.doc("The flagship rhythmic preset: a gated grindstone chord, a twelve-step comb tuner, and an eighth-note FM sawtooth under it, all locked to the song",
          "C3–C5", "Industrial, EBM, dark techno", "Hold one chord; it is a whole part", "RHYTHM",
          "Three engines, three cycle lengths, one tempo; the wheel brings the comb forward")
    out.append(p)

    return out
