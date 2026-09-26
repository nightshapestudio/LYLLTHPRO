"""LUNATK preset language.

Presets are written against the engine as it is: every value goes through a
parameter key exported from the app (params.json), is range-checked, and every
choice value (sources, destinations, filter types, warps...) is read from
LYSynthCore.h, never typed by hand.

Bank-wide macro convention (every preset):
  MACRO 1  TONE    bipolar around its default: darker <-> brighter
  MACRO 2  MOTION  scales every LFO / random movement; 0 is still
  MACRO 3  SPACE   bipolar around its default: drier <-> wetter
  MACRO 4  GRIT    0 is the designed tone; up adds drive / damage
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
HEADER = os.path.join(ROOT, "LYLLTH", "SynthCore", "LYSynthCore.h")


def _parse_enums(path):
    """Every `enum { ... };` block whose values are plain integers."""
    text = open(path).read()
    text = re.sub(r"//[^\n]*", "", text)
    values = {}
    for block in re.findall(r"enum\s*\{(.*?)\};", text, re.S):
        current = -1
        ok = True
        parsed = {}
        for item in [x.strip() for x in block.split(",") if x.strip()]:
            if "=" in item:
                name, expr = [x.strip() for x in item.split("=", 1)]
                if re.fullmatch(r"-?\d+", expr):
                    current = int(expr)
                elif expr in values or expr in parsed:
                    current = (parsed.get(expr) if expr in parsed else values[expr])
                else:
                    ok = False
                    break
            else:
                name = item
                current += 1
            parsed[name] = current
        if ok:
            values.update(parsed)
    return values


E = _parse_enums(HEADER)


def enum(name):
    if name not in E:
        raise KeyError(f"{name} is not in LYSynthCore.h")
    return E[name]


PARAMS = None


def load_params(path):
    global PARAMS
    data = json.load(open(path))
    PARAMS = {p["key"]: p for p in data["parameters"]}
    return data


SYNC = ["4 BAR", "2 BAR", "1 BAR", "3/4", "1/2", "3/8", "1/4", "3/16", "1/8", "3/32", "1/16", "3/64", "1/32", "1/12", "1/64"]


def division(name):
    """A sync division as rate/time knobs store it (normalized index)."""
    return SYNC.index(name) / (len(SYNC) - 1)


def env_time(seconds):
    """Envelope knob value for a time: 0.5 ms * 20000^p."""
    import math
    seconds = max(0.0005, min(10.0, seconds))
    return math.log(seconds / 0.0005) / math.log(20000.0)


def cutoff(hz):
    """Filter cutoff knob value for Hz: 20 * 1000^p."""
    import math
    return max(0.0, min(1.0, math.log(hz / 20.0) / math.log(1000.0)))


def lfo_hz(hz):
    """Free LFO rate knob for Hz: 0.02 * 1500^p."""
    import math
    return max(0.0, min(1.0, math.log(hz / 0.02) / math.log(1500.0)))


CATEGORIES = ["BASS", "LEAD", "PAD", "KEYS", "PLUCK", "MOTION", "DRONE", "PERC", "FX"]
LAYERS = ["FOREGROUND", "SUPPORT", "RHYTHM", "TEXTURE", "TRANSITION"]


class Preset:
    def __init__(self, name, category, table_a="BASIC", table_b="BASIC"):
        assert category in CATEGORIES, category
        self.name = name.upper()
        self.category = category
        self.table_a = enum("LY_TABLE_" + table_a)
        self.table_b = enum("LY_TABLE_" + table_b)
        self.values = {}
        self.slots = []
        self.info = {}
        self.test = {}
        # Macro defaults: tone and space sit in the middle (bipolar).
        self.set("macro1", 0.5)
        self.set("macro2", 0.5)
        self.set("macro3", 0.5)
        self.set("macro4", 0.0)

    # -- raw access -----------------------------------------------------
    def set(self, key, value):
        self.values[key] = float(value)
        return self

    def get(self, key):
        if key in self.values:
            return self.values[key]
        return PARAMS[key]["default"] if PARAMS else 0.0

    # -- oscillators ----------------------------------------------------
    def osc(self, o, on=True, level=None, pan=None, octave=None, semi=None, fine=None, wt=None, unison=None,
            detune=None, blend=None, width=None, phase=None, rand=None, warp=None, warp_amt=None, warp2=None,
            warp2_amt=None, unimode=None, stack=None):
        k = "a" if o == 0 else "b"
        self.set(f"{k}.on", 1 if on else 0)
        for field, value in [("level", level), ("pan", pan), ("octave", octave), ("semi", semi), ("fine", fine),
                             ("wtpos", wt), ("unison", unison), ("detune", detune), ("blend", blend),
                             ("width", width), ("phase", phase), ("rand", rand), ("warp", warp_amt), ("warp2", warp2_amt)]:
            if value is not None:
                self.set(f"{k}.{field}", value)
        if warp is not None:
            self.set(f"{k}.warpmode", enum("LY_WARP_" + warp))
        if warp2 is not None:
            self.set(f"{k}.warpmode2", enum("LY_WARP_" + warp2))
        if unimode is not None:
            self.set(f"{k}.unimode", enum("LY_UNI_" + unimode))
        if stack is not None:
            self.set(f"{k}.stack", enum("LY_STACK_" + stack))
        return self

    def sub(self, level, shape="SINE", octave=1, pan=0.0, filtered=False):
        self.set("sub.on", 1).set("sub.level", level).set("sub.shape", ["SINE", "TRI", "SQUARE", "SAW"].index(shape))
        self.set("sub.octave", octave).set("sub.pan", pan).set("filter.routeSub", 1 if filtered else 0)
        return self

    def noise(self, level, type="WHITE", color=0.5, pitch=0.5, keytrack=True, pan=0.0, filtered=True):
        self.set("noise.on", 1).set("noise.level", level).set("noise.type", enum("LY_NOISE_" + type))
        self.set("noise.color", color).set("noise.pitch", pitch).set("noise.keytrack", 1 if keytrack else 0)
        self.set("noise.pan", pan).set("filter.routeNoise", 1 if filtered else 0)
        return self

    # -- filters --------------------------------------------------------
    def filter(self, type="LP24", hz=None, cut=None, res=None, drive=None, keytrack=None, env=None, mix=None, on=True):
        self.set("filter.on", 1 if on else 0).set("filter.type", enum("LY_FILTER_" + type))
        if hz is not None:
            self.set("filter.cutoff", cutoff(hz))
        if cut is not None:
            self.set("filter.cutoff", cut)
        for field, value in [("res", res), ("drive", drive), ("keytrack", keytrack), ("envamt", env), ("mix", mix)]:
            if value is not None:
                self.set(f"filter.{field}", value)
        return self

    def filter2(self, type="HP12", hz=None, res=None, drive=None, keytrack=None, env=None, mix=None, parallel=False):
        self.set("filter2.on", 1).set("filter2.type", enum("LY_FILTER_" + type))
        if hz is not None:
            self.set("filter2.cutoff", cutoff(hz))
        for field, value in [("res", res), ("drive", drive), ("keytrack", keytrack), ("envamt", env), ("mix", mix)]:
            if value is not None:
                self.set(f"filter2.{field}", value)
        self.set("filter.routing", 1 if parallel else 0)
        return self

    def route_filter(self, a=True, b=True, sub=None, noise=None):
        self.set("filter.routeA", 1 if a else 0).set("filter.routeB", 1 if b else 0)
        if sub is not None:
            self.set("filter.routeSub", 1 if sub else 0)
        if noise is not None:
            self.set("filter.routeNoise", 1 if noise else 0)
        return self

    # -- envelopes (times in seconds) ------------------------------------
    def env(self, n, a=None, d=None, s=None, r=None, h=None, acurve=None, dcurve=None, rcurve=None):
        k = f"env{n}"
        for field, value in [("a", a), ("d", d), ("r", r), ("h", h)]:
            if value is not None:
                self.set(f"{k}.{field}", env_time(value) if value > 0 else 0.0)
        if s is not None:
            self.set(f"{k}.s", s)
        for field, value in [("acurve", acurve), ("dcurve", dcurve), ("rcurve", rcurve)]:
            if value is not None:
                self.set(f"{k}.{field}", value)
        return self

    # -- LFOs -----------------------------------------------------------
    def lfo(self, n, shape="SINE", hz=None, sync=None, mode="FREE", phase=None, delay=None, rise=None, smooth=None, points=None):
        k = f"lfo{n}"
        self.set(f"{k}.shape", enum("LY_LFO_" + shape))
        if sync is not None:
            self.set(f"{k}.sync", 1).set(f"{k}.rate", division(sync))
        elif hz is not None:
            self.set(f"{k}.sync", 0).set(f"{k}.rate", lfo_hz(hz))
        self.set(f"{k}.retrig", enum("LY_LFOMODE_" + mode))
        if phase is not None:
            self.set(f"{k}.phase", phase)
        if delay is not None:
            self.set(f"{k}.delay", delay / 4.0)
        if rise is not None:
            self.set(f"{k}.rise", rise / 4.0)
        if smooth is not None:
            self.set(f"{k}.smooth", 1 if smooth else 0)
        if points is not None:
            assert len(points) == 32
            for i, v in enumerate(points):
                self.set(f"{k}.p{i}", v)
        return self

    # -- modulation matrix ----------------------------------------------
    def mod(self, source, dest, amount, aux=None, curve=0.0, bipolar=False):
        slot = len(self.slots)
        assert slot < 32, f"{self.name}: matrix full"
        self.slots.append((source, dest, amount))
        self.set(f"mx{slot}.src", enum("LY_SRC_" + source))
        self.set(f"mx{slot}.dst", enum("LY_DST_" + dest))
        self.set(f"mx{slot}.amt", amount)
        self.set(f"mx{slot}.aux", enum("LY_SRC_" + aux) if aux else 0)
        self.set(f"mx{slot}.curve", curve)
        self.set(f"mx{slot}.bi", 1 if bipolar else 0)
        return self

    def motion(self, source, dest, depth):
        """LFO / random movement, scaled by MACRO 2. `depth` is the amount
        at the preset's default MOTION setting."""
        default = self.get("macro2")
        # With MOTION off by default, `depth` is the amount at full MOTION.
        scale = depth if default < 0.05 else depth / default
        return self.mod(source, dest, max(-1.0, min(1.0, scale)), aux="MACRO2")

    def pump(self, lfo=1, sync="1/4", depth=0.35, default=0.0, sharpness=5.0):
        """Tempo ducking that only ever reduces gain: a drawn shape from -1
        on the beat back up to 0, into AMP, scaled by MOTION."""
        import math
        points = [-math.exp(-sharpness * i / 31.0) for i in range(32)]
        self.lfo(lfo, "CUSTOM", sync=sync, mode="TRIG", smooth=True, points=points)
        self.set("macro2", default) if default is not None else None
        return self.mod(f"LFO{lfo}", "AMP", depth, aux="MACRO2")

    def tone(self, dest="CUTOFF", amount=0.2):
        """MACRO 1: bipolar around the default."""
        return self.mod("MACRO1", dest, amount, bipolar=True)

    def space(self, reverb=0.25, delay=0.0):
        """MACRO 3: bipolar around the default wetness."""
        if reverb:
            self.mod("MACRO3", "REVERB_MIX", reverb, bipolar=True)
        if delay:
            self.mod("MACRO3", "DELAY_MIX", delay, bipolar=True)
        return self

    def grit(self, *routes):
        """MACRO 4: unipolar from 0. routes are (dest, amount)."""
        for dest, amount in routes:
            self.mod("MACRO4", dest, amount)
        return self

    # -- voice ----------------------------------------------------------
    def voice(self, voices=8, glide=None, legato=None, glide_always=None, vel=None, bend=None, tune=None):
        self.set("voices", voices)
        if glide is not None:
            self.set("glide", glide)
        if legato is not None:
            self.set("legato", 1 if legato else 0)
        if glide_always is not None:
            self.set("glideAlways", 1 if glide_always else 0)
        if vel is not None:
            self.set("velSens", vel)
        if bend is not None:
            self.set("bendRange", bend)
        if tune is not None:
            self.set("tune", tune)
        return self

    def arp(self, mode="UP", rate="1/16", octaves=1, gate=0.6, swing=0.0, latch=False):
        self.set("arp.on", 1).set("arp.mode", enum("LY_ARP_" + mode.replace(" ", "")))
        self.set("arp.rate", division(rate)).set("arp.octaves", octaves).set("arp.gate", gate)
        self.set("arp.swing", swing).set("arp.latch", 1 if latch else 0)
        return self

    # -- effects --------------------------------------------------------
    def hyper(self, mix=0.3, detune=0.25, rate=0.4, voices=0.5, dim=0.0, dim_size=0.5):
        return self._fx("hyper", mix=mix, detune=detune, rate=rate, voices=voices, dimMix=dim, dimSize=dim_size)

    def dist(self, mode="TUBE", drive=0.2, tone=1.0, mix=1.0):
        self.set("dist.mode", enum("LY_DIST_" + mode))
        return self._fx("dist", drive=drive, tone=tone, mix=mix)

    def flanger(self, mix=0.3, rate=0.2, depth=0.5, feedback=0.6):
        return self._fx("flanger", mix=mix, rate=rate, depth=depth, feedback=feedback)

    def phaser(self, mix=0.4, rate=0.2, depth=0.5, freq=0.45, feedback=0.3):
        return self._fx("phaser", mix=mix, rate=rate, depth=depth, freq=freq, feedback=feedback)

    def chorus(self, mix=0.3, rate=0.25, delay=0.35, depth=0.45, feedback=0.0, tone=0.8):
        return self._fx("chorus", mix=mix, rate=rate, delay=delay, depth=depth, feedback=feedback, tone=tone)

    def delay(self, time="1/8", mix=0.2, feedback=0.35, pingpong=False, width=0.3, lowcut=0.25, highcut=0.55):
        self.set("delay.time", division(time)).set("delay.pingpong", 1 if pingpong else 0)
        return self._fx("delay", mix=mix, feedback=feedback, width=width, lowcut=lowcut, highcut=highcut)

    def comp(self, mode="SINGLE", threshold=0.6, ratio=0.4, attack=0.3, release=0.4, gain=0.0, depth=0.7, mix=1.0):
        self.set("comp.mode", enum("LY_COMP_" + mode))
        return self._fx("comp", threshold=threshold, ratio=ratio, attack=attack, release=release, gain=gain, depth=depth, mix=mix)

    def eq(self, low=0.0, low_hz=None, mid=0.0, mid_hz=None, q=0.4, high=0.0, high_hz=None):
        import math
        self.set("eq.on", 1).set("eq.lowGain", low / 18.0).set("eq.midGain", mid / 18.0).set("eq.highGain", high / 18.0)
        if low_hz:
            self.set("eq.lowFreq", math.log(low_hz / 20.0) / math.log(50.0))
        if mid_hz:
            self.set("eq.midFreq", math.log(mid_hz / 100.0) / math.log(100.0))
        if high_hz:
            self.set("eq.highFreq", math.log(high_hz / 1000.0) / math.log(20.0))
        self.set("eq.midQ", q)
        return self

    def fxfilter(self, type="LP", cut=0.7, res=0.2, drive=0.0, mix=1.0):
        self.set("fxfilter.type", enum("LY_FXF_" + type))
        return self._fx("fxfilter", cutoff=cut, res=res, drive=drive, mix=mix)

    def reverb(self, mix=0.2, mode="PLATE", size=0.5, decay=0.35, damp=0.45, width=0.9, predelay=0.15):
        """decay: plate t60 = 0.3 + d^2 * 8 s; hall 0.6 + d^2 * 18 s."""
        self.set("reverb.mode", enum("LY_REVERB_" + mode))
        return self._fx("reverb", mix=mix, size=size, decay=decay, damp=damp, width=width, predelay=predelay)

    def order(self, *names):
        """Effect order by name; unnamed effects follow in default order."""
        ids = {"HYPER": "LY_FX_HYPER", "DIST": "LY_FX_DIST", "FLANGER": "LY_FX_FLANGER", "PHASER": "LY_FX_PHASER",
               "CHORUS": "LY_FX_CHORUS", "DELAY": "LY_FX_DELAY", "COMP": "LY_FX_COMP", "EQ": "LY_FX_EQ",
               "FILTER": "LY_FX_FILTER", "REVERB": "LY_FX_REVERB"}
        default = ["HYPER", "DIST", "FLANGER", "PHASER", "CHORUS", "DELAY", "COMP", "REVERB", "EQ", "FILTER"]
        full = list(names) + [n for n in default if n not in names]
        for i, n in enumerate(full):
            self.set(f"fx.order{i}", enum(ids[n]))
        return self

    def _fx(self, prefix, **fields):
        self.set(f"{prefix}.on", 1)
        for field, value in fields.items():
            self.set(f"{prefix}.{field}", value)
        return self

    def master(self, value):
        return self.set("master", value)

    # -- documentation --------------------------------------------------
    def doc(self, role, register, genres, playing, layer, mix):
        assert layer in LAYERS, layer
        self.info = {"role": role, "register": register, "genres": genres, "playing": playing, "layer": layer, "mix": mix}
        return self

    def context(self, **kwargs):
        """How the tests play it: phrase, root, bpm, pitch check note..."""
        self.test.update(kwargs)
        return self

    # -- output ---------------------------------------------------------
    def validate(self):
        errors = []
        for key, value in self.values.items():
            p = PARAMS.get(key)
            if p is None:
                errors.append(f"unknown parameter {key}")
                continue
            if value < p["min"] - 1e-6 or value > p["max"] + 1e-6:
                errors.append(f"{key}={value} outside {p['min']}..{p['max']}")
            if p["stepped"] and abs(value - round(value)) > 1e-6:
                errors.append(f"{key}={value} must be whole")
        if not self.info:
            errors.append("no documentation")
        # Design-time safety: no bare screaming resonance outside the
        # resonant-by-design filters.
        for prefix in ("filter", "filter2"):
            if self.get(f"{prefix}.on") > 0.5:
                t = int(self.get(f"{prefix}.type"))
                res = self.get(f"{prefix}.res")
                if t not in (enum("LY_FILTER_COMB_POS"), enum("LY_FILTER_COMB_NEG"), enum("LY_FILTER_FORMANT")) and res > 0.72:
                    errors.append(f"{prefix}.res {res} is above the bank's 0.72 ceiling")
        if self.get("reverb.on") > 0.5:
            hall = self.get("reverb.mode") > 0.5
            d = self.get("reverb.decay")
            t60 = (0.6 + d * d * 18) if hall else (0.3 + d * d * 8)
            limit = {"PAD": 6.5, "DRONE": 8.0, "FX": 8.0}.get(self.category, 4.0)
            if t60 > limit:
                errors.append(f"reverb t60 {t60:.1f}s is over {limit}s for {self.category}")
        return errors

    def patch(self):
        values = {k: round(v, 5) for k, v in sorted(self.values.items())}
        return {"name": self.name, "values": values, "tableA": self.table_a, "tableB": self.table_b}

    def entry(self):
        return {"name": self.name, "category": self.category, "info": self.info, "patch": self.patch()}
