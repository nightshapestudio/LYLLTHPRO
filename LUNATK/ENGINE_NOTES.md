# LUNATK engine notes from the factory bank

Building and testing the 160-preset bank turned up these engine behaviors. None
were changed in the engine. Each one lists what the bank does about it.

| What happens | Why it matters | What the bank does |
|---|---|---|
| An oscillator at level 0 skips rendering, so FM, RM and AM that read it as their modulator get silence. | A patch that uses B only as a modulator (level 0) has no FM or ring mod at all. | Modulator oscillators sit at level 0.002: silent, but rendering. |
| ~~A free-running DRIFT (smooth random) LFO starts at 0 and only picks its first target after one full cycle.~~ Fixed: free LFOs pick a target when the synth is created. | At 0.25 Hz, a freshly loaded patch doesn't move for about 4 seconds. | DRIFT LFOs retrigger per note (TRIG), which also gives every note its own drift. |
| The `1/12` sync division is 1/12 of a beat (a 1/48 note), not a triplet eighth (1/3 beat). | Anyone choosing "1/12" for triplets gets a very fast rate. | Unused. Triplet gates are drawn over one beat instead. |
| ~~Free-running LFOs aren't locked to the host's bar position.~~ Fixed: while a transport plays (LYLLTH, or an AU/VST3 host), synced FREE LFOs, the arpeggiator and SONG performers follow the bar. With the transport stopped they run on their own as before. | A synced gate or pump in FREE mode used to drift against the kick. | Rhythmic LFOs retrigger per note (written before the fix; they still work). |
| There is no DC blocker in the voice path. | Asymmetric pulse waves and some saturation carry a little DC (about −40 dBFS). | Basses that showed it have a 25 Hz high-pass on filter 2. The gate allows at most 0.006. |
| The reverb has no low cut. | Any reverb widens the low end. | Low sounds use a narrow reverb (width 0.1–0.3). Every preset is gated on a mono low end. |
| Comb-filter feedback is capped at 0.96. | A noise-excited "string" dies in about 0.25 s at middle C, too short to be a string. | Plucked strings use an oscillator body with the comb as colour. |
| The QUANTIZE warp is nearly transparent below 0.6. | Small amounts do nothing audible. | Presets that use it run from 0.3 up, with MOTION taking it past 0.6. |
| Wavetable mipmaps band-limit table-based "digital" steps at high notes. | Crunch drawn into a table disappears in a lead's register. | Digital damage at high pitches uses the sample-level QUANTIZE warp or the distortion. |
| Every arpeggiator step starts a new voice, so a TRIG LFO restarts on each step. | A 2-bar filter sweep on an arp never gets past its first sixteenth; the sound doesn't move. | ARP presets run every LFO FREE. |
| MASTER plus modulation is clamped to 1. | Level compensation can't push past full MASTER. | The leveler adds clean makeup gain with the compressor at a 0 dBFS threshold. |

Worth fixing in the engine when you decide to: the `1/12` division, and an
optional DC blocker and reverb low cut. (The voice inserts now have their own DC blocker.)

## Added after the bank

- **Song position.** `lysynth_set_song_position` (plug-ins, per render) and
  `lysynth_set_transport` (LYLLTH, a host-time anchor). The arpeggiator waits
  for the next grid line unless a chord lands within 15% of a step after one.
- **Performers.** Two tempo step sequencers, four patterns (A–D) of up to 16
  steps, a level and a shape per step. SONG follows the bar, NOTE restarts
  with each note. Four switch keys (from C1 by default) pick the pattern and
  make no sound.
- **Trackers.** Two drawn 16-point curves, each reading any source.
- **Voice inserts.** Two per-voice slots before or after the filters:
  bitcrush, decimate, sine shaper, fold, rectify (DC-blocked), ring mod,
  frequency shifter (±2 kHz), comb.
- **Feedback.** Filter output back into the filter input per voice, with a
  low-pass, saturation and a DC blocker inside the loop.
- **Macros 5–8.**
- **Saturation between the filters** (light, soft, hard, diode, shaper,
  rectify, bits, rate): before filter 2 in series, on filter 1's path in
  parallel and split. **SPLIT routing** sends oscillator B to filter 2 on its
  own while A, sub and noise go through filter 1. In split, the inserts set
  before the filters work on filter 1's path only.
- **Sustain slope** on every envelope (a held note drifts down or up) and
  **PUNCH** on the amplifier's attack.
- **Arp patterns**: up to 16 steps with a level (0 rests) and a length each.
- **Vocoder**: 8–24 bands, the synth as carrier and the plug-ins' sidechain
  input as the voice. LYLLTH can't route a track into it yet; that waits for
  the per-document audio engine being built alongside this.
- **VINTAGE**: each note gets its own oscillator tuning (up to 6 cents), filter
  offset (up to a quarter octave) and envelope times (±25%), plus a slow drift
  of up to 4 cents. At 0 nothing changes and no random numbers are drawn.
- **MORPH filter**: a 12 dB state-variable filter with MORPH from low-pass
  through a notch to high-pass, per filter and modulatable.
- **LADDER**: a 2-pole option and BASS LOSS (how much of the low end the
  ladder gives up as resonance rises), shared by both filters.
- **Mono key priority**: LAST, LOW or HIGH, and letting go of the playing key
  returns to one still held (legato if LEGATO is on).

Every new parameter sits after the drawn LFO points, so the plug-ins' host
parameter ids for older parameters did not move. All 176 factory presets render
bit-for-bit the same as before these were added.
