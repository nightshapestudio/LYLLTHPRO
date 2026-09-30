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
///
/// The interface readers live here, beside the theme, because LUNATK's
/// plug-ins compile LYLLTH/Theme but not the session model. The project
/// defaults are an extension in LYLLTH/Models/LYAppPreferences.swift.
enum LYAppPreferences {
    static let textScales = [0.9, 1.0, 1.15, 1.25, 1.4]

    static func textScale(in defaults: UserDefaults = .standard) -> Double {
        nearest(defaults.object(forKey: LYPreferenceKey.interfaceTextScale) as? Double ?? 1, in: textScales)
    }

    static func highContrast(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: LYPreferenceKey.highContrast) as? Bool ?? false
    }

    static func nearest(_ value: Double, in choices: [Double]) -> Double {
        choices.min { abs($0 - value) < abs($1 - value) } ?? choices[0]
    }
}
