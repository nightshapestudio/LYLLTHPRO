import Foundation

enum LYTrackKind: String, Codable, CaseIterable {
    case drumkit
    case audio
    case instrument
    case auxiliary

    var label: String {
        switch self {
        case .drumkit: return "DRUMKIT"
        case .audio: return "AUDIO"
        case .instrument: return "INSTRUMENT"
        case .auxiliary: return "AUX"
        }
    }
}

enum LYAccent: String, Codable, CaseIterable {
    case teal
    case indigo
    case purple
}

enum LYPluginFormat: String, Codable {
    case builtIn
    case audioUnit
    case vst3
}

struct LYPluginSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var format: LYPluginFormat
    var identifier: String
    var name: String
    var manufacturer: String
    var isBypassed: Bool = false
    var state: Data?
}

struct LYClip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case pattern
        case audio
        case midi
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var startBeat: Double
    var lengthBeats: Double
    var steps: [Bool]?
    var sourceRelativePath: String?
}

struct LYTrack: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: LYTrackKind
    var accent: LYAccent
    var volumeDB: Double = 0
    var pan: Double = 0
    var isMuted = false
    var isSolo = false
    var inputName: String?
    var clips: [LYClip] = []
    var inserts: [LYPluginSlot] = []
}

struct LYLoopRange: Codable, Equatable {
    var startBeat: Double
    var lengthBeats: Double
}

struct LYLLTHSession: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var bpm: Double
    var numerator: Int
    var denominator: Int
    var sampleRate: Double
    var bitDepth: Int
    var loopRange: LYLoopRange?
    var tracks: [LYTrack]

    static func starter() -> LYLLTHSession {
        let fourOnFloor = (0..<16).map { $0 % 4 == 0 }
        let offbeats = (0..<16).map { $0 % 4 == 2 }
        let eighths = (0..<16).map { $0 % 2 == 0 }

        return LYLLTHSession(
            name: "UNTITLED 01",
            bpm: 118,
            numerator: 4,
            denominator: 4,
            sampleRate: 48_000,
            bitDepth: 24,
            loopRange: LYLoopRange(startBeat: 0, lengthBeats: 16),
            tracks: [
                LYTrack(
                    name: "DRUMKIT",
                    kind: .drumkit,
                    accent: .teal,
                    clips: [
                        LYClip(name: "PATTERN 01", kind: .pattern, startBeat: 0, lengthBeats: 16, steps: fourOnFloor),
                        LYClip(name: "PATTERN 02", kind: .pattern, startBeat: 16, lengthBeats: 16, steps: offbeats)
                    ],
                    inserts: Self.nightshapeStarterChain
                ),
                LYTrack(
                    name: "DARK POLY",
                    kind: .instrument,
                    accent: .indigo,
                    volumeDB: -3,
                    clips: [LYClip(name: "CHORD BED", kind: .midi, startBeat: 0, lengthBeats: 32, steps: eighths)],
                    inserts: [
                        LYPluginSlot(format: .builtIn, identifier: "nightshape.chorus", name: "CHORUS", manufacturer: "NIGHTSHAPE")
                    ]
                ),
                LYTrack(
                    name: "VOCAL",
                    kind: .audio,
                    accent: .purple,
                    volumeDB: -6,
                    inputName: "INPUT 1",
                    clips: [LYClip(name: "DROP AUDIO HERE", kind: .audio, startBeat: 8, lengthBeats: 12)]
                ),
                LYTrack(name: "RETURN A", kind: .auxiliary, accent: .teal, volumeDB: -8)
            ]
        )
    }

    private static var nightshapeStarterChain: [LYPluginSlot] {
        [
            LYPluginSlot(format: .builtIn, identifier: "nightshape.equalizer", name: "EQUALIZER", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.compressor", name: "COMPRESSOR", manufacturer: "NIGHTSHAPE"),
            LYPluginSlot(format: .builtIn, identifier: "nightshape.decimator", name: "SONIC DECIMATOR", manufacturer: "NIGHTSHAPE")
        ]
    }
}
