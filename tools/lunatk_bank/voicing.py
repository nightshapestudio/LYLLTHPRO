"""Bank-wide voicing rules, applied to every preset after its file builds it.

The first bank was voiced to sit under a mix: a high-pass on nearly every
non-bass sound, single-voice oscillators, and distortion on almost
everything. Played on its own, which is how a synth is judged, that read as
thin. These rules keep each preset's design and change only those habits:

1  HIGH-PASS  A FILTER 2 high-pass never sits above an octave below the
              lowest note the preset is written for. Where that leaves it
              doing nothing it is switched off. PERC and FX keep theirs:
              there it is part of the sound.
3  WIDTH      Single-voice oscillators on sustained, melodic categories get
              a little unison and detune; pads and keys without chorus or
              HYPER get a chorus.
4  GRIT       Pads, keys and plucks only carry distortion by default when
              the preset is about dirt; GRIT (MACRO 4) still adds it.
5  BODY       Presets named in BODY get their fundamental back (thin by
              construction: octave-up layers over a weak table).
Rule 2 lives in analyze.LOW_LIMIT.
"""

import re

import lunatk as L
import phrases

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
KEEP_HIGHPASS = {"PERC", "FX", "DRONE"}
# How much unison each category gets when it has none: voices, detune, width.
# Three voices, not two: a pair sits hard left and right and falls apart in mono.
THICKEN = {"PAD": (3, 0.10, 0.60), "KEYS": (3, 0.05, 0.30), "LEAD": (3, 0.07, 0.15),
           "ARP": (3, 0.04, 0.30), "PLUCK": (3, 0.04, 0.30), "MOTION": (3, 0.08, 0.50)}
# Below C3 an oscillator gets detune but no spread: stereo lows collapse in mono.
WIDE_FROM = 48
CHORUS = {"PAD": dict(mode="WIDE", mix=0.28, rate=0.25, depth=0.45, width=0.7),
          "KEYS": dict(mode="SUBTLE", mix=0.22, rate=0.3, depth=0.4, width=0.6)}
CLEAN_BY_DEFAULT = {"PAD", "KEYS", "PLUCK"}
# Words that say the dirt IS the preset. Mood words (decay, ruin, ghost) do not.
DIRT = re.compile(r"DIRT|GRIT|DISTORT|FUZZ|CRUSH|SNARL|RUST|BLOWN|SATURAT|OVERDRIV|GRIND|SHRED|MANGLE|BURN", re.I)
# Measured conflicts (build.py gates, 2026-09-28). These presets route the mod
# wheel, velocity or MOTION through the stages these rules change, or their
# reverb spreads the low end once the high-pass is gone. Each failed a gate
# under the rules and passed without them, so they keep their original voicing.
KEEP_VOICING = {"MAIN STAGE DAMAGE", "WHITE HEAT", "MACHINE SAINT", "FRACTURED PULSE", "ASH CATHEDRAL", "BLACK AMPLIFIER", "DEAD CONSTELLATION", "DEAD ROOM RHODES", "DISTORTION BLOOM", "MACHINE HEAVEN", "RAZOR VOICE", "SCAR FIELD", "SCORCHED EP", "SCREAM CIRCUIT", "SHOCK ANGEL", "SICK LIGHT", "SLOW COLLAPSE", "SUBMERSION", "VEINS OF LIGHT"}
# Rule 5: presets whose fundamental measured more than 12 dB under their
# loudest partial after rules 1-4 (body_report.py): mostly GLASS-table bells
# doubled an octave up. None has a free oscillator, so the body comes from the
# sub: a clean mono sine an octave down, under the bell rather than in it.
BODY = {"NIGHT CELESTE", "MERCURY TEARS", "PRAYER BOX", "NEEDLE RAIN", "THIN ICE", "GLASS SHARD", "GLASS EXECUTION", "HEAVY BREATH", "GLASS TENSION", "MERCURY SKIN", "MOTHER TONGUE", "DEAD CHANNEL", "GLASS TEETH", "WIRETAP", "THE IMPOSSIBLE ENGINE", "BROKEN HALO", "GLASS VENOM", "END CREDITS FOR THE APOCALYPSE", "SHARP OBJECT", "GLASS ENGINE", "ASHEN HALO"}
BODY_SUB_LEVEL = 0.22
# Rules a preset skips, where one rule failed a gate and the rest passed.
# NIGHT CELESTE: unison/chorus pulled it out of tune. THIN ICE: the sub, through
# its reverb, spread the lows past the mono gate. ELECTRIC TITAN: unison evened
# out its velocity response. THE IMPOSSIBLE ENGINE: unison stacked its custom
# table's DC offset past the gate. BURNING SAW: without the high-pass its mod
# wheel moved the level past 4 dB.
SKIP = {"NIGHT CELESTE": {"thicken"}, "THIN ICE": {"body"}, "ELECTRIC TITAN": {"thicken"}, "THE IMPOSSIBLE ENGINE": {"thicken"}, "BURNING SAW": {"highpass"}}
# A full-level sub nudged NIGHT CELESTE just past its MOTION gate.
BODY_LEVEL = {"NIGHT CELESTE": 0.15}


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowest_note(p):
    m = re.match(r"\s*([A-G])(#|b)?(-?\d)", p.info.get("register", ""))
    if not m:
        return phrases.DEFAULT_PITCH_NOTE[p.category] - 12
    n = NOTE[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)
    return 12 * (int(m.group(3)) + 1) + n


def hz_of(value):
    return 20 * 1000 ** value


def highpass(p):
    if p.category in KEEP_HIGHPASS or p.get("filter2.on") < 0.5:
        return
    if int(p.get("filter2.type")) not in (L.enum("LY_FILTER_HP12"), L.enum("LY_FILTER_HP24")):
        return
    limit = midi_hz(lowest_note(p)) / 2
    hz = min(hz_of(p.get("filter2.cutoff")), limit)
    if hz < 30:
        if p.category in ("BASS", "DRONE"):
            p.set("filter2.cutoff", L.cutoff(25))      # rumble guard only
        else:
            p.set("filter2.on", 0)
    else:
        p.set("filter2.cutoff", L.cutoff(hz))


def thicken(p):
    spec = THICKEN.get(p.category)
    if not spec:
        return
    voices, detune, width = spec
    low = lowest_note(p)
    for k in ("a", "b"):
        # Bell and tine layers two octaves up stay single: unison there is fizz.
        if p.get(f"{k}.octave") >= 2:
            continue
        if p.get(f"{k}.on") > 0.5 and p.get(f"{k}.level") > 0.05 and p.get(f"{k}.unison") < 1.5:
            wide = low + 12 * p.get(f"{k}.octave") >= WIDE_FROM
            p.set(f"{k}.unison", voices).set(f"{k}.detune", detune).set(f"{k}.width", width if wide else 0.0)
    if p.category in CHORUS and p.get("chorus.on") < 0.5 and not (p.get("hyper.on") > 0.5 and p.get("hyper.mix") > 0.05):
        p.chorus(**CHORUS[p.category])


def degrit(p):
    if p.category not in CLEAN_BY_DEFAULT or p.get("dist.on") < 0.5:
        return
    text = p.name + " " + p.info.get("role", "")
    if DIRT.search(text):
        return
    p.set("dist.mix", 0.0)


def body(p):
    if p.name in BODY and p.get("sub.on") < 0.5:
        p.sub(BODY_LEVEL.get(p.name, BODY_SUB_LEVEL), shape="SINE", octave=1, filtered=False)


def revoice(p):
    if p.name in KEEP_VOICING:
        return p
    for rule in (highpass, thicken, degrit, body):
        if rule.__name__ not in SKIP.get(p.name, ()):
            rule(p)
    return p
