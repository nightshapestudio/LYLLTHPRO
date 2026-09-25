# LYLLTH

LYLLTH is a native macOS audio workstation by NIGHTSHAPE: the larger desktop counterpart to NIGHTSHAPE DRUMKIT, not a stretched iPhone interface.

The current visual language and desktop adaptation rules are documented in `DESIGN_SYSTEM.md`.

## What works in this checkout

- Builds as a native SwiftUI macOS app.
- Uses the live `NightshapeAudioEngine` package from NIGHTSHAPE DRUMKIT.
- Starts the existing engine and drives a live 16-track musical session from the macOS transport.
- Provides a full-height desktop sequencer with 16, 32, 48, or 64 steps, two starter patterns, pattern add/copy/paste/randomize/clear, per-track mute/solo, and a live playhead.
- Persists and plays per-step velocity, level, pitch, gate length, filter, pan, and FX locks.
- Exposes the song key in the transport and recompiles the chord lane when the root or major/minor mode changes.
- Uses an adaptive 16/32-step canvas instead of preserving phone-sized paging on a large display.
- Provides persistent horizontal and vertical arrangement zoom, horizontal/vertical auto-fit, trackpad pinch zoom, and Option-pinch vertical zoom.
- Provides working Smart Snap plus Bar, Beat, Division, Ticks, Frames, Quarter Frames, Samples, and Off modes; snap can be absolute or relative, Shift temporarily suspends it, and Control requests Division precision.
- Moves and trims arrangement regions non-destructively against the visible, zoom-aware grid.
- Provides ACID-style audio-event split, cut/copy/paste, adjacent duplication, delete, Option-drag source slip, direct top-line event gain, and per-event semitone pitch controls with keyboard shortcuts.
- Persists source offsets, gain, pitch, fades, stretch mode, source tempo, and transient beat maps without modifying the original audio file.
- Imports WAV, AIFF, MP3, M4A, CAF, and FLAC audio into the project package, builds a real waveform preview, and estimates source tempo for beat-mapping.
- Ports TETHR's confidence-gated transient analysis and smoothed source-to-project beat-anchor planning into native Swift.
- Renders selected audio events for audition with source trim/slip, event gain, fades, semitone pitch, tempo stretch, and TETHR beat-map spans while preserving pitch.
- Adds drum, live-instrument, audio, and auxiliary tracks from the workspace toolbar.
- Runs the shared transport-synchronized metronome.
- Presents a macOS-sized arrangement, mixer, browser, inspector, and transport in the existing matte NIGHTSHAPE visual language.
- Scans installed Audio Unit instruments and effects into the browser.
- Creates and edits a versioned `.lyllth` document package with reserved `Audio`, `Presets`, and `PluginStates` directories.
- Registers `.lyllth` as a Finder-openable document type.

This is not yet a finished DAW. The exact DrumKit boundary is tracked in `DRUMKIT_PARITY.md`, and the professional workstation capability contract is tracked in `LOGIC_PARITY.md`. Audio-file import and pitch-preserving event audition now work, but audio-event playback inside the arrangement transport, audio-input recording, note-level MIDI editing, editable fades/crossfades, undo, routing, plug-in insertion/hosting, bounce UI, and DrumKit/iCloud interchange remain implementation work rather than implied functionality.

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
