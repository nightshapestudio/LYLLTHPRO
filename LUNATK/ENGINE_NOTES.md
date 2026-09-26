# LUNATK engine notes from the factory bank

Building and testing the 160-preset bank turned up these engine behaviors. None
were changed in the engine. Each one lists what the bank does about it.

| What happens | Why it matters | What the bank does |
|---|---|---|
| An oscillator at level 0 skips rendering, so FM, RM and AM that read it as their modulator get silence. | A patch that uses B only as a modulator (level 0) has no FM or ring mod at all. | Modulator oscillators sit at level 0.002: silent, but rendering. |
| A free-running DRIFT (smooth random) LFO starts at 0 and only picks its first target after one full cycle. | At 0.25 Hz, a freshly loaded patch doesn't move for about 4 seconds. | DRIFT LFOs retrigger per note (TRIG), which also gives every note its own drift. |
| The `1/12` sync division is 1/12 of a beat (a 1/48 note), not a triplet eighth (1/3 beat). | Anyone choosing "1/12" for triplets gets a very fast rate. | Unused. Triplet gates are drawn over one beat instead. |
| Free-running LFOs aren't locked to the host's bar position. | A synced gate or pump in FREE mode drifts against the kick. | Rhythmic LFOs retrigger per note. Presets tell you to start chords on the beat. |
| There is no DC blocker in the voice path. | Asymmetric pulse waves and some saturation carry a little DC (about −40 dBFS). | Basses that showed it have a 25 Hz high-pass on filter 2. The gate allows at most 0.006. |
| The reverb has no low cut. | Any reverb widens the low end. | Low sounds use a narrow reverb (width 0.1–0.3). Every preset is gated on a mono low end. |
| Comb-filter feedback is capped at 0.96. | A noise-excited "string" dies in about 0.25 s at middle C, too short to be a string. | Plucked strings use an oscillator body with the comb as colour. |
| The QUANTIZE warp is nearly transparent below 0.6. | Small amounts do nothing audible. | Presets that use it run from 0.3 up, with MOTION taking it past 0.6. |
| Wavetable mipmaps band-limit table-based "digital" steps at high notes. | Crunch drawn into a table disappears in a lead's register. | Digital damage at high pitches uses the sample-level QUANTIZE warp or the distortion. |
| Every arpeggiator step starts a new voice, so a TRIG LFO restarts on each step. | A 2-bar filter sweep on an arp never gets past its first sixteenth; the sound doesn't move. | ARP presets run every LFO FREE. |
| MASTER plus modulation is clamped to 1. | Level compensation can't push past full MASTER. | The leveler adds clean makeup gain with the compressor at a 0 dBFS threshold. |

Worth fixing in the engine when you decide to: the `1/12` division, the DRIFT
LFO's cold start, and an optional DC blocker and reverb low cut.
