import SwiftUI
import AppKit

/// The piano roll: a note clip's notes on a pitch-by-time grid, keys down
/// the left, velocity along the bottom. Everything is drawn on one canvas so
/// keys, grid, velocity and playhead always scroll and zoom together.
struct LYPianoRoll: View {
    @Binding var clip: LYClip
    let trackName: String
    let accent: Color
    let instrument: LYSynthInstrument?
    let beatsPerBar: Double
    /// The song beat being heard, or nil when stopped.
    let songBeat: () -> Double?
    /// Draws once, without the live clock or AppKit input, for offscreen renders.
    var isStaticPreview = false

    @State private var pixelsPerBeat: CGFloat = 96
    @State private var rowHeight: CGFloat = 14
    @State private var offset = CGPoint(x: 0, y: 0)
    @State private var snap: Double = 0.25
    @State private var selection: Set<UUID> = []
    @State private var gesture: GestureMode?
    @State private var rubberBand: CGRect?
    @State private var lastLength: Double = 0.5
    @State private var didPlaceView = false
    @State private var auditioning: Int?

    private let keyWidth: CGFloat = 58
    private let rulerHeight: CGFloat = 22
    private let velocityHeight: CGFloat = 78

    private enum GestureMode {
        case move(origins: [UUID: LYNote], anchor: CGPoint, hit: UUID)
        case resize(origins: [UUID: LYNote], anchor: CGPoint)
        case band(anchor: CGPoint, additive: Bool)
        case create(anchor: CGPoint)
        case velocity(id: UUID)
    }

    private static let snaps: [(String, Double)] = [("1/4", 1), ("1/8", 0.5), ("1/16", 0.25), ("1/32", 0.125), ("1/8T", 1.0 / 3), ("1/16T", 1.0 / 6), ("OFF", 0)]

    private var notes: [LYNote] { clip.notes ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geo in
                let size = geo.size
                if isStaticPreview {
                    Canvas { context, canvasSize in draw(&context, size: canvasSize, playhead: playheadBeat(Date())) }
                        .onAppear { placeView(size: size) }
                } else {
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation) { timeline in
                        Canvas { context, canvasSize in
                            draw(&context, size: canvasSize, playhead: playheadBeat(timeline.date))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: size))
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in doubleTap(at: tap.location, size: size) })
                    LYScrollCatcher { dx, dy, zoom in scroll(dx: dx, dy: dy, zoom: zoom, size: size) }
                        .allowsHitTesting(false)
                }
                .clipped()
                .onAppear { placeView(size: size) }
                }
            }
            .background(LYPianoRollKeys(isEnabled: true) { key, flags in handleKey(key, flags: flags) })
        }
        .background(Color(hex: 0x07080B))
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name)
                    .font(LYLLTHTheme.label(11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.text)
                Text("\(trackName)  ·  \(notes.count) NOTE\(notes.count == 1 ? "" : "S")")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(accent)
            }
            .frame(width: 180, alignment: .leading)

            HStack(spacing: 2) {
                Text("SNAP").font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.dim).padding(.trailing, 4)
                ForEach(Self.snaps, id: \.0) { item in
                    Button(item.0) { snap = item.1 }
                        .buttonStyle(LYChromeButtonStyle(active: snap == item.1, compact: true))
                }
            }

            Button("QUANTIZE") { quantize() }
                .buttonStyle(LYChromeButtonStyle(compact: true))
                .help("Snap the selected notes (or all of them) to the grid (Q)")

            LYSynthStepper(label: "LOOP", text: bars(clip.noteCycleBeats), accent: accent) { step in
                let next = max(beatsPerBar, clip.noteCycleBeats + Double(step) * beatsPerBar)
                clip.noteLoopBeats = next
                if clip.lengthBeats < next { clip.lengthBeats = next }
            }
            .help("How long the clip's content is before it repeats")

            Spacer()

            HStack(spacing: 2) {
                zoomButton("minus.magnifyingglass") { pixelsPerBeat = max(16, pixelsPerBeat / 1.3) }
                zoomButton("plus.magnifyingglass") { pixelsPerBeat = min(640, pixelsPerBeat * 1.3) }
            }
            Text("CLICK TO ADD · DRAG TO MOVE · EDGE TO RESIZE · ⌫ DELETE · ↑↓ TRANSPOSE · ⌘ SCROLL ZOOMS")
                .font(LYLLTHTheme.label(6.5, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(LYLLTHTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func zoomButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(LYLLTHTheme.chromeText)
                .frame(width: 28, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bars(_ beats: Double) -> String {
        let value = beats / max(beatsPerBar, 1)
        return value == value.rounded() ? "\(Int(value)) BAR\(value == 1 ? "" : "S")" : String(format: "%.2f", value)
    }

    // MARK: Geometry

    private func gridRect(_ size: CGSize) -> CGRect {
        CGRect(x: keyWidth, y: rulerHeight, width: max(1, size.width - keyWidth), height: max(1, size.height - rulerHeight - velocityHeight))
    }

    private func x(_ beat: Double) -> CGFloat { keyWidth + CGFloat(beat) * pixelsPerBeat - offset.x }
    private func y(_ pitch: Int) -> CGFloat { rulerHeight + CGFloat(127 - pitch) * rowHeight - offset.y }
    private func beat(atX px: CGFloat) -> Double { Double((px - keyWidth + offset.x) / pixelsPerBeat) }
    private func pitch(atY py: CGFloat) -> Int { 127 - Int(floor((py - rulerHeight + offset.y) / rowHeight)) }

    private func noteRect(_ note: LYNote) -> CGRect {
        CGRect(x: x(note.start), y: y(note.pitch), width: max(3, CGFloat(note.length) * pixelsPerBeat), height: rowHeight)
    }

    private func snapped(_ beat: Double) -> Double {
        guard snap > 0 else { return beat }
        return (beat / snap).rounded() * snap
    }

    private func snappedDown(_ beat: Double) -> Double {
        guard snap > 0 else { return beat }
        return floor(beat / snap + 0.000_1) * snap
    }

    private var contentBeats: Double { max(clip.noteCycleBeats, clip.lengthBeats) }

    /// First look: the notes (or middle C) in the middle of the view.
    private func placeView(size: CGSize) {
        guard !didPlaceView else { return }
        didPlaceView = true
        let grid = gridRect(size)
        let pitches = notes.map(\.pitch)
        let centre = pitches.isEmpty ? 60 : (pitches.min()! + pitches.max()!) / 2
        offset.y = max(0, CGFloat(127 - centre) * rowHeight - grid.height / 2)
        pixelsPerBeat = min(max((grid.width - 20) / CGFloat(max(contentBeats, 1)), 24), 220)
        lastLength = snap > 0 ? snap * 2 : 0.5
    }

    private func scroll(dx: CGFloat, dy: CGFloat, zoom: Bool, size: CGSize) {
        if zoom {
            let factor = exp(-dy / 200)
            pixelsPerBeat = min(max(pixelsPerBeat * factor, 16), 640)
            return
        }
        let grid = gridRect(size)
        let maxX = max(0, CGFloat(contentBeats + 8) * pixelsPerBeat - grid.width)
        let maxY = max(0, 128 * rowHeight - grid.height)
        offset.x = min(max(offset.x - dx, 0), maxX)
        offset.y = min(max(offset.y - dy, 0), maxY)
    }

    private func playheadBeat(_ date: Date) -> Double? {
        guard let song = songBeat() else { return nil }
        let into = song - clip.startBeat
        guard into >= 0, into < clip.lengthBeats else { return nil }
        let cycle = clip.noteCycleBeats
        let local = (into + clip.loopOffsetBeats).truncatingRemainder(dividingBy: cycle)
        return local < 0 ? local + cycle : local
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, playhead: Double?) {
        let grid = gridRect(size)
        // Rows: black keys darker, every C marked.
        let firstPitch = max(0, pitch(atY: size.height)), lastPitch = min(127, pitch(atY: rulerHeight))
        if firstPitch <= lastPitch {
            for p in firstPitch...lastPitch {
                let top = y(p)
                let black = [1, 3, 6, 8, 10].contains(p % 12)
                context.fill(Path(CGRect(x: grid.minX, y: top, width: grid.width, height: rowHeight)),
                             with: .color(black ? Color.white.opacity(0.015) : Color.white.opacity(0.04)))
                if p % 12 == 0 {
                    context.fill(Path(CGRect(x: grid.minX, y: top + rowHeight - 1, width: grid.width, height: 1)), with: .color(Color.white.opacity(0.1)))
                }
            }
        }
        // Columns: bars, beats and the snap grid.
        let firstBeat = max(0, floor(beat(atX: grid.minX)))
        let lastBeat = beat(atX: grid.maxX)
        var b = firstBeat
        let fine = snap > 0 && CGFloat(snap) * pixelsPerBeat >= 8 ? snap : 1
        while b <= lastBeat {
            let px = x(b)
            let isBar = abs(b / beatsPerBar - (b / beatsPerBar).rounded()) < 0.000_1
            let isBeat = abs(b - b.rounded()) < 0.000_1
            let alpha = isBar ? 0.16 : (isBeat ? 0.07 : 0.03)
            context.fill(Path(CGRect(x: px, y: grid.minY, width: 1, height: size.height - grid.minY)), with: .color(Color.white.opacity(alpha)))
            if isBar {
                context.draw(Text("\(Int((b / beatsPerBar).rounded()) + 1)").font(LYLLTHTheme.value(8.5)).foregroundColor(LYLLTHTheme.dim),
                             at: CGPoint(x: px + 8, y: rulerHeight / 2))
            }
            b += fine
        }
        // Past the content's loop: the repeat, shaded.
        let loopX = x(clip.noteCycleBeats)
        if loopX < grid.maxX {
            context.fill(Path(CGRect(x: max(loopX, grid.minX), y: grid.minY, width: grid.maxX - max(loopX, grid.minX), height: grid.height)),
                         with: .color(Color.black.opacity(0.45)))
            context.fill(Path(CGRect(x: loopX - 1, y: 0, width: 2, height: size.height)), with: .color(accent.opacity(0.7)))
        }
        // Notes: this clip's, then the repeats of it, dimmer.
        for note in notes {
            let selected = selection.contains(note.id)
            var repeatStart = clip.noteCycleBeats
            while repeatStart < contentBeats + 16, x(repeatStart + note.start) < grid.maxX {
                var ghost = note
                ghost.start += repeatStart
                context.fill(Path(roundedRect: noteRect(ghost), cornerRadius: 2), with: .color(accent.opacity(0.14)))
                repeatStart += clip.noteCycleBeats
            }
            let rect = noteRect(note)
            guard rect.maxX >= grid.minX, rect.minX <= grid.maxX, rect.maxY >= grid.minY, rect.minY <= grid.maxY else { continue }
            let strength = 0.35 + 0.65 * Double(note.velocity) / 127
            context.fill(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 1), cornerRadius: 2), with: .color(accent.opacity(strength * 0.85)))
            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 1), cornerRadius: 2),
                           with: .color(selected ? LYLLTHTheme.text : accent), lineWidth: selected ? 1.5 : 1)
            if rect.width > 34 {
                context.draw(Text(Self.name(note.pitch)).font(LYLLTHTheme.label(6.5, weight: .bold)).foregroundColor(Color.black.opacity(0.75)),
                             at: CGPoint(x: rect.minX + 14, y: rect.midY))
            }
        }
        if let rubberBand {
            context.fill(Path(rubberBand), with: .color(accent.opacity(0.1)))
            context.stroke(Path(rubberBand), with: .color(accent.opacity(0.8)), lineWidth: 1)
        }
        // Playhead.
        if let playhead {
            let px = x(playhead)
            if px >= grid.minX, px <= grid.maxX {
                context.fill(Path(CGRect(x: px - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(LYLLTHTheme.playhead))
            }
        }
        // Keys, over the grid's left edge.
        context.fill(Path(CGRect(x: 0, y: rulerHeight, width: keyWidth, height: size.height - rulerHeight)), with: .color(Color(hex: 0x0B0C10)))
        if firstPitch <= lastPitch {
            for p in firstPitch...lastPitch {
                let top = y(p)
                guard top < grid.maxY else { continue }
                let black = [1, 3, 6, 8, 10].contains(p % 12)
                let lit = auditioning == p
                let keyRect = CGRect(x: black ? 18 : 2, y: top + 0.5, width: black ? keyWidth - 22 : keyWidth - 6, height: rowHeight - 1)
                context.fill(Path(keyRect), with: .color(lit ? accent : (black ? Color(hex: 0x15161B) : LYLLTHTheme.chromeText.opacity(0.85))))
                if p % 12 == 0 {
                    context.draw(Text(Self.name(p)).font(LYLLTHTheme.value(7.5)).foregroundColor(Color.black.opacity(0.7)),
                                 at: CGPoint(x: keyWidth - 20, y: top + rowHeight / 2))
                }
            }
        }
        // Ruler and velocity lane.
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: rulerHeight)), with: .color(LYLLTHTheme.panel))
        if let first = (0...Int(max(0, lastBeat))).first(where: { Double($0) >= firstBeat }) {
            var bar = Double(first)
            while bar <= lastBeat {
                if abs(bar / beatsPerBar - (bar / beatsPerBar).rounded()) < 0.000_1 {
                    context.draw(Text("\(Int((bar / beatsPerBar).rounded()) + 1)").font(LYLLTHTheme.value(8.5)).foregroundColor(LYLLTHTheme.text),
                                 at: CGPoint(x: x(bar) + 8, y: rulerHeight / 2))
                }
                bar += 1
            }
        }
        let lane = CGRect(x: keyWidth, y: size.height - velocityHeight, width: size.width - keyWidth, height: velocityHeight)
        context.fill(Path(CGRect(x: 0, y: lane.minY, width: size.width, height: velocityHeight)), with: .color(Color(hex: 0x0B0C10)))
        context.fill(Path(CGRect(x: 0, y: lane.minY, width: size.width, height: 1)), with: .color(LYLLTHTheme.lineStrong))
        context.draw(Text("VELOCITY").font(LYLLTHTheme.label(6.5, weight: .bold)).foregroundColor(LYLLTHTheme.dim),
                     at: CGPoint(x: keyWidth / 2, y: lane.minY + 12))
        for note in notes {
            let px = x(note.start)
            guard px >= lane.minX - 4, px <= lane.maxX else { continue }
            let h = (lane.height - 14) * CGFloat(note.velocity) / 127
            let selected = selection.contains(note.id)
            context.fill(Path(CGRect(x: px, y: lane.maxY - 4 - h, width: 2, height: h)), with: .color(selected ? LYLLTHTheme.text : accent))
            context.fill(Path(ellipseIn: CGRect(x: px - 3, y: lane.maxY - 4 - h - 3, width: 8, height: 6)), with: .color(selected ? LYLLTHTheme.text : accent))
        }
    }

    static func name(_ pitch: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[((pitch % 12) + 12) % 12] + "\(pitch / 12 - 1)"
    }

    // MARK: Editing

    private func setNotes(_ next: [LYNote]) {
        clip.notes = next.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    private func hit(_ point: CGPoint) -> LYNote? {
        notes.last { noteRect($0).insetBy(dx: 0, dy: 0).contains(point) }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let grid = gridRect(size)
                let flags = NSEvent.modifierFlags
                if gesture == nil {
                    let start = drag.startLocation
                    if start.x < keyWidth && start.y > rulerHeight && start.y < grid.maxY {
                        audition(pitch(atY: start.y))
                        return
                    }
                    if start.y >= size.height - velocityHeight {
                        // The stem nearest the pointer.
                        if let note = notes.min(by: { abs(x($0.start) - start.x) < abs(x($1.start) - start.x) }),
                           abs(x(note.start) - start.x) < 10 {
                            gesture = .velocity(id: note.id)
                        }
                    } else if let note = hit(start) {
                        if !selection.contains(note.id) {
                            selection = flags.contains(.shift) ? selection.union([note.id]) : [note.id]
                        }
                        let origins = Dictionary(uniqueKeysWithValues: notes.filter { selection.contains($0.id) }.map { ($0.id, $0) })
                        if noteRect(note).maxX - start.x < 7 {
                            gesture = .resize(origins: origins, anchor: start)
                        } else {
                            // Option-drag copies the notes and moves the copies.
                            if flags.contains(.option) {
                                let copies = origins.values.map { original -> LYNote in var copy = original; copy.id = UUID(); return copy }
                                setNotes(notes + copies)
                                selection = Set(copies.map(\.id))
                                let copyOrigins = Dictionary(uniqueKeysWithValues: copies.map { ($0.id, $0) })
                                gesture = .move(origins: copyOrigins, anchor: start, hit: copies.first?.id ?? note.id)
                            } else {
                                gesture = .move(origins: origins, anchor: start, hit: note.id)
                            }
                            audition(note.pitch)
                        }
                    } else if start.y > rulerHeight {
                        gesture = .create(anchor: start)
                    }
                }
                switch gesture {
                case .move(let origins, let anchor, let hitID):
                    guard let hitOrigin = origins[hitID] else { return }
                    let rawStart = hitOrigin.start + Double((drag.location.x - anchor.x) / pixelsPerBeat)
                    let deltaBeats = snapped(rawStart) - hitOrigin.start
                    let deltaPitch = Int(((anchor.y - drag.location.y) / rowHeight).rounded())
                    var next = notes
                    for index in next.indices {
                        guard let origin = origins[next[index].id] else { continue }
                        next[index].start = max(0, origin.start + deltaBeats)
                        next[index].pitch = min(max(origin.pitch + deltaPitch, 0), 127)
                    }
                    if let moved = next.first(where: { $0.id == hitID }), moved.pitch != notes.first(where: { $0.id == hitID })?.pitch {
                        audition(moved.pitch)
                    }
                    clip.notes = next
                case .resize(let origins, let anchor):
                    let delta = Double((drag.location.x - anchor.x) / pixelsPerBeat)
                    var next = notes
                    for index in next.indices {
                        guard let origin = origins[next[index].id] else { continue }
                        let end = snap > 0 ? snapped(origin.end + delta) : origin.end + delta
                        next[index].length = max(snap > 0 ? snap : 0.03, end - origin.start)
                        lastLength = next[index].length
                    }
                    clip.notes = next
                case .band(let anchor, _):
                    rubberBand = CGRect(x: min(anchor.x, drag.location.x), y: min(anchor.y, drag.location.y),
                                        width: abs(drag.location.x - anchor.x), height: abs(drag.location.y - anchor.y))
                case .create(let anchor):
                    if hypot(drag.location.x - anchor.x, drag.location.y - anchor.y) > 5 {
                        gesture = .band(anchor: anchor, additive: flags.contains(.shift))
                    }
                case .velocity(let id):
                    let lane = size.height - velocityHeight
                    let value = Int(((size.height - 4 - drag.location.y) / (velocityHeight - 14) * 127).rounded())
                    _ = lane
                    var next = notes
                    let targets = selection.contains(id) ? selection : [id]
                    for index in next.indices where targets.contains(next[index].id) {
                        next[index].velocity = min(max(value, 1), 127)
                    }
                    clip.notes = next
                case nil: break
                }
            }
            .onEnded { drag in
                defer { gesture = nil; rubberBand = nil; stopAudition() }
                switch gesture {
                case .create(let anchor):
                    // A click on empty grid adds a note there.
                    let startBeat = snappedDown(beat(atX: anchor.x))
                    let p = pitch(atY: anchor.y)
                    guard startBeat >= 0, (0...127).contains(p) else { return }
                    let length = max(snap > 0 ? snap : 0.25, lastLength)
                    let note = LYNote(start: startBeat, length: length, pitch: p, velocity: 100)
                    setNotes(notes + [note])
                    selection = [note.id]
                    audition(p)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { stopAudition() }
                case .band(_, let additive):
                    if let band = rubberBand {
                        let inside = Set(notes.filter { noteRect($0).intersects(band) }.map(\.id))
                        selection = additive ? selection.union(inside) : inside
                    }
                case .move, .resize:
                    setNotes(notes)
                    growClipIfNeeded()
                default: break
                }
                _ = drag
            }
    }

    private func doubleTap(at point: CGPoint, size: CGSize) {
        guard point.y < size.height - velocityHeight, let note = hit(point) else { return }
        setNotes(notes.filter { $0.id != note.id })
        selection.remove(note.id)
    }

    /// Notes past the content's end make the content longer.
    private func growClipIfNeeded() {
        guard let last = notes.map(\.end).max(), last > clip.noteCycleBeats else { return }
        let next = ceil(last / beatsPerBar) * beatsPerBar
        clip.noteLoopBeats = next
        if clip.lengthBeats < next { clip.lengthBeats = next }
    }

    private func quantize() {
        let grid = snap > 0 ? snap : 0.25
        let targets = selection.isEmpty ? Set(notes.map(\.id)) : selection
        setNotes(notes.map { note in
            guard targets.contains(note.id) else { return note }
            var next = note
            next.start = max(0, (note.start / grid).rounded() * grid)
            next.length = max(grid, (note.length / grid).rounded() * grid)
            return next
        })
    }

    private func handleKey(_ key: String, flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case "\u{7F}", "\u{8}":
            guard !selection.isEmpty else { return false }
            setNotes(notes.filter { !selection.contains($0.id) })
            selection = []
            return true
        case "a" where flags.contains(.command):
            selection = Set(notes.map(\.id)); return true
        case "d" where flags.contains(.command):
            let chosen = notes.filter { selection.contains($0.id) }
            guard let first = chosen.map(\.start).min(), let last = chosen.map(\.end).max() else { return false }
            let span = snap > 0 ? ceil((last - first) / snap) * snap : last - first
            let copies = chosen.map { note -> LYNote in var copy = note; copy.id = UUID(); copy.start += span; return copy }
            setNotes(notes + copies)
            selection = Set(copies.map(\.id))
            growClipIfNeeded()
            return true
        case "q" where flags.isDisjoint(with: [.command, .option, .control]):
            quantize(); return true
        case "up", "down":
            guard !selection.isEmpty else { return false }
            let step = (key == "up" ? 1 : -1) * (flags.contains(.shift) ? 12 : 1)
            setNotes(notes.map { note in
                guard selection.contains(note.id) else { return note }
                var next = note
                next.pitch = min(max(note.pitch + step, 0), 127)
                return next
            })
            return true
        case "left", "right":
            guard !selection.isEmpty else { return false }
            let step = (key == "right" ? 1 : -1) * (snap > 0 ? snap : 0.25)
            setNotes(notes.map { note in
                guard selection.contains(note.id) else { return note }
                var next = note
                next.start = max(0, note.start + step)
                return next
            })
            return true
        default:
            return false
        }
    }

    // MARK: Audition

    private func audition(_ pitch: Int) {
        guard (0...127).contains(pitch), auditioning != pitch else { return }
        stopAudition()
        auditioning = pitch
        instrument?.noteOn(UInt8(pitch), velocity: 96, atHostTime: 0, cutoff: 1, resonance: 0)
    }

    private func stopAudition() {
        if let auditioning { instrument?.noteOff(UInt8(auditioning), atHostTime: 0) }
        auditioning = nil
    }
}

/// Mouse-wheel and trackpad scrolling for a canvas; ⌘ turns it into zoom.
struct LYScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                self.onScroll(event.scrollingDeltaX * scale, event.scrollingDeltaY * scale, event.modifierFlags.contains(.command))
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Keys for the piano roll while it is open: delete, arrows, ⌘A, ⌘D, Q.
struct LYPianoRollKeys: NSViewRepresentable {
    var isEnabled: Bool
    let handle: (String, NSEvent.ModifierFlags) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handler = { event in isEnabled ? route(event) : false }
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.handler = { event in isEnabled ? route(event) : false }
    }

    private func route(_ event: NSEvent) -> Bool {
        if event.window?.firstResponder is NSTextView { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 126: return handle("up", flags)
        case 125: return handle("down", flags)
        case 123: return handle("left", flags)
        case 124: return handle("right", flags)
        default: return handle(event.charactersIgnoringModifiers?.lowercased() ?? "", flags)
        }
    }

    final class KeyView: NSView {
        var handler: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                return self.handler(event) ? nil : event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
