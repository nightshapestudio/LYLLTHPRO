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
- Plays the arrangement in SONG mode: pattern regions compile to the engine's bar-by-bar song frames, and audio events play on the same transport clock through players in the one engine graph. PATTERN mode loops the pattern being edited, as in DrumKit.
- ACID-style audio events: drag the right edge past the source to loop it (loop seams are notched), split and left-trim move the loop entry point instead of cutting the source, drag the top line for volume, +/- for semitones, Option-drag to slip the audio inside the event, and drop files from Finder onto any lane.
- A LOOP brace in the ruler (drag its edges, drag to move, drag across empty ruler to draw one) and a working LOOP transport toggle.
- Imports WAV, AIFF, MP3, M4A, CAF, and FLAC audio into the project package with waveform, tempo, and TETHR beat-map analysis; stretch per event is OFF, TEMPO, or BEAT MAP.
- NIGHTSHAPE FX on musical tracks and MAIN using DrumKit's own FX windows, compiled from the sibling checkout (see `LYLLTH/DrumKitShared`), so displays and animation are identical to the phone. Effect state is stored as DrumKit's state types and pushed to the engine the same way DrumKit does.
- LYLLTH SYNTH, a realtime wavetable synth with its own C++ core (`LYLLTH/SynthCore`): two band-limited wavetable oscillators with up to 16-voice unison and 9 warp modes, sub, noise, 7 filters, 3 curved envelopes, 4 LFOs (tempo sync, drawable), 4 macros, 16-slot matrix with drag-to-modulate, MIDI and MPE input, 16-voice polyphony or mono/legato/glide. Wavetables import from Serum-format files or any audio, and can be drawn and reshaped harmonic by harmonic in the wavetable editor; custom tables travel inside the song. User presets save to ~/Library/Application Support/LYLLTH/Presets with their wavetables.
- EXPORT bounces the whole song to a 24-bit WAV in real time from the main mix.
- Real per-track and MAIN meters, M / S / R per track, and transport record enable. Record enable and R are saved but audio capture is not built yet.
- Adds drum, live-instrument, audio, and auxiliary tracks from the workspace toolbar.
- Runs the shared transport-synchronized metronome.
- Presents a macOS-sized arrangement, mixer, browser, inspector, and transport in the existing matte NIGHTSHAPE visual language.
- Scans installed Audio Unit instruments and effects into the browser.
- Creates and edits a versioned `.lyllth` document package with reserved `Audio`, `Presets`, and `PluginStates` directories.
- Registers `.lyllth` as a Finder-openable document type.

This is not yet a finished DAW. The exact DrumKit boundary is tracked in `DRUMKIT_PARITY.md`, and the professional workstation capability contract is tracked in `LOGIC_PARITY.md`. Audio recording, NIGHTSHAPE FX on audio tracks, buses and sends, note-level MIDI editing, editable fades/crossfades, undo, routing, plug-in insertion/hosting, bounce UI, and DrumKit/iCloud interchange remain implementation work rather than implied functionality.

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
