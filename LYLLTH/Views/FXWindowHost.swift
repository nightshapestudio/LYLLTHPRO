import SwiftUI
import NightshapeAudioEngine

struct LYFXWindowRequest: Equatable {
    var kind: FXKind
    var target: FXTarget
}

/// Floats one of DrumKit's own FX windows over the workspace and routes its
/// edits into the document and the engine. The windows are DrumKit's source,
/// compiled here, so their displays and animation match DrumKit; on the Mac
/// they use the wide layout, display on the left and controls beside it,
/// rather than the phone's single column.
struct LYFXWindowHost: View {
    @Binding var session: LYLLTHSession
    @Binding var request: LYFXWindowRequest?
    let original: (rack: LYFXRack, reverb: ReverbState?)
    @ObservedObject var transport: TransportDisplayState
    let isPlaying: Bool
    let onTransportTap: () -> Void

    private let engine = NightshapeAudioEngine.shared
    @State private var parkedReverbSend: Float?
    @State private var mainEQVolume: Double = 0
    @StateObject private var decimatorModel = SonicDecimatorEditorModel()
    @StateObject private var decimatorMotion = DecimatorMotionDisplay()
    @State private var loadedDecimatorFor: LYFXWindowRequest?

    var body: some View {
        if let request {
            GeometryReader { geo in
                let size = Self.windowSize(for: request.kind, in: geo.size)
                LYFloatingWindow(
                    // Their own saved positions: the old narrow window's would put
                    // these wider ones half off screen.
                    id: request.kind == .decim ? "fx.decimator" : "fx.wide",
                    title: request.kind.title + "  ·  " + targetName,
                    accent: request.kind.accent,
                    size: size.content,
                    scale: size.scale,
                    close: close
                ) {
                    window(request)
                        .environment(\.fxWindowWide, true)
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .preferredColorScheme(.dark)
            .onAppear { loadDecimator(request) }
            .onChange(of: request) { _, next in loadDecimator(next) }
        }
    }

    /// DrumKit's windows are laid out for a phone. On a desktop they are drawn
    /// a quarter larger, shrinking only if the workspace is too short to fit.
    /// SwiftUI re-renders text and strokes at the scaled size (measured: the
    /// result is as sharp as unscaled), so this is not a bitmap stretch. The
    /// extra size matters on scaled "More Space" display modes, where macOS
    /// downsamples the whole frame and thin 8 pt type breaks up.
    static func macScale(for size: CGSize) -> CGFloat {
        min(1.25, max(1, (size.height - 40) / 660), max(1, (size.width - 40) / 380))
    }

    /// Desktop windows: wide and short, the display across the top and the
    /// controls in columns below; the decimator's field square on the left.
    static func windowSize(for kind: FXKind, in workspace: CGSize) -> (content: CGSize, scale: CGFloat) {
        let target = kind == .decim ? CGSize(width: 900, height: 560) : CGSize(width: 1060, height: 640)
        // Grow type a little on big screens; shrink to fit small ones.
        let fit = min((workspace.width - 40) / target.width, (workspace.height - 60) / (target.height + 22))
        let scale = min(1.12, max(0.75, fit))
        return (target, scale)
    }

    // MARK: Sonic Decimator

    /// DrumKit's decimator editor works on its own model; it is loaded from
    /// the channel's state when the window opens and written back on edits.
    private func loadDecimator(_ request: LYFXWindowRequest?) {
        guard let request, request.kind == .decim, loadedDecimatorFor != request else { return }
        loadedDecimatorFor = request
        let state = rack.decimator ?? .neutral
        decimatorModel.isAudioReactive = false
        decimatorModel.isBypassed = state.isBypassed
        decimatorModel.motion = state.motion ?? DecimatorMotion()
        decimatorModel.selectedStep = 0
        decimatorModel.setPosition(x: Double(state.destroy), y: Double(state.crush))
    }

    private func commitDecimator() {
        update(.decim) { rack in
            var state = rack.decimator ?? .neutral
            if !decimatorModel.motion.isEnabled {
                state.destroy = Float(decimatorModel.position.x)
                state.crush = Float(decimatorModel.position.y)
            }
            state.isBypassed = decimatorModel.isBypassed
            state.motion = decimatorModel.motion
            rack.decimator = state
        }
    }

    // MARK: State plumbing

    private var target: FXTarget { request?.target ?? .main }
    private var rack: LYFXRack { LYFXBridge.rack(for: target, in: session) }
    private var isMain: Bool { target == .main }

    private var engineIndex: Int? {
        if case .track(let id) = target { return LYFXBridge.engineIndex(for: id, in: session) }
        return nil
    }

    private var targetName: String {
        switch target {
        case .main: return "MAIN MIX"
        case .track(let id): return session.tracks.first { $0.id == id }?.name ?? "TRACK"
        }
    }

    private func update(_ kind: FXKind, _ change: (inout LYFXRack) -> Void) {
        var next = rack
        change(&next)
        LYFXBridge.setRack(next, for: target, in: &session)
        LYFXBridge.push(kind, rack: next, index: engineIndex, session: session, engine: engine)
    }

    private func isEngaged(_ kind: FXKind) -> Bool {
        rack.isEngaged(kind, isMain: isMain, reverb: session.reverb ?? .neutral)
    }

    private func toggle(_ kind: FXKind) -> () -> Void {
        {
            NightshapeHaptics.selection()
            if kind == .reverb && isMain {
                var reverb = session.reverb ?? .neutral
                reverb.isBypassed.toggle()
                session.reverb = reverb
                LYFXBridge.pushReverb(session, engine: engine)
                return
            }
            var parked = parkedReverbSend
            update(kind) { $0.toggleBypass(kind, parkedReverbSend: &parked) }
            parkedReverbSend = parked
        }
    }

    private func close() {
        withAnimation(LYLLTHTheme.snap) { request = nil }
    }

    private func cancel() {
        LYFXBridge.setRack(original.rack, for: target, in: &session)
        session.reverb = original.reverb
        LYFXBridge.pushRack(target: target, session: session, engine: engine)
        LYFXBridge.pushReverb(session, engine: engine)
        close()
    }

    private var keySources: [(id: UUID, name: String)] {
        LYFXBridge.keySources(in: session, excluding: target)
    }

    private var stepsPerBar: Int { session.numerator == 4 ? 16 : 12 }

    // MARK: Windows

    private func window(_ request: LYFXWindowRequest) -> AnyView {
        let kind = request.kind
        let engaged = isEngaged(kind)
        let done = { close() }
        let cancel = { self.cancel() }
        let transportTap = onTransportTap
        let bpm = session.bpm

        switch kind {
        case .eq:
            return AnyView(EQWindowView(
                targetName: targetName,
                bands: rack.bands,
                volume: eqVolume,
                isPlaying: isPlaying,
                onBandChange: { index, frequency, gain in
                    update(.eq) { rack in
                        var bands = rack.bands
                        guard bands.indices.contains(index) else { return }
                        bands[index].frequency = max(20, min(20_000, frequency))
                        bands[index].gain = max(-12, min(12, gain))
                        rack.eqBands = bands
                    }
                },
                onBandWidthChange: { index, octaves in
                    update(.eq) { rack in
                        var bands = rack.bands
                        guard bands.indices.contains(index), bands[index].type == .peaking else { return }
                        bands[index].q = min(max(octaves, 0.2), 3.0)
                        rack.eqBands = bands
                    }
                },
                onVolumeChange: { setEQVolume($0) },
                onTransportTap: transportTap,
                onCancel: cancel,
                onDone: done,
                cut: rack.eqCut ?? .neutral,
                showsPolarity: !isMain,
                onCutChange: { cut in update(.eq) { $0.eqCut = cut } }
            ))
        case .comp:
            return AnyView(CompressorWindowView(
                targetName: targetName,
                state: rack.compressor ?? .neutral,
                sidechainSources: keySources,
                isPlaying: isPlaying,
                gainReduction: { [engineIndex] in
                    engineIndex.map { engine.compressionAmount(trackIndex: $0) } ?? engine.mainCompressionAmount()
                },
                levels: { [engineIndex] in
                    engineIndex.map { engine.compressorLevels(trackIndex: $0) } ?? engine.mainCompressorLevels()
                },
                onStateChange: { state in update(.comp) { $0.compressor = state } },
                onTransportTap: transportTap,
                onCancel: cancel,
                onDone: done
            ))
        case .filter:
            return AnyView(FilterWindowView(
                targetName: targetName,
                state: rack.filter ?? .neutral,
                isPlaying: isPlaying,
                isAutomatedInSong: false,
                onStateChange: { state in update(.filter) { $0.filter = state } },
                onTransportTap: transportTap,
                onCancel: cancel,
                onDone: done,
                keySources: keySources
            ))
        case .fracture:
            return AnyView(FractureWindowView(
                targetName: targetName,
                state: rack.fracture ?? .neutral,
                stepsPerBar: stepsPerBar,
                isPlaying: isPlaying,
                isAutomatedInSong: false,
                transport: transport,
                onStateChange: { state in update(.fracture) { $0.fracture = state } },
                onTransportTap: transportTap,
                onCancel: cancel,
                onDone: done
            ))
        case .tape:
            return AnyView(TapeWindowView(targetName: targetName, state: rack.tape ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                          onStateChange: { state in update(.tape) { $0.tape = state } }, onToggleEngaged: toggle(.tape),
                                          onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .flanger:
            return AnyView(FlangerWindowView(targetName: targetName, state: rack.flanger ?? .neutral, bpm: bpm, isEngaged: engaged, isPlaying: isPlaying,
                                             onStateChange: { state in update(.flanger) { $0.flanger = state } }, onToggleEngaged: toggle(.flanger),
                                             onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .chorus:
            return AnyView(ChorusWindowView(targetName: targetName, state: rack.chorus ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                            onStateChange: { state in update(.chorus) { $0.chorus = state } }, onToggleEngaged: toggle(.chorus),
                                            onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .voidGate:
            return AnyView(VoidGateWindowView(targetName: targetName, state: rack.voidGate ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                              onStateChange: { state in update(.voidGate) { $0.voidGate = state } }, onToggleEngaged: toggle(.voidGate),
                                              onTransportTap: transportTap, onCancel: cancel, onDone: done,
                                              keySources: keySources))
        case .tempoDelay:
            return AnyView(DelayWindowView(targetName: targetName, state: rack.tempoDelay ?? .neutral, bpm: bpm, meter: session.timeSignature,
                                           isEngaged: engaged, isPlaying: isPlaying,
                                           onStateChange: { state in update(.tempoDelay) { $0.tempoDelay = state } }, onToggleEngaged: toggle(.tempoDelay),
                                           onTransportTap: transportTap, onCancel: cancel, onDone: done,
                                           activeStepCount: stepsPerBar))
        case .pump:
            return AnyView(PumpWindowView(targetName: targetName, state: rack.pump ?? .neutral, bpm: bpm, isEngaged: engaged, isPlaying: isPlaying,
                                          transport: transport,
                                          onStateChange: { state in update(.pump) { $0.pump = state } }, onToggleEngaged: toggle(.pump),
                                          onTransportTap: transportTap, onCancel: cancel, onDone: done,
                                          keySources: keySources))
        case .deadlock:
            return AnyView(DeadlockWindowView(targetName: targetName, state: rack.deadlock ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                              meter: { [engineIndex] in engineIndex.map { engine.deadlockMeter(trackIndex: $0) } ?? engine.mainDeadlockMeter() },
                                              onStateChange: { state in update(.deadlock) { $0.deadlock = state } }, onToggleEngaged: toggle(.deadlock),
                                              onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .strike:
            return AnyView(StrikeWindowView(targetName: targetName, state: rack.strike ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                            onStateChange: { state in update(.strike) { $0.strike = state } }, onToggleEngaged: toggle(.strike),
                                            onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .steelBody:
            return AnyView(SteelBodyWindowView(targetName: targetName, state: rack.steelBody ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                               onStateChange: { state in update(.steelBody) { $0.steelBody = state } }, onToggleEngaged: toggle(.steelBody),
                                               onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .undertow:
            return AnyView(UndertowWindowView(targetName: targetName, state: rack.undertow ?? .neutral, activeStepCount: stepsPerBar,
                                              isEngaged: engaged, isPlaying: isPlaying,
                                              onStateChange: { state in update(.undertow) { $0.undertow = state } }, onToggleEngaged: toggle(.undertow),
                                              onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .splitField:
            return AnyView(SplitFieldWindowView(targetName: targetName, state: rack.splitField ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                                onStateChange: { state in update(.splitField) { $0.splitField = state } }, onToggleEngaged: toggle(.splitField),
                                                onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .shear:
            return AnyView(ShearWindowView(targetName: targetName, state: rack.shear ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                           onStateChange: { state in update(.shear) { $0.shear = state } }, onToggleEngaged: toggle(.shear),
                                           onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .cabinet:
            return AnyView(CabinetWindowView(targetName: targetName, state: rack.cabinet ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                             meter: { [engineIndex] in engineIndex.map { engine.cabinetMeter(trackIndex: $0) } ?? engine.mainCabinetMeter() },
                                             onStateChange: { state in update(.cabinet) { $0.cabinet = state } }, onToggleEngaged: toggle(.cabinet),
                                             onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .finale:
            return AnyView(LimiterWindowView(targetName: targetName, state: rack.finale ?? .neutral, isEngaged: engaged, isPlaying: isPlaying,
                                             meter: { [engineIndex] in
                                                 engineIndex.map { engine.elasticLimiterMeter(trackIndex: $0) ?? .silent } ?? engine.finaleLimiterMeter()
                                             },
                                             onStateChange: { state in update(.finale) { $0.finale = state } }, onToggleEngaged: toggle(.finale),
                                             onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .delay:
            return AnyView(SignalBloomWindowView(targetName: targetName, state: rack.signalBloom ?? .neutral, bpm: bpm,
                                                 activeStepCount: stepsPerBar, isEngaged: engaged, isPlaying: isPlaying,
                                                 onStateChange: { state in update(.delay) { $0.signalBloom = state } }, onToggleEngaged: toggle(.delay),
                                                 onTransportTap: transportTap, onCancel: cancel, onDone: done))
        case .reverb:
            return AnyView(ReverbWindowView(
                targetName: targetName,
                state: session.reverb ?? .neutral,
                trackSend: isMain ? nil : (rack.reverbSend ?? 0),
                kitSend: isMain ? kitReverbSend : nil,
                isEngaged: engaged,
                isPlaying: isPlaying,
                onStateChange: { state in
                    session.reverb = state
                    LYFXBridge.pushReverb(session, engine: engine)
                },
                onSendChange: { amount in update(.reverb) { $0.reverbSend = amount } },
                onKitSendSet: { amount in setAllReverbSends { _ in amount } },
                onKitSendTrim: { delta in setAllReverbSends { min(max($0 + delta, 0), 1) } },
                onOpenMain: { self.request = LYFXWindowRequest(kind: .reverb, target: .main) },
                onToggleEngaged: toggle(.reverb),
                onTransportTap: transportTap,
                onCancel: cancel,
                onDone: done,
                keySources: keySources
            ))
        case .decim:
            return AnyView(
                SonicDecimatorFloatingEditorView(
                    model: decimatorModel,
                    motionDisplay: decimatorMotion,
                    rowName: targetName,
                    isPlaying: isPlaying,
                    playingStep: nil,
                    motionRowID: nil,
                    onTransportTap: transportTap,
                    onMotionChange: { commitDecimator() },
                    onCancel: cancel,
                    onApply: { commitDecimator(); close() }
                )
                .onChange(of: decimatorModel.position) { _, _ in
                    if decimatorModel.motion.isEnabled {
                        decimatorModel.writeSelectedStepFromPosition()
                    } else if decimatorModel.isBypassed {
                        // Moving the pad is intent to hear it.
                        decimatorModel.isBypassed = false
                    }
                    commitDecimator()
                }
                .onChange(of: decimatorModel.isBypassed) { _, _ in commitDecimator() }
                .background(LYDecimatorMotionFollower(display: decimatorMotion, trackIndex: engineIndex, isPlaying: isPlaying,
                                                       isActive: decimatorModel.motion.isEnabled))
            )
        }
    }

    // MARK: EQ volume and reverb sends

    private var eqVolume: Double {
        switch target {
        case .main: return mainEQVolume
        case .track(let id): return session.tracks.first { $0.id == id }?.volumeDB ?? -6
        }
    }

    private func setEQVolume(_ value: Double) {
        switch target {
        case .main: mainEQVolume = value
        case .track(let id):
            guard let index = session.tracks.firstIndex(where: { $0.id == id }) else { return }
            session.tracks[index].volumeDB = value
        }
    }

    private var kitReverbSend: Float {
        let sends = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }.map { $0.fx?.reverbSend ?? 0 }
        return sends.max() ?? 0
    }

    private func setAllReverbSends(_ transform: (Float) -> Float) {
        for index in session.tracks.indices where session.tracks[index].kind == .drumkit || session.tracks[index].kind == .instrument {
            var rack = session.tracks[index].fx ?? LYFXRack()
            rack.reverbSend = transform(rack.reverbSend ?? 0)
            session.tracks[index].fx = rack
            if let engineIndex = LYFXBridge.engineIndex(for: session.tracks[index].id, in: session) {
                engine.setReverbSend(trackIndex: engineIndex, amount: rack.reverbSend ?? 0)
            }
        }
    }
}



/// Asks the engine where MOTION is and shows it on the decimator's XY field,
/// twenty times a second while the transport runs.
private struct LYDecimatorMotionFollower: View {
    let display: DecimatorMotionDisplay
    let trackIndex: Int?
    let isPlaying: Bool
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !(isPlaying && isActive))) { context in
            Color.clear.onChange(of: context.date) { _, _ in
                let engine = NightshapeAudioEngine.shared
                let point = trackIndex.flatMap { engine.decimatorMotionPosition(trackIndex: $0) } ?? (trackIndex == nil ? engine.mainDecimatorMotionPosition() : nil)
                if let point {
                    display.setPosition(.init(x: Double(point.x), y: Double(point.y)), for: nil)
                } else {
                    display.clearPosition(for: nil)
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in if !playing { display.clearPosition(for: nil) } }
    }
}
