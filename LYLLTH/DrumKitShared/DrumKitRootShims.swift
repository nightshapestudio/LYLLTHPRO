import AppKit
import SwiftUI

// Two helpers DrumKit's FX files call that DrumKit defines in its iPhone root
// view (Views/DrumkitRootView.swift), which LYLLTH does not compile.

/// DrumKit's haptics vocabulary on a Force Touch trackpad. The iPhone taps
/// map to the trackpad's two feedback patterns; there is no Mac equivalent
/// for success/warning, so those stay silent.
enum NightshapeHaptics {
    private static var performer: NSHapticFeedbackPerformer { NSHapticFeedbackManager.defaultPerformer }

    static func prepare() {}
    static func selection() { performer.perform(.alignment, performanceTime: .now) }
    static func step(enabled: Bool) { performer.perform(.alignment, performanceTime: .now) }
    static func transport(starting: Bool) { performer.perform(.levelChange, performanceTime: .now) }
    static func fxReorder() { performer.perform(.levelChange, performanceTime: .now) }
    static func detent() { performer.perform(.alignment, performanceTime: .now) }
    static func commit() { performer.perform(.alignment, performanceTime: .now) }
    static func confirm() {}
    static func destructive() {}
}

extension View {
    /// Copied from DrumKit's root view so shared panels keep the same frame.
    func nightshapePremiumPanelChrome(accent: Color) -> some View {
        self
            .background(
                LinearGradient(colors: [Color(hex: 0x15171F), Color(hex: 0x08090C)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(Rectangle().stroke(accent.opacity(0.42), lineWidth: 1.1))
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1).padding(1))
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        accent.opacity(0),
                        accent.opacity(0.95),
                        NightshapeTheme.accentIndigo.opacity(0.85),
                        accent.opacity(0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 2)
            }
            .clipShape(Rectangle())
            .shadow(color: Color.black.opacity(0.78), radius: 34, x: 0, y: 18)
            .shadow(color: accent.opacity(0.14), radius: 26, x: 0, y: 0)
    }
}

/// iOS keyboard capitalisation has no macOS counterpart. DrumKit's preset-name
/// field asks for capitals; on the Mac the field is already set in caps type.
struct TextInputAutocapitalization {
    static let characters = TextInputAutocapitalization()
    static let never = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
}

extension View {
    func textInputAutocapitalization(_ value: TextInputAutocapitalization?) -> some View { self }
}

// Copied verbatim from DrumKit Views/DrumkitRootView.swift (SongFXGlyph), which
// FRACTURE's window draws its move icons with.
struct SongFXGlyph: Shape {
    let move: SongFXMove

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height, x0 = rect.minX, y0 = rect.minY
        switch move {
        case .stutter:
            // Even repeats.
            for i in 0..<6 {
                let x = x0 + w * (CGFloat(i) + 0.5) / 6
                path.move(to: CGPoint(x: x, y: y0 + h * 0.15))
                path.addLine(to: CGPoint(x: x, y: y0 + h * 0.85))
            }
        case .roll:
            // Repeats getting closer together.
            var x = x0 + w * 0.04
            var gap = w * 0.24
            while x < x0 + w {
                path.move(to: CGPoint(x: x, y: y0 + h * 0.15))
                path.addLine(to: CGPoint(x: x, y: y0 + h * 0.85))
                x += gap
                gap = max(w * 0.035, gap * 0.62)
            }
        case .tapeStop:
            // Slowing to a stop.
            path.move(to: CGPoint(x: x0, y: y0 + h * 0.15))
            path.addQuadCurve(to: CGPoint(x: x0 + w, y: y0 + h * 0.9), control: CGPoint(x: x0 + w * 0.75, y: y0 + h * 0.1))
        case .reverse:
            // Backwards ramps.
            for i in 0..<3 {
                let a = x0 + w * CGFloat(i) / 3
                path.move(to: CGPoint(x: a, y: y0 + h * 0.15))
                path.addLine(to: CGPoint(x: a + w / 3, y: y0 + h * 0.85))
                path.addLine(to: CGPoint(x: a + w / 3, y: y0 + h * 0.15))
            }
        case .crush:
            // Stairs.
            let steps = 5
            path.move(to: CGPoint(x: x0, y: y0 + h * 0.85))
            for i in 0..<steps {
                let y = y0 + h * (0.85 - 0.7 * CGFloat(i + 1) / CGFloat(steps))
                path.addLine(to: CGPoint(x: x0 + w * CGFloat(i) / CGFloat(steps), y: y))
                path.addLine(to: CGPoint(x: x0 + w * CGFloat(i + 1) / CGFloat(steps), y: y))
            }
        case .gate:
            // On, off, on, off.
            path.move(to: CGPoint(x: x0, y: y0 + h * 0.85))
            for i in 0..<4 {
                let a = x0 + w * CGFloat(i) / 4
                path.addLine(to: CGPoint(x: a, y: y0 + h * 0.15))
                path.addLine(to: CGPoint(x: a + w / 8, y: y0 + h * 0.15))
                path.addLine(to: CGPoint(x: a + w / 8, y: y0 + h * 0.85))
                path.addLine(to: CGPoint(x: a + w / 4, y: y0 + h * 0.85))
            }
        case .drop:
            // Signal, then nothing.
            path.move(to: CGPoint(x: x0, y: y0 + h * 0.5))
            path.addLine(to: CGPoint(x: x0 + w * 0.3, y: y0 + h * 0.5))
            path.move(to: CGPoint(x: x0 + w * 0.3, y: y0 + h * 0.15))
            path.addLine(to: CGPoint(x: x0 + w * 0.3, y: y0 + h * 0.85))
            path.move(to: CGPoint(x: x0 + w * 0.7, y: y0 + h * 0.15))
            path.addLine(to: CGPoint(x: x0 + w * 0.7, y: y0 + h * 0.85))
            path.move(to: CGPoint(x: x0 + w * 0.7, y: y0 + h * 0.5))
            path.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.5))
        default:
            return SongFXCurve(move: move, start: move.defaultStartLevel, end: move.defaultEndLevel).path(in: rect)
        }
        return path
    }
}
struct SongFXCurve: Shape {
    let move: SongFXMove
    let start: Float
    let end: Float

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = max(8, Int(rect.width / 3))
        for index in 0...samples {
            let t = Double(index) / Double(samples)
            let level = CGFloat(move.level(at: t, start: start, end: end))
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(t), y: rect.maxY - rect.height * level)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
