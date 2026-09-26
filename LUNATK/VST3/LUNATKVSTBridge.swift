import AppKit
import SwiftUI

// LUNATK's VST3 plug-in, Swift side: the patch, its state, the parameter
// table and the editor. The C++ wrapper owns the host conversation and the
// audio thread, and calls in here through `LunatkBridge.h`.

private let lunatkParameters = LYSynthParameters.all
private let lunatkGroups: [String] = {
    var names: [String] = []
    for parameter in lunatkParameters {
        let name = LUNATKVSTNames.group(for: parameter)
        if !names.contains(name) { names.append(name) }
    }
    return names
}()

@_cdecl("lunatk_param_count")
public func lunatk_param_count() -> Int32 { Int32(lunatkParameters.count) }

@_cdecl("lunatk_param_info")
public func lunatk_param_info(_ index: Int32, _ out: UnsafeMutablePointer<LunatkParamInfo>) -> Bool {
    guard lunatkParameters.indices.contains(Int(index)) else { return false }
    let parameter = lunatkParameters[Int(index)]
    out.pointee.id = Int32(parameter.id)
    out.pointee.minimum = parameter.range.lowerBound
    out.pointee.maximum = parameter.range.upperBound
    out.pointee.defaultValue = LYSynthPatch.initPatch.value(parameter.id)
    out.pointee.stepCount = parameter.isStepped ? Int32((parameter.range.upperBound - parameter.range.lowerBound).rounded()) : 0
    out.pointee.group = Int32(lunatkGroups.firstIndex(of: LUNATKVSTNames.group(for: parameter)) ?? 0)
    let name = LUNATKVSTNames.name(for: parameter)
    withUnsafeMutableBytes(of: &out.pointee.name) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
        let bytes = Array(name.utf8.prefix(raw.count - 1))
        raw.copyBytes(from: bytes)
    }
    return true
}

@_cdecl("lunatk_group_count")
public func lunatk_group_count() -> Int32 { Int32(lunatkGroups.count) }

@_cdecl("lunatk_group_name")
public func lunatk_group_name(_ index: Int32, _ out: UnsafeMutablePointer<CChar>, _ capacity: Int32) -> Bool {
    guard lunatkGroups.indices.contains(Int(index)), capacity > 1 else { return false }
    let bytes = Array(lunatkGroups[Int(index)].utf8.prefix(Int(capacity) - 1))
    for (i, byte) in bytes.enumerated() { out[i] = CChar(bitPattern: byte) }
    out[bytes.count] = 0
    return true
}

/// One plug-in instance's Swift half.
final class LUNATKVSTBox {
    private(set) var instrument: LYSynthInstrument
    private(set) var patch: LYSynthPatch = .initPatch
    private var bpm = 120.0
    private var syncPending = false
    let model = LUNATKVSTEditorModel()
    var edit: ((Int32, Float, Int32) -> Void)?

    init(sampleRate: Double) {
        instrument = LYSynthInstrument(sampleRate: sampleRate)
        Self.onMain {
            self.instrument.apply(self.patch, bpm: self.bpm)
            self.model.box = self
        }
    }

    static func onMain<T>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    func setSampleRate(_ rate: Double) -> OpaquePointer {
        guard abs(rate - instrument.coreSampleRate) > 0.5 else { return instrument.core }
        let rebuilt = LYSynthInstrument(sampleRate: rate)
        let patch = patchFromCore()
        Self.onMain { rebuilt.apply(patch, bpm: self.bpm) }
        instrument = rebuilt
        DispatchQueue.main.async { MainActor.assumeIsolated { self.model.instrument = rebuilt } }
        return rebuilt.core
    }

    func setBPM(_ value: Double) { bpm = value }

    func patchFromCore() -> LYSynthPatch {
        var read = patch
        for parameter in lunatkParameters {
            read.set(parameter.id, lysynth_get_param(instrument.core, Int32(parameter.id)))
        }
        return read
    }

    /// A knob moved outside the editor; the editor catches up once per burst.
    func parameterChanged() {
        DispatchQueue.main.async {
            guard !self.syncPending else { return }
            self.syncPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.syncPending = false
                let read = self.patchFromCore()
                guard read != self.patch else { return }
                self.patch = read
                MainActor.assumeIsolated { self.model.patch = read }
            }
        }
    }

    /// The editor changed the patch: the core hears it now, the host gets
    /// every moved knob as an edit it can record.
    @MainActor
    func editorChanged(_ next: LYSynthPatch) {
        let previous = patch
        patch = next
        instrument.apply(next, bpm: bpm)
        for parameter in lunatkParameters where previous.value(parameter.id) != next.value(parameter.id) {
            let id = Int32(parameter.id), value = next.value(parameter.id)
            edit?(id, value, 0)
            edit?(id, value, 1)
            edit?(id, value, 2)
        }
    }

    func stateData() -> Data? {
        Self.onMain {
            let current = patchFromCore()
            var file = LYSynthPresetFile(patch: current)
            for custom in [current.customTableA, current.customTableB].compactMap({ $0 }) {
                if let frames = LYWavetableLibrary.shared.frames(named: custom) {
                    file.wavetables[custom] = LYWavetableLibrary.floatData(frames)
                }
            }
            return try? JSONEncoder().encode(file)
        }
    }

    func load(_ data: Data) -> Bool {
        guard let file = try? JSONDecoder().decode(LYSynthPresetFile.self, from: data) else { return false }
        Self.onMain {
            LYWavetableLibrary.shared.register(projectTables: file.wavetables)
            patch = file.patch
            instrument.forgetTables()
            instrument.apply(file.patch, bpm: bpm)
            model.patch = file.patch
        }
        return true
    }
}

@_cdecl("lunatk_box_create")
public func lunatk_box_create(_ sampleRate: Double) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(LUNATKVSTBox(sampleRate: sampleRate > 0 ? sampleRate : 44_100)).toOpaque()
}

private func box(_ pointer: UnsafeMutableRawPointer) -> LUNATKVSTBox {
    Unmanaged<LUNATKVSTBox>.fromOpaque(pointer).takeUnretainedValue()
}

@_cdecl("lunatk_box_destroy")
public func lunatk_box_destroy(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<LUNATKVSTBox>.fromOpaque(pointer).release()
}

@_cdecl("lunatk_box_core")
public func lunatk_box_core(_ pointer: UnsafeMutableRawPointer) -> OpaquePointer { box(pointer).instrument.core }

@_cdecl("lunatk_box_set_sample_rate")
public func lunatk_box_set_sample_rate(_ pointer: UnsafeMutableRawPointer, _ rate: Double) -> OpaquePointer {
    box(pointer).setSampleRate(rate)
}

@_cdecl("lunatk_box_set_bpm")
public func lunatk_box_set_bpm(_ pointer: UnsafeMutableRawPointer, _ bpm: Double) { box(pointer).setBPM(bpm) }

@_cdecl("lunatk_box_param_changed")
public func lunatk_box_param_changed(_ pointer: UnsafeMutableRawPointer, _ id: Int32, _ value: Float) {
    let instance = box(pointer)
    lysynth_set_param(instance.instrument.core, id, value)
    instance.parameterChanged()
}

@_cdecl("lunatk_box_param_value")
public func lunatk_box_param_value(_ pointer: UnsafeMutableRawPointer, _ id: Int32) -> Float {
    lysynth_get_param(box(pointer).instrument.core, id)
}

@_cdecl("lunatk_box_copy_state")
public func lunatk_box_copy_state(_ pointer: UnsafeMutableRawPointer, _ length: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt8>? {
    guard let data = box(pointer).stateData(), let bytes = malloc(data.count)?.assumingMemoryBound(to: UInt8.self) else {
        length.pointee = 0
        return nil
    }
    data.copyBytes(to: bytes, count: data.count)
    length.pointee = Int32(data.count)
    return bytes
}

@_cdecl("lunatk_box_load_state")
public func lunatk_box_load_state(_ pointer: UnsafeMutableRawPointer, _ bytes: UnsafePointer<UInt8>, _ length: Int32) -> Bool {
    box(pointer).load(Data(bytes: bytes, count: Int(length)))
}

@_cdecl("lunatk_box_make_view")
public func lunatk_box_make_view(_ pointer: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer?, _ edit: LunatkEditFunction?) -> UnsafeMutableRawPointer {
    let instance = box(pointer)
    instance.edit = { id, value, phase in edit?(context, id, value, phase) }
    let view: NSView = LUNATKVSTBox.onMain {
        LUNATKVSTFonts.registerOnce()
        instance.model.patch = instance.patch
        instance.model.instrument = instance.instrument
        let hosting = NSHostingView(rootView: LUNATKVSTEditor(model: instance.model))
        hosting.frame = NSRect(origin: .zero, size: LUNATKVSTEditor.designSize)
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }
    return Unmanaged.passRetained(view).toOpaque()
}

@MainActor
final class LUNATKVSTEditorModel: ObservableObject {
    @Published var patch: LYSynthPatch = .initPatch
    @Published var instrument: LYSynthInstrument?
    weak var box: LUNATKVSTBox?

    nonisolated init() {}

    func edit(_ next: LYSynthPatch) {
        patch = next
        box?.editorChanged(next)
    }
}

/// LYLLTH's LUNATK editor, scaled to the plug-in window.
struct LUNATKVSTEditor: View {
    static let designSize = NSSize(width: 1180, height: 720)
    @ObservedObject var model: LUNATKVSTEditorModel

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.designSize.width, geo.size.height / Self.designSize.height)
            LYSynthEditor(
                patch: Binding(get: { model.patch }, set: { model.edit($0) }),
                trackName: "LUNATK",
                instrument: model.instrument,
                close: {}
            )
            .id(model.instrument.map { ObjectIdentifier($0) })
            .frame(width: Self.designSize.width, height: Self.designSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color(hex: 0x06070B))
    }
}

enum LUNATKVSTFonts {
    private static var done = false
    /// The host's bundle is `Bundle.main` here; the fonts are in ours.
    static func registerOnce() {
        guard !done else { return }
        done = true
        FontRegistrar.registerBundledFonts(in: Bundle(for: LUNATKVSTBox.self))
    }
}

enum LUNATKVSTNames {
    static func group(for parameter: LYSynthParameter) -> String {
        guard let section = parameter.key.split(separator: ".").first, parameter.key.contains(".") else { return "GLOBAL" }
        switch section {
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
        default:
            if section.hasPrefix("env") { return "ENV " + section.dropFirst(3) }
            if section.hasPrefix("lfo") { return "LFO " + section.dropFirst(3) }
            if section.hasPrefix("mx") { return "MATRIX " + String((Int(section.dropFirst(2)) ?? 0) + 1) }
            if section == "fb" { return "FEEDBACK" }
            if section == "fsat" { return "FILTER SATURATION" }
            if section == "voc" { return "VOCODER" }
            if section == "ladder" { return "LADDER" }
            if section == "perf" { return "PERFORMERS" }
            if section.hasPrefix("ins") { return "INSERT " + section.dropFirst(3) }
            if section.hasPrefix("perf") { return "PERFORMER " + section.dropFirst(4) }
            if section.hasPrefix("track") { return "TRACKER " + section.dropFirst(5) }
            return section.uppercased()
        }
    }

    static func name(for parameter: LYSynthParameter) -> String {
        var label = parameter.label
        if parameter.key.contains(".p"), let point = parameter.key.split(separator: ".").last?.dropFirst(), Int(point) != nil {
            label = "POINT " + point
        }
        let group = group(for: parameter)
        return group == "GLOBAL" ? label : group + " " + label
    }
}
