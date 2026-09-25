import SwiftUI
import NightshapeAudioEngine

// MARK: - Meters and clip indicators

/// One place that reads the engine's meters, twenty times a second, for every
/// strip on screen. Peaks latch until clicked, the way Logic's do, and a
/// channel that reaches 0 dBFS latches its clip indicator.
@MainActor
final class LYMeterStore: ObservableObject {
    struct Reading: Equatable {
        /// 0…1 display height, −60 dBFS to 0 dBFS.
        var level: Double = 0
        /// Highest peak since the last reset, dBFS.
        var peakHoldDB: Double = -.infinity
        var clipped = false
    }

    static let mainKey = UUID(uuidString: "00000000-0000-0000-0000-00000000A1A1")!

    @Published private(set) var readings: [UUID: Reading] = [:]
    private var channels: [UUID: Int] = [:]
    private var timer: Timer?

    func track(_ session: LYLLTHSession) {
        var next: [UUID: Int] = [:]
        for track in session.tracks {
            if let index = LYFXBridge.engineIndex(for: track.id, in: session) { next[track.id] = index }
        }
        channels = next
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func reading(for id: UUID) -> Reading? { readings[id] }

    func reset(_ id: UUID) {
        readings[id]?.peakHoldDB = -.infinity
        readings[id]?.clipped = false
    }

    func resetAll() {
        for key in readings.keys { reset(key) }
    }

    private func poll() {
        let engine = NightshapeAudioEngine.shared
        var next = readings
        for (id, index) in channels {
            let linear = Double(engine.trackOutputPeak(trackIndex: index))
            update(&next, id: id, dB: linear > 0.000_001 ? 20 * log10(linear) : -120, clipFlag: linear >= 1.0)
        }
        let main = engine.state.outputMeter
        update(&next, id: Self.mainKey, dB: Double(main.peakDB), clipFlag: main.isClipping || main.peakDB >= -0.05)
        if next != readings { readings = next }
    }

    private func update(_ values: inout [UUID: Reading], id: UUID, dB: Double, clipFlag: Bool) {
        var reading = values[id] ?? Reading()
        reading.level = min(max((dB + 60) / 60, 0), 1)
        if dB > reading.peakHoldDB { reading.peakHoldDB = dB }
        if clipFlag { reading.clipped = true }
        values[id] = reading
    }
}

/// Logic's peak box: the highest level since you last clicked it. Once the
/// channel reaches 0 dBFS it latches in the record pink until clicked.
struct LYClipIndicator: View {
    let reading: LYMeterStore.Reading?
    let reset: () -> Void

    var body: some View {
        let clipped = reading?.clipped ?? false
        let peak = reading?.peakHoldDB ?? -.infinity
        Button(action: reset) {
            Text(peak < -59.5 ? "−∞" : String(format: "%.1f", peak))
                .font(LYLLTHTheme.value(10))
                .foregroundStyle(clipped ? LYLLTHTheme.background : LYLLTHTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(clipped ? LYLLTHTheme.record : Color.black.opacity(0.35))
                .overlay(Rectangle().stroke(clipped ? LYLLTHTheme.record : LYLLTHTheme.lineStrong, lineWidth: 1))
                .lyBloom(LYLLTHTheme.record, isOn: clipped)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(clipped ? "Clipped. Click to clear." : "Peak since last cleared. Click to clear.")
        .accessibilityLabel(clipped ? "Clipped" : "Peak")
    }
}

/// Thin two-rail meter with a clip lamp at the top.
struct LYStripMeter: View {
    let reading: LYMeterStore.Reading?
    var tint = LYLLTHTheme.teal

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                Rectangle()
                    .fill(reading?.clipped == true ? LYLLTHTheme.record : LYLLTHTheme.off.opacity(0.55))
                    .frame(height: 4)
                    .lyBloom(LYLLTHTheme.record, isOn: reading?.clipped == true)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach([0.94, 1.0], id: \.self) { multiplier in
                        ZStack(alignment: .bottom) {
                            Rectangle().fill(LYLLTHTheme.off.opacity(0.55))
                            if let reading {
                                let level = min(reading.level * multiplier, 1)
                                Rectangle()
                                    .fill(level > 0.97 ? LYLLTHTheme.record : tint)
                                    .frame(height: (geometry.size.height - 6) * level)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Inspector

/// Logic's inspector: the selected channel's strip beside the strip it feeds.
struct ChannelStripInspector: View {
    @Binding var session: LYLLTHSession
    let selectedTrackID: UUID?
    @ObservedObject var meters: LYMeterStore
    let openFX: (FXKind, FXTarget) -> Void
    let toggleFX: (FXKind, FXTarget) -> Void
    let openPicker: (FXTarget) -> Void
    let openSynth: (UUID) -> Void
    let openDrums: (UUID) -> Void
    let close: () -> Void

    private enum RoutingMenu { case addSend(UUID), output(UUID) }
    @State private var routingMenu: RoutingMenu?
    @State private var anchors: [String: CGRect] = [:]
    static let space = "LYInspector"

    var body: some View {
        VStack(spacing: 0) {
            LYPanelHeader(title: "INSPECTOR", actionIcon: "xmark", action: close)
            HStack(spacing: 0) {
                if let index = session.tracks.firstIndex(where: { $0.id == selectedTrackID }) {
                    trackStrip(index: index)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 22, weight: .ultraLight))
                        Text("SELECT A TRACK")
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.4)
                    }
                    .foregroundStyle(LYLLTHTheme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1)
                mainStrip
            }
        }
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(LYMenuAnchorKey.self) { anchors = $0 }
        .overlay { routingOverlay }
        .onChange(of: selectedTrackID) { _, _ in routingMenu = nil }
    }

    // MARK: Routing

    @ViewBuilder
    private var routingOverlay: some View {
        if let routingMenu {
            switch routingMenu {
            case .addSend(let id):
                LYDropdownOverlay(anchor: anchors["inspector.addSend"], dismiss: { self.routingMenu = nil }) {
                    busMenu(for: id, title: "SEND TO", current: nil) { bus in addSend(from: id, to: bus) }
                }
            case .output(let id):
                LYDropdownOverlay(anchor: anchors["inspector.output"], dismiss: { self.routingMenu = nil }) {
                    busMenu(for: id, title: "OUTPUT", current: session.tracks.first { $0.id == id }?.outputBusID, includeMain: true) { bus in
                        setOutput(of: id, to: bus)
                    }
                }
            }
        }
    }

    /// AUX RETURNs to pick from, MAIN when choosing an output, and NEW BUS.
    private func busMenu(for id: UUID, title: String, current: UUID?, includeMain: Bool = false, pick: @escaping (UUID?) -> Void) -> some View {
        let track = session.tracks.first { $0.id == id }
        let buses = track.map { LYChannelMap.buses(for: $0, in: session) } ?? []
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(LYLLTHTheme.dim)
                .padding(.bottom, 2)
            if includeMain { menuRow("MAIN", selected: current == nil) { pick(nil) } }
            ForEach(buses) { bus in
                menuRow(bus.name, selected: current == bus.id) { pick(bus.id) }
            }
            menuRow("+ NEW BUS", selected: false) { pick(makeBus()) }
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
    }

    private func menuRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            routingMenu = nil
        } label: {
            Text(title)
                .font(LYLLTHTheme.label(8.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(selected ? LYLLTHTheme.teal : LYLLTHTheme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .padding(.horizontal, 6)
                .background(LYLLTHTheme.teal.opacity(selected ? 0.12 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A new AUX RETURN at the end of the track list; returns its id.
    private func makeBus() -> UUID {
        let count = session.tracks.filter { $0.kind == .auxiliary }.count + 1
        let letter = String(Character(UnicodeScalar(64 + min(count, 26))!))
        let bus = LYTrack(name: "RETURN " + letter, kind: .auxiliary, accent: .teal, volumeDB: 0)
        session.tracks.append(bus)
        return bus.id
    }

    private func addSend(from id: UUID, to bus: UUID?) {
        guard let bus, let index = session.tracks.firstIndex(where: { $0.id == id }) else { return }
        var sends = session.tracks[index].sends ?? []
        guard !sends.contains(where: { $0.busID == bus }) else { return }
        sends.append(LYBusSend(busID: bus))
        session.tracks[index].sends = sends
    }

    private func setOutput(of id: UUID, to bus: UUID?) {
        guard let index = session.tracks.firstIndex(where: { $0.id == id }) else { return }
        session.tracks[index].outputBusID = bus
    }

    private func busSendRows(index: Int) -> [LYChannelStrip.BusSendRow] {
        let track = session.tracks[index]
        return (track.sends ?? []).compactMap { send in
            guard let busIndex = session.tracks.firstIndex(where: { $0.id == send.busID && $0.kind == .auxiliary }) else { return nil }
            return LYChannelStrip.BusSendRow(
                id: send.busID,
                name: session.tracks[busIndex].name,
                color: LYLLTHTheme.trackAccent(position: busIndex),
                level: Binding(
                    get: { session.tracks[index].sends?.first { $0.busID == send.busID }?.level ?? 0 },
                    set: { value in
                        guard let at = session.tracks[index].sends?.firstIndex(where: { $0.busID == send.busID }) else { return }
                        session.tracks[index].sends?[at].level = value
                    }
                ),
                remove: { session.tracks[index].sends?.removeAll { $0.busID == send.busID } }
            )
        }
    }

    private func outputName(for track: LYTrack) -> String {
        guard let id = track.outputBusID, let bus = session.tracks.first(where: { $0.id == id && $0.kind == .auxiliary }) else { return "MAIN" }
        return bus.name
    }

    private func trackStrip(index: Int) -> some View {
        let track = session.tracks[index]
        let target = FXTarget.track(track.id)
        let hasChannel = LYFXBridge.engineIndex(for: track.id, in: session) != nil
        let rack = track.fx ?? LYFXRack()
        return LYChannelStrip(
            name: track.name,
            accent: LYLLTHTheme.trackAccent(position: index),
            source: sourceName(for: track),
            openSource: track.kind == .drumkit ? { openDrums(track.id) }
                : (track.kind == .instrument || track.synth != nil ? { openSynth(track.id) } : nil),
            rack: rack,
            reverb: session.reverb ?? .neutral,
            isMain: false,
            hasChannel: hasChannel,
            output: outputName(for: track),
            chooseOutput: { routingMenu = .output(track.id) },
            busSends: busSendRows(index: index),
            addSend: { routingMenu = .addSend(track.id) },
            volumeDB: $session.tracks[index].volumeDB,
            pan: $session.tracks[index].pan,
            isMuted: $session.tracks[index].isMuted,
            isSolo: $session.tracks[index].isSolo,
            isArmed: track.kind == .auxiliary ? nil : $session.tracks[index].isArmed,
            reverbSend: Binding(
                get: { session.tracks[index].fx?.reverbSend ?? 0 },
                set: { amount in
                    var next = session.tracks[index].fx ?? LYFXRack()
                    next.reverbSend = amount
                    session.tracks[index].fx = next
                    if let engineIndex = LYFXBridge.engineIndex(for: track.id, in: session) {
                        NightshapeAudioEngine.shared.setReverbSend(trackIndex: engineIndex, amount: amount)
                    }
                }
            ),
            reading: meters.reading(for: track.id),
            resetClip: { meters.reset(track.id) },
            openFX: { openFX($0, target) },
            toggleFX: { toggleFX($0, target) },
            openPicker: { openPicker(target) }
        )
    }

    private var mainStrip: some View {
        LYChannelStrip(
            name: "MAIN",
            accent: LYLLTHTheme.chromeText,
            source: nil,
            openSource: nil,
            rack: session.mainFX ?? LYFXRack(),
            reverb: session.reverb ?? .neutral,
            isMain: true,
            hasChannel: true,
            output: "OUT 1–2",
            volumeDB: Binding(
                get: { session.mainVolumeDB ?? 0 },
                set: { session.mainVolumeDB = min($0, 0) }
            ),
            pan: nil,
            isMuted: nil,
            isSolo: nil,
            isArmed: nil,
            reverbSend: nil,
            reading: meters.reading(for: LYMeterStore.mainKey),
            resetClip: { meters.reset(LYMeterStore.mainKey) },
            openFX: { openFX($0, .main) },
            toggleFX: { toggleFX($0, .main) },
            openPicker: { openPicker(.main) }
        )
    }

    private func sourceName(for track: LYTrack) -> String {
        switch track.kind {
        case .audio: return track.inputName ?? "NO INPUT"
        case .auxiliary:
            let feeds = session.tracks.filter { $0.outputBusID == track.id || ($0.sends ?? []).contains { $0.busID == track.id } }.count
            return feeds == 0 ? "NO INPUTS" : feeds == 1 ? "1 INPUT" : "\(feeds) INPUTS"
        case .drumkit, .instrument:
            if let synth = track.synth { return "LYLLTH · " + synth.name }
            if let drum = LYDrumSounds.preset(id: LYDrumSounds.presetID(for: track)) { return "DRUM · " + drum.name }
            if track.isChordTrack == true { return "CHORD ENGINE" }
            return (track.synthPresetID ?? "SYNTH").uppercased()
        }
    }
}

/// One channel strip, top to bottom in Logic's order: EQ, source, inserts,
/// sends, output, pan, peak, fader and meter, M / S / R, name.
private struct LYChannelStrip: View {
    struct BusSendRow: Identifiable {
        let id: UUID
        let name: String
        let color: Color
        let level: Binding<Float>
        let remove: () -> Void
    }

    let name: String
    let accent: Color
    let source: String?
    let openSource: (() -> Void)?
    let rack: LYFXRack
    let reverb: ReverbState
    let isMain: Bool
    let hasChannel: Bool
    let output: String
    var chooseOutput: (() -> Void)? = nil
    var busSends: [BusSendRow] = []
    var addSend: (() -> Void)? = nil
    @Binding var volumeDB: Double
    var pan: Binding<Double>?
    var isMuted: Binding<Bool>?
    var isSolo: Binding<Bool>?
    var isArmed: Binding<Bool>?
    var reverbSend: Binding<Float>?
    let reading: LYMeterStore.Reading?
    let resetClip: () -> Void
    let openFX: (FXKind) -> Void
    let toggleFX: (FXKind) -> Void
    let openPicker: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if hasChannel {
                EQCurveThumbnail(bands: rack.bands, cuts: rack.eqCut)
                    .background(Color.black.opacity(0.45))
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                    .contentShape(Rectangle())
                    .frame(height: 44)
                    .onTapGesture { openFX(.eq) }
                    .help("EQ. Click to open.")
            } else {
                slot("NO EQ", color: LYLLTHTheme.dim, dim: true)
                    .frame(height: 40)
            }

            if let source {
                sectionLabel(isMain ? "" : "SOURCE")
                if let openSource {
                    Button(action: openSource) {
                        slot(source, color: LYLLTHTheme.teal, dim: false)
                            .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open LYLLTH SYNTH")
                } else {
                    slot(source, color: LYLLTHTheme.text, dim: false)
                }
            }

            sectionLabel("AUDIO FX")
            if hasChannel {
                VStack(spacing: 2) {
                    ForEach(rack.chain(isMain: isMain).filter { $0 != .eq && !($0 == .reverb && !isMain) }, id: \.self) { kind in
                        insertSlot(kind)
                    }
                    Button(action: openPicker) {
                        Text("+")
                            .font(LYLLTHTheme.label(10, weight: .bold))
                            .foregroundStyle(LYLLTHTheme.dim)
                            .frame(maxWidth: .infinity)
                            .frame(height: 18)
                            .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add or remove effects")
                }
            } else {
                Text("PAST SIXTEEN CHANNELS\nNO FX")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(0.8)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .frame(maxWidth: .infinity)
            }

            if reverbSend != nil || addSend != nil {
                sectionLabel("SENDS")
                VStack(spacing: 2) {
                    if let reverbSend { sendSlot("REVERB", amount: reverbSend) }
                    ForEach(busSends) { busSendSlot($0) }
                    if let addSend {
                        Button(action: addSend) {
                            Text("+ SEND")
                                .font(LYLLTHTheme.label(7, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(LYLLTHTheme.dim)
                                .frame(maxWidth: .infinity)
                                .frame(height: 18)
                                .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .lyMenuAnchor("inspector.addSend", in: ChannelStripInspector.space)
                        .help("Send to a bus")
                    }
                }
            }

            sectionLabel("OUTPUT")
            if let chooseOutput {
                Button(action: chooseOutput) {
                    slot(output, color: output == "MAIN" ? LYLLTHTheme.text : LYLLTHTheme.teal, dim: false)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(LYLLTHTheme.dim)
                                .padding(.trailing, 5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .lyMenuAnchor("inspector.output", in: ChannelStripInspector.space)
                .help("Where this track plays: MAIN or a bus")
            } else {
                slot(output, color: LYLLTHTheme.text, dim: false)
            }

            Spacer(minLength: 4)

            if let pan {
                LYPanKnob(value: pan, accent: accent)
                    .frame(height: 38)
            }

            HStack(spacing: 4) {
                LYClipIndicator(reading: reading, reset: resetClip)
                Text(volumeDB <= -47.9 ? "−∞" : String(format: "%.1f", volumeDB))
                    .font(LYLLTHTheme.value(10))
                    .foregroundStyle(LYLLTHTheme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
            }

            HStack(alignment: .bottom, spacing: 10) {
                LYStripFader(value: $volumeDB, range: -48...(isMain ? 0 : 6), accent: accent)
                    .frame(width: 30)
                LYStripMeter(reading: hasChannel ? reading : nil, tint: accent == LYLLTHTheme.chromeText ? LYLLTHTheme.teal : accent)
                    .frame(width: 12)
            }
            .frame(height: 170)

            HStack(spacing: 4) {
                if let isMuted { LYTrackToggle(title: "M", isOn: isMuted, tint: LYLLTHTheme.purple) }
                if let isSolo { LYTrackToggle(title: "S", isOn: isSolo, tint: LYLLTHTheme.teal) }
                if let isArmed { LYTrackToggle(title: "R", isOn: isArmed, tint: LYLLTHTheme.record) }
            }
            .frame(height: 20)

            Text(name)
                .font(LYLLTHTheme.label(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(LYLLTHTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(accent.opacity(0.14))
                .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: 2).lyBloom(accent) }
        }
        .padding(.horizontal, 9)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 148)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(LYLLTHTheme.label(6.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(LYLLTHTheme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func slot(_ text: String, color: Color, dim: Bool) -> some View {
        Text(text)
            .font(LYLLTHTheme.label(7.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .frame(minHeight: 18, maxHeight: 18)
            .background(Color.black.opacity(dim ? 0.15 : 0.35))
            .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func insertSlot(_ kind: FXKind) -> some View {
        let engaged = rack.isEngaged(kind, isMain: isMain, reverb: reverb)
        let color = kind.accent == NightshapeTheme.accentHotPurple ? LYLLTHTheme.purple : kind.accent
        return HStack(spacing: 0) {
            Button { toggleFX(kind) } label: {
                Rectangle()
                    .fill(engaged ? color : Color.clear)
                    .frame(width: 5, height: 5)
                    .frame(width: 16, height: 18)
                    .overlay(alignment: .trailing) { Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 1) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(engaged ? "Bypass" : "Engage")
            Text(kind.title)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(engaged ? LYLLTHTheme.text : LYLLTHTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
                .onTapGesture { openFX(kind) }
        }
        .background(color.opacity(engaged ? 0.12 : 0.03))
        .overlay(Rectangle().stroke(engaged ? color.opacity(0.75) : LYLLTHTheme.lineStrong, lineWidth: 1))
        .help("\(kind.title). Click to open.")
    }

    private func busSendSlot(_ row: BusSendRow) -> some View {
        let level = row.level.wrappedValue
        return HStack(spacing: 4) {
            Text(row.name)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(level > 0.0001 ? LYLLTHTheme.text : LYLLTHTheme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            LYSendKnob(value: row.level, color: row.color)
                .frame(width: 18, height: 18)
            Button(action: row.remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.dim)
                    .frame(width: 12, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this send")
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(height: 22)
        .background(Color.black.opacity(0.35))
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .help("Send to \(row.name), " + (level > 0.0001 ? String(format: "%.1f dB", 20 * log10(level)) : "off") + ". Drag the knob.")
    }

    private func sendSlot(_ title: String, amount: Binding<Float>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(amount.wrappedValue > 0.0001 ? LYLLTHTheme.text : LYLLTHTheme.dim)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { openFX(.reverb) }
            LYSendKnob(value: amount, color: FXKind.reverb.accent)
                .frame(width: 18, height: 18)
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(height: 22)
        .background(Color.black.opacity(0.35))
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
        .help("Send to the shared reverb. Drag the knob; click the name to open it.")
    }
}

// MARK: - Strip parts

private struct LYPanKnob: View {
    @Binding var value: Double
    let accent: Color
    @State private var origin: Double?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1)
                Circle()
                    .trim(from: 0.5 + min(0, value) * 0.375, to: 0.5 + max(0, value) * 0.375)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Rectangle()
                    .fill(LYLLTHTheme.chrome)
                    .frame(width: 1.5, height: 9)
                    .offset(y: -6)
                    .rotationEffect(.degrees(value * 135))
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = origin ?? value
                        if origin == nil { origin = value }
                        var next = start - Double(drag.translation.height) / 100
                        if abs(next) < 0.04 { next = 0 }
                        value = min(max(next, -1), 1)
                    }
                    .onEnded { _ in origin = nil }
            )
            .onTapGesture(count: 2) { value = 0 }
            Text(abs(value) < 0.01 ? "C" : (value < 0 ? "L\(Int(abs(value) * 64))" : "R\(Int(value * 64))"))
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.text)
        }
        .help("Pan. Drag up or down; double-click to center.")
    }
}

private struct LYSendKnob: View {
    @Binding var value: Float
    let color: Color
    @State private var origin: Float?

    var body: some View {
        ZStack {
            Circle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1)
            Circle()
                .trim(from: 0.125, to: 0.125 + 0.75 * CGFloat(value))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                .rotationEffect(.degrees(90))
        }
        .lyBloom(color, isOn: value > 0.0001)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { drag in
                    let start = origin ?? value
                    if origin == nil { origin = value }
                    value = min(max(start - Float(drag.translation.height) / 120, 0), 1)
                }
                .onEnded { _ in origin = nil }
        )
        .help("\(Int((value * 100).rounded()))%")
    }
}

/// Channel fader: DrumKit's chrome cap on a hairline rail, filled in the
/// channel's colour, with 0 dB marked.
struct LYStripFader: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accent = LYLLTHTheme.teal
    @State private var origin: Double?

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let travel = geometry.size.height - 14
            let y = (1 - fraction) * travel + 7
            let zeroY = (1 - (0 - range.lowerBound) / span) * travel + 7

            ZStack(alignment: .top) {
                Rectangle().fill(LYLLTHTheme.lineStrong).frame(width: 2)
                Rectangle()
                    .fill(accent.opacity(0.75))
                    .frame(width: 2, height: max(0, geometry.size.height - y))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle().fill(LYLLTHTheme.dim).frame(width: 12, height: 1).offset(y: zeroY)
                ZStack {
                    Rectangle().fill(LYLLTHTheme.chrome)
                    Rectangle().fill(accent).frame(height: 2)
                }
                .frame(width: 26, height: 12)
                .offset(y: y - 6)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = origin ?? value
                        if origin == nil { origin = value }
                        let scale = NSEvent.modifierFlags.contains(.option) ? 0.2 : 1.0
                        value = min(max(start - Double(drag.translation.height / max(travel, 1)) * span * scale, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in origin = nil }
            )
            .onTapGesture(count: 2) { value = 0 }
            .help("Drag for level. Option for fine. Double-click for 0 dB.")
        }
    }
}
