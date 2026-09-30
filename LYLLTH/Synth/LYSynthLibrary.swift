import AVFoundation
import Foundation

// MARK: - Wavetables

/// Every wavetable that is not a factory table: imported, drawn in the
/// wavetable editor, or carried in by a project or preset. Tables are frames
/// of LY_WT_SIZE samples, frame after frame.
///
/// On disk they are Serum-layout WAVs (mono 32-bit float, 2048-sample frames
/// end to end) in ~/Library/Application Support/LYLLTH/Wavetables, so tables
/// move freely between LYLLTH, Serum and anything else that reads the format.
@MainActor
final class LYWavetableLibrary: ObservableObject {
    static let shared = LYWavetableLibrary()
    static let frameSize = Int(LY_WT_SIZE)

    @Published private(set) var names: [String] = []
    private var tables: [String: [Float]] = [:]
    /// NIGHTSHAPE's own tables, shipped in the bundle (tools/lunatk_bank/wavetables.py).
    /// Read-only: saving under one of these names saves a copy instead.
    private(set) var factoryNames: Set<String> = []

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LYLLTH/Wavetables", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        loadFactoryTables()
        reloadFolder()
    }

    private func loadFactoryTables() {
        // Bundle(for:) is the app, the AU extension or the VST3 bundle,
        // whichever this code was built into.
        guard let folder = Bundle(for: LYWavetableLibrary.self).url(forResource: "Wavetables", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "wav" {
            let name = file.deletingPathExtension().lastPathComponent.uppercased()
            if let frames = try? Self.decodeFrames(from: file) {
                tables[name] = frames
                factoryNames.insert(name)
            }
        }
    }

    func reloadFolder() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["wav", "wave", "aif", "aiff"].contains(file.pathExtension.lowercased()) {
            let name = file.deletingPathExtension().lastPathComponent.uppercased()
            if tables[name] == nil, let frames = try? Self.decodeFrames(from: file) { tables[name] = frames }
        }
        names = tables.keys.sorted()
    }

    func frames(named name: String) -> [Float]? { tables[name] }

    func frameCount(_ name: String) -> Int { (tables[name]?.count ?? 0) / Self.frameSize }

    /// Registers a table, writes it to the user folder, and returns the name
    /// it was stored under.
    @discardableResult
    func store(_ frames: [Float], named proposed: String, writeToFolder: Bool = true) -> String {
        var name = proposed.uppercased().trimmingCharacters(in: .whitespaces).isEmpty ? "UNTITLED TABLE" : proposed.uppercased()
        if factoryNames.contains(name) { name += " COPY" }
        tables[name] = frames
        if writeToFolder { try? Self.writeWAV(frames, to: Self.folder.appendingPathComponent(name).appendingPathExtension("wav")) }
        names = tables.keys.sorted()
        return name
    }

    /// Tables a project carries, keyed by name. Registered without writing to
    /// the user folder, so opening someone else's song does not fill it.
    func register(projectTables: [String: Data]) {
        for (name, data) in projectTables where tables[name] == nil {
            if let frames = Self.decodeFloatData(data) { tables[name] = frames }
        }
        names = tables.keys.sorted()
    }

    // MARK: Import

    /// A Serum-layout file becomes its frames exactly. Anything else is
    /// treated as audio: 64 frames taken evenly through it, so a vocal or a
    /// drum loop turns into a scannable table.
    static func importFrames(from url: URL) throws -> [Float] {
        let samples = try decodeMono(from: url)
        guard !samples.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        if samples.count % frameSize == 0, samples.count / frameSize <= Int(LY_WT_MAX_FRAMES) {
            return samples
        }
        if samples.count <= frameSize * 2 {
            return resample(samples, to: frameSize)
        }
        let frameCount = 64
        var frames: [Float] = []
        frames.reserveCapacity(frameCount * frameSize)
        let span = samples.count - frameSize
        for f in 0..<frameCount {
            let start = span * f / max(frameCount - 1, 1)
            frames.append(contentsOf: samples[start..<(start + frameSize)])
        }
        return frames
    }

    private static func decodeFrames(from url: URL) throws -> [Float] {
        let samples = try decodeMono(from: url)
        guard samples.count >= frameSize else { throw CocoaError(.fileReadCorruptFile) }
        return Array(samples.prefix((samples.count / frameSize) * frameSize))
    }

    /// Reads the whole file. One `read(into:)` can return fewer frames than
    /// asked for (it stopped at 49 152 of 50 000 in testing), so this loops.
    private static func decodeMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let channelCount = Int(format.channelCount)
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: min(chunk, AVAudioFrameCount(file.length - file.framePosition)))
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for i in 0..<count {
                var sum: Float = 0
                for c in 0..<channelCount { sum += channels[c][i] }
                samples.append(sum / Float(channelCount))
            }
        }
        return samples
    }

    private static func resample(_ input: [Float], to count: Int) -> [Float] {
        (0..<count).map { i in
            let position = Double(i) * Double(input.count) / Double(count)
            let index = Int(position)
            let fraction = Float(position - Double(index))
            return input[index] + (input[(index + 1) % input.count] - input[index]) * fraction
        }
    }

    // MARK: Encoding

    static func writeWAV(_ frames: [Float], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames.count)
        frames.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: frames.count)
        }
        try file.write(from: buffer)
        // Finalise the header now rather than whenever the file object goes;
        // without this the last partial chunk can be missing on read-back.
        if #available(macOS 15.0, *) { file.close() }
    }

    /// Raw little-endian Float32, the form projects and presets embed.
    static func floatData(_ frames: [Float]) -> Data {
        frames.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decodeFloatData(_ data: Data) -> [Float]? {
        guard data.count >= frameSize * 4, data.count % 4 == 0 else { return nil }
        let frames: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return Array(frames.prefix((frames.count / frameSize) * frameSize))
    }

    /// Factory frames at full resolution, for the editor to start from.
    static func factoryFrames(_ table: Int) -> [Float] {
        var raw = [Float](repeating: 0, count: Int(LY_WT_MAX_FRAMES) * frameSize)
        let count = Int(raw.withUnsafeMutableBufferPointer { lysynth_factory_table(Int32(table), $0.baseAddress, Int32(LY_WT_MAX_FRAMES)) })
        return Array(raw.prefix(count * frameSize))
    }
}

// MARK: - Samples

/// A mono sample at its own rate, for the SAMPLE and GRANULAR oscillator modes.
struct LYSynthSample: Equatable {
    var samples: [Float]
    var rate: Double
}

/// The samples LUNATK's oscillators play, by name: imported ones, and those
/// a project or preset carries. On disk they are mono 32-bit float WAVs at
/// their own rate in ~/Library/Application Support/LYLLTH/Samples.
@MainActor
final class LYSampleLibrary: ObservableObject {
    static let shared = LYSampleLibrary()
    /// A minute at 48 kHz; longer files are cut.
    static let maxFrames = 48_000 * 60

    @Published private(set) var names: [String] = []
    private var samples: [String: LYSynthSample] = [:]

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LYLLTH/Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { reloadFolder() }

    func reloadFolder() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where ["wav", "wave", "aif", "aiff"].contains(file.pathExtension.lowercased()) {
            let name = file.deletingPathExtension().lastPathComponent.uppercased()
            if samples[name] == nil, let sample = try? Self.importSample(from: file) { samples[name] = sample }
        }
        names = samples.keys.sorted()
    }

    func sample(named name: String) -> LYSynthSample? { samples[name] }

    /// Registers a sample, writes it to the user folder, and returns the name
    /// it was stored under.
    @discardableResult
    func store(_ sample: LYSynthSample, named proposed: String, writeToFolder: Bool = true) -> String {
        let trimmed = proposed.uppercased().trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "UNTITLED SAMPLE" : trimmed
        samples[name] = sample
        if writeToFolder { try? Self.writeWAV(sample, to: Self.folder.appendingPathComponent(name).appendingPathExtension("wav")) }
        names = samples.keys.sorted()
        return name
    }

    /// Samples a project or preset carries. Registered without writing to the
    /// user folder.
    func register(projectSamples: [String: Data]) {
        for (name, data) in projectSamples where samples[name] == nil {
            if let sample = Self.decode(data) { samples[name] = sample }
        }
        names = samples.keys.sorted()
    }

    /// Any audio file, mixed to mono, at its own rate.
    static func importSample(from url: URL) throws -> LYSynthSample {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = min(Int(file.length), maxFrames)
        let chunk: AVAudioFrameCount = 16_384
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let channelCount = Int(format.channelCount)
        var mono: [Float] = []
        mono.reserveCapacity(total)
        while mono.count < total, file.framePosition < file.length {
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: min(chunk, AVAudioFrameCount(total - mono.count)))
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for i in 0..<count {
                var sum: Float = 0
                for c in 0..<channelCount { sum += channels[c][i] }
                mono.append(sum / Float(channelCount))
            }
        }
        guard !mono.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return LYSynthSample(samples: mono, rate: format.sampleRate)
    }

    static func writeWAV(_ sample: LYSynthSample, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sample.rate, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(sample.samples.count)
        sample.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: sample.samples.count)
        }
        try file.write(from: buffer)
        if #available(macOS 15.0, *) { file.close() }
    }

    /// The form projects and presets embed: the rate as a Float64, then
    /// little-endian Float32 samples.
    static func data(_ sample: LYSynthSample) -> Data {
        var rate = sample.rate
        var data = Data(bytes: &rate, count: 8)
        sample.samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    static func decode(_ data: Data) -> LYSynthSample? {
        guard data.count >= 12, (data.count - 8) % 4 == 0 else { return nil }
        let rate = data.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
        let samples: [Float] = data.dropFirst(8).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard rate > 0, rate.isFinite else { return nil }
        return LYSynthSample(samples: samples, rate: rate)
    }
}

// MARK: - Presets

/// A user preset on disk: the patch plus any custom wavetables it uses, so a
/// preset never loses its sound when moved to another Mac.
struct LYSynthPresetFile: Codable {
    var patch: LYSynthPatch
    var wavetables: [String: Data] = [:]
    /// Samples the oscillators play (LYSampleLibrary.data). Optional so files
    /// from before samples still load.
    var samples: [String: Data]? = nil

    /// The patch with every custom wavetable and sample it uses.
    @MainActor
    static func carrying(_ patch: LYSynthPatch) -> LYSynthPresetFile {
        var file = LYSynthPresetFile(patch: patch)
        for custom in [patch.customTableA, patch.customTableB, patch.customTableC].compactMap({ $0 }) {
            if let frames = LYWavetableLibrary.shared.frames(named: custom) {
                file.wavetables[custom] = LYWavetableLibrary.floatData(frames)
            }
        }
        var samples: [String: Data] = [:]
        for name in (0..<Int(LY_OSC_COUNT)).compactMap({ patch.sampleName($0) }) {
            if let sample = LYSampleLibrary.shared.sample(named: name) { samples[name] = LYSampleLibrary.data(sample) }
        }
        file.samples = samples.isEmpty ? nil : samples
        return file
    }

    /// Makes what the file carries available before its patch is applied.
    @MainActor
    func registerContents() {
        LYWavetableLibrary.shared.register(projectTables: wavetables)
        if let samples { LYSampleLibrary.shared.register(projectSamples: samples) }
    }
}

@MainActor
final class LYSynthPresetStore: ObservableObject {
    static let shared = LYSynthPresetStore()

    @Published private(set) var presets: [LYSynthPatch] = []

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("LYLLTH/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { reload() }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [LYSynthPatch] = []
        for file in files where file.pathExtension == "lyllthsynth" {
            guard let data = try? Data(contentsOf: file),
                  let preset = try? JSONDecoder().decode(LYSynthPresetFile.self, from: data) else { continue }
            preset.registerContents()
            loaded.append(preset.patch)
        }
        presets = loaded.sorted { $0.name < $1.name }
    }

    func save(_ patch: LYSynthPatch, as name: String) throws {
        var stored = patch
        stored.name = name.uppercased()
        let file = LYSynthPresetFile.carrying(stored)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url(for: stored.name), options: .atomic)
        reload()
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        reload()
    }

    private func url(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return Self.folder.appendingPathComponent(safe).appendingPathExtension("lyllthsynth")
    }
}
