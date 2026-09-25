import SwiftUI
import AppKit

// MARK: - Live readout

/// Polls the running synth 30 times a second for what the editor animates:
/// modulated wavetable positions, envelope levels, LFO phases, cutoff, scope.
@MainActor
final class LYSynthLive: ObservableObject {
    @Published private(set) var display = LYSynthDisplay()
    @Published private(set) var scope: [Float] = Array(repeating: 0, count: 256)
    private var timer: Timer?
    private weak var instrument: LYSynthInstrument?

    func attach(_ instrument: LYSynthInstrument?) {
        self.instrument = instrument
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func detach() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let instrument else { return }
        display = instrument.display()
        scope = instrument.scope(count: 256)
    }

    func modulation(_ destination: Int) -> Float {
        withUnsafeBytes(of: display.modulation) { raw in
            let values = raw.bindMemory(to: Float.self)
            return destination >= 0 && destination < values.count ? values[destination] : 0
        }
    }

    func envelope(_ index: Int) -> Float {
        [display.envelope.0, display.envelope.1, display.envelope.2][min(max(index, 0), 2)]
    }

    func lfo(_ index: Int) -> (value: Float, phase: Float) {
        let values = [display.lfo.0, display.lfo.1, display.lfo.2, display.lfo.3]
        let phases = [display.lfoPhase.0, display.lfoPhase.1, display.lfoPhase.2, display.lfoPhase.3]
        let i = min(max(index, 0), 3)
        return (values[i], phases[i])
    }
}

/// Factory wavetable frames, reduced for drawing and kept after first use.
enum LYWavetableArt {
    private static var cache: [Int: [[Float]]] = [:]

    /// A library table, reduced the same way. Not cached: the editor can
    /// re-save a table under the name it already has.
    @MainActor
    static func frames(custom name: String) -> [[Float]]? {
        guard let raw = LYWavetableLibrary.shared.frames(named: name) else { return nil }
        let size = LYWavetableLibrary.frameSize
        let count = raw.count / size
        guard count > 0 else { return nil }
        let peak = max(raw.map(abs).max() ?? 0, 0.0001)
        let step = max(1, count / 64)
        return stride(from: 0, to: count, by: step).map { f in
            (0..<96).map { i in raw[f * size + i * size / 96] / peak }
        }
    }

    static func frames(_ table: Int) -> [[Float]] {
        if let cached = cache[table] { return cached }
        var raw = [Float](repeating: 0, count: Int(LY_WT_MAX_FRAMES) * Int(LY_WT_SIZE))
        let count = Int(raw.withUnsafeMutableBufferPointer { lysynth_factory_table(Int32(table), $0.baseAddress, Int32(LY_WT_MAX_FRAMES)) })
        let size = Int(LY_WT_SIZE)
        var peak: Float = 0.0001
        for i in 0..<(count * size) { peak = max(peak, abs(raw[i])) }
        let points = 96
        let result: [[Float]] = (0..<count).map { f in
            (0..<points).map { i in raw[f * size + i * size / points] / peak }
        }
        cache[table] = result
        return result
    }
}

// MARK: - Editor

struct LYSynthEditor: View {
    @Binding var patch: LYSynthPatch
    let trackName: String
    let instrument: LYSynthInstrument?
    /// Copies a custom wavetable into the song so it travels with it.
    var storeTableInProject: (String, [Float]) -> Void = { _, _ in }
    let close: () -> Void

    @StateObject private var live = LYSynthLive()
    @ObservedObject private var tableLibrary = LYWavetableLibrary.shared
    @ObservedObject private var presetStore = LYSynthPresetStore.shared
    @State private var editingTable: Int?
    @State private var savingPreset = false
    @State private var presetDraft = ""
    @State private var presetError: String?
    @State private var anchors: [String: CGRect] = [:]
    @State private var modTab = 0          // 0…2 envelopes, 3…6 LFOs
    @State private var choosingTable: Int?
    @State private var choosingPreset = false
    @State private var heldKeys: Set<Int> = []
    @State private var keyboardOctave = 4

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(alignment: .top, spacing: 8) {
                oscillatorPanel(0).frame(width: 372)
                oscillatorPanel(1).frame(width: 372)
                subNoisePanel.frame(width: 150)
                filterPanel.frame(maxWidth: .infinity)
            }
            .frame(height: 318)
            HStack(alignment: .top, spacing: 8) {
                modulationPanel.frame(width: 540)
                macroPanel.frame(width: 232)
                voicePanel.frame(width: 172)
                matrixPanel.frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            LYSynthKeyboard(
                lowestOctave: keyboardOctave,
                held: heldKeys,
                press: { note in play(note) },
                release: { note in stop(note) }
            )
            .frame(height: 42)
        }
        .coordinateSpace(name: "LYSynthEditor")
        .onPreferenceChange(LYMenuAnchorKey.self) { anchors = $0 }
        .overlay(alignment: .topLeading) {
            if choosingPreset, let frame = anchors["preset"] {
                LYPresetBrowser(
                    current: patch.name,
                    user: presetStore.presets,
                    choose: { patch = $0; choosingPreset = false },
                    delete: { presetStore.delete($0) },
                    close: { choosingPreset = false }
                )
                .frame(width: 420, height: 380)
                .offset(x: min(frame.minX, frame.maxX - 420), y: frame.maxY + 6)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Color(hex: 0x07080D))
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.teal.opacity(0.8)).frame(height: 1) }
        .overlay { wavetableEditorOverlay }
        .overlay { presetSaveOverlay }
        .background(LYSynthKeyMonitor(octave: $keyboardOctave, press: play, release: stop,
                                      close: { if editingTable != nil { editingTable = nil } else { close() } },
                                      isEnabled: editingTable == nil && !savingPreset))
        .onAppear {
            live.attach(instrument)
            #if DEBUG
            // Screenshot hooks.
            let environment = ProcessInfo.processInfo.environment
            if let tab = environment["LYLLTH_DEBUG_MODTAB"].flatMap(Int.init) { modTab = tab }
            if environment["LYLLTH_DEBUG_WTEDIT"] != nil { editingTable = 0 }
            if environment["LYLLTH_DEBUG_PRESETS"] != nil { choosingPreset = true }
            #endif
        }
        .onDisappear {
            live.detach()
            for note in heldKeys { instrument?.noteOff(UInt8(note), atHostTime: 0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Editing

    private func set(_ id: Int, _ value: Float) {
        var next = patch
        next.set(id, value)
        patch = next
    }

    private func toggle(_ id: Int) { set(id, patch.value(id) > 0.5 ? 0 : 1) }

    private func addRoute(_ source: Int, _ destination: Int) {
        var next = patch
        next.route(source: source, destination: destination, amount: 0.3)
        patch = next
    }

    private func knob(_ id: Int, _ destination: Int? = nil, accent: Color, diameter: CGFloat = 34,
                      label: String? = nil, format: ((Float) -> String)? = nil) -> some View {
        LYSynthKnob(
            parameter: id,
            destination: destination,
            patch: patch,
            accent: accent,
            diameter: diameter,
            label: label,
            format: format,
            liveModulation: destination.map { live.modulation($0) } ?? 0,
            update: set,
            addRoute: addRoute
        )
    }

    private func play(_ note: Int) {
        guard !heldKeys.contains(note) else { return }
        heldKeys.insert(note)
        instrument?.noteOn(UInt8(min(max(note, 0), 127)), velocity: 110, atHostTime: 0, cutoff: 1, resonance: 0)
    }

    private func stop(_ note: Int) {
        heldKeys.remove(note)
        instrument?.noteOff(UInt8(min(max(note, 0), 127)), atHostTime: 0)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                Text("LYLLTH").font(LYLLTHTheme.wordmark(24))
                Text(" SYNTH").font(LYLLTHTheme.wordmarkOutline(24))
            }
            .tracking(1.4)
            .fixedSize()
            .hidden()
            .overlay(
                LYSynthTieDye().mask(
                    HStack(spacing: 0) {
                        Text("LYLLTH").font(LYLLTHTheme.wordmark(24))
                        Text(" SYNTH").font(LYLLTHTheme.wordmarkOutline(24))
                    }
                    .tracking(1.4)
                    .fixedSize()
                )
            )

            Text(trackName)
                .font(LYLLTHTheme.label(9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(LYLLTHTheme.dim)

            Spacer(minLength: 8)

            presetBar

            LYSynthScope(live: live)
                .frame(width: 180, height: 38)

            VStack(spacing: 1) {
                Text("\(live.display.activeVoices)")
                    .font(LYLLTHTheme.value(16))
                    .foregroundStyle(LYLLTHTheme.text)
                Text("VOICES")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .frame(width: 44)

            knob(LY_MASTER, accent: LYLLTHTheme.chromeText, diameter: 30, label: "MASTER")


        }
        .frame(height: 56)
    }

    private var presetBar: some View {
        let all = LYSynthPatch.factory + presetStore.presets
        let index = all.firstIndex { $0.name == patch.name } ?? -1
        return HStack(spacing: 0) {
            presetArrow("chevron.left") { if !all.isEmpty { patch = all[(index - 1 + all.count) % all.count] } }
            Button { choosingPreset.toggle() } label: {
                VStack(spacing: 1) {
                    Text(presetStore.presets.contains { $0.name == patch.name } ? "USER PRESET" : "PRESET")
                        .font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1.4).foregroundStyle(LYLLTHTheme.dim)
                    Text(patch.name).font(LYLLTHTheme.label(11, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                }
                .frame(width: 190, height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            presetArrow("chevron.right") { if !all.isEmpty { patch = all[(index + 1) % all.count] } }
            Button {
                presetDraft = patch.name == "INIT" ? "" : patch.name
                presetError = nil
                savingPreset = true
            } label: {
                Text("SAVE")
                    .font(LYLLTHTheme.label(8, weight: .bold)).tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.teal)
                    .frame(width: 44, height: 38)
                    .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save this sound to your presets")
        }
        .overlay(Rectangle().stroke(choosingPreset ? LYLLTHTheme.teal.opacity(0.7) : LYLLTHTheme.lineStrong, lineWidth: 1))
        .lyMenuAnchor("preset", in: "LYSynthEditor")
    }

    private func presetArrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                .frame(width: 26, height: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var presetSaveOverlay: some View {
        if savingPreset {
            ZStack {
                Color.black.opacity(0.6).onTapGesture { savingPreset = false }
                VStack(alignment: .leading, spacing: 12) {
                    Text("SAVE PRESET")
                        .font(LYLLTHTheme.label(11, weight: .bold)).tracking(2).foregroundStyle(LYLLTHTheme.teal)
                    TextField("NAME", text: $presetDraft)
                        .textFieldStyle(.plain)
                        .font(LYLLTHTheme.label(13, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                        .onSubmit(savePreset)
                    if let presetError {
                        Text(presetError).font(LYLLTHTheme.label(8, weight: .bold)).foregroundStyle(LYLLTHTheme.record)
                    }
                    Text("SAVED TO ~/LIBRARY/APPLICATION SUPPORT/LYLLTH/PRESETS WITH ANY CUSTOM WAVETABLES IT USES")
                        .font(LYLLTHTheme.label(7, weight: .bold)).tracking(0.8).foregroundStyle(LYLLTHTheme.dim)
                    HStack {
                        Spacer()
                        Button("CANCEL") { savingPreset = false }.buttonStyle(LYChromeButtonStyle(compact: true))
                        Button("SAVE", action: savePreset).buttonStyle(LYChromeButtonStyle(active: true, compact: true))
                            .disabled(presetDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(18)
                .frame(width: 420)
                .background(Color(hex: 0x07080D))
                .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.7), lineWidth: 1))
            }
        }
    }

    private func savePreset() {
        let name = presetDraft.trimmingCharacters(in: .whitespaces).uppercased()
        guard !name.isEmpty else { return }
        guard !LYSynthPatch.factory.contains(where: { $0.name == name }) else {
            presetError = "THAT NAME BELONGS TO A FACTORY SOUND"
            return
        }
        do {
            try presetStore.save(patch, as: name)
            var renamed = patch
            renamed.name = name
            patch = renamed
            savingPreset = false
        } catch {
            presetError = error.localizedDescription.uppercased()
        }
    }

    // MARK: Wavetables

    private func chooseFactoryTable(_ oscillator: Int, _ index: Int) {
        var next = patch
        if oscillator == 0 { next.tableA = index; next.customTableA = nil } else { next.tableB = index; next.customTableB = nil }
        patch = next
    }

    private func chooseCustomTable(_ oscillator: Int, _ name: String) {
        if let frames = tableLibrary.frames(named: name) { storeTableInProject(name, frames) }
        var next = patch
        if oscillator == 0 { next.customTableA = name } else { next.customTableB = name }
        patch = next
    }

    private func importTable(_ oscillator: Int) {
        let panel = NSOpenPanel()
        panel.title = "IMPORT WAVETABLE"
        panel.message = "A Serum-format wavetable, a single cycle, or any audio: audio becomes 64 frames."
        panel.allowedContentTypes = [.audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let frames = try LYWavetableLibrary.importFrames(from: url)
            let name = tableLibrary.store(frames, named: url.deletingPathExtension().lastPathComponent)
            chooseCustomTable(oscillator, name)
        } catch {
            NSSound.beep()
        }
    }

    private func frames(for oscillator: Int) -> [Float] {
        let custom = oscillator == 0 ? patch.customTableA : patch.customTableB
        if let custom, let frames = tableLibrary.frames(named: custom) { return frames }
        return LYWavetableLibrary.factoryFrames(oscillator == 0 ? patch.tableA : patch.tableB)
    }

    @ViewBuilder
    private var wavetableEditorOverlay: some View {
        if let oscillator = editingTable {
            ZStack {
                Color.black.opacity(0.65)
                LYWavetableEditor(
                    accent: oscillator == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo,
                    initialName: (oscillator == 0 ? patch.customTableA : patch.customTableB) ?? (patch.tableName(oscillator) + " EDIT"),
                    initialFrames: frames(for: oscillator),
                    save: { name, frames in
                        let stored = tableLibrary.store(frames, named: name)
                        storeTableInProject(stored, frames)
                        var next = patch
                        if oscillator == 0 { next.customTableA = stored } else { next.customTableB = stored }
                        instrument?.forgetTables()
                        patch = next
                        editingTable = nil
                    },
                    cancel: { editingTable = nil }
                )
                .padding(24)
            }
        }
    }

    // MARK: Oscillators
    // MARK: Oscillators

    private func oscillatorPanel(_ o: Int) -> some View {
        let accent = o == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo
        let p = { (local: Int) in LYSynthParameters.oscillator(o, local) }
        let d = { (aDestination: Int) in o == 0 ? aDestination : aDestination + (LY_DST_B_LEVEL - LY_DST_A_LEVEL) }
        let table = o == 0 ? patch.tableA : patch.tableB
        let warpNames = o == 0 ? LYSynthNames.warps : LYSynthNames.warpsB
        let warpMode = Int(patch.value(p(LY_OSC_WARPMODE)))

        return LYSynthPanel(title: o == 0 ? "OSC A" : "OSC B", accent: accent, isOn: patch.value(p(LY_OSC_ON)) > 0.5,
                            toggle: { toggle(p(LY_OSC_ON)) }) {
            HStack(spacing: 4) {
                LYSynthStepper(label: "OCT", text: String(format: "%+d", Int(patch.value(p(LY_OSC_OCTAVE)))), accent: accent) {
                    set(p(LY_OSC_OCTAVE), patch.value(p(LY_OSC_OCTAVE)) + Float($0))
                }
                LYSynthStepper(label: "SEMI", text: String(format: "%+d", Int(patch.value(p(LY_OSC_SEMI)))), accent: accent) {
                    set(p(LY_OSC_SEMI), patch.value(p(LY_OSC_SEMI)) + Float($0))
                }
            }
        } content: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    Button { choosingTable = choosingTable == o ? nil : o } label: {
                        LYWavetableView(table: table, customName: o == 0 ? patch.customTableA : patch.customTableB,
                                        oscillator: o, basePosition: patch.value(p(LY_OSC_WTPOS)),
                                        accent: accent, live: live)
                            .overlay(alignment: .topLeading) {
                                HStack(spacing: 5) {
                                    Text(patch.tableName(o))
                                        .font(LYLLTHTheme.label(8.5, weight: .bold)).tracking(1.2)
                                    Image(systemName: "chevron.down").font(.system(size: 6.5, weight: .bold))
                                }
                                .foregroundStyle(LYLLTHTheme.text)
                                .padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Choose a wavetable")
                    if choosingTable == o {
                        LYTableBrowser(
                            accent: accent,
                            current: patch.tableName(o),
                            user: tableLibrary.names,
                            chooseFactory: { chooseFactoryTable(o, $0) },
                            chooseUser: { chooseCustomTable(o, $0) },
                            importTable: { choosingTable = nil; importTable(o) },
                            editTable: { choosingTable = nil; editingTable = o },
                            close: { choosingTable = nil }
                        )
                    }
                }
                .frame(height: 138)

                HStack(alignment: .top, spacing: 0) {
                    group("TABLE") {
                        HStack(alignment: .top, spacing: 6) {
                            knob(p(LY_OSC_WTPOS), d(LY_DST_A_WTPOS), accent: accent, diameter: 44, label: "WT POS")
                            VStack(spacing: 6) {
                                LYSynthStepper(label: "WARP", text: warpNames[min(max(warpMode, 0), warpNames.count - 1)], accent: accent) { step in
                                    let count = Float(LY_WARP_COUNT)
                                    set(p(LY_OSC_WARPMODE), (patch.value(p(LY_OSC_WARPMODE)) + Float(step) + count).truncatingRemainder(dividingBy: count))
                                }
                                .frame(width: 92)
                                HStack(spacing: 0) {
                                    knob(p(LY_OSC_WARPAMT), d(LY_DST_A_WARP), accent: accent, diameter: 24, label: "AMOUNT")
                                    knob(p(LY_OSC_RANDPHASE), accent: accent, diameter: 24, label: "RAND")
                                }
                            }
                        }
                    }
                    groupDivider
                    group("UNISON") {
                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                knob(p(LY_OSC_UNISON), accent: accent, diameter: 26, label: "VOICES")
                                knob(p(LY_OSC_DETUNE), d(LY_DST_A_DETUNE), accent: accent, diameter: 26)
                            }
                            HStack(spacing: 2) {
                                knob(p(LY_OSC_BLEND), d(LY_DST_A_BLEND), accent: accent, diameter: 26)
                                knob(p(LY_OSC_WIDTH), accent: accent, diameter: 26)
                            }
                        }
                    }
                    groupDivider
                    group("OUTPUT") {
                        VStack(spacing: 4) {
                            HStack(spacing: 2) {
                                knob(p(LY_OSC_LEVEL), d(LY_DST_A_LEVEL), accent: accent, diameter: 26)
                                knob(p(LY_OSC_PAN), d(LY_DST_A_PAN), accent: accent, diameter: 26, format: panText)
                            }
                            HStack(spacing: 2) {
                                knob(p(LY_OSC_FINE), accent: accent, diameter: 26, label: "FINE", format: { String(format: "%+.0f¢", $0) })
                                knob(p(LY_OSC_PHASE), accent: accent, diameter: 26, label: "PHASE", format: { String(format: "%.0f°", $0 * 360) })
                            }
                        }
                    }
                }
            }
        }
        .zIndex(choosingTable == o ? 10 : 0)
    }

    // MARK: Sub and noise

    private var subNoisePanel: some View {
        VStack(spacing: 8) {
            LYSynthPanel(title: "SUB", accent: LYLLTHTheme.purple, isOn: patch.value(LY_SUB_ON) > 0.5, toggle: { toggle(LY_SUB_ON) }) {
                VStack(spacing: 8) {
                    LYSynthStepper(label: "SHAPE", text: LYSynthNames.subShapes[min(max(Int(patch.value(LY_SUB_SHAPE)), 0), 2)], accent: LYLLTHTheme.purple) { step in
                        set(LY_SUB_SHAPE, Float((Int(patch.value(LY_SUB_SHAPE)) + step + 3) % 3))
                    }
                    HStack(spacing: 6) {
                        LYSynthStepper(label: "OCT", text: "−\(Int(patch.value(LY_SUB_OCTAVE)))", accent: LYLLTHTheme.purple) { step in
                            set(LY_SUB_OCTAVE, patch.value(LY_SUB_OCTAVE) + Float(step))
                        }
                    }
                    knob(LY_SUB_LEVEL, LY_DST_SUB_LEVEL, accent: LYLLTHTheme.purple)
                }
            }
            LYSynthPanel(title: "NOISE", accent: LYLLTHTheme.purple, isOn: patch.value(LY_NOISE_ON) > 0.5, toggle: { toggle(LY_NOISE_ON) }) {
                HStack(spacing: 4) {
                    knob(LY_NOISE_COLOR, accent: LYLLTHTheme.purple, diameter: 30)
                    knob(LY_NOISE_LEVEL, LY_DST_NOISE_LEVEL, accent: LYLLTHTheme.purple, diameter: 30)
                }
            }
        }
    }

    // MARK: Filter

    private var filterPanel: some View {
        let accent = LYLLTHTheme.teal
        return LYSynthPanel(title: "FILTER", accent: accent, isOn: patch.value(LY_FILTER_ON) > 0.5, toggle: { toggle(LY_FILTER_ON) }) {
            HStack(spacing: 3) {
                ForEach([("A", LY_FILTER_ROUTE_A), ("B", LY_FILTER_ROUTE_B), ("S", LY_FILTER_ROUTE_SUB), ("N", LY_FILTER_ROUTE_NOISE)], id: \.1) { item in
                    LYSynthToggle(title: item.0, isOn: patch.value(item.1) > 0.5, accent: accent) { toggle(item.1) }
                        .help("Send \(item.0 == "S" ? "SUB" : item.0 == "N" ? "NOISE" : "OSC " + item.0) through the filter")
                }
            }
        } content: {
            VStack(spacing: 8) {
                FXSegmentedRow(options: LYSynthNames.filters, selected: Int(patch.value(LY_FILTER_TYPE)), accent: accent, height: 22) { index in
                    set(LY_FILTER_TYPE, Float(index))
                }
                LYFilterCurve(patch: patch, live: live, accent: accent)
                    .frame(height: 118)
                HStack(spacing: 0) {
                    knob(LY_FILTER_CUTOFF, LY_DST_CUTOFF, accent: accent, diameter: 46, format: { value in
                        let hz = 20 * pow(1000, value)
                        return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
                    })
                    Spacer(minLength: 0)
                    knob(LY_FILTER_RES, LY_DST_RES, accent: accent, diameter: 40)
                    Spacer(minLength: 0)
                    knob(LY_FILTER_DRIVE, LY_DST_DRIVE, accent: accent)
                    Spacer(minLength: 0)
                    knob(LY_FILTER_ENVAMT, accent: LYLLTHTheme.indigo, label: "ENV 2")
                    Spacer(minLength: 0)
                    knob(LY_FILTER_KEYTRACK, accent: accent, label: "KEY")
                    Spacer(minLength: 0)
                    knob(LY_FILTER_MIX, LY_DST_FILTER_MIX, accent: accent)
                }
            }
        }
    }

    // MARK: Modulation

    private var modulationPanel: some View {
        let sources = [LY_SRC_ENV1, LY_SRC_ENV2, LY_SRC_ENV3, LY_SRC_LFO1, LY_SRC_LFO2, LY_SRC_LFO3, LY_SRC_LFO4]
        let names = ["ENV 1", "ENV 2", "ENV 3", "LFO 1", "LFO 2", "LFO 3", "LFO 4"]
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    let color = LYSynthSourceColor.color(sources[index])
                    let isOn = modTab == index
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(color)
                            .help("Drag onto any knob to modulate it")
                        Text(names[index])
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(isOn ? color : LYLLTHTheme.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(color.opacity(isOn ? 0.1 : 0))
                    .overlay(alignment: .bottom) { Rectangle().fill(isOn ? color : .clear).frame(height: 2) }
                    .contentShape(Rectangle())
                    .onTapGesture { modTab = index }
                    .draggable("\(LYSynthSourceColor.dragPrefix)\(sources[index])") {
                        Text(names[index])
                            .font(LYLLTHTheme.label(10, weight: .bold))
                            .foregroundStyle(color)
                            .padding(6)
                            .background(Color.black)
                            .overlay(Rectangle().stroke(color, lineWidth: 1))
                    }
                }
            }
            .background(LYLLTHTheme.deck)
            .overlay(alignment: .bottom) { LYHairline() }

            Group {
                if modTab < 3 {
                    envelopeEditor(modTab)
                } else {
                    lfoEditor(modTab - 3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func envelopeEditor(_ e: Int) -> some View {
        let color = LYSynthSourceColor.color(LY_SRC_ENV1 + e)
        let base = LY_ENV1_A + e * 4
        let time = { (value: Float) -> String in
            let seconds = 0.0005 * pow(20_000, Double(value))
            return seconds < 1 ? String(format: "%.0f MS", seconds * 1000) : String(format: "%.2f S", seconds)
        }
        return VStack(spacing: 8) {
            LYEnvelopeGraph(
                attack: patch.value(base), decay: patch.value(base + 1),
                sustain: patch.value(base + 2), release: patch.value(base + 3),
                curves: (0..<3).map { patch.value(LY_ENV1_ACURVE + e * 3 + $0) },
                color: color, level: live.envelope(e),
                set: { index, value in set(base + index, value) },
                setCurve: { index, value in set(LY_ENV1_ACURVE + e * 3 + index, value) }
            )
            HStack(alignment: .bottom, spacing: 0) {
                knob(base, accent: color, diameter: 30, label: "ATTACK", format: time)
                Spacer(minLength: 0)
                knob(base + 1, accent: color, diameter: 30, label: "DECAY", format: time)
                Spacer(minLength: 0)
                knob(base + 2, accent: color, diameter: 30, label: "SUSTAIN")
                Spacer(minLength: 0)
                knob(base + 3, accent: color, diameter: 30, label: "RELEASE", format: time)
                Spacer(minLength: 0)
                Text(e == 0 ? "SHAPES THE VOLUME" : (e == 1 ? "ALSO FILTER ENV" : "ROUTE ANYWHERE") + "\n◆ DRAG TO CURVE")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(1)
                    .lineSpacing(3)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .padding(.bottom, 4)
            }
        }
    }

    private func lfoEditor(_ l: Int) -> some View {
        let color = LYSynthSourceColor.color(LY_SRC_LFO1 + l)
        let base = LY_LFO1_SHAPE + l * 4
        let synced = patch.value(base + 2) > 0.5
        let pointsBase = LY_LFO_POINTS_BASE + l * Int(LY_LFO_POINTS)
        return VStack(spacing: 8) {
            LYLFOGraph(
                shape: Int(patch.value(base)),
                points: (0..<Int(LY_LFO_POINTS)).map { patch.value(pointsBase + $0) },
                smooth: patch.value(LY_LFO1_SMOOTH + l) > 0.5,
                color: color, live: live, index: l,
                paint: { i, value in set(pointsBase + i, value) }
            )
            HStack(alignment: .center, spacing: 10) {
                LYSynthStepper(label: "SHAPE", text: LYSynthNames.lfoShapes[min(max(Int(patch.value(base)), 0), LYSynthNames.lfoShapes.count - 1)], accent: color) { step in
                    let count = LYSynthNames.lfoShapes.count
                    let old = Int(patch.value(base))
                    let new = (old + step + count) % count
                    var next = patch
                    // Entering DRAW starts from the shape you were on.
                    if new == LY_LFO_CUSTOM && old != LY_LFO_CUSTOM {
                        for i in 0..<Int(LY_LFO_POINTS) {
                            let p = Double(i) / Double(LY_LFO_POINTS)
                            next.set(pointsBase + i, Float(LYLFOGraph.value(shape: old, at: p, points: [], smooth: true)))
                        }
                    }
                    next.set(base, Float(new))
                    patch = next
                }
                .frame(width: 110)
                knob(base + 1, LY_DST_LFO1_RATE + l, accent: color, diameter: 30, label: "RATE", format: { value in
                    if synced {
                        let index = Int((value * Float(LYSynthNames.syncDivisions.count - 1)).rounded())
                        return LYSynthNames.syncDivisions[min(max(index, 0), LYSynthNames.syncDivisions.count - 1)]
                    }
                    let hz = 0.02 * pow(1500, Double(value))
                    return hz < 1 ? String(format: "%.2f HZ", hz) : String(format: "%.1f HZ", hz)
                })
                Spacer(minLength: 0)
                LYSynthToggle(title: "SYNC", isOn: synced, accent: color) { toggle(base + 2) }
                LYSynthToggle(title: "RETRIG", isOn: patch.value(base + 3) > 0.5, accent: color) { toggle(base + 3) }
                if Int(patch.value(base)) == LY_LFO_CUSTOM {
                    LYSynthToggle(title: "SMOOTH", isOn: patch.value(LY_LFO1_SMOOTH + l) > 0.5, accent: color) { toggle(LY_LFO1_SMOOTH + l) }
                }
            }
        }
    }

    // MARK: Macros and voice

    private var macroPanel: some View {
        LYSynthPanel(title: "MACROS", accent: LYLLTHTheme.chromeText) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<4, id: \.self) { m in
                    let source = LY_SRC_MACRO1 + m
                    let color = LYSynthSourceColor.color(source)
                    knob(LY_MACRO1 + m, accent: color, diameter: 44, label: "MACRO \(m + 1)")
                        .overlay(alignment: .topTrailing) { dragHandle(source, color: color, help: "Drag onto a knob to put it on MACRO \(m + 1)") }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var voicePanel: some View {
        LYSynthPanel(title: "VOICE", accent: LYLLTHTheme.indigo) {
            VStack(spacing: 8) {
                LYSynthStepper(label: "VOICES", text: Int(patch.value(LY_VOICES)) == 1 ? "MONO" : "\(Int(patch.value(LY_VOICES)))", accent: LYLLTHTheme.indigo) { step in
                    set(LY_VOICES, patch.value(LY_VOICES) + Float(step))
                }
                .frame(maxWidth: .infinity)
                LYSynthStepper(label: "BEND", text: "±\(Int(patch.value(LY_BEND_RANGE)))", accent: LYLLTHTheme.indigo) { step in
                    set(LY_BEND_RANGE, patch.value(LY_BEND_RANGE) + Float(step))
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    LYSynthToggle(title: "LEGATO", isOn: patch.value(LY_LEGATO) > 0.5, accent: LYLLTHTheme.indigo) { toggle(LY_LEGATO) }
                    LYSynthToggle(title: "MPE", isOn: patch.value(LY_MPE) > 0.5, accent: LYLLTHTheme.indigo) { toggle(LY_MPE) }
                        .help("MPE: each note's own channel carries its pitch bend (±48), pressure and timbre (CC 74). Route PRESSURE and TIMBRE in the matrix.")
                }
                HStack(spacing: 2) {
                    knob(LY_GLIDE, accent: LYLLTHTheme.indigo, diameter: 28, format: { String(format: "%.0f MS", $0 * 1000) })
                    knob(LY_MODWHEEL, accent: LYLLTHTheme.chromeText, diameter: 28, label: "MOD")
                        .overlay(alignment: .topTrailing) { dragHandle(LY_SRC_MODWHEEL, color: LYLLTHTheme.chromeText, help: "Drag onto a knob to put it on the mod wheel") }
                }
            }
        }
    }

    private func dragHandle(_ source: Int, color: Color, help: String) -> some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .draggable("\(LYSynthSourceColor.dragPrefix)\(source)")
            .help(help)
    }

    // MARK: Matrix

    private var matrixPanel: some View {
        let used = (0..<Int(LY_MATRIX_SLOTS)).filter { slot in
            let base = LY_MATRIX_BASE + slot * 3
            return Int(patch.value(base)) != LY_SRC_NONE || Int(patch.value(base + 1)) != LY_DST_NONE
        }
        return LYSynthPanel(title: "MATRIX", accent: LYLLTHTheme.indigo) {
            Text("\(used.count) / \(LY_MATRIX_SLOTS)")
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.dim)
        } content: {
            ScrollView {
                VStack(spacing: 4) {
                    if used.isEmpty {
                        Text("DRAG AN ENV, LFO OR MACRO ONTO ANY KNOB\nOR ADD A ROUTE HERE")
                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                            .tracking(1.1)
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(LYLLTHTheme.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    ForEach(used, id: \.self) { slot in
                        LYMatrixRow(slot: slot, patch: patch, update: set, clear: {
                            let base = LY_MATRIX_BASE + slot * 3
                            var next = patch
                            next.set(base, 0); next.set(base + 1, 0); next.set(base + 2, 0)
                            patch = next
                        })
                    }
                    Button {
                        addRoute(LY_SRC_LFO1, LY_DST_CUTOFF)
                    } label: {
                        Text("+ ADD ROUTE")
                            .font(LYLLTHTheme.label(8, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(LYLLTHTheme.chromeText)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(used.count >= Int(LY_MATRIX_SLOTS))
                }
            }
            .lyScrollers()
        }
    }

    /// A labelled cluster of controls inside a panel.
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(LYLLTHTheme.label(6.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(LYLLTHTheme.dim)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private var groupDivider: some View {
        Rectangle().fill(LYLLTHTheme.line).frame(width: 1).padding(.vertical, 4)
    }

    private func panText(_ value: Float) -> String {
        abs(value) < 0.01 ? "C" : (value < 0 ? "L\(Int(abs(value) * 100))" : "R\(Int(value * 100))")
    }
}

// MARK: - Displays

private struct LYSynthTieDye: View {
    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * 0.6
            ZStack {
                LYLLTHTheme.indigo
                ForEach(Array([(0.06, 0.40, LYLLTHTheme.teal), (0.28, 0.85, LYLLTHTheme.purple), (0.48, 0.12, LYLLTHTheme.indigo),
                               (0.70, 0.68, LYLLTHTheme.teal), (0.90, 0.28, LYLLTHTheme.purple)].enumerated()), id: \.offset) { _, spot in
                    RadialGradient(colors: [spot.2, spot.2.opacity(0)], center: UnitPoint(x: spot.0, y: spot.1), startRadius: 0, endRadius: r)
                }
            }
            .drawingGroup()
        }
    }
}

/// The wavetable as a stack of frames receding in depth, the frame being
/// played lit in the oscillator's colour and following modulation live.
struct LYWavetableView: View {
    let table: Int
    var customName: String? = nil
    let oscillator: Int
    let basePosition: Float
    let accent: Color
    @ObservedObject var live: LYSynthLive

    var body: some View {
        Canvas { context, size in
            let frames = customName.flatMap { LYWavetableArt.frames(custom: $0) } ?? LYWavetableArt.frames(table)
            guard !frames.isEmpty else { return }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
            let livePosition: Float = {
                let modulated = oscillator == 0 ? live.display.wavetablePosition.0 : live.display.wavetablePosition.1
                return live.display.activeVoices > 0 ? modulated : basePosition
            }()
            let layers = min(frames.count, 28)
            let depthX = size.width * 0.18, depthY = size.height * 0.36
            let plotW = size.width - depthX - 16, plotH = size.height * 0.34
            let current = Int((livePosition * Float(frames.count - 1)).rounded())
            for layer in stride(from: layers - 1, through: 0, by: -1) {
                let fraction = layers > 1 ? Double(layer) / Double(layers - 1) : 0
                let frameIndex = Int((fraction * Double(frames.count - 1)).rounded())
                let ox = 8 + depthX * (1 - fraction), oy = size.height - 10 - plotH / 2 - depthY * (1 - fraction)
                var path = Path()
                for (i, sample) in frames[frameIndex].enumerated() {
                    let point = CGPoint(x: ox + plotW * CGFloat(i) / CGFloat(frames[frameIndex].count - 1), y: oy - CGFloat(sample) * plotH / 2)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                let near = abs(frameIndex - current) <= max(1, frames.count / layers / 2)
                context.stroke(path, with: .color(near ? accent.opacity(0.35) : Color.white.opacity(0.07 + 0.08 * fraction)), lineWidth: near ? 1.2 : 0.8)
            }
            // The frame actually playing, drawn in front.
            let frame = frames[min(max(current, 0), frames.count - 1)]
            let t = Double(livePosition)
            let ox = 8 + depthX * (1 - t), oy = size.height - 10 - plotH / 2 - depthY * (1 - t)
            var path = Path()
            var fill = Path()
            fill.move(to: CGPoint(x: ox, y: oy))
            for (i, sample) in frame.enumerated() {
                let point = CGPoint(x: ox + plotW * CGFloat(i) / CGFloat(frame.count - 1), y: oy - CGFloat(sample) * plotH / 2)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                fill.addLine(to: point)
            }
            fill.addLine(to: CGPoint(x: ox + plotW, y: oy))
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.12)))
            var glow = context
            glow.addFilter(.shadow(color: accent.opacity(0.8), radius: 4))
            glow.stroke(path, with: .color(accent), lineWidth: 1.8)
            context.draw(Text(String(format: "%d / %d", current + 1, frames.count)).font(LYLLTHTheme.value(8)).foregroundColor(LYLLTHTheme.dim),
                         at: CGPoint(x: size.width - 26, y: 12))
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

/// The filter's response, drawn from the same analogue prototypes the core
/// discretises, at the live modulated cutoff.
struct LYFilterCurve: View {
    let patch: LYSynthPatch
    @ObservedObject var live: LYSynthLive
    let accent: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
            for decade in [100.0, 1_000.0, 10_000.0] {
                let x = size.width * CGFloat(log10(decade / 20) / 3)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.05)))
            }
            let type = Int(patch.value(LY_FILTER_TYPE))
            let res = Double(patch.value(LY_FILTER_RES))
            let base = 20 * pow(1000, Double(patch.value(LY_FILTER_CUTOFF)))
            let cutoff = live.display.activeVoices > 0 && live.display.cutoffHz > 0 ? Double(live.display.cutoffHz) : base
            let k = 2 - 1.97 * res
            let k2 = 2 - 1.2 * res
            func magnitude(_ hz: Double) -> Double {
                let w = hz / cutoff
                let w2 = w * w
                func den(_ kk: Double) -> Double { sqrt(pow(1 - w2, 2) + pow(w * kk, 2)) }
                switch type {
                case LY_FILTER_LP12: return 1 / den(k)
                case LY_FILTER_LP24: return (1 / den(k)) * (1 / den(k2))
                case LY_FILTER_HP12: return w2 / den(k)
                case LY_FILTER_HP24: return (w2 / den(k)) * (w2 / den(k2))
                case LY_FILTER_BP: return (w * k) / den(k)
                case LY_FILTER_NOTCH: return abs(1 - w2) / den(k)
                default:
                    // Ladder: four poles, resonance peaking at cutoff.
                    return (1 / den(2 - 1.95 * res)) * (1 / den(2))
                }
            }
            var path = Path()
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            let steps = Int(size.width)
            for x in 0...steps {
                let hz = 20 * pow(1000, Double(x) / Double(steps))
                let dB = 20 * log10(max(magnitude(hz), 0.00001))
                let y = size.height * 0.45 - CGFloat(dB / 30) * size.height * 0.45
                let point = CGPoint(x: CGFloat(x), y: min(max(y, 2), size.height))
                if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                fill.addLine(to: point)
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.1)))
            context.stroke(path, with: .color(accent), lineWidth: 1.5)
            let cx = size.width * CGFloat(log10(cutoff / 20) / 3)
            context.fill(Path(CGRect(x: cx, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.3)))
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .opacity(patch.value(LY_FILTER_ON) > 0.5 ? 1 : 0.4)
    }
}

/// ADSR you can drag directly: attack and decay by their corners, sustain by
/// its height, release by its end, and each stage's curve by the handle at
/// its middle. A line tracks the level while notes play.
struct LYEnvelopeGraph: View {
    let attack: Float, decay: Float, sustain: Float, release: Float
    let curves: [Float]            // attack, decay, release
    let color: Color
    let level: Float
    let set: (Int, Float) -> Void
    let setCurve: (Int, Float) -> Void
    @State private var curveOrigin: Float?

    private func shape(_ p: Double, _ curve: Float) -> Double {
        if abs(curve) < 0.01 { return p }
        let k = Double(curve) * 5
        return (exp(k * p) - 1) / (exp(k) - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let slot = size.width / 4
            let top: CGFloat = 8, bottom = size.height - 8
            let height = bottom - top
            let a = CGPoint(x: slot * CGFloat(0.1 + 0.9 * attack), y: top)
            let d = CGPoint(x: a.x + slot * CGFloat(0.1 + 0.9 * decay), y: bottom - height * CGFloat(sustain))
            let s = CGPoint(x: d.x + slot * 0.8, y: d.y)
            let r = CGPoint(x: s.x + slot * CGFloat(0.1 + 0.9 * release), y: bottom)
            let attackMid = CGPoint(x: a.x / 2, y: bottom - height * CGFloat(shape(0.5, curves[0])))
            let decayMid = CGPoint(x: (a.x + d.x) / 2, y: bottom - height * CGFloat(Double(sustain) + (1 - Double(sustain)) * (1 - shape(0.5, curves[1]))))
            let releaseMid = CGPoint(x: (s.x + r.x) / 2, y: bottom - height * CGFloat(Double(sustain) * (1 - shape(0.5, curves[2]))))
            ZStack {
                Canvas { context, _ in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: bottom))
                    for i in 1...24 {
                        let p = Double(i) / 24
                        path.addLine(to: CGPoint(x: a.x * CGFloat(p), y: bottom - height * CGFloat(shape(p, curves[0]))))
                    }
                    for i in 1...24 {
                        let p = Double(i) / 24
                        let v = Double(sustain) + (1 - Double(sustain)) * (1 - shape(p, curves[1]))
                        path.addLine(to: CGPoint(x: a.x + (d.x - a.x) * CGFloat(p), y: bottom - height * CGFloat(v)))
                    }
                    path.addLine(to: s)
                    for i in 1...24 {
                        let p = Double(i) / 24
                        let v = Double(sustain) * (1 - shape(p, curves[2]))
                        path.addLine(to: CGPoint(x: s.x + (r.x - s.x) * CGFloat(p), y: bottom - height * CGFloat(v)))
                    }
                    var fill = path
                    fill.addLine(to: CGPoint(x: 0, y: bottom))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(color.opacity(0.12)))
                    context.stroke(path, with: .color(color), lineWidth: 1.6)
                    if level > 0.001 {
                        let y = bottom - height * CGFloat(level)
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color.opacity(0.35)))
                    }
                }
                ForEach(Array([a, d, r].enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.black)
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    switch index {
                                    case 0: set(0, clamp(Float((drag.location.x / slot - 0.1) / 0.9)))
                                    case 1:
                                        set(1, clamp(Float(((drag.location.x - a.x) / slot - 0.1) / 0.9)))
                                        set(2, clamp(Float((bottom - drag.location.y) / height)))
                                    default: set(3, clamp(Float(((drag.location.x - s.x) / slot - 0.1) / 0.9)))
                                    }
                                }
                        )
                }
                ForEach(Array([attackMid, decayMid, releaseMid].enumerated()), id: \.offset) { index, point in
                    Rectangle()
                        .fill(color.opacity(0.9))
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(45))
                        .position(point)
                        .contentShape(Rectangle().inset(by: -6))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let origin = curveOrigin ?? curves[index]
                                    if curveOrigin == nil { curveOrigin = origin }
                                    // Dragging up bows the stage upward whichever way it runs.
                                    let direction: Float = index == 0 ? -1 : 1
                                    setCurve(index, min(max(origin + direction * Float(drag.translation.height / 60), -1), 1))
                                }
                                .onEnded { _ in curveOrigin = nil }
                        )
                        .onTapGesture(count: 2) { setCurve(index, index == 0 ? 0 : -0.55) }
                        .help("Drag to bend this stage. Double-click to reset.")
                }
            }
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func clamp(_ value: Float) -> Float { min(max(value, 0), 1) }
}

/// The LFO's shape with a playhead. In DRAW the shape is 32 points you paint
/// with the pointer.
struct LYLFOGraph: View {
    let shape: Int
    let points: [Float]
    let smooth: Bool
    let color: Color
    @ObservedObject var live: LYSynthLive
    let index: Int
    let paint: (Int, Float) -> Void

    static func value(shape: Int, at p: Double, points: [Float], smooth: Bool) -> Double {
        switch shape {
        case LY_LFO_SINE: return sin(p * 2 * .pi)
        case LY_LFO_TRIANGLE: return 1 - 4 * abs(p - 0.5)
        case LY_LFO_SAW_UP: return 2 * p - 1
        case LY_LFO_SAW_DOWN: return 1 - 2 * p
        case LY_LFO_SQUARE: return p < 0.5 ? 1 : -1
        case LY_LFO_SAMPLE_HOLD: return [0.6, -0.3, 0.9, -0.8, 0.2, -0.5, 0.7, -0.1][min(7, Int(p * 8))]
        case LY_LFO_CUSTOM:
            guard !points.isEmpty else { return 0 }
            let position = p * Double(points.count)
            let i = min(Int(position), points.count - 1)
            if !smooth { return Double(points[i]) }
            let t = position - Double(i)
            let eased = 0.5 - 0.5 * cos(.pi * t)
            return Double(points[i]) + Double(points[(i + 1) % points.count] - points[i]) * eased
        default: return sin(p * 2 * .pi * 1.5) * 0.7 + sin(p * 2 * .pi * 0.5) * 0.3
        }
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
                let mid = size.height / 2
                context.fill(Path(CGRect(x: 0, y: mid, width: size.width, height: 1)), with: .color(Color.white.opacity(0.06)))
                if shape == LY_LFO_CUSTOM {
                    for i in 0..<points.count {
                        let x = size.width * CGFloat(i) / CGFloat(points.count)
                        context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.04)))
                    }
                }
                var path = Path()
                let steps = Int(size.width)
                for x in 0...steps {
                    let p = min(Double(x) / Double(steps), 0.9999)
                    let point = CGPoint(x: CGFloat(x), y: mid - CGFloat(Self.value(shape: shape, at: p, points: points, smooth: smooth)) * (mid - 8))
                    if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.6)
                let state = live.lfo(index)
                let x = CGFloat(state.phase) * size.width
                let y = mid - CGFloat(state.value) * (mid - 8)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(color.opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(LYLLTHTheme.text))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard shape == LY_LFO_CUSTOM, !points.isEmpty else { return }
                        let i = min(max(Int(drag.location.x / geo.size.width * CGFloat(points.count)), 0), points.count - 1)
                        let mid = geo.size.height / 2
                        paint(i, Float(min(max((mid - drag.location.y) / (mid - 8), -1), 1)))
                    }
            )
            .overlay(alignment: .topLeading) {
                if shape == LY_LFO_CUSTOM {
                    Text("DRAW").font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1.4).foregroundStyle(color).padding(6)
                }
            }
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

struct LYSynthScope: View {
    @ObservedObject var live: LYSynthLive

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.6)))
            let samples = live.scope
            guard samples.count > 1 else { return }
            var path = Path()
            for (i, sample) in samples.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(samples.count - 1),
                                    y: size.height / 2 - CGFloat(max(-1, min(1, sample))) * size.height * 0.45)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(LYLLTHTheme.teal), lineWidth: 1.2)
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

private struct LYMatrixRow: View {
    let slot: Int
    let patch: LYSynthPatch
    let update: (Int, Float) -> Void
    let clear: () -> Void
    @State private var origin: Float?

    var body: some View {
        let base = LY_MATRIX_BASE + slot * 3
        let source = Int(patch.value(base))
        let destination = Int(patch.value(base + 1))
        let amount = patch.value(base + 2)
        let color = LYSynthSourceColor.color(source)
        return HStack(spacing: 6) {
            cycler(LYSynthNames.sources[min(max(source, 0), LYSynthNames.sources.count - 1)], color: color) { step in
                let count = LYSynthNames.sources.count
                update(base, Float((source + step + count) % count))
            }
            .frame(width: 104)
            Image(systemName: "arrow.right").font(.system(size: 7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
            cycler(LYSynthNames.destinations[min(max(destination, 0), LYSynthNames.destinations.count - 1)], color: LYLLTHTheme.text) { step in
                let count = LYSynthNames.destinations.count
                update(base + 1, Float((destination + step + count) % count))
            }
            .frame(width: 112)
            GeometryReader { geo in
                let mid = geo.size.width / 2
                ZStack(alignment: .leading) {
                    Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 2)
                    Rectangle().fill(LYLLTHTheme.dim).frame(width: 1, height: 10).offset(x: mid)
                    Rectangle().fill(color)
                        .frame(width: abs(CGFloat(amount)) * mid, height: 3)
                        .offset(x: amount >= 0 ? mid : mid - abs(CGFloat(amount)) * mid)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    update(base + 2, Float(min(max((drag.location.x - mid) / mid, -1), 1)))
                })
                .onTapGesture(count: 2) { update(base + 2, 0) }
            }
            .frame(height: 24)
            Text(String(format: "%+.0f", amount * 100))
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.text)
                .frame(width: 32, alignment: .trailing)
            Button(action: clear) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                    .frame(width: 16, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this route")
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(color.opacity(0.05))
        .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }

    private func cycler(_ text: String, color: Color, step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 6, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                    .frame(width: 12, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Text(text).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(0.6).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 6, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                    .frame(width: 12, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Keyboard

struct LYSynthKeyboard: View {
    let lowestOctave: Int
    let held: Set<Int>
    let press: (Int) -> Void
    let release: (Int) -> Void
    @State private var dragNote: Int?

    private let whiteSteps = [0, 2, 4, 5, 7, 9, 11]
    private let blackSteps: [(Int, CGFloat)] = [(1, 0.7), (3, 1.7), (6, 3.7), (8, 4.7), (10, 5.7)]

    var body: some View {
        GeometryReader { geo in
            let octaves = 4
            let whiteWidth = geo.size.width / CGFloat(octaves * 7)
            let base = (lowestOctave + 1) * 12
            ZStack(alignment: .topLeading) {
                ForEach(0..<(octaves * 7), id: \.self) { i in
                    let note = base + (i / 7) * 12 + whiteSteps[i % 7]
                    Rectangle()
                        // DrumKit's piano-roll white keys: the control chrome.
                        .fill(held.contains(note) ? LYLLTHTheme.teal : LYLLTHTheme.chromeText)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        .overlay(alignment: .bottom) {
                            if note % 12 == 0 {
                                Text("C\(note / 12 - 1)").font(LYLLTHTheme.value(7.5)).foregroundStyle(Color.black.opacity(0.6)).padding(.bottom, 3)
                            }
                        }
                        .frame(width: whiteWidth, height: geo.size.height)
                        .offset(x: CGFloat(i) * whiteWidth)
                }
                ForEach(0..<(octaves * 5), id: \.self) { i in
                    let step = blackSteps[i % 5]
                    let note = base + (i / 5) * 12 + step.0
                    Rectangle()
                        .fill(held.contains(note) ? LYLLTHTheme.indigo : Color(hex: 0x0B0C10))
                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.6)
                        .offset(x: (CGFloat(i / 5) * 7 + step.1) * whiteWidth)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let note = noteAt(drag.location, size: geo.size, whiteWidth: whiteWidth, base: base)
                        if note != dragNote {
                            if let dragNote { release(dragNote) }
                            if let note { press(note) }
                            dragNote = note
                        }
                    }
                    .onEnded { _ in
                        if let dragNote { release(dragNote) }
                        dragNote = nil
                    }
            )
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .help("Click or drag to play. Computer keys A–K play too; Z and X shift the octave.")
    }

    private func noteAt(_ point: CGPoint, size: CGSize, whiteWidth: CGFloat, base: Int) -> Int? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y <= size.height else { return nil }
        if point.y < size.height * 0.6 {
            for i in 0..<20 {
                let step = blackSteps[i % 5]
                let x = (CGFloat(i / 5) * 7 + step.1) * whiteWidth
                if point.x >= x && point.x <= x + whiteWidth * 0.62 { return base + (i / 5) * 12 + step.0 }
            }
        }
        let i = Int(point.x / whiteWidth)
        return base + (i / 7) * 12 + whiteSteps[i % 7]
    }
}

/// Computer-keyboard playing while the editor is open, the Logic layout:
/// A W S E D F T G Y H U J K, Z / X for octave, Esc closes.
private struct LYSynthKeyMonitor: NSViewRepresentable {
    @Binding var octave: Int
    let press: (Int) -> Void
    let release: (Int) -> Void
    let close: () -> Void
    var isEnabled = true

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handle
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handler = handle
    }

    private static let map: [String: Int] = ["a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8, "h": 9, "u": 10, "j": 11, "k": 12]

    private func handle(_ event: NSEvent) -> Bool {
        if event.window?.firstResponder is NSTextView { return false }
        guard isEnabled else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.type == .keyDown && event.keyCode == 53 { close(); return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.type == .keyDown && !event.isARepeat {
            if key == "z" { octave = max(0, octave - 1); return true }
            if key == "x" { octave = min(7, octave + 1); return true }
        }
        guard let offset = Self.map[key] else { return false }
        let note = (octave + 1) * 12 + offset
        if event.type == .keyDown {
            if !event.isARepeat { press(note) }
        } else {
            release(note)
        }
        return true
    }

    final class MonitorView: NSView {
        var handler: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                return self.handler(event) ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}


// MARK: - Browsers

/// FACTORY and USER sounds side by side. User sounds can be deleted here.
struct LYPresetBrowser: View {
    let current: String
    let user: [LYSynthPatch]
    let choose: (LYSynthPatch) -> Void
    let delete: (String) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOUNDS").font(LYLLTHTheme.label(9, weight: .bold)).tracking(1.8).foregroundStyle(LYLLTHTheme.teal)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                column("FACTORY", LYSynthPatch.factory, deletable: false)
                column("USER", user, deletable: true)
            }
        }
        .padding(10)
        .background(Color(hex: 0x07080D).opacity(0.98))
        .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
    }

    private func column(_ title: String, _ patches: [LYSynthPatch], deletable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1.6).foregroundStyle(LYLLTHTheme.dim)
            ScrollView {
                VStack(spacing: 3) {
                    if patches.isEmpty {
                        Text("SAVE A SOUND TO SEE IT HERE")
                            .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                            .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                    ForEach(patches, id: \.name) { item in
                        HStack(spacing: 0) {
                            Button { choose(item) } label: {
                                Text(item.name)
                                    .font(LYLLTHTheme.label(8.5, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(item.name == current ? LYLLTHTheme.teal : LYLLTHTheme.text)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                    .padding(.leading, 8)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if deletable {
                                Button { delete(item.name) } label: {
                                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                                        .frame(width: 22, height: 24).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Delete this preset")
                            }
                        }
                        .background(LYLLTHTheme.teal.opacity(item.name == current ? 0.1 : 0))
                        .overlay(Rectangle().stroke(item.name == current ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
                    }
                }
            }
            .lyScrollers()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Factory tables, the user's own tables, and IMPORT / EDIT.
struct LYTableBrowser: View {
    let accent: Color
    let current: String
    let user: [String]
    let chooseFactory: (Int) -> Void
    let chooseUser: (String) -> Void
    let importTable: () -> Void
    let editTable: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("WAVETABLE").font(LYLLTHTheme.label(8.5, weight: .bold)).tracking(1.6).foregroundStyle(accent)
                Spacer()
                action("IMPORT…", importTable)
                action("EDIT…", editTable)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    grid(LYSynthNames.tables) { index, _ in chooseFactory(index) }
                    if !user.isEmpty {
                        Text("YOUR TABLES").font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.4).foregroundStyle(LYLLTHTheme.dim).padding(.top, 4)
                        grid(user) { _, name in chooseUser(name) }
                    }
                }
            }
            .lyScrollers()
        }
        .padding(8)
        .background(Color(hex: 0x07080D).opacity(0.97))
        .overlay(Rectangle().stroke(accent.opacity(0.6), lineWidth: 1))
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(1).foregroundStyle(accent)
                .padding(.horizontal, 7).frame(height: 20)
                .overlay(Rectangle().stroke(accent.opacity(0.7), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func grid(_ names: [String], choose: @escaping (Int, String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Button { choose(index, name) } label: {
                    Text(name)
                        .font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(0.7)
                        .foregroundStyle(name == current ? accent : LYLLTHTheme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(accent.opacity(name == current ? 0.12 : 0.02))
                        .overlay(Rectangle().stroke(name == current ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}
