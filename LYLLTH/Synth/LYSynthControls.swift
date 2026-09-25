import SwiftUI

// MARK: - Modulation colours

/// Each modulation source keeps one colour everywhere: its tab, its drag
/// handle, the rings it draws on the knobs it drives. Positional 2-2-2 like
/// the tracks, so no one hue carries the editor.
enum LYSynthSourceColor {
    static func color(_ source: Int) -> Color {
        switch source {
        case LY_SRC_ENV1, LY_SRC_LFO1, LY_SRC_MACRO1: return LYLLTHTheme.teal
        case LY_SRC_ENV2, LY_SRC_LFO2, LY_SRC_MACRO2: return LYLLTHTheme.indigo
        case LY_SRC_ENV3, LY_SRC_LFO3, LY_SRC_MACRO3: return LYLLTHTheme.purple
        case LY_SRC_LFO4, LY_SRC_MACRO4: return LYLLTHTheme.lavender
        default: return LYLLTHTheme.chromeText
        }
    }

    static let dragPrefix = "lyllth-mod-source:"
}

// MARK: - Knob

/// The synth's knob: DrumKit's FX knob drawing, plus Serum-style modulation.
/// Every route into this knob's destination draws an arc in its source's
/// colour from the knob's value to where the modulation takes it, and a dot
/// shows the live modulated value. Drop a modulation source on it to route.
struct LYSynthKnob: View {
    let parameter: Int
    var destination: Int? = nil
    let patch: LYSynthPatch
    var accent: Color = LYLLTHTheme.teal
    var diameter: CGFloat = 36
    var label: String? = nil
    var format: ((Float) -> String)? = nil
    var liveModulation: Float = 0
    let update: (Int, Float) -> Void
    var addRoute: ((Int, Int) -> Void)? = nil

    @State private var dragStart: Float?
    @State private var isDropTarget = false

    private var definition: LYSynthParameter? { LYSynthParameters.byID[parameter] }
    private var value: Float { patch.value(parameter) }
    private var fraction: CGFloat { CGFloat(min(max(definition?.normalized(value) ?? 0, 0), 1)) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(Color(hex: 0x0C0D12))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                Circle()
                    .trim(from: 0, to: fraction * 0.75)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                    .shadow(color: accent.opacity(dragStart == nil ? 0.4 : 0.8), radius: dragStart == nil ? 2.5 : 5)
                modulationRings
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: diameter * 0.22)
                    .offset(y: -diameter * 0.22)
                    .rotationEffect(.degrees(-135 + Double(fraction) * 270))
                if isDropTarget {
                    Circle().stroke(LYLLTHTheme.chromeText, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(-5)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        guard let definition else { return }
                        let start = dragStart ?? Float(fraction)
                        if dragStart == nil { dragStart = start }
                        let fine: Float = NSEvent.modifierFlags.contains(.option) ? 0.2 : 1
                        let delta = Float((drag.translation.width - drag.translation.height) / 180) * fine
                        update(parameter, definition.value(fromNormalized: start + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) {
                update(parameter, LYSynthParameters.defaults[parameter] ?? 0)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let destination, let item = items.first,
                      item.hasPrefix(LYSynthSourceColor.dragPrefix),
                      let source = Int(item.dropFirst(LYSynthSourceColor.dragPrefix.count)) else { return false }
                addRoute?(source, destination)
                return true
            } isTargeted: { isDropTarget = $0 && destination != nil }

            Text(format?(value) ?? defaultText)
                .font(LYLLTHTheme.value(diameter >= 50 ? 12 : 10))
                .foregroundStyle(LYLLTHTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label ?? definition?.label ?? "")
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: diameter + 14)
        .help(destination == nil ? "Drag to set. Option-drag for fine. Double-click to reset." :
              "Drag to set. Option-drag for fine. Double-click to reset. Drop an ENV, LFO or MACRO here to modulate it.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? definition?.label ?? "")
        .accessibilityValue(format?(value) ?? defaultText)
        .accessibilityAdjustableAction { direction in
            guard let definition else { return }
            let step: Float = direction == .increment ? 0.02 : -0.02
            update(parameter, definition.value(fromNormalized: Float(fraction) + step))
        }
    }

    private var defaultText: String {
        guard let definition else { return "" }
        if definition.isStepped { return String(Int(value.rounded())) }
        if definition.range.lowerBound < 0 { return String(format: "%+.0f%%", value * 100) }
        return String(format: "%.0f%%", definition.normalized(value) * 100)
    }

    @ViewBuilder
    private var modulationRings: some View {
        if let destination {
            let routes = patch.routes(into: destination)
            ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                let color = LYSynthSourceColor.color(route.source)
                let start = Double(fraction) * 0.75
                let end = min(max(start + Double(route.amount) * 0.75, 0), 0.75)
                Circle()
                    .trim(from: min(start, end), to: max(start, end))
                    .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                    .rotationEffect(.degrees(135))
                    .padding(-2 - CGFloat(index) * 3.5)
            }
            if !routes.isEmpty {
                let live = min(max(Double(fraction) + Double(liveModulation), 0), 1)
                Circle()
                    .fill(LYLLTHTheme.text)
                    .frame(width: 4, height: 4)
                    .offset(y: -(diameter / 2 + 2))
                    .rotationEffect(.degrees(-135 + live * 270))
            }
        }
    }
}

// MARK: - Small controls

struct LYSynthToggle: View {
    let title: String
    let isOn: Bool
    var accent: Color = LYLLTHTheme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(isOn ? accent : LYLLTHTheme.dim)
                .padding(.horizontal, 7)
                .frame(minWidth: 22, minHeight: 20)
                .background(accent.opacity(isOn ? 0.12 : 0))
                .overlay(Rectangle().stroke(isOn ? accent.opacity(0.85) : LYLLTHTheme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A value stepped with arrows either side, for octaves, semitones, voices.
struct LYSynthStepper: View {
    let label: String
    let text: String
    var accent: Color = LYLLTHTheme.teal
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left") { step(-1) }
            VStack(spacing: 0) {
                Text(text).font(LYLLTHTheme.value(10)).foregroundStyle(LYLLTHTheme.text)
                Text(label).font(LYLLTHTheme.label(6.5, weight: .bold)).tracking(1).foregroundStyle(accent)
            }
            .frame(minWidth: 36)
            arrow("chevron.right") { step(1) }
        }
        .frame(height: 26)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }

    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(LYLLTHTheme.chromeText)
                .frame(width: 16, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// NIGHTSHAPE list chooser. It opens in place over its panel instead of a
/// system menu.
struct LYSynthChoiceList: View {
    let title: String
    let options: [String]
    let selected: Int
    var accent: Color = LYLLTHTheme.teal
    var columns: Int = 2
    let choose: (Int) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(LYLLTHTheme.label(8.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(accent)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button { choose(index); close() } label: {
                            Text(option)
                                .font(LYLLTHTheme.label(8, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(index == selected ? accent : LYLLTHTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 24)
                                .background(accent.opacity(index == selected ? 0.12 : 0.02))
                                .overlay(Rectangle().stroke(index == selected ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .lyScrollers()
        }
        .padding(10)
        .background(Color(hex: 0x07080D).opacity(0.97))
        .overlay(Rectangle().stroke(accent.opacity(0.6), lineWidth: 1))
    }
}

/// A panel in the synth: matte, one hairline, its name in its colour.
struct LYSynthPanel<Content: View, Trailing: View>: View {
    let title: String
    var accent: Color = LYLLTHTheme.teal
    var isOn: Bool? = nil
    var toggle: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let isOn, let toggle {
                    Button(action: toggle) {
                        Rectangle()
                            .fill(isOn ? accent : Color.clear)
                            .frame(width: 6, height: 6)
                            .frame(width: 14, height: 14)
                            .overlay(Rectangle().stroke(isOn ? accent : LYLLTHTheme.lineStrong, lineWidth: 1))
                            .lyBloom(accent, isOn: isOn, strength: 0.5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isOn ? "Turn off" : "Turn on")
                }
                Text(title)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(isOn == false ? LYLLTHTheme.dim : accent)
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(accent.opacity(0.05))
            .overlay(alignment: .bottom) { LYHairline() }
            content()
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(isOn == false ? 0.45 : 1)
        }
        .background(LYLLTHTheme.panel)
        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
    }
}

extension LYSynthPanel where Trailing == EmptyView {
    init(title: String, accent: Color = LYLLTHTheme.teal, isOn: Bool? = nil, toggle: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accent = accent
        self.isOn = isOn
        self.toggle = toggle
        self.trailing = { EmptyView() }
        self.content = content
    }
}
