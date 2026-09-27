"""ADD-ON 03 / RHYTHMIC CHORD AND PULSE MONSTERS. Played stabs and repeated
notes against a four-on-the-floor: short envelopes, a thick middle, the low
end kept out of the kick's way, and a wheel that makes every hit bigger and
dirtier."""

from bank2._common import velocity
from bank2._showcase import dimension, drift, fsat, punch, vintage
from bank2._x3 import N3, burn, poly, room, wheel
from bank2.show_arp import pattern


def K(name, a="ANALOG", b="ANALOG", category="KEYS"):
    return N3(name, category, a, b)


def stab(p, d=0.3, s=0.15, r=0.08, vel=0.55):
    p.env(1, a=0.001, d=d, s=s, r=r)
    return poly(p, voices=10, vel=vel)


def presets():
    out = []

    # 41 STOMP SYNTH: short offbeat chords: fast ladder snap, dense unison,
    # HP 170 so it never sits on the kick.
    p = K("STOMP SYNTH", "ANALOG", "NS OBSIDIAN")
    p.osc(0, level=0.55, wt=1.0, unison=3, detune=0.06, width=0.3)
    p.osc(1, level=0.28, wt=0.3, octave=1)
    p.filter("LADDER", hz=1500, res=0.28, keytrack=0.5, env=0.5)
    p.filter2("HP12", hz=170)
    stab(p, d=0.25, s=0.1)
    p.env(2, a=0.001, d=0.12, s=0.15, r=0.08)
    punch(p, 0.5)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("CUTOFF", 0.07)])
    wheel(p, ("DIST_DRIVE", 0.35), ("RES", 0.25), ("A_WIDTH", 0.4), ("DIST_MIX", 0.3))
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.3)
    p.doc("Huge offbeat chords against a four-on-the-floor: a snapping ladder, a dense saw stack and an obsidian octave, clear of the kick",
          "C3–C5", "Industrial pop, dark dance", "Offbeat or eighth-note chords", "RHYTHM",
          "Wheel: harder drive, more resonance, wider")
    out.append(p)

    # 42 BLACK JACKHAMMER: repeated notes feel physical: PUNCH + a pitch
    # blip (ENV3 -> PITCH, tiny) + a RANDOM on fold so repeats vary.
    p = K("BLACK JACKHAMMER", "ANALOG", "NS GRINDSTONE")
    p.osc(0, level=0.56, wt=1.0)
    p.osc(1, level=0.3, wt=0.35)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.4)
    p.filter("LP24", hz=1400, res=0.22, keytrack=0.5, env=0.45)
    p.filter2("HP12", hz=120)
    stab(p, d=0.2, s=0.2, r=0.06)
    p.env(3, a=0.0005, d=0.02, s=0.0, r=0.02)
    p.mod("ENV3", "PITCH", 0.01)
    punch(p, 0.6)
    velocity(p, 0.85, 0.35)
    p.mod("RANDOM", "INS1_AMOUNT", 0.12)
    p.set("macro2", 0.4)
    drift(p, 1, 0.43, [("B_WTPOS", 0.35), ("CUTOFF", 0.07)])
    wheel(p, ("INS1_AMOUNT", 0.4), ("B_WTPOS", 0.4), ("DIST_MIX", 0.35))
    p.mod("MODWHEEL", "ENV2_DECAY", -0.25)
    p.env(2, a=0.001, d=0.1, s=0.25, r=0.06)
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "HARD", drive=0.5, base=0.3)
    p.mod("VELOCITY", "DIST_MIX", 0.3, curve=0.4)
    p.doc("One-note industrial hooks that hit like a jackhammer: a punch, a tiny pitch blip and a fold that differs on every repeat",
          "C2–C4", "Industrial, EBM", "Repeated single notes", "RHYTHM",
          "Physical, not percussive: it is a pitched note every time. Wheel: denser, harder, snappier")
    out.append(p)

    # 43 BODY PULSE: low-mid air-pusher: a TRIG filter envelope on every note
    # plus a slow table drift so repeats stay alive.
    p = K("BODY PULSE", "ANALOG", "PWM")
    p.osc(0, level=0.56, wt=0.9)
    p.osc(1, level=0.3, wt=0.35, octave=-1)
    p.filter("LP24", hz=900, res=0.25, keytrack=0.5, env=0.4, drive=0.35)
    p.filter2("HP12", hz=110)
    stab(p, d=0.35, s=0.3, r=0.08)
    p.env(2, a=0.005, d=0.25, s=0.2, r=0.1)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.33, [("B_WTPOS", 0.4), ("CUTOFF", 0.08)])
    wheel(p, ("CUTOFF", 0.35), ("DIST_MIX", 0.4), ("DIST_DRIVE", 0.25))
    fsat(p, "SOFT", drive=0.4)
    room(p)
    burn(p, "DIODE", drive=0.45, base=0.25)
    p.doc("A low-mid pulse that pushes air: a driven saw and a pulse an octave down, each hit with its own soft filter swell",
          "C2–C4", "Dark dance, industrial pop", "Eighth-note pulses", "RHYTHM",
          "Wheel: the spectrum opens and the diode drive rises")
    out.append(p)

    # 44 MACHINE CHORD: fast attack, controlled decay, then metal texture
    # after each hit (ENV4 delayed comb).
    p = K("MACHINE CHORD", "ANALOG", "NS CATHEDRAL METAL")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.25)
    p.osc(1, level=0.25, wt=0.4)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.0)
    p.filter("LP24", hz=1800, res=0.22, keytrack=0.5, env=0.45)
    p.filter2("HP12", hz=150)
    stab(p, d=0.5, s=0.3, r=0.12)
    p.env(4, a=0.08, d=0.4, s=0.3, r=0.12)
    p.mod("ENV4", "INS2_AMOUNT", 0.45)
    p.set("ins2.mix", 0.3)
    punch(p, 0.5)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.39, [("B_WTPOS", 0.4), ("CUTOFF", 0.07)])
    wheel(p, ("B_WTPOS", 0.35), ("B_WIDTH", 0.5), ("DIST_MIX", 0.35), ("INS2_AMOUNT", 0.2))
    p.set("b.unison", 2)
    fsat(p, "HARD", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.3)
    p.doc("Chords that hit like machinery: a fast punched strike, then a metal comb rings in 80 ms later and fades",
          "C3–C5", "Industrial pop, electro-rock", "Chord hits", "RHYTHM",
          "Wheel: more metal damage and the metal layer spreads in stereo")
    out.append(p)

    # 45 CRUSHED STROBE: gated 1/16 chord pattern via a performer gate on
    # AMP; crush and drive; wheel adds crush and rhythmic filter motion.
    p = K("CRUSHED STROBE", "ANALOG", "NS FRACTURE")
    p.osc(0, level=0.55, wt=1.0, unison=2, detune=0.05, width=0.25)
    p.osc(1, level=0.28, wt=0.3)
    p.filter("LP24", hz=1900, res=0.22, keytrack=0.5, env=0.3)
    p.filter2("HP12", hz=150)
    p.env(1, a=0.001, d=0.6, s=0.8, r=0.1)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.performer(1, {0: [(0.0, "HOLD"), (-1.0, "HOLD"), (-0.5, "PULSE"), (-1.0, "HOLD")] * 4}, mode="SONG", rate="1/16")
    p.set("macro2", 0.55)
    p.motion("PERF1", "AMP", 0.6)
    drift(p, 1, 0.37, [("B_WTPOS", 0.4)])
    wheel(p, ("B_WTPOS", 0.35), ("DIST_MIX", 0.4))
    p.mod("PERF1", "CUTOFF", 0.2, aux="MODWHEEL")
    fsat(p, "BITS", drive=0.3, mix=0.35)
    room(p)
    burn(p, "HARD", drive=0.5, base=0.28)
    p.doc("Hold a chord and it strobes in sixteenths: gated on the grid, fracture-crushed, every strike expensive and brutal",
          "C3–C5", "Dark dance, industrial pop", "Held chords or eighth/sixteenth playing", "RHYTHM",
          "MOTION 0 removes the gate for played patterns. Wheel: more crush, and the filter starts moving with the gate")
    out.append(p)

    # 46 HEAVY SEQUENCE: between bass, stab and arp: an 8-step pattern that
    # carries low roots and mid stabs (-12 / 0 / +12).
    p = K("HEAVY SEQUENCE", "ANALOG", "NS GRINDSTONE", category="ARP")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.3, wt=0.3, octave=-1)
    p.filter("LADDER", hz=1300, res=0.28, keytrack=0.5, env=0.45)
    p.filter2("HP12", hz=95)
    p.env(1, a=0.001, d=0.22, s=0.35, r=0.07)
    poly(p, voices=8, vel=0.65)
    p.arp(mode="PLAYED", rate="1/16", octaves=1, gate=0.8)
    pattern(p, [(1.0, 0.6, -12), (0.45, 0.3, 0), (0.75, 0.45, 0), (0.45, 0.3, 12), (0.95, 0.6, -12), None, (0.7, 0.45, 0), (0.55, 0.3, 7)])
    velocity(p, 0.65, 0.3)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("B_WTPOS", 0.35), ("CUTOFF", 0.07)])
    wheel(p, ("B_WTPOS", 0.45), ("RES", 0.2), ("DIST_MIX", 0.35), ("DIST_DRIVE", 0.25))
    fsat(p, "DIODE", drive=0.4)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.28)
    p.doc("Half bass, half stab, half arp: low roots and mid stabs alternating in an eight-step pattern that can run a whole arrangement",
          "C2–C4", "Industrial pop, EBM, electro-rock", "Hold one note per chord", "RHYTHM",
          "Wheel: from tight and focused to huge and chaotic")
    out.append(p)

    # 47 STEEL DISCO: modern dance chord: pumped (drawn duck on the beat),
    # complex harmonics (EXP unison + comb), aggressive attack.
    p = K("STEEL DISCO", "ANALOG", "NS HOLLOW BONE")
    p.osc(0, level=0.55, wt=1.0, unison=4, detune=0.07, width=0.05, unimode="EXP")
    p.osc(1, level=0.25, wt=0.4, octave=1)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LP24", hz=2000, res=0.22, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=160)
    p.env(1, a=0.001, d=0.8, s=0.7, r=0.12)
    poly(p, voices=10, vel=0.55)
    punch(p, 0.45)
    velocity(p, 0.6, 0.28)
    p.pump(lfo=1, sync="1/4", depth=0.35, default=0.5)
    drift(p, 2, 0.33, [("B_WTPOS", 0.4)])
    wheel(p, ("DIST_MIX", 0.4), ("DIST_DRIVE", 0.3), ("B_WTPOS", 0.3), ("RES", 0.15))
    p.comp(mode="MULTIBAND", threshold=0.55, ratio=0.4, attack=0.3, release=0.3, gain=0.1, depth=0.55, mix=1.0)
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.25)
    p.doc("A dark dance chord: exponential saw stack and a hollow comb octave, pumping on the beat, band-compressed, no disco cliché",
          "C3–C5", "Dark dance, industrial pop", "Held or offbeat chords under a four-on-the-floor", "RHYTHM",
          "The pump only ducks; MOTION sets its depth. Wheel: heavy distorted club aggression")
    out.append(p)

    # 48 VIOLENT GLITTER: contrast: filthy low mids (A folded, driven) and
    # shiny upper harmonics (RADIANT +2 oct).
    p = K("VIOLENT GLITTER", "ANALOG", "NS RADIANT")
    p.osc(0, level=0.55, wt=1.0)
    p.osc(1, level=0.18, wt=0.8, octave=2, unison=3, detune=0.05, width=0.8)
    p.insert(1, "FOLD", after=True, amount=0.25, mix=0.4)
    p.filter("LP24", hz=1500, res=0.22, keytrack=0.5, env=0.35, drive=0.35)
    p.route_filter(a=True, b=False)
    p.filter2("HP12", hz=150)
    stab(p, d=0.6, s=0.35, r=0.12)
    velocity(p, 0.6, 0.28)
    p.set("macro2", 0.4)
    drift(p, 1, 0.41, [("B_WTPOS", 0.4), ("B_PAN", 0.2)])
    wheel(p, ("B_LEVEL", 0.15), ("B_WTPOS", 0.3), ("INS1_AMOUNT", 0.35), ("DIST_MIX", 0.35))
    p.eq(high=-2, high_hz=9000)
    room(p)
    burn(p, "HARD", drive=0.45, base=0.25)
    p.lfo(3, "TRIANGLE", hz=0.9, mode="FREE")
    p.motion("LFO3", "CUTOFF", 0.2)
    p.motion("LFO3", "A_WTPOS", 0.4)
    p.doc("Glitter over filth: a folded, driven low-mid saw and a shining radiant layer two octaves up, kept just short of harsh",
          "C3–C5", "Industrial pop, dark dance", "Stabs and chords", "RHYTHM",
          "Wheel: more sheen and more distortion at the same time")
    out.append(p)

    # 49 MIDNIGHT ENGINE (brief: BLACKOUT GROOVE, too close to BLACKOUT):
    # verse pulse that leaves room for vocals (scoop at 2 kHz); wheel = chorus.
    p = K("MIDNIGHT ENGINE", "PWM", "NS THROAT")
    p.osc(0, level=0.55, wt=0.35)
    p.osc(1, level=0.25, wt=0.3)
    p.filter("LP24", hz=1300, res=0.22, keytrack=0.5, env=0.35)
    p.filter2("HP12", hz=140)
    stab(p, d=0.4, s=0.3, r=0.1)
    velocity(p, 0.6, 0.28)
    p.performer(1, {0: [(0.6, "DECAY"), (0.1, "HOLD"), (0.3, "DECAY"), (0.1, "HOLD")] * 4}, mode="SONG", rate="1/16")
    p.set("macro2", 0.45)
    p.motion("PERF1", "CUTOFF", 0.12)
    drift(p, 1, 0.33, [("B_WTPOS", 0.4)])
    p.eq(mid=-2.5, mid_hz=2000, q=0.4)
    wheel(p, ("CUTOFF", 0.3), ("B_LEVEL", 0.2), ("A_WIDTH", 0.5), ("DIST_MIX", 0.35), ("EQ_MID", 0.25))
    p.set("a.unison", 2)
    p.set("a.width", 0.0)
    fsat(p, "SOFT", drive=0.35)
    room(p)
    burn(p, "TUBE", drive=0.45, base=0.22)
    p.doc("A dark verse pulse that carries the groove and leaves the vocal alone: a pulse-and-vowel pair, a sixteenth tick, a hole at 2 kHz",
          "C3–C5", "Dark pop, industrial pop verses", "Pulsing chords under a vocal", "SUPPORT",
          "Wheel: opens, widens, fills the vocal hole: the chorus-ready version")
    out.append(p)

    # 50 MAIN STAGE DAMAGE: the ultimate rhythmic preset: works for bass
    # riffs, hooks, power chords, stabs. Wheel staged: 50% bigger/wider/
    # animated (curves < 0 arrive early), 100% filthy scream (curves > 0 late).
    p = K("MAIN STAGE DAMAGE", "NS OBSIDIAN", "NS GRINDSTONE")
    p.osc(0, level=0.52, wt=0.3, unison=2, detune=0.05, width=0.15)
    p.osc(1, level=0.26, wt=0.2, octave=1, unison=3, detune=0.07, width=0.3)
    p.sub(0.12, "SINE", filtered=False)
    p.noise(0.0, type="WHITE", color=0.8, keytrack=True)
    p.insert(1, "FOLD", after=True, amount=0.15, mix=0.35)
    p.insert(2, "COMB", after=True, amount=0.4, freq=0.75, mix=0.12)
    p.filter("LADDER", hz=1600, res=0.28, keytrack=0.5, env=0.45)
    fsat(p, "DIODE", drive=0.4)
    p.feedback(amount=0.06, drive=0.6, tone=0.55)
    p.filter2("HP12", hz=90)
    p.env(1, a=0.001, d=0.5, s=0.6, r=0.1)
    p.env(2, a=0.001, d=0.18, s=0.3, r=0.1)
    p.env(3, a=0.0005, d=0.012, s=0.0, r=0.01)
    p.mod("ENV3", "NOISE_LEVEL", 0.12)
    punch(p, 0.5)
    poly(p, voices=10, vel=0.55)
    velocity(p, 0.6, 0.28)
    p.mod("VELOCITY", "INS1_AMOUNT", 0.2)
    p.mod("PRESSURE", "FEEDBACK", 0.15)
    p.mod("TIMBRE", "B_WTPOS", 0.3)
    vintage(p, 0.1)
    p.set("macro2", 0.4)
    drift(p, 1, 0.37, [("A_WTPOS", 0.25), ("CUTOFF", 0.06)])
    drift(p, 2, 0.19, [("B_PAN", 0.15)])
    # Stage 1 (early): bigger, wider, more animated.
    p.mod("MODWHEEL", "B_WIDTH", 0.6, curve=-0.5)
    p.mod("MODWHEEL", "DIM_MIX", 0.35, curve=-0.5)
    p.mod("MODWHEEL", "B_WTPOS", 0.35, curve=-0.4)
    p.mod("LFO1", "A_WTPOS", 0.3, aux="MODWHEEL")
    # Stage 2 (late): filthy, screaming, metallic.
    p.mod("MODWHEEL", "INS1_AMOUNT", 0.45, curve=0.6)
    p.mod("MODWHEEL", "INS2_AMOUNT", 0.35, curve=0.6)
    p.mod("MODWHEEL", "FEEDBACK", 0.18, curve=0.6)
    p.mod("MODWHEEL", "RES", 0.15, curve=0.6)
    p.mod("MODWHEEL", "DIST_MIX", 0.35, curve=0.4)
    dimension(p, mix=0.0, size=0.6)
    room(p)
    burn(p, "TUBE", drive=0.5, base=0.28)
    p.doc("The ultimate rhythmic preset: picked obsidian and grindstone layers through a folded, combed diode ladder loop; bass riffs, hooks, power chords, stabs",
          "C2–C5", "Industrial pop, electro-rock, dark dance", "Anything rhythmic", "FOREGROUND",
          "Wheel in two stages: to 50% it gets bigger, wider and more animated; past 50% the fold, comb, loop and resonance turn it filthy and screaming")
    out.append(p)

    return out
