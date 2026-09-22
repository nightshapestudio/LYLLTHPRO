# LYLLTH

LYLLTH is a native macOS audio workstation by NIGHTSHAPE: the larger desktop counterpart to NIGHTSHAPE DRUMKIT, not a stretched iPhone interface.

## What this foundation already does

- Builds as a native SwiftUI macOS app.
- Uses the live `NightshapeAudioEngine` package from NIGHTSHAPE DRUMKIT.
- Starts the existing engine and drives an audible two-voice starter arrangement from the macOS transport.
- Presents a macOS-sized arrangement, mixer, browser, inspector, and transport in the existing matte NIGHTSHAPE visual language.
- Scans installed Audio Unit instruments and effects into the browser.
- Creates and edits a versioned `.lyllth` document package with reserved `Audio`, `Presets`, and `PluginStates` directories.
- Registers `.lyllth` as a Finder-openable document type.

This is an architectural foundation, not yet a finished DAW. Audio recording, editable MIDI, clip editing, complete routing, plug-in insertion, bounce, undo, and DrumKit/iCloud interchange are the next implementation slices.

## Realtime synth direction

LYLLTH's flagship synth will not use DrumKit's pre-rendered drum-preset playback model. It is specified as a sample-accurate realtime wavetable/hybrid instrument: MIDI, automation, modulation, oscillators, filters, and effects remain live during playback. Rendering is reserved for explicit bounce, freeze, export, analysis, and optional preview workflows.

The built-in instrument and a future standalone AU/VST3 will share one portable DSP core and patch schema. The staged target includes professional wavetable generation/editing, unison and warp modes, dual filters, a deep polyphonic modulation system, MIDI/MPE, then sample, multisample, granular, and spectral synthesis. See `ARCHITECTURE.md` for the capability contract and delivery gates.

## Build

1. Install XcodeGen if needed: `brew install xcodegen`.
2. Run `xcodegen generate` in this directory.
3. Open `LYLLTH.xcodeproj` and run the `LYLLTH` scheme.

The project currently references the sibling checkout at `../nightshape-drumkit-ios/NightshapeAudioEngine`. That keeps the first prototype on the exact DSP code DrumKit is using. The extraction plan in `ARCHITECTURE.md` removes that repository coupling before release.

## Product rule

Phone-originated content remains playable and editable on Mac. Mac-only features are stored as additive desktop layers, so returning a song to DrumKit never silently destroys its original patterns, sound assignments, or NIGHTSHAPE effect state.
