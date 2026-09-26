from lunatk import Preset
from bank._common import echo, grit, space, velocity


def M(name, a="ANALOG", b="ANALOG"):
    return Preset(name, "MOTION", a, b)


def steps16(pattern, on=0.0, off=-1.0):
    """A 16-step pattern ('x' open, '-' shut, '.' half) as 32 drawn points."""
    assert len(pattern) == 16
    values = {"x": on, "-": off, ".": (on + off) / 2}
    out = []
    for c in pattern:
        out += [values[c], values[c]]
    return out


def levels16(values):
    """Sixteen levels (-1..1) as 32 drawn points: a step sequence."""
    assert len(values) == 16
    out = []
    for v in values:
        out += [v, v]
    return out


def gate(p, pattern, lfo=1, sync="1 BAR", depth=1.0, smooth=False):
    """Amplitude gate from a drawn pattern, scaled by MOTION."""
    p.lfo(lfo, "CUSTOM", sync=sync, mode="TRIG", smooth=smooth, points=steps16(pattern))
    return p.mod(f"LFO{lfo}", "AMP", depth, aux="MACRO2")


def bed(p, voices=8, vel=0.35):
    return p.voice(voices=voices, glide=0.0, vel=vel, bend=2)


def hall(p, mix=0.2, decay=0.32, amount=0.2):
    return space(p, mix, mode="HALL", size=0.55, decay=decay, damp=0.55, predelay=0.12, width=0.85, amount=amount)


def presets():
    out = []

    p = M("GATE CATHEDRAL", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=0.9, unison=5, detune=0.22, width=0.6)
    p.osc(1, level=0.35, wt=0.8, octave=1, unison=3, detune=0.15, width=0.5)
    p.filter("LP24", hz=3000, res=0.1, keytrack=0.4)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.02, d=1.0, s=0.9, r=0.4)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.8)
    gate(p, "x-xxx-x-xx-x-xxx")
    hall(p)
    grit(p, mode="SOFT", drive=0.35, tone=0.6, amount=0.4)
    p.master(0.6)
    p.doc("Supersaw chords chopped by a 16-step gate", "C3–C5", "Trance, progressive, big-room breakdowns",
          "Hold chords for a bar or more; start them on the downbeat", "RHYTHM",
          "The gate restarts with each chord, so play on the bar line. MOTION is gate depth; 0 is a plain pad")
    out.append(p)

    p = M("PISTON FIELD", "ANALOG", "PWM")
    p.osc(0, level=0.6, wt=0.85, unison=3, detune=0.12, width=0.5)
    p.osc(1, level=0.35, wt=0.3)
    p.filter("LP24", hz=700, res=0.25, keytrack=0.4, drive=0.2)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.01, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.4, 0.08)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.6)
    seq = [0.9, 0.2, 0.5, 0.2, 0.8, 0.2, 0.6, 0.3, 1.0, 0.2, 0.5, 0.2, 0.7, 0.4, 0.5, 0.2]
    p.lfo(1, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False, points=levels16([v * 2 - 1 for v in seq]))
    p.motion("LFO1", "CUTOFF", 0.18)
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    hall(p, mix=0.14)
    grit(p, mode="DIODE", drive=0.35, tone=0.5, amount=0.4)
    p.master(0.6)
    p.doc("Chords driven through a 16-step filter sequence, like a mechanical press", "C3–C5",
          "Industrial techno, EBM, midtempo, cyberpunk", "Hold chords a bar at a time", "RHYTHM",
          "The accents land on 1, 2.1 and 3: keep your hats off them or embrace the push. MOTION 0 stops the sequence")
    out.append(p)

    p = M("RUST CONVEYOR", "BASIC", "SPECTRAL_COMB")
    p.osc(0, level=0.5, wt=0.67)
    p.osc(1, level=0.3, wt=0.4)
    p.noise(0.25, "METAL", color=0.45, pitch=0.55, keytrack=True)
    p.filter("COMB_POS", cut=0.37, res=0.5, keytrack=1.0, mix=0.55)
    p.filter2("BP", hz=1600, res=0.25)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.4, 0.0)
    p.tone("F2_CUTOFF", 0.15)
    p.set("macro2", 0.75)
    gate(p, "x.-xx.-.x.-xx--.", smooth=False)
    p.lfo(2, "SAW_DOWN", sync="1/16", mode="TRIG")
    p.motion("LFO2", "F2_CUTOFF", 0.12)
    hall(p, mix=0.16)
    grit(p, mode="HARD", drive=0.35, tone=0.45, amount=0.4)
    p.eq(low=-8, low_hz=160)
    p.master(0.6)
    p.doc("Tuned metal rhythm, like a conveyor belt in the key of your chord", "C3–C5", "Industrial, techno, horror pulse",
          "Hold a chord; it clanks in time", "RHYTHM",
          "Band-passed around 1.6 kHz: it sits between the snare and the hats. MOTION 0 is a steady metallic drone")
    out.append(p)

    p = M("ARP CIRCUIT", "ANALOG", "ANALOG")
    p.osc(0, level=0.65, wt=0.9, unison=2, detune=0.08, width=0.35)
    p.osc(1, level=0.3, wt=0.5, octave=-1)
    p.filter("LP24", hz=900, res=0.2, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.001, d=0.2, s=0.2, r=0.12)
    p.env(2, a=0.001, d=0.12, s=0.0, r=0.1)
    p.arp("UPDOWN", rate="1/16", octaves=2, gate=0.55)
    bed(p)
    velocity(p, 0.5, 0.1)
    p.tone("CUTOFF", 0.15)
    p.lfo(1, "SINE", sync="2 BAR", mode="FREE")
    p.set("macro2", 0.4)
    p.motion("LFO1", "CUTOFF", 0.12)
    echo(p, time="3/16", mix=0.12, feedback=0.25, amount=0.12, pingpong=True)
    hall(p, mix=0.12)
    grit(p, mode="SOFT", drive=0.4, tone=0.55, amount=0.4)
    p.master(0.58)
    p.doc("Up-down 1/16 arpeggio over two octaves of whatever chord you hold", "C3–C5", "Synthwave, techno, trance, game",
          "Hold chords; the arp plays them. Turn ARP off for a plain pluck", "RHYTHM",
          "MOTION sweeps its filter over 2 bars; at 0 the arp stays at one brightness")
    out.append(p)

    p = M("GHOST ARP", "GLASS", "FM_BELL")
    p.osc(0, level=0.6, wt=0.35)
    p.osc(1, level=0.3, wt=0.3, octave=1)
    p.filter("LP12", hz=5000, res=0.05)
    p.filter2("HP12", hz=220)
    p.env(1, a=0.001, d=0.5, s=0.0, r=0.4)
    p.arp("RANDOM", rate="1/8", octaves=2, gate=0.7)
    bed(p)
    velocity(p, 0.5, 0.0)
    p.tone("A_WTPOS", 0.15)
    p.lfo(1, "SINE", hz=0.25, mode="FREE")
    p.set("macro2", 0.4)
    p.motion("LFO1", "A_WTPOS", 0.15)
    p.motion("LFO1", "DELAY_MIX", 0.12)
    echo(p, time="3/16", mix=0.2, feedback=0.3, amount=0.15, pingpong=True)
    hall(p, mix=0.2)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.eq(high=-3, high_hz=9000)
    p.master(0.6)
    p.doc("Glass notes picked at random from your chord, trailing echoes", "C4–C6", "Ambient, film, lo-fi, downtempo",
          "Hold a chord and let it wander; never the same twice, always in key", "TEXTURE",
          "Sits high and sparse; SPACE sets how far the echoes trail")
    out.append(p)

    p = M("PULSE BED", "ANALOG", "HARMONIC_SWEEP")
    p.osc(0, level=0.6, wt=0.55, unison=3, detune=0.15, width=0.55)
    p.osc(1, level=0.3, wt=0.3)
    p.filter("LP24", hz=1500, res=0.1, keytrack=0.4)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.3, d=1.0, s=0.9, r=0.8)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.15)
    p.pump(sync="1/8", depth=0.6 / 0.7, default=0.7, sharpness=2.5)
    hall(p, mix=0.22)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.6)
    p.doc("Soft pad pulsing in 1/8s: a cinematic heartbeat bed", "C3–C5", "Film, trailer, ambient techno, documentary",
          "Hold chords; start on the beat", "SUPPORT",
          "Makes an arrangement feel like it is moving without adding drums; MOTION 0 is a still pad")
    out.append(p)

    p = M("TIDAL SWELL", "ANALOG", "SPECTRAL_COMB")
    p.osc(0, level=0.6, wt=0.7, unison=4, detune=0.18, width=0.6)
    p.osc(1, level=0.3, wt=0.4)
    p.filter("LP24", hz=1400, res=0.12, keytrack=0.4)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.05, d=1.0, s=0.9, r=0.5)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.7)
    swell = [-1 + 2 * (i / 31) ** 2 for i in range(32)]
    p.lfo(1, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=True, points=swell)
    p.mod("LFO1", "AMP", 0.45 / 0.7, aux="MACRO2")
    p.motion("LFO1", "CUTOFF", 0.1)
    hall(p, mix=0.22)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.58)
    p.doc("Chords that swell up through each bar like a reversed note", "C3–C5", "Future garage, ambient, chillwave, film",
          "Hold chords across bars; start on the downbeat", "RHYTHM",
          "The swell peaks at the end of the bar, leading into the next downbeat. MOTION 0 is a flat pad")
    out.append(p)

    p = M("MORSE DATA", "DIGITAL", "GLASS")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.3, wt=0.5, octave=1)
    p.filter("LP12", hz=4000, res=0.08)
    p.filter2("HP12", hz=250)
    p.env(1, a=0.002, d=1.0, s=0.9, r=0.2)
    bed(p)
    velocity(p, 0.4, 0.0)
    p.tone("A_WTPOS", 0.2)
    p.set("macro2", 0.85)
    gate(p, "x-x--xx-x---x-x-")
    p.lfo(2, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False,
          points=levels16([0.2, 0, 0.6, 0, 0, 0.3, 0.8, 0, 0.4, 0, 0, 0, 0.9, 0, 0.5, 0]))
    p.motion("LFO2", "A_WTPOS", 0.2)
    echo(p, time="1/16", mix=0.1, feedback=0.2, amount=0.1)
    hall(p, mix=0.12)
    grit(p, mode="BITCRUSH", drive=0.3, tone=0.5, amount=0.35)
    p.eq(high=-3, high_hz=9000)
    p.master(0.56)
    p.doc("Irregular digital blips in the key of your chord, like a transmission", "C4–C6", "IDM, sci-fi score, minimal techno",
          "Hold a chord; the rhythm repeats every bar", "RHYTHM",
          "Keep it quieter than you think: a little goes a long way. MOTION 0 is a still digital pad")
    out.append(p)

    p = M("TRIPLET ENGINE", "ANALOG", "ANALOG")
    p.osc(0, level=0.6, wt=0.85, unison=3, detune=0.15, width=0.5)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.filter("LP24", hz=1800, res=0.15, keytrack=0.4, env=0.1)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.01, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.4, 0.08)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.8)
    # Triplet 8ths drawn over one beat (the "1/12" division is not a triplet).
    triplets = [0.0 if (i % 32) in set(range(0, 7)) | set(range(11, 18)) | set(range(22, 28)) else -1.0 for i in range(32)]
    p.lfo(1, "CUSTOM", sync="1/4", mode="TRIG", smooth=False, points=triplets)
    p.mod("LFO1", "AMP", 1.0, aux="MACRO2")
    hall(p, mix=0.16)
    grit(p, mode="SOFT", drive=0.35, tone=0.55, amount=0.4)
    p.master(0.58)
    p.doc("Chords gated in a rolling triplet pattern", "C3–C5", "Trap soul, afro-house, cinematic hip-hop",
          "Hold chords on the downbeat", "RHYTHM",
          "The triplet pushes against straight drums: great under a 4/4 groove. MOTION is gate depth")
    out.append(p)

    p = M("HEARTBEAT", "ANALOG", "BASIC")
    p.osc(0, level=0.6, wt=0.45, unison=2, detune=0.1, width=0.05)
    p.osc(1, level=0.35, wt=0.0)
    p.filter("LP24", hz=700, res=0.12, keytrack=0.4)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.02, d=1.0, s=0.9, r=0.5)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.8)
    beat = [0.0 if i in (0, 1, 2, 5, 6) else -1.0 for i in range(32)]
    p.lfo(1, "CUSTOM", sync="1/2", mode="TRIG", smooth=True, points=beat)
    p.mod("LFO1", "AMP", 1.0, aux="MACRO2")
    p.mod("LFO1", "CUTOFF", 0.08 / 0.8, aux="MACRO2")
    hall(p, mix=0.16)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.6)
    p.doc("A low double-pulse like a heartbeat, every half note", "C2–C4", "Thriller, horror, trailer, dark ambient",
          "Hold one low note or a fifth", "RHYTHM",
          "It is a clock for tension: works at 60–100 BPM. MOTION 0 is a steady dark drone")
    p.context(shift=-12)
    out.append(p)

    p = M("SPIRAL FILTER", "HARMONIC_SWEEP", "ANALOG")
    p.osc(0, level=0.6, wt=0.6, unison=4, detune=0.15, width=0.55)
    p.osc(1, level=0.3, wt=0.6, octave=1)
    p.filter("LP24", hz=900, res=0.25, keytrack=0.4)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.1, d=1.0, s=0.9, r=0.5)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.15)
    p.lfo(1, "SINE", sync="2 BAR", mode="TRIG", phase=0.75)
    p.lfo(2, "CUSTOM", sync="1/4", mode="TRIG", smooth=True, points=[-(i / 31.0) for i in range(32)])
    p.set("macro2", 0.6)
    p.motion("LFO1", "CUTOFF", 0.2)
    p.motion("LFO2", "AMP", 0.2)
    p.phaser(mix=0.2, rate=0.1, depth=0.5)
    hall(p, mix=0.18)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.58)
    p.doc("A 2-bar filter spiral with a soft quarter-note push", "C3–C5", "Progressive house, melodic techno, ambient",
          "Hold chords for two bars at a time", "RHYTHM",
          "The sweep opens across bar 1 and closes across bar 2; MOTION 0 stops both movements")
    out.append(p)

    p = M("CLOCKWORK", "GLASS", "BASIC")
    p.osc(0, level=0.6, wt=0.3)
    p.osc(1, level=0.25, wt=0.33, octave=1)
    p.filter("LP12", hz=4500, res=0.05, keytrack=0.3, env=0.2)
    p.filter2("HP12", hz=220)
    p.env(1, a=0.001, d=0.25, s=0.0, r=0.15)
    p.env(2, a=0.001, d=0.1, s=0.0, r=0.1)
    p.arp("PLAYED", rate="1/16", octaves=1, gate=0.4, swing=0.35)
    bed(p)
    velocity(p, 0.5, 0.1)
    p.tone("CUTOFF", 0.15)
    p.lfo(1, "SINE", sync="1 BAR", mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "A_WTPOS", 0.15)
    echo(p, time="1/8", mix=0.1, feedback=0.2, amount=0.1)
    hall(p, mix=0.12)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.6)
    p.doc("Swung 1/16 glass arpeggio in the order you play the notes", "C4–C6", "Downtempo, lo-fi house, UK garage, film",
          "Play the chord note by note in the order you want it arpeggiated", "RHYTHM",
          "Swing is built in (35%); line your hats' swing up with it")
    out.append(p)

    p = M("CHOPPED TAPE", "ANALOG", "BASIC")
    p.osc(0, level=0.6, wt=0.6, unison=2, detune=0.08, width=0.4)
    p.osc(1, level=0.3, wt=0.33)
    p.filter("LP12", hz=2000, res=0.1, keytrack=0.4)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.01, d=1.0, s=0.9, r=0.3)
    bed(p)
    velocity(p, 0.35, 0.06)
    p.tone("CUTOFF", 0.15)
    p.set("macro2", 0.75)
    gate(p, "xxx-xx-xxxx-x-x-")
    p.lfo(2, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False,
          points=levels16([0, 0, 0, 0, 0, 0, -0.5, 0, 0, 0, 0, 0, 0, -0.5, 0, 0]))
    p.motion("LFO2", "PITCH", 0.25)
    hall(p, mix=0.14)
    p.dist(mode="DOWNSAMPLE", drive=0.3, tone=0.45, mix=0.2)
    p.grit(("DIST_MIX", 0.45))
    p.eq(high=-4, high_hz=6500)
    p.master(0.58)
    p.doc("Chords chopped and dropping an octave twice a bar, like a sliced sample", "C3–C5", "Lo-fi, hip-hop, future beat, glitch pop",
          "Hold chords a bar at a time", "RHYTHM",
          "The octave drops on steps 7 and 14 give it a sampled-and-chopped feel; MOTION 0 is plain chords")
    out.append(p)

    p = M("OCEAN MACHINE", "SPECTRAL_COMB", "GLASS")
    p.osc(0, level=0.6, wt=0.3, unison=4, detune=0.15, width=0.6)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.filter("LP24", hz=2600, res=0.1, keytrack=0.3)
    p.filter2("HP12", hz=170)
    p.env(1, a=0.5, d=1.0, s=0.9, r=1.0)
    bed(p)
    velocity(p, 0.35, 0.05)
    p.tone("CUTOFF", 0.15)
    p.lfo(1, "SINE", sync="2 BAR", mode="TRIG")
    p.lfo(2, "SINE", sync="1/8", mode="FREE")
    p.set("macro2", 0.5)
    p.motion("LFO1", "A_WTPOS", 0.25)
    p.motion("LFO2", "PAN", 0.2)
    hall(p, mix=0.24)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.35)
    p.master(0.58)
    p.doc("Slow 2-bar tide with a quick 1/8 stereo shimmer on top", "C3–C5", "Ambient, chillout, deep house breakdowns",
          "Long chords", "TEXTURE",
          "The 1/8 panning adds life without rhythm clutter; MOTION 0 centres and stills it")
    out.append(p)

    p = M("VOLTAGE STEPS", "ANALOG", "BASIC")
    p.osc(0, level=0.65, wt=0.95)
    p.osc(1, level=0.3, wt=0.0, octave=-1)
    p.filter("LADDER", hz=500, res=0.5, keytrack=0.4, drive=0.3)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.005, d=1.0, s=0.9, r=0.2)
    bed(p)
    velocity(p, 0.4, 0.08)
    p.tone("CUTOFF", 0.18)
    p.set("macro2", 0.6)
    seq = [1.0, 0.1, 0.4, 0.1, 0.7, 0.1, 0.9, 0.3, 0.2, 0.6, 0.1, 0.8, 0.1, 0.4, 1.0, 0.2]
    p.lfo(1, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False, points=levels16([v * 2 - 1 for v in seq]))
    p.motion("LFO1", "CUTOFF", 0.2)
    p.lfo(2, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False, points=steps16("x-x-x-x-x-x-x-x-", on=0.0, off=-0.7))
    p.mod("LFO2", "AMP", 1.0, aux="MACRO2")
    echo(p, time="3/16", mix=0.1, feedback=0.25, amount=0.12)
    hall(p, mix=0.1)
    grit(p, mode="DIODE", drive=0.4, tone=0.5, amount=0.4)
    p.master(0.56)
    p.doc("Resonant chord sequence: 16 filter steps with 8th-note gates", "C3–C4", "Acid house, electro, techno",
          "Hold chords low; the sequence plays them", "RHYTHM",
          "TONE rides the whole sequence brighter or darker; MOTION 0 is held chords")
    out.append(p)

    p = M("SHIMMER TICKS", "GLASS", "GLASS")
    p.osc(0, level=0.55, wt=0.6, unison=3, detune=0.1, width=0.6)
    p.osc(1, level=0.3, wt=0.8, octave=1)
    p.filter("LP12", hz=7000, res=0.05)
    p.filter2("HP12", hz=400)
    p.env(1, a=0.2, d=1.0, s=0.9, r=0.6)
    bed(p)
    velocity(p, 0.35, 0.0)
    p.tone("A_WTPOS", 0.15)
    p.set("macro2", 0.7)
    p.lfo(1, "CUSTOM", sync="1/32", mode="FREE", smooth=True, points=[-(i / 31.0) ** 0.5 for i in range(32)])
    p.mod("LFO1", "AMP", 0.7 / 0.7, aux="MACRO2")
    hall(p, mix=0.22)
    grit(p, mode="SOFT", drive=0.3, tone=0.5, amount=0.3)
    p.eq(high=-4, high_hz=9000)
    p.master(0.58)
    p.doc("High glass shimmer flickering in 1/32s, like a hi-hat made of light", "C4–C7", "Pop, EDM, ambient, trap",
          "Hold high chords over the drop or verse", "TEXTURE",
          "High-passed at 400 Hz: it never touches the low mids. MOTION 0 is a static shimmer pad")
    p.context(shift=12)
    out.append(p)

    p = M("IRON RAIN", "BASIC", "BASIC")
    p.osc(0, level=0.0)
    p.set("a.on", 0)
    p.noise(0.6, "METAL", color=0.35, pitch=0.5, keytrack=True)
    p.filter("BP", cut=0.5, res=0.3, keytrack=1.0)
    p.filter2("HP12", hz=300)
    p.env(1, a=0.002, d=1.0, s=0.9, r=0.2)
    bed(p)
    velocity(p, 0.4, 0.0)
    p.tone("CUTOFF", 0.07)
    p.set("macro2", 0.8)
    points = []
    accents = [0.0, -0.8, -0.5, -0.8, -0.2, -0.8, -0.5, -0.8, 0.0, -0.8, -0.5, -0.4, -0.2, -0.8, -0.5, -0.8]
    for a in accents:
        points += [a, -1.0]
    p.lfo(1, "CUSTOM", sync="1 BAR", mode="TRIG", smooth=False, points=points)
    p.mod("LFO1", "AMP", 1.0, aux="MACRO2")
    hall(p, mix=0.16)
    grit(p, mode="HARD", drive=0.3, tone=0.45, amount=0.35)
    p.eq(high=-8, high_hz=7000)
    p.master(0.58)
    p.doc("Tuned metallic 16ths with accents, a percussive bed in the key", "C4–C6", "Industrial, dark techno, action score",
          "Hold one note or a fifth; it ticks in time", "RHYTHM",
          "Replaces a shaker or hat loop with something pitched; keep it under the real hats")
    p.context(shift=12)
    p.context(unpitched=True)
    out.append(p)

    p = M("CHORD STABBER", "ANALOG", "PWM")
    p.osc(0, level=0.6, wt=0.85, unison=2, detune=0.1, width=0.15)
    p.osc(1, level=0.35, wt=0.2)
    p.filter("LP24", hz=1100, res=0.15, keytrack=0.4, env=0.3)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.001, d=0.2, s=0.0, r=0.1)
    p.env(2, a=0.001, d=0.12, s=0.0, r=0.1)
    p.arp("CHORD", rate="1/8", octaves=1, gate=0.4, swing=0.2)
    bed(p)
    velocity(p, 0.5, 0.12)
    p.tone("CUTOFF", 0.15)
    p.lfo(1, "SINE", sync="1 BAR", mode="FREE")
    p.set("macro2", 0.35)
    p.motion("LFO1", "CUTOFF", 0.12)
    echo(p, time="3/16", mix=0.1, feedback=0.2, amount=0.12)
    hall(p, mix=0.12)
    grit(p, mode="SOFT", drive=0.45, tone=0.6, base=0.45, amount=0.35)
    p.master(0.58)
    p.doc("Holds your chord and restrikes it in swung 1/8 stabs", "C3–C5", "House, disco, UK garage, funk",
          "Hold chords; the arp restrikes them in time", "RHYTHM",
          "Turn ARP off to play the stabs yourself; MOTION sweeps the filter over each bar")
    out.append(p)

    return out
