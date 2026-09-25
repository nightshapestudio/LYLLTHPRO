# DrumKit continuity status

This file is the truth sheet for the current LYLLTH checkout. A visible control or library row is not counted as implemented unless it changes persisted state or the live audio engine.

## Working now

- Shared NIGHTSHAPE engine startup and live transport playback
- Tempo and 4/4, 3/4, or 6/8 engine synchronization
- Transport-synchronized metronome
- Sixteen live musical tracks plus audio and auxiliary starter channels
- Full-height 16/32/48/64-step editor without phone pages
- DrumKit-derived square-cell sequencer visuals, frozen-wave glass, accent playhead decay, and full-track playback visualizer
- Multiple patterns with add, select, copy, paste, randomize, and clear
- Per-track mute and solo
- Per-step velocity, level, pitch, note length, cutoff, resonance, pan, and FX locks
- Song root plus major/minor selection
- DrumKit chord-marker compilation through the shared `ChordLaneCompiler`
- Live NIGHTSHAPE synth presets per sequenced track; playback is generated in realtime, not pre-rendered before transport
- Persistent `.lyllth` document packages and backward decoding of the original project schema
- Audio Unit discovery in the browser
- Track creation for DrumKit, instrument, audio, and auxiliary channels
- Mixer level/pan editing and persisted insert-slot metadata

## Presentational or partial

- Arrangement: persistent horizontal/vertical zoom, auto-fit, zoom-aware grid, Logic-class snap modes, and non-destructive clip move/edge trim work. Split/copy/loop, cross-track movement, region undo, and a song-block playback timeline are not complete.
- NIGHTSHAPE effects: names and insert state persist, but the macOS editor surfaces and every effect parameter are not yet wired to the engine.
- Audio Units: discovery works; instantiation, editor hosting, automation, quarantine, and state restoration do not.
- Drum Synth and Sound Oracle: library entry points are visible; the full DrumKit browsers, patch editors, audition flow, and sound assignment are not ported.
- Live synth: current shared dual-oscillator voices play in realtime; this is not the separate wavetable/modulation core required for the Serum-grade LYLLTH instrument.

## Not implemented yet

- DrumKit `.fkit` import and lossless shared song-model migration
- iCloud Documents handoff, conflict copies, and physical iPhone-to-Mac verification
- Kit browser, pad performance surface, and live overdub capture
- Audio input selection, monitoring, arm, count-in, recording, punch, takes, and comping
- Piano-roll note creation, selection, movement, quantize, and MIDI input/recording
- Editable song blocks, song FX lane, automation lanes, and arrangement playback
- Sample import, transient editing, source replacement, and missing-media recovery
- Complete routing, sends, sidechains, buses, and latency compensation
- AUv2/AUv3 instantiation and hosting
- VST3 scanning and hosting
- Serum-grade wavetable editor, modulation matrix, MPE, resynthesis, granular, and spectral engines
- Freeze, flatten, bounce, stems, MIDI export UI, and project collection
- Undo/redo and complete keyboard-command coverage

Do not describe LYLLTH as DrumKit-complete or DAW-complete until the remaining sections are implemented and verified with saved/reopened projects, live playback, recorded audio, plug-in restoration, exports, and a physical phone handoff.
