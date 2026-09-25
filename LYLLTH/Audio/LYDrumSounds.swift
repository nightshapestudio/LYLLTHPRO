import AVFoundation
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

    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LYLLTH/DrumSynth", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The preset rendered to a WAV, rendering only if it is not cached. The
    /// file name carries a hash of the preset, so an edited preset re-renders.
    static func renderedFile(for preset: DrumSynthPreset) async throws -> URL {
        let data = (try? JSONEncoder().encode(preset)) ?? Data()
        let url = folder.appendingPathComponent("\(preset.id)-\(abs(data.hashValue & 0xFFFFFFF)).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return try await Task.detached(priority: .userInitiated) {
            let result = try DrumSynthRenderer.renderPresetToBuffer(preset)
            guard let buffer = result.makePCMBuffer(stereo: true) else { throw CocoaError(.fileWriteUnknown) }
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            if #available(macOS 15.0, *) { file.close() }
            return url
        }.value
    }

    /// A short render for the browser's audition.
    static func auditionBuffer(for preset: DrumSynthPreset) async -> AVAudioPCMBuffer? {
        await Task.detached(priority: .userInitiated) {
            (try? DrumSynthRenderer.renderPresetToBuffer(preset, maxDuration: 3))?.makePCMBuffer(stereo: true)
        }.value
    }
}
