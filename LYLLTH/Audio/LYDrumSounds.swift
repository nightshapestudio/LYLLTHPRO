import AVFoundation
import CryptoKit
import Foundation
import NightshapeAudioEngine

/// DrumKit's drum-synth library on LYLLTH's drum tracks. Each preset is
/// rendered by DrumKit's own renderer into a one-shot, cached on disk, and
/// loaded as the track's sample: the same path DrumKit uses, so a kick here is
/// the kick you hear on the phone.
enum LYDrumSounds {
    static var presets: [DrumSynthPreset] { DrumSynthPresetLibrary.builtInPresets }

    static var grouped: [(DrumSynthCategory, [DrumSynthPreset])] {
        DrumSynthPresetLibrary.groupedPresets()
    }

    static func preset(id: String?) -> DrumSynthPreset? {
        id.flatMap(DrumSynthPresetLibrary.preset(id:))
    }

    /// What a drum track plays when it has not been given a sound: chosen by
    /// its name, so the starter kit and older songs sound like a drum kit.
    static func defaultPresetID(for track: LYTrack) -> String? {
        guard track.kind == .drumkit else { return nil }
        let name = track.name.uppercased()
        let table: [(String, String)] = [
            ("KICK", "kick_064"), ("SNARE", "snare_proof_001"), ("CLOSED", "closedhat_001"),
            ("OPEN", "openhat_001"), ("CLAP", "clap_001"), ("LOW TOM", "tom_002"),
            ("HIGH TOM", "tom_004"), ("TOM", "tom_001"), ("SHAKER", "closedhat_003"),
            ("HAT", "closedhat_001"), ("CRASH", "crash_001"), ("PERC", "perc_001"), ("SUB", "kick_ns03")
        ]
        for (word, id) in table where name.contains(word) && preset(id: id) != nil { return id }
        return presets.first { $0.category == .perc }?.id
    }

    static func presetID(for track: LYTrack) -> String? {
        track.drumPresetID ?? defaultPresetID(for: track)
    }

    /// The preset a drum track plays, its own custom one included.
    static func preset(for track: LYTrack) -> DrumSynthPreset? {
        let id = presetID(for: track)
        if let custom = track.customDrumPreset, custom.id == id { return custom }
        return preset(id: id)
    }

    /// What a track plays, named for its header: the drum sound or the
    /// LUNATK patch. Nil for tracks with nothing to choose.
    static func soundName(for track: LYTrack) -> String? {
        if track.kind == .drumkit {
            return track.samplePath == nil ? preset(for: track)?.name.uppercased() : nil
        }
        return track.synth.map { "LUNATK · " + $0.name.uppercased() }
    }

    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LYLLTH/DrumSynth", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The preset rendered to a WAV, rendering only if it is not cached. The
    /// file name carries a hash of the preset, so an edited preset re-renders.
    /// Rendered at DrumKit's level: measured reference presets come out of the
    /// synth 30 dB down and only reach level through normalization.
    static func renderedFile(for preset: DrumSynthPreset) async throws -> URL {
        _ = removeLegacyRenders
        let url = folder.appendingPathComponent("\(preset.id)-s\(cacheKey(for: preset)).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return try await Task.detached(priority: .userInitiated) {
            let result = try DrumSynthRenderer.renderPresetToBuffer(preset, normalize: true)
            guard let buffer = result.makePCMBuffer(stereo: true) else { throw CocoaError(.fileWriteUnknown) }
            // Written aside and moved in, so a cut-short render never looks cached.
            let partial = url.deletingPathExtension().appendingPathExtension(UUID().uuidString + ".partial.wav")
            do {
                let file = try AVAudioFile(forWriting: partial, settings: buffer.format.settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                try file.write(from: buffer)
                if #available(macOS 15.0, *) { file.close() }
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: partial)
            } else {
                try FileManager.default.moveItem(at: partial, to: url)
            }
            removeOtherRenders(of: preset.id, keeping: url.lastPathComponent)
            return url
        }.value
    }

    /// Names a render by the preset's settings. Stable across launches, so a
    /// sound renders once; an edited preset gets a new name.
    static func cacheKey(for preset: DrumSynthPreset) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(preset)) ?? Data(preset.id.utf8)
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Older renders of the same sound: an edited preset leaves its last
    /// render behind otherwise.
    private static func removeOtherRenders(of id: String, keeping name: String) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let prefix = id + "-"
        for other in names where other != name && other.hasPrefix(prefix) && other.hasSuffix(".wav") && !other.hasSuffix(".partial.wav") {
            // The rest must be just the key, so "kick_1" never takes "kick_1-x"'s files.
            let rest = other.dropFirst(prefix.count).dropLast(4)
            guard !rest.contains("-"), rest.first == "s" || rest.first == "n" || rest.allSatisfy(\.isNumber) else { continue }
            try? fm.removeItem(at: folder.appendingPathComponent(other))
        }
    }

    /// Renders named by the old per-launch hash never hit again. Removed
    /// once per launch.
    private static let removeLegacyRenders: Void = {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasSuffix(".wav") {
            guard let dash = name.lastIndex(of: "-") else { continue }
            let key = name[name.index(after: dash)...].dropLast(4)
            let digits = key.first == "n" ? key.dropFirst() : key
            if name.hasSuffix(".partial.wav") || (!digits.isEmpty && digits.allSatisfy(\.isNumber)) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }()

    /// A short render for the browser's audition.
    static func auditionBuffer(for preset: DrumSynthPreset) async -> AVAudioPCMBuffer? {
        await Task.detached(priority: .userInitiated) {
            (try? DrumSynthRenderer.renderPresetToBuffer(preset, normalize: true, maxDuration: 3))?.makePCMBuffer(stereo: true)
        }.value
    }
}
