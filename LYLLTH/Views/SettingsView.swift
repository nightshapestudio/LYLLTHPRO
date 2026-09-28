import AppKit
import SwiftUI

private enum LYSettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case audio = "Audio & Projects"
    case recording = "Recording"
    case midi = "MIDI"
    case plugins = "Plug-ins"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "textformat.size"
        case .audio: return "waveform"
        case .recording: return "record.circle"
        case .midi: return "pianokeys"
        case .plugins: return "puzzlepiece.extension"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "TEXT AND CONTRAST"
        case .audio: return "DEVICES AND NEW SONGS"
        case .recording: return "NEW-SONG DEFAULTS"
        case .midi: return "CONNECTED CONTROLLERS"
        case .plugins: return "AUDIO UNIT DISCOVERY"
        }
    }
}

struct LYSettingsView: View {
    @State private var page: LYSettingsPage = .appearance
    @State private var confirmingReset = false
    @StateObject private var plugins = AudioUnitCatalog()
    @ObservedObject private var midi = LYMIDIInput.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(LYPreferenceKey.interfaceTextScale) private var textScale = 1.0
    @AppStorage(LYPreferenceKey.highContrast) private var highContrast = false
    @AppStorage(LYPreferenceKey.newProjectSampleRate) private var sampleRate = 48_000.0
    @AppStorage(LYPreferenceKey.newProjectBitDepth) private var bitDepth = 24
    @AppStorage(LYPreferenceKey.recordingPreRollBars) private var preRollBars = 1
    @AppStorage(LYPreferenceKey.recordingLoopTakes) private var loopTakes = true
    @AppStorage(LYPreferenceKey.recordingInputMonitoring) private var inputMonitoring = false
    @AppStorage(LYPreferenceKey.recordingLatencyMS) private var latencyMS = 0.0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                // Wider with larger text, so labels stay on one line.
                .frame(width: 190 * min(max(textScale, 1), 1.4))
            Rectangle().fill(LYLLTHTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    pageContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        // Redrawn whole when text size or contrast changes, like the song
        // window: every row reads its font from the preference.
        .id("\(textScale)-\(highContrast)")
        .frame(minWidth: 780, idealWidth: 840, minHeight: 560, idealHeight: 620)
        .background(LYLLTHTheme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            plugins.scan()
            midi.start()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LYLLTH")
                    .font(LYLLTHTheme.wordmark(21))
                    .foregroundStyle(LYLLTHTheme.text)
                Text("SETTINGS")
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.teal)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            ForEach(LYSettingsPage.allCases) { item in
                let selected = item == page
                Button {
                    page = item
                    confirmingReset = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? LYLLTHTheme.teal : LYLLTHTheme.metadata)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.rawValue.uppercased())
                                .font(LYLLTHTheme.label(9.5, weight: selected ? .bold : .medium))
                                .tracking(0.7)
                                .foregroundStyle(selected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                            Text(item.subtitle)
                                .font(LYLLTHTheme.label(7.5, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(LYLLTHTheme.metadata)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                    .background(selected ? LYLLTHTheme.panelRaised : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(selected ? LYLLTHTheme.teal : Color.clear).frame(width: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
            resetArea
                .padding(14)
        }
        .background(LYLLTHTheme.deck)
    }

    private var resetArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if confirmingReset {
                Text("RESET EVERY APP SETTING?")
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.text)
                HStack(spacing: 6) {
                    LYSettingsActionButton("RESET", accent: LYLLTHTheme.purple) {
                        LYAppPreferences.reset()
                        textScale = 1
                        highContrast = false
                        sampleRate = 48_000
                        bitDepth = 24
                        preRollBars = 1
                        loopTakes = true
                        inputMonitoring = false
                        latencyMS = 0
                        confirmingReset = false
                    }
                    LYSettingsActionButton("CANCEL") { confirmingReset = false }
                }
            } else {
                LYSettingsActionButton("RESET DEFAULTS") { confirmingReset = true }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.rawValue.uppercased())
                    .font(LYLLTHTheme.label(13, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(LYLLTHTheme.text)
                Text(page.subtitle)
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.metadata)
            }
            Spacer()
            Text("⌘,")
                .font(LYLLTHTheme.value(10))
                .foregroundStyle(LYLLTHTheme.metadata)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .appearance: appearancePage
        case .audio: audioPage
        case .recording: recordingPage
        case .midi: midiPage
        case .plugins: pluginsPage
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LYSettingsSection("INTERFACE TEXT", detail: "Changes labels, values, editors, Help, and this Settings window immediately.") {
                LYSettingsChoiceRow(
                    choices: [
                        ("90%", 0.9), ("100%", 1.0), ("115%", 1.15),
                        ("125%", 1.25), ("140%", 1.4)
                    ],
                    selection: $textScale
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("A CLEARER VIEW OF THE SESSION")
                        .font(LYLLTHTheme.label(12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(LYLLTHTheme.text)
                    Text("Track names, parameter values, menus, inspectors and long-form guidance all use this scale.")
                        .font(LYLLTHTheme.body(12))
                        .foregroundStyle(LYLLTHTheme.secondary)
                    mixedNumericLabel("BAR 17  ·  48 KHZ  ·  −6.0 DB",
                                      labelFont: LYLLTHTheme.label(11, weight: .bold), numberFont: LYLLTHTheme.value(12))
                        .tracking(0.8)
                        .foregroundStyle(LYLLTHTheme.teal)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LYLLTHTheme.deck)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
            }

            LYSettingsSection("VISIBILITY", detail: "Contrast changes LYLLTH's quiet text and dividers without adding glare or oversized glow.") {
                LYSettingsToggleRow(
                    title: "HIGH-CONTRAST CHROME",
                    detail: "Brighter secondary text, borders and panel separation.",
                    isOn: $highContrast
                )
                LYSettingsStatusRow(
                    title: "REDUCE MOTION",
                    value: reduceMotion ? "ON IN MACOS" : "OFF IN MACOS",
                    detail: "LYLLTH follows the system Accessibility setting for reduced motion."
                )
            }
        }
    }

    private var audioPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LYSettingsSection("AUDIO DEVICE", detail: "LYLLTH follows the macOS default input and output, including aggregate devices.") {
                LYSettingsActionButton("OPEN SOUND SETTINGS", accent: LYLLTHTheme.teal) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
                    NSWorkspace.shared.open(url)
                }
            }

            LYSettingsSection("NEW PROJECTS", detail: "These values are copied into a new blank song. Existing projects keep their saved format.") {
                LYSettingsLabeledChoice(
                    label: "SAMPLE RATE",
                    choices: [("44.1 KHZ", 44_100.0), ("48 KHZ", 48_000.0)],
                    selection: $sampleRate
                )
                LYSettingsLabeledChoice(
                    label: "RECORDING DEPTH",
                    choices: [("16-BIT", 16), ("24-BIT", 24)],
                    selection: $bitDepth
                )
            }
        }
    }

    private var recordingPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LYSettingsSection("NEW-SONG RECORDING", detail: "These are starting points. The recording strip can change them per project.") {
                LYSettingsLabeledChoice(
                    label: "PRE-ROLL",
                    choices: [("OFF", 0), ("1 BAR", 1), ("2 BARS", 2)],
                    selection: $preRollBars
                )
                LYSettingsToggleRow(
                    title: "LOOP TAKES",
                    detail: "Create a separate take for every pass through the cycle.",
                    isOn: $loopTakes
                )
                LYSettingsToggleRow(
                    title: "INPUT MONITORING",
                    detail: "Monitor armed audio tracks through LYLLTH when recording begins.",
                    isOn: $inputMonitoring
                )
                LYSettingsLabeledChoice(
                    label: "RECORDING OFFSET",
                    choices: [
                        ("−20 MS", -20.0), ("−10 MS", -10.0), ("0 MS", 0.0),
                        ("+10 MS", 10.0), ("+20 MS", 20.0)
                    ],
                    selection: $latencyMS
                )
                Text("Use the offset only after a loopback test. Positive values move recorded material later; negative values move it earlier.")
                    .font(LYLLTHTheme.body(10.5))
                    .foregroundStyle(LYLLTHTheme.metadata)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var midiPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LYSettingsSection("MIDI INPUT", detail: "LYLLTH listens to connected MIDI sources. Track routing can narrow the source and channel per track.") {
                LYSettingsStatusRow(
                    title: "CONNECTED SOURCES",
                    value: midi.sources.isEmpty ? "NONE" : "\(midi.sources.count)",
                    detail: midi.sources.isEmpty ? "Connect a controller, then return here." : midi.sources.map(\.name).joined(separator: "  ·  ")
                )
                LYSettingsStatusRow(
                    title: "PERFORMANCE DATA",
                    value: "ENABLED",
                    detail: "Notes, velocity, sustain, pitch bend, pressure, timbre and compatible CC data are preserved."
                )
                LYSettingsActionButton("OPEN AUDIO MIDI SETUP", accent: LYLLTHTheme.indigo) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                }
            }
        }
    }

    private var pluginsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LYSettingsSection("AUDIO UNITS", detail: "A scan checks installed instruments and effects. Units that fail repeatedly stay quarantined until reset.") {
                HStack(spacing: 10) {
                    LYSettingsMetric(label: "INSTRUMENTS", value: "\(plugins.instruments.count)")
                    LYSettingsMetric(label: "EFFECTS", value: "\(plugins.effects.count)")
                    LYSettingsMetric(label: "QUARANTINED", value: "\(plugins.quarantined.count)", accent: plugins.quarantined.isEmpty ? LYLLTHTheme.teal : LYLLTHTheme.purple)
                }
                HStack(spacing: 8) {
                    LYSettingsActionButton(plugins.isScanning ? "SCANNING…" : "SCAN NOW", accent: LYLLTHTheme.teal) {
                        plugins.scan()
                    }
                    .disabled(plugins.isScanning)
                    if !plugins.quarantined.isEmpty {
                        LYSettingsActionButton("RESET QUARANTINE", accent: LYLLTHTheme.purple) {
                            plugins.resetAllQuarantine()
                        }
                    }
                }
                if !plugins.quarantined.isEmpty {
                    Text(plugins.quarantined.map(\.name).joined(separator: "  ·  "))
                        .font(LYLLTHTheme.body(10.5))
                        .foregroundStyle(LYLLTHTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct LYSettingsSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(_ title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.text)
                Text(detail)
                    .font(LYLLTHTheme.body(10.5))
                    .foregroundStyle(LYLLTHTheme.metadata)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }
}

private struct LYSettingsChoiceRow<Value: Hashable>: View {
    let choices: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                let selected = selection == choice.1
                Button { selection = choice.1 } label: {
                    // Digits in the number face, words in Adam.
                    mixedNumericLabel(choice.0, labelFont: LYLLTHTheme.label(8.5, weight: .bold), numberFont: LYLLTHTheme.value(10.5))
                        .tracking(0.6)
                        .foregroundStyle(selected ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(selected ? LYLLTHTheme.teal.opacity(LYLLTHTheme.controlFill) : LYLLTHTheme.deck)
                        .overlay(Rectangle().stroke(selected ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct LYSettingsLabeledChoice<Value: Hashable>: View {
    let label: String
    let choices: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(LYLLTHTheme.label(8.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.metadata)
            LYSettingsChoiceRow(choices: choices, selection: $selection)
        }
    }
}

private struct LYSettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(LYLLTHTheme.label(9.5, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(LYLLTHTheme.text)
                    Text(detail)
                        .font(LYLLTHTheme.body(10.5))
                        .foregroundStyle(LYLLTHTheme.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Text(isOn ? "ON" : "OFF")
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(isOn ? LYLLTHTheme.teal : LYLLTHTheme.metadata)
                    .frame(width: 48, height: 26)
                    .background(isOn ? LYLLTHTheme.teal.opacity(LYLLTHTheme.controlFill) : LYLLTHTheme.deck)
                    .overlay(Rectangle().stroke(isOn ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
                    .lyBloom(LYLLTHTheme.teal, isOn: isOn, strength: 0.45)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct LYSettingsStatusRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(LYLLTHTheme.text)
                Text(detail)
                    .font(LYLLTHTheme.body(10.5))
                    .foregroundStyle(LYLLTHTheme.metadata)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            mixedNumericLabel(value, labelFont: LYLLTHTheme.label(8.5, weight: .bold), numberFont: LYLLTHTheme.value(10))
                .tracking(0.8)
                .foregroundStyle(LYLLTHTheme.teal)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LYSettingsMetric: View {
    let label: String
    let value: String
    var accent = LYLLTHTheme.teal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(LYLLTHTheme.metadata)
            Text(value)
                .font(LYLLTHTheme.value(18))
                .foregroundStyle(accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LYLLTHTheme.deck)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

private struct LYSettingsActionButton: View {
    let title: String
    var accent = LYLLTHTheme.secondary
    let action: () -> Void

    init(_ title: String, accent: Color = LYLLTHTheme.secondary, action: @escaping () -> Void) {
        self.title = title
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LYLLTHTheme.label(8.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .overlay(Rectangle().stroke(accent.opacity(0.72), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
