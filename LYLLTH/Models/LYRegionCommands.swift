import Foundation

/// Edits for one region on the arrangement, behind the right-click menu.
/// Each works on the session in place and never rewrites a recording.
enum LYRegionCommands {
    struct Location: Equatable {
        var track: Int
        var clip: Int
    }

    static func locate(_ clipID: UUID, in session: LYLLTHSession) -> Location? {
        for track in session.tracks.indices {
            if let clip = session.tracks[track].clips.firstIndex(where: { $0.id == clipID }) { return Location(track: track, clip: clip) }
        }
        return nil
    }

    // MARK: Any region

    /// Splits any region at a song beat. Returns the right-hand piece's id.
    @discardableResult
    static func split(_ clipID: UUID, atBeat beat: Double, in session: inout LYLLTHSession) -> UUID? {
        guard let at = locate(clipID, in: session) else { return nil }
        let clip = session.tracks[at.track].clips[at.clip]
        let pieces: (LYClip, LYClip)?
        switch clip.kind {
        case .audio:
            pieces = LYAudioEventEditor.split(clip, atBeat: beat).map { ($0.left, $0.right) }
        case .notes:
            pieces = splitNotes(clip, atBeat: beat)
        case .pattern, .midi:
            pieces = splitPattern(clip, atBeat: beat)
        }
        guard let (left, right) = pieces else { return nil }
        session.tracks[at.track].clips.replaceSubrange(at.clip...at.clip, with: [left, right])
        return right.id
    }

    /// A copy right after the region. Returns the copy's id.
    @discardableResult
    static func duplicate(_ clipID: UUID, in session: inout LYLLTHSession) -> UUID? {
        guard let at = locate(clipID, in: session) else { return nil }
        let clip = session.tracks[at.track].clips[at.clip]
        var copy: LYClip
        if clip.kind == .audio {
            copy = LYAudioEventEditor.duplicate(clip)
        } else if clip.isSequenced {
            // Another placement of the same pattern, as PLACE AGAIN does.
            copy = clip
            copy.id = UUID()
            copy.patternSourceID = clip.patternSourceID ?? clip.id
            copy.steps = nil
            copy.stepParameters = nil
            copy.isOffTimeline = nil
            copy.startBeat = clip.startBeat + clip.lengthBeats
        } else {
            copy = clip
            copy.id = UUID()
            copy.startBeat = clip.startBeat + clip.lengthBeats
            copy.notes = clip.notes?.map { var note = $0; note.id = UUID(); return note }
        }
        session.tracks[at.track].clips.insert(copy, at: at.clip + 1)
        return copy.id
    }

    /// Takes a region off the arrangement. A pattern that other regions play
    /// stays in the sequencer, off the song, so no steps are lost.
    static func delete(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        let clip = session.tracks[at.track].clips[at.clip]
        if clip.isSequenced && !clip.isPlacement {
            session.tracks[at.track].clips[at.clip].isOffTimeline = true
        } else {
            session.tracks[at.track].clips.remove(at: at.clip)
        }
    }

    static func toggleMute(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].isMuted.toggle()
    }

    static func toggleLock(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].isLocked.toggle()
    }

    static func rename(_ clipID: UUID, to name: String, in session: inout LYLLTHSession) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].name = trimmed.uppercased()
    }

    // MARK: Audio

    static func toggleLoop(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].isLooped.toggle()
    }

    /// Transposes audio by semitones, or note clips by moving their notes.
    static func transpose(_ clipID: UUID, by semitones: Double, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        var clip = session.tracks[at.track].clips[at.clip]
        switch clip.kind {
        case .audio:
            clip.pitchSemitones = min(max(clip.pitchSemitones + semitones, -24), 24)
            clip.normalizeAudioEvent()
        case .notes:
            let step = Int(semitones.rounded())
            clip.notes = clip.notes?.map { var note = $0; note.pitch = min(max(note.pitch + step, 0), 127); return note }
        default:
            return
        }
        session.tracks[at.track].clips[at.clip] = clip
    }

    static func resetPitch(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].pitchSemitones = 0
    }

    static func adjustGain(_ clipID: UUID, by db: Double, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        var clip = session.tracks[at.track].clips[at.clip]
        clip.eventGainDB = min(max(clip.eventGainDB + db, -60), 24)
        session.tracks[at.track].clips[at.clip] = clip
    }

    static func setGain(_ clipID: UUID, to db: Double, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].eventGainDB = min(max(db, -60), 24)
    }

    /// The loudest peak inside the part of the file the event plays, from its
    /// drawn waveform, in dBFS. Nil without a waveform.
    static func peakDB(of clip: LYClip) -> Double? {
        guard let peaks = clip.waveformPeaks, !peaks.isEmpty,
              let fileLength = clip.sourceFileDurationSeconds, fileLength > 0 else { return nil }
        let start = clip.sourceStartSeconds / fileLength
        let length = (clip.sourceDurationSeconds ?? (fileLength - clip.sourceStartSeconds)) / fileLength
        let first = min(max(Int(start * Double(peaks.count)), 0), peaks.count - 1)
        let last = min(max(Int((start + length) * Double(peaks.count)), first + 1), peaks.count)
        let peak = peaks[first..<last].map { abs($0) }.max() ?? 0
        return peak > 0.000_01 ? 20 * log10(Double(peak)) : nil
    }

    /// Sets event gain so the loudest peak lands at −0.3 dBFS.
    static func normalize(_ clipID: UUID, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session),
              let peak = peakDB(of: session.tracks[at.track].clips[at.clip]) else { return }
        setGain(clipID, to: -0.3 - peak, in: &session)
    }

    static func setFades(_ clipID: UUID, inSeconds: Double?, outSeconds: Double?, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        var clip = session.tracks[at.track].clips[at.clip]
        if let inSeconds { clip.fadeInSeconds = inSeconds }
        if let outSeconds { clip.fadeOutSeconds = outSeconds }
        clip.normalizeAudioEvent()
        session.tracks[at.track].clips[at.clip] = clip
    }

    static func setStretch(_ clipID: UUID, to mode: LYAudioStretchMode, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        var clip = session.tracks[at.track].clips[at.clip]
        clip.stretchMode = mode
        clip.normalizeAudioEvent()
        session.tracks[at.track].clips[at.clip] = clip
    }

    // MARK: Notes

    /// Moves every note start to the nearest multiple of `grid` beats.
    /// `strength` 1 snaps fully; 0.5 moves each note halfway.
    static func quantize(_ clipID: UUID, grid: Double, strength: Double = 1, in session: inout LYLLTHSession) {
        guard grid > 0, let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].notes = session.tracks[at.track].clips[at.clip].notes?.map { note in
            var moved = note
            let target = (note.start / grid).rounded() * grid
            moved.start = max(0, note.start + (target - note.start) * strength)
            return moved
        }
    }

    static func scaleVelocity(_ clipID: UUID, by factor: Double, in session: inout LYLLTHSession) {
        guard let at = locate(clipID, in: session) else { return }
        session.tracks[at.track].clips[at.clip].notes = session.tracks[at.track].clips[at.clip].notes?.map { note in
            var changed = note
            changed.velocity = min(max(Int((Double(note.velocity) * factor).rounded()), 1), 127)
            return changed
        }
    }

    // MARK: Patterns

    /// Turns a placement into its own pattern, so it can change without
    /// changing every other place the original plays.
    @discardableResult
    static func makeUnique(_ clipID: UUID, in session: inout LYLLTHSession) -> UUID? {
        guard let at = locate(clipID, in: session) else { return nil }
        let clip = session.tracks[at.track].clips[at.clip]
        guard clip.isPlacement else { return nil }
        let source = session.tracks[at.track].patternContent(of: clip)
        var unique = clip
        unique.patternSourceID = nil
        unique.steps = source.steps
        unique.stepParameters = source.stepParameters
        unique.isOffTimeline = nil
        let count = session.tracks[at.track].patterns.count + 1
        unique.name = (source.name.split(separator: " ").first.map(String.init) ?? "PATTERN") + " " + String(format: "%02d", count)
        session.tracks[at.track].clips[at.clip] = unique
        return unique.id
    }

    // MARK: Pieces

    private static func splitNotes(_ clip: LYClip, atBeat beat: Double) -> (LYClip, LYClip)? {
        let end = clip.startBeat + clip.lengthBeats
        guard beat > clip.startBeat + 0.000_001, beat < end - 0.000_001 else { return nil }
        let cut = beat - clip.startBeat
        var left = clip, right = clip
        left.id = UUID(); right.id = UUID()
        left.lengthBeats = cut
        right.startBeat = beat
        right.lengthBeats = end - beat
        // A looped clip keeps looping from where the cut fell; one that does
        // not loop splits its notes, trimming any that cross the cut.
        if clip.noteLoopBeats != nil && clip.noteCycleBeats < clip.lengthBeats - 0.000_001 {
            right.loopOffsetBeats = clip.loopOffsetBeats + cut
        } else {
            let notes = clip.notes ?? []
            left.notes = notes.filter { $0.start < cut }.map { note in
                var trimmed = note
                trimmed.length = min(note.length, cut - note.start)
                return trimmed
            }
            right.notes = notes.filter { $0.end > cut }.map { note in
                var moved = note
                moved.id = UUID()
                let startInRight = max(note.start - cut, 0)
                moved.length = note.end - cut - startInRight
                moved.start = startInRight
                return moved
            }
            left.noteLoopBeats = left.noteLoopBeats.map { min($0, cut) }
            right.noteLoopBeats = right.noteLoopBeats.map { max($0 - cut, 0.25) }
        }
        return (left, right)
    }

    private static func splitPattern(_ clip: LYClip, atBeat beat: Double) -> (LYClip, LYClip)? {
        let end = clip.startBeat + clip.lengthBeats
        guard beat > clip.startBeat + 0.000_001, beat < end - 0.000_001 else { return nil }
        var left = clip
        left.lengthBeats = beat - clip.startBeat
        // The right piece is another placement of the same pattern, entering
        // it where the cut fell.
        var right = clip
        right.id = UUID()
        right.patternSourceID = clip.patternSourceID ?? clip.id
        right.steps = nil
        right.stepParameters = nil
        right.startBeat = beat
        right.lengthBeats = end - beat
        right.loopOffsetBeats = clip.loopOffsetBeats + (beat - clip.startBeat)
        return (left, right)
    }
}
