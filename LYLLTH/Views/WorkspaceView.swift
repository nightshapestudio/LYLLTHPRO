import SwiftUI
import AppKit
import AVFoundation
import NightshapeAudioEngine

private final class LYAudioOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private static let supportedExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "mp3", "m4a", "mp4", "caf", "flac"
    ]

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

/// Builds a single label while keeping NIGHTSHAPE's typography split intact:
/// Adam for words, thin fixed-width SF for digits and numeric separators.
func mixedNumericLabel(
    _ string: String,
    labelFont: Font,
    numberFont: Font
) -> Text {
    string.reduce(Text("")) { partial, character in
        let isNumericGlyph = character.isNumber || "/:.−+–—".contains(character)
        return partial + Text(String(character)).font(isNumericGlyph ? numberFont : labelFont)
    }
}

/// Captures a secondary click without asking AppKit to draw a stock context
/// menu. One monitor covers the sequencer; hovered cells provide the target.
private struct LYSecondaryClickMonitor: NSViewRepresentable {
    let action: (CGPoint) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.action = action
    }

    final class MonitorView: NSView {
        var action: (CGPoint) -> Bool = { _ in false }
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            uninstallMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                return self.action(point) ? nil : event
            }
        }

        deinit {
            uninstallMonitor()
        }

        private func uninstallMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Keeps timeline edit shortcuts local to the visible Tracks area without
/// falling back to stock menus or stealing unrelated key events.
struct LYArrangementKeyMonitor: NSViewRepresentable {
    let action: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.action = action
    }

    final class MonitorView: NSView {
        var action: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            uninstallMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                return self.action(event) ? nil : event
            }
        }

        deinit { uninstallMonitor() }

        private func uninstallMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private enum LYWorkspaceMenu: Equatable {
    case project
    case songKey
    case addTrack
    case arrangementSnap
}

private struct LYAudioImportTarget {
    var trackID: UUID?
    var beat: Double
}

struct WorkspaceView: View {
    @Binding var document: LYLLTHSessionDocument
    @EnvironmentObject private var audio: AudioEngineController
    @EnvironmentObject private var plugins: AudioUnitCatalog

    @State private var selectedTrackID: UUID?
    @State private var selectedBrowserGroup = "NIGHTSHAPE"
    @State private var selectedBrowserItem = "DRUM SYNTH"
    /// SONG or PATTERN, DrumKit's two views. It also sets the transport mode.
    @State private var activeWorkspace = "SONG"
    @State private var showBrowser = true
    @State private var showInspector = true
    @State private var showMixer = true
    @State private var activeMenu: LYWorkspaceMenu?
    /// Which control opened the menu, and where every such control is.
    @State private var menuAnchorID: String?
    @State private var menuAnchors: [String: CGRect] = [:]
    @State private var audioImportError: String?
    @State private var inspectMain = false
    @State private var fxRequest: LYFXWindowRequest?
    @State private var fxOriginal: (rack: LYFXRack, reverb: ReverbState?) = (LYFXRack(), nil)
    @State private var fxPickerTarget: FXTarget?
    @State private var synthTrackID: UUID?
    @State private var drumTrackID: UUID?
    @State private var bounce = LYBounce()
    @State private var engineSync = LYCoalescedSync()
    @State private var recorder = LYRecorder()
    // Held with @State, not @StateObject: the workspace must not observe
    // these. Meters publish 20 times a second and the transport every step;
    // only the small views that draw them subscribe.
    @State private var transportDisplay = TransportDisplayState()
    @State private var meters = LYMeterStore()
    /// A passing message for the status bar: what an open or save left out.
    @State private var notice: String?
    @Environment(\.newDocument) private var newDocument

    private var selectedTrackBinding: Binding<LYTrack>? {
        guard let selectedTrackID,
              let index = document.session.tracks.firstIndex(where: { $0.id == selectedTrackID }) else {
            return nil
        }
        return $document.session.tracks[index]
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1_180
            let patternIndex = Binding<Int>(
                get: { max(0, document.session.activePatternIndex ?? 0) },
                set: { value in
                    document.session.activePatternIndex = max(0, value)
                    audio.syncSequencer(document.session, patternIndex: value)
                }
            )

            ZStack {
                VStack(spacing: 0) {
                    TransportBar(
                        session: $document.session,
                        activeWorkspace: $activeWorkspace,
                        recorder: recorder,
                        toggleRecording: toggleRecording,
                        openSongKeyMenu: { presentMenu(.songKey, from: "songKey") }
                    )
                    .environmentObject(audio)

                    WorkspaceStrip(
                        activeWorkspace: $activeWorkspace,
                        openProjectMenu: { presentMenu(.project, from: "stripProject") },
                        showBrowser: $showBrowser,
                        showInspector: $showInspector,
                        showMixer: $showMixer,
                        projectName: document.session.name,
                        openTrackMenu: { presentMenu(.addTrack, from: "stripTrack") },
                        export: presentExport
                    )

                HStack(spacing: 0) {
                    if showBrowser {
                        BrowserPanel(
                            selection: $selectedBrowserGroup,
                            selectedItem: $selectedBrowserItem,
                            projectAudio: Array(document.audioAssets.keys),
                            onEffect: { addEffectFromLibrary(named: $0) },
                            onSound: { openSoundFromLibrary($0) },
                            close: { showBrowser = false }
                        )
                        .environmentObject(plugins)
                        .frame(width: compact ? 214 : 238)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    if showInspector {
                        ChannelStripInspector(
                            session: $document.session,
                            selectedTrackID: selectedTrackID,
                            meters: meters,
                            openFX: { openFX($0, target: $1) },
                            toggleFX: { toggleFX($0, target: $1) },
                            openPicker: { target in withAnimation(LYLLTHTheme.snap) { fxPickerTarget = target } },
                            openSynth: { openSynth($0) },
                            openDrums: { openDrums($0) },
                            close: { showInspector = false }
                        )
                        .frame(width: 297)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    VStack(spacing: 0) {
                        if activeWorkspace == "PATTERN" {
                            SequencerWorkspace(
                                session: $document.session,
                                selectedTrackID: $selectedTrackID,
                                patternIndex: patternIndex,
                                currentStep: audio.currentStep,
                                isPlaying: audio.isPlaying,
                                waveformState: audio.engine.state.outputWaveformState,
                                syncEngine: { audio.syncSequencer(document.session) }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            arrangementPane

                            if showMixer {
                                MixerView(
                                    session: $document.session,
                                    selectedTrackID: $selectedTrackID,
                                    meters: meters,
                                    isMainSelected: inspectMain,
                                    selectMain: { inspectMain = true; showInspector = true },
                                    close: { showMixer = false }
                                )
                                .frame(height: compact ? 184 : 206)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                }
                .animation(LYLLTHTheme.settle, value: showBrowser)
                .animation(LYLLTHTheme.settle, value: showInspector)
                .animation(LYLLTHTheme.settle, value: showMixer)

                    StatusBar(
                        error: audioImportError ?? audio.audioEventError ?? audio.startupError ?? notice,
                        sampleRate: document.session.sampleRate,
                        bitDepth: document.session.bitDepth,
                        hiddenInspector: false
                    )
                }
                .background(LYLLTHTheme.background)

                workspaceMenuOverlay
                    .zIndex(120)

                fxPickerOverlay

                synthEditorOverlay
                    .zIndex(180)

                drumBrowserOverlay
                    .zIndex(181)

                LYBounceOverlay(bounce: bounce, cancel: { bounce.cancel(audio: audio) })
                    .zIndex(250)

                LYFXWindowHost(
                    session: $document.session,
                    request: $fxRequest,
                    original: fxOriginal,
                    transport: transportDisplay,
                    isPlaying: audio.isPlaying,
                    onTransportTap: { audio.togglePlayback() }
                )
                .zIndex(200)
            }
        }
        .coordinateSpace(name: LYDropdownOverlay<EmptyView>.space)
        .onPreferenceChange(LYMenuAnchorKey.self) { menuAnchors = $0 }
        .frame(minWidth: 960, minHeight: 640)
        .focusedSceneValue(\.lyWorkspace, workspaceActions)
        .onAppear {
            if document.isFromDrumKit {
                notice = (["OPENED FROM DRUMKIT  ·  SAVE KEEPS IT AS A LYLLTH SONG"] + document.importNotes.map { $0.uppercased() })
                    .joined(separator: "  ·  ")
            }
            // Project wavetables first, so synth tracks find them when they load.
            LYWavetableLibrary.shared.register(projectTables: document.wavetables)
            selectedTrackID = selectedTrackID ?? document.session.tracks.first?.id
            audio.prepare(document.session)
            LYMIDIInput.shared.start()
            DispatchQueue.main.async { updateMIDITarget() }
            audio.setTransportMode(transportMode, session: document.session, assets: document.audioAssets)
            audio.syncTimeline(document.session, assets: document.audioAssets)
            LYFXBridge.pushAll(document.session, engine: audio.engine)
            meters.track(document.session)
            audio.engine.setMainOutputVolume(volume: pow(10, (document.session.mainVolumeDB ?? 0) / 20))
            plugins.scan()
            #if DEBUG
            // Screenshot hook: LYLLTH_DEBUG_FX=<FXKind raw value> opens that
            // effect on the first track at launch.
            if let raw = ProcessInfo.processInfo.environment["LYLLTH_DEBUG_FX"],
               let kind = FXKind(rawValue: raw),
               let first = document.session.tracks.first {
                selectedTrackID = first.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { openFX(kind, target: .track(first.id)) }
            }
            if ProcessInfo.processInfo.environment["LYLLTH_DEBUG_DRUMS"] != nil, let first = document.session.tracks.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { openDrums(first.id) }
            }
            if ProcessInfo.processInfo.environment["LYLLTH_DEBUG_KEYMENU"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { presentMenu(.songKey, from: "songKey") }
            }
            if ProcessInfo.processInfo.environment["LYLLTH_DEBUG_SYNTH"] != nil,
               let track = document.session.tracks.first(where: { $0.synth != nil }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { openSynth(track.id) }
            }
            #endif
            // AppKit hands a new window's first text field the keyboard. The
            // workspace wants space for the transport, so start with nothing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onChange(of: audio.currentStep) { _, step in transportDisplay.update(step: step) }
        .onChange(of: audio.isPlaying) { _, playing in
            // Stop or space while recording ends the take.
            if !playing && recorder.phase == .recording { finishRecording() }
        }
        .onChange(of: selectedTrackID) { _, _ in
            inspectMain = false
            updateMIDITarget()
        }
        .onChange(of: document.session.tracks.map(\.isArmed)) { _, _ in updateMIDITarget() }
        .onChange(of: document.session.tracks.map { $0.synth != nil }) { _, _ in
            DispatchQueue.main.async { updateMIDITarget() }
        }
        .onChange(of: document.session.tracks.map(\.id)) { _, _ in
            // Engine channels follow track order, so a reorder or a new track
            // moves every rack onto a different channel.
            LYFXBridge.pushAll(document.session, engine: audio.engine)
            meters.track(document.session)
        }
        .onChange(of: document.session.mainVolumeDB) { _, value in
            audio.engine.setMainOutputVolume(volume: pow(10, (value ?? 0) / 20))
        }
        .onChange(of: activeWorkspace) { _, _ in
            audio.setTransportMode(transportMode, session: document.session, assets: document.audioAssets)
        }
        .onChange(of: document.session) { _, _ in
            // Arrangement edits have to reach the song frames and the audio
            // players. Deferred to just after this frame and coalesced, so a
            // click shows before the engine work runs.
            engineSync.schedule {
                audio.syncSequencer(document.session)
                audio.syncTimeline(document.session, assets: document.audioAssets)
            }
        }
        .onChange(of: document.session.bpm) { _, newValue in
            audio.updateTempo(newValue)
        }
        .onChange(of: document.session.songKey) { _, _ in
            audio.syncSequencer(document.session)
        }
        .onChange(of: document.session.numerator) { _, _ in
            audio.syncSequencer(document.session)
        }
        .onChange(of: document.session.denominator) { _, _ in
            audio.syncSequencer(document.session)
        }
    }

    /// Shows a track's pattern in the sequencer.
    private func openPattern(trackID: UUID, clipID: UUID) {
        guard let track = document.session.tracks.first(where: { $0.id == trackID }),
              let position = track.patternIndices.firstIndex(where: { track.clips[$0].id == clipID }) else { return }
        selectedTrackID = trackID
        document.session.activePatternIndex = position
        activeWorkspace = "PATTERN"
    }

    private var arrangementPane: some View {
        ArrangementView(
            session: $document.session,
            selectedTrackID: $selectedTrackID,
            isPlaying: audio.isPlaying,
            openSnapMenu: { presentMenu(.arrangementSnap, from: "snap") },
            openTrackMenu: { presentMenu(.addTrack, from: "laneTrack") },
            requestAudioImport: { trackID, beat in
                presentAudioImporter(trackID: trackID, atBeat: beat)
            },
            importDroppedAudio: { url, trackID, beat in
                importAudio(from: url, trackID: trackID, atBeat: beat)
            },
            previewAudioEvent: { clip in
                guard let path = clip.sourceRelativePath,
                      let data = document.audioAssets[path] else {
                    audioImportError = "This audio event's original file is missing from the project."
                    return
                }
                audio.previewAudioEvent(clip, assetData: data, projectBPM: document.session.bpm)
            },
            openSynth: { openSynth($0) },
            openDrums: { openDrums($0) },
            openPattern: { openPattern(trackID: $0, clipID: $1) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectTarget: FXTarget {
        if inspectMain { return .main }
        return selectedTrackID.map(FXTarget.track) ?? .main
    }

    private func openFX(_ kind: FXKind, target: FXTarget) {
        fxOriginal = (LYFXBridge.rack(for: target, in: document.session), document.session.reverb)
        NightshapeHaptics.selection()
        withAnimation(LYLLTHTheme.snap) { fxRequest = LYFXWindowRequest(kind: kind, target: target) }
    }

    private func toggleFX(_ kind: FXKind, target: FXTarget) {
        NightshapeHaptics.selection()
        if kind == .reverb && target == .main {
            var reverb = document.session.reverb ?? .neutral
            reverb.isBypassed.toggle()
            document.session.reverb = reverb
            LYFXBridge.pushReverb(document.session, engine: audio.engine)
            return
        }
        var rack = LYFXBridge.rack(for: target, in: document.session)
        var parked: Float?
        rack.toggleBypass(kind, parkedReverbSend: &parked)
        LYFXBridge.setRack(rack, for: target, in: &document.session)
        let index: Int? = { if case .track(let id) = target { return LYFXBridge.engineIndex(for: id, in: document.session) }; return nil }()
        LYFXBridge.push(kind, rack: rack, index: index, session: document.session, engine: audio.engine)
    }

    /// A hardware keyboard plays the selected track's synth, or failing that
    /// the first record-armed synth track.
    private func updateMIDITarget() {
        let tracks = document.session.tracks
        let target = tracks.first { $0.id == selectedTrackID && $0.synth != nil }
            ?? tracks.first { $0.isArmed && $0.synth != nil }
        LYMIDIInput.shared.setTarget(target.flatMap { audio.synthInstrument(for: $0.id) })
    }

    /// EXPORT: a real-time bounce of the whole song to WAV.
    private func presentExport() {
        let panel = NSSavePanel()
        panel.title = "EXPORT SONG"
        panel.prompt = "EXPORT"
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = document.session.name + ".wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let beatsPerBar = max(1, Double(document.session.numerator) * 4 / Double(max(document.session.denominator, 1)))
        let end = document.session.tracks.flatMap(\.clips)
            .filter(\.isInSong)
            .map { $0.startBeat + $0.lengthBeats }.max() ?? beatsPerBar
        let bars = max(1, ceil(end / beatsPerBar - 0.0001))
        let songSeconds = bars * beatsPerBar * 60 / max(document.session.bpm, 1)
        let previousWorkspace = activeWorkspace
        let previousLoop = document.session.isLoopEnabled
        bounce.start(url: url, songSeconds: songSeconds, audio: audio, prepare: {
            activeWorkspace = "SONG"
            document.session.isLoopEnabled = false
            audio.setTransportMode(.song, session: document.session, assets: document.audioAssets)
            audio.syncSequencer(document.session)
            audio.syncTimeline(document.session, assets: document.audioAssets)
        }, restore: {
            document.session.isLoopEnabled = previousLoop
            activeWorkspace = previousWorkspace
        })
    }

    // MARK: Recording

    private func toggleRecording() {
        if recorder.isActive { finishRecording(); return }
        let armedAudio = document.session.tracks.contains { $0.kind == .audio && $0.isArmed }
        let begin = {
            recorder.start(audio: audio, bpm: document.session.bpm, countIn: document.session.countIn ?? true,
                           recordAudio: armedAudio, onError: { audioImportError = $0 })
        }
        guard armedAudio else { begin(); return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { begin() } else { audioImportError = "MICROPHONE ACCESS WAS DECLINED. TURN IT ON IN SYSTEM SETTINGS › PRIVACY › MICROPHONE." }
                }
            }
        default:
            audioImportError = "LYLLTH CAN'T HEAR THE INPUT. ALLOW IT IN SYSTEM SETTINGS › PRIVACY › MICROPHONE."
        }
    }

    private func finishRecording() {
        recorder.stop(audio: audio) { notes, take in
            writeRecordedNotes(notes)
            if let take { placeRecordedAudio(take.url, transportBeat: take.startBeat) }
        }
    }

    /// Where a transport beat lands in the song: SONG cycles its window,
    /// PATTERN cycles the pattern.
    private func songBeat(forTransportBeat beat: Double) -> Double {
        let window = audio.songWindow
        return window.startBeat + beat.truncatingRemainder(dividingBy: max(window.lengthBeats, lyBeatsPerStep))
    }

    /// Recorded MIDI becomes steps: quantised to sixteenths, with velocity,
    /// pitch (on synth tracks) and length. Armed tracks record; with none
    /// armed, the selected track does.
    private func writeRecordedNotes(_ notes: [LYRecordedNote]) {
        guard !notes.isEmpty else { return }
        let musical = { (track: LYTrack) in track.kind == .drumkit || track.kind == .instrument }
        var targets = document.session.tracks.indices.filter { musical(document.session.tracks[$0]) && document.session.tracks[$0].isArmed }
        if targets.isEmpty, let selected = document.session.tracks.firstIndex(where: { $0.id == selectedTrackID }),
           musical(document.session.tracks[selected]) {
            targets = [selected]
        }
        guard !targets.isEmpty else {
            audioImportError = "ARM A TRACK (R) OR SELECT ONE TO RECORD MIDI INTO"
            return
        }
        let beatsPerBar = max(1, Double(document.session.numerator) * 4 / Double(max(document.session.denominator, 1)))
        let stepsPerBar = Int(beatsPerBar / lyBeatsPerStep)
        let inSong = activeWorkspace != "PATTERN"
        for trackIndex in targets {
            let track = document.session.tracks[trackIndex]
            let kind: LYClip.Kind = track.kind == .drumkit ? .pattern : .midi
            let root = track.rootNote ?? (track.kind == .drumkit ? 36 : 48)
            for note in notes {
                let length = max(1, min(64, Int((((note.offBeat ?? note.onBeat + 0.25) - note.onBeat) / lyBeatsPerStep).rounded())))
                var clipIndex: Int?
                var step = 0
                if inSong {
                    let beat = (songBeat(forTransportBeat: note.onBeat) / lyBeatsPerStep).rounded() * lyBeatsPerStep
                    let region = document.session.tracks[trackIndex].clips.firstIndex {
                        $0.isSequenced && $0.isOffTimeline != true && beat >= $0.startBeat - 0.0001 && beat < $0.startBeat + $0.lengthBeats - 0.0001
                    }
                    // Notes played over a placement go into the pattern it plays.
                    if let region {
                        let clip = document.session.tracks[trackIndex].clips[region]
                        step = Int(((beat - clip.startBeat + clip.loopOffsetBeats) / lyBeatsPerStep).rounded())
                        clipIndex = document.session.tracks[trackIndex].patternContentIndex(of: region)
                    }
                    if clipIndex == nil {
                        let barStart = floor(beat / beatsPerBar) * beatsPerBar
                        document.session.tracks[trackIndex].clips.append(LYClip(
                            name: "REC " + String(format: "%02d", Int(barStart / beatsPerBar) + 1),
                            kind: kind, startBeat: barStart, lengthBeats: beatsPerBar,
                            steps: Array(repeating: false, count: stepsPerBar),
                            stepParameters: Array(repeating: .default, count: stepsPerBar)))
                        clipIndex = document.session.tracks[trackIndex].clips.count - 1
                    }
                    if region == nil, let clipIndex {
                        let clip = document.session.tracks[trackIndex].clips[clipIndex]
                        step = Int(((beat - clip.startBeat + clip.loopOffsetBeats) / lyBeatsPerStep).rounded())
                    }
                } else {
                    let sequenced = document.session.tracks[trackIndex].patternIndices
                    guard !sequenced.isEmpty else { continue }
                    clipIndex = sequenced[min(max(0, document.session.activePatternIndex ?? 0), sequenced.count - 1)]
                    step = Int((note.onBeat / lyBeatsPerStep).rounded())
                }
                guard let clipIndex else { continue }
                var clip = document.session.tracks[trackIndex].clips[clipIndex]
                var steps = clip.steps ?? Array(repeating: false, count: stepsPerBar)
                var locks = clip.stepParameters ?? Array(repeating: .default, count: steps.count)
                if locks.count < steps.count { locks += Array(repeating: .default, count: steps.count - locks.count) }
                guard !steps.isEmpty else { continue }
                let index = ((step % steps.count) + steps.count) % steps.count
                steps[index] = true
                locks[index].velocity = min(max(Double(note.velocity) / 127, 0.05), 1)
                if track.kind == .instrument { locks[index].pitch = Double(min(max(note.note - root, -24), 24)) }
                locks[index].noteLength = Double(length)
                clip.steps = steps
                clip.stepParameters = locks
                document.session.tracks[trackIndex].clips[clipIndex] = clip
            }
        }
    }

    private func placeRecordedAudio(_ url: URL, transportBeat: Double) {
        guard let track = document.session.tracks.first(where: { $0.kind == .audio && $0.isArmed }) else { return }
        let beat = activeWorkspace == "PATTERN" ? 0 : songBeat(forTransportBeat: transportBeat)
        Task { @MainActor in
            do {
                var imported = try await LYAudioImporter.importFile(at: url)
                imported.displayName = "RECORDING " + String(format: "%02d", document.session.tracks.flatMap(\.clips).filter { $0.name.hasPrefix("RECORDING") }.count + 1)
                _ = document.addImportedAudio(imported, toTrackID: track.id, atBeat: beat)
            } catch {
                audioImportError = error.localizedDescription
            }
        }
    }

    /// LUNATK or DRUM SYNTH clicked in the library: open it on the
    /// selected track if it fits, else on the first track that does, else a
    /// new track.
    private func openSoundFromLibrary(_ name: String) {
        let tracks = document.session.tracks
        switch name {
        case "LUNATK":
            if let track = tracks.first(where: { $0.id == selectedTrackID && $0.kind == .instrument && $0.isChordTrack != true })
                ?? tracks.first(where: { $0.synth != nil }) {
                openSynth(track.id)
            } else {
                addTrack(kind: .instrument)
                if let id = selectedTrackID { openSynth(id) }
            }
        case "DRUM SYNTH":
            if let track = tracks.first(where: { $0.id == selectedTrackID && $0.kind == .drumkit })
                ?? tracks.first(where: { $0.kind == .drumkit }) {
                openDrums(track.id)
            } else {
                addTrack(kind: .drumkit)
                if let id = selectedTrackID { openDrums(id) }
            }
        default:
            break
        }
    }

    private func openDrums(_ trackID: UUID) {
        guard document.session.tracks.contains(where: { $0.id == trackID && $0.kind == .drumkit }) else { return }
        selectedTrackID = trackID
        withAnimation(LYLLTHTheme.settle) { drumTrackID = trackID }
    }

    @ViewBuilder
    private var drumBrowserOverlay: some View {
        if let trackID = drumTrackID, let track = document.session.tracks.first(where: { $0.id == trackID }) {
            let close = { withAnimation(LYLLTHTheme.snap) { drumTrackID = nil } }
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "drums",
                    title: "DRUM SYNTH  ·  " + track.name,
                    accent: LYLLTHTheme.teal,
                    size: CGSize(width: min(geo.size.width - 40, 980), height: min(geo.size.height - 60, 680)),
                    close: close
                ) {
                    LYDrumSoundBrowser(
                        trackName: track.name,
                        currentID: LYDrumSounds.presetID(for: track),
                        audition: { audio.auditionDrum($0) },
                        load: { preset in
                            guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
                            document.session.tracks[index].drumPresetID = preset.id
                        },
                        close: close
                    )
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
    }

    /// Opens LUNATK for a track. An instrument track still on a DrumKit
    /// preset is moved onto LUNATK first, starting from INIT.
    private func openSynth(_ trackID: UUID) {
        guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if document.session.tracks[index].synth == nil {
            guard document.session.tracks[index].kind == .instrument else { return }
            document.session.tracks[index].synth = .initPatch
            audio.syncSequencer(document.session)
        }
        selectedTrackID = trackID
        withAnimation(LYLLTHTheme.settle) { synthTrackID = trackID }
    }

    @ViewBuilder
    private var synthEditorOverlay: some View {
        if let trackID = synthTrackID,
           let track = document.session.tracks.first(where: { $0.id == trackID }),
           track.synth != nil {
            let close = { withAnimation(LYLLTHTheme.snap) { synthTrackID = nil } }
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "synth",
                    title: "LUNATK  ·  " + track.name,
                    accent: LYLLTHTheme.teal,
                    size: CGSize(width: min(geo.size.width - 32, 1340), height: min(geo.size.height - 56, 800)),
                    close: close
                ) {
                    LYSynthEditor(
                        patch: Binding(
                            get: { document.session.tracks.first { $0.id == trackID }?.synth ?? .initPatch },
                            set: { patch in
                                guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
                                document.session.tracks[index].synth = patch
                                audio.synthInstrument(for: trackID)?.apply(patch, bpm: document.session.bpm)
                            }
                        ),
                        trackName: track.name,
                        instrument: audio.synthInstrument(for: trackID),
                        storeTableInProject: { name, frames in
                            document.wavetables[name] = LYWavetableLibrary.floatData(frames)
                        },
                        close: close
                    )
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
    }

    /// Adds or removes an effect from a chain, as DrumKit's ADD / REMOVE does.
    private func toggleMembership(_ kind: FXKind, target: FXTarget) {
        var rack = LYFXBridge.rack(for: target, in: document.session)
        var chain = rack.chain(isMain: target == .main)
        if let index = chain.firstIndex(of: kind) { chain.remove(at: index) } else { chain.append(kind) }
        rack.order = chain
        LYFXBridge.setRack(rack, for: target, in: &document.session)
        LYFXBridge.pushRack(target: target, session: document.session, engine: audio.engine)
    }

    /// A library effect clicked: put it on the inspected channel and open it.
    private func addEffectFromLibrary(named name: String) {
        guard let kind = FXKind.allCases.first(where: { $0.title == name }) else { return }
        let target = inspectTarget
        if case .track(let id) = target, LYFXBridge.engineIndex(for: id, in: document.session) == nil { return }
        if !LYFXBridge.rack(for: target, in: document.session).chain(isMain: target == .main).contains(kind) {
            toggleMembership(kind, target: target)
        }
        showInspector = true
        openFX(kind, target: target)
    }

    @ViewBuilder
    private var fxPickerOverlay: some View {
        if let target = fxPickerTarget {
            let close = { withAnimation(LYLLTHTheme.snap) { fxPickerTarget = nil } }
            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                FXPickerWindowView(
                    targetName: target == .main ? "MAIN MIX" : (document.session.tracks.first { .track($0.id) == target }?.name ?? "TRACK"),
                    target: target,
                    chainOrder: LYFXBridge.rack(for: target, in: document.session).chain(isMain: target == .main),
                    onToggle: { toggleMembership($0, target: target) },
                    onDone: close
                )
                .frame(width: 380)
                .frame(maxHeight: 640)
                .scaleEffect(1.25)
            }
            .preferredColorScheme(.dark)
            .zIndex(150)
        }
    }

    private var transportMode: LYTransportMode {
        activeWorkspace == "PATTERN" ? .pattern : .song
    }

    /// Finder drops land where they were dropped: on that track and beat.
    private func importAudio(from url: URL, trackID: UUID?, atBeat beat: Double) {
        Task { @MainActor in
            do {
                let imported = try await LYAudioImporter.importFile(at: url)
                _ = document.addImportedAudio(imported, toTrackID: trackID, atBeat: beat)
                selectedTrackID = trackID ?? document.session.tracks.last(where: { $0.kind == .audio })?.id
                audioImportError = nil
            } catch {
                audioImportError = error.localizedDescription
            }
        }
    }

    /// Enables supported extensions directly because some macOS 26
    /// installations expose valid WAV files without a stable audio-conforming
    /// UTI. LYAudioImporter still validates both the extension and AVFoundation
    /// decode before changing project state.
    private func presentAudioImporter(trackID: UUID?, atBeat beat: Double) {
        let panel = NSOpenPanel()
        panel.title = "IMPORT AUDIO"
        panel.message = "Choose a WAV, AIFF, MP3, M4A, CAF, or FLAC audio file."
        panel.prompt = "IMPORT"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        // macOS 26 can expose valid WAV files with dynamic UTTypes that do not
        // conform to `.audio`. Explicit enablement keeps those rows selectable;
        // the importer still performs the authoritative decode validation.
        let panelDelegate = LYAudioOpenPanelDelegate()
        panel.delegate = panelDelegate
        panel.allowedContentTypes = []

        let target = LYAudioImportTarget(trackID: trackID, beat: beat)
        let projectWindow = NSApp.keyWindow
        let completion: (NSApplication.ModalResponse) -> Void = { [panelDelegate] response in
            _ = panelDelegate
            projectWindow?.makeKeyAndOrderFront(nil)
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let imported = try await LYAudioImporter.importFile(at: url)
                    _ = document.addImportedAudio(
                        imported,
                        toTrackID: target.trackID,
                        atBeat: target.beat
                    )
                    selectedTrackID = target.trackID
                        ?? document.session.tracks.first(where: { $0.kind == .audio })?.id
                    audioImportError = nil
                } catch {
                    audioImportError = error.localizedDescription
                }
            }
        }
        panel.begin(completionHandler: completion)
    }

    // MARK: Project

    private var workspaceActions: LYWorkspaceActions {
        LYWorkspaceActions(
            showSequencer: { activeWorkspace = "PATTERN" },
            showArrangement: { activeWorkspace = "SONG" },
            openDrumKitProject: openDrumKitProject,
            saveDrumKitProject: saveDrumKitProject,
            exportSong: presentExport
        )
    }

    private func runProjectAction(_ action: ProjectPanel.Action) {
        // Document commands go to this window's document through AppKit.
        switch action {
        case .new: NSDocumentController.shared.newDocument(nil)
        case .open: NSDocumentController.shared.openDocument(nil)
        case .save: NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        case .saveAs: NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
        case .openFKit: openDrumKitProject()
        case .saveFKit: saveDrumKitProject()
        case .export: presentExport()
        }
    }

    /// A DrumKit project opens as a new song in its own window.
    private func openDrumKitProject() {
        let panel = NSOpenPanel()
        panel.title = "OPEN DRUMKIT PROJECT"
        panel.prompt = "OPEN"
        panel.allowedContentTypes = [.drumkitProject]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try LYFKit.importProject(from: Data(contentsOf: url))
            newDocument(LYLLTHSessionDocument(imported: imported))
        } catch {
            audioImportError = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func saveDrumKitProject() {
        let panel = NSSavePanel()
        panel.title = "SAVE AS DRUMKIT PROJECT"
        panel.prompt = "SAVE"
        panel.allowedContentTypes = [.drumkitProject]
        panel.nameFieldStringValue = document.session.name + ".fkit"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let exported = try LYFKit.exportProject(document.session, assets: document.audioAssets)
            try exported.data.write(to: url, options: .atomic)
            notice = exported.notes.isEmpty
                ? "SAVED " + url.lastPathComponent.uppercased()
                : "SAVED " + url.lastPathComponent.uppercased() + "  ·  " + exported.notes.joined(separator: "  ·  ").uppercased()
        } catch {
            audioImportError = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func presentMenu(_ menu: LYWorkspaceMenu, from anchor: String? = nil) {
        menuAnchorID = anchor
        withAnimation(LYLLTHTheme.snap) { activeMenu = menu }
    }

    private func dismissMenu() {
        withAnimation(LYLLTHTheme.snap) { activeMenu = nil }
    }

    @ViewBuilder
    private var workspaceMenuOverlay: some View {
        if let activeMenu {
            LYDropdownOverlay(anchor: menuAnchorID.flatMap { menuAnchors[$0] }, dismiss: dismissMenu) {
                switch activeMenu {
                case .songKey:
                    SongKeyPicker(
                        key: Binding(
                            get: { document.session.songKey ?? .default },
                            set: { document.session.songKey = $0 }
                        ),
                        close: dismissMenu
                    )
                case .addTrack:
                    AddTrackPanel(
                        add: { kind in
                            addTrack(kind: kind)
                            dismissMenu()
                        },
                        close: dismissMenu
                    )
                case .project:
                    ProjectPanel(
                        name: document.session.name,
                        run: { action in
                            dismissMenu()
                            runProjectAction(action)
                        },
                        close: dismissMenu
                    )
                case .arrangementSnap:
                    ArrangementSnapPanel(
                        editor: arrangementEditorBinding,
                        close: dismissMenu
                    )
                }
            }
            .zIndex(100)
        }
    }

    private var arrangementEditorBinding: Binding<LYArrangementEditorState> {
        Binding(
            get: {
                var value = document.session.arrangementEditor ?? .default
                value.normalize()
                return value
            },
            set: { newValue in
                var value = newValue
                value.normalize()
                document.session.arrangementEditor = value
            }
        )
    }

    private func addTrack(kind: LYTrackKind) {
        let sameKindCount = document.session.tracks.filter { $0.kind == kind }.count + 1
        let name: String
        let accent: LYAccent
        switch kind {
        case .drumkit:
            name = "DRUM " + String(format: "%02d", sameKindCount)
            accent = .teal
        case .instrument:
            name = "SYNTH " + String(format: "%02d", sameKindCount)
            accent = .indigo
        case .audio:
            name = "AUDIO " + String(format: "%02d", sameKindCount)
            accent = .purple
        case .auxiliary:
            name = "RETURN " + String(Character(UnicodeScalar(64 + min(sameKindCount, 26))!))
            accent = .teal
        }

        var track = LYTrack(name: name, kind: kind, accent: accent, volumeDB: -6)
        if kind == .instrument { track.synth = .factory(named: "NIGHT PAD") ?? .initPatch }
        if kind == .drumkit || kind == .instrument {
            let clipKind: LYClip.Kind = kind == .drumkit ? .pattern : .midi
            let count = document.session.tracks
                .compactMap { $0.clips.first?.steps?.count }
                .max() ?? 16
            track.synthPresetID = (kind == .drumkit ? SynthPreset.deepMono : SynthPreset.junoDream).rawValue
            track.rootNote = kind == .drumkit ? 36 : 48
            track.clips = [
                LYClip(
                    name: "PATTERN 01",
                    kind: clipKind,
                    startBeat: 0,
                    lengthBeats: Double(max(count / 4, 1)),
                    steps: Array(repeating: false, count: count),
                    stepParameters: Array(repeating: .default, count: count)
                )
            ]
        }
        document.session.tracks.append(track)
        selectedTrackID = track.id
        audio.syncSequencer(document.session)
    }
}

// MARK: - Transport

private struct TransportBar: View {
    @Binding var session: LYLLTHSession
    @Binding var activeWorkspace: String
    @ObservedObject var recorder: LYRecorder
    let toggleRecording: () -> Void
    @EnvironmentObject private var audio: AudioEngineController
    let openSongKeyMenu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            LYWordmarkLockup()
                .frame(width: 300, alignment: .leading)

            divider

            HStack(spacing: 12) {
                Button { if recorder.isActive { toggleRecording() } else { audio.stop() } } label: {
                    Rectangle()
                        .fill(LYLLTHTheme.chromeText)
                        .frame(width: 9, height: 9)
                        .frame(width: 34, height: 34)
                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop and return to the start")
                .accessibilityLabel("Stop")

                LYPlayButton(isPlaying: audio.isPlaying) { audio.togglePlayback() }

                LYRecordButton(isOn: recorder.isActive, action: toggleRecording)
            }
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 3) {
                if case .countingIn(let beatsLeft) = recorder.phase {
                    Text("\(beatsLeft)")
                        .font(LYLLTHTheme.value(24))
                        .foregroundStyle(LYLLTHTheme.record)
                        .lyBloom(LYLLTHTheme.record)
                } else {
                    Text(audio.timecode)
                        .font(LYLLTHTheme.value(24))
                        .tracking(1.1)
                        .foregroundStyle(LYLLTHTheme.text)
                }
                Text(statusText)
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(recorder.isActive ? LYLLTHTheme.record : (audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.dim))
            }
            .frame(width: 128, alignment: .leading)

            divider

            LYModeSwitch(activeWorkspace: $activeWorkspace)
                .padding(.horizontal, 18)

            divider

            TempoReadout(
                bpm: $session.bpm,
                numerator: session.numerator,
                denominator: session.denominator
            )
            .padding(.horizontal, 18)

            divider

            SongKeyReadout(
                key: Binding(
                    get: { session.songKey ?? .default },
                    set: { session.songKey = $0 }
                ),
                openMenu: openSongKeyMenu
            )
            .lyMenuAnchor("songKey")
            .padding(.horizontal, 18)

            Spacer(minLength: 18)

            HStack(spacing: 6) {
                TransportUtility(
                    icon: "metronome",
                    title: "CLICK",
                    tint: LYLLTHTheme.teal,
                    isOn: audio.isMetronomeEnabled,
                    action: { audio.toggleMetronome(for: session) }
                )
                .help("Metronome")
                TransportUtility(
                    icon: "4.circle",
                    title: "COUNT",
                    tint: LYLLTHTheme.record,
                    isOn: session.countIn ?? true,
                    action: { session.countIn = !(session.countIn ?? true) }
                )
                .help("Four clicks before recording starts")
                TransportUtility(
                    icon: "repeat",
                    title: "LOOP",
                    tint: LYLLTHTheme.indigo,
                    isOn: session.isLoopActive,
                    action: toggleLoop
                )
                .help(loopHelp)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 112)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline(color: LYLLTHTheme.lineStrong) }
    }

    private var divider: some View {
        Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1, height: 46)
    }

    private var statusText: String {
        switch recorder.phase {
        case .countingIn: return "COUNT IN"
        case .recording: return "RECORDING"
        case .idle: return audio.isPlaying ? "PLAYING" : "READY"
        }
    }

    private var loopHelp: String {
        guard let loop = session.loopRange else { return "Loop the first four bars" }
        let beatsPerBar = max(1, Double(session.numerator) * 4 / Double(max(session.denominator, 1)))
        let first = Int(loop.startBeat / beatsPerBar) + 1
        let last = Int(ceil((loop.startBeat + loop.lengthBeats) / beatsPerBar))
        return "Loop bars \(first)–\(last). Drag the brace in the ruler to change it."
    }

    private func toggleLoop() {
        if session.loopRange == nil {
            let beatsPerBar = max(1, Double(session.numerator) * 4 / Double(max(session.denominator, 1)))
            session.loopRange = LYLoopRange(startBeat: 0, lengthBeats: beatsPerBar * 4)
            session.isLoopEnabled = true
        } else {
            session.isLoopEnabled = !session.isLoopActive
        }
    }
}

/// LYLLTH's lockup, built the way DRUMKIT's is: the first half in the NIGHTSHAPE
/// outline cut, the second half solid, both carrying the same tie-dye field,
/// with the tracked purple byline underneath.
private struct LYWordmarkLockup: View {
    private let size: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            letters
                .hidden()
                .overlay(LYWordmarkTieDye().mask(letters))
                .offset(y: LYLLTHTheme.wordmarkOpticalDrop(size))
                .shadow(color: LYLLTHTheme.teal.opacity(0.08), radius: 5)
                .accessibilityLabel("LYLLTH")
            // Sized from the fonts' own metrics to span 75% of the wordmark.
            Text("BY NIGHTSHAPE")
                .font(LYLLTHTheme.label(11))
                .tracking(7.1)
                .foregroundStyle(LYLLTHTheme.purple)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
    }

    private var letters: some View {
        HStack(spacing: 0) {
            Text("LYL").font(LYLLTHTheme.wordmarkOutline(size))
            Text("LTH").font(LYLLTHTheme.wordmark(size))
        }
        .tracking(1.6)
        .fixedSize()
    }
}

private struct LYPlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LYLLTHTheme.teal.opacity(isPlaying ? 0.10 : 0))
                Circle()
                    .stroke(isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.lineFocused, lineWidth: 1.5)
                if isPlaying {
                    HStack(spacing: 5) {
                        Rectangle().frame(width: 4, height: 16)
                        Rectangle().frame(width: 4, height: 16)
                    }
                    .foregroundStyle(LYLLTHTheme.teal)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LYLLTHTheme.chromeText)
                        .offset(x: 1.5)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(LYPressScaleStyle())
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .help("Play / pause (space)")
    }
}

private struct LYRecordButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LYLLTHTheme.record.opacity(isOn ? 0.14 : 0))
                Circle().stroke(isOn ? LYLLTHTheme.record : LYLLTHTheme.lineStrong, lineWidth: 1.5)
                Circle()
                    .fill(LYLLTHTheme.record)
                    .frame(width: 12, height: 12)
                    .opacity(isOn ? 1 : 0.75)
            }
            .frame(width: 34, height: 34)
            .lyBloom(LYLLTHTheme.record, isOn: isOn)
            .contentShape(Circle())
        }
        .buttonStyle(LYPressScaleStyle())
        .accessibilityLabel("Record")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("Record enable")
    }
}

/// DrumKit's PATTERN | SONG switch: the live mode is set large and lit, the
/// other sits small and quiet beside it.
private struct LYModeSwitch: View {
    @Binding var activeWorkspace: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            word("PATTERN", key: "PATTERN", color: LYLLTHTheme.purple)
            word("SONG", key: "SONG", color: LYLLTHTheme.teal)
        }
        .animation(LYLLTHTheme.glide, value: activeWorkspace)
    }

    private func word(_ title: String, key: String, color: Color) -> some View {
        let isActive = activeWorkspace == key
        return Button { activeWorkspace = key } label: {
            Text(title)
                .font(isActive ? LYLLTHTheme.label(25, weight: .light) : LYLLTHTheme.label(10, weight: .bold))
                .tracking(isActive ? 2.2 : 1.8)
                .foregroundStyle(isActive ? color : LYLLTHTheme.dim)
                .lyBloom(color, isOn: isActive)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help(key == "SONG" ? "Play the arrangement" : "Loop and edit one pattern")
    }
}

/// The acknowledgement every NIGHTSHAPE control gives a click.
struct LYPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(LYLLTHTheme.snap, value: configuration.isPressed)
    }
}

private struct SongKeyReadout: View {
    @Binding var key: SongKey
    let openMenu: () -> Void

    var body: some View {
        Button(action: openMenu) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KEY")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(LYLLTHTheme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(key.rootName)
                        .font(LYLLTHTheme.value(20))
                    Text(key.isMinor ? "MIN" : "MAJ")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .bold))
                }
                .foregroundStyle(LYLLTHTheme.teal)
            }
            .frame(minWidth: 66, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Song key \(key.name)")
        .accessibilityHint("Choose the key used by chord tracks")
    }
}

private struct SongKeyPicker: View {
    @Binding var key: SongKey
    let close: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(55), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LYNightshapeMenuHeader(
                eyebrow: "HARMONY",
                title: "SONG KEY",
                accent: LYLLTHTheme.teal,
                close: close
            )

            Text("CHORD TRACKS FOLLOW THIS TONAL CENTER")
                .font(LYLLTHTheme.label(8))
                .tracking(1.1)
                .foregroundStyle(LYLLTHTheme.dim)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 13)

            LYNightshapeMenuDivider()

            HStack(spacing: 6) {
                KeyModeButton(title: "MINOR", isOn: key.isMinor) {
                    key = SongKey(root: key.root, isMinor: true)
                }
                KeyModeButton(title: "MAJOR", isOn: !key.isMinor) {
                    key = SongKey(root: key.root, isMinor: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<SongKey.rootNames.count, id: \.self) { root in
                    Button {
                        key = SongKey(root: root, isMinor: key.isMinor)
                    } label: {
                        Text(SongKey.rootNames[root])
                            .font(LYLLTHTheme.value(17))
                            .foregroundStyle(root == key.root ? LYLLTHTheme.teal : LYLLTHTheme.lavender)
                            .frame(width: 55, height: 37)
                            .background(root == key.root ? LYLLTHTheme.teal.opacity(0.12) : LYLLTHTheme.panelRaised)
                            .overlay(Rectangle().stroke(root == key.root ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: root == key.root ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            Button("DONE", action: close)
                .buttonStyle(LYChromeButtonStyle(active: true, compact: true))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(width: 286)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
    }
}

private struct KeyModeButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(LYChromeButtonStyle(active: isOn, tint: LYLLTHTheme.indigo, compact: true))
            .frame(maxWidth: .infinity)
    }
}

private struct AddTrackPanel: View {
    let add: (LYTrackKind) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(
                eyebrow: "WORKSPACE",
                title: "ADD TRACK",
                accent: LYLLTHTheme.teal,
                close: close
            )
            LYNightshapeMenuDivider()

            VStack(spacing: 8) {
                LYNightshapeMenuRow(
                    icon: "square.grid.3x3.fill",
                    title: "DRUMKIT TRACK",
                    detail: "PATTERN + NIGHTSHAPE DRUM ENGINE",
                    accent: LYLLTHTheme.teal,
                    action: { add(.drumkit) }
                )
                LYNightshapeMenuRow(
                    icon: "pianokeys",
                    title: "INSTRUMENT TRACK",
                    detail: "REALTIME SYNTH OR PLUG-IN",
                    accent: LYLLTHTheme.indigo,
                    action: { add(.instrument) }
                )
                LYNightshapeMenuRow(
                    icon: "waveform",
                    title: "AUDIO TRACK",
                    detail: "RECORD OR ARRANGE AUDIO",
                    accent: LYLLTHTheme.purple,
                    action: { add(.audio) }
                )
                LYNightshapeMenuRow(
                    icon: "arrow.triangle.branch",
                    title: "AUX RETURN",
                    detail: "SHARED EFFECTS + ROUTING",
                    accent: LYLLTHTheme.teal,
                    action: { add(.auxiliary) }
                )
            }
            .padding(14)
        }
        .frame(width: 330)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
    }
}

private struct TempoReadout: View {
    @Binding var bpm: Double
    let numerator: Int
    let denominator: Int
    @State private var dragStartBPM: Double?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(numerator)/\(denominator)")
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.dim)
                Text("BPM")
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.purple)
                    .lyBloom(LYLLTHTheme.purple)
            }
            Text("\(Int(bpm.rounded()))")
                .font(LYLLTHTheme.value(36))
                .foregroundStyle(LYLLTHTheme.lavender)
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { gesture in
                    if dragStartBPM == nil { dragStartBPM = bpm }
                    let origin = dragStartBPM ?? bpm
                    bpm = min(max((origin - gesture.translation.height / 2.4).rounded(), 40), 240)
                }
                .onEnded { _ in dragStartBPM = nil }
        )
        .help("Drag vertically to change the tempo")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Int(bpm.rounded())) BPM, \(numerator) / \(denominator)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bpm = min(bpm + 1, 240)
            case .decrement: bpm = max(bpm - 1, 40)
            @unknown default: break
            }
        }
    }
}

private struct TransportUtility: View {
    let icon: String
    let title: String
    var tint = LYLLTHTheme.teal
    var isOn = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1.4)
            }
            .foregroundStyle(isOn ? tint : LYLLTHTheme.chromeText)
            .lyBloom(tint, isOn: isOn)
            .frame(width: 54, height: 46)
            .background(tint.opacity(isOn ? LYLLTHTheme.controlFill : 0))
            .overlay(Rectangle().stroke(isOn ? tint.opacity(0.9) : LYLLTHTheme.lineStrong, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(LYPressScaleStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Workspace chrome

/// The bar right above the tracks: the song and its file actions, the
/// switch between the sequencer and the arrangement, and the panels.
struct WorkspaceStrip: View {
    @Binding var activeWorkspace: String
    let openProjectMenu: () -> Void
    @Binding var showBrowser: Bool
    @Binding var showInspector: Bool
    @Binding var showMixer: Bool
    let projectName: String
    let openTrackMenu: () -> Void
    let export: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: openProjectMenu) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LYLLTHTheme.teal)
                    mixedNumericLabel(
                        projectName,
                        labelFont: LYLLTHTheme.label(10.5, weight: .bold),
                        numberFont: LYLLTHTheme.value(11)
                    )
                    .tracking(1.5)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .lyMenuAnchor("stripProject")
            .help("Song: new, open, save, DrumKit .fkit, export")

            LYViewSwitch(activeWorkspace: $activeWorkspace)

            Text(activeWorkspace == "PATTERN"
                 ? "LOOPS ONE PATTERN  ·  NEW, DUPLICATE, PLACE IN SONG"
                 : "PLAYS THE SONG  ·  DOUBLE-CLICK A PATTERN TO EDIT IT")
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(LYLLTHTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            LYMIDIIndicator(midi: LYMIDIInput.shared)

            Button(action: export) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 9, weight: .bold))
                    Text("EXPORT")
                }
            }
            .buttonStyle(LYChromeButtonStyle(compact: true))
            .help("Bounce the whole song to a WAV (⌘E)")

            HStack(spacing: 2) {
                VisibilityButton(icon: "books.vertical", help: "Library", isOn: $showBrowser)
                VisibilityButton(icon: "rectangle.bottomthird.inset.filled", help: "Mixer", isOn: $showMixer)
                VisibilityButton(icon: "slider.vertical.3", help: "Inspector", isOn: $showInspector)
            }

            Button(action: openTrackMenu) {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("TRACK")
                }
            }
            .buttonStyle(LYChromeButtonStyle(compact: true))
            .lyMenuAnchor("stripTrack")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }
}

/// SEQUENCER | ARRANGE: which view fills the window. The sequencer loops the
/// pattern being edited; the arrangement plays the song.
struct LYViewSwitch: View {
    @Binding var activeWorkspace: String

    var body: some View {
        HStack(spacing: 0) {
            tab("square.grid.3x3.fill", "SEQUENCER", key: "PATTERN", color: LYLLTHTheme.purple, shortcut: "⌘1")
            Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1, height: 28)
            tab("rectangle.split.3x1", "ARRANGE", key: "SONG", color: LYLLTHTheme.teal, shortcut: "⌘2")
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .animation(LYLLTHTheme.snap, value: activeWorkspace)
    }

    private func tab(_ icon: String, _ title: String, key: String, color: Color, shortcut: String) -> some View {
        let isOn = activeWorkspace == key
        return Button { activeWorkspace = key } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(isOn ? color : LYLLTHTheme.dim)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(color.opacity(isOn ? 0.12 : 0))
            .overlay(alignment: .bottom) { Rectangle().fill(isOn ? color : .clear).frame(height: 2) }
            .lyBloom(color, isOn: isOn && color != LYLLTHTheme.teal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key == "PATTERN" ? "Sequencer: edit and create patterns (\(shortcut))" : "Arrangement: build the song (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The song menu under the project name.
struct ProjectPanel: View {
    enum Action { case new, open, save, saveAs, openFKit, saveFKit, export }

    let name: String
    let run: (Action) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(eyebrow: "SONG", title: name, accent: LYLLTHTheme.teal, close: close)
            LYNightshapeMenuDivider()
            VStack(spacing: 6) {
                row("doc.badge.plus", "NEW SONG", "⌘N", .new)
                row("folder", "OPEN…", "⌘O  ·  LYLLTH SONGS", .open)
                row("square.and.arrow.down", "SAVE", "⌘S", .save)
                row("square.and.arrow.down.on.square", "SAVE AS…", "⇧⌘S", .saveAs)
            }
            .padding(12)
            LYNightshapeMenuDivider()
            VStack(spacing: 6) {
                row("square.grid.3x3", "OPEN DRUMKIT PROJECT…", "⇧⌘O  ·  .FKIT, OPENS AS A NEW SONG", .openFKit, accent: LYLLTHTheme.purple)
                row("iphone", "SAVE AS DRUMKIT PROJECT…", "⌥⌘S  ·  .FKIT FOR THE PHONE", .saveFKit, accent: LYLLTHTheme.purple)
                row("waveform", "EXPORT SONG…", "⌘E  ·  WAV", .export, accent: LYLLTHTheme.indigo)
            }
            .padding(12)
        }
        .frame(width: 330)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
    }

    private func row(_ icon: String, _ title: String, _ detail: String, _ action: Action, accent: Color = LYLLTHTheme.teal) -> some View {
        LYNightshapeMenuRow(icon: icon, title: title, detail: detail, accent: accent, action: { run(action) })
    }
}

struct VisibilityButton: View {
    let icon: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? LYLLTHTheme.teal : LYLLTHTheme.dim)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Library

/// One NIGHTSHAPE effect as DrumKit names and colours it. The colour is the one
/// its node carries in DrumKit's FX signal path, so a row here and the node it
/// opens always agree.
private struct LYNightshapeEffect: Hashable {
    let name: String
    let detail: String
    let category: String
    let accent: LYAccent?

    var color: Color { accent.map(LYLLTHTheme.accent) ?? LYLLTHTheme.chromeText }

    static let all: [LYNightshapeEffect] = [
        .init(name: "EQUALIZER", detail: "5-BAND", category: "TONE", accent: .teal),
        .init(name: "TAPE SATURATION", detail: "DRIVE · HEAD", category: "TONE", accent: .indigo),
        .init(name: "FILTER", detail: "CUTOFF · RES", category: "TONE", accent: .teal),
        .init(name: "STACK", detail: "AMP · CAB", category: "TONE", accent: .purple),
        .init(name: "COMPRESSOR", detail: "PUNCH · GLUE", category: "DYNAMICS", accent: .indigo),
        .init(name: "STRIKE", detail: "ATTACK · SUSTAIN", category: "DYNAMICS", accent: .indigo),
        .init(name: "SIDECHAIN PUMP", detail: "DUCK CURVE", category: "DYNAMICS", accent: .indigo),
        .init(name: "REVERB", detail: "ROOM · HALL · PLATE · SPRING", category: "SPACE", accent: .purple),
        .init(name: "DELAY", detail: "TIME · FEEDBACK", category: "SPACE", accent: .teal),
        .init(name: "SIGNAL BLOOM", detail: "STEP BLOOM", category: "SPACE", accent: .purple),
        .init(name: "VOID GATE", detail: "GATED VERB", category: "SPACE", accent: .purple),
        .init(name: "UNDERTOW", detail: "REVERSE SWELL", category: "SPACE", accent: .purple),
        .init(name: "SPLIT FIELD", detail: "WIDTH · MONO", category: "SPACE", accent: .teal),
        .init(name: "CHORUS", detail: "RATE · WIDTH", category: "MOTION", accent: .indigo),
        .init(name: "FLANGER", detail: "SWEEP · FEEDBACK", category: "MOTION", accent: .indigo),
        .init(name: "SONIC DECIMATOR", detail: "DESTROY · CRUSH", category: "DESTRUCTION", accent: .purple),
        .init(name: "FRACTURE", detail: "GLITCH · STUTTER", category: "DESTRUCTION", accent: .purple),
        .init(name: "DEADLOCK", detail: "CRUSH · CRUNCH", category: "DESTRUCTION", accent: .purple),
        .init(name: "ANVIL", detail: "ROOT · RING", category: "DESTRUCTION", accent: .purple),
        .init(name: "SHEAR", detail: "FOLD · SYMMETRY", category: "DESTRUCTION", accent: .purple),
        .init(name: "ELASTIC LIMITER", detail: "FINAL LIMIT", category: "OUTPUT", accent: nil)
    ]
}

private struct BrowserPanel: View {
    @Binding var selection: String
    @Binding var selectedItem: String
    let projectAudio: [String]
    let onEffect: (String) -> Void
    let onSound: (String) -> Void
    let close: () -> Void
    @EnvironmentObject private var plugins: AudioUnitCatalog
    @State private var query = ""
    /// The search field never takes focus by itself, so space stays play.
    @FocusState private var searchFocused: Bool

    private let groups = ["NIGHTSHAPE", "AU INST", "AU FX", "PROJECT"]
    private let categories = ["TONE", "DYNAMICS", "SPACE", "MOTION", "DESTRUCTION", "OUTPUT"]

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "LIBRARY", actionIcon: "xmark", action: close)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LYLLTHTheme.dim)
                TextField("SEARCH", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onAppear { DispatchQueue.main.async { searchFocused = false } }
                    .onSubmit { searchFocused = false }
                    .onExitCommand { searchFocused = false }
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .bottom) { LYHairline() }

            HStack(spacing: 0) {
                ForEach(groups, id: \.self) { group in
                    let isOn = selection == group
                    Button { selection = group } label: {
                        Text(group)
                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                            .tracking(0.9)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isOn ? LYLLTHTheme.text : LYLLTHTheme.dim)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .lyRisingBloom(LYLLTHTheme.teal, isOn: isOn, strength: 0.6)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(isOn ? LYLLTHTheme.teal : .clear).frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .background(LYLLTHTheme.panel)
            .overlay(alignment: .bottom) { LYHairline() }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.bottom, 8)
            }
            .lyScrollers()

            HStack(spacing: 8) {
                LYLED(color: plugins.isScanning ? LYLLTHTheme.indigo : LYLLTHTheme.teal, size: 4)
                (plugins.isScanning
                    ? Text("SCANNING AUDIO UNITS").font(LYLLTHTheme.label(7.5, weight: .bold))
                    : mixedNumericLabel(
                        "\(plugins.instruments.count + plugins.effects.count) AUDIO UNITS",
                        labelFont: LYLLTHTheme.label(7.5, weight: .bold),
                        numberFont: LYLLTHTheme.value(8.5)
                    ))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .top) { LYHairline() }
        }
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case "NIGHTSHAPE":
            section("SOUND")
            ForEach(filter(["LUNATK", "DRUM SYNTH"]), id: \.self) { name in
                row(name, detail: soundDetail(name), color: name == "LUNATK" ? LYLLTHTheme.indigo : LYLLTHTheme.teal, symbol: soundSymbol(name))
                    .simultaneousGesture(TapGesture().onEnded { onSound(name) })
                    .help(name == "LUNATK" ? "Open LUNATK on the selected synth track" : "Browse DrumKit drum sounds for the selected drum track")
            }
            ForEach(categories, id: \.self) { category in
                let effects = LYNightshapeEffect.all.filter { $0.category == category && matches($0.name) }
                if !effects.isEmpty {
                    section(category)
                    ForEach(effects, id: \.self) { effect in
                        row(effect.name, detail: effect.detail, color: effect.color, symbol: nil)
                            .simultaneousGesture(TapGesture().onEnded { onEffect(effect.name) })
                            .help("Add to the selected channel and open it")
                    }
                }
            }
        case "AU INST":
            pluginRows(plugins.instruments.map(\.name), empty: "NO AUDIO UNIT INSTRUMENTS FOUND")
        case "AU FX":
            pluginRows(plugins.effects.map(\.name), empty: "NO AUDIO UNIT EFFECTS FOUND")
        default:
            let files = filter(projectAudio.sorted())
            if files.isEmpty {
                emptyNote("NO AUDIO IN THIS PROJECT YET\nDRAG A FILE ONTO AN AUDIO TRACK")
            } else {
                section("AUDIO")
                ForEach(files, id: \.self) { name in
                    row(name.uppercased(), detail: nil, color: LYLLTHTheme.purple, symbol: "waveform")
                }
            }
        }
    }

    @ViewBuilder
    private func pluginRows(_ names: [String], empty: String) -> some View {
        let values = filter(names)
        if values.isEmpty {
            emptyNote(plugins.isScanning ? "SCANNING" : empty)
        } else {
            ForEach(values, id: \.self) { name in
                row(name.uppercased(), detail: nil, color: LYLLTHTheme.indigo, symbol: "square.stack.3d.up")
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(LYLLTHTheme.label(7.5, weight: .bold))
            .tracking(2)
            .foregroundStyle(LYLLTHTheme.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(LYLLTHTheme.label(8, weight: .bold))
            .tracking(1.2)
            .lineSpacing(5)
            .foregroundStyle(LYLLTHTheme.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
    }

    private func row(_ name: String, detail: String?, color: Color, symbol: String?) -> some View {
        BrowserRow(
            name: name,
            detail: detail,
            color: color,
            symbol: symbol,
            isSelected: selectedItem == name
        )
        .onTapGesture { selectedItem = name }
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private func filter(_ values: [String]) -> [String] {
        values.filter(matches)
    }

    private func soundDetail(_ name: String) -> String {
        switch name {
        case "LUNATK": return "WAVETABLE SYNTH · OPEN"
        case "DRUM SYNTH": return "\(LYDrumSounds.presets.count) DRUMKIT SOUNDS · OPEN"
        case "SOUND ORACLE": return "DESCRIBE A SOUND"
        default: return "KEY-AWARE CHORD LANES"
        }
    }

    private func soundSymbol(_ name: String) -> String {
        switch name {
        case "LUNATK": return "pianokeys"
        case "DRUM SYNTH": return "waveform.path"
        case "SOUND ORACLE": return "wand.and.stars"
        default: return "pianokeys"
        }
    }
}

private struct BrowserRow: View {
    let name: String
    let detail: String?
    let color: Color
    let symbol: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Rectangle().stroke(color.opacity(isSelected ? 1 : 0.55), lineWidth: 1)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(color)
                } else {
                    Rectangle().fill(color).frame(width: 4, height: 4)
                }
            }
            .frame(width: 20, height: 20)
            .lyBloom(color, isOn: isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(LYLLTHTheme.label(7))
                        .tracking(1)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: detail == nil ? 34 : 42)
        .background(isSelected ? color.opacity(LYLLTHTheme.controlFill) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? color : .clear).frame(width: 2)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Desktop sequencer

private struct LYSelectedSequenceStep: Hashable {
    let trackID: UUID
    let stepIndex: Int
}

private struct LYStepFramePreferenceKey: PreferenceKey {
    static var defaultValue: [LYSelectedSequenceStep: CGRect] = [:]

    static func reduce(
        value: inout [LYSelectedSequenceStep: CGRect],
        nextValue: () -> [LYSelectedSequenceStep: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SequencerWorkspace: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    @Binding var patternIndex: Int
    let currentStep: Int
    let isPlaying: Bool
    @ObservedObject var waveformState: OutputWaveformState
    let syncEngine: () -> Void

    @State private var selectedStep: LYSelectedSequenceStep?
    @State private var stepActionTarget: LYSelectedSequenceStep?
    @State private var stepFrames: [LYSelectedSequenceStep: CGRect] = [:]
    @State private var copiedSteps: [UUID: [Bool]] = [:]
    @State private var copiedLocks: [UUID: [LYStepParameters]] = [:]

    private let trackWidth: CGFloat = 190
    private let gridGap: CGFloat = 8
    private let minimumStepSize: CGFloat = 34
    private let maximumStepSize: CGFloat = 58
    private let sequencerBorderWidth: CGFloat = 1.5
    private let inactiveStepStroke = Color(hex: 0x2A2A30)
    private static let passBlue = Color(hex: 0x7B5CE5)

    private var musicalTrackIndices: [Int] {
        session.tracks.indices.filter {
            session.tracks[$0].kind == .drumkit || session.tracks[$0].kind == .instrument
        }
    }

    private var patternCount: Int {
        max(1, musicalTrackIndices.map { sequencedClipIndices(trackIndex: $0).count }.max() ?? 1)
    }

    private var stepCount: Int {
        let values = musicalTrackIndices.compactMap { trackIndex -> Int? in
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { return nil }
            return session.tracks[trackIndex].clips[clipIndex].steps?.count
        }
        return min(max(values.max() ?? 16, 1), 64)
    }

    private var selectedLocation: (track: Int, clip: Int, step: Int)? {
        guard let selectedStep,
              let track = session.tracks.firstIndex(where: { $0.id == selectedStep.trackID }),
              let clip = activeClipIndex(trackIndex: track),
              selectedStep.stepIndex < stepCount else { return nil }
        return (track, clip, selectedStep.stepIndex)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                sequencerHeader

                LYPatternPlaybackVisualizer(
                    session: session,
                    patternIndex: patternIndex,
                    currentStep: currentStep % max(stepCount, 1),
                    isPlaying: isPlaying,
                    waveformState: waveformState
                )
                .frame(height: 156)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(LYLLTHTheme.background)

                GeometryReader { viewport in
                    let gapWidth = gridGap * CGFloat(max(0, stepCount - 1))
                    let availableLane = viewport.size.width - trackWidth - gridGap - gapWidth
                    let stepSide = min(
                        maximumStepSize,
                        max(minimumStepSize, availableLane / CGFloat(max(stepCount, 1)))
                    )
                    let matrixWidth = trackWidth + gridGap + CGFloat(stepCount) * stepSide + gapWidth
                    let matrixHeight = 28 + CGFloat(musicalTrackIndices.count) * stepSide
                        + CGFloat(max(0, musicalTrackIndices.count - 1)) * gridGap

                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: gridGap) {
                            stepRuler(stepWidth: stepSide)
                            ForEach(musicalTrackIndices, id: \.self) { trackIndex in
                                sequenceRow(trackIndex: trackIndex, stepSide: stepSide)
                            }
                        }
                        .frame(
                            minWidth: max(matrixWidth, viewport.size.width),
                            minHeight: max(matrixHeight, viewport.size.height),
                            alignment: .topLeading
                        )
                    }
                    .lyScrollers()
                    .defaultScrollAnchor(.topLeading)
                    .background(LYDrumKitSequencerBackdrop())
                }

                stepInspector
                    .frame(height: selectedLocation == nil ? 42 : 174)
                    .animation(.easeOut(duration: 0.14), value: selectedStep)
            }

            if let stepActionTarget {
                LYNightshapeMenuOverlay(dismiss: dismissStepActions) {
                    stepActionPanel(stepActionTarget)
                }
            }
        }
        .coordinateSpace(name: "LYSequencerWorkspace")
        .onPreferenceChange(LYStepFramePreferenceKey.self) { stepFrames = $0 }
        .background(LYDrumKitSequencerBackdrop())
        .background(
            LYSecondaryClickMonitor { point in
                guard let target = stepFrames.first(where: { $0.value.contains(point) })?.key else {
                    return false
                }
                withAnimation(.easeOut(duration: 0.14)) { stepActionTarget = target }
                return true
            }
        )
        .onAppear {
            patternIndex = min(patternIndex, patternCount - 1)
            syncEngine()
        }
    }

    private var sequencerHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SEQUENCER")
                    .font(LYLLTHTheme.label(11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.secondary)
                mixedNumericLabel(
                    "PATTERN \(String(format: "%02d", patternIndex + 1))  ·  \(stepCount) STEPS  ·  \((session.songKey ?? .default).name)",
                    labelFont: LYLLTHTheme.label(8),
                    numberFont: LYLLTHTheme.value(8)
                )
                .tracking(1)
                .foregroundStyle(LYLLTHTheme.dim)
            }

            HStack(spacing: 3) {
                ForEach(0..<patternCount, id: \.self) { index in
                    Button("\(index + 1)") { selectPattern(index) }
                        .buttonStyle(LYChromeButtonStyle(active: patternIndex == index, compact: true, numeric: true))
                }
            }

            HStack(spacing: 3) {
                patternAction("plus", "NEW", help: "A new empty pattern on every track", action: { addPattern(copying: false) })
                patternAction("plus.square.on.square", "DUPLICATE", help: "A new pattern that starts as a copy of this one", action: { addPattern(copying: true) })
                patternAction("text.insert", "PLACE IN SONG", help: "Put this pattern at the end of the song, on every track", action: placeInSong)
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                ForEach([16, 32, 48, 64], id: \.self) { count in
                    Button("\(count)") { resizePattern(to: count) }
                        .buttonStyle(LYChromeButtonStyle(active: stepCount == count, compact: true, numeric: true))
                }
            }

            HStack(spacing: 3) {
                sequenceTool("COPY", action: copyPattern)
                sequenceTool("PASTE", enabled: !copiedSteps.isEmpty, action: pastePattern)
                sequenceTool("RANDOM", action: randomizePattern)
                sequenceTool("CLEAR", tint: LYLLTHTheme.purple, action: clearPattern)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func patternAction(_ icon: String, _ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title)
            }
        }
        .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.teal, compact: true))
        .help(help)
    }

    private func sequenceTool(_ title: String, enabled: Bool = true, tint: Color = LYLLTHTheme.metadata, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(LYChromeButtonStyle(tint: tint, compact: true))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.34)
    }

    private func stepRuler(stepWidth: CGFloat) -> some View {
        HStack(spacing: gridGap) {
            HStack {
                Text("TRACKS")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.4)
                Spacer()
                Text("M")
                Text("S")
            }
            .font(LYLLTHTheme.label(7, weight: .bold))
            .foregroundStyle(LYLLTHTheme.dim)
            .padding(.horizontal, 12)
            .frame(width: trackWidth, height: 28)
            .background(LYLLTHTheme.background.opacity(0.92))

            HStack(spacing: gridGap) {
                ForEach(0..<stepCount, id: \.self) { step in
                    Text("\(step + 1)")
                        .font(LYLLTHTheme.value(7.5))
                        .foregroundStyle(step % 4 == 0 ? LYLLTHTheme.secondary : LYLLTHTheme.dim)
                        .frame(width: stepWidth, height: 28, alignment: .center)
                }
            }
        }
    }

    private func sequenceRow(trackIndex: Int, stepSide: CGFloat) -> some View {
        let track = session.tracks[trackIndex]
        let accent = LYLLTHTheme.trackAccent(position: musicalTrackIndices.firstIndex(of: trackIndex) ?? 0)
        let clipIndex = activeClipIndex(trackIndex: trackIndex)
        let steps = clipIndex.flatMap { session.tracks[trackIndex].clips[$0].steps } ?? []
        let locks = clipIndex.flatMap { session.tracks[trackIndex].clips[$0].stepParameters } ?? []

        return HStack(spacing: gridGap) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", (musicalTrackIndices.firstIndex(of: trackIndex) ?? 0) + 1))
                    .font(LYLLTHTheme.value(10))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .overlay(Rectangle().stroke(accent.opacity(selectedTrackID == track.id ? 1 : 0.6), lineWidth: 1))
                    .lyBloom(accent, isOn: selectedTrackID == track.id)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(LYLLTHTheme.label(10, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    Text(track.isChordTrack == true ? "CHORD TRACK" : track.kind.label)
                        .font(LYLLTHTheme.label(7, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                Spacer(minLength: 3)
                LYTrackToggle(
                    title: "M",
                    isOn: trackStateBinding(trackIndex: trackIndex, keyPath: \.isMuted),
                    tint: LYLLTHTheme.purple
                )
                LYTrackToggle(
                    title: "S",
                    isOn: trackStateBinding(trackIndex: trackIndex, keyPath: \.isSolo),
                    tint: LYLLTHTheme.teal
                )
                LYTrackToggle(
                    title: "R",
                    isOn: trackStateBinding(trackIndex: trackIndex, keyPath: \.isArmed),
                    tint: LYLLTHTheme.record
                )
            }
            .padding(.horizontal, 10)
            .frame(width: trackWidth, height: stepSide)
            .background(LYDrumKitGlassSurface())
            .lyRisingBloom(accent, isOn: selectedTrackID == track.id, strength: 0.8)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(selectedTrackID == track.id ? accent : accent.opacity(0.55), lineWidth: sequencerBorderWidth)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedTrackID = track.id }

            HStack(spacing: gridGap) {
                ForEach(0..<stepCount, id: \.self) { step in
                    let storedOn = steps.indices.contains(step) && steps[step]
                    let isSelected = selectedStep == LYSelectedSequenceStep(trackID: track.id, stepIndex: step)
                    let chord = locks.indices.contains(step) ? locks[step].chord : nil
                    let isOn = storedOn || chord != nil
                    let delta = isPlaying
                        ? (currentStep - step + stepCount) % stepCount
                        : stepCount
                    let isActivelyFiring = isPlaying && isOn && delta == 0

                    Button { toggleStep(trackIndex: trackIndex, step: step) } label: {
                        ZStack(alignment: .bottom) {
                            LYDrumKitGlassSurface()
                            Rectangle().fill(drumKitCellFill(delta: delta, isEnabled: isOn, color: accent))

                            if storedOn, !isActivelyFiring, locks.indices.contains(step) {
                                Rectangle()
                                    .fill(LYLLTHTheme.indigo.opacity(0.30))
                                    .frame(height: max(2, stepSide * CGFloat(locks[step].velocity)))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                            if let chord, chord >= 0 {
                                Text((session.songKey ?? .default).chord(chord).name)
                                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                                    .foregroundStyle(LYLLTHTheme.text)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: stepSide, height: stepSide)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? LYLLTHTheme.chrome
                                        : drumKitCellStroke(delta: delta, isEnabled: isOn, color: accent),
                                    lineWidth: sequencerBorderWidth
                                )
                        }
                        .overlay {
                            if !isOn {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.035)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .background {
                        GeometryReader { proxy in
                            let target = LYSelectedSequenceStep(trackID: track.id, stepIndex: step)
                            Color.clear.preference(
                                key: LYStepFramePreferenceKey.self,
                                value: [target: proxy.frame(in: .named("LYSequencerWorkspace"))]
                            )
                        }
                    }
                    .help("Click to toggle. Right-click for NIGHTSHAPE step actions.")
                }
            }
        }
    }

    private func dismissStepActions() {
        withAnimation(.easeOut(duration: 0.14)) { stepActionTarget = nil }
    }

    private func stepActionPanel(_ target: LYSelectedSequenceStep) -> some View {
        let trackIndex = session.tracks.firstIndex { $0.id == target.trackID }
        let trackName = trackIndex.map { session.tracks[$0].name } ?? "TRACK"

        return VStack(spacing: 0) {
            LYNightshapeMenuHeader(
                eyebrow: "SEQUENCER",
                title: "STEP ACTIONS",
                accent: LYLLTHTheme.indigo,
                close: dismissStepActions
            )
            mixedNumericLabel(
                "\(trackName)  ·  STEP \(target.stepIndex + 1)",
                labelFont: LYLLTHTheme.label(8),
                numberFont: LYLLTHTheme.value(8)
            )
            .tracking(1)
            .foregroundStyle(LYLLTHTheme.dim)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 13)

            LYNightshapeMenuDivider()

            VStack(spacing: 8) {
                LYNightshapeMenuRow(
                    icon: "slider.horizontal.3",
                    title: "SELECT STEP",
                    detail: "OPEN VELOCITY, PITCH, GATE + FX",
                    accent: LYLLTHTheme.indigo,
                    action: {
                        guard let trackIndex else { return }
                        selectStep(trackIndex: trackIndex, step: target.stepIndex)
                        dismissStepActions()
                    }
                )
                LYNightshapeMenuRow(
                    icon: "eraser",
                    title: "CLEAR STEP",
                    detail: "REMOVE NOTE, CHORD + PARAMETER LOCKS",
                    accent: LYLLTHTheme.purple,
                    action: {
                        guard let trackIndex else { return }
                        clearStep(trackIndex: trackIndex, step: target.stepIndex)
                        dismissStepActions()
                    }
                )
            }
            .padding(14)
        }
        .frame(width: 326)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.indigo)
    }

    private func drumKitCellFill(delta: Int, isEnabled: Bool, color: Color) -> Color {
        guard isEnabled else { return .clear }
        switch delta {
        case 0: return color
        case 1: return color.opacity(0.42)
        case 2: return color.opacity(0.18)
        default: return .clear
        }
    }

    private func drumKitCellStroke(delta: Int, isEnabled: Bool, color: Color) -> Color {
        if isEnabled { return color }
        switch delta {
        case 0: return Self.passBlue.opacity(0.22)
        case 1: return Self.passBlue.opacity(0.13)
        case 2: return Self.passBlue.opacity(0.07)
        default: return inactiveStepStroke
        }
    }

    @ViewBuilder
    private var stepInspector: some View {
        if let location = selectedLocation {
            let track = session.tracks[location.track]
            let clip = session.tracks[location.track].clips[location.clip]
            let parameters = parameterValue(track: location.track, clip: location.clip, step: location.step)

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Rectangle().fill(LYLLTHTheme.accent(track.accent)).frame(width: 16, height: 1)
                    Text("STEP \(location.step + 1)")
                        .font(LYLLTHTheme.label(9, weight: .bold))
                        .tracking(1.4)
                    Text("\(track.name)  ·  \(clip.name)")
                        .font(LYLLTHTheme.label(8))
                        .foregroundStyle(LYLLTHTheme.dim)
                    Spacer()
                    Button("CLOSE") { selectedStep = nil }
                        .buttonStyle(LYChromeButtonStyle(compact: true))
                }
                .padding(.horizontal, 13)
                .frame(height: 38)
                .foregroundStyle(LYLLTHTheme.secondary)
                .overlay(alignment: .bottom) { LYHairline() }

                HStack(alignment: .top, spacing: 22) {
                    inspectorKnob("VELOCITY", value: parameterBinding(location, \.velocity), range: 0...1, text: "\(Int(parameters.velocity * 127))", tint: .teal)
                    inspectorKnob("LEVEL", value: parameterBinding(location, \.level), range: 0...1, text: "\(Int(parameters.level * 100))%", tint: .teal)
                    inspectorKnob("PITCH", value: parameterBinding(location, \.pitch), range: -24...24, text: String(format: "%+.0f", parameters.pitch), tint: .indigo)
                    inspectorKnob("GATE", value: parameterBinding(location, \.noteLength), range: 1...64, text: "\(Int(parameters.noteLength.rounded()))", tint: .indigo)
                    inspectorKnob("CUTOFF", value: parameterBinding(location, \.cutoff), range: 0...1, text: "\(Int(parameters.cutoff * 100))%", tint: .purple)
                    inspectorKnob("RESONANCE", value: parameterBinding(location, \.resonance), range: 0...1, text: "\(Int(parameters.resonance * 100))%", tint: .purple)
                    inspectorKnob("PAN", value: parameterBinding(location, \.pan), range: -1...1, text: panText(parameters.pan), tint: .teal)
                    inspectorKnob("FX", value: parameterBinding(location, \.effect), range: 0...1, text: "\(Int(parameters.effect * 100))%", tint: .purple)

                    if track.isChordTrack == true {
                        chordChoices(location)
                            .padding(.leading, 8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .background(LYLLTHTheme.panel)
            .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1) }
        } else {
            HStack(spacing: 8) {
                Rectangle().fill(LYLLTHTheme.teal).frame(width: 16, height: 1)
                Text("SELECT A STEP TO EDIT VELOCITY, LEVEL, PITCH, GATE, FILTER, PAN, FX OR CHORD")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
            }
            .padding(.horizontal, 13)
            .background(LYLLTHTheme.panel)
            .overlay(alignment: .top) { LYHairline() }
        }
    }

    private func inspectorKnob(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String, tint: LYAccent) -> some View {
        LYKnob(value: value, range: range, title: title, valueText: text, tint: LYLLTHTheme.accent(tint))
    }

    private func chordChoices(_ location: (track: Int, clip: Int, step: Int)) -> some View {
        let key = session.songKey ?? .default
        let current = parameterValue(track: location.track, clip: location.clip, step: location.step).chord
        return VStack(alignment: .leading, spacing: 5) {
            Text("CHORD")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.dim)
            HStack(spacing: 3) {
                ForEach(0..<SongKey.chordChoiceCount, id: \.self) { choice in
                    Button(key.chord(choice).name) { setChord(location, choice: choice) }
                        .buttonStyle(LYChromeButtonStyle(active: current == choice, compact: true))
                }
                Button("STOP") { setChord(location, choice: ChordLaneCompiler.rest) }
                    .buttonStyle(LYChromeButtonStyle(active: current == ChordLaneCompiler.rest, tint: LYLLTHTheme.purple, compact: true))
                Button("HOLD") { setChord(location, choice: nil) }
                    .buttonStyle(LYChromeButtonStyle(active: current == nil, tint: LYLLTHTheme.indigo, compact: true))
            }
        }
    }

    private func sequencedClipIndices(trackIndex: Int) -> [Int] {
        session.tracks[trackIndex].patternIndices
    }

    private func activeClipIndex(trackIndex: Int) -> Int? {
        let values = sequencedClipIndices(trackIndex: trackIndex)
        guard !values.isEmpty else { return nil }
        return values[min(patternIndex, values.count - 1)]
    }

    private func selectPattern(_ index: Int) {
        patternIndex = min(max(index, 0), patternCount - 1)
        selectedStep = nil
        syncEngine()
    }

    /// A new pattern on every sequenced track, empty or copied from the one
    /// being edited. It is not in the song until PLACE IN SONG.
    private func addPattern(copying: Bool) {
        let newIndex = patternCount
        let count = stepCount
        for trackIndex in musicalTrackIndices {
            let track = session.tracks[trackIndex]
            let kind: LYClip.Kind = track.kind == .drumkit ? .pattern : .midi
            let prefix = track.isChordTrack == true ? "CHORD BED" : "PATTERN"
            let source = copying ? activeClipIndex(trackIndex: trackIndex).map { track.clips[$0] } : nil
            var clip = LYClip(
                name: "\(prefix) \(String(format: "%02d", newIndex + 1))",
                kind: kind,
                startBeat: 0,
                lengthBeats: Double(max(count / 4, 1)),
                steps: source?.steps ?? Array(repeating: false, count: count),
                stepParameters: source?.stepParameters ?? Array(repeating: .default, count: count)
            )
            clip.isOffTimeline = true
            // A track with fewer patterns gets empty ones up to this index, so
            // pattern numbers line up across tracks.
            while session.tracks[trackIndex].patternIndices.count < newIndex {
                var filler = clip
                filler.id = UUID()
                filler.steps = Array(repeating: false, count: count)
                filler.stepParameters = Array(repeating: .default, count: count)
                session.tracks[trackIndex].clips.append(filler)
            }
            session.tracks[trackIndex].clips.append(clip)
        }
        patternIndex = newIndex
        syncEngine()
    }

    /// Places the pattern being edited at the end of the song on every track.
    private func placeInSong() {
        let beatsPerBar = max(1, Double(session.numerator) * 4 / Double(max(session.denominator, 1)))
        let end = session.tracks.flatMap(\.clips).filter(\.isInSong).map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let at = ceil(end / beatsPerBar - 0.000_1) * beatsPerBar
        for trackIndex in musicalTrackIndices {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            let pattern = session.tracks[trackIndex].clips[clipIndex]
            if pattern.isOffTimeline == true,
               !session.tracks[trackIndex].clips.contains(where: { $0.patternSourceID == pattern.id }) {
                // First use: the pattern itself goes into the song.
                session.tracks[trackIndex].clips[clipIndex].isOffTimeline = nil
                session.tracks[trackIndex].clips[clipIndex].startBeat = at
            } else {
                var placement = pattern
                placement.id = UUID()
                placement.patternSourceID = pattern.id
                placement.steps = nil
                placement.stepParameters = nil
                placement.isOffTimeline = nil
                placement.startBeat = at
                placement.loopOffsetBeats = 0
                session.tracks[trackIndex].clips.append(placement)
            }
        }
        syncEngine()
    }

    private func resizePattern(to count: Int) {
        let normalized = min(max(count, 1), 64)
        for trackIndex in musicalTrackIndices {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            let isChordTrack = session.tracks[trackIndex].isChordTrack == true
            session.tracks[trackIndex].clips[clipIndex].resizeSequencer(
                to: normalized,
                isChordTrack: isChordTrack
            )
        }
        if let selectedStep, selectedStep.stepIndex >= normalized { self.selectedStep = nil }
        syncEngine()
    }

    private func selectStep(trackIndex: Int, step: Int) {
        let track = session.tracks[trackIndex]
        selectedTrackID = track.id
        selectedStep = LYSelectedSequenceStep(trackID: track.id, stepIndex: step)
        ensureStorage(trackIndex: trackIndex, stepCount: stepCount)
    }

    private func toggleStep(trackIndex: Int, step: Int) {
        guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { return }
        ensureStorage(trackIndex: trackIndex, stepCount: stepCount)
        selectStep(trackIndex: trackIndex, step: step)

        if session.tracks[trackIndex].isChordTrack == true {
            var locks = session.tracks[trackIndex].clips[clipIndex].stepParameters ?? []
            locks[step].chord = locks[step].chord == nil ? 0 : nil
            session.tracks[trackIndex].clips[clipIndex].stepParameters = locks
        } else {
            var steps = session.tracks[trackIndex].clips[clipIndex].steps ?? []
            steps[step].toggle()
            session.tracks[trackIndex].clips[clipIndex].steps = steps
        }
        syncEngine()
    }

    private func clearStep(trackIndex: Int, step: Int) {
        guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { return }
        ensureStorage(trackIndex: trackIndex, stepCount: stepCount)
        var steps = session.tracks[trackIndex].clips[clipIndex].steps ?? []
        var locks = session.tracks[trackIndex].clips[clipIndex].stepParameters ?? []
        steps[step] = false
        locks[step] = .default
        session.tracks[trackIndex].clips[clipIndex].steps = steps
        session.tracks[trackIndex].clips[clipIndex].stepParameters = locks
        syncEngine()
    }

    private func ensureStorage(trackIndex: Int, stepCount: Int) {
        guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { return }
        session.tracks[trackIndex].clips[clipIndex].resizeSequencer(
            to: stepCount,
            isChordTrack: session.tracks[trackIndex].isChordTrack == true
        )
    }

    private func trackStateBinding(trackIndex: Int, keyPath: WritableKeyPath<LYTrack, Bool>) -> Binding<Bool> {
        Binding(
            get: { session.tracks[trackIndex][keyPath: keyPath] },
            set: { value in
                session.tracks[trackIndex][keyPath: keyPath] = value
                syncEngine()
            }
        )
    }

    private func parameterValue(track: Int, clip: Int, step: Int) -> LYStepParameters {
        let values = session.tracks[track].clips[clip].stepParameters ?? []
        return values.indices.contains(step) ? values[step] : .default
    }

    private func parameterBinding(
        _ location: (track: Int, clip: Int, step: Int),
        _ keyPath: WritableKeyPath<LYStepParameters, Double>
    ) -> Binding<Double> {
        Binding(
            get: { parameterValue(track: location.track, clip: location.clip, step: location.step)[keyPath: keyPath] },
            set: { value in
                ensureStorage(trackIndex: location.track, stepCount: stepCount)
                var locks = session.tracks[location.track].clips[location.clip].stepParameters ?? []
                locks[location.step][keyPath: keyPath] = value
                session.tracks[location.track].clips[location.clip].stepParameters = locks
                syncEngine()
            }
        )
    }

    private func setChord(_ location: (track: Int, clip: Int, step: Int), choice: Int?) {
        ensureStorage(trackIndex: location.track, stepCount: stepCount)
        var locks = session.tracks[location.track].clips[location.clip].stepParameters ?? []
        locks[location.step].chord = choice
        session.tracks[location.track].clips[location.clip].stepParameters = locks
        syncEngine()
    }

    private func copyPattern() {
        copiedSteps = [:]
        copiedLocks = [:]
        for trackIndex in musicalTrackIndices {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            let trackID = session.tracks[trackIndex].id
            copiedSteps[trackID] = session.tracks[trackIndex].clips[clipIndex].steps ?? []
            copiedLocks[trackID] = session.tracks[trackIndex].clips[clipIndex].stepParameters ?? []
        }
    }

    private func pastePattern() {
        guard !copiedSteps.isEmpty else { return }
        for trackIndex in musicalTrackIndices {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            let trackID = session.tracks[trackIndex].id
            if let values = copiedSteps[trackID] { session.tracks[trackIndex].clips[clipIndex].steps = values }
            if let values = copiedLocks[trackID] { session.tracks[trackIndex].clips[clipIndex].stepParameters = values }
        }
        syncEngine()
    }

    private func clearPattern() {
        for trackIndex in musicalTrackIndices {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            session.tracks[trackIndex].clips[clipIndex].steps = Array(repeating: false, count: stepCount)
            session.tracks[trackIndex].clips[clipIndex].stepParameters = Array(repeating: .default, count: stepCount)
        }
        syncEngine()
    }

    private func randomizePattern() {
        for (row, trackIndex) in musicalTrackIndices.enumerated() {
            guard let clipIndex = activeClipIndex(trackIndex: trackIndex) else { continue }
            var steps = Array(repeating: false, count: stepCount)
            var locks = Array(repeating: LYStepParameters.default, count: stepCount)
            if session.tracks[trackIndex].isChordTrack == true {
                let progression = session.songKey?.isMinor == false ? [0, 4, 5, 3] : [0, 5, 2, 6]
                for (index, choice) in progression.enumerated() {
                    let position = index * max(1, stepCount / progression.count)
                    if locks.indices.contains(position) { locks[position].chord = choice }
                }
            } else {
                for step in steps.indices {
                    let anchor = row == 0 ? step % 4 == 0 : step % 4 == 2
                    let ghost = Double.random(in: 0...1) < (row == 0 ? 0.08 : 0.16)
                    steps[step] = anchor || ghost
                    locks[step].velocity = anchor ? 0.92 : Double.random(in: 0.42...0.7)
                }
            }
            session.tracks[trackIndex].clips[clipIndex].steps = steps
            session.tracks[trackIndex].clips[clipIndex].stepParameters = locks
        }
        syncEngine()
    }

    private func panText(_ value: Double) -> String {
        if abs(value) < 0.01 { return "C" }
        return value < 0 ? "L\(Int(abs(value) * 100))" : "R\(Int(abs(value) * 100))"
    }
}

private struct ArrangementSnapPanel: View {
    @Binding var editor: LYArrangementEditorState
    let close: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(
                eyebrow: "ARRANGEMENT",
                title: "SNAP",
                accent: LYLLTHTheme.indigo,
                close: close
            )

            Text("GRID RESOLUTION FOLLOWS THE EDITOR, NOT THE OPERATING SYSTEM")
                .font(LYLLTHTheme.label(8))
                .tracking(0.9)
                .foregroundStyle(LYLLTHTheme.dim)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 13)

            LYNightshapeMenuDivider()

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(LYArrangementSnapMode.allCases) { mode in
                    snapModeButton(mode)
                }
            }
            .padding(14)

            LYNightshapeMenuDivider()

            VStack(spacing: 9) {
                HStack(spacing: 7) {
                    ForEach(LYSnapAlignment.allCases, id: \.self) { alignment in
                        Button {
                            var value = editor
                            value.snapAlignment = alignment
                            editor = value
                        } label: {
                            Text(alignment.label)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LYChromeButtonStyle(
                            active: editor.snapAlignment == alignment,
                            tint: LYLLTHTheme.indigo,
                            compact: true
                        ))
                    }
                }

                LYNightshapeMenuRow(
                    icon: editor.showsGrid ? "grid" : "grid.slash",
                    title: editor.showsGrid ? "GRID VISIBLE" : "GRID HIDDEN",
                    detail: "TOGGLE ARRANGEMENT GUIDE LINES",
                    accent: LYLLTHTheme.teal,
                    isSelected: editor.showsGrid,
                    action: {
                        var value = editor
                        value.showsGrid.toggle()
                        editor = value
                    }
                )
            }
            .padding(14)
        }
        .frame(width: 390)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.indigo)
    }

    private func snapModeButton(_ mode: LYArrangementSnapMode) -> some View {
        let isSelected = editor.snapMode == mode
        return Button {
            var value = editor
            value.snapMode = mode
            editor = value
        } label: {
            HStack(spacing: 7) {
                LYLED(color: LYLLTHTheme.teal, isOn: isSelected, size: 4)
                mixedNumericLabel(
                    mode.label,
                    labelFont: LYLLTHTheme.label(8.5, weight: .bold),
                    numberFont: LYLLTHTheme.value(8.5)
                )
                .tracking(0.7)
                .foregroundStyle(isSelected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? LYLLTHTheme.teal.opacity(0.08) : LYLLTHTheme.panelRaised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(isSelected ? LYLLTHTheme.teal : Color.clear).frame(height: 1)
            }
            .overlay { Rectangle().stroke(isSelected ? LYLLTHTheme.teal.opacity(0.72) : LYLLTHTheme.lineStrong, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mixer

private struct MixerView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    @ObservedObject var meters: LYMeterStore
    let isMainSelected: Bool
    let selectMain: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "MIX", detail: "LEVEL  ·  PAN  ·  METERS", actionIcon: "chevron.down", action: close)
            ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(session.tracks.indices), id: \.self) { index in
                            MixerChannel(
                                track: $session.tracks[index],
                                number: index + 1,
                                accent: LYLLTHTheme.trackAccent(position: index),
                                reading: meters.reading(for: session.tracks[index].id),
                                resetClip: { meters.reset(session.tracks[index].id) },
                                isSelected: !isMainSelected && selectedTrackID == session.tracks[index].id
                            )
                            .onTapGesture { selectedTrackID = session.tracks[index].id }
                        }
                        MainChannel(
                            reading: meters.reading(for: LYMeterStore.mainKey),
                            resetClip: { meters.reset(LYMeterStore.mainKey) },
                            isSelected: isMainSelected
                        )
                        .onTapGesture(perform: selectMain)
                    }
            }
            .lyScrollers()
            .background(LYLLTHTheme.deck)
        }
        .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1) }
    }


}

private struct MixerChannel: View {
    @Binding var track: LYTrack
    let number: Int
    let accent: Color
    let reading: LYMeterStore.Reading?
    let resetClip: () -> Void
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(String(format: "%02d", number))
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
                    .overlay(Rectangle().stroke(accent.opacity(isSelected ? 1 : 0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(LYLLTHTheme.label(9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    Text(track.kind.label)
                        .font(LYLLTHTheme.label(6.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 4) {
                    LYClipIndicator(reading: reading, reset: resetClip)
                        .frame(width: 34)
                    LYStripMeter(reading: reading, tint: accent)
                        .frame(width: 8)
                }
                .frame(width: 34)
                LYVerticalFader(value: $track.volumeDB, range: -48...6, accent: accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    LYTrackToggle(title: "M", isOn: $track.isMuted, tint: LYLLTHTheme.purple)
                    LYTrackToggle(title: "S", isOn: $track.isSolo, tint: LYLLTHTheme.teal)
                    if track.kind != .auxiliary {
                        LYTrackToggle(title: "R", isOn: $track.isArmed, tint: LYLLTHTheme.record)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text(track.volumeDB <= -47.9 ? "−∞" : String(format: "%+.1f", track.volumeDB))
                .font(LYLLTHTheme.value(11))
                .foregroundStyle(LYLLTHTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 124)
        .background(isSelected ? LYLLTHTheme.panel : Color.clear)
        .lyRisingBloom(accent, isOn: isSelected, strength: 0.7)
        .overlay(alignment: .top) {
            Rectangle().fill(isSelected ? accent : .clear).frame(height: 2).lyBloom(accent, isOn: isSelected)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.line).frame(width: 1) }
        .contentShape(Rectangle())
    }
}

private struct MainChannel: View {
    let reading: LYMeterStore.Reading?
    let resetClip: () -> Void
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MAIN")
                    .font(LYLLTHTheme.label(10.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(LYLLTHTheme.text)
                Text("ELASTIC LIMITER")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            LYClipIndicator(reading: reading, reset: resetClip)
                .frame(width: 60)
            LYStripMeter(reading: reading, tint: LYLLTHTheme.teal)
                .frame(width: 16)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 118, alignment: .leading)
        .background(isSelected ? LYLLTHTheme.panel : LYLLTHTheme.background)
        .lyRisingBloom(LYLLTHTheme.teal, isOn: isSelected, strength: 0.6)
        .contentShape(Rectangle())
        .help("MAIN: click to open its effects in the inspector")
        .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.teal.opacity(0.7)).frame(width: 1) }
    }
}


/// A fader drawn like DrumKit's: hairline rail, the level filled in the
/// track colour, a chrome cap with a single accent line.
private struct LYVerticalFader: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accent = LYLLTHTheme.teal
    @State private var origin: Double?

    var body: some View {
        GeometryReader { geometry in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let travel = geometry.size.height - 12
            let y = (1 - fraction) * travel + 6
            let zeroY = (1 - (0 - range.lowerBound) / (range.upperBound - range.lowerBound)) * travel + 6

            ZStack(alignment: .top) {
                Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1)
                Rectangle()
                    .fill(accent.opacity(0.7))
                    .frame(width: 1, height: max(0, geometry.size.height - y))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(LYLLTHTheme.dim).frame(width: 9, height: 1).offset(y: zeroY)
                ZStack {
                    Rectangle().fill(LYLLTHTheme.chrome)
                    Rectangle().fill(accent).frame(height: 1.5)
                }
                .frame(width: 22, height: 9)
                .offset(y: y - 4.5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        let start = origin ?? value
                        if origin == nil { origin = value }
                        let span = range.upperBound - range.lowerBound
                        let scale = NSEvent.modifierFlags.contains(.option) ? 0.2 : 1.0
                        value = min(max(start - Double(gesture.translation.height / max(travel, 1)) * span * scale, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in origin = nil }
            )
            .onTapGesture(count: 2) { value = 0 }
            .help("Drag for level. Option for fine. Double-click for 0 dB.")
        }
    }
}

// MARK: - Inspector




private struct LYKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    let valueText: String
    let tint: Color
    @State private var dragOrigin: Double?

    var body: some View {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let angle = Angle.degrees(-135 + fraction * 270)

        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1)
                Circle()
                    .trim(from: 0.125, to: 0.125 + 0.75 * fraction)
                    .stroke(tint.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(90))
                Rectangle()
                    .fill(LYLLTHTheme.chrome)
                    .frame(width: 1, height: 14)
                    .offset(y: -13)
                    .rotationEffect(angle)
                Circle().fill(LYLLTHTheme.deck).frame(width: 35, height: 35)
                Circle().stroke(LYLLTHTheme.lineFocused, lineWidth: 1).frame(width: 35, height: 35)
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let origin = dragOrigin ?? value
                        if dragOrigin == nil { dragOrigin = value }
                        let span = range.upperBound - range.lowerBound
                        value = min(max(origin - gesture.translation.height / 120 * span, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragOrigin = nil }
            )

            Text(title)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(LYLLTHTheme.metadata)
            Text(valueText)
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.text)
        }
    }
}




// MARK: - Status

private struct StatusBar: View {
    let error: String?
    let sampleRate: Double
    let bitDepth: Int
    let hiddenInspector: Bool

    var body: some View {
        HStack(spacing: 9) {
            LYLED(color: error == nil ? LYLLTHTheme.teal : LYLLTHTheme.purple, size: 4)
            Text(error ?? "AUDIO ENGINE ONLINE")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(error == nil ? LYLLTHTheme.metadata : LYLLTHTheme.purple)
                .lineLimit(1)
            if hiddenInspector {
                Text("INSPECTOR HIDDEN AT THIS WINDOW SIZE")
                    .font(LYLLTHTheme.label(7))
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            mixedNumericLabel(
                "\(Int(sampleRate / 1000)) KHZ  ·  \(bitDepth)-BIT",
                labelFont: LYLLTHTheme.label(7),
                numberFont: LYLLTHTheme.value(8)
            )
                .tracking(0.8)
                .foregroundStyle(LYLLTHTheme.dim)
            Text("MACOS / NATIVE")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LYLLTHTheme.dim)
        }
        .padding(.horizontal, 11)
        .frame(height: 25)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .top) { LYHairline() }
    }
}

/// NIGHTSHAPE tie-dye, ported from DRUMKIT's `DrumkitWordmarkTieDye` so both
/// wordmarks carry the identical treatment.
private struct LYWordmarkTieDye: View {
    private static let spots: [(CGFloat, CGFloat, Color)] = [
        (0.06, 0.40, LYLLTHTheme.teal),
        (0.28, 0.85, LYLLTHTheme.purple),
        (0.48, 0.12, LYLLTHTheme.indigo),
        (0.70, 0.68, LYLLTHTheme.teal),
        (0.90, 0.28, LYLLTHTheme.purple),
    ]

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.6
            ZStack {
                LYLLTHTheme.indigo
                ForEach(0..<Self.spots.count, id: \.self) { i in
                    let s = Self.spots[i]
                    RadialGradient(
                        gradient: Gradient(colors: [s.2, s.2.opacity(0)]),
                        center: UnitPoint(x: s.0, y: s.1),
                        startRadius: 0,
                        endRadius: r
                    )
                }
            }
            .drawingGroup()
        }
    }
}


/// MIDI IN light: lit while notes arrive, with how many devices are seen.
private struct LYMIDIIndicator: View {
    @ObservedObject var midi: LYMIDIInput
    @State private var lit = false

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(lit ? LYLLTHTheme.teal : LYLLTHTheme.off)
                .frame(width: 6, height: 6)
            Text(midi.sourceNames.isEmpty ? "NO MIDI" : "MIDI · \(midi.sourceNames.count)")
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.dim)
        }
        .help(midi.sourceNames.isEmpty ? "No MIDI devices connected" : "MIDI in: " + midi.sourceNames.joined(separator: ", ") + ". Plays the selected synth track.")
        .onChange(of: midi.activity) { _, _ in
            lit = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { lit = false }
        }
    }
}

/// Progress for a bounce, then where the file went.
private struct LYBounceOverlay: View {
    @ObservedObject var bounce: LYBounce
    let cancel: () -> Void

    var body: some View {
        switch bounce.phase {
        case .idle:
            EmptyView()
        case .running(let elapsed, let total):
            panel {
                Text("EXPORTING").font(LYLLTHTheme.label(11, weight: .bold)).tracking(2).foregroundStyle(LYLLTHTheme.teal)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 2)
                        Rectangle().fill(LYLLTHTheme.teal).frame(width: geo.size.width * CGFloat(elapsed / max(total, 0.001)), height: 2)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 10)
                Text(String(format: "%02d:%02d / %02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60, Int(total) / 60, Int(total) % 60))
                    .font(LYLLTHTheme.value(14)).foregroundStyle(LYLLTHTheme.text)
                Text("RECORDING THE MAIN MIX IN REAL TIME, SO IT SOUNDS EXACTLY AS IT PLAYS")
                    .font(LYLLTHTheme.label(7, weight: .bold)).tracking(0.9).foregroundStyle(LYLLTHTheme.dim)
                Button("CANCEL", action: cancel).buttonStyle(LYChromeButtonStyle(compact: true))
            }
        case .finished(let url):
            panel {
                Text("EXPORTED").font(LYLLTHTheme.label(11, weight: .bold)).tracking(2).foregroundStyle(LYLLTHTheme.teal)
                Text(url.lastPathComponent.uppercased()).font(LYLLTHTheme.label(10, weight: .bold)).foregroundStyle(LYLLTHTheme.text)
                HStack {
                    Button("SHOW IN FINDER") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(LYChromeButtonStyle(compact: true))
                    Button("DONE") { bounce.dismiss() }.buttonStyle(LYChromeButtonStyle(active: true, compact: true))
                }
            }
        case .failed(let message):
            panel {
                Text("EXPORT FAILED").font(LYLLTHTheme.label(11, weight: .bold)).tracking(2).foregroundStyle(LYLLTHTheme.record)
                Text(message).font(LYLLTHTheme.label(8, weight: .bold)).foregroundStyle(LYLLTHTheme.text)
                Button("DONE") { bounce.dismiss() }.buttonStyle(LYChromeButtonStyle(compact: true))
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(20)
                .frame(width: 440)
                .background(Color(hex: 0x07080D))
                .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
        }
    }
}


/// Runs the latest scheduled work once, on the next main-queue turn. Held in
/// @State as a plain reference so scheduling never re-renders the workspace.
final class LYCoalescedSync {
    private var pending: (() -> Void)?

    func schedule(_ work: @escaping () -> Void) {
        let isFirst = pending == nil
        pending = work
        guard isFirst else { return }
        DispatchQueue.main.async { [weak self] in
            let work = self?.pending
            self?.pending = nil
            work?()
        }
    }
}
