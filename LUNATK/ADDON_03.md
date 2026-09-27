# LUNATK Add-on 03: industrial-pop / four-on-the-floor

50 presets (`tools/lunatk_bank/bank2/x3_*.py`), added after Expansion 02. Each one's technical description is its `role` line in `FACTORY_BANK.md`.

## The mod-wheel gate

Every add-on 03 preset is rendered twice: once with the wheel at 0 and once at full (`build.py`, `wheel` context). At full wheel it must:

- change the spectrum by at least 2.5 dB over the whole phrase,
- stay within ±4 LU of the wheel-0 level, so the wheel adds danger, not volume,
- never clip. The full-wheel peak is included when the preset's level is set.

Each preset trims MASTER on the wheel. MAIN STAGE DAMAGE stages its wheel with curves: bigger, wider and more animated up to about 50%, and filthy and screaming above it.

## Categories

| Brief group | Engine category |
|---|---|
| Razor basslines | BASS |
| Biting rhythmic arps | ARP |
| Metallic synth guitars | KEYS (played as chords and riffs) |
| Screaming leads | LEAD |
| Rhythmic chord and pulse monsters | KEYS, except HEAVY SEQUENCE, which is an ARP |

## Renamed

Different patches get completely different names:

| Brief name | Shipped as | Clash |
|---|---|---|
| BLACK CONVEYOR | IRON TREADMILL | name taken |
| BLACK AMPLIFIER | HOT TUBES | name taken |
| STEEL VEIN | CHROME ARTERY | too close to STEEL VEINS |
| BURN HALO | SOLAR WOUND | too close to BURNING HALO and HALO BURN |
| METAL NERVE | TUNGSTEN | too close to METALLIC NERVE |
| BLACKOUT GROOVE | MIDNIGHT ENGINE | too close to BLACKOUT |

## Limits

These are the same limits listed in `EXPANSION_02.md`:

- The synth has no cabinet model. The synth guitars get their cabinet voicing from the EQ.
- The shaping stages have no oversampling.

Passing the gates proves a preset is technically sound, not that it sounds good. All 50 still need listening.
