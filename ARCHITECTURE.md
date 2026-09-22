# LYLLTH Architecture and Delivery Plan

## Product boundary

LYLLTH should feel like DrumKit grew into the room available on a Mac. It should not become a generic DAW wearing NIGHTSHAPE colors.

The persistent center is a fast arrangement surface, a visible signal path, a restrained mixer, and direct manipulation. Tracks, clips, plug-ins, automation, and recording are desktop-native additions. The near-black matte chassis, sharp cells, cyan/indigo/purple accents, steady active states, and minimal playhead motion remain canonical.

## What is reused from DrumKit

The existing `NightshapeAudioEngine` already builds for macOS and supplies the valuable differentiated layer:

- Drum Synth and its preset library
- live synth voices and chord lanes
- sequencer clock and sample-accurate song frames
- track and MAIN effects: EQUALIZER, COMPRESSOR, TAPE SATURATION, SONIC DECIMATOR, CHORUS, PLATE REVERB, SIGNAL BLOOM, PUMP, VOID GATE, FRACTURE, FILTER, DELAY, DEADLOCK, SHEAR, STACK, SPLIT FIELD, UNDERTOW, ANVIL, STRIKE, and FINALE
- offline rendering, output capture, MIDI export, meters, and waveform snapshots

The iPhone SwiftUI layer is not reused wholesale. It contains UIKit-specific gestures, fixed phone geometry, and a focused 16-track instrument workflow. LYLLTH gets macOS-native keyboard, pointer, window, menu, drag-and-drop, document, and accessibility behavior.

## Required engine evolution

The current engine is a fixed singleton with sixteen instrument/sample tracks and a largely fixed graph. A DAW needs a document-scoped host graph with dynamic tracks.

The safe migration is incremental:

1. Extract portable DSP and preset definitions into versioned shared packages without changing their audio behavior.
2. Introduce an `AudioGraphSession` abstraction that owns transport, graph, routing, and lifecycle per open song.
3. Keep the existing `NightshapeAudioEngine.shared` as a DrumKit compatibility facade over its one session.
4. Add dynamic audio, MIDI/instrument, DrumKit, auxiliary, bus, and MAIN channels to the session graph.
5. Add input monitoring and recording inside the authoritative graph. Do not create a second `AVAudioEngine` for recording.
6. Add delay compensation, latency reporting, freeze, and offline render only after plug-in hosting is stable.

No allocation, file I/O, logging, UI work, or unbounded synchronization belongs in a render callback.

## Plug-in strategy

### Audio Units first

Audio Units are the native macOS route and integrate directly with AVAudioEngine. Phase one enumerates installed AUv2/AUv3 instruments and effects. Phase two instantiates them asynchronously, negotiates buses, embeds custom views when available, persists full state, and restores missing plug-ins safely.

### VST3 second

VST3 is not an AVAudioEngine plug-in format. It needs the Steinberg VST3 SDK, a C++ host layer, bus/event/process translation, editor embedding, state persistence, scanning and quarantine, and a bridge into LYLLTH's graph. It should be an explicit host module, not a promise implied by the Audio Unit browser.

For stability, plug-in discovery runs outside the main launch path and records scan failures. A failed or missing plug-in opens as a disabled placeholder while preserving its identifier and state. Release planning must decide whether LYLLTH is distributed directly with hardened runtime/notarization or through the Mac App Store; broad third-party plug-in compatibility and App Sandbox constraints must be evaluated before entitlements are frozen.

## Shared song format and phone handoff

`.lyllth` is a versioned document package:

```
Song.lyllth/
  manifest.json
  project.json
  Audio/
  Presets/
  PluginStates/
```

The musical core is shared with DrumKit: tempo/meter, patterns, arrangement blocks, source identifiers, sound presets, samples, and NIGHTSHAPE effects. Desktop-only material is additive: audio regions, automation, third-party plug-ins, routing, comp lanes, and mix state.

The first transfer path should use iCloud Documents because songs are self-contained files. Both apps open/save the same package family in the same ubiquity container and use coordinated document access. The user can begin in DrumKit, close the phone, and open the synced song on Mac. A visible sync state and conflict copy are required; “seamless” must never mean last-writer-wins data loss.

CloudKit is a later layer for library metadata, favorites, collaboration, and smaller record-level updates. It is not the first store for large multitrack audio assets.

Backward compatibility rule: when DrumKit opens a song containing Mac-only tracks, it must retain those opaque desktop sections when saving. The phone may show them as locked desktop tracks, but must not strip them from the package.

## Delivery sequence

### Milestone 0 — foundation (this checkout)

- native macOS document app
- NIGHTSHAPE workspace shell
- shared engine linked and audible
- Audio Unit discovery
- versioned package format

### Milestone 1 — DrumKit continuity

- extract a shared project-model package
- import current `.fkit` packages losslessly
- save the shared musical core into `.lyllth`
- open the same package from DrumKit
- iCloud Documents and conflict handling

### Milestone 2 — recording and editing

- audio input selection, monitoring, arming, count-in, recording, punch, and takes
- destructive-safe clip trim/split/fade/loop
- MIDI note editor and quantize
- undo/redo and autosave

### Milestone 3 — mixer and native plug-ins

- dynamic routing, buses, sends, sidechains, pre/post fader points
- AUv2/AUv3 insertion, editor hosting, parameter automation, state restore
- latency compensation and plug-in crash/scan recovery
- all NIGHTSHAPE effects available as built-in inserts

### Milestone 4 — VST3 and finishing

- Steinberg SDK host bridge and scanner
- VST3 instruments/effects, editor windows, automation, state restore
- freeze/flatten, stem export, offline bounce, project collection
- performance profiling, recovery tests, notarization, device-to-Mac transfer testing

## Definition of “fully functional”

The app is not complete when its screens exist. Completion requires recorded audio to survive relaunch, edits to undo, plug-ins to restore, projects to transfer between a physical iPhone and Mac without loss, bounces to null against playback within defined tolerances, and long stress sessions to run without render underruns or corrupted documents.
