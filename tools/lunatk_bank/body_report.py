#!/usr/bin/env python3
"""Rule 5's measurement: how far each preset's fundamental sits below its
strongest partial on the held test note, and how much of the energy is in
the body octave (the note's own octave). Run after build.py has rendered.

  python3 tools/lunatk_bank/body_report.py [--worst 40]
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build as B  # noqa: E402
import phrases  # noqa: E402
import soundfile_shim as sf  # noqa: E402

SKIP = {"BASS", "PERC", "FX", "DRONE"}


def measure(path, note):
    x, sr = sf.read(path)
    x = np.asarray(x, float).mean(axis=1)[int(0.5 * sr):int(3.5 * sr)]
    S = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / sr)
    f0 = 440 * 2 ** ((note - 69) / 12)
    h1 = S[(f > f0 * 0.94) & (f < f0 * 1.06)].sum()
    strongest = max(S[(f > k * f0 * 0.97) & (f < k * f0 * 1.03)].sum() for k in range(1, 17))
    body = S[(f > f0 * 0.7) & (f < f0 * 1.45)].sum()
    return 10 * np.log10(h1 / strongest + 1e-12), 10 * np.log10(body / S.sum() + 1e-12)


def main():
    worst = int(sys.argv[sys.argv.index("--worst") + 1]) if "--worst" in sys.argv else 40
    rp = sys.argv[sys.argv.index("--report") + 1] if "--report" in sys.argv else os.path.join(B.WORK, "report.json")
    report = json.load(open(rp))
    rows = []
    for name, entry in report.items():
        cat = entry["category"]
        if cat in SKIP:
            continue
        path = os.path.join(B.WORK, "renders", f"{B.safe(name)}__pitch.wav")
        if not os.path.exists(path):
            continue
        note = phrases.DEFAULT_PITCH_NOTE[cat]
        h1, body = measure(path, note)
        rows.append((h1, body, cat, name))
    rows.sort()
    print(f"{'preset':26s} {'cat':6s} {'h1 vs loudest':>14s} {'body share':>11s}")
    for h1, body, cat, name in rows[:worst]:
        print(f"{name:26s} {cat:6s} {h1:12.1f} dB {body:9.1f} dB")
    print(f"\n{sum(1 for r in rows if r[0] < -12)} of {len(rows)} melodic presets have a fundamental more than 12 dB under their loudest partial")


if __name__ == "__main__":
    main()
