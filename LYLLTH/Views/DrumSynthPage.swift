import NightshapeAudioEngine
import SwiftUI

/// LYLLTH's DRUM SYNTH page: every drum sound by category, and the synth that
/// makes them. Pick a sound, shape it, and load it onto any drum track.
/// The Mac counterpart of DrumKit's DRUM SYNTH page, with the same knobs,
/// the same drawn envelope and filter editors, SIMPLE and FULL views.
struct LYDrumSynthPage: View {
    /// Drum tracks in the song, for LOAD INTO.
    let tracks: [LYTrack]
    /// The track the page opened for.
    let initialTrackID: UUID?
    let audition: (DrumSynthPreset) -> Void
    /// Puts a sound on a track: (track, preset, whether it is edited or yours).
    let load: (UUID, DrumSynthPreset, Bool) -> Void

    @State private var category: DrumSynthCategory = .kick
    @State private var selectedID: String = ""
    @State private var query = ""
    @State private var targetID: UUID?
    @State private var targetMenuOpen = false
    @State private var simple = true
    /// Edits not yet saved, by sound.
    @State private var edited: [String: DrumSynthPreset] = [:]
    @State private var userPresets: [DrumSynthPreset] = LYDrumUserPresets.all()
    @State private var saveAsName: String?
    @State private var status = ""
    @State private var auditionWork: DispatchWorkItem?
    @FocusState private var saveFieldFocused: Bool
    @FocusState private var browsing: Bool

    private var categories: [(DrumSynthCategory, Int)] {
        LYDrumSounds.grouped.map { group in (group.0, group.1.count + userPresets.filter { $0.category == group.0 }.count) }
    }

    private var presets: [DrumSynthPreset] {
        let library = LYDrumSounds.grouped.first { $0.0 == category }?.1 ?? []
        let mine = userPresets.filter { $0.category == category }
        let all = mine + library
        guard !query.isEmpty else { return all }
        // Search reaches every category.
        return (userPresets + LYDrumSounds.presets).filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selected: DrumSynthPreset? {
        let stored = userPresets.first { $0.id == selectedID } ?? DrumSynthPresetLibrary.preset(id: selectedID)
        return edited[selectedID] ?? stored
    }

    private var isEdited: Bool { edited[selectedID] != nil }
    private var isMine: Bool { userPresets.contains { $0.id == selectedID } }
    private var target: LYTrack? { tracks.first { $0.id == targetID } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            LYHairline()
            HStack(spacing: 0) {
                categoryColumn.frame(width: 190)
                Rectangle().fill(LYLLTHTheme.line).frame(width: 1)
                presetColumn.frame(width: 240)
                Rectangle().fill(LYLLTHTheme.line).frame(width: 1)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: 0x0C0C0E))
        .overlay { targetMenu }
        // Browse by ear: ↑ ↓ plays each sound, ← → changes category.
        .focusable()
        .focusEffectDisabled()
        .focused($browsing)
        .onKeyPress(.upArrow, phases: .down) { _ in stepPreset(-1) }
        .onKeyPress(.downArrow, phases: .down) { _ in stepPreset(1) }
        .onKeyPress(.leftArrow, phases: .down) { _ in stepCategory(-1) }
        .onKeyPress(.rightArrow, phases: .down) { _ in stepCategory(1) }
        .onAppear {
            start()
            browsing = true
        }
    }

    private func start() {
        targetID = initialTrackID ?? tracks.first?.id
        if let track = target, let preset = LYDrumSounds.preset(for: track) {
            if track.customDrumPreset?.id == preset.id, !userPresets.contains(where: { $0.id == preset.id }) {
                edited[preset.id] = preset
            }
            category = preset.category
            selectedID = preset.id
        } else {
            selectedID = presets.first?.id ?? ""
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("LOAD INTO")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(LYLLTHTheme.secondary)
            Button { targetMenuOpen = true } label: {
                HStack(spacing: 6) {
                    Text(target?.name ?? "NO DRUM TRACK").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .buttonStyle(LYChromeButtonStyle(active: target != nil, tint: LYLLTHTheme.teal, compact: true))
            .disabled(tracks.isEmpty)
            .help("The drum track LOAD puts this sound on")
            Button(isEdited || isMine ? "LOAD EDITED" : "LOAD") { loadSelected() }
                .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.teal, compact: true))
                .disabled(target == nil || selected == nil)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Put this sound on \(target?.name ?? "the track") (⌘Return, or double-click a sound)")
            Button { if let selected { audition(selected) } } label: {
                HStack(spacing: 5) { Image(systemName: "play.fill").font(.system(size: 8, weight: .bold)); Text("PLAY") }
            }
            .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.indigo, compact: true))
            .keyboardShortcut(.return, modifiers: [])
            .help("Hear it (Return)")

            Spacer(minLength: 8)
            if !status.isEmpty {
                Text(status)
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(1)
            }
            if let name = saveAsName {
                TextField("NAME", text: Binding(get: { name }, set: { saveAsName = $0 }))
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .padding(.horizontal, 8)
                    .frame(width: 170, height: 24)
                    .background(LYLLTHTheme.deck)
                    .overlay(Rectangle().stroke(LYLLTHTheme.purple.opacity(0.7), lineWidth: 1))
                    .focused($saveFieldFocused)
                    .onSubmit(commitSaveAs)
                    .onExitCommand { saveAsName = nil }
                Button("SAVE", action: commitSaveAs)
                    .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.purple, compact: true))
            } else {
                Button("SAVE AS…") {
                    saveAsName = selected.map { ($0.name + (isMine ? "" : " 2")).uppercased() } ?? "MY SOUND"
                    DispatchQueue.main.async { saveFieldFocused = true }
                }
                .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.purple, compact: true))
                .disabled(selected == nil)
                .help("Keep this sound in YOUR SOUNDS, for every song")
            }
            Button("RESET") {
                edited[selectedID] = nil
                status = "BACK TO THE SAVED SOUND"
            }
            .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.purple, compact: true))
            .disabled(!isEdited)
            Rectangle().fill(LYLLTHTheme.line).frame(width: 1, height: 22)
            HStack(spacing: 3) {
                Button("SIMPLE") { simple = true }
                    .buttonStyle(LYChromeButtonStyle(active: simple, tint: LYLLTHTheme.teal, compact: true))
                Button("FULL") { simple = false }
                    .buttonStyle(LYChromeButtonStyle(active: !simple, tint: LYLLTHTheme.teal, compact: true))
            }
            .help("SIMPLE: the essentials. FULL: every control the synth has.")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(LYLLTHTheme.panel)
    }

    // MARK: Columns

    private var categoryColumn: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(categories, id: \.0) { item in
                    let isOn = item.0 == category && query.isEmpty
                    let accent = Color(hex: UInt32(item.0.accentHex))
                    Button {
                        category = item.0
                        query = ""
                    } label: {
                        HStack(spacing: 10) {
                            Rectangle().fill(accent).frame(width: 3, height: 18)
                                .shadow(color: accent.opacity(isOn ? 0.8 : 0), radius: 5)
                            Text(item.0.displayName)
                                .font(LYLLTHTheme.label(10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(isOn ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                            Spacer(minLength: 4)
                            Text("\(item.1)")
                                .font(LYLLTHTheme.value(9.5))
                                .foregroundStyle(LYLLTHTheme.dim)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(isOn ? accent.opacity(0.10) : Color.clear)
                        .overlay(alignment: .leading) { Rectangle().fill(isOn ? accent : Color.clear).frame(width: 2) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .background(LYLLTHTheme.deck)
    }

    private var presetColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(query.isEmpty ? LYLLTHTheme.dim : LYLLTHTheme.teal)
                TextField("SEARCH \(LYDrumSounds.presets.count + userPresets.count) SOUNDS", text: $query)
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .overlay(alignment: .bottom) { LYHairline() }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(presets, id: \.id) { preset in presetRow(preset).id(preset.id) }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { reader.scrollTo(selectedID, anchor: .center) }
                .onChange(of: selectedID) { _, id in reader.scrollTo(id) }
            }
            Text("↑ ↓ PLAY  ·  ← → CATEGORY  ·  ⌘RETURN LOADS")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(LYLLTHTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 26)
                .overlay(alignment: .top) { LYHairline() }
        }
        .background(LYLLTHTheme.panel)
    }

    private func presetRow(_ preset: DrumSynthPreset) -> some View {
        let isOn = preset.id == selectedID
        let accent = Color(hex: UInt32(preset.category.accentHex))
        let onTarget = target.map { LYDrumSounds.presetID(for: $0) == preset.id } ?? false
        return HStack(spacing: 8) {
            Text(preset.name.uppercased())
                .font(LYLLTHTheme.label(9.5, weight: isOn ? .bold : .medium))
                .tracking(0.6)
                .foregroundStyle(isOn ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if edited[preset.id] != nil {
                Text("EDITED").font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.purple)
            }
            if userPresets.contains(where: { $0.id == preset.id }) {
                Text("YOURS").font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.teal)
            }
            if onTarget {
                Circle().fill(accent).frame(width: 5, height: 5).shadow(color: accent, radius: 3)
                    .help("On \(target?.name ?? "the track") now")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(isOn ? accent.opacity(0.12) : Color.clear)
        .overlay(alignment: .leading) { Rectangle().fill(isOn ? accent : Color.clear).frame(width: 2) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            select(preset)
            loadSelected()
        }
        .simultaneousGesture(TapGesture().onEnded {
            select(preset)
            browsing = true
        })
    }

    private func stepPreset(_ step: Int) -> KeyPress.Result {
        guard !saveFieldFocused, !presets.isEmpty else { return .ignored }
        let index = presets.firstIndex { $0.id == selectedID } ?? (step > 0 ? -1 : presets.count)
        select(presets[min(max(index + step, 0), presets.count - 1)])
        return .handled
    }

    private func stepCategory(_ step: Int) -> KeyPress.Result {
        guard !saveFieldFocused, query.isEmpty else { return .ignored }
        let all = categories.map(\.0)
        guard let index = all.firstIndex(of: category) else { return .ignored }
        category = all[(index + step + all.count) % all.count]
        if let first = presets.first { select(first) }
        return .handled
    }

    private func select(_ preset: DrumSynthPreset) {
        selectedID = preset.id
        if query.isEmpty { category = preset.category }
        saveAsName = nil
        audition(edited[preset.id] ?? preset)
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let preset = selected {
            let accent = Color(hex: UInt32(preset.category.accentHex))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(preset.name.uppercased())
                            .font(LYLLTHTheme.label(18, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                            .shadow(color: accent.opacity(0.35), radius: 4)
                            .lineLimit(1)
                        Text(preset.category.displayName + (isEdited ? "  ·  EDITED" : "") + (isMine ? "  ·  YOURS" : ""))
                            .font(LYLLTHTheme.label(8, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(LYLLTHTheme.dim)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        AnyView(
                            DrumSynthShapeEditor(parameters: preset.parameters, accent: accent) { next in
                                change { $0.parameters = next }
                            }
                            .id(preset.id)
                        )
                        .frame(maxWidth: .infinity)
                        AnyView(
                            DrumSynthFilterEditor(preset: preset, accent: accent) { next in
                                change { $0.parameters = next }
                            }
                            .id(preset.id)
                        )
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(sections(simple: simple), id: \.title) { section in
                        knobSection(section, preset: preset)
                    }
                }
                .padding(18)
            }
        } else {
            Text("PICK A SOUND")
                .font(LYLLTHTheme.label(11, weight: .bold))
                .tracking(2)
                .foregroundStyle(LYLLTHTheme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct Section {
        var title: String
        var keys: [DrumSynthParameterKey]
        var accent: Color
        var sustain = false
    }

    /// The same groups as DrumKit's page, SIMPLE and FULL.
    private func sections(simple: Bool) -> [Section] {
        if simple {
            return [
                Section(title: "OSCILLATORS", keys: [.body, .bodyWave, .tune, .osc2Level, .osc2Wave, .osc2TuneRatio, .osc2DetuneCents], accent: LYLLTHTheme.purple),
                Section(title: "SUB / COLOR", keys: [.sub, .tone, .noise, .click, .snap], accent: LYLLTHTheme.teal),
                Section(title: "ENVELOPE", keys: [.attack, .decay, .release, .ampHold], accent: LYLLTHTheme.indigo, sustain: true),
                Section(title: "LFO", keys: [.pitchLfoDepth, .pitchLfoRate], accent: LYLLTHTheme.indigo),
                Section(title: "OUTPUT", keys: [.level, .drive, .distortionType, .filterFreq, .filterType], accent: LYLLTHTheme.purple)
            ]
        }
        return [
            Section(title: "AMP", keys: [.level, .attack, .decay, .release, .ampHold, .ampCurve, .punch], accent: LYLLTHTheme.teal),
            Section(title: "PITCH", keys: [.tune, .pitchEnvStartFreq, .pitchEnvEndFreq, .pitchEnvDecay, .pitchEnvCurve, .pitchEnvHold, .pitchEnv2End, .pitchEnv2Decay, .pitchLfoDepth, .pitchLfoRate], accent: LYLLTHTheme.indigo),
            Section(title: "SOURCE / LAYERS", keys: [.body, .bodyWave, .osc2Level, .osc2TuneRatio, .osc2DetuneCents, .osc2Wave, .sub, .tone, .noise, .noiseColor, .noiseAttack, .noiseDecay, .click, .snap, .snapFrequency, .referenceMix, .referenceToneShape], accent: LYLLTHTheme.purple),
            Section(title: "FILTER", keys: [.filterFreq, .filterQ, .filterType, .filterEnvAmt, .filterEnvDecay, .noiseFilterFreq, .noiseFilterQ, .noiseFilterType], accent: LYLLTHTheme.teal),
            Section(title: "MODAL", keys: [.modal, .modalTune, .modalDecay, .modalTone], accent: LYLLTHTheme.purple),
            Section(title: "MOD", keys: [.fm, .fmRatio, .ringMod, .ringModFreq], accent: LYLLTHTheme.indigo),
            Section(title: "SPACE", keys: [.verbAmt, .verbSize, .verbTone, .stereoWidth, .pan], accent: LYLLTHTheme.teal),
            Section(title: "OUTPUT", keys: [.drive, .distortionType, .bitCrush, .comp], accent: LYLLTHTheme.purple)
        ]
    }

    private func knobSection(_ section: Section, preset: DrumSynthPreset) -> some View {
        // 12 pt from title to knobs (was 8): a knob turned up draws its lit arc
        // across the top of its ring, and at 8 pt that arc crowded the title,
        // so a row read tighter than an identical row of quiet knobs. The
        // extra top padding keeps the title closer to its own knobs (12) than
        // to the labels of the row above (22), so it still groups downward.
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle().fill(section.accent.opacity(0.6)).frame(width: 16, height: 1)
                Text(section.title)
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 8), alignment: .leading, spacing: 10) {
                ForEach(section.keys, id: \.self) { key in control(key, preset: preset, accent: section.accent) }
                if section.sustain { sustainKnob(preset, accent: section.accent) }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func control(_ key: DrumSynthParameterKey, preset: DrumSynthPreset, accent: Color) -> some View {
        if let definition = DrumSynthParameterMetadata.definition(for: key) {
            let value = Binding(
                get: { DrumSynthParameterAccess.normalizedValue(for: key, in: selected ?? preset) },
                set: { next in change { DrumSynthParameterAccess.setNormalizedValue(next, for: key, in: &$0) } }
            )
            let text = { DrumSynthParameterAccess.displayValue(for: key, in: selected ?? preset) }
            let options = DrumSynthParameterAccess.optionCount(for: definition.valueType)
            if options > 0 {
                DrumSynthOptionControlView(label: definition.displayLabel, valueText: text, value: value, optionCount: options, accent: accent)
            } else {
                DrumSynthKnobView(label: definition.displayLabel, valueText: text, value: value, accent: accent,
                                  bloom: accent == LYLLTHTheme.indigo)
            }
        }
    }

    private func sustainKnob(_ preset: DrumSynthPreset, accent: Color) -> some View {
        DrumSynthKnobView(
            label: "SUSTAIN",
            valueText: { String(format: "%.2F", (selected ?? preset).parameters.sustain ?? 0) },
            value: Binding(
                get: { min(max((selected ?? preset).parameters.sustain ?? 0, 0), 1) },
                set: { next in change { $0.parameters.sustain = (next * 100).rounded() / 100 } }
            ),
            accent: accent
        )
    }

    // MARK: Changes

    /// Edits the selected sound and plays it once the knob settles.
    private func change(_ edit: (inout DrumSynthPreset) -> Void) {
        guard var preset = selected else { return }
        edit(&preset)
        preset.version = DrumSynthPresetLibrary.presetFormatVersion
        edited[selectedID] = preset
        status = "EDITED  ·  LOAD PUTS THIS VERSION ON THE TRACK"
        auditionWork?.cancel()
        let work = DispatchWorkItem { audition(preset) }
        auditionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func loadSelected() {
        guard let targetID, let preset = selected, let track = target else { return }
        let custom = isEdited || isMine
        var sound = preset
        if isEdited && !isMine {
            // An edited factory sound gets its own id, so the factory one
            // stays itself on every other track.
            sound.id = preset.id + "_edit_" + String(UUID().uuidString.prefix(6)).lowercased()
        }
        load(targetID, sound, custom)
        status = "LOADED ON " + track.name
    }

    private func commitSaveAs() {
        guard let name = saveAsName?.trimmingCharacters(in: .whitespaces), !name.isEmpty, var preset = selected else { return }
        preset.name = name.uppercased()
        if !isMine { preset.id = "user_" + UUID().uuidString.prefix(8).lowercased() }
        do {
            try LYDrumUserPresets.save(preset)
            userPresets = LYDrumUserPresets.all()
            edited[selectedID] = nil
            selectedID = preset.id
            category = preset.category
            saveAsName = nil
            status = "SAVED TO YOUR SOUNDS"
        } catch {
            status = "COULD NOT SAVE: " + error.localizedDescription.uppercased()
        }
    }

    // MARK: Target menu

    @ViewBuilder
    private var targetMenu: some View {
        if targetMenuOpen {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { targetMenuOpen = false }
                VStack(alignment: .leading, spacing: 0) {
                    Text("LOAD INTO")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(LYLLTHTheme.teal)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                    LYNightshapeMenuDivider()
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(tracks) { track in
                                let isOn = track.id == targetID
                                Button {
                                    targetID = track.id
                                    targetMenuOpen = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(track.name.uppercased())
                                            .font(LYLLTHTheme.label(9.5, weight: .bold))
                                            .tracking(0.8)
                                            .foregroundStyle(isOn ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                                        Spacer(minLength: 6)
                                        Text(LYDrumSounds.soundName(for: track) ?? "")
                                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                                            .tracking(0.8)
                                            .foregroundStyle(LYLLTHTheme.dim)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .background(isOn ? LYLLTHTheme.teal.opacity(0.10) : Color.clear)
                                    .overlay(alignment: .leading) { Rectangle().fill(isOn ? LYLLTHTheme.teal : Color.clear).frame(width: 2) }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 360)
                }
                .frame(width: 300)
                .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
                .offset(x: 94, y: 44)
            }
        }
    }
}
