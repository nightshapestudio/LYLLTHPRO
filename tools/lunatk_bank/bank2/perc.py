"""PERC: industrial hits. Kicks that clip and fold, snares with metal in
them, clangs, crushed hats. Peak-normalized like drum samples; MOTION is each
hit's variation or punch."""

from lunatk import Preset
from bank2._common import grit, space


def X(name, a="BASIC", b="BASIC"):
    return Preset(name, "PERC", a, b)


def hit(p, voices=4, vel=0.8):
    return p.voice(voices=voices, glide=0.0, legato=False, vel=vel, bend=2)


def room(p, mix=0.08, decay=0.2, amount=0.16, width=0.5):
    return space(p, mix, mode="PLATE", size=0.35, decay=decay, damp=0.55, predelay=0.02, width=width, amount=amount)


def burst(p, env=3, seconds=0.004, amount=1.0):
    """A noise click from its own envelope."""
    p.env(env, a=0.0005, d=seconds, s=0.0, r=seconds)
    return p.mod(f"ENV{env}", "NOISE_LEVEL", amount)


BACKBEAT = [(1, 110), (3, 105), (5, 110), (7, 100), (7.75, 70)]
HATS = [(i * 0.5, 110 if i % 2 == 0 else 80) for i in range(16)]


def presets():
    out = []

    p = X("PISTON KICK")
    p.osc(0, level=0.9, wt=0.0)
    p.noise(0.0, "WHITE", color=0.3, keytrack=False)
    burst(p, 3, 0.005, 0.6)
    p.insert(1, "FOLD", after=True, amount=0.25, mix=0.5)
    p.filter("LP24", hz=5000, res=0.05, drive=0.3)
    p.env(1, a=0.0005, d=0.35, s=0.0, r=0.3, dcurve=-0.5)
    p.env(4, a=0.0005, d=0.05, s=0.0, r=0.03, dcurve=-0.4)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit(p, voices=1)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.3)
    p.tone("NOISE_LEVEL", 0.35)
    room(p, mix=0.04)
    grit(p, mode="HARD", drive=0.45, tone=0.5, amount=0.5, base=0.3)
    p.context(note=36, unpitched=True)
    p.doc("A folded, clipped kick for machine rhythms", "Tune around C1–G1", "Industrial, EBM, industrial techno, hip-hop",
          "One note per hit; the note sets the tuning", "RHYTHM",
          "MOTION is the pitch-drop punch; hard hits fold more. Keep the bass off 50–70 Hz")
    out.append(p)

    p = X("BLOWN KICK")
    p.osc(0, level=0.9, wt=0.1)
    p.noise(0.0, "PINK", color=0.4, keytrack=False)
    burst(p, 3, 0.008, 0.45)
    p.filter("LP24", hz=1200, res=0.3, keytrack=0.3, drive=0.4)
    p.feedback(amount=0.25, drive=0.8, tone=0.4)
    p.env(1, a=0.0005, d=0.55, s=0.0, r=0.4, dcurve=-0.4)
    p.env(4, a=0.0005, d=0.07, s=0.0, r=0.04, dcurve=-0.4)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit(p, voices=1)
    p.mod("VELOCITY", "FEEDBACK", 0.25)
    p.tone("CUTOFF", 0.2)
    room(p, mix=0.04)
    grit(p, mode="TUBE", drive=0.55, tone=0.45, amount=0.45, base=0.4)
    p.context(note=36, unpitched=True)
    p.doc("A kick through a blown speaker: long, saturated, the tail growling", "Tune around C1–G1",
          "Industrial rock, trap, noise, trailer", "Sparse hits with room to ring", "RHYTHM",
          "It is kick and sub at once; drop the bass under it or sidechain hard")
    out.append(p)

    p = X("ANVIL SNARE")
    p.osc(0, level=0.5, wt=0.33)
    p.noise(0.6, "WHITE", color=0.3, keytrack=False)
    p.insert(1, "COMB", after=True, amount=0.6, freq=0.75, mix=0.35)
    p.filter("HP12", hz=180, res=0.1)
    p.filter2("LP12", hz=8000)
    p.env(1, a=0.0005, d=0.2, s=0.0, r=0.18, dcurve=-0.5)
    p.env(4, a=0.0005, d=0.03, s=0.0, r=0.02)
    p.mod("ENV4", "PITCH", 0.3)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.motion("LFO1", "INS1_FREQ", 0.1)
    p.motion("LFO1", "NOISE_COLOR", 0.15)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.2)
    p.tone("F2_CUTOFF", 0.2)
    room(p, mix=0.1)
    grit(p, mode="HARD", drive=0.45, tone=0.5, amount=0.45, base=0.3)
    p.context(note=50, pattern=BACKBEAT, unpitched=True, allow_air=True)
    p.doc("A snare with an anvil in it: noise, a short body and a metal ring", "Around D2", "Industrial rock, EBM, trailer",
          "Backbeats; the ring changes hit to hit on MOTION", "RHYTHM",
          "The ring is at 1–3 kHz; it cuts through guitars without extra level")
    out.append(p)

    p = X("CRUSHED SNARE")
    p.osc(0, level=0.45, wt=0.0)
    p.noise(0.7, "WHITE", color=0.25, keytrack=False)
    p.insert(1, "BITCRUSH", after=True, amount=0.65, mix=0.6)
    p.insert(2, "DECIMATE", after=True, amount=0.35, mix=0.5)
    p.filter("HP12", hz=200, res=0.1)
    p.filter2("LP12", hz=6000)
    p.env(1, a=0.0005, d=0.18, s=0.0, r=0.15, dcurve=-0.5)
    p.env(4, a=0.0005, d=0.025, s=0.0, r=0.02)
    p.mod("ENV4", "PITCH", 0.3)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.motion("LFO1", "INS2_AMOUNT", 0.35)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.2)
    p.tone("F2_CUTOFF", 0.2)
    room(p, mix=0.08)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.4, base=0.2)
    p.context(note=50, pattern=BACKBEAT, unpitched=True, allow_air=True)
    p.doc("A snare ground down to bits and aliasing", "Around D2", "Industrial, glitch, hip-hop, breakbeat",
          "Backbeats and ghost notes", "RHYTHM", "Each hit crushes differently on MOTION; hard velocity adds noise")
    out.append(p)

    p = X("SHEET METAL", "SPECTRAL_COMB", "BASIC")
    p.osc(0, level=0.4, wt=0.6)
    p.noise(0.5, "METAL", color=0.3, pitch=0.6, keytrack=True)
    p.insert(1, "RING", after=True, amount=0.7, freq=0.683, mix=0.5)
    p.insert(2, "COMB", after=True, amount=0.6, freq=0.6, mix=0.3)
    p.filter("HP12", hz=300, res=0.1)
    p.env(1, a=0.0005, d=0.6, s=0.0, r=0.5, dcurve=-0.6)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.motion("LFO1", "INS1_FREQ", 0.08)
    p.motion("LFO1", "NOISE_PITCH", 0.15)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.2)
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.12, decay=0.25)
    grit(p, mode="SOFT", drive=0.35, tone=0.5, amount=0.35, base=0.15)
    p.context(note=60, pattern=[(0, 110), (1.5, 90), (3, 105), (4, 110), (5.5, 85), (7, 100)], unpitched=True, allow_air=True)
    p.doc("A sheet of metal struck and ringing, inharmonic and different every hit", "Any; C3–C5 reads as a clang",
          "Industrial, film, horror, percussion ensembles", "Accents and fills; play different notes for different sheets", "RHYTHM",
          "Rings for half a second: sparse accents, not every beat")
    out.append(p)

    p = X("HAMMER TOM")
    p.osc(0, level=0.85, wt=0.0)
    p.noise(0.0, "PINK", color=0.5, keytrack=False)
    burst(p, 3, 0.006, 0.4)
    p.insert(1, "SINE", after=True, amount=0.3, mix=0.6)
    p.filter("LP24", hz=3000, res=0.05, keytrack=0.4)
    p.env(1, a=0.0005, d=0.4, s=0.0, r=0.3, dcurve=-0.5)
    p.env(4, a=0.0005, d=0.08, s=0.0, r=0.05)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 0.6, aux="MACRO2")
    hit(p)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.3)
    p.tone("INS1_AMOUNT", 0.25)
    room(p, mix=0.1)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.4, base=0.2)
    p.context(note=43, pattern=[(0, 110), (0.5, 90), (1, 100), (2, 110), (3, 100), (3.5, 90), (4, 110), (6, 100), (7, 110)], unpitched=True)
    p.doc("A tuned tom struck with a hammer: pitch-dropping thud with a wrinkled tone", "C1–C3; play fills across notes",
          "Industrial, tribal-noir, trailer", "Tom fills and tribal patterns across several notes", "RHYTHM",
          "MOTION sets the pitch drop; velocity the wrinkle")
    out.append(p)

    p = X("STATIC HAT")
    p.osc(0, level=0.0, wt=0.0, on=False)
    p.noise(0.8, "DIGITAL", color=0.2, pitch=0.8, keytrack=False)
    p.insert(1, "DECIMATE", after=True, amount=0.3, mix=0.5)
    p.filter("HP24", hz=6000, res=0.1)
    p.env(1, a=0.0005, d=0.05, s=0.0, r=0.04, dcurve=-0.5)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/16", mode="FREE")
    p.motion("LFO1", "INS1_AMOUNT", 0.35)
    p.motion("LFO1", "NOISE_PITCH", 0.15)
    p.mod("VELOCITY", "ENV1_DECAY", 0.2)
    p.tone("CUTOFF", 0.1)
    grit(p, mode="HARD", drive=0.35, tone=0.6, amount=0.35, base=0.15)
    p.context(note=60, pattern=HATS, unpitched=True, allow_air=True)
    p.doc("A digital hi-hat: static and aliasing, each hit a little different", "Any", "Industrial, glitch, techno, hip-hop",
          "Eighths and sixteenths", "RHYTHM", "Very bright: it sits above everything at a low level")
    out.append(p)

    p = X("CHAIN SHAKE")
    p.osc(0, level=0.0, wt=0.0, on=False)
    p.noise(0.8, "METAL", color=0.3, pitch=0.7, keytrack=False)
    p.insert(1, "COMB", after=True, amount=0.5, freq=0.7, mix=0.3)
    p.filter("BP", hz=4500, res=0.2)
    p.filter2("HP12", hz=1500)
    p.env(1, a=0.003, d=0.2, s=0.0, r=0.15)
    hit(p)
    p.set("macro2", 0.45)
    p.lfo(1, "SAMPLE_HOLD", sync="1/16", mode="FREE")
    p.motion("LFO1", "CUTOFF", 0.2)
    p.motion("LFO1", "NOISE_PITCH", 0.2)
    p.mod("VELOCITY", "ENV1_DECAY", 0.2)
    p.tone("CUTOFF", 0.1)
    room(p, mix=0.08)
    grit(p, mode="SOFT", drive=0.3, tone=0.6, amount=0.35, base=0.15)
    p.context(note=60, pattern=HATS, unpitched=True, allow_air=True)
    p.doc("Chains shaken in rhythm: metal jangle that changes every step", "Any", "Industrial, work-song, film, trip-hop",
          "Shaker patterns in eighths or sixteenths", "RHYTHM", "Use it instead of a shaker for grime")
    out.append(p)

    p = X("GLASS BREAK", "GLASS", "GLASS")
    p.osc(0, level=0.5, wt=0.8)
    p.osc(1, level=0.3, wt=0.4, octave=1)
    p.noise(0.3, "WHITE", color=0.2, keytrack=False)
    burst(p, 3, 0.01, 0.6)
    p.insert(1, "SHIFT", after=True, amount=1.0, freq=0.6, mix=0.4)
    p.filter("HP12", hz=800, res=0.1)
    p.env(1, a=0.0005, d=0.35, s=0.0, r=0.3, dcurve=-0.6)
    hit(p)
    p.set("macro2", 0.45)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.motion("LFO1", "INS1_FREQ", 0.1)
    p.motion("LFO1", "A_WTPOS", 0.2)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.2)
    p.tone("CUTOFF", 0.12)
    room(p, mix=0.12, decay=0.25)
    grit(p, mode="SOFT", drive=0.3, tone=0.6, amount=0.3, base=0.1)
    p.context(note=72, pattern=[(0, 110), (2, 100), (4, 110), (6, 100), (7.5, 80)], unpitched=True, allow_air=True)
    p.doc("A pane of glass breaking: a burst and inharmonic shards", "Any; higher notes are smaller panes",
          "Film, horror, industrial, sound design", "Accents and impacts", "TRANSITION",
          "Place it on a cut or a downbeat; it layers well over a snare")
    out.append(p)

    p = X("RIVET CLICK")
    p.osc(0, level=0.4, wt=0.33)
    p.noise(0.5, "WHITE", color=0.2, keytrack=False)
    p.insert(1, "COMB", amount=0.85, freq=0.5, mix=0.7)
    p.insert(2, "BITCRUSH", after=True, amount=0.5, mix=0.3)
    p.filter("HP12", hz=1200, res=0.1)
    p.env(1, a=0.0005, d=0.06, s=0.0, r=0.05)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/16", mode="FREE")
    p.motion("LFO1", "INS2_AMOUNT", 0.35)
    p.motion("LFO1", "NOISE_COLOR", 0.3)
    p.motion("LFO1", "INS1_FREQ", 0.1)
    p.motion("LFO1", "CUTOFF", 0.15)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.2)
    p.tone("CUTOFF", 0.1)
    p.context(note=84, pattern=HATS, unpitched=True, allow_air=True)
    p.doc("A rivet gun click: tiny, tuned, a little crushed", "C4–C7 sets the pitch of the click",
          "Industrial, IDM, minimal, glitch", "Fast patterns; use as a hat or a tick", "RHYTHM",
          "Tiny: it adds articulation to a beat, not weight")
    out.append(p)

    p = X("BODY BLOW")
    p.osc(0, level=0.8, wt=0.0)
    p.noise(0.3, "BROWN", color=0.6, keytrack=False)
    burst(p, 3, 0.01, 0.5)
    p.insert(1, "SINE", after=True, amount=0.3, mix=0.5)
    p.filter("LP24", hz=900, res=0.1, drive=0.35)
    p.env(1, a=0.0005, d=0.25, s=0.0, r=0.2, dcurve=-0.5)
    p.env(4, a=0.0005, d=0.03, s=0.0, r=0.02)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 0.5, aux="MACRO2")
    hit(p)
    p.mod("VELOCITY", "CUTOFF", 0.2)
    p.tone("CUTOFF", 0.2)
    room(p, mix=0.1)
    grit(p, mode="TUBE", drive=0.45, tone=0.45, amount=0.4, base=0.3)
    p.context(note=40, pattern=[(0, 110), (1.5, 100), (3, 110), (4, 110), (5.5, 100), (7, 110)], unpitched=True)
    p.doc("A dull, heavy thump like a fist on a body: impact without a clear pitch", "Around E1–E2",
          "Film, fight scenes, industrial, trailer", "Impacts and heavy off-beats", "RHYTHM",
          "Layer under a snare for weight, or use alone for impacts")
    out.append(p)

    p = X("IRON CLAP")
    p.osc(0, level=0.0, wt=0.0, on=False)
    p.noise(0.8, "WHITE", color=0.3, keytrack=False)
    p.insert(1, "RING", after=True, amount=0.5, freq=0.72, mix=0.3)
    p.insert(2, "DECIMATE", after=True, amount=0.25, mix=0.4)
    p.filter("BP", hz=1600, res=0.2)
    p.env(1, a=0.0005, d=0.22, s=0.0, r=0.18, dcurve=-0.5)
    p.lfo(2, "SAW_DOWN", hz=60, mode="TRIG")
    p.mod("LFO2", "AMP", 0.6, aux="ENV3")
    p.env(3, a=0.0005, d=0.03, s=0.0, r=0.02)
    hit(p)
    p.set("macro2", 0.4)
    p.lfo(1, "SAMPLE_HOLD", sync="1/8", mode="FREE")
    p.motion("LFO1", "INS1_FREQ", 0.1)
    p.motion("LFO1", "CUTOFF", 0.1)
    p.mod("VELOCITY", "ENV1_DECAY", 0.2)
    p.tone("CUTOFF", 0.1)
    room(p, mix=0.12)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.4, base=0.2)
    p.context(note=60, pattern=BACKBEAT, unpitched=True, allow_air=True)
    p.doc("A clap with a metal ring and a broken sample rate; the flams are built in", "Any", "Industrial, EBM, hip-hop, techno",
          "Backbeats", "RHYTHM", "Layer with a snare for the classic industrial backbeat")
    out.append(p)

    return out
