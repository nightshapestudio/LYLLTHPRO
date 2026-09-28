import Foundation
import NightshapeAudioEngine

/// A drum kit: the sound on each drum track, nothing else. Loading one swaps
/// the sounds under the song's patterns, levels and effects, as in DrumKit.
struct LYDrumKit: Codable, Identifiable, Equatable {
    struct Slot: Codable, Equatable {
        /// The track this sound was saved from. Kits made in LYLLTH find the
        /// same track again by name; factory kits match by the kind of sound.
        var trackName: String?
        var presetID: String
        /// An edited or saved-as sound travels inside the kit.
        var customPreset: DrumSynthPreset? = nil

        var preset: DrumSynthPreset? {
            if let customPreset, customPreset.id == presetID { return customPreset }
            return DrumSynthPresetLibrary.preset(id: presetID)
        }
    }

    var id: UUID
    var name: String
    var savedAt: Date
    var isFactory: Bool
    var slots: [Slot]
}

enum LYDrumKitLibrary {
    /// DrumKit's own factory kits, so both apps load the same five.
    static let factory: [LYDrumKit] = FactoryKits.all().map { kit in
        LYDrumKit(
            id: kit.id, name: kit.name, savedAt: .distantPast, isFactory: true,
            slots: kit.slots.compactMap { slot in slot.sourcePresetID.map { LYDrumKit.Slot(trackName: nil, presetID: $0) } }
        )
    }

    // MARK: Your kits

    private static var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LYLLTH/Kits", isDirectory: true)
    }

    static func userKits() -> [LYDrumKit] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(LYDrumKit.self, from: Data(contentsOf: $0)) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    static func save(_ kit: LYDrumKit) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(kit).write(to: folder.appendingPathComponent(kit.id.uuidString + ".json"), options: .atomic)
    }

    static func delete(_ kit: LYDrumKit) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(kit.id.uuidString + ".json"))
    }

    // MARK: Song ⇄ kit

    /// Drum tracks a kit can fill: synth sounds, not sample tracks.
    static func drumTrackIndices(in session: LYLLTHSession) -> [Int] {
        session.tracks.indices.filter { session.tracks[$0].kind == .drumkit && session.tracks[$0].samplePath == nil }
    }

    /// The song's current drum sounds as a kit.
    static func kit(named name: String, from session: LYLLTHSession) -> LYDrumKit {
        let slots = drumTrackIndices(in: session).compactMap { index -> LYDrumKit.Slot? in
            let track = session.tracks[index]
            guard let preset = LYDrumSounds.preset(for: track) else { return nil }
            let isCustom = track.customDrumPreset?.id == preset.id
            return LYDrumKit.Slot(trackName: track.name, presetID: preset.id, customPreset: isCustom ? preset : nil)
        }
        return LYDrumKit(id: UUID(), name: name.uppercased(), savedAt: Date(), isFactory: false, slots: slots)
    }

    /// Which slot each drum track gets. A kit saved in LYLLTH goes back to
    /// the tracks with the same names; otherwise each track takes the next
    /// unused sound of its own kind (kick to kick, hat to hat), reusing one
    /// only when the kit has fewer of that kind than the song has tracks.
    static func assignments(of kit: LYDrumKit, in session: LYLLTHSession) -> [(track: Int, slot: LYDrumKit.Slot)] {
        var used = Set<Int>()
        var result: [(Int, LYDrumKit.Slot)] = []
        let tracks = drumTrackIndices(in: session)
        // Same name first.
        var byName: [Int: Int] = [:]
        for track in tracks {
            let name = session.tracks[track].name
            if let slot = kit.slots.indices.first(where: { !used.contains($0) && kit.slots[$0].trackName == name }) {
                byName[track] = slot
                used.insert(slot)
            }
        }
        for track in tracks {
            if let slot = byName[track] { result.append((track, kit.slots[slot])); continue }
            guard let role = LYDrumSounds.preset(for: session.tracks[track])?.category ?? role(ofName: session.tracks[track].name) else { continue }
            let matching = kit.slots.indices.filter { kit.slots[$0].preset?.category == role }
            if let slot = matching.first(where: { !used.contains($0) }) ?? matching.first {
                used.insert(slot)
                result.append((track, kit.slots[slot]))
            }
        }
        return result
    }

    /// Loads a kit's sounds onto the drum tracks. Returns how many changed.
    @discardableResult
    static func load(_ kit: LYDrumKit, into session: inout LYLLTHSession) -> Int {
        var changed = 0
        for (track, slot) in assignments(of: kit, in: session) {
            let before = (session.tracks[track].drumPresetID, session.tracks[track].customDrumPreset)
            session.tracks[track].drumPresetID = slot.presetID
            session.tracks[track].customDrumPreset = slot.customPreset
            if before.0 != slot.presetID || before.1 != slot.customPreset { changed += 1 }
        }
        return changed
    }

    /// The kit whose sounds are on the drum tracks right now, if any.
    static func loadedKit(in session: LYLLTHSession, among kits: [LYDrumKit]) -> LYDrumKit? {
        kits.first { kit in
            let pairs = assignments(of: kit, in: session)
            return !pairs.isEmpty && pairs.allSatisfy { LYDrumSounds.presetID(for: session.tracks[$0.track]) == $0.slot.presetID }
        }
    }

    private static func role(ofName name: String) -> DrumSynthCategory? {
        let upper = name.uppercased()
        let table: [(String, DrumSynthCategory)] = [
            ("KICK", .kick), ("SNARE", .snare), ("CLAP", .clap), ("OPEN", .openHat), ("HAT", .closedHat),
            ("TOM", .tom), ("CRASH", .crash), ("CYMBAL", .crash), ("SUB", .sub), ("PERC", .perc), ("SHAKER", .closedHat)
        ]
        return table.first { upper.contains($0.0) }?.1
    }
}

/// Your own drum synth sounds, made on the DRUM SYNTH page. Kept for every
/// song on this Mac; a song that uses one carries its own copy.
enum LYDrumUserPresets {
    private static var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LYLLTH/DrumSounds", isDirectory: true)
    }

    static func all() -> [DrumSynthPreset] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(DrumSynthPreset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    static func save(_ preset: DrumSynthPreset) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(preset).write(to: folder.appendingPathComponent(safe(preset.id) + ".json"), options: .atomic)
    }

    static func delete(_ preset: DrumSynthPreset) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(safe(preset.id) + ".json"))
    }

    private static func safe(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }
}
