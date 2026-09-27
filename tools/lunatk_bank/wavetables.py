#!/usr/bin/env python3
"""Builds the NIGHTSHAPE factory wavetables shipped with LUNATK.

  python3 tools/lunatk_bank/wavetables.py

Each table is 64 frames of 2048 samples, written as a Serum-layout WAV (mono
32-bit float, frames end to end) to LYLLTH/Synth/Wavetables. Every frame is
DC-free and matched in loudness to its neighbours, so scanning a table
changes timbre, not level. The engine band-limits tables when it loads them.
"""

import os
import struct

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "LYLLTH", "Synth", "Wavetables")
N = 2048
FRAMES = 64
PHASE = np.arange(N) / N
H = 256  # harmonics used by the additive tables


def additive(amps, phases=None):
    """One frame from harmonic amplitudes (index 0 = fundamental)."""
    n = np.arange(1, len(amps) + 1)
    ph = np.zeros(len(amps)) if phases is None else phases
    return np.sum(amps[:, None] * np.sin(2 * np.pi * n[:, None] * PHASE[None, :] + ph[:, None]), axis=0)


def finish(frames):
    out = []
    for f in frames:
        f = f - np.mean(f)
        rms = np.sqrt(np.mean(f ** 2))
        out.append(f / max(rms, 1e-9))
    table = np.array(out)
    return (table / np.max(np.abs(table)) * 0.95).astype(np.float32)


def write(name, frames):
    data = finish(frames).reshape(-1)
    path = os.path.join(OUT, f"{name}.wav")
    body = data.tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 3, 1, 48000, 48000 * 4, 4, 32))
        f.write(b"data" + struct.pack("<I", len(body)) + body)
    print(f"{name}: {len(frames)} frames")


def t_of(i):
    return i / (FRAMES - 1)


def obsidian():
    """A saw whose phase bends and folds: warm at 0, a torn asymmetric edge at 1."""
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        p = PHASE ** (1 + 2.5 * t)                      # phase distortion
        saw = 2 * p - 1
        fold = np.sin(np.pi * 0.5 * (1 + 3 * t) * saw)  # soft fold grows
        frames.append((1 - 0.6 * t) * saw + 0.6 * t * fold + 0.25 * t * np.abs(saw) ** 3)
    return frames


def throat():
    """A glottal source through a formant bank walking U O A E I."""
    vowels = [(300, 870, 2240), (500, 900, 2400), (730, 1090, 2440), (530, 1840, 2480), (270, 2290, 3010)]
    f0 = 110.0
    n = np.arange(1, H + 1)
    frames = []
    for i in range(FRAMES):
        x = t_of(i) * (len(vowels) - 1)
        a, b = int(np.floor(x)), min(int(np.floor(x)) + 1, len(vowels) - 1)
        w = x - a
        formants = [(1 - w) * va + w * vb for va, vb in zip(vowels[a], vowels[b])]
        source = 1.0 / n ** 1.2
        env = np.zeros(H)
        for k, (fc, bw, g) in enumerate(zip(formants, (80, 110, 160), (1.0, 0.6, 0.35))):
            env += g / (1 + ((n * f0 - fc) / bw) ** 2)
        frames.append(additive(source * (0.05 + env)))
    return frames


def radiant():
    """Additive: a dark, nearly sine tone that opens into a radiant, even-rich top."""
    n = np.arange(1, H + 1)
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        tilt = 2.6 - 1.7 * t
        even = 0.4 + 0.6 * t
        amps = (1.0 / n ** tilt) * np.where(n % 2 == 0, even, 1.0)
        frames.append(additive(amps))
    return frames


def hollow_bone():
    """Sparse harmonic sets crossfading: hollow, bell-like, never inharmonic."""
    sets = [[1, 3, 5, 7], [1, 2, 5, 11], [1, 4, 9, 16], [1, 7, 13, 19], [1, 3, 11, 23, 31]]
    frames = []
    for i in range(FRAMES):
        x = t_of(i) * (len(sets) - 1)
        a, b = int(np.floor(x)), min(int(np.floor(x)) + 1, len(sets) - 1)
        w = x - a
        amps = np.zeros(40)
        for k, h in enumerate(sets[a]):
            amps[h - 1] += (1 - w) * (1.0 / (1 + k * 0.6))
        for k, h in enumerate(sets[b]):
            amps[h - 1] += w * (1.0 / (1 + k * 0.6))
        frames.append(additive(amps))
    return frames


def fracture():
    """A sine ground down: amplitude steps and a sample-rate stumble."""
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        levels = int(round(48 * (1 - t) ** 2 + 3))
        hold = int(round(1 + 60 * t ** 1.6))
        x = np.sin(2 * np.pi * PHASE)
        x = np.repeat(x[::hold], hold)[:N]
        x = np.round(x * levels) / levels
        frames.append(x)
    return frames


def serpent():
    """Smooth hard sync: a slave saw from 1x to 9x, windowed so the reset never clicks."""
    window = 0.5 - 0.5 * np.cos(2 * np.pi * PHASE)
    frames = []
    for i in range(FRAMES):
        ratio = 1 + 8 * t_of(i) ** 1.3
        slave = 2 * ((PHASE * ratio) % 1.0) - 1
        frames.append(slave * (0.35 + 0.65 * window))
    return frames


def grindstone():
    """FM growl: the index climbs from 0 to 7 with a second, octave modulator."""
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        idx = 7 * t ** 1.5
        mod = np.sin(2 * np.pi * PHASE) + 0.4 * np.sin(4 * np.pi * PHASE)
        x = np.sin(2 * np.pi * PHASE + idx * mod)
        frames.append(np.tanh((1 + 2 * t) * x))
    return frames


def cathedral_metal():
    """A 1/n body with resonant harmonic clusters climbing through it: cold metal, still in tune."""
    n = np.arange(1, H + 1)
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        amps = 1.0 / n ** 1.3
        for centre, gain in ((6 + 20 * t, 3.0), (13 + 40 * t, 2.2), (27 + 60 * t, 1.6)):
            amps = amps + gain * amps[0] * 0.15 * np.exp(-0.5 * ((n - centre) / 1.2) ** 2)
        frames.append(additive(amps))
    return frames


def scar_pulse():
    """A pulse narrowing from square to a needle, with an inverted notch travelling through it."""
    frames = []
    for i in range(FRAMES):
        t = t_of(i)
        width = 0.5 - 0.46 * t
        x = np.where(PHASE < width, 1.0, -1.0)
        centre = 0.55 + 0.35 * t
        notch = np.abs(PHASE - centre) < 0.03 + 0.02 * t
        x = np.where(notch, -x * 0.6, x)
        frames.append(x)
    return frames


def tendon():
    """A sine folded back on itself, harder frame by frame: smooth growl, no aliasing edges."""
    frames = []
    for i in range(FRAMES):
        drive = 1 + 11 * t_of(i) ** 1.4
        x = np.sin(2 * np.pi * PHASE)
        frames.append(np.sin(0.5 * np.pi * drive * x))
    return frames


def neon_nerve():
    """A resonant peak baked into a saw spectrum, sweeping from the 2nd to the 48th harmonic."""
    n = np.arange(1, H + 1)
    frames = []
    for i in range(FRAMES):
        centre = 2 * (24 ** t_of(i))
        peak = 1 + 6 / (1 + ((n - centre) / (0.6 + 0.08 * centre)) ** 2)
        frames.append(additive((1.0 / n) * peak))
    return frames


def dust_oracle():
    """A seeded random walk through harmonic spectra: every region of the table is different."""
    rng = np.random.default_rng(1983)
    n = np.arange(1, 97)
    keys = [rng.uniform(0.1, 1.0, len(n)) / n ** 0.9 for _ in range(9)]
    frames = []
    for i in range(FRAMES):
        x = t_of(i) * (len(keys) - 1)
        a, b = int(np.floor(x)), min(int(np.floor(x)) + 1, len(keys) - 1)
        w = x - a
        w = w * w * (3 - 2 * w)
        frames.append(additive((1 - w) * keys[a] + w * keys[b]))
    return frames


TABLES = {
    "NS OBSIDIAN": obsidian, "NS THROAT": throat, "NS RADIANT": radiant, "NS HOLLOW BONE": hollow_bone,
    "NS FRACTURE": fracture, "NS SERPENT": serpent, "NS GRINDSTONE": grindstone,
    "NS CATHEDRAL METAL": cathedral_metal, "NS SCAR PULSE": scar_pulse, "NS TENDON": tendon,
    "NS NEON NERVE": neon_nerve, "NS DUST ORACLE": dust_oracle,
}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, build in TABLES.items():
        write(name, build())
