import SwiftUI
import NightshapeAudioEngine

/// The exact dense-ripple take used behind DrumKit's sequencer. It is frozen at
/// the same time value so the crisp background and every glass cell share one
/// continuous image instead of each control inventing its own decoration.
private struct LYDrumKitWave: View {
    var lineWidth: CGFloat = 3
    var intensity: Double = 1

    var body: some View {
        Canvas { context, size in
            let layers: [(CGFloat, Double, Double, Double)] = [
                (1.00, 4.5, 1.0, 0.90),
                (0.60, 8.0, 1.6, 0.50),
                (0.40, 14.0, 2.4, 0.32)
            ]
            let time = 3.4
            let diagonal = hypot(size.width, size.height)
            let bandWidth = diagonal * 1.5
            let middle = diagonal * 0.5
            let baseAmplitude = diagonal * 0.11
            var drawing = context
            drawing.translateBy(x: size.width / 2, y: size.height / 2)
            drawing.rotate(by: .degrees(-63))
            drawing.translateBy(x: -bandWidth / 2, y: -middle)

            for layer in layers {
                var path = Path()
                var x: CGFloat = 0
                var first = true
                let radians = layer.1 * 2 * Double.pi
                while x <= bandWidth {
                    let fraction = Double(x / bandWidth)
                    let envelope = sin(time * 0.3 + fraction * 2.3)
                    let amplitude = baseAmplitude * layer.0
                    let y = middle
                        + CGFloat(sin(fraction * radians + time * layer.2)) * amplitude * CGFloat(envelope)
                        + CGFloat(sin(fraction * radians * 2.3 + time * layer.2 * 1.5)) * amplitude * 0.3
                    let point = CGPoint(x: x, y: y)
                    if first { path.move(to: point); first = false } else { path.addLine(to: point) }
                    x += 4
                }
                let alpha = layer.3 * 0.9 * intensity
                drawing.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            LYLLTHTheme.teal.opacity(alpha),
                            LYLLTHTheme.indigo.opacity(alpha),
                            LYLLTHTheme.purple.opacity(alpha)
                        ]),
                        startPoint: CGPoint(x: 0, y: middle),
                        endPoint: CGPoint(x: bandWidth, y: middle)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct LYDrumKitSequencerBackdrop: View {
    var body: some View {
        ZStack {
            LYLLTHTheme.background
            LYDrumKitWave()
            Color.black.opacity(0.72)
        }
        .allowsHitTesting(false)
    }
}

struct LYDrumKitGlassSurface: View {
    var body: some View {
        ZStack {
            // The source iPhone view samples one shared, screen-aligned wave image
            // through every cell. Keep that architecture here: the matrix owns the
            // single Canvas and these translucent panes reveal it. Rendering a full
            // wave Canvas in every one of 1,024 possible cells stalls transport UI.
            LYLLTHTheme.background.opacity(0.76)
            Color.black.opacity(0.26)
            Color(hex: 0x8A8A98).opacity(0.05)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

struct LYPatternPlaybackVisualizer: View {
    let session: LYLLTHSession
    let patternIndex: Int
    let currentStep: Int
    let isPlaying: Bool
    @ObservedObject var waveformState: OutputWaveformState

    private static let matrixGradient = Gradient(colors: [Color(hex: 0x0C0E13), Color(hex: 0x070709)])
    private static let offBright = Color.white.opacity(0.024)
    private static let beatHairline = Color.white.opacity(0.085)
    private static let stepHairline = Color.white.opacity(0.035)
    private static let laneHairline = Color.white.opacity(0.03)

    private var tracks: [LYTrack] {
        Array(session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }.prefix(16))
    }

    private var stepCount: Int {
        let count = tracks.compactMap { activeClip(in: $0)?.steps?.count }.max() ?? 16
        return min(max(count, 1), 64)
    }

    var body: some View {
        ZStack {
            Color(hex: 0x08090B)
            Canvas { context, size in drawActivity(in: size, context: &context) }
            Canvas { context, size in drawWaveform(in: size, context: &context) }
                .allowsHitTesting(false)
        }
        .overlay(Rectangle().strokeBorder(LYLLTHTheme.teal, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern playback visualizer")
        .accessibilityValue("Step \(currentStep + 1) of \(stepCount)")
    }

    private func activeClip(in track: LYTrack) -> LYClip? {
        let clips = track.clips.filter { $0.kind == .pattern || $0.kind == .midi }
        guard !clips.isEmpty else { return nil }
        return clips[min(max(patternIndex, 0), clips.count - 1)]
    }

    private func drawActivity(in size: CGSize, context: inout GraphicsContext) {
        guard size.width > 1, size.height > 1 else { return }
        let rowCount = max(1, tracks.count)
        let pad: CGFloat = 2
        let railHeight: CGFloat = 4
        let railGap: CGFloat = 5
        let top = pad + railHeight + railGap
        let width = max(1, size.width - pad * 2)
        let height = max(1, size.height - top - pad)
        let slotWidth = width / CGFloat(stepCount)
        let laneHeight = height / CGFloat(rowCount)

        context.fill(
            Path(CGRect(x: pad, y: top, width: width, height: height)),
            with: .linearGradient(Self.matrixGradient, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height))
        )

        for rowIndex in tracks.indices {
            let track = tracks[rowIndex]
            let steps = activeClip(in: track)?.steps ?? []
            let locks = activeClip(in: track)?.stepParameters ?? []
            let accent = LYLLTHTheme.trackAccent(position: rowIndex)
            let y = top + CGFloat(rowIndex) * laneHeight
            let inset = min(1.25, laneHeight * 0.16)
            for step in 0..<stepCount {
                let rect = CGRect(
                    x: pad + CGFloat(step) * slotWidth,
                    y: y + inset,
                    width: slotWidth,
                    height: max(1, laneHeight - inset * 2)
                )
                let enabled = steps.indices.contains(step) && steps[step]
                if enabled {
                    let velocity = locks.indices.contains(step) ? locks[step].velocity : 0.82
                    context.fill(Path(rect), with: .color(accent.opacity(0.30 + velocity * 0.58)))
                    let capHeight = max(1.5, rect.height * (0.32 + CGFloat(velocity) * 0.5))
                    context.fill(
                        Path(CGRect(x: rect.minX, y: rect.maxY - capHeight, width: rect.width, height: capHeight)),
                        with: .color(accent.opacity(0.32 + velocity * 0.42))
                    )
                } else {
                    context.fill(Path(rect), with: .color(Self.offBright))
                }
            }
        }

        for step in 0...stepCount {
            let x = pad + CGFloat(step) * slotWidth
            context.fill(
                Path(CGRect(x: floor(x), y: top, width: 0.5, height: height)),
                with: .color(step.isMultiple(of: 4) ? Self.beatHairline : Self.stepHairline)
            )
        }
        for row in 0...rowCount {
            let y = top + CGFloat(row) * laneHeight
            context.fill(Path(CGRect(x: pad, y: floor(y), width: width, height: 0.5)), with: .color(Self.laneHairline))
        }

        guard (0..<stepCount).contains(currentStep) else { return }
        let stepLeft = pad + CGFloat(currentStep) * slotWidth
        let markerX = stepLeft + slotWidth * 0.5
        let alpha = isPlaying ? 1.0 : 0.4
        let trailWidth = min(slotWidth * 1.85, markerX - pad)
        let trail = CGRect(x: markerX - trailWidth, y: top, width: trailWidth, height: height)
        context.fill(
            Path(roundedRect: trail, cornerRadius: min(4, trailWidth * 0.18)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: LYLLTHTheme.purple.opacity(0), location: 0),
                    .init(color: LYLLTHTheme.purple.opacity(0.045 * alpha), location: 0.52),
                    .init(color: LYLLTHTheme.purple.opacity(0.20 * alpha), location: 1)
                ]),
                startPoint: CGPoint(x: trail.minX, y: trail.midY),
                endPoint: CGPoint(x: trail.maxX, y: trail.midY)
            )
        )
        context.fill(
            Path(roundedRect: CGRect(x: stepLeft, y: top, width: slotWidth, height: height), cornerRadius: min(4, slotWidth * 0.16)),
            with: .color(LYLLTHTheme.purple.opacity(0.15 * alpha))
        )
        let markerWidth = max(1.5, slotWidth * 0.10)
        context.fill(
            Path(roundedRect: CGRect(x: markerX - markerWidth * 0.5, y: top, width: markerWidth, height: height), cornerRadius: markerWidth * 0.5),
            with: .color(LYLLTHTheme.purple.opacity(0.78 * alpha))
        )

        let pageCount = max(1, Int(ceil(Double(stepCount) / 8.0)))
        let activePage = min(pageCount - 1, currentStep / 8)
        let gap: CGFloat = 4
        let segmentWidth = max(1, (width - gap * CGFloat(max(0, pageCount - 1))) / CGFloat(pageCount))
        for page in 0..<pageCount {
            let rect = CGRect(x: pad + CGFloat(page) * (segmentWidth + gap), y: pad, width: segmentWidth, height: railHeight)
            if page == activePage {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: railHeight / 2),
                    with: .linearGradient(
                        Gradient(colors: [LYLLTHTheme.teal, LYLLTHTheme.purple]),
                        startPoint: CGPoint(x: rect.minX, y: 0),
                        endPoint: CGPoint(x: rect.maxX, y: 0)
                    )
                )
            } else {
                context.fill(Path(roundedRect: rect, cornerRadius: railHeight / 2), with: .color(Color.white.opacity(0.09)))
            }
        }
    }

    private func drawWaveform(in size: CGSize, context: inout GraphicsContext) {
        let samples = waveformState.value.samples
        guard samples.count > 1 else { return }
        let rect = CGRect(x: 3, y: 8, width: max(1, size.width - 6), height: max(1, size.height - 16))
        let centerY = rect.midY
        let amplitude = rect.height * 0.38
        var trace = Path()
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = centerY - CGFloat(max(-1, min(1, sample))) * amplitude
            if index == 0 { trace.move(to: CGPoint(x: x, y: y)) } else { trace.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(
            trace,
            with: .linearGradient(
                Gradient(colors: [
                    LYLLTHTheme.teal.opacity(0.58),
                    LYLLTHTheme.indigo.opacity(0.74),
                    LYLLTHTheme.purple.opacity(0.66)
                ]),
                startPoint: CGPoint(x: rect.minX, y: centerY),
                endPoint: CGPoint(x: rect.maxX, y: centerY)
            ),
            lineWidth: 1.15
        )
    }
}
