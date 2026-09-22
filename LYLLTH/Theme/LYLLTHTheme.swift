import SwiftUI

enum LYLLTHTheme {
    static let background = Color(hex: 0x0C0C0E)
    static let panel = Color(hex: 0x0F0F13)
    static let panelRaised = Color(hex: 0x141418)
    static let line = Color.white.opacity(0.10)
    static let lineStrong = Color.white.opacity(0.18)
    static let text = Color(hex: 0xEEEEFF)
    static let secondary = Color(hex: 0xA8AABD)
    static let dim = Color(hex: 0x676878)
    static let teal = Color(hex: 0x33CCCC)
    static let indigo = Color(hex: 0x6666FF)
    static let purple = Color(hex: 0x9933FF)

    static func accent(_ token: LYAccent) -> Color {
        switch token {
        case .teal: return teal
        case .indigo: return indigo
        case .purple: return purple
        }
    }

    static func label(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func value(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func wordmark(_ size: CGFloat) -> Font {
        .custom("NIGHTSHAPE-Bold", size: size)
    }

    /// NIGHTSHAPE-Bold's cap ink sits high inside its line box. This is the
    /// same optical correction used by DrumKit for fixed-height branding.
    static func wordmarkOpticalDrop(_ size: CGFloat) -> CGFloat {
        size * 0.061
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct LYPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(LYLLTHTheme.panel)
            .overlay(Rectangle().stroke(LYLLTHTheme.line, lineWidth: 1))
    }
}

struct LYSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LYLLTHTheme.label(9, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(LYLLTHTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(LYLLTHTheme.background)
            .overlay(alignment: .bottom) { Rectangle().fill(LYLLTHTheme.line).frame(height: 1) }
    }
}
