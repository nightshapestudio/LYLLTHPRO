import SwiftUI
import AppKit
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
private func mixedNumericLabel(
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
private struct LYArrangementKeyMonitor: NSViewRepresentable {
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
    @State private var activeWorkspace = "ARRANGE"
    @State private var showBrowser = true
    @State private var showInspector = true
    @State private var showMixer = true
    @State private var activeMenu: LYWorkspaceMenu?
    @State private var audioImportError: String?

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
                        openSongKeyMenu: { presentMenu(.songKey) }
                    )
                    .environmentObject(audio)

                    WorkspaceStrip(
                        activeWorkspace: $activeWorkspace,
                        showBrowser: $showBrowser,
                        showInspector: $showInspector,
                        showMixer: $showMixer,
                        projectName: document.session.name,
                        openTrackMenu: { presentMenu(.addTrack) }
                    )

                HStack(spacing: 0) {
                    if showBrowser {
                        BrowserPanel(
                            selection: $selectedBrowserGroup,
                            selectedItem: $selectedBrowserItem,
                            close: { showBrowser = false }
                        )
                        .environmentObject(plugins)
                        .frame(width: compact ? 214 : 238)
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
                        } else if activeWorkspace == "MIX" {
                            MixerView(
                                session: $document.session,
                                selectedTrackID: $selectedTrackID,
                                close: { activeWorkspace = "ARRANGE" }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ArrangementView(
                                session: $document.session,
                                selectedTrackID: $selectedTrackID,
                                currentStep: audio.currentStep,
                                isPlaying: audio.isPlaying,
                                openSnapMenu: { presentMenu(.arrangementSnap) },
                                requestAudioImport: { trackID, beat in
                                    presentAudioImporter(trackID: trackID, atBeat: beat)
                                },
                                previewAudioEvent: { clip in
                                    guard let path = clip.sourceRelativePath,
                                          let data = document.audioAssets[path] else {
                                        audioImportError = "This audio event's original file is missing from the project."
                                        return
                                    }
                                    audio.previewAudioEvent(clip, assetData: data, projectBPM: document.session.bpm)
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if showMixer {
                                MixerView(
                                    session: $document.session,
                                    selectedTrackID: $selectedTrackID,
                                    close: { showMixer = false }
                                )
                                .frame(height: compact ? 176 : 196)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showInspector && !compact {
                        InspectorPanel(track: selectedTrackBinding, close: { showInspector = false })
                            .frame(width: 286)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.16), value: showBrowser)
                .animation(.easeOut(duration: 0.16), value: showInspector)
                .animation(.easeOut(duration: 0.16), value: showMixer)

                    StatusBar(
                        error: audioImportError ?? audio.audioEventError ?? audio.startupError,
                        sampleRate: document.session.sampleRate,
                        bitDepth: document.session.bitDepth,
                        hiddenInspector: showInspector && compact
                    )
                }
                .background(LYLLTHTheme.background)

                workspaceMenuOverlay
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            selectedTrackID = selectedTrackID ?? document.session.tracks.first?.id
            audio.prepare(document.session)
            plugins.scan()
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

    private func presentMenu(_ menu: LYWorkspaceMenu) {
        withAnimation(.easeOut(duration: 0.14)) { activeMenu = menu }
    }

    private func dismissMenu() {
        withAnimation(.easeOut(duration: 0.14)) { activeMenu = nil }
    }

    @ViewBuilder
    private var workspaceMenuOverlay: some View {
        if let activeMenu {
            LYNightshapeMenuOverlay(dismiss: dismissMenu) {
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
    @EnvironmentObject private var audio: AudioEngineController
    let openSongKeyMenu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                // Same NIGHTSHAPE tie-dye + purple byline lockup as DRUMKIT's brand header.
                Text("LYLLTH")
                    .font(LYLLTHTheme.wordmark(36))
                    .tracking(2.1)
                    .hidden()
                    .overlay(
                        LYWordmarkTieDye().mask(
                            Text("LYLLTH")
                                .font(LYLLTHTheme.wordmark(36))
                                .tracking(2.1)
                        )
                    )
                    .offset(y: LYLLTHTheme.wordmarkOpticalDrop(36))
                    .shadow(color: LYLLTHTheme.teal.opacity(0.11), radius: 6)
                Text("BY NIGHTSHAPE")
                    .font(LYLLTHTheme.label(8.5))
                    .tracking(6.4)
                    .foregroundStyle(LYLLTHTheme.purple)
                    .padding(.leading, 3)
            }
            .frame(width: 218, alignment: .leading)

            LYHairline(color: LYLLTHTheme.lineStrong)
                .rotationEffect(.degrees(90))
                .frame(width: 28)

            HStack(spacing: 10) {
                Button { audio.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LYLLTHTheme.metadata)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))

                Button { audio.togglePlayback() } label: {
                    ZStack {
                        Circle()
                            .stroke(audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.lineFocused, lineWidth: 1)
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .medium))
                            .offset(x: audio.isPlaying ? 0 : 1)
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.chrome)
                .shadow(color: audio.isPlaying ? LYLLTHTheme.teal.opacity(0.14) : .clear, radius: 5)
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(audio.timecode)
                    .font(LYLLTHTheme.value(25))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.text)
                Text(audio.isPlaying ? "PLAYING" : "READY")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.dim)
            }
            .padding(.leading, 15)
            .frame(width: 145, alignment: .leading)

            TempoReadout(
                bpm: $session.bpm,
                numerator: session.numerator,
                denominator: session.denominator
            )
            .padding(.horizontal, 15)
            .frame(height: 50)
            .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }

            SongKeyReadout(
                key: Binding(
                    get: { session.songKey ?? .default },
                    set: { session.songKey = $0 }
                ),
                openMenu: openSongKeyMenu
            )
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }

            Spacer(minLength: 18)

            HStack(spacing: 6) {
                TransportUtility(
                    icon: "metronome",
                    title: "CLICK",
                    tint: LYLLTHTheme.teal,
                    isOn: audio.isMetronomeEnabled,
                    action: { audio.toggleMetronome(for: session) }
                )
                TransportUtility(icon: "repeat", title: "LOOP", isOn: true)
                TransportUtility(icon: "record.circle", title: "RECORD", tint: LYLLTHTheme.purple)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 86)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline(color: LYLLTHTheme.lineStrong) }
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
                            .foregroundStyle(root == key.root ? LYLLTHTheme.background : LYLLTHTheme.lavender)
                            .frame(width: 55, height: 37)
                            .background(root == key.root ? LYLLTHTheme.teal : LYLLTHTheme.panelRaised)
                            .overlay(Rectangle().stroke(root == key.root ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
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
        HStack(alignment: .center, spacing: 9) {
            Text("\(Int(bpm.rounded()))")
                .font(LYLLTHTheme.value(31))
                .foregroundStyle(LYLLTHTheme.lavender)
                .lineLimit(1)
                .frame(minWidth: 63, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text("BPM")
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.purple)
                Text("\(numerator) / \(denominator)")
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.teal)
            }
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
        .help("Drag vertically to adjust tempo")
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
    var tint = LYLLTHTheme.metadata
    var isOn = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2)
            }
            .foregroundStyle(isOn ? tint : LYLLTHTheme.metadata)
            .frame(width: 50, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workspace chrome

private struct WorkspaceStrip: View {
    @Binding var activeWorkspace: String
    @Binding var showBrowser: Bool
    @Binding var showInspector: Bool
    @Binding var showMixer: Bool
    let projectName: String
    let openTrackMenu: () -> Void

    private let workspaces = ["ARRANGE", "PATTERN", "MIX", "SYNTH"]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LYLED()
                mixedNumericLabel(
                    projectName,
                    labelFont: LYLLTHTheme.label(10, weight: .bold),
                    numberFont: LYLLTHTheme.value(10)
                )
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .frame(width: 218, alignment: .leading)

            HStack(spacing: 1) {
                ForEach(workspaces, id: \.self) { workspace in
                    Button(workspace) { activeWorkspace = workspace }
                        .buttonStyle(.plain)
                        .font(LYLLTHTheme.label(9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(activeWorkspace == workspace ? LYLLTHTheme.text : LYLLTHTheme.dim)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(activeWorkspace == workspace ? LYLLTHTheme.teal : .clear)
                                .frame(height: 1)
                        }
                }
            }

            Spacer()

            HStack(spacing: 3) {
                VisibilityButton(icon: "sidebar.left", help: "Library", isOn: $showBrowser)
                VisibilityButton(icon: "rectangle.bottomthird.inset.filled", help: "Mixer", isOn: $showMixer)
                VisibilityButton(icon: "sidebar.right", help: "Inspector", isOn: $showInspector)
                Button(action: openTrackMenu) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("TRACK")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .buttonStyle(LYChromeButtonStyle(compact: true))
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

}

private struct VisibilityButton: View {
    let icon: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? LYLLTHTheme.teal : LYLLTHTheme.dim)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Library

private struct BrowserPanel: View {
    @Binding var selection: String
    @Binding var selectedItem: String
    let close: () -> Void
    @EnvironmentObject private var plugins: AudioUnitCatalog
    @State private var query = ""

    private let groups = ["NIGHTSHAPE", "INSTRUMENTS", "EFFECTS", "PLUG-INS", "FILES"]
    private let nightshape = [
        "DRUM SYNTH", "SOUND ORACLE", "EQUALIZER", "COMPRESSOR", "TAPE SATURATION",
        "SONIC DECIMATOR", "CHORUS", "PLATE REVERB", "SIGNAL BLOOM", "PUMP",
        "VOID GATE", "FRACTURE", "FILTER", "DELAY", "DEADLOCK", "SHEAR",
        "STACK", "SPLIT FIELD", "UNDERTOW", "ANVIL", "STRIKE", "FINALE"
    ]

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "LIBRARY", actionIcon: "xmark", action: close)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LYLLTHTheme.dim)
                TextField("SEARCH", text: $query)
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(9))
                    .foregroundStyle(LYLLTHTheme.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .bottom) { LYHairline() }

            HStack(spacing: 2) {
                ForEach(groups, id: \.self) { group in
                    Button(shortName(group)) { selection = group }
                        .buttonStyle(.plain)
                        .font(LYLLTHTheme.label(7, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(selection == group ? LYLLTHTheme.text : LYLLTHTheme.dim)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == group ? LYLLTHTheme.teal : .clear)
                                .frame(height: 1)
                        }
                }
            }
            .padding(.horizontal, 7)
            .background(LYLLTHTheme.panel)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems, id: \.self) { item in
                        BrowserRow(
                            name: item,
                            detail: detail(for: item),
                            symbol: symbol(for: item),
                            isSelected: selectedItem == item
                        )
                        .onTapGesture { selectedItem = item }
                    }
                }
                .padding(.vertical, 5)
            }

            HStack(spacing: 8) {
                LYLED(color: plugins.isScanning ? LYLLTHTheme.indigo : LYLLTHTheme.teal, size: 4)
                (plugins.isScanning
                    ? Text("SCANNING").font(LYLLTHTheme.label(7, weight: .bold))
                    : mixedNumericLabel(
                        "\(plugins.instruments.count + plugins.effects.count) COMPONENTS",
                        labelFont: LYLLTHTheme.label(7, weight: .bold),
                        numberFont: LYLLTHTheme.value(8)
                    ))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .top) { LYHairline() }
        }
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
    }

    private var filteredItems: [String] {
        let values = items(for: selection)
        guard !query.isEmpty else { return values }
        return values.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func shortName(_ group: String) -> String {
        switch group {
        case "NIGHTSHAPE": return "NS"
        case "INSTRUMENTS": return "INST"
        case "PLUG-INS": return "PLUG"
        default: return group.prefix(4).uppercased()
        }
    }

    private func items(for group: String) -> [String] {
        switch group {
        case "NIGHTSHAPE": return nightshape
        case "INSTRUMENTS": return ["LYLLTH SYNTH", "DRUMKIT", "POLY SYNTH", "CHORD ENGINE"] + plugins.instruments.prefix(20).map(\.name)
        case "EFFECTS": return plugins.effects.prefix(30).map(\.name)
        case "PLUG-INS": return (plugins.instruments + plugins.effects).prefix(40).map(\.name)
        default: return ["SONGS", "RECORDED AUDIO", "IMPORTED AUDIO", "PATCHES", "WAVETABLES"]
        }
    }

    private func detail(for item: String) -> String {
        if nightshape.contains(item) || item == "LYLLTH SYNTH" || item == "DRUMKIT" { return "NIGHTSHAPE" }
        if selection == "FILES" { return "LOCAL + ICLOUD" }
        return selection == "INSTRUMENTS" ? "INSTRUMENT" : "AUDIO UNIT"
    }

    private func symbol(for item: String) -> String {
        if item.contains("SYNTH") || item == "DRUMKIT" { return "waveform.path" }
        if selection == "FILES" { return "folder" }
        if selection == "INSTRUMENTS" { return "pianokeys" }
        return "slider.horizontal.3"
    }
}

private struct BrowserRow: View {
    let name: String
    let detail: String
    let symbol: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(isSelected ? LYLLTHTheme.teal : LYLLTHTheme.dim)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(LYLLTHTheme.label(10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                    .lineLimit(1)
                Text(detail)
                    .font(LYLLTHTheme.label(7))
                    .tracking(0.8)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(isSelected ? LYLLTHTheme.metadata : LYLLTHTheme.off)
        }
        .padding(.horizontal, 11)
        .frame(height: 43)
        .background(isSelected ? LYLLTHTheme.panelRaised : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? LYLLTHTheme.teal : .clear).frame(width: 1)
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
                Button(action: addPattern) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(LYChromeButtonStyle(compact: true))
                .help("Add pattern")
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
        let accent = LYLLTHTheme.accent(track.accent)
        let clipIndex = activeClipIndex(trackIndex: trackIndex)
        let steps = clipIndex.flatMap { session.tracks[trackIndex].clips[$0].steps } ?? []
        let locks = clipIndex.flatMap { session.tracks[trackIndex].clips[$0].stepParameters } ?? []

        return HStack(spacing: gridGap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(selectedTrackID == track.id ? accent : LYLLTHTheme.lineFocused, lineWidth: 1)
                    Text("\((musicalTrackIndices.firstIndex(of: trackIndex) ?? 0) + 1)")
                        .font(LYLLTHTheme.value(9))
                        .foregroundStyle(selectedTrackID == track.id ? accent : LYLLTHTheme.metadata)
                }
                .frame(width: 25, height: 25)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(LYLLTHTheme.label(10, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    Text(track.isChordTrack == true ? "CHORD TRACK" : track.kind.label)
                        .font(LYLLTHTheme.label(7))
                        .tracking(1)
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 3)
                TrackStateButton(
                    title: "M",
                    isOn: trackStateBinding(trackIndex: trackIndex, keyPath: \.isMuted),
                    tint: LYLLTHTheme.purple
                )
                TrackStateButton(
                    title: "S",
                    isOn: trackStateBinding(trackIndex: trackIndex, keyPath: \.isSolo),
                    tint: LYLLTHTheme.teal
                )
            }
            .padding(.horizontal, 10)
            .frame(width: trackWidth, height: stepSide)
            .background(LYDrumKitGlassSurface())
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(selectedTrackID == track.id ? accent : accent.opacity(0.72), lineWidth: sequencerBorderWidth)
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
        session.tracks[trackIndex].clips.indices.filter {
            let kind = session.tracks[trackIndex].clips[$0].kind
            return kind == .pattern || kind == .midi
        }
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

    private func addPattern() {
        let newIndex = patternCount
        let count = stepCount
        for trackIndex in musicalTrackIndices {
            let track = session.tracks[trackIndex]
            let kind: LYClip.Kind = track.kind == .drumkit ? .pattern : .midi
            let prefix = track.isChordTrack == true ? "CHORD BED" : "PATTERN"
            session.tracks[trackIndex].clips.append(
                LYClip(
                    name: "\(prefix) \(String(format: "%02d", newIndex + 1))",
                    kind: kind,
                    startBeat: Double(newIndex * max(count / 4, 1)),
                    lengthBeats: Double(max(count / 4, 1)),
                    steps: Array(repeating: false, count: count),
                    stepParameters: Array(repeating: .default, count: count)
                )
            )
        }
        patternIndex = newIndex
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

// MARK: - Arrangement

private struct PlayheadHead: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: size.width, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: 12, height: 10)
    }
}

private struct ArrangementView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    let currentStep: Int
    let isPlaying: Bool
    let openSnapMenu: () -> Void
    let requestAudioImport: (UUID?, Double) -> Void
    let previewAudioEvent: (LYClip) -> Void

    private let headerWidth: CGFloat = 190
    private let beats = 64
    @State private var selectedClipID: UUID?
    @State private var pinchStartZoom: Double?
    @State private var viewportSize: CGSize = .zero
    @State private var editCursorBeat = 0.0
    @State private var copiedAudioEvent: LYClip?
    @State private var transportCycleStepOffset = 0
    @State private var transportStepBeganAt = Date()

    private var editor: LYArrangementEditorState {
        var value = session.arrangementEditor ?? .default
        value.normalize()
        return value
    }

    private var beatWidth: CGFloat { CGFloat(editor.horizontalZoom) }
    private var laneHeight: CGFloat { CGFloat(editor.verticalZoom) }

    private var beatsPerBar: Double {
        max(1, Double(session.numerator) * 4 / Double(max(session.denominator, 1)))
    }

    private var barCount: Int {
        Int(ceil(Double(beats) / beatsPerBar))
    }

    private var transportStepCount: Int {
        let patternIndex = max(0, session.activePatternIndex ?? 0)
        let counts = session.tracks.compactMap { track -> Int? in
            guard track.kind == .drumkit || track.kind == .instrument else { return nil }
            let sequenced = track.clips.filter { $0.kind == .pattern || $0.kind == .midi }
            guard !sequenced.isEmpty else { return nil }
            return sequenced[min(patternIndex, sequenced.count - 1)].steps?.count
        }
        return min(max(counts.max() ?? 16, 1), 64)
    }

    private var transportStepDuration: TimeInterval {
        let pulsesPerBar = session.numerator == 6 && session.denominator == 8
            ? 2.0
            : Double(max(session.numerator, 1))
        let subdivisionsPerBar = session.numerator == 6 && session.denominator == 8
            ? 12.0
            : Double(max(session.numerator, 1) * 4)
        return (60 / max(session.bpm, 1)) * pulsesPerBar / subdivisionsPerBar
    }

    private var arrangementPlayheads: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LYLLTHTheme.indigo.opacity(0.82))
                    .frame(width: 1, height: geometry.size.height)
                    .offset(x: headerWidth + CGFloat(editCursorBeat) * beatWidth)

                Rectangle()
                    .fill(LYLLTHTheme.indigo)
                    .frame(width: 7, height: 7)
                    .offset(x: headerWidth + CGFloat(editCursorBeat) * beatWidth - 3)

                if isPlaying {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let elapsed = max(0, timeline.date.timeIntervalSince(transportStepBeganAt))
                        let fraction = min(elapsed / max(transportStepDuration, 0.001), 0.999)
                        let absoluteStep = Double(transportCycleStepOffset + currentStep) + fraction
                        let beat = wrappedTransportBeat(for: absoluteStep)
                        let x = headerWidth + CGFloat(beat) * beatWidth

                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(LYLLTHTheme.teal)
                                .frame(width: 2, height: geometry.size.height)
                                .shadow(color: LYLLTHTheme.teal.opacity(0.25), radius: 2)
                                .offset(x: x - 1)

                            PlayheadHead(color: LYLLTHTheme.teal)
                                .offset(x: x - 6, y: 1)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wrappedTransportBeat(for absoluteStep: Double) -> Double {
        let absoluteBeat = absoluteStep * 0.25
        if let loop = session.loopRange, loop.lengthBeats > 0 {
            let relativeBeat = absoluteBeat - loop.startBeat
            let wrapped = relativeBeat.truncatingRemainder(dividingBy: loop.lengthBeats)
            return loop.startBeat + (wrapped >= 0 ? wrapped : wrapped + loop.lengthBeats)
        }
        let wrapped = absoluteBeat.truncatingRemainder(dividingBy: Double(beats))
        return wrapped >= 0 ? wrapped : wrapped + Double(beats)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARRANGEMENT")
                        .font(LYLLTHTheme.label(11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(LYLLTHTheme.secondary)
                    mixedNumericLabel(
                        "16 BARS  ·  LOOP 01–04",
                        labelFont: LYLLTHTheme.label(8),
                        numberFont: LYLLTHTheme.value(8)
                    )
                        .tracking(1.1)
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                Spacer()
                if selectedTrackKind == .audio {
                    Button("IMPORT AUDIO") {
                        requestAudioImport(selectedTrackID, editCursorBeat)
                    }
                    .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.purple, compact: true))
                    .help("Copy an audio file into this LYLLTH project at the edit cursor")
                }
                snapMenu
                autoZoomButton("H FIT", isOn: editor.autoHorizontalZoom) {
                    updateEditor { $0.autoHorizontalZoom.toggle() }
                    applyAutoZoom()
                }
                autoZoomButton("V FIT", isOn: editor.autoVerticalZoom) {
                    updateEditor { $0.autoVerticalZoom.toggle() }
                    applyAutoZoom()
                }
                ArrangementZoomControl(
                    axis: "H",
                    value: editorBinding(\.horizontalZoom),
                    range: 10...140
                )
                ArrangementZoomControl(
                    axis: "V",
                    value: editorBinding(\.verticalZoom),
                    range: 38...144
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(LYLLTHTheme.panel)
            .overlay(alignment: .bottom) { LYHairline() }

            audioEditStrip

            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ruler
                        ForEach($session.tracks) { $track in
                            trackLane(track: $track)
                        }
                        automationLane
                        addTrackLane
                    }
                    .frame(
                        minWidth: max(headerWidth + CGFloat(beats) * beatWidth, viewport.size.width),
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                    .overlay(alignment: .topLeading) {
                        arrangementPlayheads
                    }
                }
                .defaultScrollAnchor(.topLeading)
                .background(LYLLTHTheme.background)
                .simultaneousGesture(zoomGesture)
                .onAppear {
                    viewportSize = viewport.size
                    applyAutoZoom()
                }
                .onChange(of: viewport.size) { _, size in
                    viewportSize = size
                    applyAutoZoom()
                }
            }
        }
        .background {
            LYArrangementKeyMonitor(action: handleArrangementKey)
        }
        .onChange(of: currentStep) { oldStep, newStep in
            guard isPlaying else { return }
            if newStep < oldStep {
                transportCycleStepOffset += transportStepCount
            }
            transportStepBeganAt = Date()
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                transportCycleStepOffset = 0
                transportStepBeganAt = Date()
            }
        }
    }

    private var selectedAudioLocation: (track: Int, clip: Int)? {
        guard let selectedClipID else { return nil }
        for trackIndex in session.tracks.indices {
            if let clipIndex = session.tracks[trackIndex].clips.firstIndex(where: {
                $0.id == selectedClipID && $0.kind == .audio
            }) {
                return (trackIndex, clipIndex)
            }
        }
        return nil
    }

    private var selectedTrackKind: LYTrackKind? {
        guard let selectedTrackID else { return nil }
        return session.tracks.first(where: { $0.id == selectedTrackID })?.kind
    }

    private var selectedAudioClip: LYClip? {
        guard let location = selectedAudioLocation else { return nil }
        return session.tracks[location.track].clips[location.clip]
    }

    @ViewBuilder
    private var audioEditStrip: some View {
        if selectedAudioLocation != nil {
            audioEventInspector
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Rectangle().fill(LYLLTHTheme.purple).frame(width: 15, height: 1)
                    Text("AUDIO EDIT")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(LYLLTHTheme.secondary)
                    Text("SELECT AN AUDIO EVENT, THEN CLICK IT TO PLACE THE EDIT CURSOR")
                        .font(LYLLTHTheme.label(7))
                        .tracking(0.65)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 27)

                audioActionRow(selectionEnabled: false)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .bottom) { LYHairline() }
        }
    }

    private var audioEventInspector: some View {
        let clip = selectedAudioClip
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(LYLLTHTheme.purple).frame(width: 15, height: 1)
                Text("AUDIO EVENT")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.secondary)
                Text(clip?.name ?? "")
                    .font(LYLLTHTheme.label(8))
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(1)

                Spacer(minLength: 8)

                eventReadout("CURSOR", String(format: "%.3f", editCursorBeat))
                eventReadout("GAIN", gainText(clip?.eventGainDB ?? 0))
                eventReadout("PITCH", pitchText(clip?.pitchSemitones ?? 0))
                eventReadout("STRETCH", (clip?.stretchMode.rawValue ?? "off").uppercased())
            }
            .frame(height: 27)

            audioActionRow(selectionEnabled: true)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func audioActionRow(selectionEnabled: Bool) -> some View {
        HStack(spacing: 6) {
            Text(selectionEnabled ? "EDIT SELECTED EVENT" : "SELECT AN EVENT TO ENABLE EDITING")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(selectionEnabled ? LYLLTHTheme.metadata : LYLLTHTheme.dim)
                .lineLimit(1)
            Spacer(minLength: 8)
            eventActionButton("PREVIEW", help: "Render and audition this event with its gain, pitch, and stretch", enabled: selectionEnabled) {
                if let clip = selectedAudioClip { previewAudioEvent(clip) }
            }
            eventActionButton("SPLIT  S", help: "Split the selected event at the purple edit cursor", enabled: selectionEnabled && canSplitSelectedAudioEvent, action: splitSelectedAudioEvent)
            eventActionButton("CUT  ⌘X", help: "Cut event", enabled: selectionEnabled, action: cutSelectedAudioEvent)
            eventActionButton("COPY  ⌘C", help: "Copy event", enabled: selectionEnabled, action: copySelectedAudioEvent)
            eventActionButton("PASTE  ⌘V", help: "Paste at the edit cursor", enabled: copiedAudioEvent != nil && (selectionEnabled || selectedTrackKind == .audio), action: pasteAudioEvent)
            eventActionButton("DUPLICATE  ⌘D", help: "Duplicate directly after the event", enabled: selectionEnabled, action: duplicateSelectedAudioEvent)
            eventActionButton("DELETE", help: "Remove the selected event", enabled: selectionEnabled, action: deleteSelectedAudioEvent)
            eventActionButton("−", help: "Pitch down one semitone (-)", enabled: selectionEnabled) { transposeSelectedAudioEvent(by: -1) }
            eventActionButton("+", help: "Pitch up one semitone (=)", enabled: selectionEnabled) { transposeSelectedAudioEvent(by: 1) }
        }
        .frame(height: 30)
    }

    private func eventReadout(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(LYLLTHTheme.dim)
            Text(value)
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.metadata)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .overlay { Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1) }
    }

    private func eventActionButton(
        _ title: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(LYChromeButtonStyle(compact: true))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.38)
            .help(help)
    }

    private var canSplitSelectedAudioEvent: Bool {
        guard let clip = selectedAudioClip else { return false }
        let inset = max(0.001, 6 / Double(max(beatWidth, 1)))
        return editCursorBeat > clip.startBeat + inset
            && editCursorBeat < clip.startBeat + clip.lengthBeats - inset
    }

    private func handleArrangementKey(_ event: NSEvent) -> Bool {
        guard selectedAudioLocation != nil else { return false }
        if event.window?.firstResponder is NSTextView || event.window?.firstResponder is NSTextField {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch key {
            case "c": copySelectedAudioEvent(); return true
            case "x": cutSelectedAudioEvent(); return true
            case "v": pasteAudioEvent(); return true
            case "d": duplicateSelectedAudioEvent(); return true
            default: break
            }
        }

        if key == "\u{7F}" || key == "\u{8}" {
            deleteSelectedAudioEvent()
            return true
        }
        if key == "s", flags.isDisjoint(with: [.command, .option, .control]) {
            splitSelectedAudioEvent()
            return true
        }
        if key == "=" || key == "+" {
            transposeSelectedAudioEvent(by: pitchIncrement(for: flags))
            return true
        }
        if key == "-" || key == "_" {
            transposeSelectedAudioEvent(by: -pitchIncrement(for: flags))
            return true
        }
        if key == "/" {
            adjustSelectedAudioGain(increase: false, flags: flags)
            return true
        }
        if key == "*" {
            adjustSelectedAudioGain(increase: true, flags: flags)
            return true
        }
        return false
    }

    private func pitchIncrement(for flags: NSEvent.ModifierFlags) -> Double {
        if flags.contains(.command) && flags.contains(.shift) { return 0 }
        if flags.contains(.command) { return 12 }
        if flags.contains(.shift) { return 4 }
        return 1
    }

    private func updateSelectedAudioEvent(_ update: (inout LYClip) -> Void) {
        guard let location = selectedAudioLocation else { return }
        update(&session.tracks[location.track].clips[location.clip])
        session.tracks[location.track].clips[location.clip].normalizeAudioEvent()
    }

    private func transposeSelectedAudioEvent(by semitones: Double) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) && flags.contains(.shift) {
            updateSelectedAudioEvent { $0.pitchSemitones = 0 }
        } else {
            updateSelectedAudioEvent { $0.pitchSemitones += semitones }
        }
    }

    private func adjustSelectedAudioGain(increase: Bool, flags: NSEvent.ModifierFlags) {
        if flags.contains(.command) && flags.contains(.shift) {
            updateSelectedAudioEvent { $0.eventGainDB = increase ? 0 : -60 }
            return
        }
        let increment: Double
        if flags.contains(.command) {
            increment = 0.25
        } else if flags.contains(.shift) {
            increment = 0.10
        } else {
            increment = 0.01
        }
        updateSelectedAudioEvent { clip in
            let amplitude = clip.eventGainDB <= -59.95 ? 0 : pow(10, clip.eventGainDB / 20)
            let adjusted = min(max(amplitude + (increase ? increment : -increment), 0), 3.981_071_706)
            clip.eventGainDB = adjusted <= 0 ? -60 : 20 * log10(adjusted)
        }
    }

    private func copySelectedAudioEvent() {
        copiedAudioEvent = selectedAudioClip
    }

    private func cutSelectedAudioEvent() {
        copySelectedAudioEvent()
        deleteSelectedAudioEvent()
    }

    private func pasteAudioEvent() {
        guard let source = copiedAudioEvent else { return }
        let trackIndex = selectedAudioLocation?.track
            ?? session.tracks.firstIndex(where: { $0.id == selectedTrackID && $0.kind == .audio })
            ?? session.tracks.firstIndex(where: { $0.kind == .audio })
        guard let trackIndex else { return }
        let copy = LYAudioEventEditor.duplicate(source, atBeat: snapBeat(editCursorBeat, editCursorBeat))
        session.tracks[trackIndex].clips.append(copy)
        selectedTrackID = session.tracks[trackIndex].id
        selectedClipID = copy.id
    }

    private func duplicateSelectedAudioEvent() {
        guard let location = selectedAudioLocation else { return }
        let original = session.tracks[location.track].clips[location.clip]
        let copy = LYAudioEventEditor.duplicate(original)
        session.tracks[location.track].clips.insert(copy, at: location.clip + 1)
        selectedClipID = copy.id
        editCursorBeat = copy.startBeat
    }

    private func splitSelectedAudioEvent() {
        guard let location = selectedAudioLocation else { return }
        let original = session.tracks[location.track].clips[location.clip]
        let beat = snapBeat(editCursorBeat, editCursorBeat)
        guard let split = LYAudioEventEditor.split(original, atBeat: beat) else { return }
        session.tracks[location.track].clips.replaceSubrange(
            location.clip...location.clip,
            with: [split.left, split.right]
        )
        selectedClipID = split.right.id
    }

    private func deleteSelectedAudioEvent() {
        guard let location = selectedAudioLocation else { return }
        session.tracks[location.track].clips.remove(at: location.clip)
        selectedClipID = nil
    }

    private func gainText(_ value: Double) -> String {
        value <= -59.95 ? "−∞ dB" : String(format: "%+.1f dB", value)
    }

    private func pitchText(_ value: Double) -> String {
        abs(value) < 0.001 ? "0 st" : String(format: "%+.0f st", value)
    }

    private var snapMenu: some View {
        Button(action: openSnapMenu) {
            HStack(spacing: 5) {
                Text(editor.snapMode.label)
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(0.8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(editor.snapMode == .off ? LYLLTHTheme.dim : LYLLTHTheme.teal)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .overlay { Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Arrangement snap mode and absolute/relative behavior")
    }

    private func autoZoomButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(LYChromeButtonStyle(active: isOn, compact: true))
    }

    private func editorBinding(_ keyPath: WritableKeyPath<LYArrangementEditorState, Double>) -> Binding<Double> {
        Binding(
            get: { editor[keyPath: keyPath] },
            set: { value in
                updateEditor {
                    $0[keyPath: keyPath] = value
                    if keyPath == \.horizontalZoom { $0.autoHorizontalZoom = false }
                    if keyPath == \.verticalZoom { $0.autoVerticalZoom = false }
                }
            }
        )
    }

    private func updateEditor(_ update: (inout LYArrangementEditorState) -> Void) {
        var value = session.arrangementEditor ?? .default
        update(&value)
        value.normalize()
        session.arrangementEditor = value
    }

    private func applyAutoZoom() {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        updateEditor { value in
            if value.autoHorizontalZoom {
                value.horizontalZoom = Double(max(10, (viewportSize.width - headerWidth) / CGFloat(beats)))
            }
            if value.autoVerticalZoom {
                let usable = max(38, viewportSize.height - 30 - 36 - 44)
                value.verticalZoom = Double(max(38, usable / CGFloat(max(session.tracks.count, 1))))
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let vertical = NSEvent.modifierFlags.contains(.option)
                let baseline = pinchStartZoom ?? (vertical ? editor.verticalZoom : editor.horizontalZoom)
                if pinchStartZoom == nil { pinchStartZoom = baseline }
                updateEditor { value in
                    if vertical {
                        value.autoVerticalZoom = false
                        value.verticalZoom = baseline * Double(scale)
                    } else {
                        value.autoHorizontalZoom = false
                        value.horizontalZoom = baseline * Double(scale)
                    }
                }
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    private var ruler: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
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
            .frame(width: headerWidth, height: 30)
            .background(LYLLTHTheme.deck)

            HStack(spacing: 0) {
                ForEach(0..<barCount, id: \.self) { bar in
                    Text("\(bar + 1)")
                        .font(LYLLTHTheme.value(8))
                        .foregroundStyle(bar < 4 ? LYLLTHTheme.secondary : LYLLTHTheme.dim)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .frame(width: beatWidth * beatsPerBar, height: 30, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(bar % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line).frame(width: 1)
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = Double(value.location.x / max(beatWidth, 1))
                        editCursorBeat = min(max(0, snapBeat(raw, raw)), Double(beats))
                    }
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LYLLTHTheme.teal.opacity(0.5))
                    .frame(width: beatWidth * CGFloat(session.loopRange?.lengthBeats ?? 16), height: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func trackLane(track: Binding<LYTrack>) -> some View {
        let selected = selectedTrackID == track.wrappedValue.id
        let accent = LYLLTHTheme.accent(track.wrappedValue.accent)

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(selected ? accent : LYLLTHTheme.lineFocused, lineWidth: 1)
                    Text(String(trackNumber(track.wrappedValue.id)))
                        .font(LYLLTHTheme.value(9))
                        .foregroundStyle(selected ? accent : LYLLTHTheme.metadata)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.wrappedValue.name)
                        .font(LYLLTHTheme.label(11, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    Text(track.wrappedValue.kind.label)
                        .font(LYLLTHTheme.label(7))
                        .tracking(1.1)
                        .foregroundStyle(selected ? accent : LYLLTHTheme.dim)
                }
                Spacer(minLength: 4)
                TrackStateButton(title: "M", isOn: track.isMuted, tint: LYLLTHTheme.purple)
                TrackStateButton(title: "S", isOn: track.isSolo, tint: LYLLTHTheme.teal)
            }
            .padding(.horizontal, 10)
            .frame(width: headerWidth, height: laneHeight)
            .background(selected ? LYLLTHTheme.panelRaised : LYLLTHTheme.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? accent.opacity(0.72) : .clear).frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedTrackID = track.wrappedValue.id }

            ZStack(alignment: .leading) {
                BeatGrid(
                    beats: beats,
                    beatWidth: beatWidth,
                    height: laneHeight,
                    beatsPerBar: beatsPerBar,
                    subdivisionBeats: displayGridBeats,
                    showsGrid: editor.showsGrid
                )

                ForEach(track.clips) { $clip in
                    ArrangementClip(
                        clip: $clip,
                        accent: accent,
                        isFocused: selectedClipID == clip.id || selected,
                        beatWidth: beatWidth,
                        laneHeight: laneHeight,
                        projectBPM: session.bpm,
                        maximumBeat: Double(beats),
                        snap: snapBeat
                    )
                    .frame(
                        width: max(beatWidth * clip.lengthBeats - 4, 28),
                        height: max(30, laneHeight - 18)
                    )
                    .offset(x: beatWidth * clip.startBeat + 2)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                selectedTrackID = track.wrappedValue.id
                                selectedClipID = clip.id
                                let localBeat = Double(value.location.x / max(beatWidth, 1))
                                let rawBeat = clip.startBeat + localBeat
                                editCursorBeat = min(
                                    max(0, snapBeat(rawBeat, clip.startBeat)),
                                    Double(beats)
                                )
                            }
                    )
                }

            }
            .frame(width: CGFloat(beats) * beatWidth, height: laneHeight)
        }
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private var automationLane: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(LYLLTHTheme.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUTOMATION")
                        .font(LYLLTHTheme.label(9, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.secondary)
                    Text("DARK POLY · CUTOFF")
                        .font(LYLLTHTheme.label(7))
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(width: headerWidth, height: 44)
            .background(LYLLTHTheme.panel)

            BeatGrid(
                beats: beats,
                beatWidth: beatWidth,
                height: 44,
                beatsPerBar: beatsPerBar,
                subdivisionBeats: displayGridBeats,
                showsGrid: editor.showsGrid
            )
                .overlay(alignment: .leading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 34))
                        path.addCurve(
                            to: CGPoint(x: beatWidth * 24, y: 9),
                            control1: CGPoint(x: beatWidth * 7, y: 34),
                            control2: CGPoint(x: beatWidth * 15, y: 7)
                        )
                    }
                    .stroke(LYLLTHTheme.purple.opacity(0.82), lineWidth: 1.2)
                }
                .frame(width: CGFloat(beats) * beatWidth, height: 44)
        }
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private var addTrackLane: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .medium))
            Text("ADD TRACK")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.2)
        }
        .foregroundStyle(LYLLTHTheme.dim)
        .padding(.leading, 14)
        .frame(width: headerWidth, height: 36, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LYLLTHTheme.deck)
    }

    private func trackNumber(_ id: UUID) -> Int {
        (session.tracks.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    private var displayGridBeats: Double? {
        let grid = editor.gridBeats(
            bpm: session.bpm,
            numerator: session.numerator,
            denominator: session.denominator,
            sampleRate: session.sampleRate,
            beatWidth: Double(beatWidth)
        )
        guard let grid, grid * Double(beatWidth) >= 6 else { return nil }
        return grid
    }

    private func snapBeat(_ rawBeat: Double, _ originalBeat: Double) -> Double {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return max(0, rawBeat) }
        let override: LYArrangementSnapMode?
        if flags.contains(.control) {
            override = .division
        } else {
            override = nil
        }
        return editor.snap(
            rawBeat: rawBeat,
            originalBeat: originalBeat,
            bpm: session.bpm,
            numerator: session.numerator,
            denominator: session.denominator,
            sampleRate: session.sampleRate,
            beatWidth: Double(beatWidth),
            overrideMode: override
        )
    }
}

private struct ArrangementZoomControl: View {
    let axis: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 5) {
            Text(axis)
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.dim)
            Slider(value: $value, in: range)
                .controlSize(.mini)
                .frame(width: 58)
                .tint(LYLLTHTheme.indigo)
        }
        .help(axis == "H" ? "Horizontal zoom" : "Vertical track zoom; Option-pinch also adjusts this")
    }
}

private struct TrackStateButton: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button(title) { isOn.toggle() }
            .buttonStyle(.plain)
            .font(LYLLTHTheme.label(7, weight: .bold))
            .foregroundStyle(isOn ? tint : LYLLTHTheme.dim)
            .frame(width: 17, height: 20)
    }
}

private struct BeatGrid: View {
    let beats: Int
    let beatWidth: CGFloat
    let height: CGFloat
    let beatsPerBar: Double
    let subdivisionBeats: Double?
    let showsGrid: Bool

    var body: some View {
        Canvas { context, size in
            let totalWidth = CGFloat(beats) * beatWidth
            let barWidth = CGFloat(beatsPerBar) * beatWidth
            let bars = max(1, Int(ceil(Double(beats) / beatsPerBar)))

            context.fill(Path(CGRect(x: 0, y: 0, width: totalWidth, height: height)), with: .color(LYLLTHTheme.background))
            for bar in 0..<bars where bar.isMultiple(of: 2) == false {
                let x = CGFloat(bar) * barWidth
                context.fill(
                    Path(CGRect(x: x, y: 0, width: min(barWidth, totalWidth - x), height: height)),
                    with: .color(LYLLTHTheme.deck.opacity(0.72))
                )
            }

            guard showsGrid else { return }
            for beat in 0...beats {
                let x = CGFloat(beat) * beatWidth
                let isBar = abs(Double(beat).truncatingRemainder(dividingBy: beatsPerBar)) < 0.0001
                context.fill(
                    Path(CGRect(x: floor(x), y: 0, width: 1, height: height)),
                    with: .color(isBar ? LYLLTHTheme.lineStrong : LYLLTHTheme.line)
                )
            }

            if let subdivisionBeats, subdivisionBeats < 1 {
                let divisionWidth = CGFloat(subdivisionBeats) * beatWidth
                guard divisionWidth >= 6 else { return }
                let count = Int(ceil(Double(beats) / subdivisionBeats))
                for division in 0...count {
                    let beat = Double(division) * subdivisionBeats
                    if abs(beat.rounded() - beat) < 0.0001 { continue }
                    let x = CGFloat(beat) * beatWidth
                    context.fill(
                        Path(CGRect(x: floor(x), y: 0, width: 0.5, height: height)),
                        with: .color(LYLLTHTheme.line.opacity(0.58))
                    )
                }
            }
        }
        .frame(width: CGFloat(beats) * beatWidth, height: height)
    }
}

private struct ArrangementClip: View {
    @Binding var clip: LYClip
    let accent: Color
    let isFocused: Bool
    let beatWidth: CGFloat
    let laneHeight: CGFloat
    let projectBPM: Double
    let maximumBeat: Double
    let snap: (Double, Double) -> Double

    @State private var moveOrigin: Double?
    @State private var movePreviewBeat: Double?
    @State private var leftTrimOrigin: (start: Double, length: Double, sourceStart: Double, sourceDuration: Double?)?
    @State private var rightTrimOrigin: (length: Double, sourceDuration: Double?)?
    @State private var slipOriginSeconds: Double?
    @State private var slipPreviewSeconds: Double?
    @State private var gainOriginDB: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(LYLLTHTheme.panelRaised.opacity(0.94))
            Rectangle().fill(accent.opacity(isFocused ? 0.105 : 0.065))
            Rectangle().stroke(accent.opacity(isFocused ? 0.9 : 0.52), lineWidth: 1)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    LYLED(color: accent, size: 4)
                    Text(clip.name)
                        .font(LYLLTHTheme.label(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                }

                if clip.kind == .audio {
                    MiniWaveform(values: clip.waveformPeaks ?? [], color: accent)
                        .opacity(max(0.15, min(1, pow(10, clip.eventGainDB / 20))))
                        .frame(height: 13)
                } else {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<previewCount, id: \.self) { index in
                            Rectangle()
                                .fill(isActive(index) ? accent : LYLLTHTheme.lineStrong)
                                .frame(width: 3, height: CGFloat(4 + (index % 4) * 2))
                        }
                    }
                    .frame(height: 12, alignment: .bottom)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                trimHandle(edge: .leading)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(moveGesture)
                trimHandle(edge: .trailing)
            }

            if clip.kind == .audio {
                audioEventOverlay
            }
        }
        .contentShape(Rectangle())
        .offset(x: moveVisualOffset)
        .shadow(
            color: movePreviewBeat == nil ? .clear : accent.opacity(0.18),
            radius: movePreviewBeat == nil ? 0 : 4
        )
        .overlay(alignment: .topTrailing) {
            if let movePreviewBeat {
                Text(String(format: "BEAT %.2f", movePreviewBeat + 1))
                    .font(LYLLTHTheme.value(7))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(LYLLTHTheme.background.opacity(0.9))
                    .overlay { Rectangle().stroke(accent.opacity(0.55), lineWidth: 1) }
                    .padding(4)
            } else if let slipPreviewSeconds {
                Text(String(format: "SLIP %+.3f s", slipPreviewSeconds))
                    .font(LYLLTHTheme.value(7))
                    .foregroundStyle(LYLLTHTheme.indigo)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(LYLLTHTheme.background.opacity(0.9))
                    .overlay { Rectangle().stroke(LYLLTHTheme.indigo.opacity(0.55), lineWidth: 1) }
                    .padding(4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clip.kind == .audio ? "Audio event \(clip.name)" : "Region \(clip.name)")
        .accessibilityValue(accessibilityDescription)
        .accessibilityIdentifier("arrangement-clip-\(clip.id.uuidString)")
        .help("Drag smoothly to move; snap is applied when released. Option-drag slips source audio. Drag edges to trim. Shift temporarily disables snap. Drag the gain line down to reduce event volume.")
    }

    private var accessibilityDescription: String {
        let location = String(format: "beat %.2f", clip.startBeat + 1)
        let duration = String(format: "%.2f beats", clip.lengthBeats)
        guard clip.kind == .audio else {
            return "\(location), \(duration)"
        }

        let gain = clip.eventGainDB <= -59.95
            ? "minus infinity decibels"
            : String(format: "%+.1f decibels", clip.eventGainDB)
        let pitch = String(format: "%+.0f semitones", clip.pitchSemitones)
        return "\(location), \(duration), \(gain), \(pitch)"
    }

    private var audioEventOverlay: some View {
        GeometryReader { geometry in
            let y = gainLineY(height: geometry.size.height)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(accent.opacity(isFocused ? 0.94 : 0.68))
                    .frame(height: 1)
                    .offset(y: y)

                HStack(spacing: 5) {
                    if abs(clip.eventGainDB) >= 0.05 {
                        Text(clip.eventGainDB <= -59.95 ? "−∞ dB" : String(format: "%+.1f dB", clip.eventGainDB))
                            .font(LYLLTHTheme.value(7))
                            .foregroundStyle(accent)
                    }
                    if abs(clip.pitchSemitones) >= 0.05 {
                        Text(String(format: "%+.0f st", clip.pitchSemitones))
                            .font(LYLLTHTheme.value(7))
                            .foregroundStyle(LYLLTHTheme.indigo)
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 11)
                .background(LYLLTHTheme.background.opacity(0.78))
                .offset(x: 9, y: min(max(1, y + 2), max(1, geometry.size.height - 12)))
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 13)
                    .offset(y: min(max(0, y - 6), max(0, geometry.size.height - 13)))
                    .contentShape(Rectangle())
                    .highPriorityGesture(gainGesture(height: geometry.size.height))
            }
        }
    }

    private func gainLineY(height: CGFloat) -> CGFloat {
        let normalized = CGFloat((12 - min(max(clip.eventGainDB, -60), 12)) / 72)
        return 4 + normalized * max(1, height - 8)
    }

    private func gainGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = gainOriginDB ?? clip.eventGainDB
                if gainOriginDB == nil { gainOriginDB = origin }
                let sensitivity = NSEvent.modifierFlags.contains(.control) ? 0.2 : 1.0
                let delta = -Double(value.translation.height / max(height - 8, 1)) * 72 * sensitivity
                clip.eventGainDB = min(max(origin + delta, -60), 12)
            }
            .onEnded { _ in gainOriginDB = nil }
    }

    private var previewCount: Int { min(16, clip.steps?.count ?? 16) }

    private func isActive(_ index: Int) -> Bool {
        guard let steps = clip.steps, steps.indices.contains(index) else { return index % 3 == 0 }
        return steps[index]
    }

    private enum TrimEdge { case leading, trailing }

    @ViewBuilder
    private func trimHandle(edge: TrimEdge) -> some View {
        if edge == .leading {
            trimHandleBody.highPriorityGesture(leftTrimGesture)
        } else {
            trimHandleBody.highPriorityGesture(rightTrimGesture)
        }
    }

    private var trimHandleBody: some View {
        Rectangle()
            .fill(isFocused ? accent.opacity(0.28) : Color.clear)
            .frame(width: 7)
            .overlay {
                Rectangle()
                    .fill(isFocused ? accent.opacity(0.82) : Color.clear)
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if clip.kind == .audio, NSEvent.modifierFlags.contains(.option) {
                    let origin = slipOriginSeconds ?? clip.slipOffsetSeconds
                    if slipOriginSeconds == nil { slipOriginSeconds = origin }
                    let secondsPerBeat = 60 / max(projectBPM, 1)
                    slipPreviewSeconds = origin + Double(value.translation.width / beatWidth) * secondsPerBeat
                    return
                }
                let origin = moveOrigin ?? clip.startBeat
                if moveOrigin == nil { moveOrigin = origin }
                let raw = origin + Double(value.translation.width / beatWidth)
                movePreviewBeat = min(max(0, raw), max(0, maximumBeat - clip.lengthBeats))
            }
            .onEnded { _ in
                if let slipPreviewSeconds {
                    clip.slipOffsetSeconds = slipPreviewSeconds
                } else if let movePreviewBeat, let moveOrigin {
                    let snapped = snap(movePreviewBeat, moveOrigin)
                    clip.startBeat = min(max(0, snapped), max(0, maximumBeat - clip.lengthBeats))
                }
                moveOrigin = nil
                movePreviewBeat = nil
                slipOriginSeconds = nil
                slipPreviewSeconds = nil
            }
    }

    private var moveVisualOffset: CGFloat {
        guard let movePreviewBeat else { return 0 }
        return CGFloat(movePreviewBeat - clip.startBeat) * beatWidth
    }

    private var leftTrimGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = leftTrimOrigin ?? (
                    clip.startBeat,
                    clip.lengthBeats,
                    clip.sourceStartSeconds,
                    clip.sourceDurationSeconds
                )
                if leftTrimOrigin == nil { leftTrimOrigin = origin }
                let end = origin.start + origin.length
                let raw = origin.start + Double(value.translation.width / beatWidth)
                let snapped = min(snap(raw, origin.start), end - minimumLength)
                clip.startBeat = max(0, snapped)
                clip.lengthBeats = max(minimumLength, end - clip.startBeat)
                if clip.kind == .audio, let sourceDuration = origin.sourceDuration {
                    let originalSecondsPerBeat = sourceDuration / max(origin.length, 0.001)
                    let trimmedBeats = clip.startBeat - origin.start
                    clip.sourceStartSeconds = origin.sourceStart + max(0, trimmedBeats) * originalSecondsPerBeat
                    clip.sourceDurationSeconds = max(0.001, sourceDuration - max(0, trimmedBeats) * originalSecondsPerBeat)
                }
            }
            .onEnded { _ in leftTrimOrigin = nil }
    }

    private var rightTrimGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = rightTrimOrigin ?? (clip.lengthBeats, clip.sourceDurationSeconds)
                if rightTrimOrigin == nil { rightTrimOrigin = origin }
                let originalLength = origin.length
                let originalEnd = clip.startBeat + originalLength
                let rawEnd = originalEnd + Double(value.translation.width / beatWidth)
                let snappedEnd = snap(rawEnd, originalEnd)
                clip.lengthBeats = min(
                    max(minimumLength, snappedEnd - clip.startBeat),
                    max(minimumLength, maximumBeat - clip.startBeat)
                )
                if clip.kind == .audio, let sourceDuration = origin.sourceDuration {
                    clip.sourceDurationSeconds = max(
                        0.001,
                        sourceDuration * (clip.lengthBeats / max(originalLength, 0.001))
                    )
                }
            }
            .onEnded { _ in rightTrimOrigin = nil }
    }

    private var minimumLength: Double {
        max(0.001, 6 / Double(max(beatWidth, 1)))
    }
}

private struct MiniWaveform: View {
    let values: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let displayValues: [CGFloat] = values.isEmpty
                    ? [0.10, 0.38, 0.74, 0.31, 0.62, 0.92, 0.45, 0.66, 0.22, 0.48, 0.79, 0.34, 0.58, 0.17, 0.42]
                    : values.map(CGFloat.init)
                let step = geometry.size.width / CGFloat(max(displayValues.count - 1, 1))
                for (index, value) in displayValues.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step, y: geometry.size.height * (1 - value))
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
            }
            .stroke(color.opacity(0.82), lineWidth: 1)
        }
    }
}

// MARK: - Mixer

private struct MixerView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "MIX", detail: "SIGNAL / LEVEL", actionIcon: "chevron.down", action: close)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach($session.tracks) { $track in
                        MixerChannel(track: $track, isSelected: selectedTrackID == track.id)
                            .onTapGesture { selectedTrackID = track.id }
                    }
                    MainChannel()
                }
            }
            .background(LYLLTHTheme.deck)
        }
        .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1) }
    }
}

private struct MixerChannel: View {
    @Binding var track: LYTrack
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                Text(track.kind.label)
                    .font(LYLLTHTheme.label(7))
                    .tracking(0.9)
                    .foregroundStyle(isSelected ? LYLLTHTheme.accent(track.accent) : LYLLTHTheme.dim)
                Spacer()
                HStack(spacing: 5) {
                    MixerToggle(title: "M", isOn: $track.isMuted, tint: LYLLTHTheme.purple)
                    MixerToggle(title: "S", isOn: $track.isSolo, tint: LYLLTHTheme.teal)
                }
                Text(String(format: "%+.1f dB", track.volumeDB))
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.metadata)
            }
            .frame(width: 74, alignment: .leading)

            StereoMeter(level: meterLevel)
                .frame(width: 10, height: 82)

            LYVerticalFader(value: $track.volumeDB, range: -48...6)
                .frame(width: 28, height: 91)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 156)
        .background(isSelected ? LYLLTHTheme.panelRaised : LYLLTHTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? LYLLTHTheme.accent(track.accent) : .clear)
                .frame(height: 1)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.line).frame(width: 1) }
    }

    private var meterLevel: Double {
        min(max((track.volumeDB + 48) / 54 * 0.7, 0.08), 0.78)
    }
}

private struct MainChannel: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAIN")
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                Text("MASTER")
                    .font(LYLLTHTheme.label(7))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.teal)
                Spacer()
                Text("−6.2 dB")
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.metadata)
            }
            StereoMeter(level: 0.68, tint: LYLLTHTheme.teal)
                .frame(width: 18, height: 88)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 124)
        .background(LYLLTHTheme.background)
        .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.teal.opacity(0.65)).frame(width: 1) }
    }
}

private struct MixerToggle: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button(title) { isOn.toggle() }
            .buttonStyle(.plain)
            .font(LYLLTHTheme.label(8, weight: .bold))
            .foregroundStyle(isOn ? tint : LYLLTHTheme.dim)
            .frame(width: 24, height: 21)
            .overlay(Rectangle().stroke(isOn ? tint.opacity(0.8) : LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

private struct StereoMeter: View {
    let level: Double
    var tint = LYLLTHTheme.indigo

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach([0.93, 1.0], id: \.self) { multiplier in
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(LYLLTHTheme.off.opacity(0.7))
                        Rectangle()
                            .fill(tint.opacity(0.88))
                            .frame(height: geometry.size.height * min(level * multiplier, 1))
                    }
                }
            }
        }
    }
}

private struct LYVerticalFader: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = (1 - fraction) * (geometry.size.height - 14) + 7

            ZStack {
                Rectangle()
                    .fill(LYLLTHTheme.lineStrong)
                    .frame(width: 1)
                Rectangle()
                    .fill(LYLLTHTheme.chrome)
                    .frame(width: 18, height: 5)
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineFocused, lineWidth: 1))
                    .position(x: geometry.size.width / 2, y: y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let normalized = min(max(1 - gesture.location.y / geometry.size.height, 0), 1)
                        value = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

// MARK: - Inspector

private struct InspectorPanel: View {
    var track: Binding<LYTrack>?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "INSPECT", actionIcon: "xmark", action: close)
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.wrappedValue.name)
                                .font(LYLLTHTheme.label(22, weight: .light))
                                .tracking(0.8)
                                .foregroundStyle(LYLLTHTheme.text)
                            HStack(spacing: 8) {
                                LYLED(color: LYLLTHTheme.accent(track.wrappedValue.accent), size: 4)
                                Text(track.wrappedValue.kind.label)
                                    .font(LYLLTHTheme.label(8, weight: .bold))
                                    .tracking(1.4)
                                    .foregroundStyle(LYLLTHTheme.metadata)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 15)

                        LYHairline()

                        HStack(spacing: 24) {
                            LYKnob(
                                value: track.volumeDB,
                                range: -48...6,
                                title: "LEVEL",
                                valueText: String(format: "%+.1f", track.wrappedValue.volumeDB),
                                tint: LYLLTHTheme.teal
                            )
                            LYKnob(
                                value: track.pan,
                                range: -1...1,
                                title: "PAN",
                                valueText: panText(track.wrappedValue.pan),
                                tint: LYLLTHTheme.indigo
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)

                        LYHairline()

                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("SIGNAL CHAIN")
                                    .font(LYLLTHTheme.label(9, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(LYLLTHTheme.secondary)
                                Spacer()
                                Text("PRE FADER")
                                    .font(LYLLTHTheme.label(7))
                                    .tracking(0.8)
                                    .foregroundStyle(LYLLTHTheme.dim)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 38)

                            if track.wrappedValue.inserts.isEmpty {
                                EmptyInsertRow()
                            } else {
                                ForEach(Array(track.wrappedValue.inserts.enumerated()), id: \.element.id) { index, insert in
                                    InsertRow(slot: insert, number: index + 1)
                                }
                            }

                            EmptyInsertRow()
                        }

                        LYHairline()

                        VStack(alignment: .leading, spacing: 12) {
                            InspectorMetric(title: "INPUT", value: track.wrappedValue.inputName ?? "INTERNAL")
                            InspectorMetric(title: "OUTPUT", value: "MAIN")
                            InspectorMetric(title: "CHANNEL", value: "STEREO")
                        }
                        .padding(16)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .ultraLight))
                    Text("SELECT A TRACK")
                        .font(LYLLTHTheme.label(9, weight: .bold))
                        .tracking(1.4)
                }
                .foregroundStyle(LYLLTHTheme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
    }

    private func panText(_ pan: Double) -> String {
        if abs(pan) < 0.01 { return "C" }
        return pan < 0 ? "L\(Int(abs(pan) * 100))" : "R\(Int(abs(pan) * 100))"
    }
}

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

private struct InsertRow: View {
    let slot: LYPluginSlot
    let number: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", number))
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.dim)
            LYLED(color: LYLLTHTheme.teal, isOn: !slot.isBypassed, size: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .foregroundStyle(slot.isBypassed ? LYLLTHTheme.dim : LYLLTHTheme.secondary)
                    .lineLimit(1)
                Text(slot.manufacturer)
                    .font(LYLLTHTheme.label(7))
                    .tracking(0.8)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            Text(slot.isBypassed ? "OFF" : "ON")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .foregroundStyle(slot.isBypassed ? LYLLTHTheme.dim : LYLLTHTheme.teal)
        }
        .padding(.horizontal, 16)
        .frame(height: 47)
        .background(LYLLTHTheme.deck.opacity(0.52))
        .overlay(alignment: .bottom) { LYHairline() }
    }
}

private struct EmptyInsertRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .medium))
            Text("ADD INSERT")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.1)
        }
        .foregroundStyle(LYLLTHTheme.dim)
        .padding(.horizontal, 16)
        .frame(height: 39, alignment: .leading)
    }
}

private struct InspectorMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(LYLLTHTheme.dim)
            Spacer()
            Text(value)
                .font(LYLLTHTheme.label(9, weight: .bold))
                .foregroundStyle(LYLLTHTheme.metadata)
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
