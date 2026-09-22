import SwiftUI

struct WorkspaceView: View {
    @Binding var document: LYLLTHSessionDocument
    @EnvironmentObject private var audio: AudioEngineController
    @EnvironmentObject private var plugins: AudioUnitCatalog

    @State private var selectedTrackID: UUID?
    @State private var selectedBrowserGroup = "NIGHTSHAPE"
    @State private var mixerHeight: CGFloat = 220

    private var selectedTrackBinding: Binding<LYTrack>? {
        guard let selectedTrackID,
              let index = document.session.tracks.firstIndex(where: { $0.id == selectedTrackID }) else {
            return nil
        }
        return $document.session.tracks[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(session: $document.session)
                .environmentObject(audio)

            HSplitView {
                BrowserPanel(selection: $selectedBrowserGroup)
                    .environmentObject(plugins)
                    .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)

                VSplitView {
                    ArrangementView(
                        session: $document.session,
                        selectedTrackID: $selectedTrackID,
                        currentStep: audio.currentStep,
                        isPlaying: audio.isPlaying
                    )
                    .frame(minHeight: 300)

                    MixerView(session: $document.session, selectedTrackID: $selectedTrackID)
                        .frame(minHeight: 160, idealHeight: mixerHeight, maxHeight: 300)
                }

                InspectorPanel(track: selectedTrackBinding)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 330)
            }

            StatusBar(error: audio.startupError, sampleRate: document.session.sampleRate, bitDepth: document.session.bitDepth)
        }
        .background(LYLLTHTheme.background)
        .frame(minWidth: 1080, minHeight: 680)
        .onAppear {
            selectedTrackID = selectedTrackID ?? document.session.tracks.first?.id
            audio.prepare(document.session)
            plugins.scan()
        }
        .onChange(of: document.session.bpm) { _, newValue in
            audio.updateTempo(newValue)
        }
    }
}

private struct TransportBar: View {
    @Binding var session: LYLLTHSession
    @EnvironmentObject private var audio: AudioEngineController

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LYLLTH")
                    .font(.system(size: 21, weight: .bold, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(
                        LinearGradient(colors: [LYLLTHTheme.teal, LYLLTHTheme.indigo, LYLLTHTheme.purple], startPoint: .leading, endPoint: .trailing)
                    )
                Text("NIGHTSHAPE AUDIO WORKSTATION")
                    .font(LYLLTHTheme.label(8))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .frame(width: 240, alignment: .leading)

            Button {
                audio.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(TransportButtonStyle(active: false))

            Button {
                audio.togglePlayback()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(TransportButtonStyle(active: audio.isPlaying))

            Text(audio.timecode)
                .font(LYLLTHTheme.value(22, weight: .light))
                .foregroundStyle(LYLLTHTheme.text)
                .frame(width: 112, alignment: .leading)

            Divider().overlay(LYLLTHTheme.lineStrong).frame(height: 34)

            HStack(spacing: 6) {
                TextField("BPM", value: $session.bpm, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.value(18, weight: .light))
                    .foregroundStyle(LYLLTHTheme.text)
                    .frame(width: 48)
                Text("BPM")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.teal)
            }

            Text("\(session.numerator)/\(session.denominator)")
                .font(LYLLTHTheme.value(15))
                .foregroundStyle(LYLLTHTheme.secondary)

            Spacer()

            HStack(spacing: 14) {
                HeaderAction(icon: "metronome", label: "CLICK")
                HeaderAction(icon: "arrow.triangle.2.circlepath", label: "LOOP")
                HeaderAction(icon: "record.circle", label: "RECORD", tint: LYLLTHTheme.purple)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1) }
    }
}

private struct HeaderAction: View {
    let icon: String
    let label: String
    var tint = LYLLTHTheme.secondary

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(label).font(LYLLTHTheme.label(7, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(tint)
        .frame(width: 52)
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(active ? LYLLTHTheme.background : LYLLTHTheme.text)
            .frame(width: 36, height: 36)
            .background(active ? LYLLTHTheme.teal : LYLLTHTheme.panelRaised)
            .overlay(Rectangle().stroke(active ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct BrowserPanel: View {
    @Binding var selection: String
    @EnvironmentObject private var plugins: AudioUnitCatalog

    private let groups = ["NIGHTSHAPE", "INSTRUMENTS", "AUDIO EFFECTS", "PLUG-INS", "FILES"]
    private let nightshape = [
        "DRUM SYNTH", "SOUND ORACLE", "EQUALIZER", "COMPRESSOR", "TAPE SATURATION",
        "SONIC DECIMATOR", "CHORUS", "PLATE REVERB", "SIGNAL BLOOM", "PUMP",
        "VOID GATE", "FRACTURE", "FILTER", "DELAY", "DEADLOCK", "SHEAR",
        "STACK", "SPLIT FIELD", "UNDERTOW", "ANVIL", "STRIKE", "FINALE"
    ]

    var body: some View {
        VStack(spacing: 0) {
            LYSectionTitle(text: "BROWSER")
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(groups, id: \.self) { group in
                        Button {
                            selection = group
                        } label: {
                            HStack {
                                Rectangle()
                                    .fill(selection == group ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong)
                                    .frame(width: 2, height: 18)
                                Text(group)
                                    .font(LYLLTHTheme.label(9, weight: .bold))
                                    .tracking(0.7)
                                Spacer()
                                Image(systemName: selection == group ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(selection == group ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if selection == group {
                            ForEach(items(for: group), id: \.self) { item in
                                Text(item)
                                    .font(LYLLTHTheme.label(8))
                                    .foregroundStyle(LYLLTHTheme.secondary)
                                    .lineLimit(1)
                                    .padding(.leading, 24)
                                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                    .background(LYLLTHTheme.background.opacity(0.35))
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
            HStack {
                Circle()
                    .fill(plugins.isScanning ? LYLLTHTheme.indigo : LYLLTHTheme.teal)
                    .frame(width: 5, height: 5)
                Text(plugins.isScanning ? "SCANNING AUDIO UNITS" : "\(plugins.instruments.count + plugins.effects.count) AUDIO UNITS")
                    .font(LYLLTHTheme.label(7))
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
            }
            .padding(10)
            .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.line).frame(height: 1) }
        }
        .background(LYLLTHTheme.panel)
    }

    private func items(for group: String) -> [String] {
        switch group {
        case "NIGHTSHAPE": return nightshape
        case "INSTRUMENTS": return ["DRUMKIT", "POLY SYNTH", "CHORD ENGINE"]
        case "AUDIO EFFECTS": return plugins.effects.prefix(24).map(\.name)
        case "PLUG-INS": return (plugins.instruments + plugins.effects).prefix(30).map(\.name)
        default: return ["SONGS", "AUDIO", "PRESETS"]
        }
    }
}

private struct ArrangementView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?
    let currentStep: Int
    let isPlaying: Bool

    private let headerWidth: CGFloat = 176
    private let beats = 64
    private let beatWidth: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            LYSectionTitle(text: "ARRANGEMENT")
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    ruler
                    ForEach($session.tracks) { $track in
                        trackLane(track: $track)
                    }
                    automationLane
                }
                .frame(minWidth: headerWidth + CGFloat(beats) * beatWidth, alignment: .topLeading)
            }
            .background(LYLLTHTheme.background)
        }
    }

    private var ruler: some View {
        HStack(spacing: 0) {
            Text("TRACKS")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LYLLTHTheme.dim)
                .padding(.leading, 12)
                .frame(width: headerWidth, height: 30, alignment: .leading)
                .background(LYLLTHTheme.panel)

            HStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { bar in
                    Text("\(bar + 1)")
                        .font(LYLLTHTheme.value(8))
                        .foregroundStyle(bar % 4 == 0 ? LYLLTHTheme.secondary : LYLLTHTheme.dim)
                        .frame(width: beatWidth * 4, height: 30, alignment: .leading)
                        .padding(.leading, 4)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(bar % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line).frame(width: 1)
                        }
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1) }
    }

    private func trackLane(track: Binding<LYTrack>) -> some View {
        let accent = LYLLTHTheme.accent(track.wrappedValue.accent)
        let selected = selectedTrackID == track.wrappedValue.id

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.wrappedValue.name)
                        .font(LYLLTHTheme.label(10, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                    Text(track.wrappedValue.kind.label)
                        .font(LYLLTHTheme.label(7))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(String(format: "%+.1f", track.wrappedValue.volumeDB))
                    .font(LYLLTHTheme.value(8))
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .padding(.horizontal, 9)
            .frame(width: headerWidth, height: 58)
            .background(selected ? LYLLTHTheme.panelRaised : LYLLTHTheme.panel)
            .contentShape(Rectangle())
            .onTapGesture { selectedTrackID = track.wrappedValue.id }

            ZStack(alignment: .leading) {
                beatGrid(height: 58)
                ForEach(track.wrappedValue.clips) { clip in
                    ClipView(clip: clip, accent: accent)
                        .frame(width: max(beatWidth * clip.lengthBeats - 3, 20), height: 42)
                        .offset(x: beatWidth * clip.startBeat + 1)
                }

                if isPlaying {
                    Rectangle()
                        .fill(LYLLTHTheme.text.opacity(0.85))
                        .frame(width: 1, height: 58)
                        .offset(x: CGFloat(currentStep) * beatWidth)
                }
            }
            .frame(width: CGFloat(beats) * beatWidth, height: 58)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(LYLLTHTheme.line).frame(height: 1) }
    }

    private var automationLane: some View {
        HStack(spacing: 0) {
            HStack {
                Rectangle().fill(LYLLTHTheme.purple).frame(width: 3)
                Text("AUTOMATION")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.secondary)
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(width: headerWidth, height: 44)
            .background(LYLLTHTheme.panel)

            beatGrid(height: 44)
                .overlay(alignment: .leading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 34))
                        path.addCurve(
                            to: CGPoint(x: beatWidth * 24, y: 10),
                            control1: CGPoint(x: beatWidth * 7, y: 34),
                            control2: CGPoint(x: beatWidth * 14, y: 9)
                        )
                    }
                    .stroke(LYLLTHTheme.purple.opacity(0.8), lineWidth: 1.5)
                }
                .frame(width: CGFloat(beats) * beatWidth, height: 44)
        }
    }

    private func beatGrid(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<beats, id: \.self) { beat in
                Rectangle()
                    .fill(beat % 8 < 4 ? LYLLTHTheme.background : LYLLTHTheme.panel.opacity(0.42))
                    .frame(width: beatWidth, height: height)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(beat % 4 == 0 ? LYLLTHTheme.lineStrong : LYLLTHTheme.line)
                            .frame(width: 1)
                    }
            }
        }
    }
}

private struct ClipView: View {
    let clip: LYClip
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(accent.opacity(0.10))
            Rectangle().stroke(accent.opacity(0.88), lineWidth: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.name)
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    ForEach(0..<previewStepCount, id: \.self) { index in
                        Rectangle()
                            .fill(previewStepIsActive(index) ? accent : LYLLTHTheme.line)
                            .frame(width: 2, height: previewBarHeight(index))
                    }
                }
            }
            .padding(7)
        }
    }

    private var previewStepCount: Int {
        min(16, clip.steps?.count ?? 12)
    }

    private func previewStepIsActive(_ index: Int) -> Bool {
        if let steps = clip.steps, steps.indices.contains(index) {
            return steps[index]
        }
        return index % 3 == 0
    }

    private func previewBarHeight(_ index: Int) -> CGFloat {
        CGFloat(4 + (index % 4) * 2)
    }
}

private struct MixerView: View {
    @Binding var session: LYLLTHSession
    @Binding var selectedTrackID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            LYSectionTitle(text: "MIXER")
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach($session.tracks) { $track in
                        ChannelStrip(track: $track, isSelected: selectedTrackID == track.id)
                            .onTapGesture { selectedTrackID = track.id }
                    }
                    MasterStrip()
                }
            }
            .background(LYLLTHTheme.panel)
        }
    }
}

private struct ChannelStrip: View {
    @Binding var track: LYTrack
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text(track.name)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .foregroundStyle(LYLLTHTheme.text)
                .lineLimit(1)
            HStack(spacing: 5) {
                SmallToggle(title: "M", isOn: $track.isMuted, tint: LYLLTHTheme.purple)
                SmallToggle(title: "S", isOn: $track.isSolo, tint: LYLLTHTheme.teal)
            }
            Slider(value: $track.volumeDB, in: -48...6)
                .controlSize(.mini)
                .frame(width: 94)
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 94)
            Text(String(format: "%+.1f dB", track.volumeDB))
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.secondary)
        }
        .padding(.vertical, 9)
        .frame(width: 96)
        .background(isSelected ? LYLLTHTheme.panelRaised : LYLLTHTheme.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(LYLLTHTheme.accent(track.accent)).frame(width: isSelected ? 3 : 1)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.line).frame(width: 1) }
    }
}

private struct MasterStrip: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("MAIN")
                .font(LYLLTHTheme.label(8, weight: .bold))
                .foregroundStyle(LYLLTHTheme.text)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach([0.35, 0.58, 0.78, 0.48, 0.86, 0.66], id: \.self) { value in
                    Rectangle()
                        .fill(LinearGradient(colors: [LYLLTHTheme.teal, LYLLTHTheme.indigo], startPoint: .bottom, endPoint: .top))
                        .frame(width: 4, height: 88 * value)
                }
            }
            .frame(height: 94, alignment: .bottom)
            Text("−6.2 dB")
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.secondary)
        }
        .padding(.vertical, 9)
        .frame(width: 96)
        .background(LYLLTHTheme.background)
        .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.28), lineWidth: 1))
    }
}

private struct SmallToggle: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button(title) { isOn.toggle() }
            .buttonStyle(.plain)
            .font(LYLLTHTheme.label(8, weight: .bold))
            .foregroundStyle(isOn ? LYLLTHTheme.background : LYLLTHTheme.secondary)
            .frame(width: 24, height: 20)
            .background(isOn ? tint : LYLLTHTheme.background)
            .overlay(Rectangle().stroke(isOn ? tint : LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

private struct InspectorPanel: View {
    var track: Binding<LYTrack>?

    var body: some View {
        VStack(spacing: 0) {
            LYSectionTitle(text: "INSPECTOR")
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.wrappedValue.name)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LYLLTHTheme.text)
                            Text(track.wrappedValue.kind.label)
                                .font(LYLLTHTheme.label(8, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(LYLLTHTheme.accent(track.wrappedValue.accent))
                        }

                        ParameterRow(title: "VOLUME", value: String(format: "%+.1f dB", track.wrappedValue.volumeDB))
                        Slider(value: track.volumeDB, in: -48...6)
                        ParameterRow(title: "PAN", value: panText(track.wrappedValue.pan))
                        Slider(value: track.pan, in: -1...1)

                        Divider().overlay(LYLLTHTheme.line)
                        Text("INSERTS")
                            .font(LYLLTHTheme.label(8, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(LYLLTHTheme.secondary)

                        if track.wrappedValue.inserts.isEmpty {
                            Text("DROP AN EFFECT HERE")
                                .font(LYLLTHTheme.label(8))
                                .foregroundStyle(LYLLTHTheme.dim)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        } else {
                            ForEach(track.wrappedValue.inserts) { insert in
                                InsertRow(slot: insert)
                            }
                        }
                    }
                    .padding(14)
                }
            } else {
                Text("SELECT A TRACK")
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LYLLTHTheme.panel)
    }

    private func panText(_ pan: Double) -> String {
        if abs(pan) < 0.01 { return "CENTER" }
        return pan < 0 ? "L \(Int(abs(pan) * 100))" : "R \(Int(abs(pan) * 100))"
    }
}

private struct ParameterRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(LYLLTHTheme.label(8, weight: .bold)).foregroundStyle(LYLLTHTheme.secondary)
            Spacer()
            Text(value).font(LYLLTHTheme.value(10)).foregroundStyle(LYLLTHTheme.text)
        }
    }
}

private struct InsertRow: View {
    let slot: LYPluginSlot

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LYLLTHTheme.teal).frame(width: 2, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(LYLLTHTheme.label(8, weight: .bold)).foregroundStyle(LYLLTHTheme.text)
                Text(slot.manufacturer).font(LYLLTHTheme.label(7)).foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            Text(slot.isBypassed ? "OFF" : "ON")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .foregroundStyle(slot.isBypassed ? LYLLTHTheme.dim : LYLLTHTheme.teal)
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(LYLLTHTheme.background)
        .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }
}

private struct StatusBar: View {
    let error: String?
    let sampleRate: Double
    let bitDepth: Int

    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(error == nil ? LYLLTHTheme.teal : LYLLTHTheme.purple).frame(width: 5, height: 5)
            Text(error ?? "AUDIO ENGINE ONLINE")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .foregroundStyle(error == nil ? LYLLTHTheme.secondary : LYLLTHTheme.purple)
                .lineLimit(1)
            Spacer()
            Text("\(Int(sampleRate / 1000)) kHz · \(bitDepth)-BIT")
                .font(LYLLTHTheme.label(7))
                .foregroundStyle(LYLLTHTheme.dim)
            Text("MACOS · NATIVE")
                .font(LYLLTHTheme.label(7, weight: .bold))
                .foregroundStyle(LYLLTHTheme.dim)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(LYLLTHTheme.background)
        .overlay(alignment: .top) { Rectangle().fill(LYLLTHTheme.line).frame(height: 1) }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
