#!/usr/bin/env python3
"""Builds, renders, measures and ships the LUNATK factory bank.

  python3 tools/lunatk_bank/build.py                 validate + render + gate everything
  python3 tools/lunatk_bank/build.py --category BASS  one category
  python3 tools/lunatk_bank/build.py --only "NAME"    one preset
  python3 tools/lunatk_bank/build.py --level          also store level corrections (then run again)
  python3 tools/lunatk_bank/build.py --ship           write the bank resource + docs (all gates must pass)

Exits non-zero if any preset fails a gate.
"""

import argparse
import glob
import importlib
import json
import math
import os
import subprocess
import sys

import warnings

import numpy as np

warnings.filterwarnings("ignore")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lunatk as L  # noqa: E402
import phrases  # noqa: E402
import analyze as A  # noqa: E402
import soundfile_shim as sf  # noqa: E402

ROOT = L.ROOT
WORK = os.environ.get("LUNATK_WORK", os.path.join(ROOT, "build", "lunatk_bank"))
LEVELS = os.path.join(HERE, "levels.json")
RESOURCE = os.path.join(ROOT, "LYLLTH", "Synth", "LUNATKFactory.json")
DOCS = os.path.join(ROOT, "LUNATK", "FACTORY_BANK.md")
DERIVED = os.environ.get("LUNATK_DERIVED", os.path.join(ROOT, "build", "DerivedData"))
# Where movement is heard: plucks and hits move while they decay.
DEFAULT_WINDOW = {"PLUCK": (0.03, 1.2), "PERC": (0.0, 0.8)}
MACROS = [(0, 0.0), (0, 1.0), (1, 0.0), (1, 1.0), (2, 0.0), (2, 1.0), (3, 1.0)]


def run_renders():
    cmd = ["xcodebuild", "-project", os.path.join(ROOT, "LYLLTH.xcodeproj"), "-scheme", "LYLLTH", "-configuration", "Debug",
           "-derivedDataPath", DERIVED, "test", "-only-testing:LYLLTHTests/LUNATKBankRenderTests"]
    env = dict(os.environ, TEST_RUNNER_LUNATK_BANK_DIR=WORK)
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if "** TEST SUCCEEDED **" not in result.stdout:
        print(result.stdout[-3000:])
        raise SystemExit("render run failed")


def load_bank():
    presets = []
    for path in sorted(glob.glob(os.path.join(HERE, "bank", "*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name.startswith("_"):
            continue
        module = importlib.import_module("bank." + name)
        presets.extend(module.presets())
    names = [p.name for p in presets]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        raise SystemExit(f"duplicate names: {sorted(dupes)}")
    return presets


def apply_levels(p, level):
    """Stored corrections: MASTER for the category's loudness, and a
    MACRO 4 -> MASTER route so GRIT changes character, not level."""
    if not level:
        return
    if isinstance(level, (int, float)):
        level = {"master": level}
    p.master(level["master"])
    if level.get("trim"):
        # Clean makeup gain: the compressor with its threshold at 0 dBFS.
        p.comp(mode="SINGLE", threshold=1.0, ratio=0.0, attack=0.0, release=0.2, gain=level["trim"], depth=0.0, mix=1.0)
    if level.get("grit"):
        p.mod("MACRO4", "MASTER", level["grit"])


def safe(name):
    return "".join(c if c.isalnum() else "_" for c in name)


def plan_for(p):
    main = phrases.main_phrase(p.category, p.test)
    renders = [dict(file=f"{safe(p.name)}__main.wav", bpm=main["bpm"], seconds=main["seconds"], notes=main["notes"])]
    note = p.test.get("pitch_note", phrases.DEFAULT_PITCH_NOTE[p.category])
    held = phrases.held(note, seconds=4.5, bpm=main["bpm"])
    base = [p.get("macro1"), p.get("macro2"), p.get("macro3"), p.get("macro4")]
    renders.append(dict(file=f"{safe(p.name)}__pitch.wav", bpm=held["bpm"], seconds=held["seconds"], notes=held["notes"]))
    still = list(base)
    still[1] = 0.0
    renders.append(dict(file=f"{safe(p.name)}__still.wav", bpm=held["bpm"], seconds=held["seconds"], notes=held["notes"], macros=still))
    full = list(base)
    full[1] = 1.0
    renders.append(dict(file=f"{safe(p.name)}__moving.wav", bpm=held["bpm"], seconds=held["seconds"], notes=held["notes"], macros=full))
    for index, value in MACROS:
        macros = list(base)
        macros[index] = value
        renders.append(dict(file=f"{safe(p.name)}__m{index + 1}_{int(value)}.wav", bpm=main["bpm"], seconds=main["seconds"],
                            notes=main["notes"], macros=macros))
    if p.category in A.VELOCITY_CATEGORIES:
        soft = [[n[0], n[1], max(1, int(n[2] * 0.35)), n[3]] for n in main["notes"]]
        renders.append(dict(file=f"{safe(p.name)}__soft.wav", bpm=main["bpm"], seconds=main["seconds"], notes=soft))
    return main, renders


def uses_motion(p):
    m2 = L.enum("LY_SRC_MACRO2")
    return any(p.get(f"mx{i}.aux") == m2 or p.get(f"mx{i}.src") == m2 for i in range(len(p.slots)))


def evaluate(p, main, timings):
    r = lambda suffix: sf.read(os.path.join(WORK, "renders", f"{safe(p.name)}__{suffix}.wav"))[0]
    x = r("main")
    last_off = main["last_off_beat"] * 60 / main["bpm"]
    m = A.analyze_main(x, p.category, {"last_off": last_off})
    fails, warns = A.gates(p.category, m, p.test)
    note = p.test.get("pitch_note", phrases.DEFAULT_PITCH_NOTE[p.category])
    held = r("pitch")
    m["dc"] = float(abs(np.mean(held[int(0.5 * A.SR):int(4.0 * A.SR)])))
    if m["dc"] > 0.006:
        fails.append(f"DC {m['dc']:.4f} on a held note")
    pfails, cents = A.pitch_gate(held, note, p.test)
    fails += pfails
    m["cents"] = cents
    # Macros: never an explosion or a disappearance.
    m["macros"] = {}
    for index, value in MACROS:
        y = r(f"m{index + 1}_{int(value)}")
        level = A.lufs(y)
        peak = 20 * math.log10(max(np.max(np.abs(y)), 1e-9))
        m["macros"][f"M{index + 1}={int(value)}"] = round(level - m["lufs"], 1)
        m["macros"][f"M{index + 1}={int(value)} peak"] = round(peak, 1)
        if level - m["lufs"] > 4 or level - m["lufs"] < -15:
            fails.append(f"MACRO {index + 1} at {int(value)} moves the level {level - m['lufs']:+.1f} dB")
        if peak > -0.1:
            fails.append(f"MACRO {index + 1} at {int(value)} peaks at {peak:.1f} dBFS")
    # MOTION must be able to stop the movement.
    if uses_motion(p):
        w0, w1 = p.test.get("motion_window", DEFAULT_WINDOW.get(p.category, (0.8, 4.3)))
        still = A.motion_index(r("still"), w0, w1)
        default = A.motion_index(r("pitch"), w0, w1)
        full = A.motion_index(r("moving"), w0, w1)
        m["motion"] = [round(still, 3), round(default, 3), round(full, 3)]
        change = A.spectral_difference(r("still"), r("moving"), w0, w1)
        m["motion"].append(round(change, 2))
        if change < 1.0:
            fails.append(f"MOTION changes the sound by only {change:.2f} dB between 0 and 1")
        if still > default + max(0.4, 0.12 * default):
            fails.append(f"MOTION at 0 moves more than the default ({still:.3f} vs {default:.3f})")
    if p.category in A.VELOCITY_CATEGORIES and not p.test.get("no_velocity"):
        y = r("soft")
        dl = A.lufs(y) - m["lufs"]
        dc = A.centroid(np.mean(y, axis=1)) / max(m["centroid"], 1)
        m["velocity"] = [round(dl, 1), round(dc, 2)]
        if dl > -2 and dc > 0.9:
            fails.append(f"velocity does nothing ({dl:+.1f} dB, brightness x{dc:.2f})")
    t = timings.get(f"{safe(p.name)}__main.wav")
    if t:
        m["cpu"] = round(t["renderSeconds"] / t["audioSeconds"], 4)
        if m["cpu"] > 0.12:
            fails.append(f"CPU {m['cpu'] * 100:.1f}% of a core on the phrase")
        elif m["cpu"] > 0.06:
            warns.append(f"CPU {m['cpu'] * 100:.1f}% of a core")
    return m, fails, warns


def context_mix(p, main):
    x, _ = sf.read(os.path.join(WORK, "renders", f"{safe(p.name)}__main.wav"))
    cat = p.category
    bed = A.arrangement(main["bpm"], len(x) / A.SR, with_bass=cat not in ("BASS",), with_chords=cat in ("BASS", "PERC"),
                        four_floor=cat not in ("PAD", "DRONE"))
    bed = bed[: len(x)]
    bed *= 10 ** ((-16 - A.lufs(bed)) / 20)
    mix = bed + x
    peak = np.max(np.abs(mix))
    if peak > 0.89:
        mix *= 0.89 / peak
    os.makedirs(os.path.join(WORK, "context"), exist_ok=True)
    sf.write(os.path.join(WORK, "context", f"{p.category}__{safe(p.name)}.wav"), mix)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--category")
    ap.add_argument("--level", action="store_true")
    ap.add_argument("--ship", action="store_true")
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()

    os.makedirs(WORK, exist_ok=True)
    params = os.path.join(WORK, "params.json")
    if not os.path.exists(params):
        if os.path.exists(os.path.join(WORK, "plan.json")):
            os.remove(os.path.join(WORK, "plan.json"))
        run_renders()
    L.load_params(params)

    levels = json.load(open(LEVELS)) if os.path.exists(LEVELS) else {}
    bank = load_bank()
    for p in bank:
        apply_levels(p, levels.get(p.name))
    errors = {p.name: e for p in bank for e in [p.validate()] if e}
    if errors:
        for name, e in errors.items():
            print(f"INVALID {name}: {'; '.join(e)}")
        raise SystemExit(1)

    selected = [p for p in bank if (not args.only or p.name in [o.upper() for o in args.only])
                and (not args.category or p.category == args.category)]
    plans = {}
    plan = {"sampleRate": 48000, "presets": []}
    for p in selected:
        main_phrase, renders = plan_for(p)
        plans[p.name] = main_phrase
        plan["presets"].append({"name": p.name, "patch": p.patch(), "renders": renders})
    json.dump(plan, open(os.path.join(WORK, "plan.json"), "w"))
    if not args.no_render:
        run_renders()
    timings = {t["file"]: t for t in json.load(open(os.path.join(WORK, "timings.json")))}

    report = {}
    failed = 0
    for p in selected:
        m, fails, warns = evaluate(p, plans[p.name], timings)
        context_mix(p, plans[p.name])
        target = A.TARGET_LUFS[p.category]
        master = p.get("master")
        entry0 = levels.get(p.name) if isinstance(levels.get(p.name), dict) else {}
        trim_db = entry0.get("trim", 0.0) * 24
        # Loudness target, but never past -1 dBFS peak at any macro position.
        peaks = [m["peak_db"]] + [v for k, v in m["macros"].items() if k.endswith("peak") and not k.startswith("M4")]
        gain_db = min(target - m["lufs"], -1.0 - max(peaks))
        wanted = master * 10 ** (gain_db / 20)
        uses_comp = p.values.get("comp.on", 0) > 0.5 and not entry0.get("trim")
        if wanted > 1.0 and not uses_comp:
            trim_db = max(0.0, trim_db + 20 * math.log10(wanted))
            suggested = 1.0
        else:
            if wanted < 0.85 and trim_db > 0:
                cut = min(trim_db, -20 * math.log10(wanted / 0.85))
                trim_db -= cut
                wanted *= 10 ** (cut / 20)
            suggested = min(1.0, wanted)
        if args.level:
            entry = levels.get(p.name) or {}
            if isinstance(entry, (int, float)):
                entry = {"master": entry}
            # GRIT: aim for at most +1 dB at full, in the new master's terms.
            grit_db = max(m["macros"].get("M4=1", 0), m["macros"].get("M4=1 peak", -99) + 1.5 + 1.0)
            old_grit = entry.get("grit", 0.0)
            gain_now = master + old_grit
            wanted = gain_now * 10 ** (min(0.0, 1.0 - grit_db) / 20)
            new_grit = (wanted - master) * (suggested / max(master, 1e-6))
            entry["master"] = round(suggested, 4)
            if trim_db > 0.05:
                entry["trim"] = round(min(trim_db / 24, 1.0), 4)
            else:
                entry.pop("trim", None)
            entry["grit"] = round(max(-0.9, min(0.0, new_grit)), 4)
            levels[p.name] = entry
        if suggested >= 0.999 and m["lufs"] < target - 1.5 and uses_comp:
            fails.append("too quiet at full MASTER and its compressor is in use")
        report[p.name] = {"category": p.category, "metrics": m, "fails": fails, "warnings": warns, "master": master}
        status = "PASS" if not fails else "FAIL"
        failed += bool(fails)
        print(f"{status}  {p.category:7} {p.name:24} {m['lufs']:6.1f} LUFS  low {m['low_db']:6.1f}  hi {m['high_db']:6.1f}  "
              f"width {m['width_db']:6.1f}  tail {m['tail_s']:4.1f}s  cpu {m.get('cpu', 0) * 100:4.1f}%"
              + ("" if not fails else "\n      - " + "\n      - ".join(fails)))
    if args.level:
        json.dump(levels, open(LEVELS, "w"), indent=1, sort_keys=True)
    json.dump(report, open(os.path.join(WORK, "report.json"), "w"), indent=1)
    print(f"\n{len(selected) - failed}/{len(selected)} pass")

    if args.ship:
        if failed or len(selected) != len(bank):
            raise SystemExit("ship needs every preset rendered and passing")
        ship(bank, report)
    raise SystemExit(1 if failed else 0)


def ship(bank, report):
    entries = [p.entry() for p in bank]
    json.dump({"version": 1, "presets": entries}, open(RESOURCE, "w"), indent=1)
    lines = ["# LUNATK factory bank", "",
             f"{len(bank)} presets. Every one is rendered through the engine in a musical phrase and mixed against a reference "
             "arrangement, then gated on loudness, headroom, low end, top end, width, mono fold-down, tails, tuning, macro "
             "range, MOTION, velocity and CPU (`tools/lunatk_bank/build.py`).", "",
             "## Macros (every preset)", "",
             "- **MACRO 1 TONE**: darker below its default, brighter above.",
             "- **MACRO 2 MOTION**: scales all movement; at 0 the sound stands still.",
             "- **MACRO 3 SPACE**: drier below its default, wetter above.",
             "- **MACRO 4 GRIT**: 0 is the designed tone; up adds drive and damage.", ""]
    for category in L.CATEGORIES:
        items = [p for p in bank if p.category == category]
        if not items:
            continue
        lines += [f"## {category} ({len(items)})", "",
                  "| Preset | Role | Register | Layer | Contexts | Play | Sit it in a mix |", "|---|---|---|---|---|---|---|"]
        for p in items:
            i = p.info
            lines.append(f"| **{p.name}** | {i['role']} | {i['register']} | {i['layer']} | {i['genres']} | {i['playing']} | {i['mix']} |")
        lines.append("")
    open(DOCS, "w").write("\n".join(lines))
    print(f"wrote {RESOURCE} and {DOCS}")


if __name__ == "__main__":
    main()
