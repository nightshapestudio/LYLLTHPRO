import SwiftUI
import AppKit

// MARK: - Live readout

/// Polls the running synth once per display frame for what the editor animates:
/// modulated wavetable positions, envelope levels, LFO phases, cutoff, scope.
@MainActor
final class LYSynthLive: ObservableObject {
    @Published private(set) var display = LYSynthDisplay()
    @Published private(set) var scope: [Float] = Array(repeating: 0, count: 256)
    private var ticks: LYFrameToken?
    private weak var instrument: LYSynthInstrument?

    func attach(_ instrument: LYSynthInstrument?) {
        self.instrument = instrument
        guard ticks == nil else { return }
        ticks = LYFrameClock.shared.add { [weak self] in self?.poll() }
    }

    func detach() {
        ticks?.cancel()
        ticks = nil
    }

    private func poll() {
        guard let instrument else { return }
        display = instrument.display()
        scope = instrument.scope(count: 256)
    }

    func fxLevel(_ fx: Int) -> Float {
        withUnsafeBytes(of: display.fxLevel) { raw in
            let values = raw.bindMemory(to: Float.self)
            return fx >= 0 && fx < values.count ? values[fx] : 0
        }
    }

    var compGain: [Float] { [display.compGain.0, display.compGain.1, display.compGain.2] }

    func modulation(_ destination: Int) -> Float {
        withUnsafeBytes(of: display.modulation) { raw in
            let values = raw.bindMemory(to: Float.self)
            return destination >= 0 && destination < values.count ? values[destination] : 0
        }
    }

    func envelope(_ index: Int) -> Float {
        [display.envelope.0, display.envelope.1, display.envelope.2, display.envelope.3][min(max(index, 0), 3)]
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


// MARK: - Displays

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

/// Both filters' responses over one frequency axis, at their live
/// modulated cutoffs: filter 1 in teal, filter 2 in indigo, and their sum
/// (serial or parallel) as a filled shape.
struct LYFilterCurve: View {
    let patch: LYSynthPatch
    @ObservedObject var live: LYSynthLive

    static func magnitude(type: Int, hz: Double, cutoff: Double, res: Double, morph: Double = 0) -> Double {
        let w = hz / cutoff
        let w2 = w * w
        let k = 2 - 1.97 * res, k2 = 2 - 1.2 * res
        func den(_ kk: Double) -> Double { sqrt(pow(1 - w2, 2) + pow(w * kk, 2)) }
        switch type {
        case LY_FILTER_LP12: return 1 / den(k)
        case LY_FILTER_LP24: return (1 / den(k)) * (1 / den(k2))
        case LY_FILTER_HP12: return w2 / den(k)
        case LY_FILTER_HP24: return (w2 / den(k)) * (w2 / den(k2))
        case LY_FILTER_BP: return (w * k) / den(k)
        case LY_FILTER_BP24: return ((w * k) / den(k)) * ((w * k2) / den(k2))
        case LY_FILTER_NOTCH: return abs(1 - w2) / den(k)
        case LY_FILTER_MORPH:
            // Low-pass and high-pass summed: (a - b·w²) over the same denominator.
            let a = min(1, 2 * (1 - morph)), b = min(1, 2 * morph)
            return abs(a - b * w2) / den(k)
        case LY_FILTER_LADDER: return (1 / den(2 - 1.95 * res)) * (1 / den(2))
        case LY_FILTER_COMB_POS, LY_FILTER_COMB_NEG:
            // Peaks (or notches) at every multiple of the cutoff.
            let fb = (type == LY_FILTER_COMB_POS ? 1.0 : -1.0) * res * 0.96
            let phase = 2 * Double.pi * hz / cutoff
            return 1 / sqrt(1 + fb * fb - 2 * fb * cos(phase)) * (1 - abs(fb) * 0.5)
        case LY_FILTER_FORMANT:
            let vowels: [[Double]] = [[800, 1150, 2900], [400, 1700, 2600], [350, 1900, 2800], [450, 800, 2830], [325, 700, 2530]]
            let position = min(max(log(cutoff / 20) / log(1000), 0), 1) * 4
            let a = min(3, Int(position)), t = position - Double(a)
            let q = 1 / (0.9 - res * 0.8)
            var sum = 0.0
            for (b, gain) in [1.0, 0.6, 0.25].enumerated() {
                let centre = vowels[a][b] + (vowels[a + 1][b] - vowels[a][b]) * t
                let x = hz / centre
                sum += gain / sqrt(1 + q * q * pow(x - 1 / x, 2))
            }
            return sum * 1.2
        case LY_FILTER_PHASER:
            // Six allpasses against the dry signal: notches around the cutoff.
            let phase = 6 * 2 * atan(hz / cutoff)
            return abs(cos(phase / 2)) * (1 + res * 0.4)
        default: return 1
        }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
            for decade in [100.0, 1_000.0, 10_000.0] {
                let x = size.width * CGFloat(log10(decade / 20) / 3)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.05)))
                context.draw(Text(decade >= 1000 ? "\(Int(decade / 1000))K" : "\(Int(decade))").font(LYLLTHTheme.value(7)).foregroundColor(LYLLTHTheme.dim),
                             at: CGPoint(x: x + 10, y: size.height - 8))
            }
            let zeroY = size.height * 0.45
            context.fill(Path(CGRect(x: 0, y: zeroY, width: size.width, height: 1)), with: .color(Color.white.opacity(0.05)))
            let active = live.display.activeVoices > 0
            let oneOn = patch.value(LY_FILTER_ON) > 0.5, twoOn = patch.value(LY_F2_ON) > 0.5
            let parallel = Int(patch.value(LY_FILTER_ROUTING).rounded()) != LY_ROUTING_SERIAL
            func cutoff(_ id: Int, live: Float) -> Double {
                active && live > 0 ? Double(live) : 20 * pow(1000, Double(patch.value(id)))
            }
            let c1 = cutoff(LY_FILTER_CUTOFF, live: live.display.cutoffHz), c2 = cutoff(LY_F2_CUTOFF, live: live.display.cutoff2Hz)
            func one(_ hz: Double) -> Double {
                let m = Self.magnitude(type: Int(patch.value(LY_FILTER_TYPE)), hz: hz, cutoff: c1, res: Double(patch.value(LY_FILTER_RES)),
                                       morph: Double(patch.value(LY_FILTER_MORPH_POS)))
                let mix = Double(patch.value(LY_FILTER_MIX))
                return 1 + (m - 1) * mix
            }
            func two(_ hz: Double) -> Double {
                let m = Self.magnitude(type: Int(patch.value(LY_F2_TYPE)), hz: hz, cutoff: c2, res: Double(patch.value(LY_F2_RES)),
                                       morph: Double(patch.value(LY_F2_MORPH)))
                let mix = Double(patch.value(LY_F2_MIX))
                return 1 + (m - 1) * mix
            }
            func y(_ magnitude: Double) -> CGFloat {
                let dB = 20 * log10(max(magnitude, 0.00001))
                return min(max(zeroY - CGFloat(dB / 30) * zeroY, 2), size.height)
            }
            let steps = Int(size.width / 2)
            func path(_ f: (Double) -> Double) -> Path {
                var path = Path()
                for i in 0...steps {
                    let x = size.width * CGFloat(i) / CGFloat(steps)
                    let hz = 20 * pow(1000, Double(i) / Double(steps))
                    let point = CGPoint(x: x, y: y(f(hz)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                return path
            }
            // Combined response, filled.
            let combined: (Double) -> Double = { hz in
                switch (oneOn, twoOn) {
                case (true, true): return parallel ? (one(hz) + two(hz)) * 0.5 * 1.4 : one(hz) * two(hz)
                case (true, false): return one(hz)
                case (false, true): return two(hz)
                default: return 1
                }
            }
            var fill = path(combined)
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .color(LYLLTHTheme.teal.opacity(oneOn || twoOn ? 0.1 : 0.03)))
            if twoOn {
                context.stroke(path(two), with: .color(LYLLTHTheme.indigo.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: oneOn ? [4, 3] : []))
                let x = size.width * CGFloat(log10(c2 / 20) / 3)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(LYLLTHTheme.indigo.opacity(0.35)))
            }
            if oneOn {
                context.stroke(path(one), with: .color(LYLLTHTheme.teal.opacity(twoOn ? 0.6 : 1)), style: StrokeStyle(lineWidth: 1.2, dash: twoOn ? [4, 3] : []))
                let x = size.width * CGFloat(log10(c1 / 20) / 3)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(LYLLTHTheme.teal.opacity(0.35)))
            }
            if oneOn && twoOn {
                var glow = context
                glow.addFilter(.shadow(color: LYLLTHTheme.teal.opacity(0.7), radius: 3))
                glow.stroke(path(combined), with: .color(LYLLTHTheme.text.opacity(0.9)), lineWidth: 1.5)
            }
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}


/// AHDSR you can drag directly: attack by its peak, hold by the end of the
/// plateau, decay and sustain by their corner, release by its end, and each
/// stage's curve by the diamond at its middle. A line tracks the level
/// while notes play.
struct LYEnvelopeGraph: View {
    let attack: Float, hold: Float, decay: Float, sustain: Float, release: Float
    let curves: [Float]            // attack, decay, release
    let color: Color
    @ObservedObject var live: LYSynthLive
    let envelopeIndex: Int
    private var level: Float { live.envelope(envelopeIndex) }
    /// Parameter offsets from the envelope's attack: 0 A, 1 D, 2 S, 3 R; `setHold` for hold.
    let set: (Int, Float) -> Void
    let setHold: (Float) -> Void
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
            let slot = size.width / 4.6
            let top: CGFloat = 10, bottom = size.height - 10
            let height = bottom - top
            let a = CGPoint(x: slot * CGFloat(0.06 + 0.94 * attack), y: top)
            let h = CGPoint(x: a.x + slot * 0.6 * CGFloat(hold), y: top)
            let d = CGPoint(x: h.x + slot * CGFloat(0.08 + 0.92 * decay), y: bottom - height * CGFloat(sustain))
            let s = CGPoint(x: d.x + slot * 0.7, y: d.y)
            let r = CGPoint(x: s.x + slot * CGFloat(0.06 + 0.94 * release), y: bottom)
            let attackMid = CGPoint(x: a.x / 2, y: bottom - height * CGFloat(shape(0.5, curves[0])))
            let decayMid = CGPoint(x: (h.x + d.x) / 2, y: bottom - height * CGFloat(Double(sustain) + (1 - Double(sustain)) * (1 - shape(0.5, curves[1]))))
            let releaseMid = CGPoint(x: (s.x + r.x) / 2, y: bottom - height * CGFloat(Double(sustain) * (1 - shape(0.5, curves[2]))))
            ZStack {
                Canvas { context, _ in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
                    for i in 1..<8 {
                        let y = top + height * CGFloat(i) / 8
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.03)))
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: bottom))
                    for i in 1...24 {
                        let p = Double(i) / 24
                        path.addLine(to: CGPoint(x: a.x * CGFloat(p), y: bottom - height * CGFloat(shape(p, curves[0]))))
                    }
                    path.addLine(to: h)
                    for i in 1...24 {
                        let p = Double(i) / 24
                        let v = Double(sustain) + (1 - Double(sustain)) * (1 - shape(p, curves[1]))
                        path.addLine(to: CGPoint(x: h.x + (d.x - h.x) * CGFloat(p), y: bottom - height * CGFloat(v)))
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
                    context.fill(fill, with: .color(color.opacity(0.13)))
                    var glow = context
                    glow.addFilter(.shadow(color: color.opacity(0.6), radius: 3))
                    glow.stroke(path, with: .color(color), lineWidth: 1.6)
                    // Stage labels along the bottom.
                    for (label, x) in [("A", a.x / 2), ("H", (a.x + h.x) / 2), ("D", (h.x + d.x) / 2), ("S", (d.x + s.x) / 2), ("R", (s.x + r.x) / 2)]
                    where label != "H" || hold > 0.01 {
                        context.draw(Text(label).font(LYLLTHTheme.label(6.5, weight: .bold)).foregroundColor(LYLLTHTheme.dim),
                                     at: CGPoint(x: x, y: bottom + 5))
                    }
                    if level > 0.001 {
                        let y = bottom - height * CGFloat(level)
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color.opacity(0.4)))
                    }
                }
                ForEach(Array([a, h, d, r].enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.black)
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                        .frame(width: index == 1 ? 8 : 10, height: index == 1 ? 8 : 10)
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    switch index {
                                    case 0: set(0, clamp(Float((drag.location.x / slot - 0.06) / 0.94)))
                                    case 1: setHold(clamp(Float((drag.location.x - a.x) / (slot * 0.6))))
                                    case 2:
                                        set(1, clamp(Float(((drag.location.x - h.x) / slot - 0.08) / 0.92)))
                                        set(2, clamp(Float((bottom - drag.location.y) / height)))
                                    default: set(3, clamp(Float(((drag.location.x - s.x) / slot - 0.06) / 0.94)))
                                    }
                                }
                        )
                        .help(["Attack: drag sideways", "Hold: drag sideways", "Decay and sustain: drag anywhere", "Release: drag sideways"][index])
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


/// The LFO's shape with a playhead, its phase offset applied, and its
/// DELAY and RISE drawn as a shaded lead-in. In DRAW the shape is 32 points
/// you paint with the pointer.
struct LYLFOGraph: View {
    let shape: Int
    let points: [Float]
    let smooth: Bool
    var phaseOffset: Float = 0
    var delay: Float = 0
    var rise: Float = 0
    var oneShot = false
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
                for i in 1..<8 {
                    let x = size.width * CGFloat(i) / 8
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(i == 4 ? 0.06 : 0.03)))
                }
                context.fill(Path(CGRect(x: 0, y: mid, width: size.width, height: 1)), with: .color(Color.white.opacity(0.06)))
                if shape == LY_LFO_CUSTOM {
                    for i in 0..<points.count {
                        let x = size.width * CGFloat(i) / CGFloat(points.count)
                        context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.035)))
                    }
                }
                var path = Path()
                var fill = Path()
                fill.move(to: CGPoint(x: 0, y: mid))
                let steps = Int(size.width)
                for x in 0...steps {
                    var p = Double(x) / Double(steps) + Double(phaseOffset)
                    p -= floor(p)
                    let point = CGPoint(x: CGFloat(x), y: mid - CGFloat(Self.value(shape: shape, at: min(p, 0.9999), points: points, smooth: smooth)) * (mid - 8))
                    if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    fill.addLine(to: point)
                }
                fill.addLine(to: CGPoint(x: size.width, y: mid))
                fill.closeSubpath()
                context.fill(fill, with: .color(color.opacity(0.1)))
                var glow = context
                glow.addFilter(.shadow(color: color.opacity(0.6), radius: 3))
                glow.stroke(path, with: .color(color), lineWidth: 1.6)
                // DELAY and RISE: how the LFO fades in after each note.
                if delay > 0.001 || rise > 0.001 {
                    let total = max(delay + rise, 0.001) * 4
                    let lane = CGRect(x: 0, y: size.height - 12, width: size.width * 0.35, height: 8)
                    let dx = lane.width * CGFloat(delay * 4 / total)
                    context.fill(Path(CGRect(x: lane.minX, y: lane.minY, width: dx, height: lane.height)), with: .color(Color.white.opacity(0.08)))
                    var ramp = Path()
                    ramp.move(to: CGPoint(x: dx, y: lane.maxY))
                    ramp.addLine(to: CGPoint(x: lane.maxX, y: lane.minY))
                    ramp.addLine(to: CGPoint(x: lane.maxX, y: lane.maxY))
                    ramp.closeSubpath()
                    context.fill(ramp, with: .color(color.opacity(0.35)))
                    context.draw(Text("DELAY \(String(format: "%.2f", delay * 4)) S · RISE \(String(format: "%.2f", rise * 4)) S")
                                    .font(LYLLTHTheme.label(6.5, weight: .bold)).foregroundColor(LYLLTHTheme.dim),
                                 at: CGPoint(x: lane.maxX + 70, y: lane.midY))
                }
                let state = live.lfo(index)
                let x = CGFloat(state.phase) * size.width
                let y = mid - CGFloat(state.value) * (mid - 8)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(color.opacity(0.3)))
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(LYLLTHTheme.text))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard shape == LY_LFO_CUSTOM, !points.isEmpty else { return }
                        var p = Double(drag.location.x / geo.size.width) + Double(phaseOffset)
                        p -= floor(p)
                        let i = min(max(Int(p * Double(points.count)), 0), points.count - 1)
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


/// The output, twice: a scope of the waveform and, behind it, a slow-moving
/// glow of its level.
struct LYSynthScope: View {
    @ObservedObject var live: LYSynthLive
    var accent: Color = LYLLTHTheme.teal

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.6)))
            context.fill(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)), with: .color(Color.white.opacity(0.05)))
            let samples = live.scope
            guard samples.count > 1 else { return }
            // Start on a rising zero crossing so the waveform stands still.
            var start = 0
            for i in 1..<(samples.count / 2) where samples[i - 1] <= 0 && samples[i] > 0 { start = i; break }
            let shown = Array(samples[start...].prefix(samples.count / 2))
            guard shown.count > 1 else { return }
            var path = Path()
            for (i, sample) in shown.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(shown.count - 1),
                                    y: size.height / 2 - CGFloat(max(-1, min(1, sample))) * size.height * 0.45)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var glow = context
            glow.addFilter(.shadow(color: accent.opacity(0.8), radius: 3))
            glow.stroke(path, with: .color(accent), lineWidth: 1.3)
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}


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
struct LYSynthKeyMonitor: NSViewRepresentable {
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
        #if !LUNATK_PLUGIN
        // The app's Musical Typing (⌘K) has the keyboard while it is open.
        if LYMusicalTyping.isOpen { return false }
        #endif
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

/// The factory bank by category, the originals and the user's own sounds.
/// Hovering a sound shows what it is for and how to sit it in a mix.
struct LYPresetBrowser: View {
    let current: String
    let user: [LYSynthPatch]
    let choose: (LYSynthPatch) -> Void
    let delete: (String) -> Void
    let close: () -> Void

    @State private var category: String?
    @State private var hovered: LYSynthPatch?

    private var groups: [String] {
        LYSynthFactoryBank.categories.filter { c in LYSynthPatch.factory.contains { $0.category == c } } + ["ORIGINAL", "USER"]
    }

    private var selected: String {
        if let category { return category }
        if user.contains(where: { $0.name == current }) { return "USER" }
        return LYSynthPatch.factory.first { $0.name == current }?.category ?? groups.first ?? "USER"
    }

    private var items: [LYSynthPatch] {
        if selected == "USER" { return user }
        return LYSynthPatch.factory.filter { $0.category == selected }
    }

    private var shown: LYSynthPatch? {
        hovered ?? LYSynthPatch.factory.first { $0.name == current } ?? user.first { $0.name == current }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOUNDS").font(LYLLTHTheme.label(9, weight: .bold)).tracking(1.8).foregroundStyle(LYLLTHTheme.teal)
                Text("\(LYSynthFactoryBank.presets.count) FACTORY · \(user.count) USER")
                    .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.dim)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 3) {
                    ForEach(groups, id: \.self) { group in
                        Button { category = group; hovered = nil } label: {
                            HStack {
                                Text(group).font(LYLLTHTheme.label(8, weight: .bold)).tracking(1.1)
                                    .foregroundStyle(group == selected ? LYLLTHTheme.teal : LYLLTHTheme.text)
                                Spacer()
                                Text("\(group == "USER" ? user.count : LYSynthPatch.factory.filter { $0.category == group }.count)")
                                    .font(LYLLTHTheme.value(8)).foregroundStyle(LYLLTHTheme.dim)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(LYLLTHTheme.teal.opacity(group == selected ? 0.1 : 0))
                            .overlay(Rectangle().stroke(group == selected ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 120)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                        if items.isEmpty {
                            Text("SAVE A SOUND TO SEE IT HERE")
                                .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                                .frame(maxWidth: .infinity).padding(.top, 20)
                        }
                        ForEach(items, id: \.name) { item in
                            HStack(spacing: 0) {
                                Button { choose(item) } label: {
                                    Text(item.name)
                                        .font(LYLLTHTheme.label(8.5, weight: .bold)).tracking(0.8)
                                        .foregroundStyle(item.name == current ? LYLLTHTheme.teal : LYLLTHTheme.text)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                        .padding(.leading, 8)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if selected == "USER" {
                                    Button { delete(item.name) } label: {
                                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                                            .frame(width: 22, height: 26).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help("Delete this preset")
                                }
                            }
                            .background(LYLLTHTheme.teal.opacity(item.name == current ? 0.1 : (hovered?.name == item.name ? 0.05 : 0)))
                            .overlay(Rectangle().stroke(item.name == current ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong, lineWidth: 1))
                            .onHover { inside in hovered = inside ? item : (hovered?.name == item.name ? nil : hovered) }
                        }
                    }
                }
                .lyScrollers()
            }
            infoStrip
        }
        .padding(10)
        .background(Color(hex: 0x07080D).opacity(0.98))
        .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private var infoStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let patch = shown, let info = patch.info {
                HStack(spacing: 8) {
                    Text(patch.name).font(LYLLTHTheme.label(9, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.text)
                    Text(info.layer).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.teal)
                        .padding(.horizontal, 5).overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
                    Text(info.register.uppercased()).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                    Spacer(minLength: 0)
                }
                Text(info.role.uppercased()).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(0.8).foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                Text(("PLAY: " + info.playing + "  ·  MIX: " + info.mix).uppercased())
                    .font(LYLLTHTheme.label(7, weight: .bold)).tracking(0.6).foregroundStyle(LYLLTHTheme.dim)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("MACROS ON EVERY FACTORY SOUND: 1 TONE · 2 MOTION · 3 SPACE · 4 GRIT")
                    .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
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


// MARK: - LUNATK mark

/// LUNATK's mark: a crescent cut from a full moon, and the name in the
/// NIGHTSHAPE outline face lit in moonlight. The one gradient LUNATK uses.
struct LUNATKMark: View {
    var size: CGFloat = 26

    private var moonlight: LinearGradient {
        LinearGradient(colors: [LYLLTHTheme.chrome, LYLLTHTheme.lavender, LYLLTHTheme.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: size * 0.35) {
            ZStack {
                Circle().fill(moonlight)
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.86, height: size * 0.86)
                    .offset(x: size * 0.26, y: -size * 0.12)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: size, height: size)
            .shadow(color: LYLLTHTheme.lavender.opacity(0.45), radius: 6)
            Text("LUNATK")
                .font(LYLLTHTheme.wordmark(size))
                .tracking(size * 0.12)
                .fixedSize()
                .foregroundStyle(moonlight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LUNATK")
    }
}
