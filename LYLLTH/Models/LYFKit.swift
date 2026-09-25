import Foundation
import UniformTypeIdentifiers
import NightshapeAudioEngine

extension UTType {
    /// DrumKit's project package. A stored ZIP with a `.fkit` extension; the
    /// older `.dkit` name opens too.
    static let drumkitProject = UTType(importedAs: "net.nightshape.drumkit.project", conformingTo: .zip)
}

/// The `manifest.json` DrumKit writes into every `.fkit`.
private struct FKitManifest: Codable {
    var format: String
    var schemaVersion: Int
    var generatedBy: String
    var projectFileName: String
    var projectName: String
    var savedAt: Date
}

/// DrumKit's `.fkit` projects in and out of LYLLTH.
///
/// DrumKit has sixteen rows that all play the same numbered pattern, and a
/// song of blocks that each play one pattern on every row. LYLLTH has tracks
/// with their own patterns and regions. Opening a `.fkit` makes one track per
/// row, one pattern per DrumKit pattern (kept off the song), and one
/// placement per song block. Saving goes back the other way.
enum LYFKit {
    struct Imported {
        var session: LYLLTHSession
        /// Sample audio the rows play, by name for the song's `Audio/` folder.
        var assets: [String: Data]
        /// What DrumKit had that LYLLTH could not bring in.
        var notes: [String]
    }

    struct Exported {
        var data: Data
        /// What LYLLTH has that a DrumKit project cannot hold.
        var notes: [String]
    }

    enum Failure: LocalizedError {
        case notAProject(String)
        case newerSchema(Int)

        var errorDescription: String? {
            switch self {
            case .notAProject(let detail): return "This is not a DrumKit project (\(detail))."
            case .newerSchema(let version): return "This project was saved by a newer DrumKit (package version \(version))."
            }
        }
    }

    private static let format = "fkit"
    private static let acceptedFormats: Set<String> = ["fkit", "dkit"]
    private static let schemaVersion = 1
    private static let rowCount = 16

    // MARK: - Open

    static func importProject(from data: Data) throws -> Imported {
        let entries = try ZipArchiveReader.readStoredArchive(from: data)
        let decoder = JSONDecoder()
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }) else {
            throw Failure.notAProject("no manifest.json")
        }
        let manifest = try decoder.decode(FKitManifest.self, from: manifestEntry.data)
        guard acceptedFormats.contains(manifest.format) else { throw Failure.notAProject("format \(manifest.format)") }
        guard manifest.schemaVersion <= schemaVersion else { throw Failure.newerSchema(manifest.schemaVersion) }
        let payload = manifest.projectFileName.isEmpty ? "project.json" : manifest.projectFileName
        guard let projectEntry = entries.first(where: { $0.name == payload }) ?? entries.first(where: { $0.name == "project.json" }) else {
            throw Failure.notAProject("no project.json")
        }
        let snapshot = try decoder.decode(ProjectSnapshot.self, from: projectEntry.data)

        var samples: [String: Data] = [:]
        for entry in entries where entry.name.hasPrefix("audio/") && entry.name.hasSuffix(".wav") {
            let id = String(entry.name.dropFirst("audio/".count).dropLast(".wav".count))
            samples[id] = entry.data
        }
        var presets: [String: DrumSynthPreset] = [:]
        for entry in entries where entry.name.hasPrefix("presets/") && entry.name.hasSuffix(".json") {
            if let preset = try? DrumSynthPresetLibrary.decodePreset(from: entry.data) { presets[preset.id] = preset }
        }
        return convert(snapshot, samples: samples, presets: presets)
    }

    static func convert(_ snapshot: ProjectSnapshot, samples: [String: Data], presets: [String: DrumSynthPreset]) -> Imported {
        var notes: [String] = []
        let meter = snapshot.meter ?? .fourFour
        let barSteps = meter.activeStepCount
        let rows = max(
            snapshot.patterns.map(\.trackSteps.count).max() ?? 0,
            (snapshot.rowSources ?? []).map { $0.rowIndex + 1 }.max() ?? 0,
            snapshot.trackNames.map { $0.index + 1 }.max() ?? 0,
            1
        )
        let accents: [LYAccent] = [.teal, .teal, .indigo, .indigo, .purple, .purple]
        let effectsByRow = Dictionary((snapshot.effects?.rows ?? []).map { ($0.rowIndex, $0) }, uniquingKeysWith: { first, _ in first })
        let sourcesByRow = Dictionary((snapshot.rowSources ?? []).map { ($0.rowIndex, $0) }, uniquingKeysWith: { first, _ in first })
        var assets: [String: Data] = [:]

        var tracks: [LYTrack] = (0..<rows).map { row in
            let source = sourcesByRow[row]
            let name = snapshot.trackNames.first { $0.index == row }?.name ?? source?.displayName ?? "TRACK \(row + 1)"
            let isSynth = source?.sourceSynthPresetID != nil || source?.chordPresetID != nil
            var track = LYTrack(
                name: name.uppercased(),
                kind: isSynth ? .instrument : .drumkit,
                accent: accents[row % accents.count],
                volumeDB: source?.volume ?? 0
            )
            track.pan = min(max(source?.pan ?? 0, -1), 1)
            track.isMuted = snapshot.mutedTrackIndexes?.contains(row) ?? false
            track.isSolo = snapshot.soloedTrackIndexes?.contains(row) ?? false
            if let groups = snapshot.trackChokeGroups, groups.indices.contains(row), groups[row] > 0 { track.chokeGroup = groups[row] }
            if isSynth {
                track.synthPresetID = source?.sourceSynthPresetID
                if let chord = source?.chordPresetID {
                    track.isChordTrack = true
                    track.chordPresetID = chord
                }
            } else if source?.sourceKind == "sample", let id = source?.sourceSampleID, let wav = samples[id] {
                let path = "fkit-\(id).wav"
                assets[path] = wav
                track.samplePath = path
            } else if let presetID = source?.sourcePresetID {
                track.drumPresetID = presetID
                if DrumSynthPresetLibrary.preset(id: presetID) == nil {
                    if let custom = presets[presetID] {
                        track.customDrumPreset = custom
                    } else {
                        notes.append("\(track.name): its drum sound was not in the file, so it plays a default")
                        track.drumPresetID = nil
                    }
                }
            } else if source?.sourceKind == "sample" {
                notes.append("\(track.name): its sample was not in the file, so it plays a default")
            }
            if let effects = effectsByRow[row] {
                track.fx = rack(from: effects)
                track.envelope = effects.envelope
            }
            return track
        }

        // One pattern clip per DrumKit pattern on every row, kept off the song.
        var patternClipIDs: [UUID: [UUID]] = [:]
        for pattern in snapshot.patterns {
            let count = DrumPattern.clampStepCount(pattern.stepCount)
            var ids: [UUID] = []
            for row in 0..<rows {
                let cells = pattern.trackSteps.indices.contains(row) ? Array(pattern.trackSteps[row].prefix(count)) : []
                var clip = LYClip(
                    name: pattern.name.uppercased(),
                    kind: tracks[row].kind == .drumkit ? .pattern : .midi,
                    startBeat: 0,
                    lengthBeats: Double(count) * lyBeatsPerStep,
                    steps: (0..<count).map { cells.indices.contains($0) && cells[$0].isEnabled },
                    stepParameters: (0..<count).map { cells.indices.contains($0) ? parameters(from: cells[$0]) : .default }
                )
                clip.isOffTimeline = true
                ids.append(clip.id)
                tracks[row].clips.append(clip)
            }
            patternClipIDs[pattern.id] = ids
        }

        // One placement per song block, per row.
        var cursor = 0
        var placedAny = false
        for block in snapshot.songBlocks {
            guard let ids = patternClipIDs[block.patternID],
                  let pattern = snapshot.patterns.first(where: { $0.id == block.patternID }) else { continue }
            let start = block.startStep ?? (block.startBar.map { $0 * barSteps } ?? cursor)
            let length = max(1, block.lengthSteps ?? block.lengthInBars * barSteps)
            cursor = max(cursor, start + length)
            for row in 0..<rows {
                var placement = LYClip(
                    name: pattern.name.uppercased(),
                    kind: tracks[row].kind == .drumkit ? .pattern : .midi,
                    startBeat: Double(start) * lyBeatsPerStep,
                    lengthBeats: Double(length) * lyBeatsPerStep
                )
                placement.patternSourceID = ids[row]
                tracks[row].clips.append(placement)
            }
            placedAny = true
        }
        // A project with no song plays its current pattern in SONG too.
        if !placedAny, !snapshot.patterns.isEmpty {
            let active = min(max(snapshot.activePatternIndex, 0), snapshot.patterns.count - 1)
            for row in 0..<rows {
                let patternIndex = tracks[row].patternIndices[active]
                tracks[row].clips[patternIndex].isOffTimeline = nil
            }
        }
        if !(snapshot.songFXBlocks ?? []).isEmpty {
            notes.append("the song's FX lane (filter and FRACTURE moves) is not in LYLLTH yet")
        }

        var session = LYLLTHSession.starter()
        session.id = UUID()
        session.name = snapshot.name.uppercased()
        session.createdAt = Date()
        session.modifiedAt = Date()
        session.bpm = snapshot.bpm
        session.numerator = meter.numerator
        session.denominator = meter.denominator
        session.songKey = snapshot.songKey ?? .default
        session.swing = snapshot.swing
        session.activePatternIndex = min(max(snapshot.activePatternIndex, 0), max(snapshot.patterns.count - 1, 0))
        session.loopRange = nil
        session.isLoopEnabled = false
        session.mainVolumeDB = snapshot.mainOutputVolume
        session.tracks = tracks
        if let effects = snapshot.effects {
            session.mainFX = mainRack(from: effects)
            session.reverb = effects.reverb
        }
        return Imported(session: session, assets: assets, notes: notes)
    }

    private static func parameters(from cell: PatternStepState) -> LYStepParameters {
        var value = LYStepParameters()
        value.velocity = unit(cell.velocity)
        value.level = unit(cell.volume)
        value.cutoff = unit(cell.cutoff)
        value.resonance = unit(cell.resonance)
        value.effect = unit(cell.fx)
        value.pan = (Double(min(max(cell.pan, 0), 127)) - 64) / 63
        value.pitch = Double(cell.pitchSemitones)
        value.noteLength = Double(max(cell.noteLengthSteps, 1))
        value.chord = cell.chord
        value.flam = cell.isFlam ? true : nil
        return value
    }

    private static func unit(_ value: Int) -> Double { Double(min(max(value, 0), 127)) / 127 }

    private static func rack(from row: RowEffectsSnapshot) -> LYFXRack {
        LYFXRack(
            order: row.chainOrder, eqBands: row.eqBands, eqCut: row.eqCut, compressor: row.compressor,
            tape: row.tape, flanger: row.flanger, chorus: row.chorus, voidGate: row.voidGate,
            tempoDelay: row.tempoDelay, filter: row.filter, fracture: row.fracture, deadlock: row.deadlock,
            strike: row.strike, steelBody: row.steelBody, undertow: row.undertow, splitField: row.splitField,
            shear: row.shear, cabinet: row.cabinet, pump: row.pump, finale: row.elasticLimiter,
            signalBloom: row.signalBloom, decimator: row.decimator, reverbSend: row.reverbSend
        )
    }

    private static func mainRack(from effects: EffectsSnapshot) -> LYFXRack {
        LYFXRack(
            order: effects.mainChainOrder, eqBands: effects.mainEQBands, eqCut: effects.mainEQCut,
            compressor: effects.mainCompressor, tape: effects.mainTape, flanger: effects.mainFlanger,
            chorus: effects.mainChorus, voidGate: effects.mainVoidGate, tempoDelay: effects.mainTempoDelay,
            filter: effects.mainFilter, fracture: effects.mainFracture, deadlock: effects.mainDeadlock,
            strike: effects.mainStrike, steelBody: effects.mainSteelBody, undertow: nil,
            splitField: effects.mainSplitField, shear: effects.mainShear, cabinet: effects.mainCabinet,
            pump: effects.mainPump, finale: effects.mainFinale, signalBloom: effects.tapeDelay,
            decimator: effects.mainDecimator, reverbSend: nil
        )
    }

    // MARK: - Save

    static func exportProject(_ session: LYLLTHSession, assets: [String: Data]) throws -> Exported {
        var notes: [String] = []
        let musical = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        if musical.count > rowCount { notes.append("DrumKit has 16 rows; only the first 16 sequencer tracks are saved") }
        let others = session.tracks.filter { $0.kind == .audio || $0.kind == .auxiliary }
        if !others.isEmpty { notes.append("audio tracks and buses do not exist in DrumKit and are left out") }
        let rows = Array(musical.prefix(rowCount))
        let meter: TimeSignature
        switch (session.numerator, session.denominator) {
        case (3, 4): meter = .threeFour
        case (6, 8): meter = .sixEight
        case (4, 4): meter = .fourFour
        default:
            meter = .fourFour
            notes.append("DrumKit has 4/4, 3/4 and 6/8; this song is saved in 4/4")
        }
        let barSteps = meter.activeStepCount

        // Patterns: DrumKit pattern N is each row's Nth pattern.
        let patternCount = max(1, rows.map(\.patternIndices.count).max() ?? 1)
        var patterns: [DrumPattern] = (0..<patternCount).map { index in
            let clips = rows.map { track -> LYClip? in
                let indices = track.patternIndices
                return indices.indices.contains(index) ? track.clips[indices[index]] : nil
            }
            let count = DrumPattern.clampStepCount(clips.compactMap { $0?.steps?.count }.max() ?? 16)
            let name = clips.compactMap { $0?.name }.first ?? "PATTERN \(index + 1)"
            return DrumPattern(id: UUID(), name: name, trackSteps: paddedRows(clips.map { cells(for: $0) }), stepCount: count)
        }

        // Song: regions that start and end together on every row that has
        // the pattern become one block. A region only some rows share gets
        // its own copy of the pattern with the other rows silent.
        struct Region: Hashable { var pattern: Int; var start: Int; var length: Int }
        var rowsByRegion: [Region: Set<Int>] = [:]
        var droppedOffsets = false
        for (row, track) in rows.enumerated() {
            let indices = track.patternIndices
            for region in track.songRegions {
                let content = track.patternContent(of: region)
                guard let pattern = indices.firstIndex(where: { track.clips[$0].id == content.id }) else { continue }
                if region.loopOffsetBeats > 0.001 { droppedOffsets = true }
                let key = Region(
                    pattern: pattern,
                    start: Int((region.startBeat / lyBeatsPerStep).rounded()),
                    length: max(1, Int((region.lengthBeats / lyBeatsPerStep).rounded()))
                )
                rowsByRegion[key, default: []].insert(row)
            }
        }
        if droppedOffsets { notes.append("regions trimmed from the left start at the top of their pattern in DrumKit") }
        var blocks: [SongBlock] = []
        var laneEnds: [Int] = []
        for region in rowsByRegion.keys.sorted(by: { ($0.start, $0.pattern) < ($1.start, $1.pattern) }) {
            let playing = rowsByRegion[region]!
            let having = Set(rows.indices.filter { rows[$0].patternIndices.count > region.pattern })
            var patternID = patterns[region.pattern].id
            if !having.isSubset(of: playing) {
                var part = patterns[region.pattern]
                part = DrumPattern(id: UUID(), name: part.name + " PART", trackSteps: part.trackSteps.enumerated().map { row, cells in
                    playing.contains(row) ? cells : cells.map { var cell = $0; cell.isEnabled = false; return cell }
                }, stepCount: part.stepCount)
                patterns.append(part)
                patternID = part.id
            }
            let lane = laneEnds.firstIndex { $0 <= region.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(0) }
            laneEnds[lane] = region.start + region.length
            blocks.append(SongBlock(
                id: UUID(),
                patternID: patternID,
                lengthInBars: max(1, Int(ceil(Double(region.length) / Double(barSteps)))),
                startBar: region.start / barSteps,
                lane: lane,
                startStep: region.start,
                lengthSteps: region.length
            ))
        }

        // Sources, samples and custom presets.
        var entries: [ZipArchiveWriter.Entry] = []
        var sources: [RowSourceSnapshot] = []
        for (row, track) in rows.enumerated() {
            var source = RowSourceSnapshot(rowIndex: row, sourcePresetID: nil, sourceKind: nil, sourceSampleID: nil, sourceSynthPresetID: nil)
            source.displayName = track.name
            source.volume = track.volumeDB
            source.pan = track.pan
            if track.kind == .instrument {
                source.sourceSynthPresetID = track.synthPresetID ?? SynthPreset.junoDream.rawValue
                if track.isChordTrack == true { source.chordPresetID = track.chordPresetID }
                if track.synth != nil { notes.append("\(track.name) plays LUNATK, which DrumKit does not have; it gets a DrumKit synth sound") }
            } else if let path = track.samplePath, let data = assets[path] {
                let id = UUID()
                source.sourceKind = "sample"
                source.sourceSampleID = id.uuidString
                entries.append(ZipArchiveWriter.Entry(data: data, archiveName: "audio/\(id.uuidString).wav"))
            } else if let preset = LYDrumSounds.preset(for: track) {
                source.sourceKind = "synth"
                source.sourcePresetID = preset.id
                if DrumSynthPresetLibrary.preset(id: preset.id) == nil, let data = try? DrumSynthPresetLibrary.encodedPresetData(preset) {
                    entries.append(ZipArchiveWriter.Entry(data: data, archiveName: "presets/\(archiveSafe(preset.id)).json"))
                }
            }
            sources.append(source)
        }

        var rowEffects: [RowEffectsSnapshot] = []
        for (row, track) in rows.enumerated() {
            let fx = track.fx ?? LYFXRack()
            var effects = RowEffectsSnapshot(rowIndex: row)
            effects.chainOrder = fx.order
            effects.eqBands = fx.eqBands
            effects.eqCut = fx.eqCut
            effects.compressor = fx.compressor
            effects.tape = fx.tape
            effects.flanger = fx.flanger
            effects.tempoDelay = fx.tempoDelay
            effects.filter = fx.filter
            effects.fracture = fx.fracture
            effects.deadlock = fx.deadlock
            effects.shear = fx.shear
            effects.cabinet = fx.cabinet
            effects.splitField = fx.splitField
            effects.undertow = fx.undertow
            effects.steelBody = fx.steelBody
            effects.strike = fx.strike
            effects.decimator = fx.decimator
            effects.chorus = fx.chorus
            effects.voidGate = fx.voidGate
            effects.pump = fx.pump
            effects.elasticLimiter = fx.finale
            effects.envelope = track.envelope
            effects.reverbSend = fx.reverbSend
            effects.signalBloom = fx.signalBloom
            rowEffects.append(effects)
        }
        let main = session.mainFX ?? LYFXRack()
        var effects = EffectsSnapshot(rows: rowEffects)
        effects.reverb = session.reverb
        effects.tapeDelay = main.signalBloom
        effects.mainEQBands = main.eqBands
        effects.mainCompressor = main.compressor
        effects.mainTape = main.tape
        effects.mainFlanger = main.flanger
        effects.mainTempoDelay = main.tempoDelay
        effects.mainFilter = main.filter
        effects.mainFracture = main.fracture
        effects.mainDeadlock = main.deadlock
        effects.mainShear = main.shear
        effects.mainCabinet = main.cabinet
        effects.mainSplitField = main.splitField
        effects.mainSteelBody = main.steelBody
        effects.mainStrike = main.strike
        effects.mainEQCut = main.eqCut
        effects.mainDecimator = main.decimator
        effects.mainChorus = main.chorus
        effects.mainVoidGate = main.voidGate
        effects.mainPump = main.pump
        effects.mainFinale = main.finale
        effects.mainChainOrder = main.order
        effects.managesPresetSends = true

        let name = String(session.name.uppercased().prefix(24))
        let snapshot = ProjectSnapshot(
            id: UUID(),
            name: name,
            savedAt: Date(),
            bpm: session.bpm,
            meter: meter,
            songKey: session.songKey,
            patterns: patterns,
            activePatternIndex: min(max(session.activePatternIndex ?? 0, 0), patterns.count - 1),
            songBlocks: blocks,
            trackNames: rows.enumerated().map { ProjectTrackName(index: $0.offset, name: $0.element.name, hasCustomName: true) }
                + (rows.count..<rowCount).map { ProjectTrackName(index: $0, name: "TRACK \($0 + 1)", hasCustomName: false) },
            mainOutputVolume: session.mainVolumeDB,
            rowSources: sources,
            mutedTrackIndexes: rows.indices.filter { rows[$0].isMuted },
            soloedTrackIndexes: rows.indices.filter { rows[$0].isSolo },
            effects: effects,
            swing: session.swing,
            trackChokeGroups: rows.map { $0.chokeGroup ?? 0 } + Array(repeating: 0, count: rowCount - rows.count)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = FKitManifest(
            format: format,
            schemaVersion: schemaVersion,
            generatedBy: "LYLLTH MACOS",
            projectFileName: "project.json",
            projectName: name,
            savedAt: snapshot.savedAt
        )
        entries.insert(ZipArchiveWriter.Entry(data: try encoder.encode(snapshot), archiveName: "project.json"), at: 0)
        entries.insert(ZipArchiveWriter.Entry(data: try encoder.encode(manifest), archiveName: "manifest.json"), at: 0)

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("lyllth-\(UUID().uuidString).fkit")
        defer { try? FileManager.default.removeItem(at: temp) }
        try ZipArchiveWriter.writeStoredArchive(entries: entries, to: temp)
        return Exported(data: try Data(contentsOf: temp), notes: notes)
    }

    /// A row's cells for one pattern, padded to DrumKit's 64 backing cells.
    private static func cells(for clip: LYClip?) -> [PatternStepState] {
        let steps = clip?.steps ?? []
        let locks = clip?.stepParameters ?? []
        return (0..<DrumPattern.maximumStepCount).map { index in
            var step = SequencerStep(isEnabled: steps.indices.contains(index) && steps[index])
            if locks.indices.contains(index) {
                let lock = locks[index]
                step.velocity = midi(lock.velocity)
                step.volume = midi(lock.level)
                step.cutoff = midi(lock.cutoff)
                step.resonance = midi(lock.resonance)
                step.fx = midi(lock.effect)
                step.pan = Int((min(max(lock.pan, -1), 1) * 63 + 64).rounded())
                step.pitchSemitones = Int(lock.pitch.rounded())
                step.noteLengthSteps = max(1, Int(lock.noteLength.rounded()))
                step.chord = lock.chord
                step.isFlam = lock.flam == true
            }
            return PatternStepState(step: step)
        }
    }

    private static func paddedRows(_ rows: [[PatternStepState]]) -> [[PatternStepState]] {
        rows + Array(repeating: cells(for: nil), count: max(0, rowCount - rows.count))
    }

    private static func midi(_ unit: Double) -> Int { Int((min(max(unit, 0), 1) * 127).rounded()) }

    private static func archiveSafe(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let mapped = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return mapped.isEmpty ? "preset" : mapped
    }
}
