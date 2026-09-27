# LUNATK Expansion 02: notes

100 presets added to the factory bank (`tools/lunatk_bank/bank2/x2_*.py`), after the showcase set. Each preset's technical description is its `role` line in `FACTORY_BANK.md`, and each design is commented in its source file.

## How the brief's groups map to engine categories

LUNATK's categories are fixed: BASS LEAD PAD KEYS PLUCK ARP MOTION DRONE PERC FX. The brief's groups were mapped by how each sound is played:

| Brief group | Engine category |
|---|---|
| Industrial monster basses | BASS |
| Corrupted cinematic pads | PAD |
| Aggressive industrial leads | LEAD |
| Chaotic melodic arpeggiators | ARP |
| Distorted emotional keys | KEYS |
| Cinematic industrial drones | DRONE |
| Hybrid synth/guitar textures | LEAD (mono lines) or KEYS (chords) |
| Dark pop signature synths | LEAD, KEYS or PAD |
| Rhythmic industrial textures | MOTION |
| Experimental showcases | PAD, LEAD, KEYS, DRONE or MOTION |

## Renamed

Three names in the brief already belonged to other presets, so these presets got entirely new names:

| Brief name | Shipped as |
|---|---|
| ASH CATHEDRAL | CINDER BASILICA |
| SUBTERRANEAN | BEDROCK |
| STATIC PRESSURE | TENSION GRID |

## Missing capabilities

These are things the brief asked for that LUNATK does not have. The closest achievable design was used instead, and the engine was not changed.

- **No oversampling on the shaping stages.** Oscillators are band-limited by wavetable mipmaps. The inserts, filter saturation, feedback loop and distortion run at the host rate. The presets keep hard shaping away from high registers, and leads roll off above 7–9 kHz.
- **No granular engine.** VELVET CORROSION imitates grain by scrubbing the wavetable position and a decimator with a fast, smoothed sample-and-hold.
- **No amp or cabinet model in the synth.** The hybrid guitar presets use drive plus EQ voicing (a 1.5–2 kHz bump and a roll-off above 5.5 kHz). A cabinet model exists in LYLLTH's track effects (STACK), not inside LUNATK.
- **No samples or physical models.** Strings and pianos are built from a comb-filter insert on an oscillator, with a noise burst for the pick or hammer.
- **The arpeggiator has one pattern length.** Its steps (1–16, each with its own level, length, transpose and rest) are shared by all notes. Polymeters come from the two performers, each with its own step count (DARK MATHEMATICS, NIGHTSHAPE PROTOCOL).
- **No low cut on the reverb.** Drones use a narrow reverb (width 0.25) to keep their lows mono.
- **The vocoder needs a live input**, so no factory preset uses it.

## Validation

Every preset was rendered through the real engine in a musical phrase: bass lines, lead lines, pad and keys chords, held arp chords, held drone notes and MOTION chords. Each one also got a held-note render, a soft-velocity render and a render at every macro extreme. It then had to pass these gates:

- Loudness within 1.5 LU of its category's target.
- Peaks under −0.5 dBFS at every macro setting.
- Low-end limits, with the lows mono.
- Top end under the limit above 10 kHz.
- Width, fold-down to mono, and tail length.
- DC and sub-rumble.
- Tuning, except RAZOR PULSE and BLACK ALGORITHM (see below).
- Velocity must change the sound.
- MOTION must move it.
- CPU.

Passing these gates proves the presets are technically sound. It does not prove they are musically good. All 100 still need human listening before anyone calls them exceptional.

- **Tuning not measured:** BLACK ALGORITHM and RAZOR PULSE are exempt from the held-note tuning test, because their step transposes (fourths and fifths) confuse the pitch detector. Their pitches are exact by construction.
