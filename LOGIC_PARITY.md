# LYLLTH professional DAW capability contract

LYLLTH's target is that a musician can complete the same **classes of production work** they can complete in Logic Pro without LYLLTH becoming a visual clone of Logic. NIGHTSHAPE's interface, instruments, effects, phone handoff, and sequencing remain its identity.

This document is a truth sheet. A row is **working** only when the feature changes real project state or audio/MIDI behavior, persists through save/reopen, supports undo where appropriate, and has automated plus hands-on validation. A visible control is not implementation.

Reference baseline:

- [What is Logic Pro?](https://support.apple.com/guide/logicpro/what-is-logic-pro-lgcpe9cc45dd/mac)
- [Logic Pro project basics](https://support.apple.com/guide/logicpro/logic-pro-project-basics-lgcpe9cc47b2/mac)
- [Logic Pro recording overview](https://support.apple.com/guide/logicpro/overview-lgcp7f3af10b/mac)
- [Logic Pro mixing overview](https://support.apple.com/guide/logicpro/mixing-overview-lgcpbc219818/mac)
- [Snap items to the grid](https://support.apple.com/guide/logicpro/snap-items-to-the-grid-lgcpf7c0f66a/mac)
- [Zoom windows](https://support.apple.com/guide/logicpro/zoom-windows-lgcp5cbf2096/mac)

Status: **WORKING**, **PARTIAL**, **MISSING**.

## Tracks area and editing

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Horizontal and vertical zoom | WORKING | Independent persisted zoom controls; trackpad pinch; Option-pinch for vertical zoom |
| Horizontal and vertical auto-fit | WORKING | Fit full timeline or all tracks to the available Tracks area |
| Smart Snap | WORKING | Zoom-dependent bar/beat/sub-beat resolution |
| Explicit snap values | WORKING | Smart, Bar, Beat, Division, Ticks, Frames, Quarter Frames, Samples, Off |
| Absolute and relative snap | WORKING | Persisted per-project behavior |
| Temporary snap overrides | WORKING | Shift suspends snap; Control requests Division precision |
| Grid visibility | WORKING | Persisted show/hide state and zoom-aware subdivisions |
| Move and trim regions | WORKING | Drag body or either edge; persistent model edits |
| Move regions between compatible tracks | MISSING | Audio-to-audio and MIDI-to-instrument drag with validation |
| Copy, duplicate, loop, alias, slip, rotate, nudge | PARTIAL | Audio cut/copy/paste, adjacent duplicate, delete, and Option-drag slip work; loop/alias/rotate/nudge remain |
| Split, join, marquee, cut section, insert silence | PARTIAL | Audio event split at edit cursor works; join, marquee, section edits, and silence remain |
| Region inspector and numeric editing | PARTIAL | Selected audio event shows cursor, gain, pitch, and stretch; full numeric fields, fades, delay, and loop remain |
| Track zoom and focused-track zoom | PARTIAL | Global vertical zoom works; per-track/focused zoom remains |
| Waveform zoom | PARTIAL | Imported events draw a real cached waveform; independent waveform-amplitude zoom remains |
| Zoom history and presets | MISSING | Save/recall zoom 1–3 and previous zoom |
| Arrangement markers and section rearrangement | MISSING | Named global sections with drag-to-reorder |

## Recording

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Audio input/device selection | MISSING | Device, channel, mono/stereo, sample-rate validation |
| Record arm, input monitoring, metering | MISSING | Per-track state and low-latency monitoring |
| Audio recording | MISSING | Project-managed media, waveform creation, interruption recovery |
| MIDI recording | MISSING | Real-time and step input with quantize/capture recording |
| Multitrack recording | MISSING | Sample-aligned audio and MIDI capture |
| Count-in, pre-roll, metronome, replace | PARTIAL | Metronome works; record modes remain |
| Cycle takes and comping | MISSING | Take folders, swipe comping, flatten/export |
| Punch in/out and autopunch | MISSING | Locators, pre-roll, replace-safe edits |

## MIDI and instruments

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Realtime built-in instruments | PARTIAL | Current synth voices work; LYLLTH flagship synth is incomplete |
| Piano Roll | MISSING | Notes, velocity, duration, selection, draw, move, resize, quantize |
| MIDI input and controller mapping | MISSING | Devices, channels, learn, sustain, pitch bend, CC, aftertouch |
| MPE | MISSING | Per-note pitch, pressure, timbre, expression editing |
| MIDI event list and transform | MISSING | Filter, select, transform, humanize, scale, length, velocity |
| Step sequencer/pattern regions | WORKING | 16–64 steps, locks, patterns, DrumKit visual language |
| Drum performance and live overdub | MISSING | Pads, capture, quantize, undo, immediate engine mirroring |
| Sampler and multisampler | MISSING | Zones, round robin, velocity layers, loop/crossfade |
| Arpeggiator and MIDI effects | PARTIAL | Chord compiler exists; general realtime MIDI FX chain remains |
| Score editor | MISSING | Notation entry, layout, parts, print/PDF/MusicXML |

## Audio editing

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Non-destructive audio regions | PARTIAL | Project-managed originals, source offsets, slip, trim, split, duplicate, gain, pitch, fades, stretch state, and beat maps persist; arrangement-transport playback remains |
| Waveform editor | PARTIAL | Imported media has a real cached waveform; event trim, split, source slip, and direct gain line work; editable fades, normalize, reverse, and silence remain |
| Time stretch and Flex Time equivalent | PARTIAL | TETHR analysis and smoothed source-to-grid anchors drive a pitch-preserving event preview renderer; arrangement playback and manual marker UI remain |
| Pitch correction and Flex Pitch equivalent | MISSING | Note segmentation, pitch/formant/drift/gain editing |
| Audio quantize and groove templates | MISSING | Transient-aware quantization and strength controls |
| Selection-based processing | MISSING | Offline effect render to selection with undo |

## Automation and control

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Track and region automation | MISSING | Volume, pan, sends, plug-ins, instruments, tempo |
| Read/Touch/Latch/Write modes | MISSING | Sample-accurate playback and safe write behavior |
| Curves, points, ramps, trim, relative automation | MISSING | Mouse editing, thinning, snapping, copy/paste |
| Automation snap and offset | MISSING | Independent editor snap and latency offset |
| Smart Controls/macros | MISSING | User-mappable multi-parameter controls and patch recall |
| Control surfaces | MISSING | MIDI learn first; MCU/HUI and OSC later |

## Mixer, routing, and plug-ins

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Volume, pan, mute, solo | WORKING | Persists and reaches the live engine |
| Inserts | PARTIAL | Metadata persists; complete editors and DSP routing remain |
| Sends, auxes, buses, outputs | MISSING | Pre/post sends, bus creation, multi-output routing |
| Groups, VCAs, track stacks | MISSING | Edit/mix groups and summing/folder stacks |
| Sidechains | MISSING | Source selection and plug-in sidechain buses |
| Metering | PARTIAL | Output waveform/meter exists; channel meters and analysis remain |
| Audio Unit instruments/effects | PARTIAL | Discovery works; hosting, state, validation, latency remain |
| VST3 instruments/effects | MISSING | Scan, quarantine, host, state restoration, editor windows |
| Plug-in delay compensation | MISSING | Graph-wide latency calculation and live/record alignment |
| Freeze and low-latency mode | MISSING | Reversible render substitution and safe monitoring path |
| Surround/Atmos | MISSING | Deferred until stereo routing and bounce are release-solid |

## Project, global, media, and delivery

| Capability | Status | LYLLTH requirement |
|---|---|---|
| Native project package | WORKING | Versioned `.lyllth` package and backward decoding |
| Undo/redo | MISSING | Model-level grouped undo across editing and mixing |
| Tempo, meter, key | PARTIAL | Static values work; global tracks and events remain |
| Markers, cycle, punch locators | PARTIAL | Loop data exists; editable global tracks remain |
| Tempo maps and beat mapping | PARTIAL | Per-audio-event TETHR analysis/anchors persist and render in event preview; project tempo ramps and arrangement playback remain |
| Media browser and loops | MISSING | Search, preview, tempo/key matching, drag import |
| File import | PARTIAL | WAV, AIFF, MP3, M4A, CAF, and FLAC originals are embedded with waveform/tempo analysis; MIDI, stems, DrumKit packages, drag import, and missing-media recovery remain |
| Bounce and export | MISSING | Mix, region, stems, MIDI, normalization, dither, metadata |
| Project alternatives and backups | MISSING | Versions, autosave recovery, consolidate, cleanup |
| iPhone handoff | MISSING | iCloud package transfer, conflict copies, lossless round-trip |
| Keyboard commands and accessibility | MISSING | Complete command model, remapping, VoiceOver, reduced motion |

## Delivery order

1. **Editor correctness:** undo/redo, selection, region move/trim/split/copy/loop, Smart Snap, zoom, cycle/playhead, keyboard commands.
2. **Recording:** audio/MIDI input, arm/monitor, files, waveform cache, count-in, punch, takes, comping.
3. **MIDI and audio editors:** Piano Roll, event operations, quantize, waveform editor, fades, stretch and pitch foundations.
4. **Mixer and hosting:** buses/sends, automation, AU hosting/state/latency, VST3 host boundary, plug-in manager.
5. **Delivery:** bounce, stems, MIDI, freeze, project collection, recovery, iCloud/DrumKit round-trip.
6. **Advanced production:** tempo mapping, groove extraction, MPE, score, control surfaces, surround/Atmos after stereo is complete.

## Non-negotiable completion gates

- No fake controls or library entries.
- Every edit is undoable, saveable, reopenable, and deterministic.
- Realtime audio performs no locks, allocations, file access, or hot logging.
- Audio and MIDI remain aligned through tempo changes, latency compensation, export, and reopen.
- Destructive source-file changes require an explicit command and recoverable history; normal region editing stays non-destructive.
- Logic capability parity does not override NIGHTSHAPE's visual identity or turn the interface into a Logic clone.
