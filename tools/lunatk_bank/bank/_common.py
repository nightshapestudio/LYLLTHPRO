"""Shared building blocks, so the bank's conventions stay consistent."""


def space(p, mix, mode="PLATE", size=0.45, decay=0.3, damp=0.5, predelay=0.12, width=0.85, amount=0.2):
    """Reverb at `mix`, MACRO 3 moves it by +-amount."""
    p.reverb(mix=mix, mode=mode, size=size, decay=decay, damp=damp, predelay=predelay, width=width)
    return p.space(reverb=amount)


def echo(p, time="3/16", mix=0.12, feedback=0.3, amount=0.12, pingpong=False, lowcut=0.35, highcut=0.5):
    p.delay(time=time, mix=mix, feedback=feedback, pingpong=pingpong, lowcut=lowcut, highcut=highcut, width=0.3)
    return p.space(reverb=0, delay=amount)


def grit(p, mode="TUBE", drive=0.4, tone=0.6, amount=0.7, base=0.0, drive_amount=0.0):
    """Distortion wet at `base`; MACRO 4 adds `amount` of wet (and drive)."""
    p.dist(mode=mode, drive=drive, tone=tone, mix=base)
    routes = [("DIST_MIX", amount)]
    if drive_amount:
        routes.append(("DIST_DRIVE", drive_amount))
    return p.grit(*routes)


def filter_grit(p, amount=0.45):
    """GRIT as filter drive, for sounds that should not meet the distortion."""
    return p.grit(("DRIVE", amount))


def velocity(p, sens=0.6, cutoff=0.1):
    p.set("velSens", sens)
    if cutoff:
        p.mod("VELOCITY", "CUTOFF", cutoff)
    return p


def vibrato(p, lfo=4, hz=5.2, depth=0.012, delay=0.35, rise=0.4):
    """Mod-wheel vibrato (depth in PITCH units: x24 semitones)."""
    p.lfo(lfo, "SINE", hz=hz, mode="TRIG", delay=delay, rise=rise)
    return p.mod(f"LFO{lfo}", "PITCH", depth * 2.5, aux="MODWHEEL")


def pressure(p, dest="CUTOFF", amount=0.15):
    return p.mod("PRESSURE", dest, amount)
