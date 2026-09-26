import Foundation
import NightshapeAudioEngine

/// One move on the song FX lane, DrumKit's SongFXBlock placed in beats and
/// pinned to a track by id (tracks move in LYLLTH; DrumKit's slots do not).
struct LYSongFXBlock: Codable, Equatable, Identifiable {
    var id = UUID()
    var move: SongFXMove
    /// The track it moves, or nil for MAIN.
    var trackID: UUID?
    var startBeat: Double
    var lengthBeats: Double
    /// Lane row, 0 or 1, so moves on different targets can overlap.
    var row: Int = 0
    var startLevel: Float
    var endLevel: Float
    var resonance: Float = SongFXBlock.defaultResonance

    init(move: SongFXMove, trackID: UUID?, startBeat: Double, lengthBeats: Double, row: Int = 0) {
        self.move = move
        self.trackID = trackID
        self.startBeat = max(0, startBeat)
        self.lengthBeats = max(lyBeatsPerStep, lengthBeats)
        self.row = min(max(row, 0), SongFXBlock.rowCount - 1)
        startLevel = move.defaultStartLevel
        endLevel = move.defaultEndLevel
    }

    var endBeat: Double { startBeat + lengthBeats }

    /// Level at a song beat inside the block (the block's end included).
    func level(atBeat beat: Double) -> Float {
        move.level(at: (beat - startBeat) / max(lengthBeats, 1e-9), start: startLevel, end: endLevel)
    }

    /// A stable 64-bit identity for the engine, from the UUID.
    var engineID: UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.load(as: UInt64.self) }
    }
}

enum LYSongFXCompiler {
    /// Filter and FRACTURE lanes for one bar, targets as engine channels.
    static func lanes(
        _ blocks: [LYSongFXBlock],
        barStartBeat: Double,
        stepsPerBar: Int,
        channels: [UUID: Int]
    ) -> (filter: [SongFilterLane], fracture: [SongFractureLane]) {
        guard !blocks.isEmpty else { return ([], []) }
        let barEnd = barStartBeat + Double(stepsPerBar) * lyBeatsPerStep
        var filter: [Int: [FilterSegment?]] = [:]
        var fracture: [Int: [SongFractureCell?]] = [:]
        for block in blocks where block.startBeat < barEnd - 1e-6 && block.endBeat > barStartBeat + 1e-6 {
            let target: Int
            if let id = block.trackID {
                guard let channel = channels[id] else { continue }
                target = channel
            } else {
                target = SongFilterLane.mainTarget
            }
            let blockSteps = max(1, Int((block.lengthBeats / lyBeatsPerStep).rounded()))
            for step in 0..<stepsPerBar {
                let beat = barStartBeat + Double(step) * lyBeatsPerStep
                guard beat >= block.startBeat - 1e-6, beat < block.endBeat - 1e-6 else { continue }
                if let kind = block.move.fractureKind {
                    var cells = fracture[target] ?? Array(repeating: nil, count: stepsPerBar)
                    cells[step] = SongFractureCell(
                        kind: kind,
                        blockID: block.engineID,
                        stepsIntoBlock: Int(((beat - block.startBeat) / lyBeatsPerStep).rounded()),
                        blockLengthSteps: blockSteps,
                        startLevel: block.startLevel,
                        endLevel: block.endLevel
                    )
                    fracture[target] = cells
                } else {
                    var segments = filter[target] ?? Array(repeating: nil, count: stepsPerBar)
                    segments[step] = FilterSegment(
                        from: block.level(atBeat: beat),
                        to: block.level(atBeat: min(beat + lyBeatsPerStep, block.endBeat)),
                        mode: block.move.mode,
                        resonance: block.resonance
                    )
                    filter[target] = segments
                }
            }
        }
        return (
            filter.keys.sorted().map { SongFilterLane(target: $0, segments: filter[$0]!) },
            fracture.keys.sorted().map { SongFractureLane(target: $0, cells: fracture[$0]!) }
        )
    }
}
