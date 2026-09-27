"""Building blocks for the showcase banks (show_pad, show_bass, show_lead).

These reach the parts of the engine the first bank2 files barely touch: the
filter saturation stage, VINTAGE per-note drift, PUNCH, the MORPH filter,
the fourth envelope, and slow envelopes used as modulation sources so a held
chord keeps changing for twenty seconds without looping.
"""

from lunatk import enum


def fsat(p, type="SOFT", drive=0.3, mix=1.0):
    """The filter's own saturation stage (LIGHT SOFT HARD DIODE SHAPER RECTIFY BITS RATE)."""
    return p.set("fsat.type", enum("LY_FSAT_" + type)).set("fsat.drive", drive).set("fsat.mix", mix)


def vintage(p, amount):
    """Each note's own pitch, cutoff and envelope spread, and a slow drift."""
    return p.set("vintage", amount)


def punch(p, amount):
    return p.set("punch", amount)


def morph(p, pos, second=False):
    """MORPH filter position: 0 low-pass, 0.5 notch, 1 high-pass."""
    return p.set("filter2.morph" if second else "filter.morph", pos)


def ladder(p, two_pole=False, bass_loss=0.0):
    return p.set("ladder.poles", 1 if two_pole else 0).set("ladder.bass", bass_loss)


def drift(p, lfo, hz, dests, shape="SMOOTH_RANDOM"):
    """A free-running wander: never retriggered, so no two notes or bars meet
    it at the same point. dests: [(dest, depth at default MOTION)]."""
    p.lfo(lfo, shape, hz=hz, mode="FREE")
    for dest, depth in dests:
        p.motion(f"LFO{lfo}", dest, depth)
    return p


def dimension(p, mix=0.3, size=0.5, hyper=0.0, detune=0.2, rate=0.3):
    """Width from the HYPER/DIMENSION stage rather than chorus."""
    return p.hyper(mix=hyper, detune=detune, rate=rate, voices=0.5, dim=mix, dim_size=size)
