"""Shared pieces for Expansion 02 (x2_*). Deliberately different defaults
from the showcase files: other distortion algorithms, other saturation
stages, other spaces, so the two expansions do not share a fingerprint."""

from lunatk import Preset
from bank2._common import space, echo
from bank2._showcase import drift, fsat


def N(name, category, a="ANALOG", b="BASIC"):
    return Preset(name, category, a, b)


def poly(p, voices=8, vel=0.4, glide=0.0):
    return p.voice(voices=voices, glide=glide, vel=vel, bend=2)


def mono(p, glide=0.03, vel=0.45, legato=True):
    return p.voice(voices=1, glide=glide, legato=legato, glide_always=False, vel=vel, bend=2)


def burn(p, mode, drive, base, amount=0.35, tone=0.45, drive_amount=0.0):
    """Distortion wet at `base`, GRIT adds `amount` of wet (and drive)."""
    p.dist(mode=mode, drive=drive, tone=tone, mix=base)
    p.mod("MACRO4", "DIST_MIX", amount)
    if drive_amount:
        p.mod("MACRO4", "DIST_DRIVE", drive_amount)
    return p


def plate(p, mix=0.1, decay=0.3, amount=0.12):
    return space(p, mix, mode="PLATE", size=0.45, decay=decay, damp=0.55, predelay=0.04, width=0.8, amount=amount)


def hall(p, mix=0.16, decay=0.38, size=0.7, amount=0.15, predelay=0.1, width=0.9):
    """LUNATK's reverb has no low cut: drones pass width 0.25 to keep lows mono."""
    return space(p, mix, mode="HALL", size=size, decay=decay, damp=0.6, predelay=predelay, width=width, amount=amount)


def dc_guard(p):
    """A 26 Hz FX high-pass: saturation inside the filter can leave DC."""
    return p.fxfilter(type="HP", cut=0.04, res=0.0, mix=1.0)


def bass_space(p, amount=0.16):
    p.delay(time="1/8", mix=0.0, feedback=0.22, lowcut=0.8, highcut=0.45, width=0.2)
    return p.space(reverb=0, delay=amount)
