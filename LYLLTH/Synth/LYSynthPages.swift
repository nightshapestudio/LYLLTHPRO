import SwiftUI

// MARK: - ARP

/// The arpeggiator: its pattern drawn as a lane of steps, lit as it plays.
struct LYSynthArpPage: View {
    let context: LYSynthContext

    var body: some View {
        let c = context
        let accent = LYLLTHTheme.purple
        let on = c.isOn(LY_ARP_ON)
        return VStack(spacing: 8) {
            LYSynthPanel(title: "ARPEGGIATOR", accent: accent, isOn: on, toggle: { c.toggle(LY_ARP_ON) }) {
                Text(on ? "HOLD NOTES TO PLAY THE PATTERN" : "TURN ON, THEN HOLD A CHORD")
                    .font(LYLLTHTheme.label(7.5, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(LYLLTHTheme.dim)
            } content: {
                VStack(spacing: 12) {
                    LYArpLane(patch: c.patch, live: c.live, accent: accent)
                        .frame(maxHeight: .infinity)
                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                    HStack(alignment: .center, spacing: 14) {
                        c.choice(LY_ARP_MODE, label: "MODE", names: LYSynthNames.arpModes, accent: accent, columns: 2, width: 240, anchor: "arpMode")
                            .frame(width: 130)
                        c.knob(LY_ARP_RATE, accent: accent, diameter: 40, format: { v in
                            let i = Int((v * Float(LYSynthNames.syncDivisions.count - 1)).rounded())
                            return LYSynthNames.syncDivisions[min(max(i, 0), LYSynthNames.syncDivisions.count - 1)]
                        })
                        LYSynthStepper(label: "OCTAVES", text: "\(Int(c.value(LY_ARP_OCTAVES)))", accent: accent) { step in
                            c.set(LY_ARP_OCTAVES, c.value(LY_ARP_OCTAVES) + Float(step))
                        }
                        c.knob(LY_ARP_GATE, accent: accent, diameter: 36, format: { String(format: "%.0f%%", $0 * 100) })
                        c.knob(LY_ARP_SWING, accent: accent, diameter: 36, format: { String(format: "%.0f%%", $0 * 100) })
                        LYSynthToggle(title: "LATCH", isOn: c.isOn(LY_ARP_LATCH), accent: accent) { c.toggle(LY_ARP_LATCH) }
                            .help("Keeps playing after you let go; the next chord replaces it")
                        Spacer(minLength: 0)
                    }
                    .frame(height: 70)
                }
            }
        }
    }
}

/// The pattern as it will play a C–E–G chord, step by step and octave by
/// octave, with the step that is sounding now lit.
struct LYArpLane: View {
    let patch: LYSynthPatch
    @ObservedObject var live: LYSynthLive
    let accent: Color

    private func sequence() -> [[Int]] {
        let chord = [60, 64, 67]
        let octaves = max(1, min(4, Int(patch.value(LY_ARP_OCTAVES))))
        let notes = (0..<octaves).flatMap { o in chord.map { $0 + 12 * o } }
        switch Int(patch.value(LY_ARP_MODE)) {
        case LY_ARP_DOWN: return notes.reversed().map { [$0] }
        case LY_ARP_UPDOWN: return notes.count > 1 ? (notes + notes.reversed().dropFirst().dropLast()).map { [$0] } : notes.map { [$0] }
        case LY_ARP_RANDOM: return [2, 0, 5, 1, 4, 3, 0, 2].map { [notes[$0 % notes.count]] }
        case LY_ARP_CHORD: return (0..<octaves).map { o in chord.map { $0 + 12 * o } }
        default: return notes.map { [$0] }
        }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.55)))
            let pattern = sequence()
            let steps = 16
            let all = pattern.flatMap { $0 }
            let low = (all.min() ?? 60) - 2, high = (all.max() ?? 72) + 2
            let columnWidth = size.width / CGFloat(steps)
            // Rows stay note-sized however few notes there are; the pattern
            // sits in the middle of the lane.
            let rowHeight = min((size.height - 30) / CGFloat(max(high - low, 1)), 14)
            let band = rowHeight * CGFloat(high - low)
            let floor = (size.height - 22) - ((size.height - 22) - band) / 2
            let gate = CGFloat(min(max(patch.value(LY_ARP_GATE), 0.05), 1))
            let swing = CGFloat(patch.value(LY_ARP_SWING)) * 0.33
            let current = Int(live.display.arpStep)
            for step in 0...steps {
                let x = CGFloat(step) * columnWidth
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height - 22)), with: .color(Color.white.opacity(step % 4 == 0 ? 0.08 : 0.03)))
            }
            for step in 0..<steps {
                let notes = pattern[step % pattern.count]
                let shift = step % 2 == 1 ? swing * columnWidth : 0
                let isNow = current >= 0 && current % steps == step
                for note in notes {
                    let y = floor - CGFloat(note - low) * rowHeight
                    let rect = CGRect(x: CGFloat(step) * columnWidth + shift + 2, y: y - rowHeight * 0.4, width: max(3, columnWidth * gate - 4), height: max(4, rowHeight * 0.8))
                    context.fill(Path(rect), with: .color(accent.opacity(isNow ? 1 : 0.45)))
                    if isNow {
                        var glow = context
                        glow.addFilter(.shadow(color: accent, radius: 6))
                        glow.stroke(Path(rect), with: .color(LYLLTHTheme.text), lineWidth: 1)
                    }
                }
                context.draw(Text("\(step + 1)").font(LYLLTHTheme.value(7.5)).foregroundColor(isNow ? accent : LYLLTHTheme.dim),
                             at: CGPoint(x: CGFloat(step) * columnWidth + columnWidth / 2, y: size.height - 10))
            }
            context.draw(Text("PREVIEW · C E G").font(LYLLTHTheme.label(7.5, weight: .bold)).foregroundColor(LYLLTHTheme.dim),
                         at: CGPoint(x: 52, y: 12))
        }
    }
}

// MARK: - MATRIX

/// All 32 routes: source, how much, where to, an AUX source that scales it,
/// a curve, and whether a 0…1 source swings both ways.
struct LYSynthMatrixPage: View {
    let context: LYSynthContext

    var body: some View {
        let used = context.patch.usedMatrixSlots
        return LYSynthPanel(title: "MODULATION MATRIX", accent: LYLLTHTheme.lavender) {
            Text("\(used.count) / \(LY_MATRIX_SLOTS)")
                .font(LYLLTHTheme.value(9))
                .foregroundStyle(LYLLTHTheme.dim)
        } content: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    headerCell("SOURCE", width: 130)
                    headerCell("AMOUNT", width: nil)
                    headerCell("DESTINATION", width: 150)
                    headerCell("× AUX", width: 120)
                    headerCell("CURVE", width: 64)
                    headerCell("BI", width: 30)
                    Color.clear.frame(width: 18)
                }
                .padding(.horizontal, 8)
                ScrollView {
                    VStack(spacing: 4) {
                        if used.isEmpty {
                            Text("DRAG AN ENV, LFO, MACRO OR SOURCE ONTO ANY KNOB, OR ADD A ROUTE HERE")
                                .font(LYLLTHTheme.label(8, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(LYLLTHTheme.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                        ForEach(used, id: \.self) { slot in
                            LYMatrixRow(slot: slot, context: context)
                        }
                        Button {
                            var next = context.patch
                            next.route(source: LY_SRC_LFO1, destination: LY_DST_CUTOFF, amount: 0.3)
                            context.replace(next)
                        } label: {
                            Text("+ ADD ROUTE")
                                .font(LYLLTHTheme.label(8, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(LYLLTHTheme.chromeText)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .overlay(Rectangle().stroke(LYLLTHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(used.count >= Int(LY_MATRIX_SLOTS))
                    }
                }
                .lyScrollers()
            }
        }
    }

    private func headerCell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(LYLLTHTheme.label(7, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(LYLLTHTheme.dim)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct LYMatrixRow: View {
    let slot: Int
    let context: LYSynthContext

    private func id(_ field: Int) -> Int { LYSynthParameters.matrix(slot, field) }

    var body: some View {
        let c = context
        let source = Int(c.value(id(LY_MX_SOURCE)))
        let destination = Int(c.value(id(LY_MX_DEST)))
        let amount = c.value(id(LY_MX_AMOUNT))
        let aux = Int(c.value(id(LY_MX_AUX)))
        let curve = c.value(id(LY_MX_CURVE))
        let color = LYSynthSourceColor.color(source)
        return HStack(spacing: 8) {
            LYSynthChoiceButton(label: "SOURCE", value: LYSynthNames.sources[min(max(source, 0), LYSynthNames.sources.count - 1)], accent: color) {
                c.openMenu(LYSynthMenuRequest(anchor: "mxSrc\(slot)", title: "SOURCE", names: LYSynthNames.sources, order: LYSynthNames.sourceOrder,
                                              selected: source, accent: color, columns: 3, width: 330) { c.set(id(LY_MX_SOURCE), Float($0)) })
            }
            .lyMenuAnchor("mxSrc\(slot)", in: LYSynthContext.space)
            .frame(width: 130)

            LYAmountBar(amount: amount, live: c.live, destination: destination, color: color) { c.set(id(LY_MX_AMOUNT), $0) }
                .frame(maxWidth: .infinity)

            LYSynthChoiceButton(label: "DESTINATION", value: LYSynthNames.destinations[min(max(destination, 0), LYSynthNames.destinations.count - 1)],
                                accent: LYLLTHTheme.text) {
                c.openMenu(LYSynthMenuRequest(
                    anchor: "mxDst\(slot)", title: "DESTINATION",
                    sections: LYSynthNames.destinationGroups.map { group in
                        LYSynthMenuRequest.Section(title: group.title, options: group.items.map { .init(value: $0.0, label: $0.1) })
                    },
                    selected: destination, accent: LYLLTHTheme.lavender, columns: 3, width: 420) { c.set(id(LY_MX_DEST), Float($0)) })
            }
            .lyMenuAnchor("mxDst\(slot)", in: LYSynthContext.space)
            .frame(width: 150)

            LYSynthChoiceButton(label: "AUX", value: aux == LY_SRC_NONE ? "—" : LYSynthNames.sources[min(max(aux, 0), LYSynthNames.sources.count - 1)],
                                accent: LYSynthSourceColor.color(aux), isActive: aux != LY_SRC_NONE) {
                c.openMenu(LYSynthMenuRequest(anchor: "mxAux\(slot)", title: "SCALED BY", names: LYSynthNames.sources, order: LYSynthNames.sourceOrder,
                                              selected: aux, accent: LYLLTHTheme.lavender, columns: 3, width: 330) { c.set(id(LY_MX_AUX), Float($0)) })
            }
            .lyMenuAnchor("mxAux\(slot)", in: LYSynthContext.space)
            .frame(width: 120)

            LYCurveKnob(curve: curve, color: color) { c.set(id(LY_MX_CURVE), $0) }
                .frame(width: 64, height: 30)

            LYSynthToggle(title: "BI", isOn: c.isOn(id(LY_MX_BIPOLAR)), accent: color) { c.toggle(id(LY_MX_BIPOLAR)) }
                .help("Bipolar: a 0…1 source (envelope, velocity, macro) swings both ways around the knob")
                .frame(width: 30)

            Button {
                var next = c.patch
                next.clearRoute(slot)
                c.replace(next)
            } label: {
                Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold)).foregroundStyle(LYLLTHTheme.dim)
                    .frame(width: 18, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this route")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(color.opacity(0.05))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
        .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }
}

/// A bipolar amount: drag from the centre either way; a dot shows what the
/// route is doing right now.
struct LYAmountBar: View {
    let amount: Float
    @ObservedObject var live: LYSynthLive
    let destination: Int
    let color: Color
    let set: (Float) -> Void

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack(alignment: .leading) {
                Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 2)
                Rectangle().fill(LYLLTHTheme.dim).frame(width: 1, height: 12).offset(x: mid)
                Rectangle().fill(color)
                    .frame(width: abs(CGFloat(amount)) * mid, height: 4)
                    .offset(x: amount >= 0 ? mid : mid - abs(CGFloat(amount)) * mid)
                    .lyBloom(color, isOn: color != LYLLTHTheme.teal, strength: 0.5)
                let now = live.modulation(destination)
                Circle().fill(LYLLTHTheme.text).frame(width: 5, height: 5)
                    .offset(x: mid + CGFloat(min(max(now, -1), 1)) * mid - 2.5)
                    .opacity(abs(now) > 0.001 ? 1 : 0)
                Text(String(format: "%+.0f", amount * 100))
                    .font(LYLLTHTheme.value(9))
                    .foregroundStyle(LYLLTHTheme.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: -11)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fine: Float = NSEvent.modifierFlags.contains(.option) ? 0.25 : 1
                set(Float(min(max((drag.location.x - mid) / mid, -1), 1)) * fine)
            })
            .onTapGesture(count: 2) { set(0) }
        }
        .help("Drag left or right from the centre. Double-click for zero.")
    }
}

/// The route's response curve, drawn; drag up or down to bend it.
struct LYCurveKnob: View {
    let curve: Float
    let color: Color
    let set: (Float) -> Void
    @State private var origin: Float?

    var body: some View {
        Canvas { context, size in
            context.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(LYLLTHTheme.lineStrong), lineWidth: 1)
            var path = Path()
            for i in 0...24 {
                let p = Double(i) / 24
                let k = Double(curve) * 5
                let y = abs(curve) < 0.01 ? p : (exp(k * p) - 1) / (exp(k) - 1)
                let point = CGPoint(x: 3 + (size.width - 6) * CGFloat(p), y: size.height - 3 - (size.height - 6) * CGFloat(y))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), lineWidth: 1.4)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
            let start = origin ?? curve
            if origin == nil { origin = start }
            set(min(max(start - Float(drag.translation.height / 60), -1), 1))
        }.onEnded { _ in origin = nil })
        .onTapGesture(count: 2) { set(0) }
        .help("Drag up or down to bend the response. Double-click for straight.")
    }
}

// MARK: - GLOBAL

struct LYSynthGlobalPage: View {
    let context: LYSynthContext

    var body: some View {
        let c = context
        let accent = LYLLTHTheme.indigo
        return HStack(alignment: .top, spacing: 8) {
            LYSynthPanel(title: "VOICING", accent: accent) {
                VStack(alignment: .leading, spacing: 18) {
                    LYVoiceLights(live: c.live, voices: Int(c.value(LY_VOICES)), accent: accent)
                        .frame(height: 34)
                    HStack(spacing: 10) {
                        LYSynthStepper(label: "POLYPHONY", text: Int(c.value(LY_VOICES)) == 1 ? "MONO" : "\(Int(c.value(LY_VOICES)))", accent: accent) { step in
                            c.set(LY_VOICES, c.value(LY_VOICES) + Float(step))
                        }
                        LYSynthToggle(title: "LEGATO", isOn: c.isOn(LY_LEGATO), accent: accent) { c.toggle(LY_LEGATO) }
                            .help("In MONO, a note played while another is held slides without restarting the envelopes")
                        LYSynthStepper(label: "BEND RANGE", text: "±\(Int(c.value(LY_BEND_RANGE)))", accent: accent) { step in
                            c.set(LY_BEND_RANGE, c.value(LY_BEND_RANGE) + Float(step))
                        }
                    }
                    HStack(spacing: 18) {
                        c.knob(LY_GLIDE, accent: accent, diameter: 40, format: { String(format: "%.0f MS", $0 * 1000) })
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GLIDE").font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.dim)
                            HStack(spacing: 3) {
                                LYSynthToggle(title: "ALWAYS", isOn: c.isOn(LY_GLIDE_ALWAYS), accent: accent) { c.set(LY_GLIDE_ALWAYS, 1) }
                                LYSynthToggle(title: "LEGATO ONLY", isOn: !c.isOn(LY_GLIDE_ALWAYS), accent: accent) { c.set(LY_GLIDE_ALWAYS, 0) }
                            }
                        }
                        c.knob(LY_VEL_SENS, accent: accent, diameter: 40, label: "VELOCITY", format: { String(format: "%.0f%%", $0 * 100) })
                            .help("How much playing harder makes it louder. Velocity can also be routed in the matrix.")
                        c.knob(LY_TUNE, accent: accent, diameter: 40, label: "MASTER TUNE", format: { String(format: "%+.0f¢", $0) })
                    }
                    LYVelocityCurve(sensitivity: c.value(LY_VEL_SENS), accent: accent)
                        .frame(width: 320, height: 110)
                    HStack(spacing: 10) {
                        LYSynthToggle(title: "MPE", isOn: c.isOn(LY_MPE), accent: accent) { c.toggle(LY_MPE) }
                        Text("MPE: EACH NOTE'S OWN CHANNEL CARRIES ITS BEND (±48), PRESSURE AND TIMBRE (CC 74). ROUTE PRESSURE AND TIMBRE IN THE MATRIX.")
                            .font(LYLLTHTheme.label(7, weight: .bold))
                            .tracking(0.9)
                            .lineSpacing(3)
                            .foregroundStyle(LYLLTHTheme.dim)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            LYSynthPanel(title: "LUNATK", accent: LYLLTHTheme.lavender) {
                VStack(alignment: .leading, spacing: 12) {
                    LUNATKMark(size: 30)
                    Text("WAVETABLE SYNTHESIZER BY NIGHTSHAPE")
                        .font(LYLLTHTheme.label(8, weight: .bold)).tracking(1.4).foregroundStyle(LYLLTHTheme.text)
                    VStack(alignment: .leading, spacing: 6) {
                        fact("OSCILLATORS", "2 WAVETABLE · 16 UNISON · DUAL WARP · STACK")
                        fact("SUB + NOISE", "4 SHAPES · 8 NOISE TYPES")
                        fact("FILTERS", "2 · SERIAL OR PARALLEL · \(LY_FILTER_COUNT) TYPES")
                        fact("MODULATION", "4 ENV · 4 LFO · 4 MACROS · \(LY_MATRIX_SLOTS)-SLOT MATRIX")
                        fact("FX", "\(LY_FX_COUNT) EFFECTS · ANY ORDER")
                        fact("PLAY", "16 VOICES · ARP · MPE · SUSTAIN")
                    }
                    Spacer(minLength: 0)
                    Text("COMPUTER KEYS A–K PLAY · Z / X OCTAVE · ESC CLOSES")
                        .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1).foregroundStyle(LYLLTHTheme.dim)
                }
            }
            .frame(width: 420)
        }
    }

    private func fact(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.2).foregroundStyle(LYLLTHTheme.lavender).frame(width: 90, alignment: .leading)
            Text(detail).font(LYLLTHTheme.label(7.5, weight: .bold)).tracking(0.8).foregroundStyle(LYLLTHTheme.secondary)
        }
    }
}

/// Sixteen lamps, one per voice: lit while sounding, dim when allowed but
/// idle, dark past the polyphony.
struct LYVoiceLights: View {
    @ObservedObject var live: LYSynthLive
    let voices: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("VOICES  \(live.display.activeVoices) / \(voices == 1 ? "MONO" : "\(voices)")")
                .font(LYLLTHTheme.label(7, weight: .bold)).tracking(1.3).foregroundStyle(LYLLTHTheme.dim)
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { index in
                    let allowed = index < voices
                    let sounding = index < Int(live.display.activeVoices)
                    Rectangle()
                        .fill(sounding ? accent : (allowed ? accent.opacity(0.12) : Color.clear))
                        .frame(width: 16, height: 12)
                        .overlay(Rectangle().stroke(allowed ? accent.opacity(0.6) : LYLLTHTheme.lineStrong, lineWidth: 1))
                        .lyBloom(accent, isOn: sounding, strength: 0.6)
                }
            }
        }
    }
}

/// How loud a note plays against how hard it is struck.
struct LYVelocityCurve: View {
    let sensitivity: Float
    let accent: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4, y = size.height * CGFloat(i) / 4
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.04)))
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.04)))
            }
            var path = Path()
            for i in 0...40 {
                let v = Double(i) / 40
                // The core's velocity curve (0.8 power) and sensitivity blend.
                let shaped = pow(max(v, 1 / 127), 0.8)
                let level = (1 - Double(sensitivity)) + Double(sensitivity) * shaped
                let point = CGPoint(x: size.width * CGFloat(v), y: size.height - 6 - (size.height - 12) * CGFloat(level))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var glow = context
            glow.addFilter(.shadow(color: accent.opacity(0.7), radius: 3))
            glow.stroke(path, with: .color(accent), lineWidth: 1.6)
            context.draw(Text("VELOCITY → LEVEL").font(LYLLTHTheme.label(7, weight: .bold)).foregroundColor(LYLLTHTheme.dim),
                         at: CGPoint(x: 62, y: 12))
        }
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}
