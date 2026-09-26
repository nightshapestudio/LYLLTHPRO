"""Test phrases: how each category is played in the render tests.

All phrases are simple, original and generic (roots, fifths, stock
progression voicings), written only to put a sound in a musical situation.
Times in beats are converted with the phrase's tempo.
Each note: (start_beat, midi, velocity, length_beats)
"""

PROGRESSION = [  # voicings kept between C3 and C5
    [57, 60, 64, 67, 71],   # A minor 9
    [53, 57, 60, 64],       # F major 7
    [52, 55, 60, 62],       # C add 9 over E
    [55, 60, 62, 64],       # G 6 sus
]


def _notes(bpm, notes):
    spb = 60.0 / bpm
    return [[round(b * spb, 5), n, v, round(max(l * spb, 0.02), 5)] for b, n, v, l in notes]


def bass(root=28, bpm=124):
    r = root
    line = [(0, r, 110, 0.45), (0.75, r, 90, 0.2), (1.5, r + 12, 100, 0.4), (2.5, r, 110, 0.45), (3, r + 7, 95, 0.45),
            (3.5, r + 10, 90, 0.4), (4, r - 4 + 12, 110, 0.45), (4.75, r - 4 + 12, 90, 0.2), (5.5, r + 8, 100, 0.45),
            (6.5, r + 3, 105, 0.45), (7, r + 5, 95, 0.45), (7.5, r + 7, 100, 0.4), (8, r, 115, 3.5)]
    return {"bpm": bpm, "seconds": 12 * 60 / bpm + 1.5, "notes": _notes(bpm, line), "last_off_beat": 11.5}


def lead(root=60, bpm=100, legato=False):
    o = 0.1 if legato else -0.05
    line = [(0, root, 100, 1 + o), (1, root + 3, 90, 0.5 + o), (1.5, root + 7, 100, 0.5 + o), (2, root + 10, 110, 2 + o),
            (4, root + 8, 95, 1 + o), (5, root + 7, 90, 1 + o), (6, root + 5, 95, 0.5 + o), (6.5, root + 3, 90, 0.5 + o),
            (7, root + 7, 110, 3)]
    return {"bpm": bpm, "seconds": 10 * 60 / bpm + 4.0, "notes": _notes(bpm, line), "last_off_beat": 10}


def pad(bpm=84, shift=0, bars=2):
    notes = []
    for i, chord in enumerate(PROGRESSION):
        for n in chord:
            notes.append((i * 4 * bars, n + shift, 90, 4 * bars - 0.1))
    beats = len(PROGRESSION) * 4 * bars
    return {"bpm": bpm, "seconds": beats * 60 / bpm + 5, "notes": _notes(bpm, notes), "last_off_beat": beats}


def keys(bpm=96, shift=0):
    notes = []
    rhythm = [(0, 1.4, 100), (1.5, 0.4, 80), (2, 0.9, 95), (3, 0.4, 70), (3.5, 0.4, 85)]
    for i, chord in enumerate(PROGRESSION):
        for start, length, vel in rhythm:
            for n in chord[-4:]:
                notes.append((i * 4 + start, n + shift, vel, length))
    beats = len(PROGRESSION) * 4
    return {"bpm": bpm, "seconds": beats * 60 / bpm + 3, "notes": _notes(bpm, notes), "last_off_beat": beats}


def pluck(bpm=120, shift=12):
    notes = []
    pattern = [0, 2, 1, 3, 2, 1, 3, 0]
    for i, chord in enumerate(PROGRESSION):
        upper = sorted(chord)[-4:]
        for step in range(16):
            n = upper[pattern[step % 8]] + shift
            vel = 110 if step % 4 == 0 else (80 if step % 2 == 0 else 65)
            notes.append((i * 4 + step * 0.25, n, vel, 0.2))
    beats = len(PROGRESSION) * 4
    return {"bpm": bpm, "seconds": beats * 60 / bpm + 2.5, "notes": _notes(bpm, notes), "last_off_beat": beats}


def arp(bpm=122, shift=0, notes=3, bars=1):
    """Chords held for a bar each; the arpeggiator plays them."""
    out = []
    for i, chord in enumerate(PROGRESSION):
        for n in sorted(chord)[-notes:]:
            out.append((i * 4 * bars, n + shift, 100, 4 * bars - 0.05))
    beats = len(PROGRESSION) * 4 * bars
    return {"bpm": bpm, "seconds": beats * 60 / bpm + 3, "notes": _notes(bpm, out), "last_off_beat": beats}


def motion(bpm=120, shift=0):
    notes = []
    for i, chord in enumerate(PROGRESSION[:2]):
        for n in chord[-4:]:
            notes.append((i * 8, n + shift, 95, 7.9))
    return {"bpm": bpm, "seconds": 16 * 60 / bpm + 3, "notes": _notes(bpm, notes), "last_off_beat": 16}


def drone(root=38, bpm=90, fifth=True, seconds=12.0):
    beats = seconds * bpm / 60
    notes = [(0, root, 95, beats)] + ([(0, root + 7, 85, beats)] if fifth else [])
    return {"bpm": bpm, "seconds": seconds + 5, "notes": _notes(bpm, notes), "last_off_beat": beats}


def perc(note=36, bpm=120, pattern=None):
    pattern = pattern or [(0, 115), (1, 100), (2, 115), (2.75, 80), (3, 105), (4, 115), (5, 100), (6, 115), (7, 105), (7.5, 90)]
    notes = [(b, note, v, 0.2) for b, v in pattern]
    return {"bpm": bpm, "seconds": 8 * 60 / bpm + 1.5, "notes": _notes(bpm, notes), "last_off_beat": 7.7}


def fx(note=60, bpm=120, hold_beats=8, tail=4.0):
    notes = [(0, note, 110, hold_beats)]
    return {"bpm": bpm, "seconds": hold_beats * 60 / bpm + tail, "notes": _notes(bpm, notes), "last_off_beat": hold_beats}


def held(note, seconds=2.5, bpm=120):
    return {"bpm": bpm, "seconds": seconds + 1.0, "notes": [[0.0, note, 100, seconds]], "last_off_beat": seconds * bpm / 60}


DEFAULT_PITCH_NOTE = {"BASS": 40, "LEAD": 69, "PAD": 60, "KEYS": 60, "PLUCK": 72, "ARP": 60, "MOTION": 60, "DRONE": 45, "PERC": 48, "FX": 60}


def main_phrase(category, test):
    t = dict(test)
    if category == "BASS":
        return bass(t.get("root", 28), t.get("bpm", 124))
    if category == "LEAD":
        return lead(t.get("root", 60), t.get("bpm", 100), t.get("legato", False))
    if category == "PAD":
        return pad(t.get("bpm", 84), t.get("shift", 0), t.get("bars", 2))
    if category == "KEYS":
        return keys(t.get("bpm", 96), t.get("shift", 0))
    if category == "PLUCK":
        return pluck(t.get("bpm", 120), t.get("shift", 12))
    if category == "ARP":
        return arp(t.get("bpm", 122), t.get("shift", 0), t.get("notes", 3), t.get("bars", 1))
    if category == "MOTION":
        return motion(t.get("bpm", 120), t.get("shift", 0))
    if category == "DRONE":
        return drone(t.get("root", 38), t.get("bpm", 90), t.get("fifth", True), t.get("seconds", 12.0))
    if category == "PERC":
        return perc(t.get("note", 36), t.get("bpm", 120), t.get("pattern"))
    return fx(t.get("note", 60), t.get("bpm", 120), t.get("hold", 8), t.get("tail", 4.0))
