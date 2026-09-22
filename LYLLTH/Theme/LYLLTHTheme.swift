import SwiftUI

enum LYLLTHTheme {
    static let background = Color(hex: 0x0C0C0E)
    static let deck = Color(hex: 0x09090C)
    static let panel = Color(hex: 0x0F0F13)
    static let panelRaised = Color(hex: 0x141418)
    static let panelPressed = Color(hex: 0x18181E)

    static let line = Color.white.opacity(0.085)
    static let lineStrong = Color(hex: 0x343440)
    static let lineFocused = Color(hex: 0x57586A)

    static let text = Color(hex: 0xEEEEFF)
    static let secondary = Color(hex: 0xB6B8C6)
    static let metadata = Color(hex: 0x9090A0)
    static let dim = Color(hex: 0x656574)
    static let off = Color(hex: 0x393945)
    static let chrome = Color(hex: 0xDCE6FA)

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
        switch weight {
        case .ultraLight, .thin, .light:
            return .custom("Adam-Light", size: size)
        case .semibold, .bold, .heavy, .black:
            return .custom("Adam-Bold", size: size)
        default:
            return .custom("Adam-Medium", size: size)
        }
    }

    static func value(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        label(size, weight: weight).monospacedDigit()
    }

    static func wordmark(_ size: CGFloat) -> Font {
        .custom("NIGHTSHAPE-Bold", size: size)
    }

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

struct LYHairline: View {
    var color = LYLLTHTheme.line

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

struct LYPanelHeader: View {
    let title: String
    var detail: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(LYLLTHTheme.teal)
                .frame(width: 16, height: 1)
            Text(title)
                .font(LYLLTHTheme.label(10, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(LYLLTHTheme.secondary)
            if let detail {
                Text(detail)
                    .font(LYLLTHTheme.label(9))
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            Spacer()
            if let actionIcon, let action {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LYLLTHTheme.metadata)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(LYLLTHTheme.panel)
        .overlay(alignment: .bottom) { LYHairline() }
    }
}

struct LYChromeButtonStyle: ButtonStyle {
    var active = false
    var tint = LYLLTHTheme.teal
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LYLLTHTheme.label(compact ? 9 : 10, weight: .bold))
            .foregroundStyle(active ? tint : LYLLTHTheme.secondary)
            .padding(.horizontal, compact ? 8 : 11)
            .frame(height: compact ? 25 : 30)
            .background(configuration.isPressed ? LYLLTHTheme.panelPressed : Color.clear)
            .overlay {
                Rectangle()
                    .stroke(active ? tint.opacity(0.82) : LYLLTHTheme.lineStrong, lineWidth: 1)
            }
    }
}

struct LYLED: View {
    var color = LYLLTHTheme.teal
    var isOn = true
    var size: CGFloat = 5

    var body: some View {
        Circle()
            .fill(isOn ? color : LYLLTHTheme.off)
            .frame(width: size, height: size)
            .shadow(color: isOn ? color.opacity(0.22) : .clear, radius: 3)
    }
}
