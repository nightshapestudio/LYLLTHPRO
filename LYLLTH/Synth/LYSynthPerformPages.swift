import SwiftUI

/// A modulation source to drag onto any knob.
struct LYSourceDragHandle: View {
    let source: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 7, weight: .bold))
            Text("DRAG").font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1.2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .overlay(Rectangle().stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .contentShape(Rectangle())
        .draggable("\(LYSynthSourceColor.dragPrefix)\(source)")
        .help("Drag onto any knob to modulate it with \(LYSynthNames.sources[min(source, LYSynthNames.sources.count - 1)])")
    }
}

enum LYNoteName {
    static func name(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[((note % 12) + 12) % 12] + "\(note / 12 - 1)"
    }
}

// MARK: - VOICE FX

/// Per-voice damage: two insert slots, before or after the filters, and a
/// feedback loop around the filters. Each note gets its own, so chords stay
/// clear however hard they are pushed.
struct LYSynthVoiceFXPage: View {
    let context: LYSynthContext

    var body: some View {
        let c = context
        return VStack(spacing: 8) {
            AnyView(LYVoiceFlow(patch: c.patch)).frame(height: 64)
            HStack(alignment: .top, spacing: 8) {
                AnyView(insertPanel(0)).frame(maxWidth: .infinity)
                AnyView(insertPanel(1)).frame(maxWidth: .infinity)
                AnyView(feedbackPanel).frame(width: 330)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func insertPanel(_ k: Int) -> some View {
        let c = context
        let accent = k == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo
        let f = { (field: Int) in LYSynthParameters.insert(k, field) }
        let type = Int(c.value(f(LY_INS1_TYPE)))
        let on = type != LY_INS_OFF
        let after = c.isOn(f(LY_INS1_POSITION))
        let amountDst = k == 0 ? LY_DST_INS1_AMOUNT : LY_DST_INS2_AMOUNT
        let freqDst = k == 0 ? LY_DST_INS1_FREQ : LY_DST_INS2_FREQ
        let usesFreq = [LY_INS_RING, LY_INS_SHIFT, LY_INS_COMB].contains(type)
        return LYSynthPanel(title: "INSERT \(k + 1)", accent: accent) {
            HStack(spacing: 4) {
                LYSynthToggle(title: "BEFORE", isOn: !after, accent: accent) { c.set(f(LY_INS1_POSITION), 0) }
                LYSynthToggle(title: "AFTER", isOn: after, accent: accent) { c.set(f(LY_INS1_POSITION), 1) }
            }
            .help("Before the filters it shapes what they hear; after them it works on the whole voice")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                c.choice(f(LY_INS1_TYPE), label: "TYPE", names: LYSynthNames.inserts, accent: accent, columns: 3, width: 330, anchor: "ins\(k)")
                    .frame(width: 180)
                Text(Self.describe(type))
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 34, alignment: .topLeading)
                HStack(spacing: 18) {
                    c.knob(f(LY_INS1_AMOUNT), amountDst, accent: accent, diameter: 44, label: Self.amountLabel(type),
                           format: { String(format: "%.0f%%", $0 * 100) })
                    c.knob(f(LY_INS1_FREQ), freqDst, accent: accent, diameter: 44, label: type == LY_INS_SHIFT ? "SHIFT" : "PITCH",
                           format: { Self.freqText(type, $0) })
                        .opacity(usesFreq ? 1 : 0.3)
                        .allowsHitTesting(usesFreq)
                    c.knob(f(LY_INS1_MIX), accent: accent, diameter: 36, label: "MIX", format: { String(format: "%.0f%%", $0 * 100) })
                    Spacer(minLength: 0)
                }
            }
            .opacity(on ? 1 : 0.55)
        }
    }

    private var feedbackPanel: some View {
        let c = context
        let accent = LYLLTHTheme.purple
        let filtersOn = c.isOn(LY_FILTER_ON) || c.isOn(LY_F2_ON)
        return LYSynthPanel(title: "FEEDBACK", accent: accent) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(filtersOn ? "THE FILTERS' OUTPUT BACK INTO THEIR INPUT. LOW AMOUNTS THICKEN; HIGH AMOUNTS GROWL AND SCREAM."
                               : "TURN A FILTER ON: THE LOOP RUNS THROUGH THE FILTERS.")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(filtersOn ? LYLLTHTheme.dim : LYLLTHTheme.purple)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 34, alignment: .topLeading)
                HStack(spacing: 18) {
                    c.knob(LY_FB_AMOUNT, LY_DST_FEEDBACK, accent: accent, diameter: 44, label: "AMOUNT", format: { String(format: "%.0f%%", $0 * 100) })
                    c.knob(LY_FB_DRIVE, accent: accent, diameter: 36, label: "DRIVE", format: { String(format: "%.0f%%", $0 * 100) })
                    c.knob(LY_FB_TONE, LY_DST_FB_TONE, accent: accent, diameter: 36, label: "TONE", format: { v in
                        let hz = 150 * pow(100, v)
                        return hz >= 1000 ? String(format: "%.1fK", hz / 1000) : String(format: "%.0f", hz)
                    })
                    Spacer(minLength: 0)
                }
            }
            .opacity(filtersOn ? 1 : 0.55)
        }
    }

    static func describe(_ type: Int) -> String {
        switch type {
        case LY_INS_BITCRUSH: return "FEWER BITS PER SAMPLE: GRAIN, THEN GRIT, THEN STAIRS."
        case LY_INS_DECIMATE: return "HOLDS SAMPLES FOR LONGER: ALIASED, METALLIC, BROKEN DIGITAL."
        case LY_INS_SINE: return "RUNS THE WAVE THROUGH A SINE: SMOOTH HARMONICS THAT FOLD INTO BELLS."
        case LY_INS_FOLD: return "FOLDS THE PEAKS BACK: HOLLOW, BUZZING, VOCAL AT HIGH AMOUNTS."
        case LY_INS_RECTIFY: return "FLIPS THE NEGATIVE HALF UP: AN OCTAVE-UP EDGE, DC REMOVED."
        case LY_INS_RING: return "MULTIPLIES BY A SINE TUNED TO THE NOTE: BELLS, CLANG, METAL."
        case LY_INS_SHIFT: return "MOVES EVERY PARTIAL BY THE SAME HZ: INHARMONIC, SLIDING, UNSTABLE."
        case LY_INS_COMB: return "A SHORT TUNED ECHO: STRINGS, TUBES, METALLIC RESONANCE."
        default: return "CHOOSE A TYPE. EACH NOTE GETS ITS OWN, SO CHORDS STAY CLEAR."
        }
    }

    static func amountLabel(_ type: Int) -> String {
        switch type {
        case LY_INS_BITCRUSH: return "CRUSH"
        case LY_INS_DECIMATE: return "RATE"
        case LY_INS_SINE, LY_INS_FOLD: return "DRIVE"
        case LY_INS_COMB: return "FEEDBACK"
        default: return "AMOUNT"
        }
    }

    static func freqText(_ type: Int, _ value: Float) -> String {
        if type == LY_INS_SHIFT {
            let f = (value - 0.5) * 2
            let hz = (f < 0 ? -1 : 1) * f * f * 2000
            return String(format: "%+.0f HZ", hz)
        }
        let octaves = type == LY_INS_COMB ? (value - 0.5) * 4 : (value - 0.5) * 8
        let semis = octaves * 12
        return abs(semis) < 0.05 ? "NOTE" : String(format: "%+.1f ST", semis)
    }
}

/// The voice's path, with what is in it lit.
struct LYVoiceFlow: View {
    let patch: LYSynthPatch

    var body: some View {
        let before = slots(after: false), after = slots(after: true)
        let filters = patch.value(LY_FILTER_ON) > 0.5 || patch.value(LY_F2_ON) > 0.5
        let feedback = patch.value(LY_FB_AMOUNT) > 0.0005 && filters
        return HStack(spacing: 6) {
            block("OSCILLATORS", on: true, color: LYLLTHTheme.chromeText)
            arrow
            block(before.isEmpty ? "INSERT" : before.joined(separator: " + "), on: !before.isEmpty, color: LYLLTHTheme.teal)
            arrow
            block(feedback ? "FILTERS + FEEDBACK" : "FILTERS", on: filters, color: feedback ? LYLLTHTheme.purple : LYLLTHTheme.chromeText)
            arrow
            block(after.isEmpty ? "INSERT" : after.joined(separator: " + "), on: !after.isEmpty, color: LYLLTHTheme.indigo)
            arrow
            block("AMP", on: true, color: LYLLTHTheme.chromeText)
            arrow
            block("FX RACK", on: true, color: LYLLTHTheme.chromeText)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func slots(after: Bool) -> [String] {
        (0..<2).compactMap { k in
            let type = Int(patch.value(LYSynthParameters.insert(k, LY_INS1_TYPE)))
            guard type != LY_INS_OFF, type < LYSynthNames.inserts.count else { return nil }
            guard (patch.value(LYSynthParameters.insert(k, LY_INS1_POSITION)) > 0.5) == after else { return nil }
            return LYSynthNames.inserts[type]
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
    }

    private func block(_ title: String, on: Bool, color: Color) -> some View {
        Text(title)
            .font(LYLLTHTheme.label(7.5, weight: .bold))
            .tracking(1.1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(on ? color : LYLLTHTheme.dim)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30)
            .overlay(Rectangle().stroke(on ? color.opacity(0.8) : LYLLTHTheme.lineStrong,
                                        style: StrokeStyle(lineWidth: 1, dash: on ? [] : [3, 2])))
    }
}

// MARK: - PERFORM

/// Performers: tempo step sequencers for modulation, four patterns each,
/// locked to the bar while the song plays; switch keys change the pattern
/// from the keyboard. Trackers: any source read through a drawn curve.
struct LYSynthPerformPage: View {
    let context: LYSynthContext

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                AnyView(performerPanel(0))
                AnyView(performerPanel(1))
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                AnyView(switchPanel).frame(height: 104)
                AnyView(trackerPanel(0))
                AnyView(trackerPanel(1))
            }
            .frame(width: 330)
        }
    }

    private func performerPanel(_ k: Int) -> some View {
        let c = context
        let accent = k == 0 ? LYLLTHTheme.teal : LYLLTHTheme.indigo
        let f = { (field: Int) in LYSynthParameters.performer(k, field) }
        let steps = max(1, min(16, Int(c.value(f(LY_PERF1_STEPS)))))
        let pattern = Int(c.value(f(LY_PERF1_PATTERN)))
        return LYSynthPanel(title: "PERFORMER \(k + 1)", accent: accent) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { p in
                    LYSynthToggle(title: ["A", "B", "C", "D"][p], isOn: pattern == p, accent: accent) { c.set(f(LY_PERF1_PATTERN), Float(p)) }
                }
                LYSourceDragHandle(source: k == 0 ? LY_SRC_PERF1 : LY_SRC_PERF2, color: accent)
            }
        } content: {
            VStack(spacing: 8) {
                LYPerformerLane(context: c, index: k, pattern: pattern, steps: steps, accent: accent)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 12) {
                    LYSynthToggle(title: "SONG", isOn: Int(c.value(f(LY_PERF1_MODE))) == LY_PERFMODE_SONG, accent: accent) {
                        c.set(f(LY_PERF1_MODE), Float(LY_PERFMODE_SONG))
                    }
                    .help("Follows the song's bar: every note lands on the same part of the pattern")
                    LYSynthToggle(title: "NOTE", isOn: Int(c.value(f(LY_PERF1_MODE))) == LY_PERFMODE_TRIG, accent: accent) {
                        c.set(f(LY_PERF1_MODE), Float(LY_PERFMODE_TRIG))
                    }
                    .help("Starts from step 1 on every note")
                    c.knob(f(LY_PERF1_RATE), accent: accent, diameter: 30, label: "STEP", format: { v in
                        let i = Int((v * Float(LYSynthNames.syncDivisions.count - 1)).rounded())
                        return LYSynthNames.syncDivisions[min(max(i, 0), LYSynthNames.syncDivisions.count - 1)]
                    })
                    LYSynthStepper(label: "STEPS", text: "\(steps)", accent: accent) { step in
                        c.set(f(LY_PERF1_STEPS), Float(min(max(steps + step, 1), 16)))
                    }
                    Text("DRAG A STEP UP OR DOWN · CLICK ITS SHAPE TO CHANGE IT")
                        .font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1.1).foregroundStyle(LYLLTHTheme.dim)
                    Spacer(minLength: 0)
                }
                .frame(height: 42)
            }
        }
    }

    private var switchPanel: some View {
        let c = context
        let accent = LYLLTHTheme.lavender
        let root = Int(c.value(LY_PERF_KEYROOT))
        let on = c.isOn(LY_PERF_KEYSWITCH)
        return LYSynthPanel(title: "SWITCH KEYS", accent: accent, isOn: on, toggle: { c.toggle(LY_PERF_KEYSWITCH) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LYSynthStepper(label: "FIRST KEY", text: LYNoteName.name(root), accent: accent) { step in
                        c.set(LY_PERF_KEYROOT, Float(min(max(root + step, 0), 124)))
                    }
                    Text("\(LYNoteName.name(root))–\(LYNoteName.name(root + 3)) PICK PATTERN A–D. THEY MAKE NO SOUND.")
                        .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func trackerPanel(_ t: Int) -> some View {
        let c = context
        let accent = t == 0 ? LYLLTHTheme.purple : LYLLTHTheme.lavender
        let id = t == 0 ? LY_TRACK1_SOURCE : LY_TRACK2_SOURCE
        let source = Int(c.value(id))
        // A tracker can read any source but a tracker.
        let order = LYSynthNames.sourceOrder.filter { $0 != LY_SRC_TRACK1 && $0 != LY_SRC_TRACK2 }
        return LYSynthPanel(title: "TRACKER \(t + 1)", accent: accent) {
            LYSourceDragHandle(source: t == 0 ? LY_SRC_TRACK1 : LY_SRC_TRACK2, color: accent)
        } content: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    LYSynthChoiceButton(label: "READS", value: LYSynthNames.sources[min(max(source, 0), LYSynthNames.sources.count - 1)], accent: accent) {
                        c.openMenu(LYSynthMenuRequest(anchor: "track\(t)", title: "TRACKER READS", names: LYSynthNames.sources, order: order,
                                                      selected: source, accent: accent, columns: 3, width: 330) { c.set(id, Float($0)) })
                    }
                    .lyMenuAnchor("track\(t)", in: LYSynthContext.space)
                    .frame(width: 140)
                    Button {
                        var next = c.patch
                        for i in 0..<Int(LY_TRACK_POINTS) { next.set(LYSynthParameters.trackerPoint(t, i), -1 + 2 * Float(i) / Float(LY_TRACK_POINTS - 1)) }
                        c.replace(next)
                    } label: {
                        Text("RESET").font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.chromeText)
                            .padding(.horizontal, 8).frame(height: 22)
                            .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Back to a straight line")
                    Spacer(minLength: 0)
                }
                LYTrackerCurve(context: c, index: t, accent: accent)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// One performer pattern: a bar of steps. Drag a step up or down for its
/// level; the strip under it picks the shape it plays across the step.
struct LYPerformerLane: View {
    let context: LYSynthContext
    let index: Int
    let pattern: Int
    let steps: Int
    let accent: Color
    @ObservedObject private var live: LYSynthLive

    init(context: LYSynthContext, index: Int, pattern: Int, steps: Int, accent: Color) {
        self.context = context
        self.index = index
        self.pattern = pattern
        self.steps = steps
        self.accent = accent
        _live = ObservedObject(wrappedValue: context.live)
    }

    private func value(_ step: Int) -> Float { context.value(LYSynthParameters.performerStep(index, pattern, step)) }
    private func shape(_ step: Int) -> Int { Int(context.value(LYSynthParameters.performerShape(index, pattern, step))) }

    /// The step's shape across its width, 0…1 → -1…1.
    private func shaped(_ step: Int, _ t: Double) -> Double {
        let v = Double(value(step))
        switch shape(step) {
        case LY_PSTEP_RAMP_UP: return v * t
        case LY_PSTEP_RAMP_DOWN: return v * (1 - t)
        case LY_PSTEP_TRIANGLE: return v * (1 - abs(2 * t - 1))
        case LY_PSTEP_DECAY: return v * exp(-5 * t)
        case LY_PSTEP_RISE: return v * (exp(3 * t) - 1) / (exp(3) - 1)
        case LY_PSTEP_PULSE: return t < 0.5 ? v : 0
        case LY_PSTEP_GLIDE:
            let previous = Double(value((step + steps - 1) % steps))
            return previous + (v - previous) * (0.5 - 0.5 * cos(.pi * t))
        default: return v
        }
    }

    var body: some View {
        let shapeRow: CGFloat = 18
        let playing = withUnsafeBytes(of: live.display.perfPattern) { $0.bindMemory(to: Int32.self)[index] } == Int32(pattern)
        let current = playing ? Int(withUnsafeBytes(of: live.display.perfStep) { $0.bindMemory(to: Int32.self)[index] }) : -1
        return GeometryReader { geo in
            let lane = CGSize(width: geo.size.width, height: max(10, geo.size.height - shapeRow - 4))
            let column = lane.width / 16
            ZStack(alignment: .topLeading) {
                Canvas { g, size in
                    g.fill(Path(CGRect(origin: .zero, size: lane)), with: .color(Color.black.opacity(0.5)))
                    let mid = lane.height / 2
                    for i in 0...16 {
                        g.fill(Path(CGRect(x: CGFloat(i) * column, y: 0, width: 1, height: lane.height)),
                               with: .color(Color.white.opacity(i % 4 == 0 ? 0.08 : 0.03)))
                    }
                    g.fill(Path(CGRect(x: 0, y: mid, width: lane.width, height: 1)), with: .color(Color.white.opacity(0.07)))
                    // Steps past the pattern's length are dimmed.
                    if steps < 16 {
                        g.fill(Path(CGRect(x: CGFloat(steps) * column, y: 0, width: lane.width - CGFloat(steps) * column, height: lane.height)),
                               with: .color(Color.black.opacity(0.55)))
                    }
                    var path = Path(), fill = Path()
                    fill.move(to: CGPoint(x: 0, y: mid))
                    for step in 0..<steps {
                        for k in 0...12 {
                            let t = Double(k) / 12
                            let x = (CGFloat(step) + CGFloat(t)) * column
                            let y = mid - CGFloat(shaped(step, min(t, 0.999))) * (mid - 6)
                            let point = CGPoint(x: x, y: y)
                            if step == 0 && k == 0 { path.move(to: point) } else { path.addLine(to: point) }
                            fill.addLine(to: point)
                        }
                    }
                    fill.addLine(to: CGPoint(x: CGFloat(steps) * column, y: mid))
                    fill.closeSubpath()
                    g.fill(fill, with: .color(accent.opacity(0.14)))
                    var glow = g
                    glow.addFilter(.shadow(color: accent.opacity(0.6), radius: 3))
                    glow.stroke(path, with: .color(accent), lineWidth: 1.5)
                    for step in 0..<steps {
                        let y = mid - CGFloat(value(step)) * (mid - 6)
                        let rect = CGRect(x: CGFloat(step) * column + 3, y: y - 1.5, width: column - 6, height: 3)
                        g.fill(Path(rect), with: .color(step == current ? LYLLTHTheme.text : accent.opacity(0.9)))
                    }
                    if current >= 0 {
                        g.fill(Path(CGRect(x: CGFloat(current) * column, y: 0, width: column, height: lane.height)),
                               with: .color(accent.opacity(0.12)))
                    }
                    _ = size
                }
                .frame(width: lane.width, height: lane.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let step = min(max(Int(drag.location.x / column), 0), steps - 1)
                    let mid = lane.height / 2
                    let v = Float(min(max((mid - drag.location.y) / (mid - 6), -1), 1))
                    context.set(LYSynthParameters.performerStep(index, pattern, step), (v * 20).rounded() / 20)
                })
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))

                HStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { step in
                        let s = shape(step)
                        Button {
                            context.set(LYSynthParameters.performerShape(index, pattern, step), Float((s + 1) % Int(LY_PSTEP_COUNT)))
                        } label: {
                            LYStepShapeIcon(shape: s, color: step < steps ? (step == current ? LYLLTHTheme.text : accent) : LYLLTHTheme.dim)
                                .frame(width: column, height: shapeRow)
                                .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(step >= steps)
                        .help(LYSynthNames.stepShapes[min(max(s, 0), LYSynthNames.stepShapes.count - 1)] + " · CLICK FOR THE NEXT SHAPE")
                    }
                }
                .offset(y: lane.height + 4)
            }
        }
    }
}

/// A tracker's curve: input across, output up. Drag to draw; the dot is
/// where the newest note is reading it.
struct LYTrackerCurve: View {
    let context: LYSynthContext
    let index: Int
    let accent: Color
    @ObservedObject private var live: LYSynthLive

    init(context: LYSynthContext, index: Int, accent: Color) {
        self.context = context
        self.index = index
        self.accent = accent
        _live = ObservedObject(wrappedValue: context.live)
    }

    private var points: [Float] {
        (0..<Int(LY_TRACK_POINTS)).map { context.value(LYSynthParameters.trackerPoint(index, $0)) }
    }

    var body: some View {
        let points = self.points
        let input = CGFloat(withUnsafeBytes(of: live.display.trackInput) { $0.bindMemory(to: Float.self)[index] })
        return GeometryReader { geo in
            Canvas { g, size in
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
                let mid = size.height / 2
                let n = points.count
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    g.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.03)))
                }
                g.fill(Path(CGRect(x: 0, y: mid, width: size.width, height: 1)), with: .color(Color.white.opacity(0.07)))
                var path = Path()
                for i in 0..<n {
                    let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1), y: mid - CGFloat(points[i]) * (mid - 6))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                var glow = g
                glow.addFilter(.shadow(color: accent.opacity(0.6), radius: 3))
                glow.stroke(path, with: .color(accent), lineWidth: 1.6)
                for i in 0..<n {
                    let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1), y: mid - CGFloat(points[i]) * (mid - 6))
                    g.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(accent))
                }
                let position = input * CGFloat(n - 1)
                let i = min(Int(position), n - 2)
                let y = CGFloat(points[i]) + (CGFloat(points[i + 1]) - CGFloat(points[i])) * (position - CGFloat(i))
                let x = input * size.width
                g.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(accent.opacity(0.3)))
                g.fill(Path(ellipseIn: CGRect(x: x - 4, y: mid - y * (mid - 6) - 4, width: 8, height: 8)), with: .color(LYLLTHTheme.text))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let n = Int(LY_TRACK_POINTS)
                let i = min(max(Int((drag.location.x / geo.size.width * CGFloat(n - 1)).rounded()), 0), n - 1)
                let mid = geo.size.height / 2
                context.set(LYSynthParameters.trackerPoint(index, i), Float(min(max((mid - drag.location.y) / (mid - 6), -1), 1)))
            })
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

/// A step shape, drawn small.
struct LYStepShapeIcon: View {
    let shape: Int
    let color: Color

    var body: some View {
        Canvas { g, size in
            let inset = CGRect(x: 4, y: 4, width: max(1, size.width - 8), height: max(1, size.height - 8))
            var path = Path()
            for k in 0...16 {
                let t = Double(k) / 16
                let y: Double
                switch shape {
                case LY_PSTEP_RAMP_UP: y = t
                case LY_PSTEP_RAMP_DOWN: y = 1 - t
                case LY_PSTEP_TRIANGLE: y = 1 - abs(2 * t - 1)
                case LY_PSTEP_DECAY: y = exp(-5 * t)
                case LY_PSTEP_RISE: y = (exp(3 * t) - 1) / (exp(3) - 1)
                case LY_PSTEP_PULSE: y = t < 0.5 ? 1 : 0
                case LY_PSTEP_GLIDE: y = 0.5 - 0.5 * cos(.pi * t)
                default: y = 1
                }
                let point = CGPoint(x: inset.minX + inset.width * t, y: inset.maxY - inset.height * y)
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            g.stroke(path, with: .color(color), lineWidth: 1.2)
        }
    }
}
