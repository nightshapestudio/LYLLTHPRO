import SwiftUI
import Accelerate

/// Draw and shape a wavetable. Works on a copy; SAVE stores it in the user
/// wavetable folder and puts it on the oscillator.
struct LYWavetableEditor: View {
    let accent: Color
    let initialName: String
    let initialFrames: [Float]
    let save: (_ name: String, _ frames: [Float]) -> Void
    let cancel: () -> Void

    @State private var frames: [[Float]] = []
    @State private var selected = 0
    @State private var name = ""
    @State private var lastDrawPoint: (index: Int, value: Float)?
    @State private var harmonics: [Float] = []
    @State private var morphFrom = 0
    @State private var morphTo = 0

    private static let size = LYWavetableLibrary.frameSize
    private static let harmonicCount = 48

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("WAVETABLE EDITOR")
                    .font(LYLLTHTheme.label(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(accent)
                TextField("NAME", text: $name)
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(11, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .padding(.horizontal, 8)
                    .frame(width: 240, height: 28)
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                Text("\(frames.count) FRAMES")
                    .font(LYLLTHTheme.value(10))
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
                Button("CANCEL", action: cancel)
                    .buttonStyle(LYChromeButtonStyle(compact: true))
                Button("SAVE") { save(name, frames.flatMap { $0 }) }
                    .buttonStyle(LYChromeButtonStyle(active: true, tint: accent, compact: true))
                    .disabled(frames.isEmpty)
            }

            HStack(alignment: .top, spacing: 10) {
                frameStrip.frame(width: 120)
                VStack(spacing: 10) {
                    drawingCanvas
                    harmonicEditor.frame(height: 150)
                }
                tools.frame(width: 190)
            }
        }
        .padding(14)
        .background(Color(hex: 0x07080D))
        .overlay(Rectangle().stroke(accent.opacity(0.7), lineWidth: 1))
        .onAppear {
            name = initialName
            let size = Self.size
            let count = max(1, initialFrames.count / size)
            frames = (0..<count).map { f in
                initialFrames.count >= (f + 1) * size ? Array(initialFrames[(f * size)..<((f + 1) * size)]) : Array(repeating: 0, count: size)
            }
            morphTo = frames.count - 1
            refreshHarmonics()
        }
    }

    // MARK: Frames

    private var frameStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(frames.indices, id: \.self) { index in
                        LYFrameThumbnail(samples: frames[index], accent: accent, isSelected: index == selected, number: index + 1)
                            .frame(height: 40)
                            .id(index)
                            .onTapGesture { selected = index; refreshHarmonics() }
                    }
                }
            }
            .lyScrollers()
            .onChange(of: selected) { _, value in proxy.scrollTo(value) }
        }
        .padding(4)
        .background(Color.black.opacity(0.4))
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private var drawingCanvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.55)))
                let mid = size.height / 2
                context.fill(Path(CGRect(x: 0, y: mid, width: size.width, height: 1)), with: .color(Color.white.opacity(0.08)))
                for q in 1..<4 {
                    let x = size.width * CGFloat(q) / 4
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.05)))
                }
                guard frames.indices.contains(selected) else { return }
                if selected > 0 {
                    context.stroke(path(frames[selected - 1], in: size), with: .color(Color.white.opacity(0.12)), lineWidth: 1)
                }
                let current = path(frames[selected], in: size)
                var fill = current
                fill.addLine(to: CGPoint(x: size.width, y: mid))
                fill.addLine(to: CGPoint(x: 0, y: mid))
                fill.closeSubpath()
                context.fill(fill, with: .color(accent.opacity(0.1)))
                var glow = context
                glow.addFilter(.shadow(color: accent.opacity(0.7), radius: 4))
                glow.stroke(current, with: .color(accent), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in draw(at: drag.location, in: geo.size) }
                    .onEnded { _ in lastDrawPoint = nil; refreshHarmonics() }
            )
            .overlay(alignment: .topLeading) {
                Text("DRAW FRAME \(selected + 1)")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .padding(8)
            }
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func path(_ samples: [Float], in size: CGSize) -> Path {
        var path = Path()
        let points = 512
        for i in 0..<points {
            let sample = samples[i * samples.count / points]
            let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(points - 1),
                                y: size.height / 2 - CGFloat(max(-1, min(1, sample))) * (size.height / 2 - 6))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Paints samples along the stroke, filling between successive pointer
    /// positions so a fast stroke leaves no gaps.
    private func draw(at location: CGPoint, in size: CGSize) {
        guard frames.indices.contains(selected), size.width > 0 else { return }
        let index = min(max(Int(location.x / size.width * CGFloat(Self.size)), 0), Self.size - 1)
        let value = Float(min(max((size.height / 2 - location.y) / (size.height / 2 - 6), -1), 1))
        var frame = frames[selected]
        if let last = lastDrawPoint {
            let lo = min(last.index, index), hi = max(last.index, index)
            for i in lo...hi {
                let t = hi == lo ? 1 : Float(i - last.index) / Float(index - last.index)
                frame[i] = last.value + (value - last.value) * min(max(t, 0), 1)
            }
        } else {
            frame[index] = value
        }
        frames[selected] = frame
        lastDrawPoint = (index, value)
    }

    // MARK: Harmonics

    private var harmonicEditor: some View {
        GeometryReader { geo in
            let count = Self.harmonicCount
            let width = geo.size.width / CGFloat(count)
            ZStack(alignment: .bottomLeading) {
                Color.black.opacity(0.55)
                ForEach(0..<min(count, harmonics.count), id: \.self) { h in
                    Rectangle()
                        .fill(h == 0 ? accent : accent.opacity(0.55 + 0.45 * Double(harmonics[h])))
                        .frame(width: max(1, width - 2), height: max(1, geo.size.height * CGFloat(harmonics[h])))
                        .offset(x: CGFloat(h) * width + 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let h = min(max(Int(drag.location.x / width), 0), count - 1)
                        let level = Float(min(max(1 - drag.location.y / geo.size.height, 0), 1))
                        setHarmonic(h, level)
                    }
            )
            .overlay(alignment: .topLeading) {
                Text("HARMONICS · DRAG TO RESHAPE")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .padding(8)
            }
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    /// Magnitudes of harmonics 1…48 of the selected frame, relative to the
    /// loudest.
    private func refreshHarmonics() {
        guard frames.indices.contains(selected) else { return }
        let spectrum = Self.spectrum(frames[selected])
        let peak = max(spectrum.magnitudes.prefix(Self.harmonicCount).max() ?? 0, 0.000_1)
        harmonics = spectrum.magnitudes.prefix(Self.harmonicCount).map { min($0 / peak, 1) }
    }

    /// Sets one harmonic's level and resynthesises the frame, keeping every
    /// harmonic's phase and everything above the editable range.
    private func setHarmonic(_ index: Int, _ level: Float) {
        guard frames.indices.contains(selected), harmonics.indices.contains(index) else { return }
        var spectrum = Self.spectrum(frames[selected])
        let peak = max(spectrum.magnitudes.prefix(Self.harmonicCount).max() ?? 0, 0.000_1)
        spectrum.magnitudes[index] = level * peak
        if spectrum.phases[index] == 0 { spectrum.phases[index] = -.pi / 2 }
        frames[selected] = Self.synthesize(spectrum)
        harmonics[index] = level
    }

    struct Spectrum { var magnitudes: [Float]; var phases: [Float] }

    static func spectrum(_ frame: [Float]) -> Spectrum {
        let n = size, half = n / 2
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(kFFTDirection_Forward))
            }
        }
        // Bin h is harmonic h; skip DC (bin 0 holds DC and Nyquist).
        var magnitudes = [Float](repeating: 0, count: half), phases = [Float](repeating: 0, count: half)
        for h in 1..<half {
            magnitudes[h - 1] = (re[h] * re[h] + im[h] * im[h]).squareRoot() / Float(n)
            phases[h - 1] = atan2(im[h], re[h])
        }
        return Spectrum(magnitudes: magnitudes, phases: phases)
    }

    static func synthesize(_ spectrum: Spectrum) -> [Float] {
        let n = size, half = n / 2
        var re = [Float](repeating: 0, count: half), im = [Float](repeating: 0, count: half)
        for h in 1..<half {
            let magnitude = spectrum.magnitudes[h - 1] * Float(n)
            re[h] = magnitude * cos(spectrum.phases[h - 1])
            im[h] = magnitude * sin(spectrum.phases[h - 1])
        }
        var output = [Float](repeating: 0, count: n)
        let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(kFFTDirection_Inverse))
                output.withUnsafeMutableBufferPointer { out in
                    out.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
                    }
                }
            }
        }
        let scale = 1 / Float(2 * n)
        return output.map { $0 * scale }
    }

    // MARK: Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("FRAME")
            tool("DUPLICATE") {
                frames.insert(frames[selected], at: selected + 1)
                selected += 1
            }
            .disabled(frames.count >= Int(LY_WT_MAX_FRAMES))
            tool("DELETE") {
                frames.remove(at: selected)
                selected = min(selected, frames.count - 1)
                refreshHarmonics()
            }
            .disabled(frames.count <= 1)
            tool("NORMALIZE") { edit { frame in
                let peak = max(frame.map(abs).max() ?? 0, 0.000_1)
                return frame.map { $0 / peak }
            } }
            tool("SMOOTH") { edit { frame in
                (0..<frame.count).map { i in
                    (frame[(i - 2 + frame.count) % frame.count] + frame[(i - 1 + frame.count) % frame.count] + frame[i]
                     + frame[(i + 1) % frame.count] + frame[(i + 2) % frame.count]) / 5
                }
            } }
            tool("REVERSE") { edit { $0.reversed() } }
            tool("INVERT") { edit { $0.map { -$0 } } }
            tool("REMOVE DC") { edit { frame in
                let mean = frame.reduce(0, +) / Float(frame.count)
                return frame.map { $0 - mean }
            } }

            section("TABLE")
            HStack(spacing: 4) {
                LYSynthStepper(label: "FROM", text: "\(morphFrom + 1)", accent: accent) { morphFrom = min(max(morphFrom + $0, 0), frames.count - 1) }
                LYSynthStepper(label: "TO", text: "\(morphTo + 1)", accent: accent) { morphTo = min(max(morphTo + $0, 0), frames.count - 1) }
            }
            tool("CROSSFADE BETWEEN") { morph(spectral: false) }
            tool("SPECTRAL MORPH") { morph(spectral: true) }
            tool("RESIZE TO 64") { resize(64) }
            tool("RESIZE TO 256") { resize(256) }
            Spacer()
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(LYLLTHTheme.label(7.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(LYLLTHTheme.dim)
            .padding(.top, 4)
    }

    private func tool(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(LYLLTHTheme.text)
                .frame(maxWidth: .infinity, minHeight: 24)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func edit(_ transform: ([Float]) -> [Float]) {
        guard frames.indices.contains(selected) else { return }
        frames[selected] = transform(frames[selected])
        refreshHarmonics()
    }

    /// Fills every frame strictly between FROM and TO, either by crossfading
    /// samples or by interpolating harmonic magnitudes (which keeps partials
    /// from cancelling out halfway).
    private func morph(spectral: Bool) {
        let a = min(morphFrom, morphTo), b = max(morphFrom, morphTo)
        guard b - a >= 2 else { return }
        let first = frames[a], last = frames[b]
        let s0 = spectral ? Self.spectrum(first) : nil
        let s1 = spectral ? Self.spectrum(last) : nil
        for f in (a + 1)..<b {
            let t = Float(f - a) / Float(b - a)
            if let s0, let s1 {
                let magnitudes = zip(s0.magnitudes, s1.magnitudes).map { $0 + ($1 - $0) * t }
                frames[f] = Self.synthesize(Spectrum(magnitudes: magnitudes, phases: t < 0.5 ? s0.phases : s1.phases))
            } else {
                frames[f] = zip(first, last).map { $0 + ($1 - $0) * t }
            }
        }
        refreshHarmonics()
    }

    private func resize(_ count: Int) {
        guard !frames.isEmpty else { return }
        let source = frames
        frames = (0..<count).map { f in
            let position = Float(f) / Float(max(count - 1, 1)) * Float(source.count - 1)
            let i = Int(position), t = position - Float(i)
            let j = min(i + 1, source.count - 1)
            return zip(source[i], source[j]).map { $0 + ($1 - $0) * t }
        }
        selected = min(selected, frames.count - 1)
        morphFrom = 0
        morphTo = frames.count - 1
        refreshHarmonics()
    }
}

private struct LYFrameThumbnail: View {
    let samples: [Float]
    let accent: Color
    let isSelected: Bool
    let number: Int

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let points = 64
            for i in 0..<points {
                let sample = samples[i * samples.count / points]
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(points - 1), y: size.height / 2 - CGFloat(max(-1, min(1, sample))) * (size.height / 2 - 3))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(isSelected ? accent : Color.white.opacity(0.35)), lineWidth: isSelected ? 1.5 : 1)
        }
        .overlay(alignment: .topLeading) {
            Text("\(number)").font(LYLLTHTheme.value(7.5)).foregroundStyle(LYLLTHTheme.dim).padding(3)
        }
        .background(isSelected ? accent.opacity(0.1) : Color.clear)
        .overlay(Rectangle().stroke(isSelected ? accent : LYLLTHTheme.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}
