"""Shared pieces for Add-on 03 (x3_*): four-on-the-floor industrial pop.

Every x3 preset is built with `N3`, which turns on the build's mod-wheel
gate: the phrase is rendered again at wheel = 1 and must change the
spectrum by at least 2.5 dB, stay within ±4 LU and never clip. `wheel()`
routes the transformation and trims MASTER so the wheel adds danger, not level."""

from lunatk import Preset
from bank2._common import space
from bank2._x2 import burn, dc_guard, mono, plate, poly  # noqa: F401  (re-exported)


def N3(name, category, a="ANALOG", b="BASIC"):
    p = Preset(name, category, a, b)
    p.context(wheel=True)
    return p


def wheel(p, *routes, trim=0.0):
    """Mod wheel routes (dest, amount), plus a MASTER trim so full wheel
    lands near the same loudness as none."""
    for dest, amount in routes:
        p.mod("MODWHEEL", dest, amount)
    if trim:
        p.mod("MODWHEEL", "MASTER", trim)
    return p


def room(p, mix=0.06, decay=0.25, amount=0.1):
    """Club-dry: a short plate, never the reason a patch sounds big."""
    return space(p, mix, mode="PLATE", size=0.35, decay=decay, damp=0.55, predelay=0.02, width=0.7, amount=amount)


def sub(p, level=0.55, shape="SINE"):
    return p.sub(level, shape, octave=1, pan=0.0, filtered=False)


def tight(p, d=0.35, s=0.6, r=0.06):
    """A fast, rhythm-ready amp envelope."""
    return p.env(1, a=0.001, d=d, s=s, r=r)
