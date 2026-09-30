import Foundation

/// Project defaults and reset. The type, its key names and the interface
/// readers are in LYLLTH/Theme/LYInterfacePreferences.swift.
extension LYAppPreferences {
    static let sampleRates = [44_100.0, 48_000.0]
    static let bitDepths = [16, 24]
    static let preRollBars = [0, 1, 2]
    static let latencyOffsets = [-20.0, -10.0, 0.0, 10.0, 20.0]

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

    private static func nearest(_ value: Int, in choices: [Int]) -> Int {
        choices.min { abs($0 - value) < abs($1 - value) } ?? choices[0]
    }
}
