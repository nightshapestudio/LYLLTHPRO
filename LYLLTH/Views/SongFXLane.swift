import SwiftUI
import AppKit

/// DrumKit's song FX lane above the tracks: filter sweeps and FRACTURE
/// moves on a track or MAIN, two rows so moves on different targets can
/// overlap. Double-click to add a move, drag to move it, drag its right edge
/// to resize, click to change it.
struct LYSongFXLane: View {
    @Binding var blocks: [LYSongFXBlock]
    let tracks: [LYTrack]
    let headerWidth: CGFloat
    let beatWidth: CGFloat
    let beats: Int
    let beatsPerBar: Double
    let snap: (Double) -> Double
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
                Text(blocks.isEmpty ? "DOUBLE-CLICK TO ADD A FILTER OR FRACTURE MOVE" : "FILTER + FRACTURE MOVES")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .frame(width: headerWidth, height: height, alignment: .leading)
            .background(LYLLTHTheme.deck)
            .lyMenuAnchor("songfx")

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
                        open: { openEditor(block.id) }
                    )
                    .frame(width: max(CGFloat(block.lengthBeats) * beatWidth - 2, 8), height: Self.rowHeight - 3)
                    .offset(x: CGFloat(block.startBeat) * beatWidth + 1, y: 4 + CGFloat(block.row) * Self.rowHeight)
                }
            }
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
    @Binding var block: LYSongFXBlock
    let title: String
    let accent: Color
    let beatWidth: CGFloat
    let rowHeight: CGFloat
    let maximumBeat: Double
    let snap: (Double) -> Double
    let open: () -> Void

    @State private var moveOrigin: (beat: Double, row: Int)?
    @State private var resizeOrigin: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: 0x0B0C10))
            Rectangle().fill(accent.opacity(0.1))
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
                .padding(.horizontal, 5)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                Rectangle().fill(Color.clear).contentShape(Rectangle()).gesture(moveGesture)
                Rectangle()
                    .fill(accent.opacity(resizeOrigin == nil ? 0.001 : 0.5))
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(resizeGesture)
            }
        }
        .overlay(Rectangle().stroke(accent.opacity(0.85), lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { open() })
        .help("Click to change the move or what it moves. Drag to move it, drag the right edge to resize.")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { drag in
                let origin = moveOrigin ?? (block.startBeat, block.row)
                moveOrigin = origin
                let beat = snap(origin.beat + Double(drag.translation.width / max(beatWidth, 1)))
                block.startBeat = min(max(0, beat), max(0, maximumBeat - block.lengthBeats))
                block.row = min(max(origin.row + Int((drag.translation.height / rowHeight).rounded()), 0), SongFXBlock.rowCount - 1)
            }
            .onEnded { _ in moveOrigin = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                let origin = resizeOrigin ?? block.lengthBeats
                resizeOrigin = origin
                let end = snap(block.startBeat + origin + Double(drag.translation.width / max(beatWidth, 1)))
                block.lengthBeats = max(lyBeatsPerStep, min(end, maximumBeat) - block.startBeat)
            }
            .onEnded { _ in resizeOrigin = nil }
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
                    moveSection("FILTER", SongFXMove.filterMoves)
                    moveSection("FRACTURE", SongFXMove.fractureMoves)
                    VStack(alignment: .leading, spacing: 4) {
                        heading("APPLIES TO")
                        targetRow(nil, "MAIN")
                        ForEach(targets) { track in targetRow(track.id, track.name) }
                    }
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
                }
                .padding(14)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 320)
        .lyNightshapeMenuChrome(accent: accent)
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
