import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

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
}

struct LYLLTHSessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lyllthSession] }
    static var writableContentTypes: [UTType] { [.lyllthSession] }

    var session: LYLLTHSession
    /// Project-owned originals keyed by their path below `Audio/`.
    /// Edits remain references into these immutable bytes.
    var audioAssets: [String: Data]

    init(session: LYLLTHSession = .starter()) {
        self.session = session
        audioAssets = [:]
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isDirectory,
              let children = fileWrapper.fileWrappers,
              let projectData = children["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LYLLTHSession.self, from: projectData)
        guard decoded.schemaVersion <= LYLLTHSession.currentSchemaVersion else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        session = decoded.migratedToCurrentSchema()
        audioAssets = children["Audio"]?.fileWrappers?.reduce(into: [:]) { result, entry in
            guard let data = entry.value.regularFileContents else { return }
            result[entry.key] = data
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

        let manifest = LYLLTHManifest(
            schemaVersion: LYLLTHSession.currentSchemaVersion,
            projectID: snapshot.id,
            projectName: snapshot.name,
            modifiedAt: snapshot.modifiedAt
        )

        let audioWrappers = audioAssets.reduce(into: [String: FileWrapper]()) { result, entry in
            result[entry.key] = FileWrapper(regularFileWithContents: entry.value)
        }

        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: try encoder.encode(manifest)),
            "project.json": FileWrapper(regularFileWithContents: try encoder.encode(snapshot)),
            "Audio": FileWrapper(directoryWithFileWrappers: audioWrappers),
            "Presets": FileWrapper(directoryWithFileWrappers: [:]),
            "PluginStates": FileWrapper(directoryWithFileWrappers: [:])
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
        }

        let storedName = uniqueAudioName(imported.fileName)
        audioAssets[storedName] = imported.data
        let durationBeats = imported.duration * max(session.bpm, 1) / 60
        let clip = LYClip(
            name: imported.displayName,
            kind: .audio,
            startBeat: max(0, atBeat),
            lengthBeats: max(0.001, durationBeats),
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
        while audioAssets[candidate] != nil {
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
