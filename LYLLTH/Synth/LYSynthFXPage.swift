import SwiftUI

/// LUNATK's effects rack: every effect in play order on the left, lit while
/// it is on and pulsing with its output; the chosen one on the right, large,
/// with a picture of what it is doing.
struct LYSynthFXPage: View {
    let context: LYSynthContext
    @AppStorage("lunatk.fx.selected") private var selected: Int = Int(LY_FX_HYPER)
    @State private var dropTarget: Int?

    static let onIDs: [Int] = [LY_HYPER_ON, LY_DIST_ON, LY_FLANGER_ON, LY_PHASER_ON, LY_CHORUS_ON,
                               LY_DELAY_ON, LY_COMP_ON, LY_EQ_ON, LY_FXF_ON, LY_REVERB_ON].map { Int($0) }

    static func accent(_ fx: Int) -> Color {
        switch fx {
        case LY_FX_HYPER, LY_FX_CHORUS, LY_FX_EQ: return LYLLTHTheme.teal
        case LY_FX_DIST, LY_FX_COMP, LY_FX_FILTER: return LYLLTHTheme.indigo
        case LY_FX_FLANGER, LY_FX_PHASER: return LYLLTHTheme.purple
        default: return LYLLTHTheme.lavender
        }
    }

    static let details = ["UNISON + DIMENSION", "10 CHARACTERS", "COMB SWEEP", "6-STAGE SWEEP", "2-VOICE ENSEMBLE",
                          "TEMPO · PING-PONG", "SINGLE OR MULTIBAND", "SHELF · PEAK · SHELF", "LP · HP · BP · COMB", "PLATE OR HALL"]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                rack
                AnyView(LYVocoderPanel(context: context)).frame(height: 236)
            }
            .frame(width: 260)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Rack

    private var rack: some View {
        let order = context.patch.effectOrder
        return LYSynthPanel(title: "FX RACK", accent: LYLLTHTheme.indigo) {
            Text("\(Self.onIDs.filter { context.isOn($0) }.count) ON")
                .font(LYLLTHTheme.value(8.5))
                .foregroundStyle(LYLLTHTheme.dim)
        } content: {
            VStack(spacing: 4) {
                ForEach(Array(order.enumerated()), id: \.element) { position, fx in
                    rackRow(fx: fx, position: position, order: order)
                }
                Spacer(minLength: 0)
                Text("SIGNAL RUNS TOP TO BOTTOM\nDRAG A ROW OR USE THE ARROWS TO REORDER")
                    .font(LYLLTHTheme.label(6.5, weight: .bold))
                    .tracking(1)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .frame(maxWidth: .infinity)
                Button {
                    var next = context.patch
                    next.setEffectOrder(LYSynthPatch.defaultEffectOrder)
                    context.replace(next)
                } label: {
                    Text("RESET ORDER")
                        .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1)
                        .foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rackRow(fx: Int, position: Int, order: [Int]) -> some View {
        let on = context.isOn(Self.onIDs[fx])
        let accent = Self.accent(fx)
        let isSelected = selected == fx
        return HStack(spacing: 7) {
            Text(String(format: "%02d", position + 1))
                .font(LYLLTHTheme.value(8))
                .foregroundStyle(LYLLTHTheme.dim)
                .frame(width: 16)
            Button { context.toggle(Self.onIDs[fx]) } label: {
                Rectangle()
                    .fill(on ? accent : Color.clear)
                    .frame(width: 6, height: 6)
                    .frame(width: 16, height: 16)
                    .overlay(Rectangle().stroke(on ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                    .lyBloom(accent, isOn: on && accent != LYLLTHTheme.teal, strength: 0.6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(on ? "Turn \(LYSynthNames.effects[fx]) off" : "Turn \(LYSynthNames.effects[fx]) on")
            VStack(alignment: .leading, spacing: 2) {
                Text(LYSynthNames.effects[fx])
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(on ? LYLLTHTheme.text : LYLLTHTheme.dim)
                LYFXLevelBar(live: context.live, fx: fx, accent: accent, isOn: on)
                    .frame(height: 2)
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                arrow("chevron.up", enabled: position > 0) { move(order, from: position, to: position - 1) }
                arrow("chevron.down", enabled: position < order.count - 1) { move(order, from: position, to: position + 1) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(accent.opacity(isSelected ? 0.12 : (on ? 0.04 : 0)))
        .overlay(Rectangle().stroke(isSelected ? accent : LYLLTHTheme.lineStrong, lineWidth: isSelected ? 1.2 : 1))
        .overlay(alignment: .top) { if dropTarget == fx { Rectangle().fill(accent).frame(height: 2) } }
        .contentShape(Rectangle())
        .onTapGesture { selected = fx }
        .draggable("lunatk-fx:\(fx)")
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, item.hasPrefix("lunatk-fx:"), let moving = Int(item.dropFirst(10)),
                  let from = order.firstIndex(of: moving) else { return false }
            move(order, from: from, to: position)
            return true
        } isTargeted: { dropTarget = $0 ? fx : (dropTarget == fx ? nil : dropTarget) }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(enabled ? LYLLTHTheme.chromeText : LYLLTHTheme.dim.opacity(0.3))
                .frame(width: 18, height: 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func move(_ order: [Int], from: Int, to: Int) {
        guard from != to, order.indices.contains(from), order.indices.contains(to) else { return }
        var next = order
        let item = next.remove(at: from)
        next.insert(item, at: to)
        var patch = context.patch
        patch.setEffectOrder(next)
        context.replace(patch)
    }

    // MARK: Detail

    private var detail: some View {
        let fx = min(max(selected, 0), Int(LY_FX_COUNT) - 1)
        let accent = Self.accent(fx)
        let on = context.isOn(Self.onIDs[fx])
        return LYSynthPanel(title: LYSynthNames.effects[fx], accent: accent, isOn: on, toggle: { context.toggle(Self.onIDs[fx]) }) {
            Text(Self.details[fx])
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(LYLLTHTheme.dim)
        } content: {
            VStack(spacing: 12) {
                LYFXVisual(fx: fx, patch: context.patch, live: context.live, accent: accent, set: context.set)
                    .frame(maxHeight: .infinity)
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                controls(fx, accent: accent)
                    .frame(height: 70)
            }
        }
    }

    @ViewBuilder
    private func controls(_ fx: Int, accent: Color) -> some View {
        let c = context
        let pct = { (v: Float) in String(format: "%.0f%%", v * 100) }
        HStack(alignment: .center, spacing: 10) {
            switch fx {
            case LY_FX_HYPER:
                c.knob(LY_HYPER_RATE, accent: accent, diameter: 34, format: pct)
                c.knob(LY_HYPER_DETUNE, LY_DST_HYPER_DETUNE, accent: accent, diameter: 34)
                c.knob(LY_HYPER_VOICES, accent: accent, diameter: 34, format: { "\(1 + Int(($0 * 6).rounded()))" })
                c.knob(LY_HYPER_MIX, LY_DST_HYPER_MIX, accent: accent, diameter: 38)
                divider
                c.knob(LY_HYPER_DIM_SIZE, accent: LYLLTHTheme.lavender, diameter: 34)
                c.knob(LY_HYPER_DIM_MIX, LY_DST_DIM_MIX, accent: LYLLTHTheme.lavender, diameter: 38)
            case LY_FX_DIST:
                c.choice(LY_DIST_MODE, label: "MODE", names: LYSynthNames.distortionModes, accent: accent, columns: 2, width: 240, anchor: "distMode")
                    .frame(width: 120)
                c.knob(LY_DIST_DRIVE, LY_DST_DIST_DRIVE, accent: accent, diameter: 40, format: { String(format: "%.0f DB", $0 * 36) })
                c.knob(LY_DIST_TONE, accent: accent, diameter: 34, format: { v in
                    let hz = 400 * pow(50, v); return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
                })
                c.knob(LY_DIST_MIX, LY_DST_DIST_MIX, accent: accent, diameter: 38)
            case LY_FX_FLANGER:
                c.knob(LY_FLANGER_RATE, accent: accent, diameter: 34, format: { String(format: "%.2f HZ", 0.02 + $0 * $0 * 5) })
                c.knob(LY_FLANGER_DEPTH, LY_DST_FLANGER_DEPTH, accent: accent, diameter: 34)
                c.knob(LY_FLANGER_FEEDBACK, accent: accent, diameter: 34, format: { String(format: "%+.0f%%", ($0 * 2 - 1) * 92) })
                c.knob(LY_FLANGER_MIX, LY_DST_FLANGER_MIX, accent: accent, diameter: 38)
            case LY_FX_PHASER:
                c.knob(LY_PHASER_RATE, accent: accent, diameter: 34, format: { String(format: "%.2f HZ", 0.02 + $0 * $0 * 6) })
                c.knob(LY_PHASER_DEPTH, accent: accent, diameter: 34)
                c.knob(LY_PHASER_FREQ, LY_DST_PHASER_FREQ, accent: accent, diameter: 38, format: { v in
                    let hz = 100 * pow(80, v); return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
                })
                c.knob(LY_PHASER_FEEDBACK, accent: accent, diameter: 34)
                c.knob(LY_PHASER_MIX, LY_DST_PHASER_MIX, accent: accent, diameter: 38)
            case LY_FX_CHORUS:
                // CLASSIC is LUNATK's own chorus; SUBTLE, WIDE and DEEP are the
                // NIGHTSHAPE track chorus, modelled on the Juno's.
                let juno = Int(c.value(LY_CHORUS_MODE)) != LY_CHORUS_CLASSIC
                c.choice(LY_CHORUS_MODE, label: "MODE", names: LYSynthNames.chorusModes, accent: accent, columns: 4, width: 300, anchor: "chorusMode")
                    .frame(width: 104)
                if juno {
                    c.knob(LY_CHORUS_RATE, accent: accent, diameter: 34, format: { String(format: "%.2f HZ", 0.05 * pow(70, $0)) })
                    c.knob(LY_CHORUS_DEPTH, LY_DST_CHORUS_DEPTH, accent: accent, diameter: 38, format: { String(format: "%.0f%%", $0 * 100) })
                    c.knob(LY_CHORUS_WIDTH, accent: accent, diameter: 34, format: { String(format: "%.0f%%", $0 * 100) })
                } else {
                    c.knob(LY_CHORUS_RATE, accent: accent, diameter: 34, format: { String(format: "%.2f HZ", 0.05 + $0 * $0 * 5) })
                    c.knob(LY_CHORUS_DELAY, accent: accent, diameter: 34, format: { String(format: "%.1f MS", 4 + $0 * 26) })
                    c.knob(LY_CHORUS_DEPTH, LY_DST_CHORUS_DEPTH, accent: accent, diameter: 34)
                    c.knob(LY_CHORUS_FEEDBACK, accent: accent, diameter: 34)
                    c.knob(LY_CHORUS_TONE, accent: accent, diameter: 34)
                }
                c.knob(LY_CHORUS_MIX, LY_DST_CHORUS_MIX, accent: accent, diameter: 38)
            case LY_FX_DELAY:
                c.knob(LY_DELAY_TIME, accent: accent, diameter: 38, format: { v in
                    let i = Int((v * Float(LYSynthNames.syncDivisions.count - 1)).rounded())
                    return LYSynthNames.syncDivisions[min(max(i, 0), LYSynthNames.syncDivisions.count - 1)]
                })
                c.knob(LY_DELAY_FEEDBACK, LY_DST_DELAY_FEEDBACK, accent: accent, diameter: 34)
                c.knob(LY_DELAY_WIDTH, accent: accent, diameter: 30, label: "R OFFSET", format: { String(format: "+%.0f%%", $0 * 50) })
                LYSynthToggle(title: "PING-PONG", isOn: c.isOn(LY_DELAY_PINGPONG), accent: accent) { c.toggle(LY_DELAY_PINGPONG) }
                c.knob(LY_DELAY_LOWCUT, accent: accent, diameter: 30, format: { String(format: "%.0f HZ", 20 * pow(50, $0)) })
                c.knob(LY_DELAY_HIGHCUT, accent: accent, diameter: 30, format: { String(format: "%.1fK", pow(20, $0)) })
                c.knob(LY_DELAY_MIX, LY_DST_DELAY_MIX, accent: accent, diameter: 38)
            case LY_FX_COMP:
                let multiband = c.isOn(LY_COMP_MODE)
                HStack(spacing: 3) {
                    LYSynthToggle(title: "SINGLE", isOn: !multiband, accent: accent) { c.set(LY_COMP_MODE, 0) }
                    LYSynthToggle(title: "MULTIBAND", isOn: multiband, accent: accent) { c.set(LY_COMP_MODE, 1) }
                }
                if multiband {
                    c.knob(LY_COMP_DEPTH, LY_DST_COMP_DEPTH, accent: accent, diameter: 40)
                    c.knob(LY_COMP_RELEASE, accent: accent, diameter: 34, label: "TIME")
                    c.knob(LY_COMP_THRESHOLD, accent: accent, diameter: 34, label: "UP / DOWN")
                } else {
                    c.knob(LY_COMP_THRESHOLD, accent: accent, diameter: 38, format: { String(format: "%.0f DB", -60 + $0 * 60) })
                    c.knob(LY_COMP_RATIO, accent: accent, diameter: 34, format: { String(format: "%.1f:1", 1 + $0 * $0 * 19) })
                    c.knob(LY_COMP_ATTACK, accent: accent, diameter: 30, format: { String(format: "%.1f MS", (0.0001 + $0 * $0 * 0.1) * 1000) })
                    c.knob(LY_COMP_RELEASE, accent: accent, diameter: 30, format: { String(format: "%.0f MS", (0.01 + $0 * $0) * 1000) })
                }
                c.knob(LY_COMP_GAIN, accent: accent, diameter: 30, format: { String(format: "+%.1f DB", $0 * 24) })
                c.knob(LY_COMP_MIX, LY_DST_COMP_MIX, accent: accent, diameter: 38)
            case LY_FX_EQ:
                let db = { (v: Float) in String(format: "%+.1f DB", v * 18) }
                c.knob(LY_EQ_LOW_FREQ, accent: accent, diameter: 30, label: "LOW", format: { String(format: "%.0f HZ", 20 * pow(50, $0)) })
                c.knob(LY_EQ_LOW_GAIN, LY_DST_EQ_LOW, accent: accent, diameter: 34, label: "LOW", format: db)
                divider
                c.knob(LY_EQ_MID_FREQ, accent: LYLLTHTheme.indigo, diameter: 30, label: "MID", format: { v in
                    let hz = 100 * pow(100, v); return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
                })
                c.knob(LY_EQ_MID_GAIN, LY_DST_EQ_MID, accent: LYLLTHTheme.indigo, diameter: 34, label: "MID", format: db)
                c.knob(LY_EQ_MID_Q, accent: LYLLTHTheme.indigo, diameter: 30, label: "Q", format: { String(format: "%.1f", 0.3 * pow(27, $0)) })
                divider
                c.knob(LY_EQ_HIGH_FREQ, accent: LYLLTHTheme.purple, diameter: 30, label: "HIGH", format: { String(format: "%.1fK", pow(20, $0)) })
                c.knob(LY_EQ_HIGH_GAIN, LY_DST_EQ_HIGH, accent: LYLLTHTheme.purple, diameter: 34, label: "HIGH", format: db)
            case LY_FX_FILTER:
                c.choice(LY_FXF_TYPE, label: "TYPE", names: LYSynthNames.fxFilters, accent: accent, columns: 2, width: 220, anchor: "fxfType")
                    .frame(width: 120)
                c.knob(LY_FXF_CUTOFF, LY_DST_FXF_CUTOFF, accent: accent, diameter: 40, format: LYSynthContext.hz)
                c.knob(LY_FXF_RES, LY_DST_FXF_RES, accent: accent, diameter: 34)
                c.knob(LY_FXF_DRIVE, accent: accent, diameter: 34)
                c.knob(LY_FXF_MIX, LY_DST_FXF_MIX, accent: accent, diameter: 38)
            default:
                let hall = c.isOn(LY_REVERB_MODE)
                HStack(spacing: 3) {
                    LYSynthToggle(title: "PLATE", isOn: !hall, accent: accent) { c.set(LY_REVERB_MODE, 0) }
                    LYSynthToggle(title: "HALL", isOn: hall, accent: accent) { c.set(LY_REVERB_MODE, 1) }
                }
                c.knob(LY_REVERB_SIZE, LY_DST_REVERB_SIZE, accent: accent, diameter: 36)
                c.knob(LY_REVERB_DECAY, LY_DST_REVERB_DECAY, accent: accent, diameter: 36, format: { v in
                    String(format: "%.1f S", (hall ? 0.6 : 0.3) + v * v * (hall ? 18 : 8))
                })
                c.knob(LY_REVERB_DAMP, accent: accent, diameter: 32)
                c.knob(LY_REVERB_PREDELAY, accent: accent, diameter: 32, format: { String(format: "%.0f MS", $0 * $0 * 250) })
                c.knob(LY_REVERB_WIDTH, accent: accent, diameter: 32)
                c.knob(LY_REVERB_MIX, LY_DST_REVERB_MIX, accent: accent, diameter: 38)
            }
            Spacer(minLength: 0)
        }
    }

    private var divider: some View {
        Rectangle().fill(LYLLTHTheme.line).frame(width: 1, height: 44)
    }
}

// MARK: - Pictures

/// What each effect is doing, drawn from the same numbers the core uses.
struct LYFXVisual: View {
    let fx: Int
    let patch: LYSynthPatch
    @ObservedObject var live: LYSynthLive
    let accent: Color
    let set: (Int, Float) -> Void

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            GeometryReader { geo in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.55)))
                        draw(&context, size: size, time: t)
                    }
                    if fx == LY_FX_EQ { eqHandles(size: geo.size) }
                }
            }
        }
        .opacity(patch.value(LYSynthFXPage.onIDs[fx]) > 0.5 ? 1 : 0.45)
    }

    private var animated: Bool {
        [LY_FX_HYPER, LY_FX_FLANGER, LY_FX_PHASER, LY_FX_CHORUS].contains(fx) || fx == LY_FX_COMP
    }

    private func p(_ id: Int) -> Double { Double(patch.value(id)) }

    private func grid(_ context: inout GraphicsContext, _ size: CGSize, logFrequency: Bool) {
        if logFrequency {
            for decade in [100.0, 1_000.0, 10_000.0] {
                let x = size.width * CGFloat(log10(decade / 20) / 3)
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.05)))
                context.draw(Text(decade >= 1000 ? "\(Int(decade / 1000))K" : "\(Int(decade))").font(LYLLTHTheme.value(7.5)).foregroundColor(LYLLTHTheme.dim),
                             at: CGPoint(x: x + 12, y: size.height - 10))
            }
        }
        context.fill(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)), with: .color(Color.white.opacity(0.05)))
    }

    private func stroke(_ context: inout GraphicsContext, _ path: Path, color: Color? = nil, width: CGFloat = 1.8) {
        var glow = context
        glow.addFilter(.shadow(color: (color ?? accent).opacity(0.7), radius: 4))
        glow.stroke(path, with: .color(color ?? accent), lineWidth: width)
    }

    /// A curve across the log frequency axis, dB centred at the middle.
    private func response(_ size: CGSize, range: Double = 24, _ magnitude: (Double) -> Double) -> Path {
        var path = Path()
        let steps = Int(size.width / 2)
        for i in 0...steps {
            let hz = 20 * pow(1000, Double(i) / Double(steps))
            let dB = 20 * log10(max(magnitude(hz), 1e-5))
            let y = size.height / 2 - CGFloat(dB / range) * size.height * 0.45
            let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(steps), y: min(max(y, 2), size.height - 2))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        switch fx {
        case LY_FX_HYPER:
            grid(&context, size, logFrequency: false)
            let count = 1 + Int((p(LY_HYPER_VOICES) * 6).rounded())
            let rate = 0.1 + p(LY_HYPER_RATE) * p(LY_HYPER_RATE) * 6
            let detune = p(LY_HYPER_DETUNE)
            let mix = p(LY_HYPER_MIX)
            for v in 0..<count {
                let pan = count == 1 ? 0 : -1 + 2 * Double(v) / Double(count - 1)
                let wobble = sin(time * rate * (1 + 0.173 * Double(v)) * 2 * .pi + Double(v))
                let x = size.width / 2 + CGFloat(pan) * size.width * 0.4
                let y = size.height / 2 + CGFloat(wobble * detune) * size.height * 0.3
                let r = 5 + CGFloat(mix) * 9
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(accent.opacity(0.25 + 0.5 * mix)))
                context.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(accent), lineWidth: 1)
            }
            let dim = p(LY_HYPER_DIM_MIX)
            if dim > 0.01 {
                let spread = size.width * CGFloat(0.2 + 0.25 * p(LY_HYPER_DIM_SIZE))
                for side in [-1.0, 1.0] {
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: size.width / 2, y: size.height * 0.9), radius: spread,
                               startAngle: .degrees(side < 0 ? 180 : 300), endAngle: .degrees(side < 0 ? 240 : 360), clockwise: false)
                    context.stroke(arc, with: .color(LYLLTHTheme.lavender.opacity(0.3 + 0.6 * dim)), lineWidth: 2)
                }
            }
            label(&context, size, "L", at: 12); label(&context, size, "R", at: size.width - 12)
        case LY_FX_DIST:
            grid(&context, size, logFrequency: false)
            context.fill(Path(CGRect(x: size.width / 2, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.05)))
            let mode = Int(patch.value(LY_DIST_MODE))
            let drive = min(max(p(LY_DIST_DRIVE) + Double(live.modulation(LY_DST_DIST_DRIVE)), 0), 1)
            let gain = pow(10, drive * 36 / 20)
            let mix = p(LY_DIST_MIX)
            var path = Path()
            let steps = Int(size.width)
            for i in 0...steps {
                let x = -1 + 2 * Double(i) / Double(steps)
                let y = x + (Self.shape(mode: mode, x: x, gain: gain, drive: drive) - x) * mix
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(steps), y: size.height / 2 - CGFloat(y) * size.height * 0.42)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: size.height * 0.92)); diagonal.addLine(to: CGPoint(x: size.width, y: size.height * 0.08))
            context.stroke(diagonal, with: .color(Color.white.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            stroke(&context, path)
            label(&context, size, "IN → OUT", at: size.width - 40, y: 14)
        case LY_FX_FLANGER:
            grid(&context, size, logFrequency: true)
            let hz = 0.02 + p(LY_FLANGER_RATE) * p(LY_FLANGER_RATE) * 5
            let lfo = 0.5 + 0.5 * sin(2 * .pi * hz * time)
            let delay = 0.0003 + p(LY_FLANGER_DEPTH) * 0.006 * lfo
            let fb = (p(LY_FLANGER_FEEDBACK) * 2 - 1) * 0.92
            let mix = p(LY_FLANGER_MIX)
            stroke(&context, response(size, range: 30) { f in
                // Dry plus the fed-back delayed copy: H = e^-jwd / (1 - fb·e^-jwd).
                let w = 2 * Double.pi * f * delay
                let dRe = 1 - fb * cos(w), dIm = fb * sin(w)
                let den = dRe * dRe + dIm * dIm
                let wetRe = (cos(w) * dRe - sin(w) * dIm) / den
                let wetIm = (-sin(w) * dRe - cos(w) * dIm) / den
                let re = (1 - mix) + 0.7 * mix * (1 + wetRe), im = 0.7 * mix * wetIm
                return (re * re + im * im).squareRoot()
            })
        case LY_FX_PHASER:
            grid(&context, size, logFrequency: true)
            let hz = 0.02 + p(LY_PHASER_RATE) * p(LY_PHASER_RATE) * 6
            let centre = 100 * pow(80, p(LY_PHASER_FREQ)) * pow(2, sin(2 * .pi * hz * time) * p(LY_PHASER_DEPTH) * 3)
            let mix = p(LY_PHASER_MIX)
            stroke(&context, response(size, range: 30) { f in
                let phase = 6 * 2 * atan(f / centre)
                let wet = abs(cos(phase / 2))
                return (1 - mix * 0.5) + (wet - 1) * mix * 0.5 + 0.0001
            })
        case LY_FX_CHORUS:
            grid(&context, size, logFrequency: false)
            let juno = Int(patch.value(LY_CHORUS_MODE)) != LY_CHORUS_CLASSIC
            let hz = juno ? 0.05 * pow(70, p(LY_CHORUS_RATE)) : 0.05 + p(LY_CHORUS_RATE) * p(LY_CHORUS_RATE) * 5
            let depth = p(LY_CHORUS_DEPTH)
            for voice in 0..<4 {
                var path = Path()
                for i in 0...Int(size.width / 3) {
                    let x = Double(i * 3) / Double(size.width)
                    let phase = time * hz + x * 2 + Double(voice) * 0.25 + (voice >= 2 ? 0.33 : 0)
                    let y = 0.5 + 0.35 * depth * sin(2 * .pi * phase) * (voice % 2 == 0 ? 1 : 0.8)
                    let point = CGPoint(x: CGFloat(x) * size.width, y: size.height * CGFloat(y))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                stroke(&context, path, color: (voice < 2 ? accent : LYLLTHTheme.indigo).opacity(0.85), width: 1.3)
            }
            label(&context, size, "L", at: 12); label(&context, size, "R", at: size.width - 12)
        case LY_FX_DELAY:
            grid(&context, size, logFrequency: false)
            let fb = min(max(p(LY_DELAY_FEEDBACK) + Double(live.modulation(LY_DST_DELAY_FEEDBACK)), 0), 1) * 0.98
            let ping = patch.value(LY_DELAY_PINGPONG) > 0.5
            let width = p(LY_DELAY_WIDTH)
            let taps = 12
            for n in 0..<taps {
                let level = pow(fb, Double(n))
                guard level > 0.01 else { break }
                for channel in 0..<2 {
                    if ping && (n + channel) % 2 == 1 { continue }
                    let spacing = size.width / CGFloat(taps + 1) * CGFloat(channel == 1 && !ping ? 1 + width * 0.5 : 1)
                    let x = spacing * CGFloat(n + 1)
                    let h = size.height * 0.4 * CGFloat(level)
                    let rect = channel == 0
                        ? CGRect(x: x - 3, y: size.height / 2 - h, width: 6, height: h)
                        : CGRect(x: x - 3, y: size.height / 2, width: 6, height: h)
                    context.fill(Path(rect), with: .color((channel == 0 ? accent : LYLLTHTheme.indigo).opacity(0.3 + 0.6 * level)))
                }
            }
            context.fill(Path(CGRect(x: 8, y: size.height / 2 - size.height * 0.4, width: 6, height: size.height * 0.4)), with: .color(LYLLTHTheme.text.opacity(0.8)))
            label(&context, size, "L", at: 18, y: 14); label(&context, size, "R", at: 18, y: size.height - 14)
        case LY_FX_COMP:
            if patch.value(LY_COMP_MODE) > 0.5 {
                let gains = live.compGain
                let names = ["LOW", "MID", "HIGH"]
                let colors = [LYLLTHTheme.teal, LYLLTHTheme.indigo, LYLLTHTheme.purple]
                let zero = size.height / 2
                context.fill(Path(CGRect(x: 0, y: zero, width: size.width, height: 1)), with: .color(Color.white.opacity(0.12)))
                for band in 0..<3 {
                    let x = size.width * (CGFloat(band) + 0.5) / 3
                    let g = CGFloat(max(-24, min(24, gains[band])))
                    let h = abs(g) / 24 * size.height * 0.42
                    let rect = g >= 0 ? CGRect(x: x - 22, y: zero - h, width: 44, height: h) : CGRect(x: x - 22, y: zero, width: 44, height: h)
                    context.fill(Path(rect), with: .color(colors[band].opacity(0.75)))
                    context.draw(Text(names[band]).font(LYLLTHTheme.label(8, weight: .bold)).foregroundColor(colors[band]), at: CGPoint(x: x, y: size.height - 12))
                    context.draw(Text(String(format: "%+.1f", gains[band])).font(LYLLTHTheme.value(8)).foregroundColor(LYLLTHTheme.text), at: CGPoint(x: x, y: 14))
                }
                label(&context, size, "UP", at: 22, y: zero - 12); label(&context, size, "DOWN", at: 26, y: zero + 12)
            } else {
                let th = -60 + p(LY_COMP_THRESHOLD) * 60
                let ratio = 1 + p(LY_COMP_RATIO) * p(LY_COMP_RATIO) * 19
                let makeup = p(LY_COMP_GAIN) * 24
                for i in 1..<6 {
                    let v = size.width * CGFloat(i) / 6
                    context.fill(Path(CGRect(x: v, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.04)))
                    context.fill(Path(CGRect(x: 0, y: size.height * CGFloat(i) / 6, width: size.width, height: 1)), with: .color(Color.white.opacity(0.04)))
                }
                var path = Path()
                for i in 0...60 {
                    let input = -60 + Double(i)
                    var out = input > th ? th + (input - th) / ratio : input
                    out += makeup
                    let point = CGPoint(x: size.width * CGFloat(i) / 60, y: size.height * CGFloat(-min(out, 0) / 60))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                stroke(&context, path)
                let tx = size.width * CGFloat((th + 60) / 60)
                context.fill(Path(CGRect(x: tx, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.3)))
                let gr = CGFloat(min(max(-live.compGain[1], 0), 24)) / 24
                context.fill(Path(CGRect(x: size.width - 14, y: 0, width: 8, height: size.height * gr)), with: .color(LYLLTHTheme.record.opacity(0.8)))
                label(&context, size, "GR", at: size.width - 10, y: size.height - 10)
            }
        case LY_FX_EQ:
            grid(&context, size, logFrequency: true)
            let sampleRate = 44_100.0
            let bands = Self.eqBands(patch: patch, live: live)
            let curve = response(size, range: 24) { f in
                bands.reduce(1) { $0 * Self.biquadMagnitude($1, hz: f, sampleRate: sampleRate) }
            }
            var fill = curve
            fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
            fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.12)))
            stroke(&context, curve)
        case LY_FX_FILTER:
            grid(&context, size, logFrequency: true)
            let type = Int(patch.value(LY_FXF_TYPE))
            let cutoff = 20 * pow(1000, min(max(p(LY_FXF_CUTOFF) + Double(live.modulation(LY_DST_FXF_CUTOFF)), 0), 1))
            let res = p(LY_FXF_RES)
            let mix = p(LY_FXF_MIX)
            let voiceType: Int = [LY_FILTER_LP12, LY_FILTER_HP12, LY_FILTER_BP, LY_FILTER_NOTCH, LY_FILTER_LADDER, LY_FILTER_COMB_POS].map { Int($0) }[min(max(type, 0), 5)]
            let curve = response(size, range: 30) { f in 1 + (LYFilterCurve.magnitude(type: voiceType, hz: f, cutoff: cutoff, res: res) - 1) * mix }
            var fill = curve
            fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .color(accent.opacity(0.1)))
            stroke(&context, curve)
        default:
            let hall = patch.value(LY_REVERB_MODE) > 0.5
            let decay = (hall ? 0.6 : 0.3) + p(LY_REVERB_DECAY) * p(LY_REVERB_DECAY) * (hall ? 18 : 8)
            let pre = p(LY_REVERB_PREDELAY) * p(LY_REVERB_PREDELAY) * 0.25
            let span = max(decay * 1.1 + pre, 0.5)
            let damp = p(LY_REVERB_DAMP)
            let mix = p(LY_REVERB_MIX)
            for i in 1..<8 { context.fill(Path(CGRect(x: size.width * CGFloat(i) / 8, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.04))) }
            // Early reflections, then the tail: level falls 60 dB over the decay.
            var tail = Path()
            tail.move(to: CGPoint(x: size.width * CGFloat(pre / span), y: size.height))
            for i in 0...120 {
                let t = pre + Double(i) / 120 * (span - pre)
                let level = pow(10, -3 * (t - pre) / decay)
                tail.addLine(to: CGPoint(x: size.width * CGFloat(t / span), y: size.height - size.height * 0.85 * CGFloat(level) * CGFloat(0.4 + 0.6 * mix)))
            }
            tail.addLine(to: CGPoint(x: size.width, y: size.height))
            tail.closeSubpath()
            context.fill(tail, with: .color(accent.opacity(0.12 + 0.1 * (1 - damp))))
            for k in 0..<18 {
                let t = pre + 0.004 + Double(k) * 0.011 * (0.5 + p(LY_REVERB_SIZE))
                guard t < span else { break }
                let level = pow(10, -3 * (t - pre) / decay)
                let x = size.width * CGFloat(t / span)
                context.fill(Path(CGRect(x: x, y: size.height - size.height * 0.85 * CGFloat(level), width: 1.5, height: size.height * 0.85 * CGFloat(level))),
                             with: .color(accent.opacity(0.6)))
            }
            label(&context, size, String(format: "%.1f S", decay), at: size.width - 30, y: 14)
            label(&context, size, "PRE-DELAY", at: 36, y: size.height - 10)
        }
    }

    private func label(_ context: inout GraphicsContext, _ size: CGSize, _ text: String, at x: CGFloat, y: CGFloat? = nil) {
        context.draw(Text(text).font(LYLLTHTheme.label(8, weight: .bold)).foregroundColor(LYLLTHTheme.dim), at: CGPoint(x: x, y: y ?? size.height / 2))
    }

    // MARK: EQ

    /// Low shelf, peak and high shelf: frequency, gain in dB, and Q.
    static func eqBands(patch: LYSynthPatch, live: LYSynthLive) -> [(type: Int, hz: Double, dB: Double, q: Double)] {
        func g(_ id: Int, _ dst: Int) -> Double { Double(min(max(patch.value(id) + live.modulation(dst), -1), 1)) * 18 }
        return [
            (0, 20 * pow(50, Double(patch.value(LY_EQ_LOW_FREQ))), g(LY_EQ_LOW_GAIN, LY_DST_EQ_LOW), 0.7071),
            (1, 100 * pow(100, Double(patch.value(LY_EQ_MID_FREQ))), g(LY_EQ_MID_GAIN, LY_DST_EQ_MID), 0.3 * pow(27, Double(patch.value(LY_EQ_MID_Q)))),
            (2, 1000 * pow(20, Double(patch.value(LY_EQ_HIGH_FREQ))), g(LY_EQ_HIGH_GAIN, LY_DST_EQ_HIGH), 0.7071),
        ]
    }

    /// The same RBJ biquads the core uses, evaluated on the unit circle.
    static func biquadMagnitude(_ band: (type: Int, hz: Double, dB: Double, q: Double), hz: Double, sampleRate: Double) -> Double {
        let A = pow(10, band.dB / 40)
        let w0 = 2 * Double.pi * min(band.hz, sampleRate * 0.45) / sampleRate
        let cw = cos(w0), sw = sin(w0)
        var b0, b1, b2, a0, a1, a2: Double
        if band.type == 1 {
            let alpha = sw / (2 * band.q)
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        } else {
            let s = 2 * sqrt(A) * sw / 2 * sqrt(2)
            if band.type == 0 {
                b0 = A * ((A + 1) - (A - 1) * cw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - s)
                a0 = (A + 1) + (A - 1) * cw + s; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - s
            } else {
                b0 = A * ((A + 1) + (A - 1) * cw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - s)
                a0 = (A + 1) - (A - 1) * cw + s; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - s
            }
        }
        let w = 2 * Double.pi * hz / sampleRate
        func mag(_ c0: Double, _ c1: Double, _ c2: Double) -> Double {
            let re = c0 + c1 * cos(w) + c2 * cos(2 * w)
            let im = -(c1 * sin(w) + c2 * sin(2 * w))
            return (re * re + im * im).squareRoot()
        }
        return mag(b0, b1, b2) / max(mag(a0, a1, a2), 1e-9)
    }

    /// Drag a band's dot: sideways for frequency, up and down for gain.
    private func eqHandles(size: CGSize) -> some View {
        let bands = Self.eqBands(patch: patch, live: live)
        let ids: [(freq: Int, gain: Int, range: (Double, Double))] = [
            (LY_EQ_LOW_FREQ, LY_EQ_LOW_GAIN, (20, 1000)), (LY_EQ_MID_FREQ, LY_EQ_MID_GAIN, (100, 10000)), (LY_EQ_HIGH_FREQ, LY_EQ_HIGH_GAIN, (1000, 20000))
        ]
        let colors = [LYLLTHTheme.teal, LYLLTHTheme.indigo, LYLLTHTheme.purple]
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let band = bands[index]
                let x = size.width * CGFloat(log10(band.hz / 20) / 3)
                let y = size.height / 2 - CGFloat(band.dB / 24) * size.height * 0.45
                Circle()
                    .fill(Color.black)
                    .overlay(Circle().stroke(colors[index], lineWidth: 2))
                    .frame(width: 13, height: 13)
                    .position(x: x, y: y)
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { drag in
                            let hz = 20 * pow(1000, Double(drag.location.x / size.width))
                            let range = ids[index].range
                            let normalized = log(min(max(hz, range.0), range.1) / range.0) / log(range.1 / range.0)
                            set(ids[index].freq, Float(normalized))
                            let dB = Double((size.height / 2 - drag.location.y) / (size.height * 0.45)) * 24
                            set(ids[index].gain, Float(min(max(dB / 18, -1), 1)))
                        }
                    )
                    .help(["Low shelf", "Peak", "High shelf"][index] + ": drag sideways for frequency, up and down for gain")
            }
        }
    }

    // MARK: Distortion

    static func shape(mode: Int, x: Double, gain: Double, drive: Double) -> Double {
        func soft(_ v: Double) -> Double { let c = min(max(v, -3), 3); return c * (27 + c * c) / (27 + 9 * c * c) }
        let v = x * gain
        switch mode {
        case LY_DIST_TUBE: return soft(v + 0.15 * v * v)
        case LY_DIST_SOFT: return soft(v)
        case LY_DIST_HARD: return min(max(v, -1), 1)
        case LY_DIST_DIODE: return v > 0 ? soft(v) : soft(v * 0.25) * 0.4
        case LY_DIST_LINFOLD:
            var y = v
            for _ in 0..<8 where abs(y) > 1 { y = y > 1 ? 2 - y : -2 - y }
            return y
        case LY_DIST_SINFOLD: return sin(v * 0.5 * .pi)
        case LY_DIST_ZEROSQUARE: return min(max(v * abs(v), -1), 1)
        case LY_DIST_DOWNSAMPLE: return x
        case LY_DIST_BITCRUSH:
            let steps = pow(2, 12 - drive * 10)
            return (x * steps).rounded() / steps
        case LY_DIST_RECTIFY: return soft(abs(v) * 1.2)
        default: return x
        }
    }
}


/// The vocoder: the synth is the carrier, the host's sidechain input the
/// voice. With no input arriving it stands aside and the synth plays as is.
struct LYVocoderPanel: View {
    let context: LYSynthContext
    @ObservedObject private var live: LYSynthLive

    init(context: LYSynthContext) {
        self.context = context
        _live = ObservedObject(wrappedValue: context.live)
    }

    var body: some View {
        let c = context
        let accent = LYLLTHTheme.lavender
        let on = c.isOn(LY_VOC_ON)
        let receiving = live.display.vocoderInput == 1
        let bands = Int(c.value(LY_VOC_BANDS))
        let levels = withUnsafeBytes(of: live.display.vocoderBands) { Array($0.bindMemory(to: Float.self)) }
        return LYSynthPanel(title: "VOCODER", accent: accent, isOn: on, toggle: { c.toggle(LY_VOC_ON) }) {
            Text(!on ? "OFF" : receiving ? "INPUT" : "NO INPUT")
                .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2)
                .foregroundStyle(receiving ? accent : LYLLTHTheme.dim)
        } content: {
            VStack(spacing: 8) {
                Canvas { g, size in
                    g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
                    let n = max(bands, 1)
                    let w = size.width / CGFloat(n)
                    for b in 0..<n {
                        let h = CGFloat(b < levels.count ? levels[b] : 0) * (size.height - 4)
                        g.fill(Path(CGRect(x: CGFloat(b) * w + 1, y: size.height - 2 - h, width: w - 2, height: max(h, 1))),
                               with: .color(accent.opacity(receiving ? 0.9 : 0.25)))
                    }
                }
                .frame(height: 34)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                .overlay {
                    if on && !receiving {
                        Text("ROUTE A SIDECHAIN INTO LUNATK")
                            .font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                    }
                }
                HStack(spacing: 0) {
                    LYSynthStepper(label: "BANDS", text: "\(bands)", accent: accent) { step in
                        c.set(LY_VOC_BANDS, Float(min(max(bands + step * 4, 8), Int(LY_VOC_MAX_BANDS))))
                    }
                    Spacer(minLength: 0)
                    c.knob(LY_VOC_GAIN, accent: accent, diameter: 22, label: "INPUT", format: { String(format: "%+.0f DB", -12 + $0 * 36) })
                    c.knob(LY_VOC_MIX, LY_DST_VOC_MIX, accent: accent, diameter: 22, format: { String(format: "%.0f%%", $0 * 100) })
                }
                HStack(spacing: 0) {
                    c.knob(LY_VOC_ATTACK, accent: accent, diameter: 20, format: { String(format: "%.0f MS", pow(50, $0)) })
                    c.knob(LY_VOC_RELEASE, accent: accent, diameter: 20, format: { String(format: "%.0f MS", 10 * pow(50, $0)) })
                    c.knob(LY_VOC_SHIFT, LY_DST_VOC_SHIFT, accent: accent, diameter: 20, format: { String(format: "%+.0f ST", $0 * 12) })
                    c.knob(LY_VOC_Q, accent: accent, diameter: 20, format: { String(format: "%.0f%%", $0 * 100) })
                    c.knob(LY_VOC_HIGHS, accent: accent, diameter: 20, format: { String(format: "%.0f%%", $0 * 100) })
                }
            }
        }
    }
}
