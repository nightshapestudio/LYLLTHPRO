import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CryptoKit

extension UTType {
    static let lyllthSession = UTType(exportedAs: "net.nightshape.lyllth.session", conformingTo: .package)
}

private struct LYLLTHManifest: Codable {
    var format = "lyllth"
    var schemaVersion: Int
    var generatedBy = "LYLLTH macOS"
    var projectFileName = "project.json"
    var projectID: UUID
    var projectName: String
    var modifiedAt: Date
    var projectSHA256: String?
    var audioFiles: [String]?
    var audioSHA256: [String: String]?
}

/// File-backed working storage for immutable project media. The document only
/// keeps names and URLs in memory; audio bytes are mapped on demand for
/// playback/export and package saves stream from these files.
final class LYProjectMediaStore: @unchecked Sendable {
    private let lock = NSLock()
    let rootURL: URL
    private var files = Set<String>()
    private(set) var previousProjectData: Data?

    init(projectID: UUID, assets: [String: Data] = [:], previousProjectData: Data? = nil) {
        let manager = FileManager.default
        let applicationSupport = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.temporaryDirectory
        rootURL = applicationSupport
            .appendingPathComponent("LYLLTH/Working Media", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try? manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.previousProjectData = previousProjectData
        replace(with: assets)
    }

    convenience init(projectID: UUID, wrappers: [String: FileWrapper], previousProjectData: Data?) {
        self.init(projectID: projectID, previousProjectData: previousProjectData)
        for (name, wrapper) in wrappers {
            guard Self.isValidAssetName(name), let data = wrapper.regularFileContents else { continue }
            try? put(data, named: name)
        }
    }

    private static func isValidAssetName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." &&
            (name as NSString).lastPathComponent == name
    }

    var names: [String] {
        lock.lock(); defer { lock.unlock() }
        return files.sorted()
    }

    func contains(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files.contains(name)
    }

    func url(for name: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard files.contains(name) else { return nil }
        return rootURL.appendingPathComponent(name, isDirectory: false)
    }

    func data(for name: String) -> Data? {
        guard let url = url(for: name) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    func put(_ data: Data, named name: String) throws {
        guard Self.isValidAssetName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = rootURL.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url, options: .atomic)
        lock.lock(); files.insert(name); lock.unlock()
    }

    func replace(with assets: [String: Data]) {
        for (name, data) in assets { try? put(data, named: name) }
    }

    /// Compatibility boundary for formats that intentionally need a complete
    /// in-memory bundle (currently .fkit). Normal playback never calls this.
    func snapshot() -> [String: Data] {
        Dictionary(uniqueKeysWithValues: names.compactMap { name in data(for: name).map { (name, $0) } })
    }

    func fileWrappers() throws -> [String: FileWrapper] {
        try Dictionary(uniqueKeysWithValues: names.compactMap { name in
            guard let url = url(for: name) else { return nil }
            let wrapper = try FileWrapper(url: url, options: .immediate)
            wrapper.preferredFilename = name
            return (name, wrapper)
        })
    }

    func rememberProjectSnapshot(_ data: Data) { previousProjectData = data }

    func sha256(for name: String) -> String? {
        guard let data = data(for: name) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A small, atomic edit journal outside the package. It is intentionally
/// project JSON only: immutable media is already safe in the working-media
/// store, and recording has its own journal until a take is committed.
enum LYRecoveryJournal {
    private struct Entry: Codable {
        var capturedAt: Date
        var session: LYLLTHSession
    }

    private static func url(for projectID: UUID) -> URL {
        let manager = FileManager.default
        let base = (try? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? manager.temporaryDirectory
        return base.appendingPathComponent("LYLLTH/Recovery", isDirectory: true)
            .appendingPathComponent(projectID.uuidString + ".json")
    }

    static func write(_ session: LYLLTHSession, capturedAt: Date = Date()) {
        let target = url(for: session.id)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(Entry(capturedAt: capturedAt, session: session)).write(to: target, options: .atomic)
        } catch {
            #if DEBUG
            NSLog("[RECOVERY] Could not journal project: %@", error.localizedDescription)
            #endif
        }
    }

    static func recoverable(projectID: UUID, newerThan savedAt: Date) -> LYLLTHSession? {
        guard let data = try? Data(contentsOf: url(for: projectID)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.capturedAt > savedAt else { return nil }
        return entry.session.migratedToCurrentSchema()
    }

    static func discard(projectID: UUID) {
        try? FileManager.default.removeItem(at: url(for: projectID))
    }
}

struct LYLLTHSessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lyllthSession] }
    static var writableContentTypes: [UTType] { [.lyllthSession] }

    var session: LYLLTHSession
    /// Project-owned originals keyed by their path below `Audio/`.
    /// Edits remain references into these immutable bytes.
    private var mediaStore: LYProjectMediaStore
    var audioAssets: [String: Data] {
        get { mediaStore.snapshot() }
        set { mediaStore.replace(with: newValue) }
    }
    var audioAssetNames: [String] { mediaStore.names }
    var audioMediaStore: LYProjectMediaStore { mediaStore }
    func audioData(for name: String) -> Data? { mediaStore.data(for: name) }
    func audioURL(for name: String) -> URL? { mediaStore.url(for: name) }
    /// Custom LUNATK wavetables the song uses, raw Float32 frames by
    /// name, so a song opens with its sounds on any Mac.
    var wavetables: [String: Data] = [:]

    init(session: LYLLTHSession = .starter()) {
        self.session = session.migratedToCurrentSchema()
        mediaStore = LYProjectMediaStore(projectID: self.session.id)
    }

    /// Set on a song just made from a .fkit, with what could not come across.
    /// Neither is saved.
    var isFromDrumKit = false
    var importNotes: [String] = []

    /// A DrumKit project as a new, untitled song. It is never saved back
    /// over the .fkit; SAVE AS DRUMKIT PROJECT writes one on purpose.
    init(imported: LYFKit.Imported) {
        self.init(session: imported.session)
        mediaStore.replace(with: imported.assets)
        isFromDrumKit = true
        importNotes = imported.notes
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isDirectory,
              let children = fileWrapper.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        let primaryData = children["project.json"]?.regularFileContents
        let recoveryData = children["Recovery"]?.fileWrappers?["project.json"]?.regularFileContents
        let manifest = children["manifest.json"]?.regularFileContents.flatMap {
            try? decoder.decode(LYLLTHManifest.self, from: $0)
        }
        let primaryMatchesManifest = primaryData.map { data in
            guard let expected = manifest?.projectSHA256 else { return true }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
        } ?? false
        let decoded: LYLLTHSession
        let decodedData: Data
        if primaryMatchesManifest, let primaryData, let primary = try? decoder.decode(LYLLTHSession.self, from: primaryData) {
            decoded = primary
            decodedData = primaryData
        } else if let recoveryData, let recovery = try? decoder.decode(LYLLTHSession.self, from: recoveryData) {
            decoded = recovery
            decodedData = recoveryData
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard decoded.schemaVersion <= LYLLTHSession.currentSchemaVersion else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        session = decoded.migratedToCurrentSchema()
        mediaStore = LYProjectMediaStore(
            projectID: session.id,
            wrappers: children["Audio"]?.fileWrappers ?? [:],
            previousProjectData: decodedData
        )
        if let listed = manifest?.audioFiles, Set(listed) != Set(mediaStore.names) {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let expected = manifest?.audioSHA256 {
            let corrupt = expected.contains { name, digest in mediaStore.sha256(for: name) != digest }
            if corrupt { throw CocoaError(.fileReadCorruptFile) }
        }
        wavetables = children["Wavetables"]?.fileWrappers?.reduce(into: [:]) { result, entry in
            guard let data = entry.value.regularFileContents else { return }
            result[(entry.key as NSString).deletingPathExtension] = data
        } ?? [:]
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try packageFileWrapper()
    }

    func packageFileWrapper(modifiedAt: Date = Date()) throws -> FileWrapper {
        var snapshot = session
        snapshot.modifiedAt = modifiedAt

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let projectData = try encoder.encode(snapshot)
        let audioDigests = Dictionary(uniqueKeysWithValues: mediaStore.names.compactMap { name in
            mediaStore.sha256(for: name).map { (name, $0) }
        })
        let manifest = LYLLTHManifest(
            schemaVersion: LYLLTHSession.currentSchemaVersion,
            projectID: snapshot.id,
            projectName: snapshot.name,
            modifiedAt: snapshot.modifiedAt,
            projectSHA256: SHA256.hash(data: projectData).map { String(format: "%02x", $0) }.joined(),
            audioFiles: mediaStore.names,
            audioSHA256: audioDigests
        )

        let audioWrappers = try mediaStore.fileWrappers()
        let previous = mediaStore.previousProjectData ?? projectData
        mediaStore.rememberProjectSnapshot(projectData)

        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: try encoder.encode(manifest)),
            "project.json": FileWrapper(regularFileWithContents: projectData),
            "Audio": FileWrapper(directoryWithFileWrappers: audioWrappers),
            "Wavetables": FileWrapper(directoryWithFileWrappers: wavetables.reduce(into: [String: FileWrapper]()) { result, entry in
                result[entry.key + ".f32"] = FileWrapper(regularFileWithContents: entry.value)
            }),
            "Presets": FileWrapper(directoryWithFileWrappers: [:]),
            "PluginStates": FileWrapper(directoryWithFileWrappers: [:]),
            "Recovery": FileWrapper(directoryWithFileWrappers: [
                "project.json": FileWrapper(regularFileWithContents: projectData)
            ]),
            "Backups": FileWrapper(directoryWithFileWrappers: [
                "project-previous.json": FileWrapper(regularFileWithContents: previous)
            ])
        ])
    }

    mutating func addImportedAudio(
        _ imported: LYImportedAudio,
        toTrackID requestedTrackID: UUID?,
        atBeat: Double
    ) -> UUID {
        let trackIndex: Int
        if let requestedTrackID,
           let existing = session.tracks.firstIndex(where: { $0.id == requestedTrackID && $0.kind == .audio }) {
            trackIndex = existing
        } else if let existing = session.tracks.firstIndex(where: { $0.kind == .audio }) {
            trackIndex = existing
        } else {
            session.tracks.append(
                LYTrack(name: "AUDIO 01", kind: .audio, accent: .purple, volumeDB: -6)
            )
            trackIndex = session.tracks.count - 1
            session.assignEngineChannel(toTrackAt: trackIndex)
        }

        let storedName = uniqueAudioName(imported.fileName)
        try? mediaStore.put(imported.data, named: storedName)
        var clip = LYClip(
            name: imported.displayName,
            kind: .audio,
            startBeat: max(0, atBeat),
            lengthBeats: max(0.001, imported.duration * max(session.bpm, 1) / 60),
            sourceRelativePath: storedName,
            sourceStartSeconds: 0,
            sourceDurationSeconds: imported.duration,
            waveformPeaks: imported.waveformPeaks,
            sourceSampleRate: imported.sampleRate,
            sourceChannelCount: imported.channelCount,
            stretchMode: imported.beatMap == nil ? .off : .beatMapped,
            sourceBPM: imported.sourceBPM,
            preservePitch: true,
            beatMap: imported.beatMap
        )
        // Lay the event down at the length it actually plays for, so a
        // beat-mapped loop fills whole beats on the grid.
        clip.sourceFileDurationSeconds = imported.duration
        if let cycle = LYAudioEventTiming.cycleBeats(for: clip, projectBPM: session.bpm) {
            clip.lengthBeats = cycle
        }
        session.tracks[trackIndex].clips.append(clip)
        return clip.id
    }

    private func uniqueAudioName(_ proposed: String) -> String {
        let source = URL(fileURLWithPath: proposed)
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        var candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
        var suffix = 2
        while mediaStore.contains(candidate) {
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }
}

struct LYImportedAudio: Sendable {
    var fileName: String
    var displayName: String
    var data: Data
    var duration: Double
    var sampleRate: Double
    var channelCount: Int
    var waveformPeaks: [Float]
    var sourceBPM: Double?
    var beatMap: LYBeatMap?
}

enum LYAudioImportError: LocalizedError {
    case unsupportedFileType
    case unreadableAudio
    case unsupportedPCM

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType: return "Choose a WAV, AIFF, MP3, M4A, CAF, or FLAC audio file."
        case .unreadableAudio: return "LYLLTH could not read that audio file."
        case .unsupportedPCM: return "LYLLTH could not decode that file to PCM audio."
        }
    }
}

enum LYAudioImporter {
    static func importFile(at url: URL) async throws -> LYImportedAudio {
        try await Task.detached(priority: .userInitiated) {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }

            let supportedExtensions: Set<String> = [
                "wav", "wave", "aif", "aiff", "mp3", "m4a", "mp4", "caf", "flac"
            ]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                throw LYAudioImportError.unsupportedFileType
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else {
                throw LYAudioImportError.unreadableAudio
            }

            let totalFrames = Int(file.length)
            let analysisLimit = min(totalFrames, Int(format.sampleRate * 180))
            let waveformPointCount = 512
            var waveform = [Float](repeating: 0, count: waveformPointCount)
            var mono: [Float] = []
            mono.reserveCapacity(analysisLimit)
            let chunkFrames: AVAudioFrameCount = 16_384
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                throw LYAudioImportError.unsupportedPCM
            }

            file.framePosition = 0
            var absoluteFrame = 0
            while absoluteFrame < totalFrames {
                buffer.frameLength = 0
                try file.read(into: buffer, frameCount: min(chunkFrames, AVAudioFrameCount(totalFrames - absoluteFrame)))
                let count = Int(buffer.frameLength)
                guard count > 0, let channels = buffer.floatChannelData else { break }
                for frame in 0..<count {
                    var sample: Float = 0
                    for channel in 0..<Int(format.channelCount) {
                        sample += channels[channel][frame]
                    }
                    sample /= Float(format.channelCount)
                    let globalFrame = absoluteFrame + frame
                    if globalFrame < analysisLimit { mono.append(sample) }
                    let bucket = min(
                        waveformPointCount - 1,
                        Int(Double(globalFrame) / Double(max(totalFrames, 1)) * Double(waveformPointCount))
                    )
                    waveform[bucket] = max(waveform[bucket], abs(sample))
                }
                absoluteFrame += count
            }

            let bpmEstimate = LYBeatMapAnalyzer.estimateBPM(
                monoSamples: mono,
                sampleRate: format.sampleRate
            )
            let credibleBPM = bpmEstimate.flatMap { $0.confidence >= 0.35 ? $0.bpm : nil }
            let beatMap = credibleBPM.flatMap {
                LYBeatMapAnalyzer.detect(
                    monoSamples: mono,
                    sampleRate: format.sampleRate,
                    sourceBPM: $0
                )
            }
            return LYImportedAudio(
                fileName: url.lastPathComponent,
                displayName: url.deletingPathExtension().lastPathComponent.uppercased(),
                data: data,
                duration: Double(file.length) / format.sampleRate,
                sampleRate: format.sampleRate,
                channelCount: Int(format.channelCount),
                waveformPeaks: waveform,
                sourceBPM: credibleBPM,
                beatMap: beatMap
            )
        }.value
    }
}
