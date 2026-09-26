import math

from lunatk import Preset
from bank._common import grit, space


def X(name, a="BASIC", b="BASIC"):
    return Preset(name, "PERC", a, b)


def hit_voice(p, voices=4, vel=0.8):
    return p.voice(voices=voices, glide=0.0, legato=False, vel=vel, bend=2)


def room(p, mix=0.1, decay=0.2, amount=0.18):
    return space(p, mix, mode="PLATE", size=0.35, decay=decay, damp=0.55, predelay=0.02, width=0.6, amount=amount)


def burst(p, env=3, seconds=0.004, amount=1.0):
    """A noise click from its own envelope."""
    p.env(env, a=0.0005, d=seconds, s=0.0, r=seconds)
    return p.mod(f"ENV{env}", "NOISE_LEVEL", amount)


def presets():
    out = []

    p = X("IRON KICK")
    p.osc(0, level=0.9, wt=0.0)
    p.noise(0.0, "WHITE", color=0.3, keytrack=False)
    burst(p, 3, 0.004, 0.6)
    p.filter("LP24", hz=6000, res=0.05)
    p.env(1, a=0.0005, d=0.32, s=0.0, r=0.32, dcurve=-0.5, rcurve=-0.5)
    p.env(4, a=0.0005, d=0.045, s=0.0, r=0.03, dcurve=-0.4)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit_voice(p, voices=1)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.3, aux="ENV3")
    p.tone("NOISE_LEVEL", 0.4)
    room(p, mix=0.05)
    grit(p, mode="SOFT", drive=0.4, tone=0.55, amount=0.6)
    p.master(0.7)
    p.doc("Punchy, tuned electronic kick with a clean click", "Tune to the song's key around C1–G1", "Techno, house, pop, hip-hop",
          "Play one note per hit; the note you play sets the tuning", "RHYTHM",
          "MOTION is the pitch-drop depth (punch), TONE the click; keep the bass out of its 50–70 Hz or sidechain it")
    p.context(note=36, unpitched=True)
    out.append(p)

    p = X("DEEP KICK")
    p.osc(0, level=0.9, wt=0.0)
    p.noise(0.0, "PINK", color=0.5, keytrack=False)
    burst(p, 3, 0.006, 0.35)
    p.filter("LP24", hz=3000, res=0.05)
    p.env(1, a=0.0005, d=0.7, s=0.0, r=0.6, dcurve=-0.35, rcurve=-0.35)
    p.env(4, a=0.0005, d=0.06, s=0.0, r=0.03, dcurve=-0.4)
    p.set("macro2", 0.4)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit_voice(p, voices=1)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.25, aux="ENV3")
    p.tone("NOISE_LEVEL", 0.3)
    room(p, mix=0.05)
    grit(p, mode="TUBE", drive=0.4, tone=0.5, amount=0.6)
    p.master(0.7)
    p.doc("Long, round sub kick with a soft attack", "Tune around C1–G1", "Deep techno, dub techno, trap, ambient techno",
          "Quarter notes, or sparse hits with room to ring", "RHYTHM",
          "It rings long: this is the bass in sparse tracks. Shorter release by playing shorter notes")
    p.context(note=36, unpitched=True)
    out.append(p)

    p = X("FURNACE KICK")
    p.osc(0, level=0.9, wt=0.15)
    p.noise(0.0, "WHITE", color=0.2, keytrack=False)
    burst(p, 3, 0.008, 0.5)
    p.filter("LP24", hz=4500, res=0.1, drive=0.3)
    p.env(1, a=0.0005, d=0.35, s=0.0, r=0.35, dcurve=-0.4, rcurve=-0.4)
    p.env(4, a=0.0005, d=0.05, s=0.0, r=0.03, dcurve=-0.4)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit_voice(p, voices=1)
    p.mod("VELOCITY", "DIST_DRIVE", 0.2)
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.05)
    grit(p, mode="HARD", drive=0.45, tone=0.45, base=0.45, amount=0.4)
    p.comp(mode="SINGLE", threshold=0.5, ratio=0.4, attack=0.15, release=0.2, gain=0.55, depth=0.6)
    p.master(0.62)
    p.doc("Overdriven industrial kick: hard, but still tuned and punchy", "Tune around C1–G1", "Industrial techno, hard techno, EBM, trap metal",
          "Four-on-the-floor or broken patterns", "RHYTHM",
          "Already distorted: it takes the place of a clean kick, not a layer; GRIT takes it further")
    p.context(note=36, unpitched=True)
    out.append(p)

    p = X("SNARE PLATE", "BASIC", "BASIC")
    p.osc(0, level=0.5, wt=0.2)
    p.noise(0.0, "WHITE", color=0.25, keytrack=False)
    p.env(3, a=0.0005, d=0.16, s=0.0, r=0.16, dcurve=-0.5, rcurve=-0.5)
    p.mod("ENV3", "NOISE_LEVEL", 0.9)
    p.route_filter(a=False, b=False, noise=True)
    p.filter("BP", hz=2600, res=0.1)
    p.filter2("HP12", hz=180)
    p.env(1, a=0.0005, d=0.2, s=0.0, r=0.2)
    p.env(4, a=0.0005, d=0.03, s=0.0, r=0.02)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 0.5, aux="MACRO2")
    hit_voice(p)
    p.mod("VELOCITY", "NOISE_LEVEL", 0.2, aux="ENV3")
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.14, decay=0.24)
    grit(p, mode="HARD", drive=0.4, tone=0.5, amount=0.5)
    p.master(0.64)
    p.doc("Tight synthetic snare: a tuned body under a bright crack", "Body tuned around G2–D3", "Pop, techno, electro, synthwave",
          "Backbeats and ghost notes at low velocity", "RHYTHM",
          "The crack sits at 2–3 kHz; SPACE for a bigger room, TONE to darken it under a vocal")
    p.context(note=43, unpitched=True)
    out.append(p)

    p = X("CLAP RUST", "BASIC", "BASIC")
    p.set("a.on", 0)
    p.noise(0.9, "WHITE", color=0.3, keytrack=False)
    p.filter("BP", hz=1500, res=0.2)
    p.filter2("HP12", hz=400)
    p.env(1, a=0.0005, d=0.22, s=0.0, r=0.22, dcurve=-0.6, rcurve=-0.6)
    strikes = []
    for i in range(32):
        strikes.append(0.0 if (i in (0, 3, 6) or i > 9) else -1.0)
    p.lfo(1, "CUSTOM", hz=12.0, mode="ENV", smooth=False, points=strikes)
    p.mod("LFO1", "AMP", 1.0)
    hit_voice(p)
    p.set("macro2", 0.4)
    p.motion("RANDOM", "CUTOFF", 0.15)
    p.motion("RANDOM", "ENV1_DECAY", 0.06)
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.16, decay=0.26)
    grit(p, mode="HARD", drive=0.35, tone=0.5, amount=0.5)
    p.master(0.64)
    p.doc("Three-strike hand clap with a rough edge", "Unpitched", "House, trap, pop, techno",
          "Backbeats; layer with a snare", "RHYTHM",
          "MOTION gives each clap a slightly different colour, like real hands")
    p.context(note=60, unpitched=True)
    out.append(p)

    p = X("RIM SPARK", "BASIC", "BASIC")
    p.osc(0, level=0.6, wt=0.67)
    p.noise(0.0, "WHITE", color=0.2, keytrack=False)
    burst(p, 3, 0.003, 0.7)
    p.filter("BP", hz=1800, res=0.3)
    p.filter2("HP12", hz=300)
    p.env(1, a=0.0005, d=0.06, s=0.0, r=0.04)
    p.env(4, a=0.0005, d=0.01, s=0.0, r=0.01)
    p.set("macro2", 0.4)
    p.mod("ENV4", "PITCH", 0.4, aux="MACRO2")
    hit_voice(p)
    p.mod("VELOCITY", "CUTOFF", 0.1)
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.12)
    grit(p, mode="HARD", drive=0.35, tone=0.5, amount=0.5)
    p.master(0.64)
    p.doc("Short woody rimshot click", "Tuned around C4", "Deep house, reggaeton, minimal, lo-fi",
          "Syncopated clicks and off-beats", "RHYTHM",
          "Tiny and bright: it cuts through at low level")
    p.context(note=60, unpitched=True)
    out.append(p)

    p = X("STEEL HAT")
    p.set("a.on", 0)
    p.noise(0.9, "METAL", color=0.15, pitch=0.65, keytrack=False)
    p.filter("HP24", hz=6500, res=0.1)
    p.env(1, a=0.0005, d=0.05, s=0.0, r=0.04, dcurve=-0.6)
    hit_voice(p, voices=1)
    p.mod("VELOCITY", "ENV1_DECAY", 0.15)
    p.set("macro2", 0.4)
    p.motion("RANDOM", "CUTOFF", 0.08)
    p.motion("RANDOM", "NOISE_PITCH", 0.1)
    p.tone("CUTOFF", 0.1)
    room(p, mix=0.08)
    grit(p, mode="BITCRUSH", drive=0.3, tone=0.6, amount=0.4)
    p.master(0.62)
    p.doc("Closed metallic hat; harder hits ring a little longer", "Unpitched", "Techno, house, trap, electro",
          "8ths and 16ths with velocity accents", "RHYTHM",
          "MOTION varies each hit so rolls sound played, not looped")
    p.context(note=60, unpitched=True, allow_air=True)
    out.append(p)

    p = X("OPEN STEEL")
    p.set("a.on", 0)
    p.noise(0.9, "METAL", color=0.2, pitch=0.6, keytrack=False)
    p.filter("HP24", hz=6000, res=0.1)
    p.env(1, a=0.001, d=0.4, s=0.0, r=0.4, dcurve=-0.4, rcurve=-0.4)
    hit_voice(p, voices=1)
    p.mod("VELOCITY", "ENV1_DECAY", 0.1)
    p.set("macro2", 0.35)
    p.motion("RANDOM", "NOISE_PITCH", 0.08)
    p.tone("CUTOFF", 0.1)
    room(p, mix=0.1)
    grit(p, mode="BITCRUSH", drive=0.3, tone=0.6, amount=0.4)
    p.master(0.6)
    p.doc("Open metallic hat that the next closed hit chokes (mono voice)", "Unpitched", "House, disco, techno, garage",
          "Off-beat opens; play STEEL HAT on the same track to choke it", "RHYTHM",
          "Mono by design: any new note cuts the ring, like a real hi-hat pedal")
    p.context(note=60, unpitched=True, allow_air=True)
    out.append(p)

    p = X("GRAIN SHAKER")
    p.set("a.on", 0)
    p.noise(0.9, "WHITE", color=0.25, keytrack=False)
    p.filter("BP", hz=5500, res=0.15)
    p.filter2("HP12", hz=2500)
    p.env(1, a=0.012, d=0.09, s=0.0, r=0.05, acurve=0.3)
    hit_voice(p)
    p.mod("VELOCITY", "ENV1_ATTACK", -0.1)
    p.set("macro2", 0.45)
    p.motion("RANDOM", "CUTOFF", 0.06)
    p.motion("RANDOM", "ENV1_DECAY", 0.05)
    p.tone("CUTOFF", 0.1)
    room(p, mix=0.1)
    grit(p, mode="SOFT", drive=0.3, tone=0.55, amount=0.4)
    p.eq(high=-4, high_hz=11000)
    p.master(0.62)
    p.doc("Soft grainy shaker with a swell on each hit", "Unpitched", "Afro-house, reggaeton, pop, lo-fi",
          "16ths with accents on the off-beats", "RHYTHM",
          "Sits under hats; MOTION humanizes every hit")
    p.context(note=60, unpitched=True, allow_air=True)
    out.append(p)

    p = X("BRASS TOM", "BASIC", "BASIC")
    p.osc(0, level=0.8, wt=0.12)
    p.noise(0.0, "PINK", color=0.5, keytrack=False)
    burst(p, 3, 0.01, 0.3)
    p.filter("LP24", hz=2500, res=0.08, keytrack=0.5)
    p.env(1, a=0.0005, d=0.45, s=0.0, r=0.45, dcurve=-0.5, rcurve=-0.5)
    p.env(4, a=0.0005, d=0.1, s=0.0, r=0.05)
    p.set("macro2", 0.4)
    p.mod("ENV4", "PITCH", 0.35, aux="MACRO2")
    hit_voice(p)
    p.mod("VELOCITY", "CUTOFF", 0.1)
    p.tone("CUTOFF", 0.15)
    room(p, mix=0.14, decay=0.24)
    grit(p, mode="TUBE", drive=0.35, tone=0.5, amount=0.5)
    p.master(0.66)
    p.doc("Tuned synth tom: play it melodically across an octave", "C2–C4", "Synthwave, 80s pop, cinematic drums, electro",
          "Fills down the keyboard; tuned to the note", "RHYTHM",
          "MOTION is the pitch bend on each hit; tune fills to the key")
    p.context(note=48, pattern=[(0, 110), (1, 100), (1.5, 90), (2, 110), (3, 100), (4, 110), (4.5, 90), (5, 100), (6, 110), (7, 100)])
    out.append(p)

    p = X("ANVIL STRIKE", "FM_BELL", "BASIC")
    p.osc(0, level=0.6, wt=0.6, warp="RM", warp_amt=0.4)
    p.osc(1, level=0.002, wt=0.0, octave=1, semi=6)
    p.noise(0.0, "METAL", color=0.3, pitch=0.6, keytrack=True)
    burst(p, 3, 0.015, 0.5)
    p.filter("LP12", hz=6500, res=0.05)
    p.filter2("HP12", hz=250)
    p.env(1, a=0.0005, d=0.5, s=0.0, r=0.5, dcurve=-0.6, rcurve=-0.6)
    hit_voice(p)
    p.mod("VELOCITY", "A_WARP", 0.2)
    p.set("macro2", 0.35)
    p.motion("RANDOM", "A_WTPOS", 0.1)
    p.tone("A_WTPOS", 0.15)
    room(p, mix=0.14, decay=0.26)
    grit(p, mode="HARD", drive=0.35, tone=0.5, amount=0.45)
    p.master(0.6)
    p.doc("Metal-on-metal strike, inharmonic and bright", "Unpitched", "Industrial, EBM, trailer percussion, game",
          "Accents on 2 and 4, or sparse hits in a groove", "RHYTHM",
          "Inharmonic by design, so it never clashes with the key; keep it sparse")
    p.context(note=60, unpitched=True)
    out.append(p)

    p = X("ZAP BLIP", "BASIC", "BASIC")
    p.osc(0, level=0.7, wt=0.4)
    p.filter("LP12", hz=5000, res=0.1)
    p.filter2("HP12", hz=200)
    p.env(1, a=0.0005, d=0.12, s=0.0, r=0.12)
    p.env(4, a=0.0005, d=0.08, s=0.0, r=0.03, dcurve=-0.3)
    p.set("macro2", 0.5)
    p.mod("ENV4", "PITCH", 1.0, aux="MACRO2")
    hit_voice(p)
    p.mod("VELOCITY", "CUTOFF", 0.12)
    p.tone("A_WTPOS", 0.25)
    room(p, mix=0.12)
    grit(p, mode="BITCRUSH", drive=0.3, tone=0.55, amount=0.45)
    p.master(0.6)
    p.doc("Electronic zap: a fast downward sweep", "C3–C5", "Electro, IDM, trap, video-game",
          "Fills and accents; pitch it for melodic zaps", "RHYTHM",
          "MOTION sets the sweep depth; short enough to sit between any drums")
    p.context(note=60, unpitched=True)
    out.append(p)

    return out
