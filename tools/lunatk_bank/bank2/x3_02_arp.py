"""ADD-ON 03 / BITING RHYTHMIC ARPS. Programmed like a drummer: anchors,
ghosts, accents, gaps, octave hits. Accents route velocity (the step level)
into tone, and the wheel makes the accented steps more vicious."""

from bank2._common import echo, velocity
from bank2._showcase import dimension, drift, fsat, punch
from bank2._x3 import N3, burn, poly, room, wheel
from bank2.show_arp import S, pattern


def A(name, a="ANALOG", b="BASIC"):
    return N3(name, "ARP", a, b)


def voice(p, d=0.2, s=0.3, r=0.07):
    p.env(1, a=0.001, d=d, s=s, r=r)
    return poly(p, vel=0.65)


def presets():
    out = []

    # 11 BITE SEQUENCE: 16 steps: note order via PLAYED + transposes,
    # octave displacement, ghosts, rests, a small contour (0 0 +7 0 | +12 ...).
    p = A("BITE SEQUENCE", "SYNC_SWEEP", "ANALOG")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.3, wt=1.0, octave=-1)
    p.filter("LP24", hz=1800, res=0.25, keytrack=0.5, env=0.45)
    fsat(p, "HARD", drive=0.4)
    p.filter2("HP12", hz=130)
    voice(p)
    p.env(2, a=0.001, d=0.09, s=0.15, r=0.05)
    punch(p, 0.5)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AaFaAO.aAaFxA.Oa", {"A": (1.0, 0.5, 0), "a": (0.45, 0.25, 0), "F": (0.8, 0.45, 7),
                                     "O": (0.9, 0.35, 12), "x": (0.75, 0.4, -12)}))
    velocity(p, 0.65, 0.3)
    p.mod("VELOCITY", "A_WTPOS", 0.35)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("A_WTPOS", 0.2), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_MIX", 0.4), ("CUTOFF", 0.2), ("ENV1_DECAY", -0.25), ("A_WTPOS", 0.3))
    p.mod("VELOCITY", "DIST_DRIVE", 0.3, aux="MODWHEEL")
    room(p)
    burn(p, "HARD", drive=0.45, base=0.3)
    p.doc("A biting sixteenth sequence built to lock with a kick: anchors, ghosts, a fifth, octave hits and two gaps, all with a sync snap",
          "C3–C5", "Industrial pop, dark dance", "Hold a note or a fifth under a four-on-the-floor", "RHYTHM",
          "Wheel: more drive, shorter notes, brighter, and the accents alone get a harder drive")
    out.append(p)

    # 12 STEEL RUNNER: repeated anchors + octave jumps + three signature steps.
    p = A("STEEL RUNNER", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.2, wt=0.4)
    p.filter("LP24", hz=1700, res=0.25, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=150)
    voice(p, d=0.22, s=0.35)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AaAaAaOaAaAa5a7O", {"A": (0.9, 0.45, 0), "a": (0.45, 0.3, 0), "O": (0.85, 0.5, 12),
                                     "5": (0.8, 0.45, 5), "7": (0.85, 0.5, 7)}))
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("B_WTPOS", 0.35), ("CUTOFF", 0.08)])
    wheel(p, ("RES", 0.25), ("B_LEVEL", 0.25), ("B_WTPOS", 0.4), ("DIST_MIX", 0.35))
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.25)
    p.context(unpitched=True)
    p.doc("Forward motion: repeated anchors, an octave hit, and a fourth-fifth-octave turn at the end of the bar that makes it a phrase",
          "C3–C5", "Industrial pop, synth rock", "Hold a note under vocals", "RHYTHM",
          "Wheel: a resonant metal layer steps in and its harmonics start moving")
    out.append(p)

    # 13 BLACK STROBE: short gated steps with strong velocity contrast.
    p = A("BLACK STROBE", "NS SCAR PULSE", "ANALOG")
    p.osc(0, level=0.55, wt=0.25)
    p.osc(1, level=0.3, wt=0.95, fine=6)
    p.filter("LP24", hz=2000, res=0.25, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=160)
    voice(p, d=0.12, s=0.1, r=0.04)
    p.arp(mode="UP", rate="1/16", octaves=2, gate=0.4)
    pattern(p, [(1.0, 0.3, 0), (0.3, 0.2, 0), (0.6, 0.25, 0), (0.3, 0.2, 0), (1.0, 0.3, 12), (0.3, 0.2, 0), (0.6, 0.25, 0), None,
                (1.0, 0.3, 0), (0.3, 0.2, 0), (0.7, 0.25, 0), (0.3, 0.2, 0), (1.0, 0.35, 12), None, (0.8, 0.3, 7), (0.4, 0.2, 0)])
    velocity(p, 0.7, 0.3)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("A_WTPOS", 0.35), ("CUTOFF", 0.08)])
    wheel(p, ("DIST_MIX", 0.45), ("A_WTPOS", 0.35), ("HYPER_MIX", 0.35))
    p.hyper(mix=0.0, detune=0.2, rate=0.4, voices=0.5)
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "ZEROSQUARE", drive=0.35, base=0.25)
    p.doc("A strobe in sixteenths: very short gated steps, hard accents against quiet ghosts, a scarred pulse and a rubbing saw",
          "C3–C5", "Dark dance, industrial pop", "Hold chords", "RHYTHM",
          "Wheel: zero-square drive and the scar get denser and the top widens through the hyper stage")
    out.append(p)

    # 14 MACHINE DESIRE: less rigid: short steps + longer notes; a
    # descending figure (0, -2 steps as -5/-7 within octaves).
    p = A("MACHINE DESIRE", "NS THROAT", "ANALOG")
    p.osc(0, level=0.55, wt=0.3)
    p.osc(1, level=0.3, wt=0.9)
    p.filter("LP24", hz=1500, res=0.25, keytrack=0.5, env=0.35)
    fsat(p, "SOFT", drive=0.4)
    p.filter2("HP12", hz=150)
    voice(p, d=0.35, s=0.4, r=0.12)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.85, swing=0.08)
    pattern(p, [(0.9, 0.9, 12), (0.4, 0.3, 0), (0.6, 0.3, 0), (0.8, 0.8, 7), None, (0.45, 0.3, 0), (0.75, 0.9, 5), (0.4, 0.3, 0),
                (0.9, 0.5, 0), (0.45, 0.3, 0), None, (0.7, 1.0, -5)])
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.29, [("A_WTPOS", 0.4), ("CUTOFF", 0.08)])
    wheel(p, ("CUTOFF", 0.3), ("FSAT_DRIVE", 0.35), ("DIST_MIX", 0.35))
    p.mod("VELOCITY", "RES", 0.2, aux="MODWHEEL")
    echo(p, time="3/16", mix=0.08, feedback=0.25, amount=0.1)
    burn(p, "TUBE", drive=0.45, base=0.22)
    p.context(unpitched=True)
    p.doc("A sexy, loose sequence: a twelve-step descent (octave, fifth, fourth, down a fourth) with long notes between short ones, a little swing",
          "C3–C5", "Dark pop, alt-dance", "Hold chords", "FOREGROUND",
          "Wheel: the filter opens, saturation rises and only the accents gain resonance")
    out.append(p)

    # 15 RAZOR GRID: a drummer's 16: downbeats, ghost notes, flams (+12 short),
    # small gaps, unexpected -12 hits.
    p = A("RAZOR GRID", "ANALOG", "NS SERPENT")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LP24", hz=1900, res=0.28, keytrack=0.5, env=0.45)
    p.filter2("HP12", hz=150)
    voice(p, d=0.18, s=0.25)
    punch(p, 0.5)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.75)
    pattern(p, [(1.0, 0.45, 0), (0.25, 0.15, 0), (0.5, 0.25, 0), (0.25, 0.15, 12), (0.95, 0.45, 0), None, (0.4, 0.2, 0), (0.85, 0.35, -12),
                (1.0, 0.45, 0), (0.25, 0.15, 0), (0.55, 0.3, 12), None, (0.95, 0.45, 0), (0.3, 0.15, 0), (0.6, 0.25, 7), (0.8, 0.35, 12)])
    velocity(p, 0.7, 0.3)
    p.mod("VELOCITY", "B_WTPOS", 0.35)
    p.set("macro2", 0.4)
    drift(p, 1, 0.39, [("B_WTPOS", 0.3), ("CUTOFF", 0.08)])
    wheel(p, ("RES", 0.25), ("DIST_MIX", 0.4), ("B_WIDTH", 0.6), ("ENV2_DECAY", -0.3))
    p.set("b.unison", 2)
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "HARD", drive=0.45, base=0.28)
    p.doc("A sixteen-step grid played like a drummer: accents, ghost notes, octave flams, gaps and an unexpected low hit",
          "C3–C5", "Industrial pop, electro-rock", "Hold a note or fifth", "RHYTHM",
          "Wheel: a harder snap, more resonance and drive, and the serpent layer spreads")
    out.append(p)

    # 16 VOLTAGE HOOK: a 2-bar signature line (32 steps impossible: 16 at 1/8
    # = two bars), key-safe intervals so it transposes with chords.
    p = A("VOLTAGE HOOK", "NS OBSIDIAN", "ANALOG")
    p.osc(0, level=0.55, wt=0.3, unison=2, detune=0.05, width=0.2)
    p.osc(1, level=0.28, wt=0.9, octave=-1)
    p.filter("LADDER", hz=1800, res=0.25, keytrack=0.5, env=0.35)
    fsat(p, "DIODE", drive=0.35)
    p.filter2("HP12", hz=140)
    voice(p, d=0.3, s=0.45, r=0.1)
    p.arp(mode="PLAYED", rate="1/8", octaves=1, gate=0.85)
    pattern(p, [(1.0, 0.7, 0), (0.6, 0.4, 0), (0.85, 0.6, 12), (0.6, 0.4, 7), (0.9, 0.8, 5), None, (0.7, 0.5, 7), (0.6, 0.4, 0),
                (1.0, 0.7, 0), (0.6, 0.4, 0), (0.85, 0.6, 12), (0.7, 0.5, 19), (0.95, 1.0, 17), None, (0.7, 0.5, 12), (0.6, 0.4, 7)])
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.31, [("A_WTPOS", 0.3), ("CUTOFF", 0.08)])
    wheel(p, ("B_LEVEL", 0.25), ("B_WTPOS", 0.45), ("DIST_MIX", 0.4))
    echo(p, time="3/16", mix=0.08, feedback=0.25, amount=0.1)
    burn(p, "TUBE", drive=0.45, base=0.25)
    p.context(unpitched=True)
    p.doc("A real hook: a two-bar eighth-note line that answers itself (octave, fifth, fourth; then up to the twelfth), built from intervals that follow any chord",
          "C3–C5", "Industrial pop, dark pop", "Hold one note per chord; the line transposes with it", "FOREGROUND",
          "Wheel: an octave-down layer steps in and the whole line gets dirtier")
    out.append(p)

    # 17 PANIC DISCO: density and velocity rise through the bar.
    p = A("PANIC DISCO", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LP24", hz=1700, res=0.25, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=150)
    voice(p)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(0.7, 0.6, 0), None, None, None, (0.75, 0.6, 12), None, (0.6, 0.4, 0), None,
                (0.8, 0.5, 0), (0.6, 0.3, 0), (0.85, 0.4, 12), (0.65, 0.3, 0), (0.9, 0.3, 7), (0.8, 0.25, 0), (1.0, 0.25, 12), (1.0, 0.2, 19)])
    velocity(p, 0.7, 0.3)
    p.mod("VELOCITY", "B_WTPOS", 0.4)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.25), ("CUTOFF", 0.08)])
    wheel(p, ("B_WTPOS", 0.4), ("DIST_MIX", 0.4), ("RES", 0.2))
    p.lfo(2, "SAMPLE_HOLD", sync="1/16", mode="FREE", smooth=True)
    p.mod("LFO2", "CUTOFF", 0.12, aux="MODWHEEL")
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "HARD", drive=0.45, base=0.28)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("Urgency without tempo change: the bar starts sparse and ends in a rush of short, loud steps climbing to the twelfth",
          "C3–C5", "Dark dance, industrial pop pre-choruses", "Hold a note", "RHYTHM",
          "Wheel: the fracture layer crushes harder and the filter starts jumping in sixteenths")
    out.append(p)

    # 18 IRON HEARTBEAT: anchor note on every other step; tension notes around.
    p = A("IRON HEARTBEAT", "ANALOG", "NS TENDON")
    p.osc(0, level=0.55, wt=0.95)
    p.osc(1, level=0.28, wt=0.2)
    p.filter("LP24", hz=1600, res=0.25, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=140)
    voice(p, d=0.25, s=0.35)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, S("AtAuAtAOAtAuA5Ax", {"A": (1.0, 0.45, 0), "t": (0.5, 0.3, 7), "u": (0.55, 0.3, 12),
                                     "O": (0.7, 0.4, 19), "5": (0.55, 0.3, 5), "x": (0.6, 0.35, -12)}))
    velocity(p, 0.65, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("B_WTPOS", 0.35), ("CUTOFF", 0.08)])
    wheel(p, ("B_WTPOS", 0.5), ("B_LEVEL", 0.2), ("DIST_MIX", 0.4))
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "DIODE", drive=0.45, base=0.25)
    p.doc("A heartbeat note on every other sixteenth with tension and release moving around it: fifth, octave, twelfth, fourth, the octave below",
          "C3–C5", "Industrial pop, dark dance", "Hold a note", "RHYTHM",
          "Wheel: the tendon folds harder around the anchor; the anchor stays solid")
    out.append(p)

    # 19 STATIC DANCER: tight timing, electrical grit from a 1/32 S&H into a
    # ring insert; the arp itself is plain-rhythm but tightly accented.
    p = A("STATIC DANCER", "ANALOG", "DIGITAL")
    p.osc(0, level=0.55, wt=0.95)
    p.osc(1, level=0.25, wt=0.5)
    p.noise(0.04, type="DIGITAL", color=0.6, keytrack=True)
    p.insert(2, "RING", after=True, amount=0.3, freq=0.6, mix=0.15)
    p.filter("LP24", hz=1900, res=0.25, keytrack=0.5, env=0.4)
    p.filter2("HP12", hz=150)
    voice(p)
    p.arp(mode="UPDOWN", rate="1/16", octaves=2, gate=0.7)
    pattern(p, [(1.0, 0.45, 0), (0.45, 0.3, 0), (0.7, 0.4, 0), (0.45, 0.3, 0), (0.95, 0.45, 0), (0.45, 0.3, 0), (0.75, 0.4, 12), None])
    velocity(p, 0.65, 0.28)
    p.lfo(1, "SAMPLE_HOLD", sync="1/32", mode="FREE", smooth=False)
    p.set("macro2", 0.4)
    p.motion("LFO1", "INS2_FREQ", 0.02)
    p.motion("LFO1", "NOISE_LEVEL", 0.04)
    drift(p, 2, 0.35, [("B_WTPOS", 0.3), ("CUTOFF", 0.08)])
    wheel(p, ("INS2_AMOUNT", 0.4), ("NOISE_LEVEL", 0.06), ("RES", 0.2), ("DIST_MIX", 0.35))
    room(p)
    burn(p, "BITCRUSH", drive=0.3, base=0.2)
    p.doc("A tight dance pattern with static in its skin: a ring and a digital crackle stepping at 1/32, never loosening the groove",
          "C3–C5", "Dark dance, glitch pop", "Hold chords", "RHYTHM",
          "Wheel: the ring and static intensify, resonance and crush rise; timing stays exact")
    out.append(p)

    # 20 NIGHTCLUB MACHINE: flagship dance-industrial arp: 14 steps with
    # rests, ties, octave and fifth movement; PERF1 (12 steps) moves the table.
    p = A("NIGHTCLUB MACHINE", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.55, wt=0.3, unison=2, detune=0.05, width=0.2)
    p.osc(1, level=0.28, wt=0.2, octave=-1)
    p.insert(1, "FOLD", after=True, amount=0.2, mix=0.3)
    p.filter("LADDER", hz=1700, res=0.28, keytrack=0.5, env=0.45)
    fsat(p, "DIODE", drive=0.4)
    p.filter2("HP12", hz=130)
    voice(p, d=0.25, s=0.35, r=0.08)
    punch(p, 0.45)
    p.arp(mode="PLAYED", rate="1/16", octaves=2, gate=0.85, swing=0.04)
    pattern(p, [(1.0, 0.55, 0), (0.4, 0.25, 0), (0.75, 0.45, 12), (0.4, 0.25, 0), (0.9, 0.9, 7), None, (0.6, 0.35, 0), (1.0, 0.55, 12),
                (0.45, 0.25, 0), (0.8, 0.45, 0), None, (0.6, 0.35, 19), (0.95, 0.8, 12), (0.5, 0.3, -12)])
    velocity(p, 0.85, 0.35)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.2)
    p.performer(1, {0: [(v, "GLIDE") for v in (0.0, 0.5, -0.3, 0.8, 0.2, -0.6, 0.6, -0.1, 0.9, 0.3, -0.4, 0.7)]}, mode="SONG", rate="1/16", steps=12)
    p.set("macro2", 0.45)
    p.mod("PERF1", "A_WTPOS", 0.35, aux="MACRO2")
    drift(p, 1, 0.23, [("CUTOFF", 0.06)])
    wheel(p, ("B_WTPOS", 0.5), ("INS1_AMOUNT", 0.35), ("DIST_MIX", 0.35), ("RES", 0.15))
    p.mod("MODWHEEL", "DIM_MIX", 0.35)
    dimension(p, mix=0.0, size=0.6)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.28)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("The flagship dance-industrial arp: a fourteen-step phrase with rests, a tie and octave/fifth/twelfth moves over a twelve-step timbre walk: a track's backbone from one chord",
          "C3–C5", "Industrial pop, dark dance, electro-rock", "Hold a chord for the whole section", "FOREGROUND",
          "Wheel: the grindstone opens, the fold bites, the top widens: same phrase, far more dangerous")
    out.append(p)

    return out
