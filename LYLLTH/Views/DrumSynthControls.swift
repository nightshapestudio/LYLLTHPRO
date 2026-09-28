import NightshapeAudioEngine
import SwiftUI

// DrumKit's drum synth knob and option control, copied from its DRUM SYNTH
// page (Views/DrumSynthBrowserView.swift, which is iPhone-only and not to be
// edited) so LYLLTH's DRUM SYNTH page and the shared shape and filter
// editors turn exactly the same knob. Keep in step with DrumKit by hand.

struct DrumSynthKnobView: View {
    let label: String
    let valueText: () -> String
    @Binding var value: Double
    let accent: Color
    /// Same-color bloom to lift apparent brightness (used for the indigo
    /// sections, which read dimmer than cyan/violet at the same hex).
    var bloom: Bool = false
    /// The unrounded position under the finger. The bound value is snapped to
    /// what the knob displays, so the drag keeps its own running total and a
    /// value can walk step by step instead of sticking on the snap.
    @State private var dragValue: Double?
    @State private var lastTranslation: CGSize = .zero
    @State private var lastDragTime: Date?
    @State private var shownText = ""
    private let ticker = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color(hex: 0x1E1E22), lineWidth: 1.5)
                    .background(Circle().fill(Color(hex: 0x0C0C0E)))

                Circle()
                    .trim(from: 0, to: CGFloat(clampedValue) * 0.75)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .opacity(0.95)
                    .shadow(color: bloom ? accent.opacity(0.9) : .clear, radius: bloom ? 2.5 : 0)
                    .shadow(color: bloom ? accent.opacity(0.5) : .clear, radius: bloom ? 5 : 0)

                Circle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: bloom ? accent.opacity(0.95) : .clear, radius: bloom ? 2.5 : 0)
                    .shadow(color: bloom ? accent.opacity(0.5) : .clear, radius: bloom ? 5 : 0)
                    .offset(y: -16)
                    // Dot rotation must match the arc's angular range so the
                    // indicator lines up with the band: 225° CW puts the dot
                    // at 7:30 (lower-left = arc start) at value 0; +270° more
                    // lands it at 4:30 (lower-right = arc end) at value 1.
                    .rotationEffect(.degrees(225 + clampedValue * 270))
            }
            .frame(width: 40, height: 40)
            // Grows a touch under the finger so it reads as held.
            .scaleEffect(isAdjusting ? 1.28 : 1)
            // While held, a wider ring opens around the knob and fills with the
            // value, big enough to read past the finger on it.
            .background {
                if isAdjusting {
                    DrumSynthKnobRing(position: clampedValue, accent: accent)
                        .frame(width: 80, height: 80)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let now = Date()
                        if dragValue == nil {
                            dragValue = clampedValue
                            lastTranslation = .zero
                            lastDragTime = now
                            shownText = valueText()
                            ticker.prepare()
                        }
                        let dx = Double(gesture.translation.width - lastTranslation.width)
                        let dy = Double(gesture.translation.height - lastTranslation.height)
                        let elapsed = max(now.timeIntervalSince(lastDragTime ?? now), 1.0 / 240)
                        // Slow movement is fine control: a creeping finger moves
                        // the knob up to ~7x less, so a single step is easy to
                        // land on. A quick swipe still covers the whole range.
                        let speed = (dx * dx + dy * dy).squareRoot() / elapsed
                        let fine = min(max(speed / 320, 0.15), 1)
                        let delta = (dx - dy) / 150 * fine
                        let next = min(max((dragValue ?? clampedValue) + delta, 0), 1)
                        dragValue = next
                        lastTranslation = gesture.translation
                        lastDragTime = now
                        value = next
                        let text = valueText()
                        if text != shownText {
                            // Rolls the digits in the readout rather than
                            // swapping them.
                            withAnimation(.snappy(duration: 0.14)) { shownText = text }
                            ticker.selectionChanged()
                        }
                    }
                    .onEnded { gesture in
                        if abs(gesture.translation.width) < 2, abs(gesture.translation.height) < 2 {
                            value = min(clampedValue + 0.05, 1)
                        }
                        dragValue = nil
                        lastDragTime = nil
                    }
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    value = min(clampedValue + 0.05, 1)
                case .decrement:
                    value = max(clampedValue - 0.05, 0)
                @unknown default:
                    break
                }
            }

            // Colour only. 0x555566 and 0x444455 measured 2.7:1 and 2.1:1 on
            // this page, so the reading and the name of every synth knob sat
            // below the point where they are legible on a phone. The faces are
            // left on the page's monospaced cut deliberately: swapping them to
            // the theme's numeric/meta faces is the right end state but changes
            // glyph widths inside a four-column grid, which wants a look on a
            // device first.
            Text(valueText())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(NightshapeTheme.textSecondary)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(NightshapeTheme.textFloor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(minWidth: 40)
        .overlay(alignment: .top) {
            if isAdjusting {
                DrumSynthKnobReadout(label: label, value: shownText, accent: accent)
                    .offset(y: -84)
                    .transition(.scale(scale: 0.82, anchor: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .zIndex(isAdjusting ? 10 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isAdjusting)
    }

    private var isAdjusting: Bool { dragValue != nil }

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }
}

/// The enlarged readout that rides above a knob while it is held: the name,
/// the value in the display face, and a thin bar for where the knob sits.
/// Flat outline language, bloom rather than any fill or gradient.
private struct DrumSynthKnobReadout: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(NightshapeTheme.textFloor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(NightshapeTheme.dm80Light(size: 26))
                .tracking(1.2)
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.55), radius: 5)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // A fixed box, so it doesn't resize as the reading changes.
        .frame(width: 112)
        .background(Color(hex: 0x08080A))
        .overlay {
            RoundedRectangle(cornerRadius: 3)
                .stroke(accent.opacity(0.85), lineWidth: 1)
        }
        // Corner brackets: the instrument-readout detail.
        .overlay(alignment: .topLeading) { bracket.offset(x: -3, y: -3) }
        .overlay(alignment: .bottomTrailing) { bracket.rotationEffect(.degrees(180)).offset(x: 3, y: 3) }
    }

    private var bracket: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 8, y: 0))
        }
        .stroke(accent, lineWidth: 1.5)
        .frame(width: 8, height: 8)
    }
}

/// The held-knob ring: a dim track over the knob's 270 degrees of travel, the
/// lit run filling up to the value, and ticks every tenth.
private struct DrumSynthKnobRing: View {
    let position: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color(hex: 0x1E1E22), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * CGFloat(position))
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: accent.opacity(0.9), radius: 3)
                .shadow(color: accent.opacity(0.45), radius: 7)
                .animation(.snappy(duration: 0.1), value: position)
            ForEach(0...10, id: \.self) { tick in
                Rectangle()
                    .fill(Double(tick) / 10 <= position + 0.0001 ? accent : Color(hex: 0x3A3A48))
                    .frame(width: 1, height: tick % 5 == 0 ? 6 : 3)
                    .offset(y: -46)
                    .rotationEffect(.degrees(225 + Double(tick) * 27))
            }
        }
    }
}

struct DrumSynthOptionControlView: View {
    let label: String
    let valueText: () -> String
    @Binding var value: Double
    let optionCount: Int
    let accent: Color
    /// See DrumSynthKnobView.bloom.
    var bloom: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Button {
                advance()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color(hex: 0x1E1E22), lineWidth: 1.5)
                        .background(Circle().fill(Color(hex: 0x0C0C0E)))

                    Text(valueText())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(accent.opacity(0.95))
                        .shadow(color: bloom ? accent.opacity(0.9) : .clear, radius: bloom ? 2.5 : 0)
                        .shadow(color: bloom ? accent.opacity(0.45) : .clear, radius: bloom ? 5 : 0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .padding(.horizontal, 6)
                }
                .frame(width: 40, height: 40)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    advance()
                case .decrement:
                    retreat()
                @unknown default:
                    break
                }
            }

            // Matches DrumSynthKnobView above: colour tiers only, faces left
            // as they were.
            Text(valueText())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(NightshapeTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(NightshapeTheme.textFloor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(minWidth: 40)
    }

    private func advance() {
        let count = max(optionCount, 2)
        let current = currentIndex(count: count)
        let next = (current + 1) % count
        value = normalizedValue(for: next, count: count)
    }

    private func retreat() {
        let count = max(optionCount, 2)
        let current = currentIndex(count: count)
        let next = (current + count - 1) % count
        value = normalizedValue(for: next, count: count)
    }

    private func currentIndex(count: Int) -> Int {
        min(max(Int((clampedValue * Double(count - 1)).rounded()), 0), count - 1)
    }

    private func normalizedValue(for index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) / Double(count - 1)
    }

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }
}
