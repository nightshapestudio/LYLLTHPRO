import SwiftUI
import AppKit

/// What every LUNATK page needs to read and change the sound, and to open
/// the editor's dropdowns.
@MainActor
struct LYSynthContext {
    let patch: LYSynthPatch
    let live: LYSynthLive
    let set: (Int, Float) -> Void
    let replace: (LYSynthPatch) -> Void
    let addRoute: (Int, Int) -> Void
    let openMenu: (LYSynthMenuRequest) -> Void

    static let space = "LYSynthEditor"

    func value(_ id: Int) -> Float { patch.value(id) }
    func isOn(_ id: Int) -> Bool { patch.value(id) > 0.5 }
    func toggle(_ id: Int) { set(id, isOn(id) ? 0 : 1) }

    func knob(_ id: Int, _ destination: Int? = nil, accent: Color, diameter: CGFloat = 28,
              label: String? = nil, format: ((Float) -> String)? = nil) -> LYSynthKnob {
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

    /// A dropdown for a stepped parameter.
    func choice(_ id: Int, label: String, names: [String], order: [Int]? = nil, accent: Color,
                columns: Int = 2, width: CGFloat = 260, anchor: String) -> some View {
        let current = Int(value(id).rounded())
        return LYSynthChoiceButton(label: label, value: names.indices.contains(current) ? names[current] : "—", accent: accent) {
            openMenu(LYSynthMenuRequest(anchor: anchor, title: label, names: names, order: order, selected: current,
                                        accent: accent, columns: columns, width: width) { set(id, Float($0)) })
        }
        .lyMenuAnchor(anchor, in: Self.space)
    }

    static func time(_ value: Float) -> String {
        let seconds = 0.0005 * pow(20_000, Double(value))
        return seconds < 1 ? String(format: "%.0f MS", seconds * 1000) : String(format: "%.2f S", seconds)
    }

    static func pan(_ value: Float) -> String {
        abs(value) < 0.01 ? "C" : (value < 0 ? "L\(Int(abs(value) * 100))" : "R\(Int(value * 100))")
    }

    static func hz(_ value: Float) -> String {
        let hz = 20 * pow(1000, value)
        return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
    }
}

// MARK: - Editor

/// LUNATK. OSC, FX, ARP, MATRIX and GLOBAL pages over one header and one
/// keyboard, in the NIGHTSHAPE language.
struct LYSynthEditor: View {
    @Binding var patch: LYSynthPatch
    let trackName: String
    let instrument: LYSynthInstrument?
    /// Copies a custom wavetable into the song so it travels with it.
    var storeTableInProject: (String, [Float]) -> Void = { _, _ in }
    let close: () -> Void
    /// The page it opens on.
    var initialPage: Page = .osc

    enum Page: String, CaseIterable { case osc = "OSC", fx = "FX", arp = "ARP", matrix = "MATRIX", global = "GLOBAL" }

    @StateObject private var live = LYSynthLive()
    @ObservedObject private var tableLibrary = LYWavetableLibrary.shared
    @ObservedObject private var presetStore = LYSynthPresetStore.shared
    @State private var chosenPage: Page?
    private var page: Page { chosenPage ?? initialPage }
    @State private var editingTable: Int?
    @State private var savingPreset = false
    @State private var presetDraft = ""
    @State private var presetError: String?
    @State private var anchors: [String: CGRect] = [:]
    @State private var menu: LYSynthMenuRequest?
    @State private var choosingTable: Int?
    @State private var choosingPreset = false
    @State private var modTab = 0          // 0…3 envelopes, 4…7 LFOs
    @State private var heldKeys: Set<Int> = []
    @State private var keyboardOctave = 4

    private var context: LYSynthContext {
        LYSynthContext(patch: patch, live: live, set: set, replace: { patch = $0 }, addRoute: addRoute,
                       openMenu: { request in withAnimation(LYLLTHTheme.snap) { menu = request } })
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            pageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LYSynthKeyboard(
                lowestOctave: keyboardOctave,
                held: heldKeys,
                press: { note in play(note) },
                release: { note in stop(note) }
            )
            .frame(height: 40)
        }
        .coordinateSpace(name: LYSynthContext.space)
        .onPreferenceChange(LYMenuAnchorKey.self) { anchors = $0 }
        .overlay(alignment: .topLeading) { floatingLayer }
        .padding(12)
        .background(Color(hex: 0x06070B))
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .overlay { wavetableEditorOverlay }
        .overlay { presetSaveOverlay }
        .background(LYSynthKeyMonitor(octave: $keyboardOctave, press: play, release: stop,
                                      close: { if editingTable != nil { editingTable = nil } else if menu != nil { menu = nil } else { close() } },
                                      isEnabled: editingTable == nil && !savingPreset))
        .onAppear {
            live.attach(instrument)
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if let raw = environment["LYLLTH_DEBUG_SYNTHPAGE"], let debugPage = Page(rawValue: raw) { chosenPage = debugPage }
            if let tab = environment["LYLLTH_DEBUG_MODTAB"].flatMap(Int.init) { modTab = tab }
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

    private func addRoute(_ source: Int, _ destination: Int) {
        var next = patch
        next.route(source: source, destination: destination, amount: 0.3)
        patch = next
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                LUNATKMark(size: 22)
                Text(trackName)
                    .font(LYLLTHTheme.label(7, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(1)
            }
            .fixedSize()

            HStack(spacing: 0) {
                ForEach(Page.allCases, id: \.self) { item in
                    let isOn = page == item
                    Button { withAnimation(LYLLTHTheme.snap) { chosenPage = item; menu = nil } } label: {
                        Text(item.rawValue)
                            .font(LYLLTHTheme.label(9.5, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(isOn ? LYLLTHTheme.text : LYLLTHTheme.dim)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(isOn ? pageAccent(item) : .clear).frame(height: 2)
                                    .lyBloom(pageAccent(item), isOn: isOn && pageAccent(item) != LYLLTHTheme.teal)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) { pageBadge(item) }
                }
            }
            .overlay(alignment: .bottom) { LYHairline() }

            Spacer(minLength: 8)

            presetBar

            LYSynthScope(live: live, accent: LYLLTHTheme.lavender)
                .frame(width: 150, height: 38)

            VStack(spacing: 1) {
                Text("\(live.display.activeVoices)")
                    .font(LYLLTHTheme.value(15))
                    .foregroundStyle(LYLLTHTheme.text)
                Text("VOICES")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .frame(width: 42)

            context.knob(LY_MASTER, LY_DST_MASTER, accent: LYLLTHTheme.chromeText, diameter: 28, label: "MASTER")
        }
        .frame(height: 50)
    }

    private func pageAccent(_ page: Page) -> Color {
        switch page {
        case .osc: return LYLLTHTheme.teal
        case .fx: return LYLLTHTheme.indigo
        case .arp: return LYLLTHTheme.purple
        case .matrix: return LYLLTHTheme.lavender
        case .global: return LYLLTHTheme.chromeText
        }
    }

    /// A small count on FX and MATRIX, a dot on ARP while it is on.
    @ViewBuilder
    private func pageBadge(_ page: Page) -> some View {
        switch page {
        case .fx:
            let on = LYSynthFXPage.onIDs.filter { patch.value($0) > 0.5 }.count
            if on > 0 { badge("\(on)", color: LYLLTHTheme.indigo) }
        case .matrix:
            let used = patch.usedMatrixSlots.count
            if used > 0 { badge("\(used)", color: LYLLTHTheme.lavender) }
        case .arp:
            if patch.value(LY_ARP_ON) > 0.5 {
                Circle().fill(LYLLTHTheme.purple).frame(width: 5, height: 5).lyBloom(LYLLTHTheme.purple).padding(.top, 6).padding(.trailing, 4)
            }
        default: EmptyView()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(LYLLTHTheme.value(7))
            .foregroundStyle(color)
            .padding(.top, 4)
            .padding(.trailing, 3)
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
                .frame(width: 200, height: 38)
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
        .lyMenuAnchor("preset", in: LYSynthContext.space)
    }

    private func presetArrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                .frame(width: 26, height: 38).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pages

    private var pageView: AnyView {
        switch page {
        case .osc: return AnyView(oscPage)
        case .fx: return AnyView(LYSynthFXPage(context: context))
        case .arp: return AnyView(LYSynthArpPage(context: context))
        case .matrix: return AnyView(LYSynthMatrixPage(context: context))
        case .global: return AnyView(LYSynthGlobalPage(context: context))
        }
    }

    private var oscPage: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                AnyView(subNoiseColumn).frame(width: 196)
                AnyView(oscillatorPanel(0)).frame(width: 342)
                AnyView(oscillatorPanel(1)).frame(width: 342)
                AnyView(filterPanel).frame(maxWidth: .infinity)
            }
            .frame(height: 336)
            HStack(alignment: .top, spacing: 8) {
                AnyView(modulationPanel).frame(maxWidth: .infinity)
                AnyView(macroPanel).frame(width: 236)
                AnyView(voicePanel).frame(width: 200)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: Floating layer: dropdowns, table and preset browsers

    @ViewBuilder
    private var floatingLayer: some View {
        ZStack(alignment: .topLeading) {
            if menu != nil || choosingTable != nil || choosingPreset {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { menu = nil; choosingTable = nil; choosingPreset = false }
            }
            if let menu, let frame = anchors[menu.anchor] {
                LYSynthMenuView(request: menu, close: { self.menu = nil })
                    .offset(x: max(0, min(frame.minX, frame.maxX - menu.width)), y: frame.maxY + 4)
                    .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
            if let oscillator = choosingTable, let frame = anchors["table\(oscillator)"] {
                LYTableBrowser(
                    accent: oscillator == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo,
                    current: patch.tableName(oscillator),
                    user: tableLibrary.names,
                    chooseFactory: { chooseFactoryTable(oscillator, $0); choosingTable = nil },
                    chooseUser: { chooseCustomTable(oscillator, $0); choosingTable = nil },
                    importTable: { choosingTable = nil; importTable(oscillator) },
                    editTable: { choosingTable = nil; editingTable = oscillator },
                    close: { choosingTable = nil }
                )
                .frame(width: frame.width, height: 260)
                .offset(x: frame.minX, y: frame.minY)
            }
            if choosingPreset, let frame = anchors["preset"] {
                LYPresetBrowser(
                    current: patch.name,
                    user: presetStore.presets,
                    choose: { patch = $0; choosingPreset = false },
                    delete: { presetStore.delete($0) },
                    close: { choosingPreset = false }
                )
                .frame(width: 440, height: 420)
                .offset(x: min(frame.minX, frame.maxX - 440), y: frame.maxY + 6)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: Oscillators

    private func oscillatorPanel(_ o: Int) -> some View {
        let accent = o == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo
        let p = { (local: Int) in LYSynthParameters.oscillator(o, local) }
        let d = { (aDestination: Int) in o == 0 ? aDestination : aDestination + (LY_DST_B_LEVEL - LY_DST_A_LEVEL) }
        let d2 = { (aDestination: Int) in o == 0 ? aDestination : aDestination + (LY_DST_B_WARP2 - LY_DST_A_WARP2) }
        let table = o == 0 ? patch.tableA : patch.tableB
        let warpNames = o == 0 ? LYSynthNames.warps : LYSynthNames.warpsB
        let name = o == 0 ? "A" : "B"
        let c = context

        return LYSynthPanel(title: "OSC \(name)", accent: accent, isOn: c.isOn(p(LY_OSC_ON)), toggle: { c.toggle(p(LY_OSC_ON)) }) {
            HStack(spacing: 4) {
                LYSynthStepper(label: "OCT", text: String(format: "%+d", Int(c.value(p(LY_OSC_OCTAVE)))), accent: accent) {
                    c.set(p(LY_OSC_OCTAVE), c.value(p(LY_OSC_OCTAVE)) + Float($0))
                }
                LYSynthStepper(label: "SEMI", text: String(format: "%+d", Int(c.value(p(LY_OSC_SEMI)))), accent: accent) {
                    c.set(p(LY_OSC_SEMI), c.value(p(LY_OSC_SEMI)) + Float($0))
                }
            }
        } content: {
            VStack(spacing: 7) {
                Button { choosingTable = choosingTable == o ? nil : o } label: {
                    LYWavetableView(table: table, customName: o == 0 ? patch.customTableA : patch.customTableB,
                                    oscillator: o, basePosition: c.value(p(LY_OSC_WTPOS)),
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
                .help("Choose, import or edit a wavetable")
                .lyMenuAnchor("table\(o)", in: LYSynthContext.space)
                .frame(height: 120)

                HStack(spacing: 4) {
                    c.choice(p(LY_OSC_WARPMODE), label: "WARP", names: warpNames, order: LYSynthNames.warpOrder, accent: accent,
                             columns: 2, width: 240, anchor: "warp\(o)")
                    c.choice(p(LY_OSC_WARPMODE2), label: "WARP 2", names: warpNames, order: LYSynthNames.warpOrder, accent: accent,
                             columns: 2, width: 240, anchor: "warp2\(o)")
                    c.choice(p(LY_OSC_UNIMODE), label: "UNISON", names: LYSynthNames.unisonModes, accent: accent,
                             columns: 2, width: 200, anchor: "uni\(o)")
                    c.choice(p(LY_OSC_STACK), label: "STACK", names: LYSynthNames.stacks, accent: accent,
                             columns: 1, width: 140, anchor: "stack\(o)")
                }

                Grid(horizontalSpacing: 0, verticalSpacing: 6) {
                    GridRow {
                        c.knob(p(LY_OSC_WTPOS), d(LY_DST_A_WTPOS), accent: accent, diameter: 32, label: "WT POS")
                        c.knob(p(LY_OSC_WARPAMT), d(LY_DST_A_WARP), accent: accent, label: "WARP")
                        c.knob(p(LY_OSC_WARPAMT2), d2(LY_DST_A_WARP2), accent: accent, label: "WARP 2")
                        c.knob(p(LY_OSC_LEVEL), d(LY_DST_A_LEVEL), accent: accent)
                        c.knob(p(LY_OSC_PAN), d(LY_DST_A_PAN), accent: accent, format: LYSynthContext.pan)
                        c.knob(p(LY_OSC_FINE), d2(LY_DST_A_FINE), accent: accent, label: "FINE", format: { String(format: "%+.0f¢", $0) })
                    }
                    GridRow {
                        c.knob(p(LY_OSC_UNISON), accent: accent, label: "VOICES")
                        c.knob(p(LY_OSC_DETUNE), d(LY_DST_A_DETUNE), accent: accent)
                        c.knob(p(LY_OSC_BLEND), d(LY_DST_A_BLEND), accent: accent)
                        c.knob(p(LY_OSC_WIDTH), d2(LY_DST_A_WIDTH), accent: accent)
                        c.knob(p(LY_OSC_PHASE), accent: accent, label: "PHASE", format: { String(format: "%.0f°", $0 * 360) })
                        c.knob(p(LY_OSC_RANDPHASE), accent: accent, label: "RAND")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Sub and noise

    private var subNoiseColumn: some View {
        let c = context
        let accent = LYLLTHTheme.purple
        return VStack(spacing: 8) {
            LYSynthPanel(title: "SUB", accent: accent, isOn: c.isOn(LY_SUB_ON), toggle: { c.toggle(LY_SUB_ON) }) {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        c.choice(LY_SUB_SHAPE, label: "SHAPE", names: LYSynthNames.subShapes, accent: accent, columns: 2, width: 180, anchor: "subShape")
                        LYSynthStepper(label: "OCT", text: "−\(Int(c.value(LY_SUB_OCTAVE)))", accent: accent) { step in
                            c.set(LY_SUB_OCTAVE, c.value(LY_SUB_OCTAVE) + Float(step))
                        }
                    }
                    HStack(spacing: 0) {
                        c.knob(LY_SUB_LEVEL, LY_DST_SUB_LEVEL, accent: accent, diameter: 30)
                        c.knob(LY_SUB_PAN, LY_DST_SUB_PAN, accent: accent, diameter: 30, format: LYSynthContext.pan)
                    }
                }
            }
            .frame(height: 146)
            LYSynthPanel(title: "NOISE", accent: accent, isOn: c.isOn(LY_NOISE_ON), toggle: { c.toggle(LY_NOISE_ON) }) {
                LYSynthToggle(title: "KEY", isOn: c.isOn(LY_NOISE_KEYTRACK), accent: accent) { c.toggle(LY_NOISE_KEYTRACK) }
                    .help("The pitched noises (DIGITAL, METAL, BREATH, CRACKLE) follow the note")
            } content: {
                VStack(spacing: 8) {
                    c.choice(LY_NOISE_TYPE, label: "TYPE", names: LYSynthNames.noiseTypes, accent: accent, columns: 2, width: 190, anchor: "noiseType")
                    HStack(spacing: 0) {
                        c.knob(LY_NOISE_LEVEL, LY_DST_NOISE_LEVEL, accent: accent, diameter: 24)
                        c.knob(LY_NOISE_COLOR, LY_DST_NOISE_COLOR, accent: accent, diameter: 24)
                        c.knob(LY_NOISE_PITCH, LY_DST_NOISE_PITCH, accent: accent, diameter: 24)
                        c.knob(LY_NOISE_PAN, LY_DST_NOISE_PAN, accent: accent, diameter: 24, format: LYSynthContext.pan)
                    }
                }
            }
        }
    }

    // MARK: Filters

    private var filterPanel: some View {
        let c = context
        let accent = LYLLTHTheme.teal
        return LYSynthPanel(title: "FILTER", accent: accent) {
            HStack(spacing: 3) {
                ForEach([("A", LY_FILTER_ROUTE_A), ("B", LY_FILTER_ROUTE_B), ("S", LY_FILTER_ROUTE_SUB), ("N", LY_FILTER_ROUTE_NOISE)], id: \.1) { item in
                    LYSynthToggle(title: item.0, isOn: c.isOn(item.1), accent: accent) { c.toggle(item.1) }
                        .help("Send \(item.0 == "S" ? "SUB" : item.0 == "N" ? "NOISE" : "OSC " + item.0) through the filters")
                }
            }
        } content: {
            VStack(spacing: 6) {
                LYFilterCurve(patch: patch, live: live)
                    .frame(height: 92)
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 3) {
                            LYSynthToggle(title: "SERIAL", isOn: !c.isOn(LY_FILTER_ROUTING), accent: accent) { c.set(LY_FILTER_ROUTING, 0) }
                            LYSynthToggle(title: "PARALLEL", isOn: c.isOn(LY_FILTER_ROUTING), accent: accent) { c.set(LY_FILTER_ROUTING, 1) }
                        }
                        .padding(5)
                    }
                filterRow(number: 1, on: LY_FILTER_ON, type: LY_FILTER_TYPE, cutoff: LY_FILTER_CUTOFF, res: LY_FILTER_RES, drive: LY_FILTER_DRIVE,
                          env: LY_FILTER_ENVAMT, envLabel: "ENV 2", key: LY_FILTER_KEYTRACK, mix: LY_FILTER_MIX,
                          destinations: (LY_DST_CUTOFF, LY_DST_RES, LY_DST_DRIVE, LY_DST_FILTER_MIX), accent: accent)
                filterRow(number: 2, on: LY_F2_ON, type: LY_F2_TYPE, cutoff: LY_F2_CUTOFF, res: LY_F2_RES, drive: LY_F2_DRIVE,
                          env: LY_F2_ENVAMT, envLabel: "ENV 3", key: LY_F2_KEYTRACK, mix: LY_F2_MIX,
                          destinations: (LY_DST_F2_CUTOFF, LY_DST_F2_RES, LY_DST_F2_DRIVE, LY_DST_F2_MIX), accent: LYLLTHTheme.indigo)
            }
        }
    }

    private func filterRow(number: Int, on: Int, type: Int, cutoff: Int, res: Int, drive: Int, env: Int, envLabel: String,
                           key: Int, mix: Int, destinations: (Int, Int, Int, Int), accent: Color) -> some View {
        let c = context
        let isOn = c.isOn(on)
        return HStack(spacing: 6) {
            VStack(spacing: 4) {
                Button { c.toggle(on) } label: {
                    Text("\(number)")
                        .font(LYLLTHTheme.value(10))
                        .foregroundStyle(isOn ? accent : LYLLTHTheme.dim)
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(isOn ? 0.14 : 0))
                        .overlay(Rectangle().stroke(isOn ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOn ? "Turn filter \(number) off" : "Turn filter \(number) on")
                if number == 1 {
                    c.knob(LY_FILTER_PAN, LY_DST_FILTER_PAN, accent: LYLLTHTheme.chromeText, diameter: 16, label: "PAN", format: LYSynthContext.pan)
                }
            }
            c.choice(type, label: "FILTER \(number)", names: LYSynthNames.filters, order: LYSynthNames.filterOrder, accent: accent,
                     columns: 2, width: 220, anchor: "filterType\(number)")
                .frame(width: 84)
            HStack(spacing: 0) {
                c.knob(cutoff, destinations.0, accent: accent, diameter: 28, format: LYSynthContext.hz)
                c.knob(res, destinations.1, accent: accent, diameter: 24)
                c.knob(drive, destinations.2, accent: accent, diameter: 24)
                c.knob(env, accent: LYLLTHTheme.indigo, diameter: 24, label: envLabel)
                c.knob(key, accent: accent, diameter: 24, label: "KEY")
                c.knob(mix, destinations.3, accent: accent, diameter: 24)
            }
            .opacity(isOn ? 1 : 0.4)
        }
    }

    // MARK: Modulation

    private var modulationPanel: some View {
        let sources = [LY_SRC_ENV1, LY_SRC_ENV2, LY_SRC_ENV3, LY_SRC_ENV4, LY_SRC_LFO1, LY_SRC_LFO2, LY_SRC_LFO3, LY_SRC_LFO4]
        let names = ["ENV 1", "ENV 2", "ENV 3", "ENV 4", "LFO 1", "LFO 2", "LFO 3", "LFO 4"]
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    let color = LYSynthSourceColor.color(sources[index])
                    let isOn = modTab == index
                    let routes = patch.usedMatrixSlots.filter { Int(patch.value(LYSynthParameters.matrix($0, LY_MX_SOURCE))) == sources[index] }.count
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(color)
                            .help("Drag onto any knob to modulate it")
                        Text(names[index])
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(isOn ? color : LYLLTHTheme.dim)
                        if routes > 0 {
                            Text("\(routes)").font(LYLLTHTheme.value(7)).foregroundStyle(color)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
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
                if modTab < 4 { envelopeEditor(modTab) } else { lfoEditor(modTab - 4) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func envelopeEditor(_ e: Int) -> some View {
        let c = context
        let color = LYSynthSourceColor.color(e == 3 ? LY_SRC_ENV4 : LY_SRC_ENV1 + e)
        let base = LY_ENV1_A + e * 4
        let hold = LY_ENV1_H + e
        let note = ["SHAPES THE VOLUME", "FILTER 1 · ROUTE ANYWHERE", "FILTER 2 · ROUTE ANYWHERE", "ROUTE ANYWHERE"][e]
        return VStack(spacing: 8) {
            LYEnvelopeGraph(
                attack: c.value(base), hold: c.value(hold), decay: c.value(base + 1),
                sustain: c.value(base + 2), release: c.value(base + 3),
                curves: (0..<3).map { c.value(LY_ENV1_ACURVE + e * 3 + $0) },
                color: color, level: live.envelope(e),
                set: { index, value in c.set(base + index, value) },
                setHold: { c.set(hold, $0) },
                setCurve: { index, value in c.set(LY_ENV1_ACURVE + e * 3 + index, value) }
            )
            HStack(alignment: .bottom, spacing: 0) {
                c.knob(base, e == 0 ? LY_DST_ENV1_ATTACK : e == 1 ? LY_DST_ENV2_ATTACK : nil, accent: color, label: "ATTACK", format: LYSynthContext.time)
                Spacer(minLength: 0)
                c.knob(hold, accent: color, label: "HOLD", format: { $0 < 0.001 ? "—" : LYSynthContext.time($0) })
                Spacer(minLength: 0)
                c.knob(base + 1, e == 0 ? LY_DST_ENV1_DECAY : e == 1 ? LY_DST_ENV2_DECAY : nil, accent: color, label: "DECAY", format: LYSynthContext.time)
                Spacer(minLength: 0)
                c.knob(base + 2, accent: color, label: "SUSTAIN")
                Spacer(minLength: 0)
                c.knob(base + 3, e == 0 ? LY_DST_ENV1_RELEASE : e == 1 ? LY_DST_ENV2_RELEASE : nil, accent: color, label: "RELEASE", format: LYSynthContext.time)
                Spacer(minLength: 0)
                Text(note + "\n◆ DRAG TO CURVE")
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
        let c = context
        let color = LYSynthSourceColor.color(LY_SRC_LFO1 + l)
        let f = { (field: Int) in LYSynthParameters.lfo(l, field) }
        let synced = c.isOn(f(LY_LFO1_SYNC))
        let pointsBase = LY_LFO_POINTS_BASE + l * Int(LY_LFO_POINTS)
        let shape = Int(c.value(f(LY_LFO1_SHAPE)))
        let rateText = { (value: Float) -> String in
            if synced {
                let index = Int((value * Float(LYSynthNames.syncDivisions.count - 1)).rounded())
                return LYSynthNames.syncDivisions[min(max(index, 0), LYSynthNames.syncDivisions.count - 1)]
            }
            let hz = 0.02 * pow(1500, Double(value))
            return hz < 1 ? String(format: "%.2f HZ", hz) : String(format: "%.1f HZ", hz)
        }
        return VStack(spacing: 8) {
            LYLFOGraph(
                shape: shape,
                points: (0..<Int(LY_LFO_POINTS)).map { c.value(pointsBase + $0) },
                smooth: c.isOn(f(LY_LFO1_SMOOTH)),
                phaseOffset: c.value(f(LY_LFO1_PHASE)),
                delay: c.value(f(LY_LFO1_DELAY)),
                rise: c.value(f(LY_LFO1_RISE)),
                oneShot: Int(c.value(f(LY_LFO1_RETRIG))) == LY_LFOMODE_ENV,
                color: color, live: live, index: l,
                paint: { i, value in c.set(pointsBase + i, value) }
            )
            HStack(alignment: .center, spacing: 6) {
                LYSynthChoiceButton(label: "SHAPE", value: LYSynthNames.lfoShapes[min(max(shape, 0), LYSynthNames.lfoShapes.count - 1)], accent: color) {
                    c.openMenu(LYSynthMenuRequest(anchor: "lfoShape", title: "LFO \(l + 1) SHAPE", names: LYSynthNames.lfoShapes, selected: shape,
                                                  accent: color, columns: 2, width: 200) { new in
                        var next = patch
                        // Entering DRAW starts from the shape you were on.
                        if new == LY_LFO_CUSTOM && shape != LY_LFO_CUSTOM {
                            for i in 0..<Int(LY_LFO_POINTS) {
                                let p = Double(i) / Double(LY_LFO_POINTS)
                                next.set(pointsBase + i, Float(LYLFOGraph.value(shape: shape, at: p, points: [], smooth: true)))
                            }
                        }
                        next.set(f(LY_LFO1_SHAPE), Float(new))
                        patch = next
                    })
                }
                .lyMenuAnchor("lfoShape", in: LYSynthContext.space)
                .frame(width: 96)
                c.choice(f(LY_LFO1_RETRIG), label: "MODE", names: LYSynthNames.lfoModes, accent: color, columns: 3, width: 210, anchor: "lfoMode")
                    .frame(width: 76)
                    .help("FREE runs on its own; TRIG restarts with each note; ENV runs once per note, like an envelope")
                c.knob(f(LY_LFO1_RATE), LY_DST_LFO1_RATE + l, accent: color, label: "RATE", format: rateText)
                LYSynthToggle(title: "SYNC", isOn: synced, accent: color) { c.toggle(f(LY_LFO1_SYNC)) }
                c.knob(f(LY_LFO1_PHASE), accent: color, label: "PHASE", format: { String(format: "%.0f°", $0 * 360) })
                c.knob(f(LY_LFO1_DELAY), accent: color, label: "DELAY", format: { String(format: "%.2f S", $0 * 4) })
                c.knob(f(LY_LFO1_RISE), accent: color, label: "RISE", format: { String(format: "%.2f S", $0 * 4) })
                if shape == LY_LFO_CUSTOM {
                    LYSynthToggle(title: "SMOOTH", isOn: c.isOn(f(LY_LFO1_SMOOTH)), accent: color) { c.toggle(f(LY_LFO1_SMOOTH)) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Macros and voice

    private var macroPanel: some View {
        let c = context
        return LYSynthPanel(title: "MACROS", accent: LYLLTHTheme.chromeText) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<4, id: \.self) { m in
                    let source = LY_SRC_MACRO1 + m
                    let color = LYSynthSourceColor.color(source)
                    let routes = patch.usedMatrixSlots.filter { Int(patch.value(LYSynthParameters.matrix($0, LY_MX_SOURCE))) == source }.count
                    c.knob(LY_MACRO1 + m, accent: color, diameter: 42, label: routes > 0 ? "MACRO \(m + 1) · \(routes)" : "MACRO \(m + 1)")
                        .overlay(alignment: .topTrailing) { dragHandle(source, color: color, help: "Drag onto a knob to put it on MACRO \(m + 1)") }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var voicePanel: some View {
        let c = context
        let accent = LYLLTHTheme.indigo
        let sources: [(Int, String)] = [(LY_SRC_VELOCITY, "VELO"), (LY_SRC_NOTE, "NOTE"), (LY_SRC_RANDOM, "RAND"),
                                        (LY_SRC_MODWHEEL, "MOD"), (LY_SRC_PRESSURE, "AFTER"), (LY_SRC_PITCHBEND, "BEND")]
        return LYSynthPanel(title: "VOICE", accent: accent) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    LYSynthStepper(label: "VOICES", text: Int(c.value(LY_VOICES)) == 1 ? "MONO" : "\(Int(c.value(LY_VOICES)))", accent: accent) { step in
                        c.set(LY_VOICES, c.value(LY_VOICES) + Float(step))
                    }
                    LYSynthToggle(title: "LEGATO", isOn: c.isOn(LY_LEGATO), accent: accent) { c.toggle(LY_LEGATO) }
                }
                HStack(spacing: 0) {
                    c.knob(LY_GLIDE, accent: accent, diameter: 26, format: { String(format: "%.0f MS", $0 * 1000) })
                    c.knob(LY_MODWHEEL, accent: LYLLTHTheme.chromeText, diameter: 26, label: "MOD WHEEL")
                }
                Text("SOURCES · DRAG ONTO A KNOB")
                    .font(LYLLTHTheme.label(6, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.dim)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(sources, id: \.0) { source in
                        Text(source.1)
                            .font(LYLLTHTheme.label(7, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(LYLLTHTheme.text)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Rectangle())
                            .draggable("\(LYSynthSourceColor.dragPrefix)\(source.0)") {
                                Text(LYSynthNames.sources[source.0]).font(LYLLTHTheme.label(10, weight: .bold)).padding(6).background(Color.black)
                            }
                            .help("Drag onto any knob to modulate it with \(LYSynthNames.sources[source.0])")
                    }
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

    // MARK: Wavetables and presets

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
}
