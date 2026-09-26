import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Arrangement

/// The SONG view: tracks down the side, the timeline across, audio events and
/// pattern regions painted onto lanes the way ACID paints loops.
struct ArrangementView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    let isPlaying: Bool
    let openSnapMenu: () -> Void
    let openTrackMenu: () -> Void
    let requestAudioImport: (UUID?, Double) -> Void
    let importDroppedAudio: (URL, UUID?, Double) -> Void
    let previewAudioEvent: (LYClip) -> Void
    var openSynth: (UUID) -> Void = { _ in }
    var openDrums: (UUID) -> Void = { _ in }
    /// Opens a track's pattern (by clip id) in the sequencer.
    var openPattern: (UUID, UUID) -> Void = { _, _ in }
    /// Opens a note clip (track id, clip id) in the piano roll.
    var openNotes: (UUID, UUID) -> Void = { _, _ in }
    /// Opens the automation target menu: (track id, lane id or nil to add one).
    var openAutomationMenu: (UUID, UUID?) -> Void = { _, _ in }
    /// Opens a song FX move's editor.
    var openSongFXMenu: (UUID) -> Void = { _ in }

    @EnvironmentObject private var audio: AudioEngineController

    private let headerWidth: CGFloat = 272
    private let rulerHeight: CGFloat = 36
    @State private var selectedClipID: UUID?
    @State private var pinchStartZoom: Double?
    @State private var viewportSize: CGSize = .zero
    @State private var editCursorBeat = 0.0
    @State private var copiedAudioEvent: LYClip?
    @State private var dropTargetTrackID: UUID?
    @State private var loopDrag: LoopDrag?
    @State private var lastBraceClick = Date.distantPast

    private enum LoopDrag {
        case create(anchor: Double)
        case move(originStart: Double, grab: Double)
        case start(end: Double)
        case end(start: Double)
    }

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

    /// Room for everything placed plus four empty bars to paint into.
    private var beats: Int {
        let end = session.tracks.flatMap(\.clips).map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let loopEnd = session.loopRange.map { $0.startBeat + $0.lengthBeats } ?? 0
        let bars = ceil(max(end, loopEnd) / beatsPerBar) + 4
        return max(64, Int(bars * beatsPerBar))
    }

    private var barCount: Int { Int(ceil(Double(beats) / beatsPerBar)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            audioEditStrip

            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ruler
                        LYSongFXLane(
                            blocks: Binding(get: { session.songFX ?? [] }, set: { session.songFX = $0.isEmpty ? nil : $0 }),
                            tracks: session.tracks,
                            headerWidth: headerWidth,
                            beatWidth: beatWidth,
                            beats: beats,
                            beatsPerBar: beatsPerBar,
                            snap: { snapBeat($0, $0) },
                            openEditor: openSongFXMenu
                        )
                        ForEach(Array(session.tracks.indices), id: \.self) { index in
                            trackLane(index: index)
                            AnyView(automationRows(index: index))
                        }
                        addTrackLane
                    }
                    .frame(
                        minWidth: max(headerWidth + CGFloat(beats) * beatWidth, viewport.size.width),
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                    .overlay(alignment: .topLeading) { cursors }
                }
                .lyScrollers()
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
        .background { LYArrangementKeyMonitor(action: handleArrangementKey) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ARRANGEMENT")
                    .font(LYLLTHTheme.label(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.secondary)
                mixedNumericLabel(
                    arrangementSummary,
                    labelFont: LYLLTHTheme.label(8, weight: .bold),
                    numberFont: LYLLTHTheme.value(9)
                )
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            snapMenu
            autoZoomButton("H FIT", isOn: editor.autoHorizontalZoom) {
                updateEditor { $0.autoHorizontalZoom.toggle() }
                applyAutoZoom()
            }
            autoZoomButton("V FIT", isOn: editor.autoVerticalZoom) {
                updateEditor { $0.autoVerticalZoom.toggle() }
                applyAutoZoom()
            }
            LYMiniSlider(label: "H", value: editorBinding(\.horizontalZoom), range: 10...140)
                .help("Horizontal zoom. Pinch on the trackpad works too.")
            LYMiniSlider(label: "V", value: editorBinding(\.verticalZoom), range: 38...144)
                .help("Track height. Option-pinch works too.")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private var arrangementSummary: String {
        let end = session.tracks.flatMap(\.clips)
            .filter(\.isInSong)
            .map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let bars = "\(max(1, Int(ceil(end / beatsPerBar - 0.0001)))) BAR SONG"
        guard session.isLoopActive, let loop = session.loopRange else { return bars + "  ·  LOOP OFF" }
        let first = Int(loop.startBeat / beatsPerBar) + 1
        let last = Int(ceil((loop.startBeat + loop.lengthBeats) / beatsPerBar))
        return bars + "  ·  LOOP " + String(format: "%02d–%02d", first, last)
    }

    private var snapMenu: some View {
        Button(action: openSnapMenu) {
            HStack(spacing: 6) {
                Text("SNAP")
                    .foregroundStyle(LYLLTHTheme.dim)
                Text(editor.snapMode.label)
                    .foregroundStyle(editor.snapMode == .off ? LYLLTHTheme.dim : LYLLTHTheme.teal)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .font(LYLLTHTheme.label(8.5, weight: .bold))
            .tracking(0.9)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay { Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .lyMenuAnchor("snap")
        .help("Snap resolution, and whether moves keep their offset from the grid")
    }

    private func autoZoomButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(LYChromeButtonStyle(active: isOn, compact: true))
    }

    // MARK: Audio event strip

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

    private var selectedPatternLocation: (track: Int, clip: Int)? {
        guard let selectedClipID else { return nil }
        for trackIndex in session.tracks.indices {
            if let clipIndex = session.tracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID && $0.isSequenced }) {
                return (trackIndex, clipIndex)
            }
        }
        return nil
    }

    /// Opens the selected region's pattern in the sequencer.
    private func editSelectedPattern() {
        guard let location = selectedPatternLocation else { return }
        let track = session.tracks[location.track]
        openPattern(track.id, track.patternContent(of: track.clips[location.clip]).id)
    }

    /// Places the selected region's pattern again, right after it.
    private func placeSelectedPatternAgain() {
        guard let location = selectedPatternLocation else { return }
        let track = session.tracks[location.track]
        let region = track.clips[location.clip]
        let content = track.patternContent(of: region)
        var copy = region
        copy.id = UUID()
        copy.patternSourceID = content.id
        copy.steps = nil
        copy.stepParameters = nil
        copy.isOffTimeline = nil
        copy.name = content.name
        copy.startBeat = region.startBeat + region.lengthBeats
        session.tracks[location.track].clips.append(copy)
        selectedClipID = copy.id
        editCursorBeat = copy.startBeat
    }

    /// Takes a region out of the song. A placement goes; a pattern stays in
    /// the sequencer, just off the arrangement, so no steps are ever lost here.
    private func removeSelectedPatternFromSong() {
        guard let location = selectedPatternLocation else { return }
        if session.tracks[location.track].clips[location.clip].isPlacement {
            session.tracks[location.track].clips.remove(at: location.clip)
        } else {
            session.tracks[location.track].clips[location.clip].isOffTimeline = true
        }
        selectedClipID = nil
    }

    private var selectedTrackKind: LYTrackKind? {
        guard let selectedTrackID else { return nil }
        return session.tracks.first(where: { $0.id == selectedTrackID })?.kind
    }

    private var selectedAudioClip: LYClip? {
        guard let location = selectedAudioLocation else { return nil }
        return session.tracks[location.track].clips[location.clip]
    }

    private var audioEditStrip: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LYLLTHTheme.purple).frame(width: 14, height: 2)
                .lyBloom(LYLLTHTheme.purple)
            if let clip = selectedAudioClip {
                Text("EVENT")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(LYLLTHTheme.dim)
                Text(clip.name)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                    .frame(maxWidth: 170, alignment: .leading)

                eventReadout("GAIN", gainText(clip.eventGainDB))
                eventReadout("PITCH", pitchText(clip.pitchSemitones))
                stretchButton(clip)
                if let cycle = LYAudioEventTiming.cycleBeats(for: clip, projectBPM: session.bpm), cycle > 0 {
                    eventReadout("LOOPS", String(format: "×%.1f", clip.lengthBeats / cycle))
                }

                Spacer(minLength: 8)

                eventActionButton("PREVIEW", help: "Hear this event alone") { previewAudioEvent(clip) }
                eventActionButton("SPLIT  S", help: "Split at the purple edit cursor", enabled: canSplitSelectedAudioEvent, action: splitSelectedAudioEvent)
                eventActionButton("DUP  ⌘D", help: "Duplicate right after this event", action: duplicateSelectedAudioEvent)
                eventActionButton("DELETE", help: "Remove this event (delete key)", action: deleteSelectedAudioEvent)
                eventActionButton("−", help: "Down a semitone (−). Shift: 4, ⌘: octave") { transposeSelectedAudioEvent(by: -1) }
                eventActionButton("+", help: "Up a semitone (=). Shift: 4, ⌘: octave") { transposeSelectedAudioEvent(by: 1) }
            } else if let location = selectedPatternLocation {
                let track = session.tracks[location.track]
                let region = track.clips[location.clip]
                Text(region.isPlacement ? "PLACEMENT" : "PATTERN")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(LYLLTHTheme.dim)
                Text(track.patternContent(of: region).name)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                    .frame(maxWidth: 170, alignment: .leading)
                Spacer(minLength: 8)
                eventActionButton("EDIT IN SEQUENCER  ↩", help: "Open this pattern in the sequencer (or double-click the region)", action: editSelectedPattern)
                eventActionButton("PLACE AGAIN  ⌘D", help: "Play this pattern again right after. Editing the pattern changes every place it plays.", action: placeSelectedPatternAgain)
                eventActionButton("REMOVE", help: "Take it out of the song (delete key). The pattern stays in the sequencer.", action: removeSelectedPatternFromSong)
            } else {
                Text(selectedTrackKind == .audio
                     ? "DROP AUDIO ON A LANE  ·  DRAG AN EVENT'S RIGHT EDGE TO LOOP IT  ·  DRAG ITS TOP LINE FOR VOLUME"
                     : "DOUBLE-CLICK A PATTERN TO EDIT IT  ·  CLICK AN AUDIO EVENT TO EDIT IT  ·  DROP FILES FROM FINDER ONTO ANY LANE")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if copiedAudioEvent != nil {
                    eventActionButton("PASTE  ⌘V", help: "Paste at the edit cursor", action: pasteAudioEvent)
                }
                Button("IMPORT AUDIO") {
                    requestAudioImport(selectedTrackKind == .audio ? selectedTrackID : nil, editCursorBeat)
                }
                .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.purple, compact: true))
                .help("Copy an audio file into the project at the edit cursor")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func eventReadout(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(LYLLTHTheme.dim)
            Text(value)
                .font(LYLLTHTheme.value(10))
                .foregroundStyle(LYLLTHTheme.text)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .overlay { Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1) }
    }

    private func stretchButton(_ clip: LYClip) -> some View {
        let label: String
        switch clip.stretchMode {
        case .off: label = "OFF"
        case .tempo: label = "TEMPO"
        case .beatMapped: label = "BEAT MAP"
        }
        return Button {
            updateSelectedAudioEvent { event in
                switch event.stretchMode {
                case .off: event.stretchMode = event.sourceBPM == nil ? (event.beatMap == nil ? .off : .beatMapped) : .tempo
                case .tempo: event.stretchMode = event.beatMap == nil ? .off : .beatMapped
                case .beatMapped: event.stretchMode = .off
                }
                if let cycle = LYAudioEventTiming.cycleBeats(for: event, projectBPM: session.bpm), event.lengthBeats <= cycle * 1.001 + 0.5 {
                    event.lengthBeats = cycle
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("STRETCH")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
                Text(label)
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(clip.stretchMode == .off ? LYLLTHTheme.text : LYLLTHTheme.teal)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .overlay { Rectangle().stroke(clip.stretchMode == .off ? LYLLTHTheme.line : LYLLTHTheme.teal.opacity(0.6), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("OFF plays at the source speed. TEMPO follows the project tempo. BEAT MAP locks each detected beat to the grid.")
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
            .opacity(enabled ? 1 : 0.4)
            .help(help)
    }

    // MARK: Ruler and loop brace

    private var ruler: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("TRACKS")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(width: headerWidth, height: rulerHeight)
            .background(LYLLTHTheme.deck)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let barWidth = CGFloat(beatsPerBar) * beatWidth
                    for bar in 0...barCount {
                        let x = floor(CGFloat(bar) * barWidth)
                        context.fill(
                            Path(CGRect(x: x, y: bar % 4 == 0 ? 0 : 12, width: 1, height: size.height)),
                            with: .color(bar % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line)
                        )
                        if barWidth >= 14 {
                            for beat in 1..<Int(beatsPerBar) {
                                let bx = floor(x + CGFloat(beat) * beatWidth)
                                context.fill(Path(CGRect(x: bx, y: size.height - 16, width: 1, height: 4)), with: .color(LYLLTHTheme.line))
                            }
                        }
                    }
                }
                loopBrace
                HStack(spacing: 0) {
                    ForEach(0..<barCount, id: \.self) { bar in
                        let showsNumber = beatWidth * CGFloat(beatsPerBar) >= 22 || bar % 4 == 0
                        Text(showsNumber ? "\(bar + 1)" : "")
                            .font(LYLLTHTheme.value(10))
                            .foregroundStyle(bar % 4 == 0 ? LYLLTHTheme.text : LYLLTHTheme.dim)
                            .padding(.leading, 5)
                            .padding(.top, 3)
                            .frame(width: beatWidth * CGFloat(beatsPerBar), height: 20, alignment: .topLeading)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: CGFloat(beats) * beatWidth, height: rulerHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Logic's cycle area: a drag anywhere in the ruler
                        // draws, moves or resizes the loop.
                        if loopDrag != nil || hypot(value.translation.width, value.translation.height) >= 3 {
                            dragLoop(value)
                        }
                    }
                    .onEnded { value in
                        let wasDrag = loopDrag != nil
                        loopDrag = nil
                        guard !wasDrag else { return }
                        if !handleBraceClick(value) {
                            let raw = Double(value.location.x / max(beatWidth, 1))
                            editCursorBeat = min(max(0, snapBeat(raw, raw)), Double(beats))
                        }
                    }
            )
            .help("Drag in the ruler to draw, move or resize the loop. Double-click the loop to remove it. Click outside it to place the edit cursor.")
        }
        .background(LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline(color: LYLLTHTheme.lineStrong) }
    }

    @ViewBuilder
    private var loopBrace: some View {
        if let loop = session.loopRange {
            let active = session.isLoopActive
            let color = active ? LYLLTHTheme.indigo : LYLLTHTheme.off
            let x = CGFloat(loop.startBeat) * beatWidth
            let width = max(4, CGFloat(loop.lengthBeats) * beatWidth)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(active ? 0.18 : 0.35))
                Rectangle()
                    .fill(color)
                    .frame(height: 2)
                    .lyBloom(color, isOn: active, strength: 0.3)
                Rectangle().fill(color).frame(width: 2, height: rulerHeight)
                Rectangle().fill(color).frame(width: 2, height: rulerHeight).offset(x: width - 2)
            }
            .frame(width: width, height: rulerHeight)
            .offset(x: x)
            .allowsHitTesting(false)
        }
    }

    /// Double-clicking the loop brace removes the loop. Detected here because
    /// the ruler's zero-distance drag would swallow a tap recognizer.
    /// Returns true when the click landed on the loop, so it is not also an
    /// edit-cursor click.
    @discardableResult
    private func handleBraceClick(_ value: DragGesture.Value) -> Bool {
        guard let loop = session.loopRange else { return false }
        let beat = Double(value.startLocation.x / max(beatWidth, 1))
        guard beat >= loop.startBeat, beat <= loop.startBeat + loop.lengthBeats else { return false }
        let now = Date()
        if now.timeIntervalSince(lastBraceClick) <= NSEvent.doubleClickInterval {
            session.loopRange = nil
            session.isLoopEnabled = false
            lastBraceClick = .distantPast
        } else {
            lastBraceClick = now
        }
        return true
    }

    private func dragLoop(_ value: DragGesture.Value) {
        let bar = beatsPerBar
        let raw = Double(value.location.x / max(beatWidth, 1))
        let snapped = (raw / bar).rounded() * bar
        if loopDrag == nil {
            let startRaw = Double(value.startLocation.x / max(beatWidth, 1))
            if let loop = session.loopRange {
                let edge = 6 / Double(max(beatWidth, 1))
                let end = loop.startBeat + loop.lengthBeats
                if abs(startRaw - loop.startBeat) <= max(edge, 0.25) {
                    loopDrag = .start(end: end)
                } else if abs(startRaw - end) <= max(edge, 0.25) {
                    loopDrag = .end(start: loop.startBeat)
                } else if startRaw > loop.startBeat, startRaw < end {
                    loopDrag = .move(originStart: loop.startBeat, grab: startRaw)
                } else {
                    loopDrag = .create(anchor: (startRaw / bar).rounded(.down) * bar)
                }
            } else {
                loopDrag = .create(anchor: (startRaw / bar).rounded(.down) * bar)
            }
        }
        var range = session.loopRange ?? LYLoopRange(startBeat: 0, lengthBeats: bar)
        switch loopDrag {
        case .create(let anchor):
            let a = min(anchor, snapped), b = max(anchor + bar, snapped)
            range = LYLoopRange(startBeat: max(0, a), lengthBeats: max(bar, b - max(0, a)))
        case .move(let originStart, let grab):
            let moved = ((originStart + raw - grab) / bar).rounded() * bar
            range.startBeat = max(0, moved)
        case .start(let end):
            let start = min(max(0, snapped), end - bar)
            range = LYLoopRange(startBeat: start, lengthBeats: end - start)
        case .end(let start):
            let end = max(start + bar, snapped)
            range = LYLoopRange(startBeat: start, lengthBeats: end - start)
        case nil:
            break
        }
        if range != session.loopRange { session.loopRange = range }
        if session.isLoopEnabled != true { session.isLoopEnabled = true }
    }

    // MARK: Lanes

    private func trackLane(index: Int) -> some View {
        let track = session.tracks[index]
        let selected = selectedTrackID == track.id
        let accent = LYLLTHTheme.trackAccent(position: index)
        let isDropTarget = dropTargetTrackID == track.id

        return HStack(spacing: 0) {
            LYTrackHeader(
                number: index + 1,
                name: track.name,
                kind: track.isChordTrack == true ? "CHORD TRACK" : track.kind.label,
                accent: accent,
                isSelected: selected,
                isMuted: $session.tracks[index].isMuted,
                isSolo: $session.tracks[index].isSolo,
                isArmed: track.kind == .auxiliary ? nil : $session.tracks[index].isArmed,
                showsAutomation: Binding(
                    get: { session.tracks.indices.contains(index) && session.tracks[index].showsAutomation == true },
                    set: { value in
                        guard session.tracks.indices.contains(index) else { return }
                        session.tracks[index].showsAutomation = value ? true : nil
                    }
                ),
                automationCount: (track.automation ?? []).count,
                instrumentIcon: track.kind == .drumkit ? "waveform.path" : (track.kind == .instrument && track.isChordTrack != true ? "pianokeys" : nil),
                openInstrument: { track.kind == .drumkit ? openDrums(track.id) : openSynth(track.id) }
            )
            .frame(width: headerWidth, height: laneHeight)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { track.kind == .drumkit ? openDrums(track.id) : openSynth(track.id) }
            .onTapGesture { selectedTrackID = track.id }

            ZStack(alignment: .topLeading) {
                BeatGrid(
                    beats: beats,
                    beatWidth: beatWidth,
                    height: laneHeight,
                    beatsPerBar: beatsPerBar,
                    subdivisionBeats: displayGridBeats,
                    showsGrid: editor.showsGrid
                )
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            guard takesNoteClips(track) else { return }
                            let raw = Double(value.location.x / max(beatWidth, 1))
                            createNoteClip(trackIndex: index, atBeat: raw)
                        }
                        .exclusively(before: SpatialTapGesture()
                        .onEnded { value in
                            selectedTrackID = track.id
                            selectedClipID = nil
                            let raw = Double(value.location.x / max(beatWidth, 1))
                            editCursorBeat = min(max(0, snapBeat(raw, raw)), Double(beats))
                        })
                )

                if takesNoteClips(track) && !track.clips.contains(where: { $0.isInSong }) {
                    Text("DOUBLE-CLICK TO ADD A NOTE CLIP")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .padding(.leading, 14)
                        .frame(height: laneHeight)
                        .allowsHitTesting(false)
                }

                if track.kind == .audio && track.clips.isEmpty {
                    Text("DROP AUDIO HERE")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .padding(.leading, 14)
                        .frame(height: laneHeight)
                        .allowsHitTesting(false)
                }

                ForEach($session.tracks[index].clips) { $clip in
                    if clip.isInSong || clip.kind == .audio {
                    ArrangementClip(
                        clip: $clip,
                        source: clip.patternSourceID.flatMap { id in track.clips.first { $0.id == id } },
                        accent: accent,
                        isSelected: selectedClipID == clip.id,
                        isTrackSelected: selected,
                        isChordTrack: track.isChordTrack == true,
                        beatWidth: beatWidth,
                        projectBPM: session.bpm,
                        maximumBeat: Double(beats) + 64,
                        snap: snapBeat
                    )
                    .frame(
                        width: max(beatWidth * clip.lengthBeats - 2, 10),
                        height: max(28, laneHeight - 12)
                    )
                    .offset(x: beatWidth * clip.startBeat + 1, y: 6)
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                selectedTrackID = track.id
                                selectedClipID = clip.id
                                let rawBeat = clip.startBeat + Double(value.location.x / max(beatWidth, 1))
                                editCursorBeat = min(max(0, snapBeat(rawBeat, clip.startBeat)), Double(beats))
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            if clip.isNoteClip { openNotes(track.id, clip.id); return }
                            guard clip.isSequenced else { return }
                            openPattern(track.id, track.patternContent(of: clip).id)
                        }
                    )
                    }
                }

                if isDropTarget {
                    Rectangle()
                        .fill(LYLLTHTheme.purple.opacity(0.07))
                        .overlay { Rectangle().strokeBorder(LYLLTHTheme.purple.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: CGFloat(beats) * beatWidth, height: laneHeight)
            .clipped()
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: Binding(
                    get: { dropTargetTrackID == track.id },
                    set: { targeted in
                        if targeted { dropTargetTrackID = track.id } else if dropTargetTrackID == track.id { dropTargetTrackID = nil }
                    }
                )
            ) { providers, location in
                let raw = Double(location.x / max(beatWidth, 1))
                let beat = max(0, snapBeat(raw, raw))
                let trackID = track.kind == .audio ? track.id : nil
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { importDroppedAudio(url, trackID, beat) }
                    }
                }
                return !providers.isEmpty
            }
        }
        .background(selected ? LYLLTHTheme.panel : LYLLTHTheme.deck)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    // MARK: Automation

    private let automationHeight: CGFloat = 64

    private func laneBinding(trackID: UUID, laneID: UUID) -> Binding<LYAutomationLane>? {
        guard let t = session.tracks.firstIndex(where: { $0.id == trackID }),
              let lane = session.tracks[t].automation?.first(where: { $0.id == laneID }) else { return nil }
        return Binding(
            get: { session.tracks.first { $0.id == trackID }?.automation?.first { $0.id == laneID } ?? lane },
            set: { value in
                guard let t = session.tracks.firstIndex(where: { $0.id == trackID }),
                      let l = session.tracks[t].automation?.firstIndex(where: { $0.id == laneID }) else { return }
                session.tracks[t].automation?[l] = value
            }
        )
    }

    @ViewBuilder
    private func automationRows(index: Int) -> some View {
        let track = session.tracks[index]
        if track.showsAutomation == true {
            let accent = LYLLTHTheme.trackAccent(position: index)
            ForEach(track.automation ?? []) { lane in
                if let binding = laneBinding(trackID: track.id, laneID: lane.id) {
                    HStack(spacing: 0) {
                        LYAutomationLaneHeader(
                            title: lane.target.title(in: session),
                            accent: accent,
                            anchor: "auto.\(lane.id)",
                            isBypassed: Binding(get: { binding.wrappedValue.isBypassed == true },
                                                set: { binding.wrappedValue.isBypassed = $0 ? true : nil }),
                            pickTarget: { openAutomationMenu(track.id, lane.id) },
                            remove: {
                                guard let t = session.tracks.firstIndex(where: { $0.id == track.id }) else { return }
                                session.tracks[t].automation?.removeAll { $0.id == lane.id }
                            }
                        )
                        .frame(width: headerWidth, height: automationHeight)
                        LYAutomationLaneView(
                            lane: binding,
                            accent: accent,
                            beatWidth: beatWidth,
                            snap: { snapBeat($0, $0) },
                            songBeat: { [audio] in audio.currentSongBeat() },
                            isPlaying: isPlaying && audio.transportMode == .song
                        )
                        .frame(width: CGFloat(beats) * beatWidth, height: automationHeight)
                        .background(
                            BeatGrid(beats: beats, beatWidth: beatWidth, height: automationHeight, beatsPerBar: beatsPerBar,
                                     subdivisionBeats: displayGridBeats, showsGrid: editor.showsGrid)
                                .opacity(0.6)
                                .allowsHitTesting(false)
                        )
                    }
                    .background(LYLLTHTheme.background)
                    .overlay(alignment: .bottom) { LYHairline() }
                }
            }
            HStack(spacing: 0) {
                Button { openAutomationMenu(track.id, nil) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                        Text("AUTOMATION LANE").font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1.4)
                    }
                    .foregroundStyle(LYLLTHTheme.indigo)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .overlay(Rectangle().stroke(LYLLTHTheme.indigo.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .lyMenuAnchor("auto.add.\(track.id)")
                .padding(.leading, 18)
                .frame(width: headerWidth, height: 30, alignment: .leading)
                if (track.automation ?? []).isEmpty {
                    Text("PICK VOLUME, PAN, A SEND, AN EFFECT OR A LUNATK KNOB · CLICK THE LANE TO ADD POINTS")
                        .font(LYLLTHTheme.label(7, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .padding(.leading, 12)
                }
                Spacer(minLength: 0)
            }
            .background(LYLLTHTheme.background)
            .overlay(alignment: .bottom) { LYHairline() }
        }
    }

    /// Melodic tracks take piano-roll clips; drums and chord tracks keep steps.
    private func takesNoteClips(_ track: LYTrack) -> Bool {
        track.kind == .instrument && track.isChordTrack != true
    }

    /// A new, empty note clip on the bar under the pointer, opened straight
    /// into the piano roll.
    private func createNoteClip(trackIndex: Int, atBeat raw: Double) {
        let start = max(0, floor(raw / beatsPerBar) * beatsPerBar)
        let length = beatsPerBar * 4
        let track = session.tracks[trackIndex]
        let taken = track.clips.filter(\.isInSong).map { ($0.startBeat, $0.startBeat + $0.lengthBeats) }
        guard !taken.contains(where: { raw >= $0.0 && raw < $0.1 }) else { return }
        let nextStart = taken.map(\.0).filter { $0 > start }.min() ?? .infinity
        let fitted = min(length, nextStart - start)
        guard fitted >= 0.25 else { return }
        let count = track.clips.filter(\.isNoteClip).count + 1
        let clip = LYClip(name: "NOTES \(count)", kind: .notes, startBeat: start, lengthBeats: fitted, notes: [], noteLoopBeats: fitted)
        session.tracks[trackIndex].clips.append(clip)
        selectedTrackID = track.id
        selectedClipID = clip.id
        openNotes(track.id, clip.id)
    }

    private var addTrackLane: some View {
        Button(action: openTrackMenu) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("ADD TRACK")
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.6)
            }
            .foregroundStyle(LYLLTHTheme.chromeText)
            .padding(.leading, 16)
            .frame(width: headerWidth, height: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lyMenuAnchor("laneTrack")
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LYLLTHTheme.deck)
    }

    // MARK: Cursors

    private var cursors: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LYLLTHTheme.purple.opacity(0.9))
                    .frame(width: 1, height: geometry.size.height - rulerHeight)
                    .offset(x: headerWidth + CGFloat(editCursorBeat) * beatWidth, y: rulerHeight)
                Rectangle()
                    .fill(LYLLTHTheme.purple)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(45))
                    .lyBloom(LYLLTHTheme.purple, strength: 0.3)
                    .offset(x: headerWidth + CGFloat(editCursorBeat) * beatWidth - 3.5, y: rulerHeight - 22)

                if isPlaying && audio.transportMode == .song {
                    TimelineView(.animation) { _ in
                        if let beat = audio.currentSongBeat() {
                            let x = headerWidth + CGFloat(beat) * beatWidth
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(LYLLTHTheme.playhead)
                                    .frame(width: 1.5, height: geometry.size.height)
                                    .offset(x: x - 0.75)
                                PlayheadHead(color: LYLLTHTheme.teal)
                                    .offset(x: x - 6, y: 2)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Editing commands

    private var canSplitSelectedAudioEvent: Bool {
        guard let clip = selectedAudioClip else { return false }
        let inset = max(0.001, 6 / Double(max(beatWidth, 1)))
        return editCursorBeat > clip.startBeat + inset
            && editCursorBeat < clip.startBeat + clip.lengthBeats - inset
    }

    private func handleArrangementKey(_ event: NSEvent) -> Bool {
        if event.window?.firstResponder is NSTextView || event.window?.firstResponder is NSTextField {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command), key == "v" {
            guard copiedAudioEvent != nil else { return false }
            pasteAudioEvent()
            return true
        }
        if selectedPatternLocation != nil {
            if flags.contains(.command), key == "d" { placeSelectedPatternAgain(); return true }
            if key == "\u{7F}" || key == "\u{8}" { removeSelectedPatternFromSong(); return true }
            if key == "\r" { editSelectedPattern(); return true }
            return false
        }
        guard selectedAudioLocation != nil else { return false }

        if flags.contains(.command) {
            switch key {
            case "c": copySelectedAudioEvent(); return true
            case "x": cutSelectedAudioEvent(); return true
            case "d": duplicateSelectedAudioEvent(); return true
            default: return false
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

    // MARK: Zoom and snap

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
        if value != session.arrangementEditor { session.arrangementEditor = value }
    }

    private func applyAutoZoom() {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        updateEditor { value in
            if value.autoHorizontalZoom {
                value.horizontalZoom = Double(max(10, (viewportSize.width - headerWidth) / CGFloat(beats)))
            }
            if value.autoVerticalZoom {
                let usable = max(38, viewportSize.height - rulerHeight - 40)
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
        return editor.snap(
            rawBeat: rawBeat,
            originalBeat: originalBeat,
            bpm: session.bpm,
            numerator: session.numerator,
            denominator: session.denominator,
            sampleRate: session.sampleRate,
            beatWidth: Double(beatWidth),
            overrideMode: flags.contains(.control) ? .division : nil
        )
    }
}

// MARK: - Track header

/// DrumKit's sequencer track cell carried to the timeline: frosted glass,
/// a 1.5 pt border in the row's positional colour, a square number badge.
struct LYTrackHeader: View {
    let number: Int
    let name: String
    let kind: String
    let accent: Color
    let isSelected: Bool
    @Binding var isMuted: Bool
    @Binding var isSolo: Bool
    var isArmed: Binding<Bool>?
    var showsAutomation: Binding<Bool>? = nil
    var automationCount = 0
    var instrumentIcon: String? = nil
    var openInstrument: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", number))
                .font(LYLLTHTheme.value(10))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(accent.opacity(isSelected ? 1 : 0.6), lineWidth: 1))
                .lyBloom(accent, isOn: isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(LYLLTHTheme.label(10.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(isMuted ? LYLLTHTheme.dim : LYLLTHTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(name)
                Text(kind)
                    .font(LYLLTHTheme.label(7, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
            if let instrumentIcon {
                Button(action: openInstrument) {
                    Image(systemName: instrumentIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 19, height: 19)
                        .overlay(Rectangle().stroke(accent.opacity(0.7), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(instrumentIcon == "pianokeys" ? "Open LUNATK" : "Choose this track's drum sound")
            }
            LYTrackToggle(title: "M", isOn: $isMuted, tint: LYLLTHTheme.purple)
                .help("Mute")
            LYTrackToggle(title: "S", isOn: $isSolo, tint: LYLLTHTheme.teal)
                .help("Solo")
            if let isArmed {
                LYTrackToggle(title: "R", isOn: isArmed, tint: LYLLTHTheme.record)
                    .help("Record arm")
            }
            if let showsAutomation {
                LYTrackToggle(title: "A", isOn: showsAutomation, tint: LYLLTHTheme.indigo)
                    .overlay(alignment: .topTrailing) {
                        if automationCount > 0 && !showsAutomation.wrappedValue {
                            Circle().fill(LYLLTHTheme.indigo).frame(width: 4, height: 4).offset(x: 1.5, y: -1.5)
                        }
                    }
                    .help("Show automation lanes")
            }
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LYDrumKitGlassSurface())
        .lyRisingBloom(accent, isOn: isSelected, strength: 0.8)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(accent.opacity(isSelected ? 1 : 0.55), lineWidth: 1.5)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
    }
}

struct LYTrackToggle: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title)
                .font(LYLLTHTheme.label(8.5, weight: .bold))
                .foregroundStyle(isOn ? tint : LYLLTHTheme.chromeText)
                .frame(width: 19, height: 19)
                .background(tint.opacity(isOn ? 0.14 : 0))
                .overlay(Rectangle().stroke(isOn ? tint : LYLLTHTheme.lineStrong, lineWidth: 1))
                .lyBloom(tint, isOn: isOn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["M": "Mute", "S": "Solo", "R": "Record arm", "A": "Automation"][title] ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Thin NIGHTSHAPE slider: a hairline track, an accent fill, a square cap.
struct LYMiniSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint = LYLLTHTheme.indigo
    @State private var origin: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .foregroundStyle(LYLLTHTheme.dim)
            GeometryReader { geometry in
                let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let x = min(max(fraction, 0), 1) * (geometry.size.width - 6)
                ZStack(alignment: .leading) {
                    Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1)
                    Rectangle().fill(tint).frame(width: x + 3, height: 1)
                    Rectangle()
                        .fill(LYLLTHTheme.chrome)
                        .frame(width: 6, height: 12)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let f = min(max(drag.location.x / max(geometry.size.width, 1), 0), 1)
                            value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(width: 64, height: 22)
        }
    }
}

struct PlayheadHead: View {
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

// MARK: - Grid

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

            // Four-bar phrases alternate, the way DrumKit's song lanes read.
            for bar in stride(from: 4, to: bars, by: 8) {
                let x = CGFloat(bar) * barWidth
                context.fill(
                    Path(CGRect(x: x, y: 0, width: min(barWidth * 4, totalWidth - x), height: height)),
                    with: .color(Color.white.opacity(0.012))
                )
            }

            guard showsGrid else { return }
            for beat in 0...beats {
                let x = CGFloat(beat) * beatWidth
                let isBar = abs(Double(beat).truncatingRemainder(dividingBy: beatsPerBar)) < 0.0001
                if !isBar && beatWidth < 7 { continue }
                context.fill(
                    Path(CGRect(x: floor(x), y: 0, width: 1, height: height)),
                    with: .color(isBar ? LYLLTHTheme.lineStrong.opacity(0.9) : Color.white.opacity(0.035))
                )
            }

            if let subdivisionBeats, subdivisionBeats < 1 {
                let divisionWidth = CGFloat(subdivisionBeats) * beatWidth
                guard divisionWidth >= 8 else { return }
                let count = Int(ceil(Double(beats) / subdivisionBeats))
                for division in 0...count {
                    let beat = Double(division) * subdivisionBeats
                    if abs(beat.rounded() - beat) < 0.0001 { continue }
                    let x = CGFloat(beat) * beatWidth
                    context.fill(
                        Path(CGRect(x: floor(x), y: height - 5, width: 1, height: 5)),
                        with: .color(Color.white.opacity(0.05))
                    )
                }
            }
        }
        .frame(width: CGFloat(beats) * beatWidth, height: height)
    }
}

// MARK: - Clip

/// A note clip's notes in miniature, repeated across the clip's length.
private struct LYNoteClipMiniRoll: View {
    let notes: [LYNote]
    let accent: Color
    let beatWidth: CGFloat
    let lengthBeats: Double
    let cycleBeats: Double
    let loopOffsetBeats: Double

    var body: some View {
        Canvas { context, size in
            guard !notes.isEmpty, cycleBeats > 0 else { return }
            let low = notes.map(\.pitch).min()!, high = notes.map(\.pitch).max()!
            let span = CGFloat(max(high - low, 11) + 1)
            let row = max(1.5, (size.height - 4) / span)
            let base = (size.height - row * span) / 2
            var pass = -loopOffsetBeats
            while pass < lengthBeats {
                if pass > 0 {
                    context.fill(Path(CGRect(x: CGFloat(pass) * beatWidth, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.25)))
                }
                for note in notes {
                    let start = pass + note.start
                    let end = min(pass + note.end, pass + cycleBeats, lengthBeats)
                    guard end > max(start, 0) else { continue }
                    let x0 = CGFloat(max(start, 0)) * beatWidth
                    let y = base + CGFloat(high - note.pitch) * row
                    let rect = CGRect(x: x0, y: y, width: max(2, CGFloat(end - max(start, 0)) * beatWidth - 1), height: max(1.5, row - 0.5))
                    context.fill(Path(rect), with: .color(accent.opacity(0.4 + 0.5 * Double(note.velocity) / 127)))
                }
                pass += cycleBeats
            }
        }
    }
}

private struct ArrangementClip: View {
    @Binding var clip: LYClip
    /// The pattern a placement plays, whose steps it draws.
    var source: LYClip? = nil
    let accent: Color
    let isSelected: Bool
    let isTrackSelected: Bool
    let isChordTrack: Bool
    let beatWidth: CGFloat
    let projectBPM: Double
    let maximumBeat: Double
    let snap: (Double, Double) -> Double

    @State private var moveOrigin: Double?
    @State private var movePreviewBeat: Double?
    @State private var leftTrimOrigin: (start: Double, length: Double, offset: Double)?
    @State private var rightTrimOrigin: Double?
    @State private var slipOriginSeconds: Double?
    @State private var slipPreviewSeconds: Double?
    @State private var gainOriginDB: Double?
    @State private var isHovering = false

    private static let body0 = Color(hex: 0x0B0C10)
    private let titleHeight: CGFloat = 15

    /// Beats one pass of the content lasts: the source loop for audio, the
    /// pattern for a pattern region.
    private var cycleBeats: Double? {
        if clip.kind == .audio {
            return LYAudioEventTiming.cycleBeats(for: clip, projectBPM: projectBPM)
        }
        if clip.isNoteClip { return clip.noteCycleBeats }
        guard let count = (source ?? clip).steps?.count, count > 0 else { return nil }
        return Double(count) * lyBeatsPerStep
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Self.body0)
            Rectangle().fill(accent.opacity(isSelected ? 0.11 : (isTrackSelected ? 0.075 : LYLLTHTheme.controlFill)))

            content
                .padding(.top, titleHeight)
                .allowsHitTesting(false)

            titleRow
                .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(accent.opacity(isSelected ? 1 : (isTrackSelected || isHovering ? 0.85 : 0.55)), lineWidth: isSelected ? 1.5 : 1)
                .lyBloom(accent, isOn: isSelected)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                trimHandle(edge: .leading)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(moveGesture)
                trimHandle(edge: .trailing)
            }

            if clip.kind == .audio && clip.sourceRelativePath != nil {
                gainOverlay
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .offset(x: moveVisualOffset)
        .onHover { isHovering = $0 }
        .overlay(alignment: .topTrailing) { dragReadout }
        .animation(LYLLTHTheme.snap, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clip.kind == .audio ? "Audio event \(clip.name)" : (clip.isNoteClip ? "Note clip \(clip.name)" : "Pattern region \(clip.name)"))
        .accessibilityValue(accessibilityDescription)
        .accessibilityIdentifier("arrangement-clip-\(clip.id.uuidString)")
        .help(clip.kind == .audio
              ? "Drag to move. Drag the right edge past the end to loop it. Option-drag slides the audio inside the event. Drag the top line for volume."
              : clip.isNoteClip
              ? "Double-click to edit the notes in the piano roll. Drag to move. Drag the right edge to repeat the notes."
              : "Double-click to edit in the sequencer. Drag to move. Drag the right edge to repeat the pattern. ⌘D places it again.")
    }

    // MARK: Drawing

    private var titleRow: some View {
        HStack(spacing: 5) {
            Rectangle().fill(accent).frame(width: 4, height: 4)
            Text(source?.name ?? clip.name)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(LYLLTHTheme.text)
                .lineLimit(1)
            if let cycle = cycleBeats, clip.lengthBeats > cycle + 0.01 {
                Image(systemName: "repeat")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
            if clip.kind == .audio {
                if abs(clip.pitchSemitones) >= 0.05 {
                    Text(String(format: "%+.0f ST", clip.pitchSemitones))
                        .font(LYLLTHTheme.value(8))
                        .foregroundStyle(LYLLTHTheme.lavender)
                }
                if abs(clip.eventGainDB) >= 0.05 {
                    Text(clip.eventGainDB <= -59.95 ? "−∞ DB" : String(format: "%+.1f DB", clip.eventGainDB))
                        .font(LYLLTHTheme.value(8))
                        .foregroundStyle(LYLLTHTheme.text)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: titleHeight)
        .background(accent.opacity(isSelected ? 0.16 : 0.08))
    }

    @ViewBuilder
    private var content: some View {
        if clip.kind == .audio {
            if clip.sourceRelativePath == nil {
                Text("NO SOURCE")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .padding(6)
            } else {
                LYEventWaveform(
                    peaks: clip.waveformPeaks ?? [],
                    accent: accent,
                    gain: clip.eventGainDB <= -59.95 ? 0 : pow(10, clip.eventGainDB / 20),
                    beatWidth: beatWidth,
                    lengthBeats: clip.lengthBeats,
                    cycleBeats: cycleBeats ?? clip.lengthBeats,
                    loopOffsetBeats: clip.loopOffsetBeats,
                    sourceStart: max(0, clip.sourceStartSeconds + clip.slipOffsetSeconds + (slipPreviewSeconds.map { $0 - clip.slipOffsetSeconds } ?? 0)),
                    sourceDuration: clip.sourceDurationSeconds ?? 0,
                    fileDuration: clip.sourceFileDurationSeconds ?? (clip.sourceStartSeconds + (clip.sourceDurationSeconds ?? 0))
                )
            }
        } else if clip.isNoteClip {
            LYNoteClipMiniRoll(
                notes: clip.notes ?? [],
                accent: accent,
                beatWidth: beatWidth,
                lengthBeats: clip.lengthBeats,
                cycleBeats: clip.noteCycleBeats,
                loopOffsetBeats: clip.loopOffsetBeats
            )
        } else {
            LYPatternCells(
                steps: patternSteps,
                velocities: ((source ?? clip).stepParameters ?? []).map(\.velocity),
                accent: accent,
                beatWidth: beatWidth,
                lengthBeats: clip.lengthBeats,
                loopOffsetBeats: clip.loopOffsetBeats
            )
        }
    }

    private var patternSteps: [Bool] {
        let pattern = source ?? clip
        let steps = pattern.steps ?? []
        guard isChordTrack, let locks = pattern.stepParameters else { return steps }
        return locks.indices.map { index in
            (steps.indices.contains(index) && steps[index]) || (locks[index].chord.map { $0 >= 0 } ?? false)
        }
    }

    @ViewBuilder
    private var dragReadout: some View {
        if let movePreviewBeat {
            readout(String(format: "BAR %.2f", movePreviewBeat / 4 + 1), color: accent)
        } else if let slipPreviewSeconds {
            readout(String(format: "SLIP %+.3f S", slipPreviewSeconds), color: LYLLTHTheme.indigo)
        } else if rightTrimOrigin != nil, let cycle = cycleBeats, cycle > 0 {
            readout(String(format: "×%.2f", clip.lengthBeats / cycle), color: accent)
        }
    }

    private func readout(_ text: String, color: Color) -> some View {
        Text(text)
            .font(LYLLTHTheme.value(9))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(LYLLTHTheme.background.opacity(0.92))
            .overlay { Rectangle().stroke(color.opacity(0.7), lineWidth: 1) }
            .padding(3)
            .offset(y: titleHeight)
    }

    private var accessibilityDescription: String {
        let location = String(format: "beat %.2f", clip.startBeat + 1)
        let duration = String(format: "%.2f beats", clip.lengthBeats)
        guard clip.kind == .audio else { return "\(location), \(duration)" }
        let gain = clip.eventGainDB <= -59.95
            ? "minus infinity decibels"
            : String(format: "%+.1f decibels", clip.eventGainDB)
        let pitch = String(format: "%+.0f semitones", clip.pitchSemitones)
        return "\(location), \(duration), \(gain), \(pitch)"
    }

    // MARK: Volume line

    /// ACID's volume line: drag it down to turn the event down. +12 dB at the
    /// top of the event, silence at the bottom, 0 dB a sixth of the way down.
    private var gainOverlay: some View {
        GeometryReader { geometry in
            let usable = geometry.size.height - titleHeight
            let y = titleHeight + gainLineY(height: usable)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LYLLTHTheme.chrome.opacity(isSelected || gainOriginDB != nil ? 0.9 : 0.45))
                    .frame(height: 1)
                    .offset(y: y)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12)
                    .offset(y: min(max(titleHeight, y - 6), max(titleHeight, geometry.size.height - 12)))
                    .contentShape(Rectangle())
                    .highPriorityGesture(gainGesture(height: usable))
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                    }
            }
        }
    }

    private func gainLineY(height: CGFloat) -> CGFloat {
        let normalized = CGFloat((12 - min(max(clip.eventGainDB, -60), 12)) / 72)
        return 2 + normalized * max(1, height - 4)
    }

    private func gainGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = gainOriginDB ?? clip.eventGainDB
                if gainOriginDB == nil { gainOriginDB = origin }
                let sensitivity = NSEvent.modifierFlags.contains(.control) ? 0.2 : 1.0
                let delta = -Double(value.translation.height / max(height - 4, 1)) * 72 * sensitivity
                clip.eventGainDB = min(max(origin + delta, -60), 12)
            }
            .onEnded { _ in gainOriginDB = nil }
    }

    // MARK: Move and trim

    private enum TrimEdge { case leading, trailing }

    @ViewBuilder
    private func trimHandle(edge: TrimEdge) -> some View {
        let handle = Rectangle()
            .fill(isSelected || isHovering ? accent.opacity(0.22) : Color.clear)
            .frame(width: 7)
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                Rectangle().fill(isSelected || isHovering ? accent : Color.clear).frame(width: 2)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
        if edge == .leading {
            handle.highPriorityGesture(leftTrimGesture)
        } else {
            handle.highPriorityGesture(rightTrimGesture)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if clip.kind == .audio, NSEvent.modifierFlags.contains(.option) {
                    let origin = slipOriginSeconds ?? clip.slipOffsetSeconds
                    if slipOriginSeconds == nil { slipOriginSeconds = origin }
                    let secondsPerBeat = 60 / max(projectBPM, 1)
                    slipPreviewSeconds = origin - Double(value.translation.width / beatWidth) * secondsPerBeat
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

    /// The left edge moves the event's start and where it enters its loop, so
    /// the audio under every beat stays put, as in ACID.
    private var leftTrimGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = leftTrimOrigin ?? (clip.startBeat, clip.lengthBeats, clip.loopOffsetBeats)
                if leftTrimOrigin == nil { leftTrimOrigin = origin }
                let end = origin.start + origin.length
                let raw = origin.start + Double(value.translation.width / beatWidth)
                let snapped = min(snap(raw, origin.start), end - minimumLength)
                clip.startBeat = max(0, snapped)
                clip.lengthBeats = max(minimumLength, end - clip.startBeat)
                var offset = origin.offset + (clip.startBeat - origin.start)
                if let cycle = cycleBeats, cycle > 0 {
                    offset = offset.truncatingRemainder(dividingBy: cycle)
                    if offset < 0 { offset += cycle }
                }
                clip.loopOffsetBeats = max(0, offset)
            }
            .onEnded { _ in leftTrimOrigin = nil }
    }

    /// The right edge only sets length. Past the end of the source the event
    /// keeps repeating its loop.
    private var rightTrimGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let origin = rightTrimOrigin ?? clip.lengthBeats
                if rightTrimOrigin == nil { rightTrimOrigin = origin }
                let originalEnd = clip.startBeat + origin
                let rawEnd = originalEnd + Double(value.translation.width / beatWidth)
                let snappedEnd = snap(rawEnd, originalEnd)
                clip.lengthBeats = min(
                    max(minimumLength, snappedEnd - clip.startBeat),
                    max(minimumLength, maximumBeat - clip.startBeat)
                )
            }
            .onEnded { _ in rightTrimOrigin = nil }
    }

    private var minimumLength: Double {
        max(0.001, 6 / Double(max(beatWidth, 1)))
    }
}

// MARK: - Clip content

/// A pattern region drawn as DrumKit step cells, repeated across the region.
/// Each repeat of the pattern gets a notch at the top, like ACID's loop marks.
private struct LYPatternCells: View {
    let steps: [Bool]
    let velocities: [Double]
    let accent: Color
    let beatWidth: CGFloat
    let lengthBeats: Double
    let loopOffsetBeats: Double

    var body: some View {
        Canvas { context, size in
            let count = steps.count
            guard count > 0 else { return }
            let stepWidth = beatWidth * CGFloat(lyBeatsPerStep)
            let total = Int(ceil(lengthBeats / lyBeatsPerStep))
            let offset = Int((loopOffsetBeats / lyBeatsPerStep).rounded())
            let gap: CGFloat = stepWidth >= 9 ? 2 : (stepWidth >= 4 ? 1 : 0)
            let cell = max(1, stepWidth - gap)
            let side = min(cell, max(4, size.height - 10))
            let y = (size.height - side) / 2

            for i in 0..<total {
                let index = ((i + offset) % count + count) % count
                let x = CGFloat(i) * stepWidth + gap / 2
                if x > size.width { break }
                if index == 0 && i > 0 {
                    context.fill(Path(CGRect(x: x - gap / 2, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.45)))
                    var notch = Path()
                    notch.move(to: CGPoint(x: x - gap / 2 - 3, y: 0))
                    notch.addLine(to: CGPoint(x: x - gap / 2 + 3, y: 0))
                    notch.addLine(to: CGPoint(x: x - gap / 2, y: 4))
                    notch.closeSubpath()
                    context.fill(notch, with: .color(accent))
                }
                let rect = CGRect(x: x, y: stepWidth >= 4 ? y : 3, width: cell, height: stepWidth >= 4 ? side : size.height - 6)
                if steps[index] {
                    let velocity = velocities.indices.contains(index) ? velocities[index] : 0.82
                    context.fill(Path(rect), with: .color(accent.opacity(0.42 + 0.58 * min(max(velocity, 0), 1))))
                } else if stepWidth >= 6 {
                    context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color.white.opacity(0.07)), lineWidth: 1)
                }
            }
        }
    }
}

/// An audio event's waveform, mirrored around its centre line, following the
/// event through every pass of its loop. Loop seams get the same notch.
private struct LYEventWaveform: View {
    let peaks: [Float]
    let accent: Color
    let gain: Double
    let beatWidth: CGFloat
    let lengthBeats: Double
    let cycleBeats: Double
    let loopOffsetBeats: Double
    let sourceStart: Double
    let sourceDuration: Double
    let fileDuration: Double

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            context.fill(Path(CGRect(x: 0, y: floor(mid), width: size.width, height: 1)), with: .color(accent.opacity(0.22)))
            guard !peaks.isEmpty, cycleBeats > 0, fileDuration > 0, sourceDuration > 0 else { return }

            let column: CGFloat = 2
            var x: CGFloat = 0
            var fill = Path()
            let scale = min(1.6, max(0, gain))
            while x < size.width {
                let beat = Double(x / beatWidth) + loopOffsetBeats
                let intoCycle = beat.truncatingRemainder(dividingBy: cycleBeats)
                let time = sourceStart + intoCycle / cycleBeats * sourceDuration
                let bucket = Int(time / fileDuration * Double(peaks.count))
                let peak = peaks.indices.contains(bucket) ? CGFloat(peaks[bucket]) : 0
                let h = min(mid - 1, max(0.5, peak * CGFloat(scale) * (mid - 2)))
                fill.addRect(CGRect(x: x, y: mid - h, width: column - 0.5, height: h * 2))
                x += column
            }
            context.fill(fill, with: .color(accent.opacity(0.78)))

            var seam = cycleBeats - loopOffsetBeats.truncatingRemainder(dividingBy: cycleBeats)
            while seam < lengthBeats - 0.001 {
                let sx = CGFloat(seam) * beatWidth
                context.fill(Path(CGRect(x: sx, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.5)))
                var notch = Path()
                notch.move(to: CGPoint(x: sx - 3, y: 0))
                notch.addLine(to: CGPoint(x: sx + 3, y: 0))
                notch.addLine(to: CGPoint(x: sx, y: 4))
                notch.closeSubpath()
                context.fill(notch, with: .color(accent))
                seam += cycleBeats
            }
        }
    }
}
