import XCTest
@testable import LYLLTH

final class AppPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LYLLTHTests.AppPreferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsProduceProfessionalBlankProjectSettings() {
        var session = LYLLTHSession.blank()
        LYAppPreferences.applyNewProjectDefaults(to: &session, defaults: defaults)

        XCTAssertEqual(session.sampleRate, 48_000)
        XCTAssertEqual(session.bitDepth, 24)
        XCTAssertEqual(session.recordingSettings?.preRollBars, 1)
        XCTAssertEqual(session.recordingSettings?.loopTakes, true)
        XCTAssertEqual(session.recordingSettings?.inputMonitoring, false)
        XCTAssertEqual(session.recordingSettings?.manualLatencyMS, 0)
    }

    func testNewProjectPreferencesAreCopiedAndNormalized() {
        defaults.set(44_100.0, forKey: LYPreferenceKey.newProjectSampleRate)
        defaults.set(16, forKey: LYPreferenceKey.newProjectBitDepth)
        defaults.set(2, forKey: LYPreferenceKey.recordingPreRollBars)
        defaults.set(false, forKey: LYPreferenceKey.recordingLoopTakes)
        defaults.set(true, forKey: LYPreferenceKey.recordingInputMonitoring)
        defaults.set(9.2, forKey: LYPreferenceKey.recordingLatencyMS)
        var session = LYLLTHSession.blank()

        LYAppPreferences.applyNewProjectDefaults(to: &session, defaults: defaults)

        XCTAssertEqual(session.sampleRate, 44_100)
        XCTAssertEqual(session.bitDepth, 16)
        XCTAssertEqual(session.recordingSettings?.preRollBars, 2)
        XCTAssertEqual(session.recordingSettings?.loopTakes, false)
        XCTAssertEqual(session.recordingSettings?.inputMonitoring, true)
        XCTAssertEqual(session.recordingSettings?.manualLatencyMS, 10)
    }

    func testTextScaleUsesSupportedReadableSteps() {
        defaults.set(1.31, forKey: LYPreferenceKey.interfaceTextScale)
        XCTAssertEqual(LYAppPreferences.textScale(in: defaults), 1.25)
        defaults.set(1.38, forKey: LYPreferenceKey.interfaceTextScale)
        XCTAssertEqual(LYAppPreferences.textScale(in: defaults), 1.4)
    }

    func testResetRemovesOnlyLYLLTHPreferenceKeys() {
        defaults.set(1.4, forKey: LYPreferenceKey.interfaceTextScale)
        defaults.set("keep", forKey: "Unrelated")

        LYAppPreferences.reset(defaults)

        XCTAssertNil(defaults.object(forKey: LYPreferenceKey.interfaceTextScale))
        XCTAssertEqual(defaults.string(forKey: "Unrelated"), "keep")
    }
}
