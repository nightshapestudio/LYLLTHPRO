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
    static let lavender = Color(hex: 0xBBA6FD)

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

    /// The single numeric-readout face used across NIGHTSHAPE products.
    /// Labels stay in Adam; reported values use the quiet, thin SF display cut
    /// with fixed-width figures so changing values never shift laterally.
    static func value(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .thin, design: .default).monospacedDigit()
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
    var numeric = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(numeric
                ? LYLLTHTheme.value(compact ? 9 : 10)
                : LYLLTHTheme.label(compact ? 9 : 10, weight: .bold))
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

/// The only menu language used inside the LYLLTH workspace. Product controls
/// never inherit SwiftUI `Menu`, `contextMenu`, or system-popover chrome.
struct LYNightshapeMenuOverlay<Content: View>: View {
    let dismiss: () -> Void
    let content: Content

    init(dismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.dismiss = dismiss
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            content
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
    }
}

struct LYNightshapeMenuHeader: View {
    let eyebrow: String
    let title: String
    var accent = LYLLTHTheme.teal
    var close: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(accent.opacity(0.78))
                Text(title.uppercased())
                    .font(LYLLTHTheme.label(17, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 38)

            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.metadata)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -5)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 15)
        .padding(.horizontal, 16)
    }
}

struct LYNightshapeMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(LYLLTHTheme.lineStrong.opacity(0.9))
            .frame(height: 1)
            .padding(.horizontal, 15)
    }
}

struct LYNightshapeMenuRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var accent = LYLLTHTheme.teal
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Rectangle().fill(LYLLTHTheme.deck)
                    Rectangle().stroke(accent.opacity(isSelected ? 0.88 : 0.42), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.96))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(LYLLTHTheme.label(11, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(LYLLTHTheme.text)
                    if let detail {
                        Text(detail.uppercased())
                            .font(LYLLTHTheme.label(7.5))
                            .tracking(0.7)
                            .foregroundStyle(LYLLTHTheme.dim)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    LYLED(color: accent, size: 5)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LYLLTHTheme.dim)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: detail == nil ? 48 : 54)
            .background(isSelected ? accent.opacity(0.07) : LYLLTHTheme.panelRaised)
            .overlay(alignment: .leading) {
                Rectangle().fill(accent.opacity(isSelected ? 0.9 : 0.58)).frame(width: 2)
            }
            .overlay { Rectangle().stroke(LYLLTHTheme.lineStrong.opacity(0.92), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LYNightshapeMenuChrome: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(LYLLTHTheme.panel)
            .overlay { Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1) }
            .overlay(alignment: .top) { Rectangle().fill(accent.opacity(0.72)).frame(height: 1) }
            .shadow(color: Color.black.opacity(0.48), radius: 9, x: 0, y: 3)
    }
}

extension View {
    func lyNightshapeMenuChrome(accent: Color = LYLLTHTheme.teal) -> some View {
        modifier(LYNightshapeMenuChrome(accent: accent))
    }
}
