import Foundation

enum LYPreferenceKey {
    static let interfaceTextScale = "LYLLTH.interfaceTextScale"
    static let highContrast = "LYLLTH.highContrast"
    static let newProjectSampleRate = "LYLLTH.newProjectSampleRate"
    static let newProjectBitDepth = "LYLLTH.newProjectBitDepth"
    static let recordingPreRollBars = "LYLLTH.recordingPreRollBars"
    static let recordingLoopTakes = "LYLLTH.recordingLoopTakes"
    static let recordingInputMonitoring = "LYLLTH.recordingInputMonitoring"
    static let recordingLatencyMS = "LYLLTH.recordingLatencyMS"

    static let all = [
        interfaceTextScale, highContrast, newProjectSampleRate, newProjectBitDepth,
        recordingPreRollBars, recordingLoopTakes, recordingInputMonitoring, recordingLatencyMS
    ]
}

/// App-wide preferences. Project-independent values live in UserDefaults;
/// every setting that changes sound is copied into a new project so the
/// project remains portable and deterministic afterwards.
enum LYAppPreferences {
    static let textScales = [0.9, 1.0, 1.15, 1.25, 1.4]
    static let sampleRates = [44_100.0, 48_000.0]
    static let bitDepths = [16, 24]
    static let preRollBars = [0, 1, 2]
    static let latencyOffsets = [-20.0, -10.0, 0.0, 10.0, 20.0]

    static func textScale(in defaults: UserDefaults = .standard) -> Double {
        nearest(defaults.object(forKey: LYPreferenceKey.interfaceTextScale) as? Double ?? 1, in: textScales)
    }

    static func highContrast(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: LYPreferenceKey.highContrast) as? Bool ?? false
    }

    static func applyNewProjectDefaults(to session: inout LYLLTHSession, defaults: UserDefaults = .standard) {
        session.sampleRate = nearest(
            defaults.object(forKey: LYPreferenceKey.newProjectSampleRate) as? Double ?? 48_000,
            in: sampleRates
        )
        session.bitDepth = nearest(
            defaults.object(forKey: LYPreferenceKey.newProjectBitDepth) as? Int ?? 24,
            in: bitDepths
        )
        let bars = nearest(
            defaults.object(forKey: LYPreferenceKey.recordingPreRollBars) as? Int ?? 1,
            in: preRollBars
        )
        session.countIn = bars > 0
        session.recordingSettings = LYRecordingSettings(
            preRollBars: bars,
            loopTakes: defaults.object(forKey: LYPreferenceKey.recordingLoopTakes) as? Bool ?? true,
            inputMonitoring: defaults.object(forKey: LYPreferenceKey.recordingInputMonitoring) as? Bool ?? false,
            manualLatencyMS: nearest(
                defaults.object(forKey: LYPreferenceKey.recordingLatencyMS) as? Double ?? 0,
                in: latencyOffsets
            )
        )
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        LYPreferenceKey.all.forEach(defaults.removeObject(forKey:))
    }

    private static func nearest(_ value: Double, in choices: [Double]) -> Double {
        choices.min { abs($0 - value) < abs($1 - value) } ?? choices[0]
    }

    private static func nearest(_ value: Int, in choices: [Int]) -> Int {
        choices.min { abs($0 - value) < abs($1 - value) } ?? choices[0]
    }
}
