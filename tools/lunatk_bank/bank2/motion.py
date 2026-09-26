"""MOTION: hold a chord and the rhythm is built in. Performers lock to the
bar; most presets carry four patterns (A–D) you can switch with PATTERN or
with the switch keys. MOTION scales every movement down to a still chord."""

from lunatk import Preset
from bank2._common import accents, echo, gate_seq, grit, seq, space, velocity


def M(name, a="ANALOG", b="ANALOG"):
    return Preset(name, "MOTION", a, b)


def bed(p, voices=8, vel=0.35):
    return p.voice(voices=voices, glide=0.0, vel=vel, bend=2)


def hall(p, mix=0.16, decay=0.3, amount=0.16, width=0.8):
    return space(p, mix, mode="HALL", size=0.55, decay=decay, damp=0.55, predelay=0.08, width=width, amount=amount)


def switchable(p):
    """The four switch keys from C1 pick the pattern."""
    return p.set("perf.keyswitch", 1).set("perf.keyroot", 24)


def presets():
    out = []

    p = M("IRON GATE", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=1.0, unison=5, detune=0.18, width=0.6)
    p.osc(1, level=0.3, wt=0.9, octave=1, unison=3, detune=0.12, width=0.5)
    p.insert(1, "BITCRUSH", after=True, amount=0.5, mix=0.25)
    p.filter("LP24", hz=2600, res=0.15, keytrack=0.3, drive=0.35)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: gate_seq("x-xxx-x-xx-x-xxx"), 1: gate_seq("xxx-xxx-xxx-xx-x"),
                    2: gate_seq("x---x---x-x-x---"), 3: gate_seq("xxxxxxxxxxxx.-.-")}, rate="1/16")
    switchable(p)
    p.set("macro2", 0.8)
    p.motion("PERF1", "AMP", 0.95)
    hall(p)
    grit(p, mode="TUBE", drive=0.45, tone=0.5, amount=0.4, base=0.25)
    p.doc("Crushed supersaw chords chopped by a sixteenth gate; four patterns on the switch keys", "C3–C5",
          "Industrial, trance-noir, trailer, EBM", "Hold chords; C1–D#1 switch patterns A–D", "RHYTHM",
          "Start chords on the bar. MOTION 0 is the plain chord; halfway is a soft chop")
    out.append(p)

    p = M("PISTON CHORDS", "ANALOG", "PWM")
    p.osc(0, level=0.6, wt=0.95, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.35, wt=0.3)
    p.filter("LP24", hz=1400, res=0.25, keytrack=0.3, drive=0.4)
    p.filter2("HP12", hz=180)
    p.feedback(amount=0.12, drive=0.5, tone=0.6)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("xxxxxxxxxxxxxxxx", {"x": (-1.0, "DECAY")}),
                    1: seq("x-x-x-x-x-x-x-x-", {"x": (-1.0, "DECAY")})}, rate="1/8")
    p.performer(2, {0: accents("X-x-X-x-X-x-X-x-", "DECAY")}, rate="1/16")
    p.set("macro2", 0.6)
    p.motion("PERF1", "AMP", 0.7)
    p.motion("PERF2", "CUTOFF", 0.25)
    hall(p, mix=0.12)
    grit(p, mode="HARD", drive=0.45, tone=0.5, amount=0.4, base=0.25)
    p.doc("Chords that duck and swell like a machine press, with accented filter hits", "C3–C5",
          "Industrial techno, EBM, big-room noir", "Hold chords; the pump is on eighths", "RHYTHM",
          "It pumps by itself; skip the sidechain or keep it light")
    out.append(p)

    p = M("RATTLE CAGE", "SPECTRAL_COMB", "BASIC")
    p.osc(0, level=0.6, wt=0.5, unison=3, detune=0.1, width=0.5)
    p.osc(1, level=0.3, wt=0.0, octave=1)
    p.insert(1, "COMB", after=True, amount=0.75, freq=0.5, mix=0.5)
    p.filter("LP24", hz=3000, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("aabbaaccaabbaadd", {"a": (0.0, "HOLD"), "b": (0.5, "HOLD"), "c": (-0.5, "HOLD"), "d": (1.0, "HOLD")}),
                    1: seq("abcdabcdabcdabcd", {"a": (0.0, "HOLD"), "b": (0.5, "HOLD"), "c": (1.0, "HOLD"), "d": (-0.5, "HOLD")})},
                rate="1/16")
    switchable(p)
    p.set("macro2", 0.5)
    p.motion("PERF1", "INS1_FREQ", 0.25)
    hall(p, mix=0.14)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.15)
    p.doc("Chords rattling inside a tuned cage: the comb steps between the note and its octaves", "C3–C5",
          "Industrial, sci-fi, IDM, film", "Hold chords; switch keys change the rattle", "RHYTHM",
          "Every step is an octave of the note, so it stays in key")
    out.append(p)

    p = M("STUTTER HYMN", "ORGAN", "ORGAN")
    p.osc(0, level=0.65, wt=0.5)
    p.osc(1, level=0.3, wt=0.8, octave=1, fine=5)
    p.insert(1, "DECIMATE", after=True, amount=0.25, mix=0.4)
    p.filter("LP12", hz=3000, res=0.05, keytrack=0.3, drive=0.3)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.005, d=1.0, s=0.95, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: gate_seq("xx-xx-xx-xx-x-x-"), 1: gate_seq("x--x--x--x--x--x"),
                    2: gate_seq("xxx.xxx.xxx.x.x."), 3: gate_seq("x-x-x-x-xxxxxxxx")}, rate="1/16")
    switchable(p)
    p.set("macro2", 0.75)
    p.motion("PERF1", "AMP", 0.9)
    p.chorus(mode="WIDE", mix=0.3, rate=0.35, depth=0.45, width=0.6)
    hall(p, mix=0.16)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.4, base=0.2)
    p.doc("A damaged organ hymn stuttering in three-against-four", "C3–C5", "Gothic, industrial, film",
          "Hold chords; patterns B and C are the dotted feels", "RHYTHM",
          "A hymn you can dance to: MOTION 0 for the plain organ in the bridge")
    out.append(p)

    p = M("HEAVY BREATH", "FORMANT", "ANALOG")
    p.osc(0, level=0.6, wt=0.4, unison=3, detune=0.1, width=0.5)
    p.noise(0.14, type="BREATH", color=0.5)
    p.filter("FORMANT", cut=0.4, res=0.3, keytrack=0.2)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.01, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.12)
    p.performer(1, {0: seq("x-------x-------", {"x": (1.0, "TRIANGLE")}, (0.0, "HOLD")),
                    1: seq("x---x---x---x---", {"x": (1.0, "TRIANGLE")})}, rate="1/8")
    p.set("macro2", 0.55)
    p.motion("PERF1", "NOISE_LEVEL", 0.4)
    p.motion("PERF1", "AMP", 0.4)
    p.motion("PERF1", "CUTOFF", 0.35)
    hall(p, mix=0.14)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35, base=0.1)
    p.doc("A chord that breathes: in and out on the bar, through a throat-shaped filter", "C3–C5",
          "Horror, industrial, film, dark ambient", "Hold chords for a bar or more", "TEXTURE",
          "Pattern B breathes twice as fast: panic")
    out.append(p)

    p = M("GRAIN CONVEYOR", "ANALOG", "GLASS")
    p.osc(0, level=0.6, wt=0.85, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.insert(1, "DECIMATE", after=True, amount=0.3, mix=0.6)
    p.filter("LP24", hz=2400, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: accents("X-o-x-o-X-o-x-oo", "DECAY"), 1: accents("XxXxoooo XxXxoooo".replace(" ", ""), "DECAY")}, rate="1/16")
    p.set("macro2", 0.55)
    p.motion("PERF1", "INS1_AMOUNT", 0.55)
    hall(p, mix=0.14)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.15)
    p.doc("A chord carried along a belt of grain: the crush pulses in sixteenths", "C3–C5",
          "Industrial, glitch, minimal techno", "Hold chords under drums", "RHYTHM",
          "The crush is the groove; MOTION 0 leaves a lightly crushed chord")
    out.append(p)

    p = M("VOWEL MACHINE", "CHOIR", "FORMANT")
    p.osc(0, level=0.6, wt=0.4, unison=3, detune=0.1, width=0.5)
    p.osc(1, level=0.35, wt=0.5)
    p.filter("FORMANT", cut=0.4, res=0.3, keytrack=0.2, drive=0.3)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.01, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.15)
    p.performer(1, {0: seq("aabbccddaabbccee", {"a": (-0.8, "GLIDE"), "b": (0.2, "GLIDE"), "c": (0.8, "GLIDE"), "d": (-0.3, "GLIDE"), "e": (0.5, "GLIDE")}),
                    1: seq("abababababababab", {"a": (-0.6, "HOLD"), "b": (0.6, "HOLD")})}, rate="1/8")
    p.set("macro2", 0.55)
    p.motion("PERF1", "CUTOFF", 0.45)
    hall(p, mix=0.16)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35, base=0.15)
    p.doc("A choir forced to speak a vowel sequence in eighths", "C3–C5", "Industrial, electro, film",
          "Hold chords for two bars", "RHYTHM", "Pattern B snaps between two vowels: a talk-box chug")
    out.append(p)

    p = M("BROKEN METRONOME", "BASIC", "BASIC")
    p.osc(0, level=0.65, wt=0.33, unison=3, detune=0.1, width=0.5)
    p.insert(1, "RING", after=True, amount=0.6, freq=0.625, mix=0.4)
    p.filter("LP24", hz=3000, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("x---x---x---x-x-", {"x": (1.0, "DECAY")}), 1: seq("x--x--x--x--x-x-", {"x": (1.0, "DECAY")})}, rate="1/16")
    p.performer(2, {0: gate_seq("xxxxxxxxxxxxxx--")}, rate="1/16")
    p.set("macro2", 0.55)
    p.motion("PERF1", "INS1_AMOUNT", 0.5)
    p.motion("PERF2", "AMP", 0.8)
    hall(p, mix=0.14)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("A chord with a metallic click on each beat, and a hiccup before the bar", "C3–C5",
          "Industrial, minimal, film", "Hold chords", "RHYTHM",
          "The ring clicks with the beat; pattern B is the dotted one")
    out.append(p)

    p = M("DOPPLER BLADES", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=1.0, unison=5, detune=0.15, width=0.4)
    p.osc(1, level=0.3, wt=0.9, fine=-7)
    p.filter("LP24", hz=1600, res=0.2, keytrack=0.3, drive=0.3)
    p.filter2("HP12", hz=180)
    p.feedback(amount=0.12, drive=0.5, tone=0.6)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("abcdcbabcdcbabcd", {"a": (-1.0, "GLIDE"), "b": (-0.3, "GLIDE"), "c": (0.3, "GLIDE"), "d": (1.0, "GLIDE")})}, rate="1/16")
    p.set("macro2", 0.55)
    p.motion("PERF1", "PAN", 0.5)
    p.motion("PERF1", "CUTOFF", 0.2)
    hall(p, mix=0.12)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("Chords spinning past like blades: pan and filter swinging on the grid", "C3–C5",
          "Industrial, trailer, drum and bass", "Hold chords", "RHYTHM",
          "Wide in motion but centred on average; check mono, it holds up")
    out.append(p)

    p = M("TREMOR", "PWM", "ANALOG")
    p.osc(0, level=0.6, wt=0.4, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.35, wt=0.9)
    p.filter("LP24", hz=2000, res=0.15, keytrack=0.3, drive=0.35)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.lfo(1, "SINE", sync="1/32", mode="FREE")
    p.lfo(2, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.set("macro2", 0.55)
    p.motion("LFO1", "AMP", 0.45)
    p.motion("LFO2", "CUTOFF", 0.2)
    p.motion("LFO2", "LFO1_RATE", 0.2)
    hall(p, mix=0.14)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("A chord shaking with a fast tremolo whose speed and tone jump every eighth", "C3–C5",
          "Industrial, horror, noise", "Hold chords under something steady", "TEXTURE",
          "Nervous by design; MOTION scales the jumps")
    out.append(p)

    p = M("OFFBEAT ENGINE", "ANALOG", "DIGITAL")
    p.osc(0, level=0.6, wt=0.9, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.3, wt=0.5)
    p.insert(1, "BITCRUSH", after=True, amount=0.4, mix=0.3)
    p.filter("LP24", hz=2600, res=0.15, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: gate_seq("--x---x---x---x-"), 1: gate_seq("--xx--xx--xx--xx"),
                    2: gate_seq("-xx--xx--xx--xxx"), 3: gate_seq("--x-x-x---x-x-xx")}, rate="1/16")
    switchable(p)
    p.set("macro2", 0.8)
    p.motion("PERF1", "AMP", 0.95)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.1)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("Off-beat chord stabs, crushed, with four patterns on the switch keys", "C3–C5",
          "Industrial techno, EBM, dub-noir", "Hold chords; stabs land between the kicks", "RHYTHM",
          "The gaps leave the kick alone; no sidechain needed")
    out.append(p)

    p = M("BITSTREAM", "DIGITAL", "ANALOG")
    p.osc(0, level=0.6, wt=0.5, unison=3, detune=0.1, width=0.5)
    p.osc(1, level=0.3, wt=0.9)
    p.insert(1, "BITCRUSH", after=True, amount=0.15, mix=0.7)
    p.filter("LP24", hz=2800, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: accents("XoXxoXoxXoXxoXXx", "HOLD")}, rate="1/32", steps=16)
    p.set("macro2", 0.5)
    p.motion("PERF1", "INS1_AMOUNT", 0.7)
    p.motion("PERF1", "CUTOFF", 0.2)
    hall(p, mix=0.1)
    grit(p, mode="BITCRUSH", drive=0.35, tone=0.5, amount=0.35, base=0.2)
    p.doc("A chord streamed through a failing data line: bit depth flickering in thirty-seconds", "C3–C5",
          "Glitch, IDM, industrial", "Hold chords", "TEXTURE",
          "Busy in the top end; a low-pass at 8 kHz on the bus keeps it off the hats")
    out.append(p)

    p = M("SHIFT SWARM", "ANALOG", "GLASS")
    p.osc(0, level=0.6, wt=0.7, unison=3, detune=0.1, width=0.5)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.5, mix=0.45)
    p.filter("LP24", hz=3000, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("abcdabceabcdabcf", {"a": (0.0, "GLIDE"), "b": (0.3, "GLIDE"), "c": (-0.3, "GLIDE"), "d": (0.6, "GLIDE"), "e": (-0.6, "GLIDE"), "f": (0.9, "GLIDE")})},
                rate="1/16")
    p.set("macro2", 0.5)
    p.motion("PERF1", "INS1_FREQ", 0.12)
    hall(p, mix=0.14)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.15)
    p.context(unpitched=True)
    p.doc("A chord with a shifted swarm sliding up and down around it in sixteenths", "C3–C5",
          "Sci-fi, industrial, experimental, horror", "Hold chords", "TEXTURE",
          "Inharmonic by nature; keep the chord simple and let the swarm do the rest")
    out.append(p)

    p = M("BLOOD PUMP", "ANALOG", "BASIC")
    p.osc(0, level=0.6, wt=0.8, unison=3, detune=0.1, width=0.4)
    p.osc(1, level=0.35, wt=0.0, octave=-1)
    p.filter("LP24", hz=1200, res=0.2, keytrack=0.3, drive=0.35)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("xx--------------", {"x": (0.0, "HOLD")}, (-1.0, "HOLD")),
                    1: seq("xx------xx------", {"x": (0.0, "HOLD")}, (-1.0, "HOLD"))}, rate="1/16")
    p.performer(2, {0: seq("Xx--------------", {"X": (1.0, "DECAY"), "x": (0.7, "DECAY")})}, rate="1/16")
    p.set("macro2", 0.7)
    p.motion("PERF1", "AMP", 0.85)
    p.motion("PERF2", "CUTOFF", 0.3)
    hall(p, mix=0.14)
    grit(p, mode="TUBE", drive=0.4, tone=0.45, amount=0.35, base=0.2)
    p.doc("A chord that beats like a heart: lub-dub once a bar (twice on pattern B)", "C3–C5",
          "Horror, thriller, film, dark ambient", "Hold chords; set the tempo to the heart rate you want", "RHYTHM",
          "At 60–80 BPM it is a resting heart; push the tempo for panic")
    out.append(p)

    p = M("CHAIN GANG", "SPECTRAL_COMB", "ANALOG")
    p.osc(0, level=0.6, wt=0.4, unison=3, detune=0.1, width=0.5)
    p.osc(1, level=0.3, wt=0.9, octave=-1)
    p.insert(1, "COMB", after=True, amount=0.6, freq=0.75, mix=0.4)
    p.filter("LP24", hz=2000, res=0.15, keytrack=0.3)
    p.filter2("HP12", hz=180)
    p.feedback(amount=0.15, drive=0.6, tone=0.6)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: accents("X--x--X-X--x--x-", "DECAY"), 1: accents("X-xX-xX-xX-xX-x-", "DECAY")}, rate="1/16")
    p.set("macro2", 0.55)
    p.motion("PERF1", "FEEDBACK", 0.4)
    p.motion("PERF1", "INS1_AMOUNT", 0.3)
    hall(p, mix=0.12)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("Chords struck like chains: feedback and a comb flaring on a work-song rhythm", "C3–C5",
          "Industrial, blues-noir, film", "Hold chords under a slow beat", "RHYTHM",
          "The flares are loud for a moment; a slow compressor keeps them even")
    out.append(p)

    p = M("DEAD AIR MORSE", "BASIC", "PWM")
    p.osc(0, level=0.6, wt=0.2, unison=3, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.noise(0.05, type="CRACKLE", color=0.5, keytrack=False)
    p.insert(1, "DECIMATE", after=True, amount=0.2, mix=0.4)
    p.filter("BP", hz=1400, res=0.2, keytrack=0.3)
    p.filter2("HP12", hz=250)
    p.env(1, a=0.003, d=1.0, s=0.9, r=0.2)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.08)
    p.performer(1, {0: gate_seq("x-x-xxx-x-------"), 1: gate_seq("xxx-x-xxx-------")}, rate="1/16")
    p.set("macro2", 0.75)
    p.motion("PERF1", "AMP", 0.95)
    echo(p, time="3/16", mix=0.16, feedback=0.4, amount=0.14)
    p.doc("A chord keyed like morse code over a dead radio channel, then silence", "C3–C5",
          "Film, sci-fi, thriller, ambient", "Hold chords; half of every bar is empty", "TEXTURE",
          "The empty half is for something else to answer it")
    out.append(p)

    p = M("TIDAL MACHINE", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=1.0, unison=5, detune=0.15, width=0.5)
    p.osc(1, level=0.3, wt=0.9, octave=1)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.4)
    p.filter("LP24", hz=1200, res=0.2, keytrack=0.3, drive=0.3)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: seq("aaaaaaaabbbbbbbb", {"a": (-0.7, "GLIDE"), "b": (0.8, "GLIDE")})}, rate="1/8")
    p.performer(2, {0: gate_seq("x.x.x.x.x.x.xxx.")}, rate="1/16")
    p.set("macro2", 0.6)
    p.motion("PERF1", "CUTOFF", 0.35)
    p.motion("PERF2", "AMP", 0.6)
    hall(p, mix=0.14)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.35, base=0.2)
    p.doc("A slow two-bar tide under a fast sixteenth pulse: two performers against each other", "C3–C5",
          "Progressive, industrial, trailer", "Hold chords for two bars", "RHYTHM",
          "Performer 1 is the tide, 2 the pulse; MOTION scales both")
    out.append(p)

    p = M("CONVULSION", "DIGITAL", "ANALOG")
    p.osc(0, level=0.6, wt=0.5, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.35, wt=1.0, fine=8)
    p.insert(1, "BITCRUSH", after=True, amount=0.4, mix=0.4)
    p.insert(2, "FOLD", amount=0.2, mix=0.5)
    p.filter("LP24", hz=2400, res=0.15, keytrack=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.003, d=1.0, s=0.9, r=0.2)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.18)
    p.performer(1, {0: gate_seq("xx-x-xxx--x-x-xx"), 1: gate_seq("x.x.xx-xx-.x-xxx"),
                    2: gate_seq("xxxx--xx--x-x---"), 3: gate_seq("x-xx.x-xxx.x-x.x")}, rate="1/16")
    p.performer(2, {0: accents("XxoXxoXxXoXxoXXo", "DECAY")}, rate="1/16")
    switchable(p)
    p.set("macro2", 0.75)
    p.motion("PERF1", "AMP", 0.9)
    p.motion("PERF2", "INS1_AMOUNT", 0.45)
    echo(p, time="1/16", mix=0.08, feedback=0.2, amount=0.1)
    grit(p, mode="HARD", drive=0.45, tone=0.5, amount=0.4, base=0.25)
    p.doc("Chords in spasm: a broken gate and a crush sequence fighting each other; four patterns", "C3–C5",
          "Industrial, breakcore, glitch, trailer", "Hold chords; switch patterns with the keys for fills", "RHYTHM",
          "The most violent motion preset. MOTION halfway is still usable under a vocal")
    out.append(p)

    return out
