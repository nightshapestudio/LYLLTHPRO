import AppKit
import NightshapeAudioEngine
import SwiftUI

/// What the editor needs from the song around the region.
struct LYSirenContext {
    var session: LYLLTHSession
    var trackID: UUID
    /// The original recording for a project audio path, on disk.
    var sourceURL: (String) -> URL?
    /// True from the moment transport starts, including the short interval
    /// before an audio scheduling anchor exists.
    var isTransportRunning: () -> Bool
    /// The song beat being heard, or nil when stopped.
    var songBeat: () -> Double?
}

/// A SIREN-only history. Snapshots wrap the optional edit so "no SIREN edit"
/// is itself an undoable state rather than being confused with an empty stack.
struct LYSirenEditHistory {
    struct Snapshot: Equatable { var edit: LYVocalEdit? }
    private(set) var undo: [Snapshot] = []
    private(set) var redo: [Snapshot] = []

    var canUndo: Bool { !undo.isEmpty }
    var canRedo: Bool { !redo.isEmpty }

    mutating func record(_ edit: LYVocalEdit?) {
        undo.append(Snapshot(edit: edit))
        if undo.count > 64 { undo.removeFirst(undo.count - 64) }
        redo = []
    }

    mutating func undo(current: LYVocalEdit?) -> Snapshot? {
        guard let previous = undo.popLast() else { return nil }
        redo.append(Snapshot(edit: current))
        return previous
    }

    mutating func redo(current: LYVocalEdit?) -> Snapshot? {
        guard let next = redo.popLast() else { return nil }
        undo.append(Snapshot(edit: current))
        return next
    }

    mutating func reset() { undo = []; redo = [] }
}

/// SIREN: tune, flatten, nudge and align a sung part, note by note.
struct LYSirenEditor: View {
    @Binding var clip: LYClip
    let context: LYSirenContext
    let accent: Color

    private enum Mode: String, CaseIterable { case tune = "TUNE", align = "ALIGN" }
    private enum EditTool: String, CaseIterable {
        case pitch = "PITCH"
        case transition = "TRANSITION"
        case vibrato = "VIBRATO"
        case formant = "FORMANT"
    }
    private enum Status: Equatable { case waitingForTransport, listening, ready, aligning, failed(String) }

    @State private var mode: Mode = .tune
    @State private var status: Status = .listening
    @State private var analysis: LYVocalAnalysis?
    @State private var analysisPeak: Float = 1
    /// The notes being edited. Written to the region when a gesture ends,
    /// so a drag re-renders the audio once, not on every frame.
    @State private var notes: [LYVocalNote] = []
    @State private var detectedNotes: [LYVocalNote] = []
    @State private var selection: Set<UUID> = []
    @State private var pixelsPerSecond: CGFloat = 220
    @State private var pixelsPerSemitone: CGFloat = 24
    @State private var editTool: EditTool = .pitch

    // CORRECT
    @State private var centerAmount = 1.0
    @State private var driftAmount = 0.5
    @State private var snapsToKey = false

    // ALIGN
    @State private var guideID: UUID?
    @State private var tightness = 0.8
    @State private var alignsPitch = false
    @State private var guideMenuOpen = false

    // Gestures
    @State private var drag: DragState?
    @State private var marquee: CGRect?
    @State private var zoomDrag: ZoomDragState?
    @State private var magnificationOrigin: (horizontal: CGFloat, vertical: CGFloat)?
    @State private var localHistory = LYSirenEditHistory()
    @State private var isApplyingLocalHistory = false

    private struct NoteOrigin {
        var pitch: Double
        var time: Double
        var vibrato: Double
        var formant: Double
        var pitchTransition: Double
        var formantTransition: Double
    }

    private struct DragState {
        var noteIDs: Set<UUID>
        var origins: [UUID: NoteOrigin]
        var axis: Axis?
        var connector: Bool
        enum Axis { case pitch, time }
    }

    private struct ZoomDragState {
        var horizontal: CGFloat
        var vertical: CGFloat
    }

    /// Note names sit in a fixed column; the canvas scrolls beside it.
    private let labelWidth: CGFloat = 46
    private let gutter: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            LYHairline()
            ZStack {
                LYLLTHTheme.background
                switch status {
                case .waitingForTransport:
                    message("READY WHEN PLAYBACK STOPS", detail: "SIREN is keeping playback clean. Stop transport once to analyze this take.")
                case .listening:
                    message("LISTENING TO THE TAKE", detail: "Finding the pitch and the notes. Long takes need a few seconds.")
                case .failed(let reason):
                    message("SIREN COULD NOT READ THIS EVENT", detail: reason)
                default:
                    if notes.isEmpty {
                        message("NO SUNG NOTES FOUND", detail: "SIREN works on one voice at a time: a lead, a double, a single instrument line.")
                    } else {
                        noteCanvas
                    }
                }
            }
            LYHairline()
            footer
        }
        .background(LYLLTHTheme.panel)
        .task(id: clip.sourceRelativePath) { await load() }
        // Undo and redo change the region under the editor.
        .onChange(of: clip.vocal) { _, stored in
            guard drag == nil, !isApplyingLocalHistory else { return }
            let restored = stored?.sourceRelativePath == clip.sourceRelativePath ? stored?.notes ?? detectedNotes : detectedNotes
            guard restored != notes else { return }
            notes = restored
            selection = selection.filter { id in restored.contains { $0.id == id } }
        }
        .overlay { guideMenu }
    }

    // MARK: Loading

    private var edit: LYVocalEdit? { clip.vocal?.sourceRelativePath == clip.sourceRelativePath ? clip.vocal : nil }

    private func load() async {
        guard let path = clip.sourceRelativePath, let url = context.sourceURL(path) else {
            status = .failed("The audio file for this event is missing. Relink it in LIBRARY ▸ PROJECT.")
            return
        }
        do {
            let cache = LYVocalAnalysisCache.shared
            let result: (LYVocalAnalysis, [LYVocalNote])
            if let cached = cache.cachedAnalysis(for: url) {
                result = (cached, LYVocalAnalyzer.notes(in: cached))
            } else {
                // Pitch detection is deliberately held off while the song is
                // running. The analyzer is a sustained CPU/Accelerate job;
                // starting it when this panel opens can starve the realtime
                // audio thread and sounds like distortion or added latency.
                status = .waitingForTransport
                while context.isTransportRunning() {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(120))
                    if let cached = cache.cachedAnalysis(for: url) {
                        finishLoading((cached, LYVocalAnalyzer.notes(in: cached)))
                        return
                    }
                }
                try Task.checkCancellation()
                status = .listening
                result = try await Task.detached(priority: .background) {
                    let analysis = try cache.analysis(for: url)
                    return (analysis, LYVocalAnalyzer.notes(in: analysis))
                }.value
            }
            finishLoading(result)
        } catch is CancellationError {
            return
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func finishLoading(_ result: (LYVocalAnalysis, [LYVocalNote])) {
        analysis = result.0
        analysisPeak = max(result.0.level.max() ?? 1, 1e-6)
        detectedNotes = result.1
        notes = edit?.notes ?? detectedNotes
        localHistory.reset()
        guideID = edit?.alignment?.guideClipID
        tightness = edit?.alignment?.tightness ?? tightness
        alignsPitch = edit?.alignment?.alignsPitch ?? alignsPitch
        status = .ready
    }

    /// Writes the notes back to the region, which re-renders its audio.
    private func commit() {
        guard let path = clip.sourceRelativePath else { return }
        var next = edit ?? LYVocalEdit(sourceRelativePath: path, notes: notes)
        next.notes = notes
        applyLocalEdit(next)
    }

    private func applyLocalEdit(_ next: LYVocalEdit?, recordingHistory: Bool = true) {
        guard next != clip.vocal else { return }
        if recordingHistory {
            localHistory.record(clip.vocal)
        }
        isApplyingLocalHistory = true
        clip.vocal = next
        notes = next?.sourceRelativePath == clip.sourceRelativePath ? next?.notes ?? detectedNotes : detectedNotes
        selection = selection.filter { id in notes.contains { $0.id == id } }
        DispatchQueue.main.async { isApplyingLocalHistory = false }
    }

    private func undoSiren() {
        guard let previous = localHistory.undo(current: clip.vocal) else { return }
        applyLocalEdit(previous.edit, recordingHistory: false)
    }

    private func redoSiren() {
        guard let next = localHistory.redo(current: clip.vocal) else { return }
        applyLocalEdit(next.edit, recordingHistory: false)
    }

    private func removeSiren() {
        guard clip.vocal != nil else { return }
        applyLocalEdit(nil)
        guideID = nil
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Button(item.rawValue) { mode = item }
                            .buttonStyle(LYChromeButtonStyle(active: mode == item, tint: accent, compact: true))
                    }
                }
                if mode == .tune {
                    Rectangle().fill(LYLLTHTheme.line).frame(width: 1, height: 22)
                    editToolControls
                }
                Spacer(minLength: 8)
                zoomControls
                Button("UNDO") { undoSiren() }
                    .buttonStyle(LYChromeButtonStyle(compact: true))
                    .disabled(!localHistory.canUndo)
                    .help("Undo the last SIREN edit (Command-Z)")
                Button("REDO") { redoSiren() }
                    .buttonStyle(LYChromeButtonStyle(compact: true))
                    .disabled(!localHistory.canRedo)
                    .help("Redo the last SIREN edit (Shift-Command-Z)")
                let bypassed = clip.vocal?.isBypassed == true
                Button(bypassed ? "BYPASSED" : "A / B") {
                    guard var next = clip.vocal else { return }
                    next.isBypassed.toggle()
                    applyLocalEdit(next)
                }
                .buttonStyle(LYChromeButtonStyle(active: bypassed, tint: LYLLTHTheme.purple, compact: true))
                .disabled(clip.vocal == nil)
                .help("Hear the original take while keeping every edit")
                Button("REMOVE SIREN") { removeSiren() }
                    .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.purple, compact: true))
                    .disabled(clip.vocal == nil)
                    .help("Remove every SIREN edit from this event and play its original recording")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            LYHairline()
            HStack(spacing: 10) {
                if mode == .tune { tuneControls } else { alignControls }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
        }
        .background(LYLLTHTheme.panel)
    }

    private var editToolControls: some View {
        HStack(spacing: 3) {
            ForEach(EditTool.allCases, id: \.self) { tool in
                Button { editTool = tool } label: {
                    Text(tool.rawValue)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(LYChromeButtonStyle(active: editTool == tool, tint: accent, compact: true))
                .help(toolHelp(tool))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tuneControls: some View {
        HStack(spacing: 10) {
            percentSlider("PITCH", $centerAmount, help: "How far each note's center moves onto the nearest pitch")
            percentSlider("DRIFT", $driftAmount, help: "How much of the slow rise or fall across each note is removed")
            Button(snapsToKey ? keyName : "CHROMATIC") { snapsToKey.toggle() }
                .buttonStyle(LYChromeButtonStyle(active: snapsToKey, tint: accent, compact: true))
                .help(snapsToKey ? "Notes move to the song's key. Click for every semitone." : "Notes move to the nearest semitone. Click to use the song's key.")
            Button(selection.isEmpty ? "CORRECT ALL" : "CORRECT \(selection.count)") { correct() }
                .buttonStyle(LYChromeButtonStyle(active: true, tint: accent, compact: true))
                .help("Pull the notes onto pitch by the amounts set here")
            Button("JOIN") { join() }
                .buttonStyle(LYChromeButtonStyle(compact: true))
                .disabled(!canJoin)
                .help("Merge the selected neighboring notes into one")
            Button(selection.isEmpty ? "RESET ALL" : "RESET") { reset() }
                .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.purple, compact: true))
                .help("Put notes back exactly as sung")
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Text("H").font(LYLLTHTheme.label(7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
            Button { zoom(horizontal: 1 / 1.35, vertical: 1) } label: { Image(systemName: "minus") }
            Button { zoom(horizontal: 1.35, vertical: 1) } label: { Image(systemName: "plus") }
            Text("V").font(LYLLTHTheme.label(7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
            Button { zoom(horizontal: 1, vertical: 1 / 1.25) } label: { Image(systemName: "minus") }
            Button { zoom(horizontal: 1, vertical: 1.25) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(LYChromeButtonStyle(compact: true))
        .fixedSize(horizontal: true, vertical: false)
        .help("Horizontal and vertical zoom. You can also Command-Option-drag in the editor or pinch.")
    }

    private func toolHelp(_ tool: EditTool) -> String {
        switch tool {
        case .pitch: return "Drag notes vertically to tune and horizontally to move them"
        case .transition: return "Drag a note-to-note connector vertically to move the pitch transition earlier or later"
        case .vibrato: return "Drag notes vertically to reduce or exaggerate their vibrato"
        case .formant: return "Drag notes vertically to shift vocal color without changing pitch; drag connectors for formant transitions"
        }
    }

    private var alignControls: some View {
        HStack(spacing: 10) {
            Text("GUIDE")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(LYLLTHTheme.secondary)
            Button {
                guideMenuOpen = true
            } label: {
                HStack(spacing: 6) {
                    Text(guideName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .buttonStyle(LYChromeButtonStyle(active: guideID != nil, tint: accent, compact: true))
            .lyMenuAnchor("siren.guide")
            .help("The performance this one should follow")
            percentSlider("TIGHT", $tightness, help: "How closely the timing follows the guide. Lower keeps more of this take's feel.")
            Button(alignsPitch ? "PITCH TOO" : "TIMING ONLY") { alignsPitch.toggle() }
                .buttonStyle(LYChromeButtonStyle(active: alignsPitch, tint: accent, compact: true))
                .help(alignsPitch ? "Notes also move to the guide's pitch" : "Only the timing changes")
            Button(status == .aligning ? "ALIGNING…" : "ALIGN") { Task { await align() } }
                .buttonStyle(LYChromeButtonStyle(active: true, tint: accent, compact: true))
                .disabled(guideID == nil || status == .aligning)
            Button("CLEAR") {
                guard var next = clip.vocal else { return }
                next.alignment = nil
                applyLocalEdit(next)
            }
            .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.purple, compact: true))
            .disabled(clip.vocal?.alignment == nil)
            .help("Put the timing back the way it was sung")
        }
    }

    private func percentSlider(_ label: String, _ value: Binding<Double>, help: String) -> some View {
        HStack(spacing: 5) {
            LYMiniSlider(label: label, value: value, range: 0...1, tint: accent)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 34, alignment: .leading)
        }
        .help(help)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(footerHelp)
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(LYLLTHTheme.dim)
                .lineLimit(1)
            Spacer()
            if !notes.isEmpty {
                mixedNumericLabel("\(notes.count) NOTES  ·  \(notes.filter(\.isEdited).count) EDITED",
                                  labelFont: LYLLTHTheme.label(7.5, weight: .bold), numberFont: LYLLTHTheme.value(9))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private var footerHelp: String {
        guard mode == .tune else { return "PICK THE GUIDE, SET HOW TIGHT, PRESS ALIGN  ·  THE NOTES STAY EDITABLE AFTERWARDS" }
        switch editTool {
        case .pitch: return "DRAG UP/DOWN TO RETUNE  ·  ⌥ FOR CENTS  ·  SIDEWAYS TO MOVE  ·  DOUBLE-CLICK TO SPLIT"
        case .transition: return "DRAG THE / \\ CONNECTOR UP OR DOWN TO MOVE THE PITCH TRANSITION EARLIER OR LATER"
        case .vibrato: return "DRAG UP TO ADD VIBRATO, DOWN TO REDUCE IT  ·  100% IS THE ORIGINAL PERFORMANCE"
        case .formant: return "DRAG UP/DOWN TO SHIFT FORMANTS  ·  DRAG A CONNECTOR TO SHAPE THE FORMANT TRANSITION"
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(LYLLTHTheme.label(11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(LYLLTHTheme.text)
            Text(detail)
                .font(LYLLTHTheme.body(12.5))
                .foregroundStyle(LYLLTHTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    // MARK: Geometry

    /// The part of the recording the region plays, in source seconds.
    private var visibleRange: ClosedRange<Double> {
        let start = max(0, clip.sourceStartSeconds + clip.slipOffsetSeconds)
        let length = clip.sourceDurationSeconds ?? max((analysis?.duration ?? 0) - start, 0)
        return start...(start + max(length, 0.5))
    }

    private var pitchRange: ClosedRange<Double> {
        let pitches = notes.flatMap { [$0.detectedPitch, $0.pitch] }
        let low = (pitches.min() ?? 55).rounded(.down) - 4
        let high = (pitches.max() ?? 67).rounded(.up) + 4
        return low...max(high, low + 12)
    }

    private func outputTime(_ source: Double) -> Double {
        LYWarp.output(atSource: source, clip.vocal?.alignment?.points ?? [])
    }

    private func x(_ time: Double) -> CGFloat { gutter + CGFloat(time - visibleRange.lowerBound) * pixelsPerSecond }
    private func time(_ x: CGFloat) -> Double { visibleRange.lowerBound + Double((x - gutter) / pixelsPerSecond) }
    private func y(_ pitch: Double, height: CGFloat) -> CGFloat {
        let inset: CGFloat = 12
        return inset + CGFloat(pitchRange.upperBound - pitch) * pixelsPerSemitone
    }


    private func canvasHeight(viewport: CGFloat) -> CGFloat {
        max(viewport, CGFloat(pitchRange.upperBound - pitchRange.lowerBound) * pixelsPerSemitone + 24)
    }

    private var noteHalfHeight: CGFloat { max(5, pixelsPerSemitone * 0.44) }

    private func frame(of note: LYVocalNote, height: CGFloat) -> CGRect {
        let start = outputTime(note.start) + note.timeOffset
        let end = outputTime(note.end) + note.timeOffset
        let center = y(note.pitch, height: height)
        return CGRect(x: x(start), y: center - noteHalfHeight, width: max(4, x(end) - x(start)), height: noteHalfHeight * 2)
    }

    // MARK: Canvas

    private var noteCanvas: some View {
        GeometryReader { geo in
            let height = canvasHeight(viewport: geo.size.height)
            let width = max(geo.size.width - labelWidth, x(visibleRange.upperBound) + 40)
            let tileWidth: CGFloat = 1_024
            let tileCount = max(1, Int(ceil(width / tileWidth)))
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    Canvas { graphics, size in drawLabels(in: &graphics, size: size) }
                        .frame(width: labelWidth, height: height)
                        .background(LYLLTHTheme.panel)
                        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                    // A whole-song Canvas becomes a tens-of-thousands-pixel
                    // backing surface for an ordinary vocal. Tiled lazy
                    // canvases keep drawing bounded to the visible viewport.
                    LazyHStack(spacing: 0) {
                        ForEach(0..<tileCount, id: \.self) { tile in
                            let origin = CGFloat(tile) * tileWidth
                            let localWidth = min(tileWidth, width - origin)
                            Canvas(rendersAsynchronously: true) { graphics, size in
                                draw(in: &graphics, size: size, originX: origin)
                            }
                            .frame(width: localWidth, height: height)
                        }
                    }
                    .frame(width: width, height: height, alignment: .leading)
                    if let marquee {
                        Rectangle()
                            .fill(LYLLTHTheme.purple.opacity(0.08))
                            .overlay(Rectangle().stroke(LYLLTHTheme.purple.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .frame(width: marquee.width, height: marquee.height)
                            .offset(x: marquee.minX, y: marquee.minY)
                            .allowsHitTesting(false)
                    }
                    LYSirenPlayhead(
                        songBeat: context.songBeat,
                        position: { beat in playheadX(songBeat: beat) },
                        height: height
                    )
                    .allowsHitTesting(false)
                        }
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                        .gesture(canvasGesture(height: height))
                        .simultaneousGesture(magnificationGesture)
                        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { split(at: $0.location, height: height) })
                        .simultaneousGesture(SpatialTapGesture().onEnded { tap(at: $0.location, height: height) })
                    }
                    .scrollIndicators(.visible)
                }
                .frame(height: height, alignment: .top)
            }
            .scrollIndicators(.visible)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow, phases: .down) { press in nudge(press.modifiers.contains(.option) ? 0.1 : 1); return .handled }
        .onKeyPress(.downArrow, phases: .down) { press in nudge(press.modifiers.contains(.option) ? -0.1 : -1); return .handled }
        .onKeyPress(characters: .init(charactersIn: "a"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection = Set(notes.map(\.id)); return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "z"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) { redoSiren() } else { undoSiren() }
            return .handled
        }
    }

    private func playheadX(songBeat: Double) -> CGFloat? {
        let bpm = max(context.session.bpm, 1)
        let offset = (songBeat - clip.startBeat + clip.loopOffsetBeats) * 60 / bpm
        guard offset >= 0, songBeat <= clip.startBeat + clip.lengthBeats else { return nil }
        return x(visibleRange.lowerBound + offset)
    }

    private func drawLabels(in graphics: inout GraphicsContext, size: CGSize) {
        let height = size.height
        let key = context.session.songKey ?? .default
        for pitch in stride(from: Int(pitchRange.lowerBound), through: Int(pitchRange.upperBound), by: 1) {
            let top = y(Double(pitch) + 0.5, height: height)
            let rowHeight = y(Double(pitch) - 0.5, height: height) - top
            let inKey = key.scale.contains(((pitch - key.root) % 12 + 12) % 12)
            let isC = pitch % 12 == 0
            let name = SongKey.rootNames[((pitch % 12) + 12) % 12]
            // Note names, octave digits in the number face.
            let label = Text(name).font(LYLLTHTheme.label(8, weight: isC ? .bold : .medium))
                + Text("\(pitch / 12 - 1)").font(LYLLTHTheme.value(8.5))
            graphics.draw(label.foregroundColor(inKey ? LYLLTHTheme.secondary : LYLLTHTheme.dim),
                          at: CGPoint(x: 9, y: top + rowHeight / 2), anchor: .leading)
        }
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, originX: CGFloat) {
        let height = size.height
        let key = context.session.songKey ?? .default
        // Rows: one per semitone, darker on notes outside the key.
        let range = pitchRange
        for pitch in stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: 1) {
            let top = y(Double(pitch) + 0.5, height: height)
            let rowHeight = y(Double(pitch) - 0.5, height: height) - top
            let inKey = key.scale.contains(((pitch - key.root) % 12 + 12) % 12)
            if !inKey {
                graphics.fill(Path(CGRect(x: 0, y: top, width: size.width, height: rowHeight)),
                             with: .color(Color.black.opacity(0.22)))
            }
            let isC = pitch % 12 == 0
            graphics.stroke(Path { $0.move(to: CGPoint(x: 0, y: top)); $0.addLine(to: CGPoint(x: size.width, y: top)) },
                           with: .color(isC ? LYLLTHTheme.lineStrong : LYLLTHTheme.line), lineWidth: isC ? 1 : 0.5)
        }
        // Seconds along the top.
        let tileStartTime = visibleRange.lowerBound + Double(originX / pixelsPerSecond)
        let tileEndTime = visibleRange.lowerBound + Double((originX + size.width) / pixelsPerSecond)
        var second = ceil(tileStartTime)
        while second <= min(visibleRange.upperBound, tileEndTime) {
            let px = x(second) - originX
            graphics.stroke(Path { $0.move(to: CGPoint(x: px, y: 0)); $0.addLine(to: CGPoint(x: px, y: height)) },
                           with: .color(LYLLTHTheme.line), lineWidth: 0.5)
            graphics.draw(Text("\(Int(second))s").font(LYLLTHTheme.value(8)).foregroundColor(LYLLTHTheme.dim),
                         at: CGPoint(x: px + 3, y: 8), anchor: .leading)
            second += 1
        }
        guard let analysis else { return }
        let peak = analysisPeak
        let tileRange = originX...(originX + size.width)

        drawConnections(in: &graphics, height: height, originX: originX, tileRange: tileRange)

        for note in notes {
            let selected = selection.contains(note.id)
            let globalRect = frame(of: note, height: height)
            guard globalRect.maxX >= tileRange.lowerBound, globalRect.minX <= tileRange.upperBound else { continue }
            let rect = globalRect.offsetBy(dx: -originX, dy: 0)
            let color = selected ? LYLLTHTheme.purple : accent

            // Ghost where the note was sung, when it has moved.
            if abs(note.pitchOffset) > 0.02 || abs(note.timeOffset) > 0.002 {
                let ghostStart = x(outputTime(note.start)) - originX
                let ghostEnd = x(outputTime(note.end)) - originX
                let ghostY = y(note.detectedPitch, height: height)
                graphics.stroke(Path { $0.move(to: CGPoint(x: ghostStart, y: ghostY)); $0.addLine(to: CGPoint(x: ghostEnd, y: ghostY)) },
                               with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // The blob: as wide as the note, as thick as the singer is loud.
            let steps = max(2, Int(rect.width / 3))
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let sourceTime = note.start + note.duration * fraction
                let level = CGFloat(min(1, analysis.level(at: sourceTime) / peak))
                let thickness = noteHalfHeight * (0.22 + 0.78 * sqrt(level))
                let px = rect.minX + rect.width * CGFloat(fraction)
                let taper = CGFloat(min(1, min(fraction, 1 - fraction) * 8 + 0.15))
                top.append(CGPoint(x: px, y: rect.midY - thickness * taper))
                bottom.append(CGPoint(x: px, y: rect.midY + thickness * taper))
            }
            var blob = Path()
            blob.addLines(top)
            blob.addLines(bottom.reversed())
            blob.closeSubpath()
            if selected {
                // Brightened by its own glow, not a hotter color.
                var glow = graphics
                glow.addFilter(.blur(radius: 6))
                glow.stroke(blob, with: .color(color.opacity(0.7)), lineWidth: 3)
            }
            graphics.fill(blob, with: .color(color.opacity(selected ? 0.30 : 0.16)))
            graphics.stroke(blob, with: .color(color.opacity(selected ? 1 : 0.8)), lineWidth: selected ? 1.6 : 1.1)

            // The pitch line as it will sound: drift and offset applied.
            var line = Path()
            var started = false
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let sourceTime = note.start + note.duration * fraction
                guard let sung = analysis.pitch(at: sourceTime) else { started = false; continue }
                let heard = note.detectedPitch + (sung - note.detectedPitch) * note.drift + note.pitchOffset
                let point = CGPoint(x: rect.minX + rect.width * CGFloat(fraction), y: y(heard, height: height))
                if started { line.addLine(to: point) } else { line.move(to: point); started = true }
            }
            graphics.stroke(line, with: .color(LYLLTHTheme.text.opacity(0.85)), lineWidth: 1.2)

            if editTool == .formant || abs(note.formantShift) > 0.001 {
                let beamY = rect.midY - noteHalfHeight * 0.64 - CGFloat(note.formantShift) * 1.8
                let beam = Path { path in
                    path.move(to: CGPoint(x: rect.minX + min(8, rect.width * 0.2), y: beamY))
                    path.addLine(to: CGPoint(x: rect.maxX - min(8, rect.width * 0.2), y: beamY))
                }
                graphics.stroke(beam, with: .color(LYLLTHTheme.teal.opacity(selected ? 1 : 0.8)), lineWidth: 2.2)
            }

            // How far off pitch the center sits, in cents. Off by more than
            // ten reads in the record pink, with its glow so a thin figure
            // keeps the pink instead of thinning toward red.
            let cents = Int(((note.pitch - note.pitch.rounded()) * 100).rounded())
            if rect.width > 34 {
                let sign = cents > 0 ? "+" : cents < 0 ? "−" : ""
                let off = abs(cents) > 10
                let label = graphics.resolve(Text("\(sign)\(abs(cents))").font(LYLLTHTheme.value(9.5))
                    .foregroundColor(off ? LYLLTHTheme.record : LYLLTHTheme.secondary))
                let at = CGPoint(x: rect.minX + 2, y: rect.minY - 2)
                if off {
                    var glow = graphics
                    glow.addFilter(.blur(radius: 3))
                    glow.draw(label, at: at, anchor: .bottomLeading)
                }
                graphics.draw(label, at: at, anchor: .bottomLeading)
            }

            if selected, rect.width > 48 {
                let value: String?
                switch editTool {
                case .pitch: value = nil
                case .transition: value = String(format: "T %d%%", Int(note.pitchTransition * 100))
                case .vibrato: value = String(format: "V %d%%", Int(note.vibrato * 100))
                case .formant: value = String(format: "F %+.1f", note.formantShift)
                }
                if let value {
                    graphics.draw(Text(value).font(LYLLTHTheme.value(8.5)).foregroundColor(LYLLTHTheme.text),
                                  at: CGPoint(x: rect.midX, y: rect.maxY + 2), anchor: .top)
                }
            }
        }
    }

    private func connectedPairs(height: CGFloat) -> [(left: LYVocalNote, right: LYVocalNote, start: CGPoint, end: CGPoint)] {
        guard notes.count > 1 else { return [] }
        return zip(notes, notes.dropFirst()).compactMap { left, right in
            guard right.start - left.end < 0.08 else { return nil }
            let leftRect = frame(of: left, height: height)
            let rightRect = frame(of: right, height: height)
            let start = CGPoint(x: max(leftRect.midX, leftRect.maxX - max(12, leftRect.width * 0.28)), y: leftRect.midY)
            let end = CGPoint(x: min(rightRect.midX, rightRect.minX + max(12, rightRect.width * 0.28)), y: rightRect.midY)
            return (left, right, start, end)
        }
    }

    private func connectionPath(start: CGPoint, end: CGPoint, position: Double, originX: CGFloat) -> Path {
        let a = CGPoint(x: start.x - originX, y: start.y)
        let b = CGPoint(x: end.x - originX, y: end.y)
        let center = a.x + (b.x - a.x) * CGFloat(min(max(position, 0.05), 0.95))
        return Path { path in
            path.move(to: a)
            path.addCurve(to: b, control1: CGPoint(x: center, y: a.y), control2: CGPoint(x: center, y: b.y))
        }
    }

    private func drawConnections(
        in graphics: inout GraphicsContext,
        height: CGFloat,
        originX: CGFloat,
        tileRange: ClosedRange<CGFloat>
    ) {
        for pair in connectedPairs(height: height) where pair.end.x >= tileRange.lowerBound && pair.start.x <= tileRange.upperBound {
            let selected = selection.contains(pair.left.id) || selection.contains(pair.right.id)
            let pitchPath = connectionPath(start: pair.start, end: pair.end,
                                           position: pair.left.pitchTransition, originX: originX)
            graphics.stroke(pitchPath,
                            with: .color((editTool == .transition ? LYLLTHTheme.purple : LYLLTHTheme.text).opacity(selected ? 0.95 : 0.55)),
                            style: StrokeStyle(lineWidth: editTool == .transition ? 2.4 : 1.5, lineCap: .round))

            if editTool == .formant || abs(pair.left.formantShift) > 0.001 || abs(pair.right.formantShift) > 0.001 {
                let formantStart = CGPoint(x: pair.start.x, y: pair.start.y - noteHalfHeight * 0.64 - CGFloat(pair.left.formantShift) * 1.8)
                let formantEnd = CGPoint(x: pair.end.x, y: pair.end.y - noteHalfHeight * 0.64 - CGFloat(pair.right.formantShift) * 1.8)
                let formantPath = connectionPath(start: formantStart, end: formantEnd,
                                                 position: pair.left.formantTransition, originX: originX)
                graphics.stroke(formantPath, with: .color(LYLLTHTheme.teal.opacity(selected ? 1 : 0.75)),
                                style: StrokeStyle(lineWidth: editTool == .formant ? 2.4 : 1.6, lineCap: .round))
            }
        }
    }

    // MARK: Gestures

    private func note(at point: CGPoint, height: CGFloat) -> LYVocalNote? {
        notes.last { frame(of: $0, height: height).insetBy(dx: -2, dy: -3).contains(point) }
    }

    private func connectorNote(at point: CGPoint, height: CGFloat) -> LYVocalNote? {
        connectedPairs(height: height).first { pair in
            let top = min(pair.start.y, pair.end.y) - 12
            let bottom = max(pair.start.y, pair.end.y) + 12
            return point.x >= pair.start.x - 6 && point.x <= pair.end.x + 6 && point.y >= top && point.y <= bottom
        }?.left
    }

    private func tap(at point: CGPoint, height: CGFloat) {
        let additive = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
        guard let hit = note(at: point, height: height) else {
            if !additive { selection = [] }
            return
        }
        if additive {
            if selection.contains(hit.id) { selection.remove(hit.id) } else { selection.insert(hit.id) }
        } else {
            selection = [hit.id]
        }
    }

    private func canvasGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let modifiers = NSEvent.modifierFlags
                if zoomDrag != nil || (modifiers.contains(.command) && modifiers.contains(.option)) {
                    let origin = zoomDrag ?? ZoomDragState(horizontal: pixelsPerSecond, vertical: pixelsPerSemitone)
                    if zoomDrag == nil { zoomDrag = origin; drag = nil; marquee = nil }
                    pixelsPerSecond = min(max(origin.horizontal * pow(2, value.translation.width / 180), 40), 1_600)
                    pixelsPerSemitone = min(max(origin.vertical * pow(2, -value.translation.height / 160), 10), 72)
                    return
                }
                if drag == nil && marquee == nil {
                    let connector = editTool == .transition || editTool == .formant
                        ? connectorNote(at: value.startLocation, height: height) : nil
                    if let hit = connector ?? note(at: value.startLocation, height: height) {
                        if !selection.contains(hit.id) { selection = [hit.id] }
                        let ids = selection
                        drag = DragState(
                            noteIDs: ids,
                            origins: Dictionary(uniqueKeysWithValues: notes.filter { ids.contains($0.id) }.map {
                                ($0.id, NoteOrigin(pitch: $0.pitchOffset, time: $0.timeOffset,
                                                   vibrato: $0.vibrato, formant: $0.formantShift,
                                                   pitchTransition: $0.pitchTransition,
                                                   formantTransition: $0.formantTransition))
                            }),
                            connector: connector != nil
                        )
                    } else {
                        marquee = CGRect(origin: value.startLocation, size: .zero)
                    }
                }
                if var state = drag {
                    let dx = value.translation.width, dy = value.translation.height
                    if state.axis == nil, max(abs(dx), abs(dy)) > 5 { state.axis = abs(dy) >= abs(dx) ? .pitch : .time }
                    drag = state
                    let fine = NSEvent.modifierFlags.contains(.option)
                    let semitonesPerPixel = Double(pitchRange.upperBound - pitchRange.lowerBound) / Double(height)
                    for index in notes.indices where state.noteIDs.contains(notes[index].id) {
                        guard let origin = state.origins[notes[index].id] else { continue }
                        switch editTool {
                        case .pitch:
                            switch state.axis {
                            case .pitch:
                                let raw = origin.pitch - Double(dy) * semitonesPerPixel
                                if fine {
                                    notes[index].pitchOffset = (raw * 100).rounded() / 100
                                } else {
                                    let target = (notes[index].detectedPitch + raw).rounded()
                                    notes[index].pitchOffset = target - notes[index].detectedPitch
                                }
                            case .time:
                                notes[index].timeOffset = origin.time + Double(dx / pixelsPerSecond)
                            case nil:
                                break
                            }
                        case .transition:
                            notes[index].pitchTransition = min(max(origin.pitchTransition - Double(dy) / 120, 0.05), 0.95)
                        case .vibrato:
                            notes[index].vibrato = min(max(origin.vibrato - Double(dy) / 80, 0), 2)
                        case .formant:
                            if state.connector {
                                notes[index].formantTransition = min(max(origin.formantTransition - Double(dy) / 120, 0.05), 0.95)
                            } else {
                                let sensitivity = fine ? 0.02 : 0.08
                                notes[index].formantShift = min(max(origin.formant - Double(dy) * sensitivity, -12), 12)
                            }
                        }
                    }
                } else if let start = marquee?.origin {
                    let end = value.location
                    _ = start
                    let origin = value.startLocation
                    marquee = CGRect(x: min(origin.x, end.x), y: min(origin.y, end.y),
                                     width: abs(end.x - origin.x), height: abs(end.y - origin.y))
                    if let box = marquee {
                        selection = Set(notes.filter { frame(of: $0, height: height).intersects(box) }.map(\.id))
                    }
                }
            }
            .onEnded { _ in
                if drag != nil { commit() }
                drag = nil
                marquee = nil
                zoomDrag = nil
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let origin = magnificationOrigin ?? (pixelsPerSecond, pixelsPerSemitone)
                if magnificationOrigin == nil { magnificationOrigin = origin }
                let factor = CGFloat(value)
                pixelsPerSecond = min(max(origin.horizontal * factor, 40), 1_600)
                pixelsPerSemitone = min(max(origin.vertical * factor, 10), 72)
            }
            .onEnded { _ in magnificationOrigin = nil }
    }

    private func split(at point: CGPoint, height: CGFloat) {
        guard let hit = note(at: point, height: height), let index = notes.firstIndex(where: { $0.id == hit.id }) else { return }
        let rect = frame(of: hit, height: height)
        let fraction = Double((point.x - rect.minX) / max(rect.width, 1))
        let cut = hit.start + hit.duration * fraction
        guard cut - hit.start > 0.03, hit.end - cut > 0.03 else { return }
        var left = hit, right = hit
        left.end = cut
        right.id = UUID()
        right.start = cut
        if let analysis {
            let pitch = analysis.pitch
            let hop = analysis.hop
            if let center = LYVocalAnalyzer.centerPitch(pitch, Int(left.start / hop)...max(Int(left.start / hop), Int(left.end / hop) - 1)) {
                left.pitchOffset += left.detectedPitch - center; left.detectedPitch = center
            }
            if let center = LYVocalAnalyzer.centerPitch(pitch, Int(right.start / hop)...max(Int(right.start / hop), Int(right.end / hop) - 1)) {
                right.pitchOffset += right.detectedPitch - center; right.detectedPitch = center
            }
        }
        notes.replaceSubrange(index...index, with: [left, right])
        selection = [right.id]
        commit()
    }

    // MARK: Commands

    private var targets: [Int] {
        selection.isEmpty ? Array(notes.indices) : notes.indices.filter { selection.contains(notes[$0].id) }
    }

    private var keyName: String { (context.session.songKey ?? .default).name }

    private func nearestPitch(to pitch: Double) -> Double {
        guard snapsToKey else { return pitch.rounded() }
        let key = context.session.songKey ?? .default
        let candidates = (Int(pitch) - 2...Int(pitch) + 2).filter { key.scale.contains((($0 - key.root) % 12 + 12) % 12) }
        return Double(candidates.min { abs(Double($0) - pitch) < abs(Double($1) - pitch) } ?? Int(pitch.rounded()))
    }

    private func correct() {
        for index in targets {
            let sung = notes[index].detectedPitch
            let target = nearestPitch(to: sung + notes[index].pitchOffset)
            let full = target - sung
            // PITCH moves the center part or all of the way; DRIFT keeps
            // the rest of the movement inside the note.
            notes[index].pitchOffset = notes[index].pitchOffset + (full - notes[index].pitchOffset) * centerAmount
            notes[index].drift = 1 - driftAmount
        }
        commit()
    }

    private func reset() {
        for index in targets {
            notes[index].pitchOffset = 0
            notes[index].drift = 1
            notes[index].vibrato = 1
            notes[index].formantShift = 0
            notes[index].pitchTransition = 0.5
            notes[index].formantTransition = 0.5
            notes[index].gainDB = 0
            notes[index].timeOffset = 0
        }
        commit()
    }

    private func nudge(_ semitones: Double) {
        guard !selection.isEmpty else { return }
        for index in targets { notes[index].pitchOffset = ((notes[index].pitchOffset + semitones) * 100).rounded() / 100 }
        commit()
    }

    private var canJoin: Bool {
        let chosen = notes.filter { selection.contains($0.id) }.sorted { $0.start < $1.start }
        guard chosen.count >= 2 else { return false }
        return zip(chosen, chosen.dropFirst()).allSatisfy { $1.start - $0.end < 0.08 }
    }

    private func join() {
        let chosen = notes.filter { selection.contains($0.id) }.sorted { $0.start < $1.start }
        guard canJoin, let first = chosen.first, let last = chosen.last, let analysis else { return }
        var merged = first
        merged.end = last.end
        let hop = analysis.hop
        let center = LYVocalAnalyzer.centerPitch(analysis.pitch, Int(merged.start / hop)...max(Int(merged.start / hop), Int(merged.end / hop) - 1))
        if let center { merged.pitchOffset = first.pitch - center; merged.detectedPitch = center }
        notes.removeAll { selection.contains($0.id) }
        notes.append(merged)
        notes.sort { $0.start < $1.start }
        selection = [merged.id]
        commit()
    }

    private func zoom(horizontal: CGFloat, vertical: CGFloat) {
        pixelsPerSecond = min(max(pixelsPerSecond * horizontal, 40), 1_600)
        pixelsPerSemitone = min(max(pixelsPerSemitone * vertical, 10), 72)
    }

    // MARK: Align

    private var guideCandidates: [(track: LYTrack, clip: LYClip)] {
        let bpm = max(context.session.bpm, 1)
        let start = clip.startBeat, end = clip.startBeat + clip.lengthBeats
        return context.session.tracks.flatMap { track in
            track.clips.filter { other in
                other.kind == .audio && other.id != clip.id && other.sourceRelativePath != nil
                    && other.startBeat < end && other.startBeat + other.lengthBeats > start
                    && (min(end, other.startBeat + other.lengthBeats) - max(start, other.startBeat)) * 60 / bpm >= 1
            }.map { (track, $0) }
        }
    }

    private var guideName: String {
        guard let guideID, let found = guideCandidates.first(where: { $0.clip.id == guideID }) else {
            return guideCandidates.isEmpty ? "NO OVERLAPPING EVENT" : "CHOOSE"
        }
        return (found.track.name + " · " + found.clip.name).uppercased()
    }

    @ViewBuilder
    private var guideMenu: some View {
        if guideMenuOpen {
            LYDropdownOverlay(anchor: nil, dismiss: { guideMenuOpen = false }) {
                VStack(spacing: 0) {
                    LYNightshapeMenuHeader(eyebrow: "ALIGN TO", title: "GUIDE", accent: accent, close: { guideMenuOpen = false })
                    LYNightshapeMenuDivider()
                    VStack(spacing: 6) {
                        if guideCandidates.isEmpty {
                            Text("Put the guide on another track, overlapping this event by at least a second.")
                                .font(LYLLTHTheme.body(12))
                                .foregroundStyle(LYLLTHTheme.secondary)
                                .frame(width: 280, alignment: .leading)
                        }
                        ForEach(guideCandidates, id: \.clip.id) { item in
                            LYNightshapeMenuRow(icon: "waveform", title: item.clip.name.uppercased(), detail: item.track.name.uppercased(),
                                                accent: accent, action: { guideID = item.clip.id; guideMenuOpen = false })
                        }
                    }
                    .padding(12)
                }
                .frame(width: 320)
                .lyNightshapeMenuChrome(accent: accent)
            }
        }
    }

    private func align() async {
        guard let guideID, let guide = guideCandidates.first(where: { $0.clip.id == guideID })?.clip,
              let dubPath = clip.sourceRelativePath, let dubURL = context.sourceURL(dubPath),
              let guidePath = guide.sourceRelativePath, let guideURL = context.sourceURL(guidePath) else { return }
        guard clip.stretchMode == .off, guide.stretchMode == .off else {
            status = .failed("Turn STRETCH off on both events first. SIREN aligns audio at its recorded speed.")
            return
        }
        status = .aligning
        let bpm = max(context.session.bpm, 1)
        func songSeconds(_ beat: Double) -> Double { beat * 60 / bpm }
        func sourceTime(_ event: LYClip, _ song: Double) -> Double {
            event.sourceStartSeconds + event.slipOffsetSeconds + event.loopOffsetBeats * 60 / bpm + (song - songSeconds(event.startBeat))
        }
        let t0 = songSeconds(max(clip.startBeat, guide.startBeat))
        let t1 = songSeconds(min(clip.startBeat + clip.lengthBeats, guide.startBeat + guide.lengthBeats))
        let tight = tightness, wantsPitch = alignsPitch
        // Positions worked out here, on the main actor, then handed over.
        let guideFrom = sourceTime(guide, t0), guideTo = sourceTime(guide, t1)
        let dubFrom = sourceTime(clip, t0), dubTo = sourceTime(clip, t1)
        do {
            let points = try await Task.detached(priority: .userInitiated) { () -> [LYWarpPoint] in
                let (guideSamples, guideRate) = try LYVocalAnalyzer.monoSamples(url: guideURL)
                let (dubSamples, dubRate) = try LYVocalAnalyzer.monoSamples(url: dubURL)
                func cut(_ samples: [Float], _ rate: Double, from: Double, to: Double) -> [Float] {
                    let a = min(max(0, Int(from * rate)), samples.count), b = min(max(a, Int(to * rate)), samples.count)
                    return Array(samples[a..<b])
                }
                let guidePart = cut(guideSamples, guideRate, from: guideFrom, to: guideTo)
                let dubPart = cut(dubSamples, dubRate, from: dubFrom, to: dubTo)
                let match = LYVocalAligner.path(guide: LYVocalAligner.features(guidePart, sampleRate: guideRate),
                                                dub: LYVocalAligner.features(dubPart, sampleRate: dubRate))
                let origin = dubFrom
                let hop = LYVocalAligner.hopSeconds
                return LYVocalAligner.warp(match: match, tightness: tight,
                                           outputTime: { origin + Double($0) * hop },
                                           sourceTime: { origin + Double($0) * hop })
            }.value
            guard !points.isEmpty else { status = .failed("The two events do not overlap enough to compare."); return }
            if wantsPitch, let guideAnalysis = try? await Task.detached(priority: .userInitiated, operation: {
                try LYVocalAnalysisCache.shared.analysis(for: guideURL)
            }).value {
                for index in notes.indices {
                    let outStart = LYWarp.output(atSource: notes[index].start, points)
                    let outEnd = LYWarp.output(atSource: notes[index].end, points)
                    // Output time in the double's file, to song time, to the guide's file.
                    let song0 = t0 + (outStart - dubFrom), song1 = t0 + (outEnd - dubFrom)
                    let g0 = sourceTime(guide, song0), g1 = sourceTime(guide, song1)
                    let range = guideAnalysis.frame(at: g0)...max(guideAnalysis.frame(at: g0), guideAnalysis.frame(at: g1))
                    if let target = LYVocalAnalyzer.centerPitch(guideAnalysis.pitch, range),
                       abs(target - notes[index].detectedPitch) <= 12 {
                        notes[index].pitchOffset = target - notes[index].detectedPitch
                    }
                }
            }
            guard let path = clip.sourceRelativePath else { return }
            var next = edit ?? LYVocalEdit(sourceRelativePath: path, notes: notes)
            next.notes = notes
            next.alignment = LYVocalAlignment(guideClipID: guideID, tightness: tightness, alignsPitch: alignsPitch, points: points)
            applyLocalEdit(next)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

/// The playhead, redrawn on the display clock. Only this leaf watches the
/// transport, so the note canvas never redraws while the song plays.
private struct LYSirenPlayhead: View {
    let songBeat: () -> Double?
    let position: (Double) -> CGFloat?
    let height: CGFloat
    @State private var x: CGFloat?
    @State private var token: LYFrameToken?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let x {
                Rectangle().fill(LYLLTHTheme.chrome).frame(width: 1, height: height).offset(x: x)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            token = LYFrameClock.shared.add {
                let next = songBeat().flatMap(position)
                if next != x { x = next }
            }
        }
        .onDisappear { token?.cancel(); token = nil }
    }
}
