import Foundation

// SIREN: note-level vocal tuning and timing, plus alignment to a guide.
// Everything here is non-destructive. The region keeps pointing at its
// original recording; the edit is a list of notes with offsets, and the
// sound is rebuilt from the original every time the edit changes.

/// One sung note SIREN found in a recording. Times are seconds in the
/// source file; pitches are MIDI note numbers with cents as the fraction.
struct LYVocalNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    /// The note's center as sung.
    var detectedPitch: Double
    /// Semitones added to the note. 0.5 is fifty cents.
    var pitchOffset: Double = 0
    /// How much of the singer's own pitch movement is kept: 1 is all of it,
    /// 0 holds the note dead flat on its center.
    var drift: Double = 1
    var gainDB: Double = 0
    /// Moves the note later (positive) or earlier, in seconds. Its
    /// neighbors stretch or squeeze to make room.
    var timeOffset: Double = 0

    var duration: Double { end - start }
    /// Where the note's center lands after editing.
    var pitch: Double { detectedPitch + pitchOffset }
    var isEdited: Bool {
        abs(pitchOffset) > 0.000_5 || abs(drift - 1) > 0.000_5 || abs(gainDB) > 0.01 || abs(timeOffset) > 0.000_5
    }
}

/// One point on a time map: sound from `source` in the original file plays
/// at `output`, both in source-file seconds.
struct LYWarpPoint: Codable, Equatable {
    var output: Double
    var source: Double
}

/// A region lined up against a guide region.
struct LYVocalAlignment: Codable, Equatable {
    var guideClipID: UUID
    /// 0 leaves the timing alone, 1 follows the guide as closely as it can.
    var tightness: Double
    var alignsPitch: Bool
    /// Output-to-source map, sorted and rising.
    var points: [LYWarpPoint]
}

/// A region's SIREN edit.
struct LYVocalEdit: Codable, Equatable {
    var version = 1
    /// The recording the notes were found in. A different take or a relinked
    /// file means the notes describe other audio, so they are found again.
    var sourceRelativePath: String
    var notes: [LYVocalNote]
    var alignment: LYVocalAlignment? = nil
    /// A/B: plays the original while the edit is kept.
    var isBypassed = false

    var isActive: Bool {
        !isBypassed && (notes.contains(where: \.isEdited) || alignment != nil)
    }

    /// A short, stable fingerprint for render caches.
    var renderKey: String {
        guard isActive else { return "" }
        var hasher = LYStableHasher()
        for note in notes where note.isEdited {
            hasher.add(note.start); hasher.add(note.end); hasher.add(note.pitchOffset)
            hasher.add(note.drift); hasher.add(note.gainDB); hasher.add(note.timeOffset)
        }
        for point in alignment?.points ?? [] { hasher.add(point.output); hasher.add(point.source) }
        return hasher.hex
    }
}

/// FNV-1a over doubles rounded to microseconds, so the key survives
/// relaunches (Swift's own hashing is seeded per launch).
struct LYStableHasher {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325
    mutating func add(_ number: Double) {
        var bits = Int64((number * 1_000_000).rounded()).littleEndian
        withUnsafeBytes(of: &bits) { bytes in
            for byte in bytes {
                value ^= UInt64(byte)
                value = value &* 0x0000_0100_0000_01b3
            }
        }
    }
    var hex: String { String(value, radix: 16) }
}

extension LYClip {
    /// The SIREN edit, if it still describes this region's audio.
    var activeVocalEdit: LYVocalEdit? {
        guard kind == .audio, let vocal, vocal.isActive, vocal.sourceRelativePath == sourceRelativePath else { return nil }
        return vocal
    }
}

/// Monotone piecewise-linear time maps.
enum LYWarp {
    static func source(atOutput time: Double, _ points: [LYWarpPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return time }
        if time <= first.output { return first.source + (time - first.output) }
        if time >= last.output { return last.source + (time - last.output) }
        var low = 0, high = points.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].output <= time { low = mid } else { high = mid }
        }
        let a = points[low], b = points[high]
        let span = b.output - a.output
        guard span > 1e-9 else { return a.source }
        return a.source + (b.source - a.source) * (time - a.output) / span
    }

    static func output(atSource time: Double, _ points: [LYWarpPoint]) -> Double {
        source(atOutput: time, points.map { LYWarpPoint(output: $0.source, source: $0.output) })
    }

    /// Chains two maps: `outer` first (output to intermediate), then `inner`.
    static func compose(outer: [LYWarpPoint], inner: [LYWarpPoint]) -> [LYWarpPoint] {
        if outer.isEmpty { return inner }
        if inner.isEmpty { return outer }
        // Breakpoints of both maps, expressed as outputs of the chain.
        var outputs = Set(outer.map(\.output))
        for point in inner { outputs.insert(output(atSource: point.output, outer)) }
        return outputs.sorted().map { LYWarpPoint(output: $0, source: source(atOutput: source(atOutput: $0, outer), inner)) }
    }

    /// Drops points a straight line through their neighbors already covers
    /// to within `tolerance` seconds.
    static func simplify(_ points: [LYWarpPoint], tolerance: Double = 0.001) -> [LYWarpPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            let a = points[first], b = points[last]
            var worst = 0.0, worstIndex = -1
            for index in (first + 1)..<last {
                let p = points[index]
                let t = b.output - a.output > 1e-12 ? (p.output - a.output) / (b.output - a.output) : 0
                let error = abs(p.source - (a.source + (b.source - a.source) * t))
                if error > worst { worst = error; worstIndex = index }
            }
            if worst > tolerance, worstIndex > 0 {
                keep[worstIndex] = true
                stack.append((first, worstIndex))
                stack.append((worstIndex, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
