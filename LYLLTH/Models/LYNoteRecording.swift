import Foundation

/// Where recorded MIDI lands on a LUNATK track in the song: free-timed notes
/// in note clips, never rounded to steps.
enum LYNoteRecording {
    typealias Played = (beat: Double, length: Double, pitch: Int, velocity: Int)

    /// A note played over a note clip goes into that clip, at its place in
    /// the clip's repeating content. Anywhere else, the take gets a new clip
    /// on the bar, and a take that runs on grows that clip bar by bar.
    static func write(_ played: [Played], into clips: [LYClip], beatsPerBar: Double) -> [LYClip] {
        var clips = clips
        var made: Set<UUID> = []
        for note in played.sorted(by: { $0.beat < $1.beat }) {
            let beat = max(0, note.beat)
            var index = clips.firstIndex { $0.isNoteClip && $0.isInSong && beat >= $0.startBeat - 0.000_1 && beat < $0.startBeat + $0.lengthBeats - 0.000_1 }
            let barStart = floor(beat / beatsPerBar + 0.000_1) * beatsPerBar
            if index == nil, let growing = clips.firstIndex(where: { made.contains($0.id) && abs($0.startBeat + $0.lengthBeats - barStart) < 0.000_1 }) {
                let bars = barStart + beatsPerBar - clips[growing].startBeat
                clips[growing].lengthBeats = bars
                clips[growing].noteLoopBeats = bars
                index = growing
            }
            if index == nil {
                // Stop short of the next clip on the lane.
                let next = clips.filter { $0.isInSong && $0.startBeat > barStart }.map(\.startBeat).min() ?? .infinity
                let length = min(beatsPerBar, next - barStart)
                guard length > 0.24 else { continue }
                let clip = LYClip(name: "REC " + String(format: "%02d", Int(barStart / beatsPerBar) + 1), kind: .notes,
                                  startBeat: barStart, lengthBeats: length, notes: [], noteLoopBeats: length)
                clips.append(clip)
                made.insert(clip.id)
                index = clips.count - 1
            }
            guard let index else { continue }
            let clip = clips[index]
            let cycle = clip.noteCycleBeats
            var local = (beat - clip.startBeat + clip.loopOffsetBeats).truncatingRemainder(dividingBy: cycle)
            if local < 0 { local += cycle }
            clips[index].notes = ((clip.notes ?? []) + [LYNote(start: local, length: note.length,
                                                              pitch: min(max(note.pitch, 0), 127),
                                                              velocity: min(max(note.velocity, 1), 127))])
                .sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        }
        return clips
    }
}

/// A note as the song plays it: the clip's content placed and repeated.
struct LYSongNote: Equatable {
    var beat: Double
    var length: Double
    var pitch: Int
    var velocity: Int
}

extension LYClip {
    /// The notes this clip sounds that start in `from..<to` (song beats).
    /// Each repeat of the content is cut where the repeat ends, and every
    /// note is cut at the clip's end, as the piano roll draws them.
    func songNotes(from: Double, to: Double) -> [LYSongNote] {
        guard isNoteClip, let notes, !notes.isEmpty, to > from else { return [] }
        let cycle = noteCycleBeats
        let clipEnd = startBeat + lengthBeats
        let lower = max(from, startBeat), upper = min(to, clipEnd)
        guard upper > lower else { return [] }
        let firstRepeat = max(0, Int(floor((lower - startBeat + loopOffsetBeats) / cycle)) - 1)
        let lastRepeat = max(0, Int(floor((upper - startBeat + loopOffsetBeats) / cycle)) + 1)
        var out: [LYSongNote] = []
        for k in firstRepeat...lastRepeat {
            let repeatStart = startBeat + Double(k) * cycle - loopOffsetBeats
            for note in notes where note.start < cycle {
                let beat = repeatStart + note.start
                guard beat >= startBeat - 0.000_1, beat >= lower, beat < upper else { continue }
                let end = min(beat + note.length, repeatStart + cycle, clipEnd)
                guard end > beat else { continue }
                out.append(LYSongNote(beat: beat, length: end - beat, pitch: note.pitch, velocity: note.velocity))
            }
        }
        return out.sorted { ($0.beat, $0.pitch) < ($1.beat, $1.pitch) }
    }
}
