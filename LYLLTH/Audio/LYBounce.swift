import AppKit
import Foundation
import NightshapeAudioEngine

/// Exports the song the way DrumKit does, from the same choices:
/// a mixdown (WAV 24-bit, WAV 32-bit float, M4A), STEMS as a ZIP of one WAV
/// per track that plays, and MIDI. Audio is recorded in real time, from the
/// first bar to the end of the last region (or the loop, when one is on),
/// so what is written is exactly what plays: every track, LUNATK, audio
/// events, buses, all FX. A tail after the last bar keeps reverbs and
/// releases.
@MainActor
final class LYBounce: ObservableObject {
    enum Kind: Equatable {
        case mixdown(NightshapeAudioEngine.CaptureFormat)
        case stems

        var title: String {
            switch self {
            case .mixdown(.wav): return "WAV · 24-BIT"
            case .mixdown(.wavFloat): return "WAV · 32-BIT FLOAT"
            case .mixdown(.m4a): return "M4A · AAC"
            case .mixdown: return "AUDIO"
            case .stems: return "STEMS · ZIP"
            }
        }
    }

    /// One stem: what it records and the file name it gets in the ZIP.
    struct Stem {
        var source: NightshapeAudioEngine.StemSource
        var name: String
    }

    enum Phase: Equatable {
        case idle
        case running(elapsed: Double, total: Double, kind: String)
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var timer: Timer?
    private var startedAt = Date()
    private var restore: (() -> Void)?
    private var kind: Kind = .mixdown(.wav)
    private var stemFolder: URL?
    private var stemFiles: [(name: String, url: URL)] = []
    private var readme = ""
    static let tailSeconds = 3.0

    func start(kind: Kind, url: URL, songSeconds: Double, stems: [Stem] = [], readme: String = "",
               audio: AudioEngineController, prepare: () -> Void, restore: @escaping () -> Void) {
        guard case .idle = phase else { return }
        audio.stop()
        prepare()
        self.restore = restore
        self.kind = kind
        self.readme = readme
        do {
            switch kind {
            case .mixdown(let format):
                try audio.engine.beginOutputCapture(to: url, format: format)
            case .stems:
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LYLLTH-Stems-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                stemFolder = folder
                stemFiles = stems.map { ($0.name, folder.appendingPathComponent($0.name + ".wav")) }
                try audio.engine.beginStemCapture(zip(stems, stemFiles).map { ($0.0.source, $0.1.url) }, format: .wav)
            }
        } catch {
            cleanUpStems()
            restore()
            phase = .failed(error.localizedDescription.uppercased())
            return
        }
        audio.togglePlayback()
        startedAt = Date()
        let total = songSeconds + Self.tailSeconds
        phase = .running(elapsed: 0, total: total, kind: kind.title)
        var transportStopped = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self, weak audio] _ in
            MainActor.assumeIsolated {
                guard let self, let audio else { return }
                let elapsed = Date().timeIntervalSince(self.startedAt)
                self.phase = .running(elapsed: min(elapsed, total), total: total, kind: kind.title)
                // Stop the transport at the end of the song so it does not
                // come round again, then keep recording the tail.
                if !transportStopped && elapsed >= songSeconds + 0.05 {
                    transportStopped = true
                    audio.stopTransportKeepingTails()
                }
                if elapsed >= total + 0.05 { self.finish(url: url, audio: audio) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel(audio: AudioEngineController) {
        timer?.invalidate()
        timer = nil
        if kind == .stems { audio.engine.cancelStemCapture() } else { audio.engine.cancelOutputCapture() }
        cleanUpStems()
        audio.stop()
        restore?()
        restore = nil
        phase = .idle
    }

    func dismiss() { phase = .idle }

    /// For exports that are written at once (MIDI, .fkit).
    func report(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): phase = .finished(url)
        case .failure(let error): phase = .failed(error.localizedDescription.uppercased())
        }
    }

    private func finish(url: URL, audio: AudioEngineController) {
        timer?.invalidate()
        timer = nil
        let done: (Result<Void, NightshapeAudioError>) -> Void = { [weak self] result in
            guard let self else { return }
            audio.stop()
            self.restore?()
            self.restore = nil
            switch result {
            case .success:
                if self.kind == .stems {
                    do {
                        try self.zipStems(to: url)
                        self.phase = .finished(url)
                    } catch {
                        self.phase = .failed("COULD NOT WRITE THE ZIP: " + error.localizedDescription.uppercased())
                    }
                    self.cleanUpStems()
                } else {
                    self.phase = .finished(url)
                }
            case .failure(let error):
                self.cleanUpStems()
                self.phase = .failed(error.localizedDescription.uppercased())
            }
        }
        if kind == .stems { audio.engine.endStemCapture(completion: done) } else { audio.engine.endOutputCapture(completion: done) }
    }

    private func zipStems(to url: URL) throws {
        var entries: [ZipArchiveWriter.Entry] = []
        for file in stemFiles where FileManager.default.fileExists(atPath: file.url.path) {
            entries.append(ZipArchiveWriter.Entry(data: try Data(contentsOf: file.url), archiveName: file.name + ".wav"))
        }
        entries.append(ZipArchiveWriter.Entry(data: Data(readme.utf8), archiveName: "README.txt"))
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try ZipArchiveWriter.writeStoredArchive(entries: entries, to: url)
    }

    private func cleanUpStems() {
        if let stemFolder { try? FileManager.default.removeItem(at: stemFolder) }
        stemFolder = nil
        stemFiles = []
    }
}

/// The song's notes as a Standard MIDI File: drums on channel 10 with the
/// General MIDI drum map, each pitched track on its own channel, the same
/// bars an audio export would cover. DrumKit's MIDI export, from LYLLTH's
/// song.
enum LYMIDIExport {
    static func data(session: LYLLTHSession, frames: [SongPatternFrame], window: LYSongWindow? = nil) -> Data {
        let musical = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        let bars = frames.map { frame in
            OfflineRenderBar(tracks: frame.tracks.map { track in
                (0..<track.activeSteps.count).map { i in
                    OfflineRenderStep(
                        isEnabled: track.activeSteps[i],
                        velocity: track.velocities.indices.contains(i) ? track.velocities[i] : 0.82,
                        volume: track.volumes.indices.contains(i) ? track.volumes[i] : 1,
                        cutoff: 1, resonance: 0, fx: 0,
                        isFlam: track.flamSteps.indices.contains(i) && track.flamSteps[i],
                        pitchSemitones: track.pitches.indices.contains(i) ? track.pitches[i] : 0,
                        noteLengthSteps: track.noteLengths.indices.contains(i) ? track.noteLengths[i] : 1
                    )
                }
            }, stepCount: frame.stepCount)
        }
        var usedDrumNotes = Set<Int>()
        var nextChannel = 0
        let tracks: [MIDIExportTrack?] = musical.enumerated().map { index, track in
            let name = String(format: "%02d %@", index + 1, track.name.uppercased())
            if track.kind == .instrument {
                if nextChannel == 9 { nextChannel += 1 }
                let channel = min(nextChannel, 15)
                nextChannel += 1
                return MIDIExportTrack(name: name, note: track.rootNote ?? 48, channel: channel)
            }
            let role = track.name.uppercased() + " " + (LYDrumSounds.preset(for: track)?.category.displayName ?? "")
            let preferred: [Int]
            switch role {
            case let r where r.contains("KICK"): preferred = [36, 35]
            case let r where r.contains("SNARE"): preferred = [38, 40]
            case let r where r.contains("CLAP"): preferred = [39]
            case let r where r.contains("OPEN"): preferred = [46]
            case let r where r.contains("CLOSED") || r.contains("HAT"): preferred = [42, 44]
            case let r where r.contains("TOM"): preferred = [45, 47, 48, 50, 43, 41]
            case let r where r.contains("RIDE"): preferred = [51, 59]
            case let r where r.contains("CRASH") || r.contains("CYMBAL"): preferred = [49, 57, 55, 52]
            case let r where r.contains("RIM"): preferred = [37]
            case let r where r.contains("SHAKER"): preferred = [82, 70]
            default: preferred = [56, 54, 75, 76, 77, 69, 70, 67, 68]
            }
            let note = preferred.first { !usedDrumNotes.contains($0) }
                ?? (60...81).first { !usedDrumNotes.contains($0) } ?? preferred[0]
            usedDrumNotes.insert(note)
            return MIDIExportTrack(name: name, note: note, channel: 9)
        }
        let muted = Set(musical.indices.filter { !LYChannelMap.isAudible(musical[$0], in: session) })
        let meter: TransportMeter.Preset
        switch (session.numerator, session.denominator) {
        case (3, 4): meter = .threeFour
        case (6, 8): meter = .sixEight
        default: meter = .fourFour
        }
        // Piano-roll notes, as played, over the same range as the bars.
        let rangeStart = window?.startBeat ?? 0
        let rangeEnd = window?.endBeat ?? frames.reduce(0) { $0 + Double($1.stepCount) * lyBeatsPerStep }
        var free: [Int: [MIDIExportNote]] = [:]
        for (index, track) in musical.enumerated() where track.kind == .instrument {
            let notes = track.clips.filter { $0.isNoteClip && $0.isInSong && !$0.isMuted }
                .flatMap { $0.songNotes(from: rangeStart, to: rangeEnd) }
                .map { MIDIExportNote(startQuarters: $0.beat - rangeStart, lengthQuarters: min($0.length, rangeEnd - $0.beat),
                                      note: $0.pitch, velocity: $0.velocity) }
            if !notes.isEmpty { free[index] = notes }
        }
        return MIDIFileExporter.data(
            bars: bars, tracks: tracks, muted: muted, freeNotes: free, bpm: session.bpm, meter: meter,
            swing: session.swing ?? 0.5,
            flamIntervalSeconds: TrackChannel.flamGraceSeconds,
            flamGraceVelocityScale: TrackChannel.flamGraceVelocityScale,
            title: session.name.uppercased()
        )
    }
}
