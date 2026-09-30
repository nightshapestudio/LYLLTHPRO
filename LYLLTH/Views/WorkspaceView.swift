import SwiftUI
import AppKit
import AVFoundation
import NightshapeAudioEngine

@MainActor
final class LYDocumentHistory: ObservableObject {
    private var current: LYLLTHSession?
    private var pendingUndo: LYLLTHSession?
    private var pendingWork: DispatchWorkItem?
    private var ignoreNextChange = false
    private var pendingApply: ((LYLLTHSession) -> Void)?
    private weak var pendingManager: UndoManager?
    private var pendingActionName = "Edit Project"

    func begin(_ session: LYLLTHSession) {
        current = session
    }

    func record(_ next: LYLLTHSession, undoManager: UndoManager?, apply: @escaping (LYLLTHSession) -> Void) {
        if ignoreNextChange {
            ignoreNextChange = false
            current = next
            return
        }
        guard let previous = current, previous != next else { return }
        if pendingUndo == nil {
            pendingUndo = previous
            pendingActionName = LYUndoActionName.describe(from: previous, to: next)
        }
        current = next
        pendingApply = apply
        pendingManager = undoManager
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func flush() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let snapshot = pendingUndo,
              let manager = pendingManager,
              let apply = pendingApply else {
            if let current { LYRecoveryJournal.write(current) }
            return
        }
        pendingUndo = nil
        manager.registerUndo(withTarget: self) { target in
            target.restore(snapshot, undoManager: manager, apply: apply)
        }
        manager.setActionName(pendingActionName)
        if let current { LYRecoveryJournal.write(current) }
    }

    func replace(with session: LYLLTHSession) {
        pendingWork?.cancel()
        pendingWork = nil
        pendingUndo = nil
        current = session
        ignoreNextChange = true
        LYRecoveryJournal.write(session)
    }

    private func restore(_ snapshot: LYLLTHSession, undoManager: UndoManager, apply: @escaping (LYLLTHSession) -> Void) {
        flush()
        guard let redo = current else { return }
        ignoreNextChange = true
        current = snapshot
        apply(snapshot)
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(redo, undoManager: undoManager, apply: apply)
        }
        undoManager.setActionName(LYUndoActionName.describe(from: snapshot, to: redo))
        LYRecoveryJournal.write(snapshot)
    }
}

enum LYUndoActionName {
    static func describe(from old: LYLLTHSession, to new: LYLLTHSession) -> String {
        if old.bpm != new.bpm { return "Change Tempo" }
        if old.loopRange != new.loopRange || old.isLoopEnabled != new.isLoopEnabled { return "Edit Cycle" }
        if old.tracks.count != new.tracks.count { return old.tracks.count < new.tracks.count ? "Add Track" : "Delete Track" }
        if old.trackFolders != new.trackFolders { return "Edit Track Folder" }
        if old.mixGroups != new.mixGroups { return "Edit Mix Group" }
        for (before, after) in zip(old.tracks, new.tracks) where before != after {
            if before.name != after.name { return "Rename Track" }
            if before.volumeDB != after.volumeDB { return "Adjust Track Volume" }
            if before.pan != after.pan { return "Adjust Track Pan" }
            if before.isMuted != after.isMuted { return "Toggle Mute" }
            if before.isSolo != after.isSolo { return "Toggle Solo" }
            if before.isArmed != after.isArmed { return "Toggle Record Arm" }
            if before.automation != after.automation { return "Edit Automation" }
            if before.inserts != after.inserts || before.instrumentPlugin != after.instrumentPlugin { return "Edit Plug-ins" }
            if before.clips != after.clips {
                let oldIDs = Set(before.clips.map(\.id)), newIDs = Set(after.clips.map(\.id))
                if newIDs.count > oldIDs.count { return "Add Region" }
                if newIDs.count < oldIDs.count { return "Delete Region" }
                return "Edit Region"
            }
        }
        if old.mainVolumeDB != new.mainVolumeDB { return "Adjust Main Volume" }
        return "Edit Project"
    }
}

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
        // "%" too: Adam has no usable percent sign.
        let isNumericGlyph = character.isNumber || "/:.−+–—%".contains(character)
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
                // Musical Typing owns its keys while it is open.
                if LYMusicalTyping.claims(event) { return event }
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
    case export
    case project
    case songKey
    case meter
    case addTrack
    case arrangementSnap
    /// Pick what a lane moves: (track, lane), lane nil to add one.
    case automation(UUID, UUID?)
    /// Edit one song FX move.
    case songFX(UUID)
    /// Drum kits.
    case kits
}

private struct LYAudioImportTarget {
    var trackID: UUID?
    var beat: Double
}

struct WorkspaceView: View {
    @Binding var document: LYLLTHSessionDocument
    /// Where the song is saved; nil until it has been saved once.
    var fileURL: URL? = nil
    @EnvironmentObject private var audio: AudioEngineController
    @EnvironmentObject private var plugins: AudioUnitCatalog
    @EnvironmentObject private var audioUnits: LYAudioUnitHost
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @StateObject private var history = LYDocumentHistory()
    /// Which floating window is in front.
    @StateObject private var windowStack = LYWindowStack()

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
    /// Set when the menu was opened from a filled slot's ▾.
    @State private var fxPickerSlot: LYFXSlotRef?
    @State private var synthTrackID: UUID?
    @State private var showTyping = false
    /// The note clip open in the piano roll: (track, clip).
    @State private var pianoRollClip: (track: UUID, clip: UUID)?
    @State private var sirenClip: (track: UUID, clip: UUID)?
    @State private var drumTrackID: UUID?
    /// The DRUM SYNTH page is open; `drumTrackID` is where LOAD puts sounds.
    @State private var drumSynthOpen = false
    @State private var bounce = LYBounce()
    @State private var engineSync = LYCoalescedSync()
    @State private var recorder = LYRecorder()
    // Held with @State, not @StateObject: the workspace must not observe
    // these. Meters publish 20 times a second and the transport every step;
    // only the small views that draw them subscribe.
    private var transportDisplay: TransportDisplayState { audio.stepDisplay }
    @State private var meters = LYMeterStore()
    /// A passing message for the status bar: what an open or save left out.
    @State private var notice: String?
    @State private var recoveryCandidate: LYLLTHSession?
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
                        openSongKeyMenu: { presentMenu(.songKey, from: "songKey") },
                        openMeterMenu: { presentMenu(.meter, from: "meter") }
                    )
                    .environmentObject(audio)

                    WorkspaceStrip(
                        activeWorkspace: $activeWorkspace,
                        openProjectMenu: { presentMenu(.project, from: "stripProject") },
                        showBrowser: $showBrowser,
                        showInspector: $showInspector,
                        showMixer: $showMixer,
                        projectName: document.session.name,
                        isSaved: fileURL != nil,
                        openTrackMenu: { presentMenu(.addTrack, from: "stripTrack") },
                        export: presentExport,
                        openHelp: { openWindow(id: "lyllth-help") },
                        openSettings: { openSettings() },
                        kitName: currentKitName,
                        openKits: { presentMenu(.kits, from: "stripKit") },
                        openDrumSynth: { openDrums(nil) }
                    )

                HStack(spacing: 0) {
                    if showBrowser {
                        BrowserPanel(
                            selection: $selectedBrowserGroup,
                            selectedItem: $selectedBrowserItem,
                            projectAudio: document.audioAssetNames,
                            missingAudio: document.audioNeedingRelink,
                            unusedAudio: document.orphanedAudioNames,
                            onRelink: { relinkAudio(named: $0) },
                            onRemoveUnused: { removeUnusedAudio() },
                            onEffect: { addEffectFromLibrary(named: $0) },
                            onSound: { openSoundFromLibrary($0) },
                            onAudioUnit: { installAudioUnit($0) },
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
                            openPicker: { target in
                                withAnimation(LYLLTHTheme.snap) {
                                    fxPickerSlot = nil
                                    fxPickerTarget = target
                                }
                            },
                            openSynth: { openSynth($0) },
                            openDrums: { openDrums($0) },
                            close: { showInspector = false },
                            openSlotMenu: { target, slot in
                                withAnimation(LYLLTHTheme.snap) {
                                    fxPickerSlot = slot
                                    fxPickerTarget = target
                                }
                            }
                        )
                        .frame(width: 297)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    VStack(spacing: 0) {
                        if activeWorkspace == "PATTERN" {
                            LYStepFollower(steps: audio.stepDisplay) { step in
                            SequencerWorkspace(
                                session: $document.session,
                                selectedTrackID: $selectedTrackID,
                                patternIndex: patternIndex,
                                currentStep: step,
                                isPlaying: audio.isPlaying,
                                waveformState: audio.engine.state.outputWaveformState,
                                syncEngine: { audio.syncSequencer(document.session) },
                                openSound: { id in
                                    let isDrum = document.session.tracks.first { $0.id == id }?.kind == .drumkit
                                    isDrum ? openDrums(id) : openSynth(id)
                                },
                                stepSound: { stepSound($0, by: $1) },
                                openTrackMenu: { presentMenu(.addTrack, from: "seqTracks") }
                            )
                            }
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

                // Menus and the effect picker open above every window; the
                // windows themselves stack in the order they were last used.
                workspaceMenuOverlay
                    .zIndex(LYWindowStack.menus)

                fxPickerOverlay
                    .zIndex(LYWindowStack.menus)

                pianoRollOverlay
                    .zIndex(windowStack.zIndex("pianoroll"))
                sirenOverlay
                    .zIndex(windowStack.zIndex("siren"))

                musicalTypingOverlay
                    .zIndex(windowStack.zIndex("typing"))

                synthEditorOverlay
                    .zIndex(windowStack.zIndex("synth"))

                drumBrowserOverlay
                    .zIndex(windowStack.zIndex("drumsynth"))

                LYBounceOverlay(bounce: bounce, cancel: { bounce.cancel(audio: audio) })
                    .zIndex(250)

                recoveryOverlay
                    .zIndex(300)

                audioUnitEditorOverlay
                    .zIndex(windowStack.zIndex("audio-unit"))

                LYFXWindowHost(
                    session: $document.session,
                    request: $fxRequest,
                    original: fxOriginal,
                    transport: transportDisplay,
                    isPlaying: audio.isPlaying,
                    onTransportTap: { audio.togglePlayback() }
                )
                .zIndex(windowStack.zIndex("fx"))
            }
        }
        .environment(\.lyWindowStack, windowStack)
        .coordinateSpace(name: LYDropdownOverlay<EmptyView>.space)
        .onPreferenceChange(LYMenuAnchorKey.self) { menuAnchors = $0 }
        .frame(minWidth: 960, minHeight: 640)
        .focusedSceneValue(\.lyWorkspace, workspaceActions)
        .onAppear {
            audio.connectAudioUnitHost(audioUnits)
            // First open of this song window only. A text size or contrast
            // change redraws the view, and none of this may happen twice:
            // recovery prompts, recording recovery, Audio Unit restore.
            let firstOpen = !audio.hasOpenedWorkspace
            audio.hasOpenedWorkspace = true
            history.begin(document.session)
            if firstOpen {
                let needsRelink = document.audioNeedingRelink.count
                if needsRelink > 0 {
                    notice = "\(needsRelink) AUDIO FILE\(needsRelink == 1 ? " IS" : "S ARE") MISSING OR DAMAGED  ·  RELINK IN LIBRARY ▸ PROJECT"
                    showBrowser = true
                    selectedBrowserGroup = "PROJECT"
                }
                recoveryCandidate = LYRecoveryJournal.recoverable(
                    projectID: document.session.id,
                    newerThan: document.session.modifiedAt
                )
                if let orphan = LYRecordingJournal.recoverable(projectID: document.session.id) {
                    recoverRecording(orphan)
                }
                if document.isFromDrumKit {
                    notice = (["OPENED FROM DRUMKIT  ·  SAVE KEEPS IT AS A LYLLTH SONG"] + document.importNotes.map { $0.uppercased() })
                        .joined(separator: "  ·  ")
                }
                // Project wavetables first, so synth tracks find them when they load.
                LYWavetableLibrary.shared.register(projectTables: document.wavetables)
                Task { @MainActor in
                    document.session = await audioUnits.restore(document.session, engine: audio.engine)
                }
            }
            selectedTrackID = selectedTrackID ?? document.session.tracks.first?.id
            audio.prepare(document.session)
            LYMIDIInput.shared.start()
            DispatchQueue.main.async { updateMIDITarget() }
            audio.setTransportMode(transportMode, session: document.session, media: document.audioMediaStore)
            audio.syncTimeline(document.session, media: document.audioMediaStore)
            LYFXBridge.pushAll(document.session, engine: audio.engine)
            meters.track(document.session, engine: audio.engine)
            audio.engine.setMainOutputVolume(volume: pow(10, (document.session.mainVolumeDB ?? 0) / 20))
            if firstOpen { plugins.scan() }
            #if DEBUG
            // Screenshot hook: LYLLTH_DEBUG_WORKSPACE=PATTERN or SONG.
            if let workspace = ProcessInfo.processInfo.environment["LYLLTH_DEBUG_WORKSPACE"] { activeWorkspace = workspace }
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
            // Track IDs own stable graph channels. New and deleted tracks still
            // require rack and meter bindings to be refreshed; reorder does not.
            LYFXBridge.pushAll(document.session, engine: audio.engine)
            meters.track(document.session, engine: audio.engine)
        }
        .onChange(of: document.session.mainVolumeDB) { _, value in
            audio.engine.setMainOutputVolume(volume: pow(10, (value ?? 0) / 20))
        }
        .onChange(of: activeWorkspace) { _, _ in
            audio.setTransportMode(transportMode, session: document.session, media: document.audioMediaStore)
        }
        .onChange(of: document.session) { _, _ in
            history.record(document.session, undoManager: undoManager) { recovered in
                document.session = recovered
            }
            // Arrangement edits have to reach the song frames and the audio
            // players. Deferred to just after this frame and coalesced, so a
            // click shows before the engine work runs.
            engineSync.schedule {
                audio.syncSequencer(document.session)
                audio.syncTimeline(document.session, media: document.audioMediaStore)
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
        .onChange(of: audioUnits.stateRevision) { _, _ in
            document.session = audioUnits.captureStates(in: document.session, engine: audio.engine)
        }
        .onDisappear { history.flush() }
    }

    @ViewBuilder
    private var recoveryOverlay: some View {
        if let recovered = recoveryCandidate {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("RECOVER PROJECT")
                    .font(LYLLTHTheme.label(15, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.text)
                Text("LYLLTH FOUND NEWER UNSAVED EDITS FOR \(recovered.name.uppercased()).")
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("DISCARD") {
                        LYRecoveryJournal.discard(projectID: document.session.id)
                        recoveryCandidate = nil
                    }
                    .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.dim))
                    Button("RECOVER") {
                        var session = recovered
                        session.normalizeEngineChannelIndices()
                        document.session = session
                        history.replace(with: session)
                        recoveryCandidate = nil
                        notice = "RECOVERED UNSAVED PROJECT EDITS"
                    }
                    .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.teal))
                }
            }
            .padding(24)
            .frame(width: 390)
            .background(LYLLTHTheme.panel)
            .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.7), lineWidth: 1))
            .shadow(color: LYLLTHTheme.teal.opacity(0.16), radius: 18)
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
                      let data = document.audioData(for: path) else {
                    audioImportError = "This audio event's original file is missing from the project."
                    return
                }
                audio.previewAudioEvent(clip, assetData: data, projectBPM: document.session.bpm)
            },
            openSynth: { openSynth($0) },
            openDrums: { openDrums($0) },
            openPattern: { openPattern(trackID: $0, clipID: $1) },
            openNotes: { openNotes(trackID: $0, clipID: $1) },
            openVocal: { trackID, clipID in
                selectedTrackID = trackID
                withAnimation(LYLLTHTheme.settle) { sirenClip = (trackID, clipID) }
            },
            openAutomationMenu: { trackID, laneID in
                presentMenu(.automation(trackID, laneID), from: laneID.map { "auto.\($0)" } ?? "auto.add.\(trackID)")
            },
            openSongFXMenu: { presentMenu(.songFX($0), from: "songfx") },
            placePattern: {
                document.session.placePatternInSong(document.session.activePatternIndex ?? 0)
                audio.syncSequencer(document.session)
                audio.syncTimeline(document.session, media: document.audioMediaStore)
            },
            consolidateAudio: consolidateAudioEvent,
            toggleFreeze: toggleFreeze,
            printDrum: printDrumSound,
            reprintDrum: reprintDrumSound,
            acceptsRightClicks: {
                // Nothing floating over the arrangement.
                activeMenu == nil && fxRequest == nil && fxPickerTarget == nil && synthTrackID == nil
                    && pianoRollClip == nil && sirenClip == nil && !drumSynthOpen
                    && audioUnits.editor == nil && recoveryCandidate == nil && !showTyping
            },
            stepSound: { stepSound($0, by: $1) },
            openTrackMenuAt: { presentMenu(.addTrack, from: $0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func consolidateAudioEvent(trackID: UUID, clipID: UUID) {
        guard let trackIndex = document.session.tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = document.session.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }),
              let path = document.session.tracks[trackIndex].clips[clipIndex].sourceRelativePath,
              let data = document.audioData(for: path) else {
            audioImportError = "THIS EVENT'S SOURCE AUDIO IS MISSING"
            return
        }
        let clip = document.session.tracks[trackIndex].clips[clipIndex]
        let bpm = document.session.bpm
        Task { @MainActor in
            do {
                let rendered = try await LYAudioEventRenderer.render(
                    data: data,
                    fileExtension: URL(fileURLWithPath: path).pathExtension,
                    clip: clip,
                    projectBPM: bpm
                )
                let printed = try LYAudioEventRenderer.wavData(from: rendered)
                let name = "consolidated-\(UUID().uuidString.lowercased()).wav"
                try document.audioMediaStore.put(printed, named: name)
                guard let currentTrack = document.session.tracks.firstIndex(where: { $0.id == trackID }),
                      let currentClip = document.session.tracks[currentTrack].clips.firstIndex(where: { $0.id == clipID }) else { return }
                var replacement = document.session.tracks[currentTrack].clips[currentClip]
                replacement.sourceRelativePath = name
                replacement.sourceStartSeconds = 0
                replacement.sourceDurationSeconds = Double(rendered.frameLength) / rendered.format.sampleRate
                replacement.sourceFileDurationSeconds = replacement.sourceDurationSeconds
                replacement.sourceSampleRate = rendered.format.sampleRate
                replacement.sourceChannelCount = Int(rendered.format.channelCount)
                replacement.waveformPeaks = LYAudioEventRenderer.waveformPeaks(from: rendered)
                replacement.slipOffsetSeconds = 0
                replacement.eventGainDB = 0
                replacement.pitchSemitones = 0
                replacement.fadeInSeconds = 0
                replacement.fadeOutSeconds = 0
                replacement.stretchMode = .off
                replacement.sourceBPM = nil
                replacement.beatMap = nil
                replacement.preservePitch = true
                replacement.name += " · CONSOLIDATED"
                document.session.tracks[currentTrack].clips[currentClip] = replacement
                audio.syncTimeline(document.session, media: document.audioMediaStore)
                notice = "CONSOLIDATED " + replacement.name.uppercased()
            } catch {
                audioImportError = "CONSOLIDATE: " + error.localizedDescription.uppercased()
            }
        }
    }

    private func toggleFreeze(_ trackID: UUID) {
        guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if let frozen = document.session.tracks[index].frozenState {
            document.session.tracks[index].kind = frozen.kind
            document.session.tracks[index].clips = frozen.clips
            document.session.tracks[index].inserts = frozen.inserts
            document.session.tracks[index].instrumentPlugin = frozen.instrumentPlugin
            document.session.tracks[index].fx = frozen.fx
            document.session.tracks[index].synth = frozen.synth
            document.session.tracks[index].synthPresetID = frozen.synthPresetID
            document.session.tracks[index].drumPresetID = frozen.drumPresetID
            document.session.tracks[index].customDrumPreset = frozen.customDrumPreset
            document.session.tracks[index].samplePath = frozen.samplePath
            document.session.tracks[index].automation = frozen.automation
            document.session.tracks[index].frozenState = nil
            audio.syncSequencer(document.session)
            audio.syncTimeline(document.session, media: document.audioMediaStore)
            notice = "UNFROZE " + document.session.tracks[index].name
            return
        }

        let session = document.session
        Task { @MainActor in
            do {
                let print = try await LYTrackFreezer.render(
                    trackID: trackID,
                    session: session,
                    media: document.audioMediaStore,
                    audio: audio
                )
                let name = "freeze-\(trackID.uuidString.lowercased()).wav"
                try document.audioMediaStore.put(print.data, named: name)
                guard let current = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
                let original = document.session.tracks[current]
                let state = LYFrozenTrackState(
                    kind: original.kind,
                    clips: original.clips,
                    inserts: original.inserts,
                    instrumentPlugin: original.instrumentPlugin,
                    fx: original.fx,
                    synth: original.synth,
                    synthPresetID: original.synthPresetID,
                    drumPresetID: original.drumPresetID,
                    customDrumPreset: original.customDrumPreset,
                    samplePath: original.samplePath,
                    automation: original.automation
                )
                let seconds = print.window.lengthBeats * 60 / max(document.session.bpm, 1)
                document.session.tracks[current].kind = .audio
                document.session.tracks[current].clips = [LYClip(
                    name: original.name + " · FREEZE",
                    kind: .audio,
                    startBeat: print.window.startBeat,
                    lengthBeats: print.window.lengthBeats,
                    sourceRelativePath: name,
                    sourceDurationSeconds: seconds,
                    sourceSampleRate: print.sampleRate,
                    sourceChannelCount: 2,
                    sourceFileDurationSeconds: seconds
                )]
                document.session.tracks[current].inserts = []
                document.session.tracks[current].instrumentPlugin = nil
                document.session.tracks[current].fx = nil
                document.session.tracks[current].synth = nil
                document.session.tracks[current].synthPresetID = nil
                document.session.tracks[current].drumPresetID = nil
                document.session.tracks[current].customDrumPreset = nil
                document.session.tracks[current].samplePath = nil
                document.session.tracks[current].automation = nil
                document.session.tracks[current].frozenState = state
                audio.syncSequencer(document.session)
                audio.syncTimeline(document.session, media: document.audioMediaStore)
                notice = "FROZE " + original.name
            } catch {
                audioImportError = "FREEZE: " + error.localizedDescription.uppercased()
            }
        }
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
        let musical = { (t: LYTrack) in t.kind == .drumkit || t.kind == .instrument }
        let target = tracks.first { $0.id == selectedTrackID && musical($0) } ?? tracks.first { $0.isArmed && musical($0) }
        guard let track = target else { LYMIDIInput.shared.setTarget(nil); return }
        if track.synth != nil {
            LYMIDIInput.shared.setTarget(audio.synthInstrument(for: track.id), routing: track.midiRouting)
            return
        }
        // A DrumKit drum or synth track: each note triggers the channel at
        // that pitch, relative to the track's root.
        let session = document.session
        let engine = audio.engine
        let root = track.rootNote ?? (track.kind == .drumkit ? 36 : 48)
        LYMIDIInput.shared.setTarget(nil, routing: track.midiRouting, fallback: { note, _ in
            guard let channel = LYFXBridge.engineIndex(for: track.id, in: session) else { return }
            engine.auditionNote(trackIndex: channel, pitchSemitones: min(max(Int(note) - root, -48), 48))
        })
    }

    /// EXPORT: a real-time bounce of the whole song to WAV.
    /// EXPORT: DrumKit's export choices in one panel.
    private func presentExport() {
        presentMenu(.export, from: "stripExport")
    }

    private var exportSummary: String {
        let window = audio.exportWindow(document.session)
        return "\(window.barCount) BAR\(window.barCount == 1 ? "" : "S")  ·  \(Int(document.session.bpm.rounded())) BPM  ·  \(document.session.numerator)/\(document.session.denominator)"
    }

    private var exportLoopNote: String? {
        guard document.session.isLoopActive else { return nil }
        let window = audio.exportWindow(document.session)
        return "LOOP · BARS \(window.startBar + 1)–\(window.startBar + window.barCount) · CLEAR THE LOOP TO EXPORT THE WHOLE SONG"
    }

    private func savePanel(_ title: String, name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "EXPORT"
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func runExport(_ choice: ExportPanel.Choice) {
        let name = document.session.name
        switch choice {
        case .wav24:
            guard let url = savePanel("EXPORT · WAV 24-BIT", name: name + ".wav", type: .wav) else { return }
            bounceSong(.mixdown(.wav), to: url)
        case .wav32:
            guard let url = savePanel("EXPORT · WAV 32-BIT FLOAT", name: name + ".wav", type: .wav) else { return }
            bounceSong(.mixdown(.wavFloat), to: url)
        case .m4a:
            guard let url = savePanel("EXPORT · M4A", name: name + ".m4a", type: .mpeg4Audio) else { return }
            bounceSong(.mixdown(.m4a), to: url)
        case .stems:
            guard let url = savePanel("EXPORT · STEMS", name: name + " STEMS.zip", type: .zip) else { return }
            bounceSong(.stems, to: url)
        case .midi:
            guard let url = savePanel("EXPORT · MIDI", name: name + ".mid", type: .midi) else { return }
            let window = audio.exportWindow(document.session)
            let data = LYMIDIExport.data(session: document.session, frames: audio.songFrames(document.session, window: window), window: window)
            bounce.report(Result { try data.write(to: url, options: .atomic); return url })
        case .fkit:
            saveDrumKitProject()
        }
    }

    /// Renders the export range (the loop when one is on, otherwise the whole
    /// song from bar 1) offline, faster than real time.
    private func bounceSong(_ kind: LYBounce.Kind, to url: URL) {
        let session = document.session
        let media = document.audioMediaStore
        bounce.startOffline(
            kind: kind,
            url: url,
            stemName: { track, _ in
                let position = (session.tracks.firstIndex { $0.id == track.id } ?? 0) + 1
                return String(format: "%02d %@", position, track.name.uppercased())
                    .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            },
            readme: { names in offlineStemReadme(window: audio.exportWindow(session), names: names) },
            prepare: { try await LYOfflineExport.prepare(session: session, media: media, audio: audio) },
            fallback: { recordSong(kind, to: url) }
        )
    }

    /// Plays the export range once and records it, for a song the offline
    /// renderer cannot take.
    private func recordSong(_ kind: LYBounce.Kind, to url: URL) {
        let window = audio.exportWindow(document.session)
        let songSeconds = window.lengthBeats * 60 / max(document.session.bpm, 1)
        let stems = kind == .stems ? exportStems() : []
        let previousWorkspace = activeWorkspace
        bounce.start(kind: kind, url: url, songSeconds: songSeconds, stems: stems, readme: stemReadme(window: window, stems: stems),
                     audio: audio, prepare: {
            activeWorkspace = "SONG"
            audio.setTransportMode(.song, session: document.session, media: document.audioMediaStore)
            audio.syncSequencer(document.session)
            audio.syncTimeline(document.session, media: document.audioMediaStore)
        }, restore: {
            activeWorkspace = previousWorkspace
        })
    }

    private func offlineStemReadme(window: LYSongWindow, names: [String]) -> String {
        let session = document.session
        return """
        \(session.name.uppercased())  ·  STEMS FROM LYLLTH

        TEMPO: \(String(format: "%.2f", session.bpm)) BPM
        METER: \(session.numerator)/\(session.denominator)
        BARS: \(window.startBar + 1)–\(window.startBar + window.barCount) (\(window.barCount) BARS)
        EACH STEM STARTS AT BAR \(window.startBar + 1) AND RUNS THE FULL LENGTH, WITH ITS TAIL.

        EACH STEM IS ONE TRACK WITH EVERYTHING IT FEEDS: ITS OWN EFFECTS AND FADER,
        ITS SENDS THROUGH THE BUSES AND ITS SHARE OF THE SHARED REVERB. EFFECTS ON
        MAIN, INCLUDING ITS LIMITER, ARE LEFT OFF SO THE STEMS ADD BACK UP CLEANLY.

        STEMS:
        \(names.map { "  " + $0 }.joined(separator: "\n"))
        """
    }

    /// One stem per track that plays (mute and solo respected, as DrumKit),
    /// buses included, plus the shared reverb's return.
    private func exportStems() -> [LYBounce.Stem] {
        let session = document.session
        let channels = Dictionary(uniqueKeysWithValues: LYChannelMap.channels(in: session).map { ($0.trackID, $0.index) })
        var used = Set<String>()
        var stems: [LYBounce.Stem] = []
        for (position, track) in session.tracks.enumerated() {
            guard let channel = channels[track.id], LYChannelMap.isAudible(track, in: session) else { continue }
            var name = String(format: "%02d %@", position + 1, track.name.uppercased())
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            while used.contains(name) { name += " 2" }
            used.insert(name)
            stems.append(LYBounce.Stem(source: .track(channel), name: name))
        }
        let sends = session.tracks.contains { ($0.fx?.reverbSend ?? 0) > 0.0001 }
        if sends && !(session.reverb?.isBypassed ?? false) {
            stems.append(LYBounce.Stem(source: .sharedReverb, name: "\(String(format: "%02d", session.tracks.count + 1)) SHARED REVERB"))
        }
        return stems
    }

    private func stemReadme(window: LYSongWindow, stems: [LYBounce.Stem]) -> String {
        let session = document.session
        return """
        \(session.name.uppercased())  ·  STEMS FROM LYLLTH

        TEMPO: \(String(format: "%.2f", session.bpm)) BPM
        METER: \(session.numerator)/\(session.denominator)
        BARS: \(window.startBar + 1)–\(window.startBar + window.barCount) (\(window.barCount) BARS)
        EACH STEM STARTS AT BAR \(window.startBar + 1) AND RUNS THE FULL LENGTH, WITH A \(Int(LYBounce.tailSeconds)) S TAIL.

        EACH TRACK IS RECORDED AFTER ITS OWN EFFECTS AND FADER. EFFECTS ON MAIN,
        INCLUDING ITS LIMITER, ARE LEFT OFF SO THE STEMS ADD BACK UP CLEANLY.
        SENDS TO BUSES ARE ON THE BUS STEMS; THE SHARED REVERB HAS ITS OWN STEM.

        STEMS:
        \(stems.map { "  " + $0.name }.joined(separator: "\n"))
        """
    }

    // MARK: Recording

    private func toggleRecording() {
        if recorder.isActive { finishRecording(); return }
        let legacyInput = document.session.recordingSettings?.inputChannel ?? 0
        let audioTargets = document.session.tracks.filter { $0.kind == .audio && $0.isArmed }.map {
            LYAudioRecordTarget(trackID: $0.id, inputChannel: $0.audioInputChannel ?? legacyInput)
        }
        let armedAudio = !audioTargets.isEmpty
        let settings = document.session.recordingSettings ?? LYRecordingSettings(
            preRollBars: document.session.countIn == false ? 0 : 1
        )
        let begin = {
            recorder.start(
                audio: audio,
                bpm: document.session.bpm,
                preRollBeats: settings.preRollBars * max(document.session.numerator, 1),
                recordAudio: armedAudio,
                projectID: document.session.id,
                audioTargets: audioTargets,
                inputMonitoring: settings.inputMonitoring,
                onError: { audioImportError = $0 }
            )
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
        recorder.stop(audio: audio) { notes, takes in
            writeRecordedNotes(notes)
            placeRecordedAudio(takes)
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
            if inSong, track.kind == .instrument, track.synth != nil, track.isChordTrack != true {
                document.session.tracks[trackIndex].clips = LYNoteRecording.write(
                    notes.map { note in
                        let on = songBeat(forTransportBeat: note.onBeat)
                        let off = note.offBeat.map { songBeat(forTransportBeat: $0) } ?? on + 0.25
                        return LYNoteRecording.ExpressivePlayed(
                            beat: on,
                            length: max(off - on, 0.03),
                            pitch: note.note,
                            velocity: note.velocity,
                            expression: note.expression
                        )
                    },
                    into: document.session.tracks[trackIndex].clips,
                    beatsPerBar: beatsPerBar
                )
                continue
            }
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

    /// Places every armed track's take. The recording journal is cleared only
    /// when all of them are in the song, so a failure stays recoverable.
    private func placeRecordedAudio(_ captures: [LYRecordedAudioCapture]) {
        guard !captures.isEmpty else { return }
        Task { @MainActor in
            var placedAll = true
            for capture in captures where await !placeRecordedAudio(capture) { placedAll = false }
            if placedAll { LYRecordingJournal.complete(projectID: document.session.id) }
        }
    }

    private func placeRecordedAudio(_ capture: LYRecordedAudioCapture) async -> Bool {
        let settings = document.session.recordingSettings ?? LYRecordingSettings()
        let latencySeconds = max(0, capture.measuredLatencySeconds + settings.manualLatencyMS / 1_000)
        let latencyBeats = latencySeconds * max(document.session.bpm, 1) / 60
        let correctedTransportBeat = max(0, capture.startBeat - latencyBeats)
        let beat = activeWorkspace == "PATTERN" ? 0 : songBeat(forTransportBeat: correctedTransportBeat)
        do {
                var imported = try await LYAudioImporter.importFile(at: capture.url)
                imported.displayName = "RECORDING " + String(format: "%02d", document.session.tracks.flatMap(\.clips).filter { $0.name.hasPrefix("RECORDING") }.count + 1)
                let firstTrack = capture.targetTrackID
                let firstClipID = document.addImportedAudio(imported, toTrackID: firstTrack, atBeat: beat)
                guard let firstTrackIndex = document.session.tracks.firstIndex(where: { $0.id == firstTrack }),
                      let firstClipIndex = document.session.tracks[firstTrackIndex].clips.firstIndex(where: { $0.id == firstClipID }) else { return false }

                var clip = document.session.tracks[firstTrackIndex].clips[firstClipIndex]
                configureRecordedTakes(&clip, imported: imported, settings: settings)
                document.session.tracks[firstTrackIndex].clips[firstClipIndex] = clip
                return true
        } catch {
            audioImportError = error.localizedDescription
            return false
        }
    }

    private func recoverRecording(_ entry: LYRecordingJournal.Entry) {
        let targets = entry.targetTrackIDs.filter { id in
            document.session.tracks.contains { $0.id == id && $0.kind == .audio }
        }
        guard !targets.isEmpty else {
            LYRecordingJournal.complete(projectID: entry.projectID)
            return
        }
        notice = "RECOVERING INTERRUPTED RECORDING"
        let files = entry.files ?? targets.map {
            LYRecordingJournal.Entry.File(trackID: $0, inputChannel: 0, filePath: entry.filePath)
        }
        placeRecordedAudio(files.filter { targets.contains($0.trackID) && FileManager.default.fileExists(atPath: $0.filePath) }.map { file in
            LYRecordedAudioCapture(
                url: URL(fileURLWithPath: file.filePath), startBeat: 0,
                targetTrackID: file.trackID, inputChannel: file.inputChannel,
                measuredLatencySeconds: 0
            )
        })
    }

    private func configureRecordedTakes(
        _ clip: inout LYClip,
        imported: LYImportedAudio,
        settings: LYRecordingSettings
    ) {
        let secondsPerBeat = 60 / max(document.session.bpm, 1)
        let takeLengthBeats: Double
        if settings.loopTakes, document.session.isLoopActive, let loop = document.session.loopRange {
            takeLengthBeats = max(loop.lengthBeats, lyBeatsPerStep)
            clip.startBeat = loop.startBeat
            clip.lengthBeats = takeLengthBeats
        } else {
            takeLengthBeats = clip.lengthBeats
        }
        let takeSeconds = takeLengthBeats * secondsPerBeat
        let count = settings.loopTakes ? max(1, Int(imported.duration / max(takeSeconds, 0.001))) : 1
        let path = clip.sourceRelativePath ?? imported.fileName
        clip.takes = (0..<count).map { index in
            LYAudioTake(
                name: "TAKE " + String(format: "%02d", index + 1),
                sourceRelativePath: path,
                sourceStartSeconds: Double(index) * takeSeconds,
                durationSeconds: min(takeSeconds, max(0.001, imported.duration - Double(index) * takeSeconds))
            )
        }
        if let active = clip.takes?.last {
            clip.activeTakeID = active.id
            clip.sourceStartSeconds = active.sourceStartSeconds
            clip.sourceDurationSeconds = active.durationSeconds
        }
        if let punch = settings.punchRange {
            let trimStartBeats = max(0, punch.startBeat - clip.startBeat)
            let available = max(lyBeatsPerStep, clip.lengthBeats - trimStartBeats)
            clip.startBeat = max(clip.startBeat, punch.startBeat)
            clip.sourceStartSeconds += trimStartBeats * secondsPerBeat
            clip.lengthBeats = min(available, punch.lengthBeats)
            clip.sourceDurationSeconds = clip.lengthBeats * secondsPerBeat
        }
        clip.compSegments = clip.activeTakeID.map {
            [LYCompSegment(startBeat: 0, lengthBeats: clip.lengthBeats, takeID: $0)]
        }
        clip.normalizeAudioEvent()
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

    /// Replaces a missing or damaged audio file. Every event and take that
    /// names it plays the new file.
    private func relinkAudio(named name: String) {
        let panel = NSOpenPanel()
        panel.title = "RELINK " + name.uppercased()
        panel.message = "Choose the audio file to use for \(name)."
        panel.prompt = "RELINK"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.relinkAudio(named: name, from: url)
            audio.syncTimeline(document.session, media: document.audioMediaStore)
            notice = "RELINKED " + name.uppercased()
        } catch {
            audioImportError = "Could not relink \(name): \(error.localizedDescription)"
        }
    }

    private func removeUnusedAudio() {
        do {
            let moved = try document.cleanupOrphanedAudio()
            notice = moved.isEmpty ? "NO UNUSED AUDIO" : "MOVED \(moved.count) UNUSED AUDIO FILE\(moved.count == 1 ? "" : "S") TO THE TRASH"
        } catch {
            audioImportError = "Could not move unused audio: \(error.localizedDescription)"
        }
    }

    private func installAudioUnit(_ descriptor: LYAudioUnitDescriptor) {
        guard let trackID = selectedTrackID else {
            audioImportError = "SELECT A TRACK BEFORE LOADING AN AUDIO UNIT"
            return
        }
        installAudioUnit(descriptor, on: trackID)
    }

    private func installAudioUnit(_ descriptor: LYAudioUnitDescriptor, on trackID: UUID) {
        Task { @MainActor in
            do {
                document.session = try await audioUnits.install(
                    descriptor,
                    on: trackID,
                    in: document.session,
                    engine: audio.engine
                )
                let slot = descriptor.isInstrument
                    ? document.session.tracks.first(where: { $0.id == trackID })?.instrumentPlugin
                    : document.session.tracks.first(where: { $0.id == trackID })?.inserts.last(where: { $0.identifier == descriptor.id })
                if let slot { audioUnits.openEditor(slotID: slot.id, title: slot.name) }
            } catch {
                audioImportError = "AUDIO UNIT: " + error.localizedDescription.uppercased()
            }
        }
    }

    @ViewBuilder
    private var audioUnitEditorOverlay: some View {
        if let editor = audioUnits.editor {
            GeometryReader { geometry in
                LYFloatingWindow(
                    id: "audio-unit-\(editor.id)",
                    title: "AUDIO UNIT  ·  " + editor.title.uppercased(),
                    accent: LYLLTHTheme.indigo,
                    size: CGSize(width: min(geometry.size.width - 48, 900), height: min(geometry.size.height - 72, 650)),
                    layer: "audio-unit",
                    close: {
                        document.session = audioUnits.captureStates(in: document.session, engine: audio.engine)
                        audioUnits.editor = nil
                    }
                ) {
                    LYAudioUnitEditorView(controller: editor.controller)
                }
            }
        }
    }

    /// Opens DRUM SYNTH, loading into `trackID`, or into the selected drum
    /// track (else the first) when none is given.
    private func openDrums(_ trackID: UUID?) {
        let drums = document.session.tracks.filter { $0.kind == .drumkit && $0.samplePath == nil }
        let target = trackID.flatMap { id in drums.first { $0.id == id } }
            ?? drums.first { $0.id == selectedTrackID } ?? drums.first
        if let target { selectedTrackID = target.id }
        drumTrackID = target?.id
        withAnimation(LYLLTHTheme.settle) { drumSynthOpen = true }
    }

    /// The loaded kit's name, or what the drums are when no kit matches.
    private var currentKitName: String {
        if LYDrumKitLibrary.drumTrackIndices(in: document.session).isEmpty { return "NO DRUMS" }
        return LYDrumKitLibrary.loadedKit(in: document.session, among: LYDrumKitLibrary.factory + LYDrumKitLibrary.userKits())?.name ?? "CUSTOM"
    }

    @ViewBuilder
    private var drumBrowserOverlay: some View {
        if drumSynthOpen {
            let close = { withAnimation(LYLLTHTheme.snap) { drumSynthOpen = false } }
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "drumsynth",
                    title: "DRUM SYNTH",
                    accent: LYLLTHTheme.teal,
                    size: CGSize(width: min(geo.size.width - 32, 1320), height: min(geo.size.height - 56, 800)),
                    close: close
                ) {
                    LYDrumSynthPage(
                        tracks: document.session.tracks.filter { $0.kind == .drumkit && $0.samplePath == nil },
                        initialTrackID: drumTrackID,
                        audition: { audio.auditionDrum($0) },
                        load: { trackID, preset, custom in
                            guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
                            document.session.tracks[index].customDrumPreset = custom ? preset : nil
                            document.session.tracks[index].drumPresetID = preset.id
                            drumTrackID = trackID
                        }
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

    /// Opens a note clip in the piano roll. A track still on a DrumKit
    /// preset moves onto LUNATK so the notes have something to play.
    private func openNotes(trackID: UUID, clipID: UUID) {
        guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if document.session.tracks[index].synth == nil {
            document.session.tracks[index].synth = .initPatch
        }
        audio.syncSequencer(document.session)
        selectedTrackID = trackID
        withAnimation(LYLLTHTheme.settle) { pianoRollClip = (trackID, clipID) }
    }

    /// SIREN over the workspace, editing one audio event in place.
    @ViewBuilder
    private var sirenOverlay: some View {
        if let ref = sirenClip,
           let trackIndex = document.session.tracks.firstIndex(where: { $0.id == ref.track }),
           let clipIndex = document.session.tracks[trackIndex].clips.firstIndex(where: { $0.id == ref.clip }) {
            let track = document.session.tracks[trackIndex]
            let clip = track.clips[clipIndex]
            let close = { withAnimation(LYLLTHTheme.snap) { sirenClip = nil } }
            let position = document.session.tracks.firstIndex { $0.id == track.id } ?? 0
            let accent = LYLLTHTheme.trackAccent(position: position)
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "siren",
                    title: "SIREN  ·  " + track.name + "  ·  " + clip.name.uppercased(),
                    accent: accent,
                    size: CGSize(width: min(geo.size.width - 32, 1240), height: min(geo.size.height - 56, 640)),
                    close: close
                ) {
                    LYSirenEditor(
                        clip: Binding(
                            get: {
                                document.session.tracks.first { $0.id == ref.track }?.clips.first { $0.id == ref.clip } ?? clip
                            },
                            set: { edited in
                                guard let t = document.session.tracks.firstIndex(where: { $0.id == ref.track }),
                                      let c = document.session.tracks[t].clips.firstIndex(where: { $0.id == ref.clip }) else { return }
                                document.session.tracks[t].clips[c] = edited
                            }
                        ),
                        context: LYSirenContext(
                            session: document.session,
                            trackID: ref.track,
                            sourceURL: { [document] path in
                                guard let data = document.audioData(for: path) else { return nil }
                                return try? LYAudioSourceFileCache.url(for: data, fileExtension: URL(fileURLWithPath: path).pathExtension)
                            },
                            songBeat: { [audio] in audio.isPlaying && audio.transportMode == .song ? audio.currentSongBeat() : nil }
                        ),
                        accent: accent
                    )
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var pianoRollOverlay: some View {
        if let ref = pianoRollClip,
           let trackIndex = document.session.tracks.firstIndex(where: { $0.id == ref.track }),
           let clipIndex = document.session.tracks[trackIndex].clips.firstIndex(where: { $0.id == ref.clip }) {
            let track = document.session.tracks[trackIndex]
            let close = { withAnimation(LYLLTHTheme.snap) { pianoRollClip = nil } }
            let position = document.session.tracks.firstIndex { $0.id == track.id } ?? 0
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "pianoroll",
                    title: "PIANO ROLL  ·  " + track.name,
                    accent: LYLLTHTheme.trackAccent(position: position),
                    size: CGSize(width: min(geo.size.width - 32, 1180), height: min(geo.size.height - 56, 640)),
                    close: close
                ) {
                    LYPianoRoll(
                        clip: Binding(
                            get: {
                                document.session.tracks.first { $0.id == ref.track }?.clips.first { $0.id == ref.clip }
                                    ?? document.session.tracks[trackIndex].clips[clipIndex]
                            },
                            set: { clip in
                                guard let t = document.session.tracks.firstIndex(where: { $0.id == ref.track }),
                                      let c = document.session.tracks[t].clips.firstIndex(where: { $0.id == ref.clip }) else { return }
                                document.session.tracks[t].clips[c] = clip
                            }
                        ),
                        trackName: track.name,
                        accent: LYLLTHTheme.trackAccent(position: position),
                        instrument: audio.synthInstrument(for: ref.track),
                        beatsPerBar: max(1, Double(document.session.numerator) * 4 / Double(max(document.session.denominator, 1))),
                        songBeat: { [audio] in audio.isPlaying && audio.transportMode == .song ? audio.currentSongBeat() : nil }
                    )
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
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
    /// Puts an effect on the channel (switched on, as Logic inserts a
    /// plug-in running) or takes it off.
    private func toggleMembership(_ kind: FXKind, target: FXTarget) {
        var rack = LYFXBridge.rack(for: target, in: document.session)
        var chain = rack.chain(isMain: target == .main)
        if let index = chain.firstIndex(of: kind) {
            chain.remove(at: index)
            rack.order = chain
        } else {
            chain.append(kind)
            rack.order = chain
            rack.engage(kind, isMain: target == .main)
        }
        LYFXBridge.setRack(rack, for: target, in: &document.session)
        LYFXBridge.pushRack(target: target, session: document.session, engine: audio.engine)
    }

    /// The name a filled slot's menu shows.
    private func slotTitle(_ slot: LYFXSlotRef, target: FXTarget) -> String {
        switch slot {
        case .effect(let kind): return kind.title
        case .audioUnit(let id):
            guard case .track(let trackID) = target else { return "AUDIO UNIT" }
            return document.session.tracks.first { $0.id == trackID }?.inserts.first { $0.id == id }?.name.uppercased() ?? "AUDIO UNIT"
        }
    }

    /// NO EFFECT in a slot's menu.
    private func clearSlot(_ slot: LYFXSlotRef, target: FXTarget) {
        switch slot {
        case .effect(let kind):
            if LYFXBridge.rack(for: target, in: document.session).chain(isMain: target == .main).contains(kind) {
                toggleMembership(kind, target: target)
            }
            if fxRequest?.kind == kind && fxRequest?.target == target { fxRequest = nil }
        case .audioUnit(let id):
            guard case .track(let trackID) = target else { return }
            document.session = audioUnits.removeEffect(slotID: id, from: trackID, in: document.session, engine: audio.engine)
        }
    }

    /// Another effect chosen from a filled slot's menu: it takes that slot's
    /// place in the chain, switched on.
    private func replaceSlot(_ slot: LYFXSlotRef, with kind: FXKind, target: FXTarget) {
        guard case .effect(let old) = slot else {
            clearSlot(slot, target: target)
            toggleMembership(kind, target: target)
            return
        }
        guard old != kind else { return }
        let isMain = target == .main
        var rack = LYFXBridge.rack(for: target, in: document.session)
        var chain = rack.chain(isMain: isMain)
        guard var position = chain.firstIndex(of: old) else { return }
        chain.remove(at: position)
        if let existing = chain.firstIndex(of: kind) {
            chain.remove(at: existing)
            if existing < position { position -= 1 }
        }
        chain.insert(kind, at: min(position, chain.count))
        rack.order = chain
        rack.engage(kind, isMain: isMain)
        LYFXBridge.setRack(rack, for: target, in: &document.session)
        LYFXBridge.pushRack(target: target, session: document.session, engine: audio.engine)
        if fxRequest?.kind == old && fxRequest?.target == target { fxRequest = nil }
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

    /// The + menu beside a channel strip: folders of effects that open to
    /// the right, over the arrangement.
    @ViewBuilder
    private var fxPickerOverlay: some View {
        if let target = fxPickerTarget {
            let close = {
                withAnimation(LYLLTHTheme.snap) {
                    fxPickerTarget = nil
                    fxPickerSlot = nil
                }
            }
            let slot = fxPickerSlot
            let anchor = slot.flatMap { menuAnchors[$0.anchorID(isMain: target == .main)] }
                ?? menuAnchors[target == .main ? "fxAdd.main" : "fxAdd.track"]
            let trackID: UUID? = { if case .track(let id) = target { return id } else { return nil } }()
            GeometryReader { geo in
                let x = min((anchor?.maxX ?? geo.size.width / 3) + 8, max(8, geo.size.width - 240))
                let y = min(max(8, (anchor?.minY ?? geo.size.height / 3) - 60), max(8, geo.size.height - 520))
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: close)
                    LYFXStartMenu(
                        targetName: target == .main ? "MAIN MIX" : (document.session.tracks.first { $0.id == trackID }?.name ?? "TRACK"),
                        target: target,
                        chain: LYFXBridge.rack(for: target, in: document.session).chain(isMain: target == .main),
                        audioUnits: trackID == nil ? [] : plugins.effects,
                        add: { kind in
                            if let slot {
                                replaceSlot(slot, with: kind, target: target)
                            } else {
                                toggleMembership(kind, target: target)
                            }
                            openFX(kind, target: target)
                        },
                        open: { openFX($0, target: target) },
                        remove: { toggleMembership($0, target: target) },
                        addAudioUnit: { unit in
                            guard let trackID else { return }
                            if let slot { clearSlot(slot, target: target) }
                            installAudioUnit(unit, on: trackID)
                        },
                        close: close,
                        replacing: slot.map { slotTitle($0, target: target) },
                        clearSlot: slot.map { slot in { clearSlot(slot, target: target) } }
                    )
                    .offset(x: x, y: y)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .preferredColorScheme(.dark)
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
            exportSong: presentExport,
            toggleMusicalTyping: toggleMusicalTyping,
            togglePlayback: { audio.togglePlayback() },
            addTrack: { presentMenu(.addTrack, from: activeWorkspace == "PATTERN" ? "seqTracks" : "arrTracks") },
            openDrumSynth: { openDrums(nil) },
            openKits: { presentMenu(.kits, from: "stripKit") },
            openLUNATK: {
                let synths = document.session.tracks.filter { $0.kind == .instrument && $0.isChordTrack != true }
                if let track = synths.first(where: { $0.id == selectedTrackID }) ?? synths.first { openSynth(track.id) }
            },
            stepSound: { step in if let id = selectedTrackID { stepSound(id, by: step) } },
            printSound: {
                guard let id = selectedTrackID,
                      document.session.tracks.first(where: { $0.id == id })?.kind == .drumkit else {
                    notice = "SELECT A DRUM TRACK TO PRINT ITS SOUND"
                    return
                }
                printDrumSound(id, atBeat: audio.cursorBeat)
            }
        )
    }

    /// A drum track's sound laid on its PRINT audio track at `beat`.
    private func printDrumSound(_ trackID: UUID, atBeat beat: Double) {
        guard let track = document.session.tracks.first(where: { $0.id == trackID }), track.kind == .drumkit else { return }
        let media = document.audioMediaStore
        Task { @MainActor in
            do {
                let (sound, printed) = try await LYDrumPrint.audio(for: track) { media.url(for: $0) }
                guard let placed = document.addDrumPrint(sound, fromDrumTrackID: trackID, printed: printed, atBeat: beat) else { return }
                selectedTrackID = placed.trackID
                audioImportError = nil
                notice = "PRINTED " + sound.displayName + " TO " + LYDrumPrint.trackName(for: track)
            } catch {
                audioImportError = "PRINT: " + error.localizedDescription.uppercased()
            }
        }
    }

    /// Prints a printed event's drum sound again, as that sound is now.
    /// Every event cut from the same print follows.
    private func reprintDrumSound(_ clipID: UUID) {
        guard let clip = document.session.tracks.lazy.flatMap(\.clips).first(where: { $0.id == clipID }),
              let printed = clip.printedDrum, let sourceName = clip.sourceRelativePath else { return }
        guard let preset = LYDrumPrint.currentPreset(for: printed, in: document.session) else {
            audioImportError = "PRINT AGAIN: THAT SOUND IS NO LONGER IN THE LIBRARY"
            return
        }
        Task { @MainActor in
            do {
                let sound = try await LYDrumPrint.audio(for: preset)
                document.replaceDrumPrint(sourceName: sourceName, with: sound)
                audioImportError = nil
                notice = "PRINTED " + sound.displayName + " AGAIN"
            } catch {
                audioImportError = "PRINT AGAIN: " + error.localizedDescription.uppercased()
            }
        }
    }

    /// Previous / next sound on a track, within its kind, played as it lands.
    private func stepSound(_ trackID: UUID, by step: Int) {
        guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let track = document.session.tracks[index]
        selectedTrackID = trackID
        if track.kind == .drumkit, track.samplePath == nil {
            let mine = LYDrumUserPresets.all()
            guard let next = LYSoundStepping.drum(from: track, step: step, userPresets: mine) else { return }
            document.session.tracks[index].customDrumPreset = mine.contains { $0.id == next.id } ? next : nil
            document.session.tracks[index].drumPresetID = next.id
            audio.auditionDrum(next)
            notice = track.name + "  ·  " + next.name.uppercased()
        } else if let patch = track.synth,
                  let next = LYSoundStepping.synth(from: patch, step: step, userPatches: LYSynthPresetStore.shared.presets) {
            document.session.tracks[index].synth = next
            audio.synthInstrument(for: trackID)?.apply(next, bpm: document.session.bpm)
            previewSynth(trackID)
            notice = track.name + "  ·  LUNATK " + next.name.uppercased()
        }
    }

    /// A short note on a LUNATK track, so a new patch is heard at once.
    /// Skipped while the song plays: the song is the preview then.
    private func previewSynth(_ trackID: UUID) {
        guard !audio.isPlaying, let instrument = audio.synthInstrument(for: trackID),
              let track = document.session.tracks.first(where: { $0.id == trackID }) else { return }
        let note = UInt8(min(max((track.rootNote ?? 48) + 12, 36), 84))
        instrument.noteOn(note, velocity: 100, atHostTime: 0, cutoff: 1, resonance: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { instrument.noteOff(note, atHostTime: 0) }
    }

    private func toggleMusicalTyping() {
        withAnimation(LYLLTHTheme.snap) { showTyping.toggle() }
        if showTyping { LYMusicalTyping.shared.open() } else { LYMusicalTyping.shared.close() }
        updateMIDITarget()
    }

    /// What Musical Typing and a MIDI keyboard play right now.
    private var playTargetName: String {
        let tracks = document.session.tracks
        guard let track = tracks.first(where: { $0.id == selectedTrackID && ($0.kind == .drumkit || $0.kind == .instrument) })
            ?? tracks.first(where: { $0.isArmed && ($0.kind == .drumkit || $0.kind == .instrument) }) else {
            return "SELECT A SYNTH OR DRUM TRACK"
        }
        return track.name.uppercased() + (track.synth != nil ? "  ·  LUNATK" : track.kind == .drumkit ? "  ·  DRUMS" : "  ·  SYNTH")
    }

    @ViewBuilder
    private var musicalTypingOverlay: some View {
        if showTyping {
            GeometryReader { geo in
                LYFloatingWindow(
                    id: "typing",
                    title: "MUSICAL TYPING  ·  ⌘K",
                    accent: LYLLTHTheme.teal,
                    size: CGSize(width: min(geo.size.width - 32, 760), height: 190),
                    close: { toggleMusicalTyping() }
                ) {
                    LYMusicalTypingPanel(typing: LYMusicalTyping.shared, target: playTargetName, accent: LYLLTHTheme.teal)
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
    }

    private func runProjectAction(_ action: ProjectPanel.Action) {
        // Document commands go to this window's document through AppKit.
        switch action {
        case .new: NSDocumentController.shared.newDocument(nil)
        case .demo: LYNewSong.openDemo()
        case .open: NSDocumentController.shared.openDocument(nil)
        case .save: saveDocument(as: false)
        case .saveAs: saveDocument(as: true)
        case .openFKit: openDrumKitProject()
        case .saveFKit: saveDrumKitProject()
        case .export: presentExport()
        }
    }

    /// Saves this window's song; an unsaved one asks where. Sent to the
    /// document itself: a nil-targeted action from an overlay could miss it.
    private func saveDocument(as newCopy: Bool) {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if let doc = window.flatMap({ NSDocumentController.shared.document(for: $0) }) ?? NSDocumentController.shared.currentDocument {
            newCopy ? doc.saveAs(nil) : doc.save(nil)
        } else {
            NSApp.sendAction(newCopy ? #selector(NSDocument.saveAs(_:)) : #selector(NSDocument.save(_:)), to: nil, from: nil)
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

    /// Adds a lane for `target`, or points an existing lane at it. A new lane
    /// starts with one point at the control's current value, so nothing
    /// jumps until the line is drawn.
    private func setAutomationTarget(_ target: LYAutomationTarget, trackID: UUID, laneID: UUID?) {
        guard let index = document.session.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        var lanes = document.session.tracks[index].automation ?? []
        let start = target.staticValue(of: document.session.tracks[index])
        if let laneID, let l = lanes.firstIndex(where: { $0.id == laneID }) {
            guard lanes[l].target != target else { return }
            lanes[l].target = target
            lanes[l].points = [LYAutomationPoint(beat: 0, value: start)]
        } else {
            lanes.append(LYAutomationLane(target: target, points: [LYAutomationPoint(beat: 0, value: start)]))
        }
        document.session.tracks[index].automation = lanes
        document.session.tracks[index].showsAutomation = true
        // A send lane needs its connection even while the send is at zero.
        if case .send(let busID) = target {
            var sends = document.session.tracks[index].sends ?? []
            if !sends.contains(where: { $0.busID == busID }) {
                sends.append(LYBusSend(busID: busID, level: 0))
                document.session.tracks[index].sends = sends
            }
            audio.syncSequencer(document.session)
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
                case .meter:
                    MeterPicker(
                        numerator: $document.session.numerator,
                        denominator: $document.session.denominator,
                        close: dismissMenu
                    )
                case .songKey:
                    SongKeyPicker(
                        key: Binding(
                            get: { document.session.songKey ?? .default },
                            set: { document.session.songKey = $0 }
                        ),
                        close: dismissMenu
                    )
                case .songFX(let blockID):
                    if (document.session.songFX ?? []).contains(where: { $0.id == blockID }) {
                        LYSongFXPanel(
                            block: Binding(
                                get: { document.session.songFX?.first { $0.id == blockID } ?? LYSongFXBlock(move: .open, trackID: nil, startBeat: 0, lengthBeats: 4) },
                                set: { value in
                                    guard let index = document.session.songFX?.firstIndex(where: { $0.id == blockID }) else { return }
                                    document.session.songFX?[index] = value
                                }
                            ),
                            targets: document.session.tracks,
                            remove: {
                                document.session.songFX?.removeAll { $0.id == blockID }
                                if document.session.songFX?.isEmpty == true { document.session.songFX = nil }
                                dismissMenu()
                            },
                            close: dismissMenu
                        )
                    }
                case .automation(let trackID, let laneID):
                    if let track = document.session.tracks.first(where: { $0.id == trackID }) {
                        LYAutomationTargetPanel(
                            track: track,
                            session: document.session,
                            current: laneID.flatMap { id in track.automation?.first { $0.id == id }?.target },
                            taken: Set((track.automation ?? []).map(\.target)),
                            choose: { target in
                                setAutomationTarget(target, trackID: trackID, laneID: laneID)
                                dismissMenu()
                            },
                            close: dismissMenu
                        )
                    }
                case .addTrack:
                    AddTrackPanel(
                        add: { kind in
                            addTrack(kind: kind)
                            dismissMenu()
                            // A new track wants a sound: open the browser on it.
                            if let id = selectedTrackID {
                                if kind == .drumkit { openDrums(id) }
                                if kind == .instrument { openSynth(id) }
                            }
                        },
                        addFolder: {
                            guard let selectedTrackID else { return }
                            let number = (document.session.trackFolders?.count ?? 0) + 1
                            _ = document.session.createFolder(
                                name: "FOLDER " + String(format: "%02d", number),
                                trackIDs: [selectedTrackID]
                            )
                            dismissMenu()
                        },
                        addGroup: {
                            guard let selectedTrackID else { return }
                            let members = document.session.folder(containing: selectedTrackID)?.trackIDs ?? [selectedTrackID]
                            let number = (document.session.mixGroups?.count ?? 0) + 1
                            _ = document.session.createMixGroup(
                                name: "GROUP " + String(format: "%02d", number),
                                trackIDs: members
                            )
                            dismissMenu()
                        },
                        close: dismissMenu
                    )
                case .export:
                    ExportPanel(
                        summary: exportSummary,
                        loopNote: exportLoopNote,
                        run: { choice in
                            dismissMenu()
                            // Let the menu close before a save panel opens.
                            DispatchQueue.main.async { runExport(choice) }
                        },
                        close: dismissMenu
                    )
                case .kits:
                    LYKitPanel(
                        session: document.session,
                        loadKit: { kit in LYDrumKitLibrary.load(kit, into: &document.session) },
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
        document.session.assignEngineChannel(toTrackAt: document.session.tracks.count - 1)
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
    let openMeterMenu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            LYWordmarkLockup()
                .frame(width: 264, alignment: .leading)

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
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(statusText)
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(recorder.isActive ? LYLLTHTheme.record : (audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.dim))
            }
            .frame(minWidth: 128, alignment: .leading)
            .fixedSize()

            // Narrow windows: the utilities fold into two rows of icons, then
            // PATTERN / SONG steps aside (SEQUENCER / ARRANGE below does the
            // same). Time, tempo and key always keep their full width.
            ViewThatFits(in: .horizontal) {
                trailing(showsMode: true, compact: false)
                trailing(showsMode: true, compact: true)
                trailing(showsMode: false, compact: true)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 112)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline(color: LYLLTHTheme.lineStrong) }
    }

    private func trailing(showsMode: Bool, compact: Bool) -> some View {
        HStack(spacing: 0) {
            if showsMode {
                divider

                LYModeSwitch(activeWorkspace: $activeWorkspace)
                .padding(.horizontal, 18)
            }

            divider

            TempoReadout(
                bpm: $session.bpm,
                numerator: session.numerator,
                denominator: session.denominator,
                openMeter: openMeterMenu
            )
            .padding(.horizontal, 18)
            .fixedSize()

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
            .fixedSize()

            Spacer(minLength: compact ? 8 : 18)

            if compact {
                VStack(spacing: 4) {
                    HStack(spacing: 4) { recordingUtilities(compact: true) }
                    HStack(spacing: 4) { playbackUtilities(compact: true) }
                }
            } else {
                HStack(spacing: 6) {
                    recordingUtilities(compact: false)
                    playbackUtilities(compact: false)
                }
            }
        }
    }

    @ViewBuilder
    private func recordingUtilities(compact: Bool) -> some View {
                TransportUtility(
                    compact: compact,
                    icon: "metronome",
                    title: "CLICK",
                    tint: LYLLTHTheme.teal,
                    isOn: audio.isMetronomeEnabled,
                    action: { audio.toggleMetronome(for: session) }
                )
                .help("Metronome")
                TransportUtility(
                    compact: compact,
                    icon: "4.circle",
                    title: "COUNT",
                    tint: LYLLTHTheme.record,
                    isOn: (session.recordingSettings?.preRollBars ?? (session.countIn == false ? 0 : 1)) > 0,
                    action: {
                        var settings = session.recordingSettings ?? LYRecordingSettings()
                        settings.preRollBars = settings.preRollBars > 0 ? 0 : 1
                        session.recordingSettings = settings
                        session.countIn = settings.preRollBars > 0
                    }
                )
                .help("One-bar pre-roll before recording starts")
                TransportUtility(
                    compact: compact,
                    icon: "arrow.triangle.2.circlepath",
                    title: "TAKES",
                    tint: LYLLTHTheme.purple,
                    isOn: session.recordingSettings?.loopTakes ?? true,
                    action: {
                        var settings = session.recordingSettings ?? LYRecordingSettings()
                        settings.loopTakes.toggle()
                        session.recordingSettings = settings
                    }
                )
                .help("Create a take for every recorded loop pass")
                TransportUtility(
                    compact: compact,
                    icon: "scope",
                    title: "PUNCH",
                    tint: LYLLTHTheme.record,
                    isOn: session.recordingSettings?.punchRange != nil,
                    action: {
                        var settings = session.recordingSettings ?? LYRecordingSettings()
                        settings.punchRange = settings.punchRange == nil ? session.loopRange : nil
                        session.recordingSettings = settings
                    }
                )
                .help("Use the loop range as the punch-in/out range")
    }

    @ViewBuilder
    private func playbackUtilities(compact: Bool) -> some View {
                TransportUtility(
                    compact: compact,
                    icon: "ear",
                    title: "MON",
                    tint: LYLLTHTheme.teal,
                    isOn: session.recordingSettings?.inputMonitoring ?? false,
                    action: {
                        var settings = session.recordingSettings ?? LYRecordingSettings()
                        settings.inputMonitoring.toggle()
                        session.recordingSettings = settings
                    }
                )
                .help("Monitor the selected input while recording; use headphones")
                TransportUtility(
                    compact: compact,
                    icon: "timer",
                    title: "LAT " + String(format: "%+.0f", session.recordingSettings?.manualLatencyMS ?? 0),
                    tint: LYLLTHTheme.indigo,
                    isOn: abs(session.recordingSettings?.manualLatencyMS ?? 0) > 0.01,
                    action: {
                        let choices: [Double] = [-10, -5, -2, 0, 2, 5, 10]
                        var settings = session.recordingSettings ?? LYRecordingSettings()
                        let current = choices.firstIndex(of: settings.manualLatencyMS) ?? 3
                        settings.manualLatencyMS = choices[(current + 1) % choices.count]
                        session.recordingSettings = settings
                    }
                )
                .help("Manual recording latency correction in milliseconds")
                TransportUtility(
                    compact: compact,
                    icon: "repeat",
                    title: "LOOP",
                    tint: LYLLTHTheme.indigo,
                    isOn: session.isLoopActive,
                    action: toggleLoop
                )
                .help(loopHelp)
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
/// outline cut in indigo, the second half solid in purple, with the muted
/// byline spread across the full width of the wordmark and set close under it.
private struct LYWordmarkLockup: View {
    private let size: CGFloat = 62
    private static let outline = Color(hex: 0x786CF7)
    private static let solid = Color(hex: 0x8853F6)
    /// Muted, so it signs the wordmark instead of competing with it.
    private static let byline = Color(hex: 0x7D7893)
    private static let bylineSize: CGFloat = 11
    /// Cap heights as a share of the point size (the fonts' own metrics).
    private static let wordmarkCap: CGFloat = 696.0 / 1024.0
    private static let bylineCap: CGFloat = 680.0 / 1000.0

    var body: some View {
        // Placed by the baselines, not by the text boxes: the NIGHTSHAPE face
        // keeps room for descenders under the caps that LYLLTH never uses, and
        // stacking the boxes left a gap wider than the byline is tall. The gap
        // from the wordmark's baseline to the byline's cap top is a fifth of
        // the wordmark's cap height.
        let drop = LYLLTHTheme.wordmarkOpticalDrop(size)
        let gap = size * Self.wordmarkCap * 0.2
        let bylineCapHeight = Self.bylineSize * CGFloat(LYAppPreferences.textScale()) * Self.bylineCap
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .lockupSeam)) {
            letters
                .offset(y: drop)
                .alignmentGuide(.lockupSeam) { d in d[.lastTextBaseline] + drop + gap }
                .accessibilityLabel("LYLLTH")
            byline
                .alignmentGuide(.lockupSeam) { d in d[.firstTextBaseline] - bylineCapHeight }
                .accessibilityHidden(true)
        }
        // The stack is as wide as the wordmark; the byline fills that width.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var letters: some View {
        HStack(spacing: 0) {
            Text("LYL").font(LYLLTHTheme.wordmarkOutline(size)).foregroundStyle(Self.outline)
            Text("LTH").font(LYLLTHTheme.wordmark(size)).foregroundStyle(Self.solid)
        }
        .tracking(1.6)
        .fixedSize()
    }

    /// Each character spaced evenly from the wordmark's first stroke to its last.
    private var byline: some View {
        HStack(spacing: 0) {
            let characters = Array("BY NIGHTSHAPE")
            ForEach(characters.indices, id: \.self) { index in
                if index > 0 { Spacer(minLength: 0) }
                Text(String(characters[index]))
            }
        }
        .font(LYLLTHTheme.label(Self.bylineSize))
        .foregroundStyle(Self.byline)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }
}

private extension VerticalAlignment {
    /// Where the wordmark ends and the byline begins.
    enum LockupSeam: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.bottom] }
    }
    static let lockupSeam = VerticalAlignment(LockupSeam.self)
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
        case .running(let elapsed, let total, let kind):
            panel {
                Text("EXPORTING  ·  " + kind).font(LYLLTHTheme.label(11, weight: .bold)).tracking(2).foregroundStyle(LYLLTHTheme.teal)
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
                Text(bounce.isOffline
                     ? (kind.hasPrefix("STEMS") ? "RENDERING FASTER THAN REAL TIME · STEM \(bounce.passLabel ?? "")"
                                                : "RENDERING FASTER THAN REAL TIME THROUGH THE SAME CHANNELS AND EFFECTS")
                     : (kind.hasPrefix("STEMS") ? "RECORDING EVERY TRACK AT ONCE, IN REAL TIME, SO EACH SOUNDS EXACTLY AS IT PLAYS"
                                                : "RECORDING THE MAIN MIX IN REAL TIME, SO IT SOUNDS EXACTLY AS IT PLAYS"))
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

/// Rebuilds only its content on each sequencer step, so the rest of the
/// workspace stays put while the song plays.
private struct LYStepFollower<Content: View>: View {
    @ObservedObject var steps: TransportDisplayState
    @ViewBuilder let content: (Int) -> Content

    var body: some View { content(steps.currentStep) }
}


/// DrumKit's export choices, with its wording.
struct ExportPanel: View {
    enum Choice { case wav24, wav32, m4a, stems, midi, fkit }

    let summary: String
    let loopNote: String?
    let run: (Choice) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(eyebrow: "EXPORT", title: summary, accent: LYLLTHTheme.indigo, close: close)
            if let loopNote {
                Text(loopNote)
                    .font(LYLLTHTheme.label(7, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.purple)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            LYNightshapeMenuDivider()
            VStack(spacing: 6) {
                row("square.stack.3d.down.right", "STEMS · ZIP", "EACH TRACK ALONE · BAR-1 ALIGNED · README", .stems, LYLLTHTheme.teal)
                row("pianokeys", "MIDI · SONG", "NOTES ONLY · ONE TRACK PER SOUND · GM DRUM MAP", .midi, LYLLTHTheme.teal)
            }
            .padding(12)
            LYNightshapeMenuDivider()
            VStack(spacing: 6) {
                row("waveform", "WAV · 24-BIT", "MIXDOWN · THE USUAL MASTER", .wav24, LYLLTHTheme.indigo)
                row("waveform.path", "WAV · 32-BIT FLOAT", "MIXDOWN · FULL HEADROOM", .wav32, LYLLTHTheme.indigo)
                row("envelope", "M4A · AAC", "COMPRESSED · FOR SENDING AROUND", .m4a, LYLLTHTheme.indigo)
            }
            .padding(12)
            LYNightshapeMenuDivider()
            VStack(spacing: 6) {
                row("iphone", "PROJECT · FKIT", "EVERYTHING · OPEN AND EDIT IN DRUMKIT", .fkit, LYLLTHTheme.purple)
            }
            .padding(12)
        }
        .frame(width: 360)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.indigo)
    }

    private func row(_ icon: String, _ title: String, _ detail: String, _ choice: Choice, _ accent: Color) -> some View {
        LYNightshapeMenuRow(icon: icon, title: title, detail: detail, accent: accent, action: { run(choice) })
    }
}
