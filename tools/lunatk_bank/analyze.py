"""Measures rendered presets and enforces the bank's gates.

Every gate is a number, so "song-usable" is checked, not asserted:
loudness on target, headroom, DC, low end that leaves room for kick and
bass (or, for basses, a mono low end), controlled top end, sane width and
mono fold-down, finite tails, silence after release, in tune, macros that
never blow up the level, MOTION that really stops the movement, velocity
that does something, and CPU.
"""

import math
import numpy as np
import soundfile_shim as sf
from scipy import signal

SR = 48000

TARGET_LUFS = {"BASS": -16, "LEAD": -16, "PAD": -18, "KEYS": -17, "PLUCK": -17, "MOTION": -17, "DRONE": -20, "PERC": -15, "FX": -18}
TAIL_LIMIT = {"BASS": 1.2, "LEAD": 3.0, "PAD": 6.5, "KEYS": 3.5, "PLUCK": 3.0, "MOTION": 4.5, "DRONE": 8.0, "PERC": 1.5, "FX": 8.0}
WIDTH_LIMIT = {"BASS": -10, "LEAD": -5, "PERC": -8}
LOW_LIMIT = {"PAD": -15, "KEYS": -15, "LEAD": -15, "PLUCK": -15, "MOTION": -14, "FX": -8}
VELOCITY_CATEGORIES = {"BASS", "LEAD", "KEYS", "PLUCK", "PERC"}


# -- loudness (ITU-R BS.1770-4) -------------------------------------------
def _k_weight(x):
    # Pre-filter (high shelf) and RLB high-pass at 48 kHz, from the standard.
    b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285]
    a1 = [1.0, -1.69065929318241, 0.73248077421585]
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, -1.99004745483398, 0.99007225036621]
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def lufs(stereo):
    if len(stereo) < SR * 0.4:
        stereo = np.pad(stereo, ((0, int(SR * 0.4) - len(stereo)), (0, 0)))
    y = _k_weight(stereo)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    powers = []
    for start in range(0, len(y) - block + 1, hop):
        seg = y[start:start + block]
        powers.append(np.mean(seg[:, 0] ** 2) + np.mean(seg[:, 1] ** 2))
    powers = np.array(powers)
    loud = -0.691 + 10 * np.log10(np.maximum(powers, 1e-12))
    gated = powers[loud > -70]
    if len(gated) == 0:
        return -99.0
    rel = -0.691 + 10 * np.log10(np.mean(gated)) - 10
    gated = powers[(loud > -70) & (loud > rel)]
    if len(gated) == 0:
        return -99.0
    return float(-0.691 + 10 * np.log10(np.mean(gated)))


def db(x):
    return 10 * math.log10(max(x, 1e-20))


def band_energy(mono, lo, hi):
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1 / SR)
    return float(np.sum(spec[(freqs >= lo) & (freqs < hi)])), float(np.sum(spec[freqs >= 20]))


def rms_envelope(x, window=0.02):
    n = int(window * SR)
    mono = np.mean(x, axis=1) if x.ndim == 2 else x
    frames = len(mono) // n
    if frames == 0:
        return np.zeros(1)
    return np.sqrt(np.mean(mono[:frames * n].reshape(frames, n) ** 2, axis=1) + 1e-20)


def f0_estimate(mono):
    """Autocorrelation pitch of a steady segment, Hz."""
    x = mono - np.mean(mono)
    x = x[: min(len(x), SR)]
    if np.max(np.abs(x)) < 1e-4:
        return None
    corr = signal.fftconvolve(x, x[::-1], mode="full")[len(x) - 1:]
    corr /= corr[0] + 1e-12
    lo, hi = int(SR / 2000), int(SR / 25)
    seg = corr[lo:hi]
    if len(seg) == 0:
        return None
    peak = int(np.argmax(seg)) + lo
    # Earliest peak close to the best one avoids octave-down picks.
    threshold = corr[peak] * 0.9
    for i in range(lo + 1, hi - 1):
        if corr[i] >= threshold and corr[i] >= corr[i - 1] and corr[i] >= corr[i + 1]:
            peak = i
            break
    if peak + 1 < len(corr):
        a, b, c = corr[peak - 1], corr[peak], corr[peak + 1]
        denom = a - 2 * b + c
        shift = 0.5 * (a - c) / denom if abs(denom) > 1e-12 else 0
    else:
        shift = 0
    return SR / (peak + shift)


def motion_index(x, start, end):
    """Spectral flux of a held note: mean change of the log spectrum from one
    46 ms frame to the next. A static tone reads near 0; vibrato, filter or
    wavetable movement and tremolo all raise it."""
    mono = np.mean(x, axis=1)
    seg = mono[int(start * SR):int(end * SR)]
    n, hop = 2048, 1024
    frames = (len(seg) - n) // hop
    if frames < 4:
        return 0.0
    win = np.hanning(n)
    spectra = []
    for f in range(frames):
        spec = np.abs(np.fft.rfft(seg[f * hop:f * hop + n] * win))[:600]
        spectra.append(20 * np.log10(spec + 1e-6))
    spectra = np.array(spectra)
    top = np.max(spectra)
    spectra = np.maximum(spectra, top - 50)  # ignore the noise floor
    flux = float(np.mean(np.abs(np.diff(spectra, axis=0))))
    # Slow movement barely changes frame to frame, so also take each bin's
    # spread over the whole hold (loud bins only).
    loud = np.mean(spectra, axis=0) > top - 40
    spread = float(np.mean(np.std(spectra[:, loud], axis=0))) if np.any(loud) else 0.0
    level = 20 * np.log10(rms_envelope(np.stack([seg, seg], axis=1), 0.02) + 1e-9)
    level = level[level > np.max(level) - 40]
    return flux + spread + (float(np.std(level)) if len(level) > 4 else 0.0)


def spectral_difference(a, b, start, end):
    """Mean dB difference between two renders of the same notes, over loud
    bins. The engine is deterministic, so this is what one setting changes."""
    ma, mb = np.mean(a, axis=1), np.mean(b, axis=1)
    sa, sb = ma[int(start * SR):int(end * SR)], mb[int(start * SR):int(end * SR)]
    n, hop = 2048, 1024
    frames = (min(len(sa), len(sb)) - n) // hop
    if frames < 2:
        return 0.0
    win = np.hanning(n)
    total = []
    for f in range(frames):
        xa = 20 * np.log10(np.abs(np.fft.rfft(sa[f * hop:f * hop + n] * win))[:800] + 1e-6)
        xb = 20 * np.log10(np.abs(np.fft.rfft(sb[f * hop:f * hop + n] * win))[:800] + 1e-6)
        top = max(np.max(xa), np.max(xb))
        loud = (xa > top - 40) | (xb > top - 40)
        if np.any(loud):
            total.append(np.mean(np.abs(np.maximum(xa, top - 50) - np.maximum(xb, top - 50))[loud]))
    return float(np.mean(total)) if total else 0.0


def analyze_main(x, category, info):
    mono = np.mean(x, axis=1)
    side = 0.5 * (x[:, 0] - x[:, 1])
    mid = 0.5 * (x[:, 0] + x[:, 1])
    out = {}
    out["lufs"] = lufs(x)
    out["peak_db"] = 20 * math.log10(max(np.max(np.abs(x)), 1e-9))
    out["nan"] = bool(not np.all(np.isfinite(x)))
    low, total = band_energy(mono, 20, 80)
    out["low_db"] = db(low) - db(total)
    rumble, _ = band_energy(mono, 5, 35)
    out["rumble_db"] = db(rumble) - db(total)
    low150, _ = band_energy(mono, 20, 150)
    out["low150_db"] = db(low150) - db(total)
    sub_side, _ = band_energy(side, 20, 150)
    sub_mid, _ = band_energy(mid, 20, 150)
    out["low_side_db"] = db(sub_side) - db(sub_mid)
    high, _ = band_energy(mono, 10000, 24000)
    out["high_db"] = db(high) - db(total)
    presence, _ = band_energy(mono, 2000, 6000)
    out["presence_db"] = db(presence) - db(total)
    out["width_db"] = db(float(np.sum(side ** 2))) - db(float(np.sum(mid ** 2)))
    mono_st = np.stack([mid, mid], axis=1)
    out["mono_loss_db"] = out["lufs"] - lufs(mono_st)
    denom = math.sqrt(float(np.sum(x[:, 0] ** 2)) * float(np.sum(x[:, 1] ** 2))) + 1e-12
    out["correlation"] = float(np.sum(x[:, 0] * x[:, 1]) / denom)
    env = rms_envelope(x)
    ref = float(np.max(env))
    off = info["last_off"]
    above = np.where(env > ref * 10 ** (-60 / 20))[0]
    last = (above[-1] + 1) * 0.02 if len(above) else 0.0
    out["tail_s"] = max(0.0, last - off)
    out["tail_open"] = bool(len(above) and above[-1] >= len(env) - 3)
    end = x[-int(0.3 * SR):]
    out["end_db"] = 20 * math.log10(math.sqrt(float(np.mean(end ** 2))) + 1e-12)
    out["centroid"] = centroid(mono)
    return out


def centroid(mono):
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    freqs = np.fft.rfftfreq(len(mono), 1 / SR)
    return float(np.sum(freqs * spec) / (np.sum(spec) + 1e-12))


def gates(category, m, flags):
    fails, warns = [], []
    target = TARGET_LUFS[category]
    if m["nan"]:
        fails.append("non-finite samples")
    if abs(m["lufs"] - target) > 1.5:
        fails.append(f"loudness {m['lufs']:.1f} LUFS, target {target}")
    if m["peak_db"] > -0.5:
        fails.append(f"peak {m['peak_db']:.1f} dBFS")
    if m.get("dc", 0) > 0.006:
        fails.append(f"DC {m['dc']:.4f}")
    if category in LOW_LIMIT and not flags.get("allow_low") and m["low_db"] > LOW_LIMIT[category]:
        fails.append(f"low end {m['low_db']:.1f} dB below 80 Hz (limit {LOW_LIMIT[category]})")
    if m["rumble_db"] > -18:
        fails.append(f"sub-rumble {m['rumble_db']:.1f} dB under 35 Hz")
    if m["low150_db"] > -25 and m["low_side_db"] > -18:
        fails.append(f"low end not mono: side {m['low_side_db']:.1f} dB under 150 Hz")
    if not flags.get("allow_air") and m["high_db"] > -14:
        fails.append(f"top end {m['high_db']:.1f} dB above 10 kHz")
    limit = WIDTH_LIMIT.get(category, -1)
    if m["width_db"] > limit:
        fails.append(f"width {m['width_db']:.1f} dB side/mid (limit {limit})")
    if m["mono_loss_db"] > 3:
        fails.append(f"loses {m['mono_loss_db']:.1f} dB in mono")
    if m["correlation"] < 0.1:
        fails.append(f"L/R correlation {m['correlation']:.2f}")
    if m["tail_s"] > TAIL_LIMIT[category]:
        fails.append(f"tail {m['tail_s']:.1f}s (limit {TAIL_LIMIT[category]})")
    if m["tail_open"]:
        fails.append("still sounding at the end of the render")
    if m["end_db"] > -70 and not m["tail_open"]:
        warns.append(f"residual {m['end_db']:.0f} dBFS at the end")
    return fails, warns


def pitch_gate(x, note, flags):
    if flags.get("unpitched"):
        return [], None
    mono = np.mean(x, axis=1)
    seg = mono[int(0.6 * SR):int(1.8 * SR)]
    f0 = f0_estimate(seg)
    if f0 is None:
        return ["held note is silent"], None
    expected = 440 * 2 ** ((note - 69) / 12)
    cents = 1200 * math.log2(f0 / expected)
    folded = ((cents + 600) % 1200) - 600
    # A fifth stack can read as the fifth; accept those intervals when declared.
    ok = abs(folded) <= 30 or (flags.get("fifths") and min(abs(folded - 702), abs(folded + 498)) <= 30)
    return ([] if ok else [f"out of tune: {folded:+.0f} cents"]), folded


# -- reference arrangement ---------------------------------------------
def _env(t, decay):
    return np.exp(-t / decay)


def arrangement(bpm, seconds, with_bass=True, with_chords=False, four_floor=True, seed=7):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    out = np.zeros((n, 2))
    beat = 60.0 / bpm
    t_hit = np.arange(int(0.5 * SR)) / SR
    kick = np.sin(2 * np.pi * np.cumsum(45 + 110 * _env(t_hit, 0.03)) / SR) * _env(t_hit, 0.32)
    tnoise = rng.standard_normal(len(t_hit))
    b, a = signal.butter(2, [1200 / (SR / 2), 5000 / (SR / 2)], btype="band")
    snare = 0.6 * signal.lfilter(b, a, tnoise) * _env(t_hit, 0.14) + 0.4 * np.sin(2 * np.pi * 190 * t_hit) * _env(t_hit, 0.08)
    bh, ah = signal.butter(2, 7000 / (SR / 2), btype="high")
    hat = signal.lfilter(bh, ah, tnoise) * _env(t_hit, 0.035)

    def place(sample, time, gain, pan=0.0):
        i = int(time * SR)
        if i >= n:
            return
        seg = sample[: n - i] * gain
        out[i:i + len(seg), 0] += seg * (1 - max(pan, 0))
        out[i:i + len(seg), 1] += seg * (1 + min(pan, 0))

    beats = int(seconds / beat)
    for k in range(beats):
        tk = k * beat
        if four_floor or k % 2 == 0:
            place(kick, tk, 0.9)
        if k % 2 == 1:
            place(snare, tk, 0.55)
        place(hat, tk + beat / 2, 0.25, 0.3)
        place(hat, tk, 0.15, -0.3)
    roots = [33, 29, 28, 31]
    if with_bass:
        for k in range(beats):
            root = roots[(k // 8) % 4]
            hz = 440 * 2 ** ((root - 69) / 12)
            length = int(beat * 0.9 * SR)
            tt = np.arange(length) / SR
            tone = np.sin(2 * np.pi * hz * tt) + 0.25 * np.sin(2 * np.pi * hz * 2 * tt)
            place(tone * np.minimum(1, tt / 0.005) * _env(tt, 0.6), k * beat, 0.35)
    if with_chords:
        voicings = [[57, 60, 64, 67], [53, 57, 60, 64], [52, 55, 60, 62], [55, 60, 62, 64]]
        bl, al = signal.butter(2, 1500 / (SR / 2))
        for k in range(0, beats, 8):
            chord = voicings[(k // 8) % 4]
            length = int(min(8 * beat, seconds - k * beat) * SR)
            if length <= 0:
                continue
            tt = np.arange(length) / SR
            tone = sum(signal.sawtooth(2 * np.pi * 440 * 2 ** ((m - 69) / 12) * tt) for m in chord) / len(chord)
            tone = signal.lfilter(bl, al, tone) * np.minimum(1, tt / 0.2) * np.minimum(1, (tt[-1] - tt + 1e-3) / 0.2)
            place(tone, k * beat, 0.25)
    return out
