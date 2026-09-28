import SwiftUI
import AppKit

/// DrumKit's song FX lane above the tracks: filter sweeps and FRACTURE
/// moves on a track or MAIN, two rows so moves on different targets can
/// overlap. Double-click empty lane to add a move, double-click a move to
/// remove it. Drag a move to place it, drag either edge to shorten or
/// lengthen it, click it to change it.
struct LYSongFXLane: View {
    @Binding var blocks: [LYSongFXBlock]
    let tracks: [LYTrack]
    let headerWidth: CGFloat
    let beatWidth: CGFloat
    let beats: Int
    let beatsPerBar: Double
    let snap: (Double) -> Double
    let headerOffset: CGFloat
    let openEditor: (UUID) -> Void

    static let rowHeight: CGFloat = 22
    private var height: CGFloat { Self.rowHeight * CGFloat(SongFXBlock.rowCount) + 8 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SONG FX")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.chromeText)
                Text(blocks.isEmpty ? "DOUBLE-CLICK TO ADD A FILTER OR FRACTURE MOVE" : "DOUBLE-CLICK ADDS OR REMOVES · DRAG EDGES TO RESIZE")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .frame(width: headerWidth, height: height, alignment: .leading)
            .background(LYLLTHTheme.deck)
            .lyMenuAnchor("songfx")
            .offset(x: headerOffset)
            .zIndex(10)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(LYLLTHTheme.background)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { tap in add(at: tap.location) })
                ForEach($blocks) { $block in
                    LYSongFXBlockView(
                        block: $block,
                        title: title(for: block),
                        accent: accent(for: block),
                        beatWidth: beatWidth,
                        rowHeight: Self.rowHeight,
                        maximumBeat: Double(beats),
                        snap: snap,
                        open: { openEditor(block.id) },
                        remove: { remove(block.id) }
                    )
                }
            }
            .coordinateSpace(name: LYSongFXBlockView.space)
            .frame(width: CGFloat(beats) * beatWidth, height: height)
            .clipped()
        }
        .overlay(alignment: .bottom) { LYHairline() }
    }

    private func title(for block: LYSongFXBlock) -> String {
        let target = block.trackID.flatMap { id in tracks.first { $0.id == id }?.name } ?? "MAIN"
        return block.move.title + " · " + target
    }

    private func accent(for block: LYSongFXBlock) -> Color {
        block.move.isFracture ? LYLLTHTheme.purple : LYLLTHTheme.indigo
    }

    private func remove(_ id: UUID) {
        blocks.removeAll { $0.id == id }
    }

    private func add(at location: CGPoint) {
        let row = min(max(Int((location.y - 4) / Self.rowHeight), 0), SongFXBlock.rowCount - 1)
        let start = floor(Double(location.x / max(beatWidth, 1)) / beatsPerBar) * beatsPerBar
        guard !blocks.contains(where: { $0.row == row && $0.startBeat < start + beatsPerBar && $0.endBeat > start }) else { return }
        let block = LYSongFXBlock(move: .open, trackID: nil, startBeat: start, lengthBeats: beatsPerBar, row: row)
        blocks.append(block)
        openEditor(block.id)
    }
}

private struct LYSongFXBlockView: View {
    static let space = "LYSongFXLane"

    @Binding var block: LYSongFXBlock
    let title: String
    let accent: Color
    let beatWidth: CGFloat
    let rowHeight: CGFloat
    let maximumBeat: Double
    let snap: (Double) -> Double
    let open: () -> Void
    let remove: () -> Void

    private enum Grab { case body, leading, trailing }

    // One gesture does everything (click, double-click, move, both edges),
    // so no recognizer can starve another.
    @State private var grab: Grab?
    @State private var dragged = false
    /// Where the move sits while it's being dragged. The song is written
    /// once, on release: writing it on every mouse move re-renders the
    /// arrangement under the gesture and loses the drag.
    @State private var preview: (start: Double, length: Double, row: Int)?
    @State private var lastClick = Date.distantPast
    @State private var pendingOpen: DispatchWorkItem?
    @State private var hoverEdge: Grab?

    private var start: Double { preview?.start ?? block.startBeat }
    private var length: Double { preview?.length ?? block.lengthBeats }
    private var row: Int { preview?.row ?? block.row }
    private var width: CGFloat { max(CGFloat(length) * beatWidth - 2, 8) }
    private var edge: CGFloat { min(7, width / 3) }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: 0x0B0C10))
            Rectangle().fill(accent.opacity(grab == nil ? 0.1 : 0.2))
            if block.move.hasLevels {
                Canvas { context, size in
                    var path = Path()
                    let steps = max(Int(size.width / 3), 2)
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let level = block.move.level(at: t, start: block.startLevel, end: block.endLevel)
                        let point = CGPoint(x: CGFloat(t) * size.width, y: 2 + (1 - CGFloat(level)) * (size.height - 4))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(accent.opacity(0.55)), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            Text(title)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LYLLTHTheme.text)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .allowsHitTesting(false)
            // Edge grips: always faintly there so they can be found, bright
            // when hovered or held.
            HStack(spacing: 0) {
                grip(active: hoverEdge == .leading || grab == .leading)
                Spacer(minLength: 0)
                grip(active: hoverEdge == .trailing || grab == .trailing)
            }
            .allowsHitTesting(false)
        }
        .overlay(Rectangle().stroke(accent.opacity(0.85), lineWidth: 1))
        .frame(width: width, height: rowHeight - 3)
        .contentShape(Rectangle())
        .gesture(gesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let next = region(at: point.x)
                hoverEdge = next == .body ? nil : next
                (next == .body ? NSCursor.openHand : NSCursor.resizeLeftRight).set()
            case .ended:
                hoverEdge = nil
                NSCursor.arrow.set()
            }
        }
        .help("Click to change it. Double-click to remove it. Drag to move it; drag either edge to shorten or lengthen it.")
        .offset(x: CGFloat(start) * beatWidth + 1, y: 4 + CGFloat(row) * rowHeight)
    }

    private func grip(active: Bool) -> some View {
        Rectangle()
            .fill(accent.opacity(active ? 0.75 : 0.28))
            .frame(width: 2)
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
    }

    private func region(at x: CGFloat) -> Grab {
        if x <= edge { return .leading }
        if x >= width - edge { return .trailing }
        return .body
    }

    private var gesture: some Gesture {
        // Measured in the lane's space, which doesn't move while the block does.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if grab == nil {
                    grab = region(at: drag.startLocation.x - (CGFloat(block.startBeat) * beatWidth + 1))
                }
                guard let grab else { return }
                if !dragged, hypot(drag.translation.width, drag.translation.height) < 3 { return }
                if !dragged { pendingOpen?.cancel() }
                dragged = true
                let beats = Double(drag.translation.width / max(beatWidth, 1))
                let end = block.startBeat + block.lengthBeats
                switch grab {
                case .body:
                    let start = min(max(0, snap(block.startBeat + beats)), max(0, maximumBeat - block.lengthBeats))
                    let row = min(max(block.row + Int((drag.translation.height / rowHeight).rounded()), 0), SongFXBlock.rowCount - 1)
                    preview = (start, block.lengthBeats, row)
                case .leading:
                    let start = min(max(0, snap(block.startBeat + beats)), end - lyBeatsPerStep)
                    preview = (start, end - start, block.row)
                case .trailing:
                    let newEnd = min(snap(end + beats), maximumBeat)
                    preview = (block.startBeat, max(lyBeatsPerStep, newEnd - block.startBeat), block.row)
                }
            }
            .onEnded { _ in
                if let preview {
                    block.startBeat = preview.start
                    block.lengthBeats = preview.length
                    block.row = preview.row
                } else if !dragged {
                    click()
                }
                preview = nil
                grab = nil
                dragged = false
            }
    }

    /// A single click opens the editor once the double-click window has
    /// passed; a second click inside it removes the move instead.
    private func click() {
        let now = Date()
        if now.timeIntervalSince(lastClick) <= NSEvent.doubleClickInterval {
            pendingOpen?.cancel()
            pendingOpen = nil
            lastClick = .distantPast
            remove()
            return
        }
        lastClick = now
        let work = DispatchWorkItem { open() }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }
}

/// What a song FX move is and what it moves, NIGHTSHAPE dropdown style.
struct LYSongFXPanel: View {
    @Binding var block: LYSongFXBlock
    let targets: [LYTrack]
    let remove: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(eyebrow: "SONG FX", title: block.move.title, accent: accent, close: close)
            LYNightshapeMenuDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    removeButton
                    moveSection("FILTER", SongFXMove.filterMoves)
                    moveSection("FRACTURE", SongFXMove.fractureMoves)
                    VStack(alignment: .leading, spacing: 4) {
                        heading("APPLIES TO")
                        targetRow(nil, "MAIN")
                        ForEach(targets) { track in targetRow(track.id, track.name) }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 320)
        .lyNightshapeMenuChrome(accent: accent)
    }

    private var removeButton: some View {
        Button(action: remove) {
            Text("REMOVE MOVE")
                .font(LYLLTHTheme.label(8.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(LYLLTHTheme.record)
                .frame(maxWidth: .infinity, minHeight: 28)
                .overlay(Rectangle().stroke(LYLLTHTheme.record.opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Or double-click the move in the lane")
    }

    private var accent: Color { block.move.isFracture ? LYLLTHTheme.purple : LYLLTHTheme.indigo }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(LYLLTHTheme.label(7.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(accent)
            .padding(.bottom, 2)
    }

    private func moveSection(_ title: String, _ moves: [SongFXMove]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            heading(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(moves) { move in
                    Button {
                        guard move != block.move else { return }
                        block.move = move
                        block.startLevel = move.defaultStartLevel
                        block.endLevel = move.defaultEndLevel
                    } label: {
                        Text(move.title)
                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                            .tracking(0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(move == block.move ? LYLLTHTheme.text : LYLLTHTheme.chromeText)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(move == block.move ? accent.opacity(0.12) : LYLLTHTheme.panelRaised)
                            .overlay(Rectangle().stroke(move == block.move ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func targetRow(_ id: UUID?, _ name: String) -> some View {
        Button { block.trackID = id } label: {
            HStack {
                Text(name)
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(LYLLTHTheme.text)
                Spacer()
                if block.trackID == id { LYLED(color: accent, size: 5) }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(block.trackID == id ? accent.opacity(0.08) : LYLLTHTheme.panelRaised)
            .overlay(alignment: .leading) { Rectangle().fill(accent.opacity(block.trackID == id ? 0.9 : 0.4)).frame(width: 2) }
            .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong.opacity(0.9), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
