import AudioToolbox
import AVFoundation
import Foundation

/// LUNATK as an Audio Unit instrument: the same C++ core LYLLTH plays,
/// every knob a host parameter, the patch saved with the host's song and
/// as AU presets. MIDI arrives sample-accurately: each block renders up to
/// an event, applies it, and carries on.
final class LUNATKAudioUnit: AUAudioUnit {
    /// What the render block reads. Swapped only while render resources are
    /// deallocated, so the audio thread never sees a core change under it.
    private final class Kernel {
        var core: OpaquePointer
        var left: UnsafeMutablePointer<Float>
        var right: UnsafeMutablePointer<Float>
        var capacity: Int
        var bpm: Double = 120
        var sampleRate: Double = 48_000
        var musicalContext: AUHostMusicalContextBlock?
        var transportState: AUHostTransportStateBlock?
        // The sidechain input (the vocoder's voice), pulled into these.
        var inputLeft: UnsafeMutablePointer<Float>
        var inputRight: UnsafeMutablePointer<Float>
        let inputList = AudioBufferList.allocate(maximumBuffers: 2)
        var inputEnabled = false
        var inputChannels = 2

        init(core: OpaquePointer, capacity: Int) {
            self.core = core
            self.capacity = capacity
            left = .allocate(capacity: capacity)
            right = .allocate(capacity: capacity)
            inputLeft = .allocate(capacity: capacity)
            inputRight = .allocate(capacity: capacity)
        }

        func resize(_ frames: Int) {
            guard frames > capacity else { return }
            left.deallocate()
            right.deallocate()
            inputLeft.deallocate()
            inputRight.deallocate()
            capacity = frames
            left = .allocate(capacity: frames)
            right = .allocate(capacity: frames)
            inputLeft = .allocate(capacity: frames)
            inputRight = .allocate(capacity: frames)
        }

        deinit {
            left.deallocate()
            right.deallocate()
            inputLeft.deallocate()
            inputRight.deallocate()
            inputList.unsafeMutablePointer.deallocate()
        }
    }

    static let designSampleRate = 48_000.0

    private(set) var instrument: LYSynthInstrument
    private let kernel: Kernel
    private var outputBus: AUAudioUnitBus
    private var busArray: AUAudioUnitBusArray!
    /// A sidechain input: the vocoder's voice.
    private var inputBus: AUAudioUnitBus
    private var inputBusArray: AUAudioUnitBusArray!
    private var tree: AUParameterTree!
    private var editorToken: AUParameterObserverToken?
    private var pendingPatchSync = false

    /// The patch, kept on the main thread. The editor edits it; host
    /// automation reaches the core directly and is folded back in here.
    private(set) var patch: LYSynthPatch = .initPatch
    /// Called on the main thread when the patch changes from outside the
    /// editor: a preset, a restored song, host automation.
    var onPatchChange: ((LYSynthPatch) -> Void)?
    /// Called on the main thread when the core is rebuilt for a new rate.
    var onInstrumentChange: ((LYSynthInstrument) -> Void)?

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        instrument = LYSynthInstrument(sampleRate: Self.designSampleRate)
        kernel = Kernel(core: instrument.core, capacity: 4_096)
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.designSampleRate, channels: 2)!
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.maximumChannelCount = 2
        inputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        try super.init(componentDescription: componentDescription, options: options)
        busArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        tree = Self.makeTree()
        wireTree()
        applyToCore(patch, to: instrument)
        maximumFramesToRender = 4_096
    }

    // MARK: Busses and formats

    override var outputBusses: AUAudioUnitBusArray { busArray }
    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    // Stereo out, with the sidechain stereo, mono or not connected.
    override var channelCapabilities: [NSNumber]? { [2, 2, 1, 2, 0, 2] }
    override var supportsUserPresets: Bool { true }
    override var canProcessInPlace: Bool { false }

    /// LUNATK renders stereo only.
    override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        if bus === inputBus { return (1...2).contains(format.channelCount) && super.shouldChange(to: format, for: bus) }
        return format.channelCount == 2 && super.shouldChange(to: format, for: bus)
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let rate = outputBus.format.sampleRate
        // The core is built for one sample rate; a new rate gets a new core
        // with the same patch.
        if abs(rate - instrument.coreSampleRate) > 0.5 {
            let rebuilt = LYSynthInstrument(sampleRate: rate)
            applyToCore(patch, to: rebuilt)
            instrument = rebuilt
            kernel.core = rebuilt.core
            let current = rebuilt
            DispatchQueue.main.async { [weak self] in self?.onInstrumentChange?(current) }
        }
        kernel.resize(Int(maximumFramesToRender))
        kernel.sampleRate = rate
        kernel.inputEnabled = inputBus.isEnabled
        kernel.inputChannels = Int(max(1, min(2, inputBus.format.channelCount)))
        kernel.musicalContext = musicalContextBlock
        kernel.transportState = transportStateBlock
    }

    override func deallocateRenderResources() {
        lysynth_all_notes_off(kernel.core)
        kernel.musicalContext = nil
        kernel.transportState = nil
        super.deallocateRenderResources()
    }

    // MARK: Render

    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = kernel
        return { _, timestamp, frameCount, _, outputData, realtimeEventListHead, pullInputBlock in
            let count = Int(frameCount)
            guard count <= kernel.capacity else { return kAudioUnitErr_TooManyFramesToProcess }
            let core = kernel.core

            // The sidechain, if the host is feeding one.
            var inLeft: UnsafePointer<Float>?
            var inRight: UnsafePointer<Float>?
            if kernel.inputEnabled, let pull = pullInputBlock {
                let list = kernel.inputList
                let channels = kernel.inputChannels
                list.count = channels
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(kernel.inputLeft))
                if channels > 1 {
                    list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                                          mData: UnsafeMutableRawPointer(kernel.inputRight))
                }
                var flags = AudioUnitRenderActionFlags()
                if pull(&flags, timestamp, frameCount, 0, list.unsafeMutablePointer) == noErr, let first = list[0].mData {
                    inLeft = UnsafePointer(first.assumingMemoryBound(to: Float.self))
                    inRight = channels > 1 ? list[1].mData.map { UnsafePointer($0.assumingMemoryBound(to: Float.self)) } : inLeft
                }
            }

            // Follow the host's tempo and song position, for synced LFOs,
            // delay, ARP and the performers.
            var blockBeat: Double?
            var playing = false
            if let context = kernel.musicalContext {
                var tempo = 0.0
                var beat = 0.0
                if context(&tempo, nil, nil, &beat, nil, nil) {
                    if tempo > 0, abs(tempo - kernel.bpm) > 0.001 {
                        kernel.bpm = tempo
                        lysynth_set_param(core, Int32(LY_BPM), Float(tempo))
                    }
                    blockBeat = beat
                }
            }
            if let state = kernel.transportState {
                var flags = AUHostTransportStateFlags()
                if state(&flags, nil, nil, nil) { playing = flags.contains(.moving) }
            }
            let beatsPerFrame = kernel.bpm / 60 / kernel.sampleRate

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            if buffers.count >= 1, buffers[0].mData == nil { buffers[0].mData = UnsafeMutableRawPointer(kernel.left) }
            if buffers.count >= 2, buffers[1].mData == nil { buffers[1].mData = UnsafeMutableRawPointer(kernel.right) }
            guard buffers.count >= 1, let leftRaw = buffers[0].mData else { return noErr }
            let left = leftRaw.assumingMemoryBound(to: Float.self)
            let right = buffers.count >= 2 ? buffers[1].mData!.assumingMemoryBound(to: Float.self) : kernel.right
            for index in 0..<min(buffers.count, 2) { buffers[index].mDataByteSize = UInt32(count * MemoryLayout<Float>.size) }

            let blockStart = AUEventSampleTime(timestamp.pointee.mSampleTime)
            var position = 0
            var event = realtimeEventListHead
            while let current = event {
                let offset = Int(max(0, min(Int64(count), current.pointee.head.eventSampleTime - blockStart)))
                if offset > position {
                    if let blockBeat { lysynth_set_song_position(core, blockBeat + Double(position) * beatsPerFrame, playing ? 1 : 0) }
                    lysynth_render_input(core, left + position, right + position, inLeft.map { $0 + position }, inRight.map { $0 + position },
                                         Int32(offset - position), 0)
                    position = offset
                }
                switch current.pointee.head.eventType {
                case .MIDI:
                    let midi = current.pointee.MIDI
                    if midi.length >= 1 {
                        lysynth_midi(core, midi.data.0, midi.length > 1 ? midi.data.1 : 0, midi.length > 2 ? midi.data.2 : 0, 0)
                    }
                case .parameter, .parameterRamp:
                    // A host can schedule an address that isn't ours; converting it
                    // unchecked would trap on the audio thread.
                    let parameter = current.pointee.parameter
                    if parameter.parameterAddress < AUParameterAddress(LY_PARAM_COUNT) {
                        lysynth_set_param(core, Int32(parameter.parameterAddress), parameter.value)
                    }
                default:
                    break
                }
                event = UnsafePointer(current.pointee.head.next)
            }
            if count > position {
                if let blockBeat { lysynth_set_song_position(core, blockBeat + Double(position) * beatsPerFrame, playing ? 1 : 0) }
                lysynth_render_input(core, left + position, right + position, inLeft.map { $0 + position }, inRight.map { $0 + position },
                                     Int32(count - position), 0)
            }
            // A mono output gets the left channel; LUNATK is stereo.
            _ = right
            return noErr
        }
    }

    // MARK: Parameters

    override var parameterTree: AUParameterTree? {
        get { tree }
        set { }
    }

    /// Every LUNATK parameter, grouped by section. Addresses are the core's
    /// parameter ids, identifiers the patch keys, so automation written
    /// against one version keeps its meaning.
    private static func makeTree() -> AUParameterTree {
        var sections: [String: [AUParameter]] = [:]
        var order: [String] = []
        for parameter in LYSynthParameters.all {
            let section = String(parameter.key.split(separator: ".").first ?? "global")
            let grouped = parameter.key.contains(".") ? section : "global"
            if sections[grouped] == nil { order.append(grouped) }
            let name = LUNATKNames.parameter(parameter)
            let node = AUParameterTree.createParameter(
                withIdentifier: parameter.key.replacingOccurrences(of: ".", with: "_"),
                name: name,
                address: AUParameterAddress(parameter.id),
                min: parameter.range.lowerBound,
                max: parameter.range.upperBound,
                unit: parameter.isStepped ? .indexed : .generic,
                unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
                valueStrings: nil,
                dependentParameters: nil
            )
            node.value = LYSynthPatch.initPatch.value(parameter.id)
            sections[grouped, default: []].append(node)
        }
        let groups = order.map { key in
            AUParameterTree.createGroup(withIdentifier: key, name: LUNATKNames.section(key), children: sections[key] ?? [])
        }
        return AUParameterTree.createTree(withChildren: groups)
    }

    private func wireTree() {
        let kernel = kernel
        tree.implementorValueObserver = { [weak self] parameter, value in
            lysynth_set_param(kernel.core, Int32(parameter.address), value)
            self?.schedulePatchSync()
        }
        tree.implementorValueProvider = { parameter in
            lysynth_get_param(kernel.core, Int32(parameter.address))
        }
        tree.implementorStringFromValueCallback = { parameter, value in
            let v = value?.pointee ?? parameter.value
            if parameter.unit == .indexed { return String(Int(v.rounded())) }
            return String(format: "%.3f", v)
        }
    }

    /// Host automation moved knobs in the core; bring the patch (and the
    /// editor) up to date, once per burst.
    private func schedulePatchSync() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.pendingPatchSync else { return }
            self.pendingPatchSync = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.pendingPatchSync = false
                let read = self.patchFromCore()
                guard read != self.patch else { return }
                self.patch = read
                self.onPatchChange?(read)
            }
        }
    }

    private func patchFromCore() -> LYSynthPatch {
        var read = patch
        for parameter in LYSynthParameters.all {
            read.set(parameter.id, lysynth_get_param(kernel.core, Int32(parameter.id)))
        }
        return read
    }

    // MARK: Patch

    /// The editor changed the patch: send it to the core and tell the host
    /// which knobs moved, so it can record them as automation.
    @MainActor
    func setPatchFromEditor(_ next: LYSynthPatch) {
        let previous = patch
        patch = next
        instrument.apply(next, bpm: kernel.bpm)
        if editorToken == nil { editorToken = tree.token(byAddingParameterObserver: { _, _ in }) }
        for parameter in LYSynthParameters.all where previous.value(parameter.id) != next.value(parameter.id) {
            tree.parameter(withAddress: AUParameterAddress(parameter.id))?.setValue(next.value(parameter.id), originator: editorToken)
        }
    }

    /// A whole new patch from outside the editor.
    private func loadPatch(_ next: LYSynthPatch) {
        let apply = {
            self.patch = next
            self.applyToCore(next, to: self.instrument)
            for parameter in LYSynthParameters.all {
                self.tree.parameter(withAddress: AUParameterAddress(parameter.id))?.value = next.value(parameter.id)
            }
            self.onPatchChange?(next)
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.sync(execute: apply) }
    }

    private func applyToCore(_ patch: LYSynthPatch, to instrument: LYSynthInstrument) {
        let bpm = kernel.bpm
        Self.onMain { instrument.forgetTables(); instrument.apply(patch, bpm: bpm) }
    }

    // MARK: Presets and state

    override var factoryPresets: [AUAudioUnitPreset]? {
        LYSynthPatch.factory.enumerated().map { index, patch in
            let preset = AUAudioUnitPreset()
            preset.number = index
            preset.name = patch.category.map { "\($0) / \(patch.name)" } ?? patch.name
            return preset
        }
    }

    private var chosenPreset: AUAudioUnitPreset?

    override var currentPreset: AUAudioUnitPreset? {
        get { chosenPreset }
        set {
            guard let preset = newValue else { chosenPreset = nil; return }
            if preset.number >= 0 {
                guard LYSynthPatch.factory.indices.contains(preset.number) else { return }
                loadPatch(LYSynthPatch.factory[preset.number])
                chosenPreset = preset
            } else {
                // presetState(for:) raises an Objective-C exception for a
                // preset with no file behind it, which would take the
                // extension down: only ask for ones that were saved.
                if userPresets.contains(where: { $0.number == preset.number && $0.name == preset.name }),
                   let state = try? presetState(for: preset) {
                    fullState = state
                }
                chosenPreset = preset
            }
        }
    }

    private static let stateKey = "lunatk.patch"

    /// Runs main-actor work from whatever thread the host calls on.
    private static func onMain<T>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    /// The patch, with any custom wavetables it uses, travels in the host's
    /// song and in user presets.
    override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            let current = Thread.isMainThread ? patchFromCore() : patch
            var file = LYSynthPresetFile(patch: current)
            file.wavetables = Self.onMain {
                var tables: [String: Data] = [:]
                for custom in [current.customTableA, current.customTableB].compactMap({ $0 }) {
                    if let frames = LYWavetableLibrary.shared.frames(named: custom) {
                        tables[custom] = LYWavetableLibrary.floatData(frames)
                    }
                }
                return tables
            }
            if let data = try? JSONEncoder().encode(file) { state[Self.stateKey] = data }
            return state
        }
        set {
            guard let state = newValue else { return }
            if let data = state[Self.stateKey] as? Data, let file = try? JSONDecoder().decode(LYSynthPresetFile.self, from: data) {
                Self.onMain { LYWavetableLibrary.shared.register(projectTables: file.wavetables) }
                loadPatch(file.patch)
            }
        }
    }
}

/// Names hosts show for LUNATK's parameters and sections.
enum LUNATKNames {
    static func section(_ key: String) -> String {
        switch key {
        case "a": return "OSC A"
        case "b": return "OSC B"
        case "sub": return "SUB"
        case "noise": return "NOISE"
        case "filter": return "FILTER 1"
        case "filter2": return "FILTER 2"
        case "arp": return "ARP"
        case "fx": return "FX ORDER"
        case "fxfilter": return "FX FILTER"
        case "dist": return "DISTORTION"
        case "comp": return "COMPRESSOR"
        case "global": return "GLOBAL"
        default:
            if key.hasPrefix("env") { return "ENV " + key.dropFirst(3) }
            if key.hasPrefix("lfo") { return "LFO " + key.dropFirst(3) }
            if key.hasPrefix("mx") { return "MATRIX " + String(Int(key.dropFirst(2)).map { $0 + 1 } ?? 0) }
            return LUNATKNames.added(key) ?? key.uppercased()
        }
    }

    /// Sections added after the first release.
    static func added(_ key: String) -> String? {
        switch key {
        case "fb": return "FEEDBACK"
        case "fsat": return "FILTER SATURATION"
        case "voc": return "VOCODER"
        case "ladder": return "LADDER"
        case "perf": return "PERFORMERS"
        default:
            if key.hasPrefix("ins") { return "INSERT " + key.dropFirst(3) }
            if key.hasPrefix("perf") { return "PERFORMER " + key.dropFirst(4) }
            if key.hasPrefix("track") { return "TRACKER " + key.dropFirst(5) }
            return nil
        }
    }

    static func parameter(_ parameter: LYSynthParameter) -> String {
        guard let section = parameter.key.split(separator: ".").first, parameter.key.contains(".") else { return parameter.label }
        var label = parameter.label
        if parameter.key.contains(".p"), let point = parameter.key.split(separator: ".").last?.dropFirst(), Int(point) != nil {
            label = "POINT " + point
        }
        return self.section(String(section)) + " " + label
    }
}
