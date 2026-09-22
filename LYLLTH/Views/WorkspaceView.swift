import SwiftUI

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

            VStack(spacing: 0) {
                TransportBar(session: $document.session)
                    .environmentObject(audio)

                WorkspaceStrip(
                    activeWorkspace: $activeWorkspace,
                    showBrowser: $showBrowser,
                    showInspector: $showInspector,
                    showMixer: $showMixer,
                    projectName: document.session.name
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
                        ArrangementView(
                            session: $document.session,
                            selectedTrackID: $selectedTrackID,
                            currentStep: audio.currentStep,
                            isPlaying: audio.isPlaying
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
                    error: audio.startupError,
                    sampleRate: document.session.sampleRate,
                    bitDepth: document.session.bitDepth,
                    hiddenInspector: showInspector && compact
                )
            }
            .background(LYLLTHTheme.background)
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
    }
}

// MARK: - Transport

private struct TransportBar: View {
    @Binding var session: LYLLTHSession
    @EnvironmentObject private var audio: AudioEngineController

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LYLLTH")
                    .font(LYLLTHTheme.wordmark(28))
                    .tracking(1.4)
                    .offset(y: LYLLTHTheme.wordmarkOpticalDrop(28))
                    .foregroundStyle(LYLLTHTheme.chrome)
                HStack(spacing: 7) {
                    Rectangle().fill(LYLLTHTheme.teal).frame(width: 19, height: 1)
                    Text("BY NIGHTSHAPE")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(LYLLTHTheme.metadata)
                }
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
                    .font(LYLLTHTheme.value(25, weight: .light))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.text)
                Text(audio.isPlaying ? "PLAYING" : "READY")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(audio.isPlaying ? LYLLTHTheme.teal : LYLLTHTheme.dim)
            }
            .padding(.leading, 15)
            .frame(width: 145, alignment: .leading)

            HStack(spacing: 8) {
                TextField("BPM", value: $session.bpm, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.value(25, weight: .light))
                    .foregroundStyle(LYLLTHTheme.text)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 55)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BPM")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(LYLLTHTheme.teal)
                    Text("\(session.numerator) / \(session.denominator)")
                        .font(LYLLTHTheme.value(9))
                        .foregroundStyle(LYLLTHTheme.metadata)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 44)
            .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }

            Spacer(minLength: 18)

            HStack(spacing: 6) {
                TransportUtility(icon: "metronome", title: "CLICK")
                TransportUtility(icon: "repeat", title: "LOOP")
                TransportUtility(icon: "record.circle", title: "RECORD", tint: LYLLTHTheme.purple)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 78)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline(color: LYLLTHTheme.lineStrong) }
    }
}

private struct TransportUtility: View {
    let icon: String
    let title: String
    var tint = LYLLTHTheme.metadata

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2)
            }
            .foregroundStyle(tint)
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

    private let workspaces = ["ARRANGE", "PATTERN", "MIX", "SYNTH"]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                LYLED()
                Text(projectName)
                    .font(LYLLTHTheme.label(10, weight: .bold))
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
                Button {
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("TRACK")
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
                Text(plugins.isScanning ? "SCANNING" : "\(plugins.instruments.count + plugins.effects.count) COMPONENTS")
                    .font(LYLLTHTheme.label(7, weight: .bold))
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

// MARK: - Arrangement

private struct ArrangementView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    let currentStep: Int
    let isPlaying: Bool

    private let headerWidth: CGFloat = 190
    private let beats = 64
    private let beatWidth: CGFloat = 29
    private let laneHeight: CGFloat = 66

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARRANGEMENT")
                        .font(LYLLTHTheme.label(11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(LYLLTHTheme.secondary)
                    Text("16 BARS  ·  LOOP 01–04")
                        .font(LYLLTHTheme.label(8))
                        .tracking(1.1)
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                Spacer()
                Button("SNAP 1/16") {}
                    .buttonStyle(LYChromeButtonStyle(compact: true))
                Button {
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(LYLLTHTheme.metadata)
                Button {
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(LYLLTHTheme.metadata)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(LYLLTHTheme.panel)
            .overlay(alignment: .bottom) { LYHairline() }

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    ruler
                    ForEach($session.tracks) { $track in
                        trackLane(track: $track)
                    }
                    automationLane
                    addTrackLane
                }
                .frame(minWidth: headerWidth + CGFloat(beats) * beatWidth, alignment: .topLeading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(LYLLTHTheme.background)
        }
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
                ForEach(0..<16, id: \.self) { bar in
                    Text("\(bar + 1)")
                        .font(LYLLTHTheme.value(8))
                        .foregroundStyle(bar < 4 ? LYLLTHTheme.secondary : LYLLTHTheme.dim)
                        .frame(width: beatWidth * 4, height: 30, alignment: .topLeading)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(bar % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line).frame(width: 1)
                        }
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LYLLTHTheme.teal.opacity(0.5))
                    .frame(width: beatWidth * 16, height: 1)
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
                        .font(LYLLTHTheme.value(8, weight: .bold))
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
                BeatGrid(beats: beats, beatWidth: beatWidth, height: laneHeight)

                ForEach(track.wrappedValue.clips) { clip in
                    ArrangementClip(clip: clip, accent: accent, isFocused: selected)
                        .frame(width: max(beatWidth * clip.lengthBeats - 4, 28), height: 48)
                        .offset(x: beatWidth * clip.startBeat + 2)
                }

                if isPlaying {
                    Rectangle()
                        .fill(LYLLTHTheme.chrome.opacity(0.76))
                        .frame(width: 1, height: laneHeight)
                        .offset(x: CGFloat(currentStep) * beatWidth)
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

            BeatGrid(beats: beats, beatWidth: beatWidth, height: 44)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<beats, id: \.self) { beat in
                Rectangle()
                    .fill(beat % 8 < 4 ? LYLLTHTheme.background : LYLLTHTheme.deck.opacity(0.72))
                    .frame(width: beatWidth, height: height)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(beat % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line)
                            .frame(width: 1)
                    }
            }
        }
    }
}

private struct ArrangementClip: View {
    let clip: LYClip
    let accent: Color
    let isFocused: Bool

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
                    MiniWaveform(color: accent).frame(height: 13)
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
        }
    }

    private var previewCount: Int { min(16, clip.steps?.count ?? 16) }

    private func isActive(_ index: Int) -> Bool {
        guard let steps = clip.steps, steps.indices.contains(index) else { return index % 3 == 0 }
        return steps[index]
    }
}

private struct MiniWaveform: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let values: [CGFloat] = [0.10, 0.38, 0.74, 0.31, 0.62, 0.92, 0.45, 0.66, 0.22, 0.48, 0.79, 0.34, 0.58, 0.17, 0.42]
                let step = geometry.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
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
            Text("\(Int(sampleRate / 1000)) KHZ  ·  \(bitDepth)-BIT")
                .font(LYLLTHTheme.label(7))
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
