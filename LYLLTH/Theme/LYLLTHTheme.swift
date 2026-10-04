import SwiftUI

enum LYLLTHTheme {
    static let background = Color(hex: 0x0C0C0E)
    static let deck = Color(hex: 0x09090C)
    static let panel = Color(hex: 0x0F0F13)
    static let panelRaised = Color(hex: 0x141418)
    static let panelPressed = Color(hex: 0x18181E)

    static var line: Color { Color.white.opacity(LYAppPreferences.highContrast() ? 0.16 : 0.085) }
    static var lineStrong: Color { Color(hex: LYAppPreferences.highContrast() ? 0x555568 : 0x343440) }
    static var lineFocused: Color { Color(hex: LYAppPreferences.highContrast() ? 0x77798E : 0x57586A) }

    // Text has two tiers on the dark ground and nothing dimmer, same as
    // DrumKit: near-white for anything read, #888899 for the quiet tier.
    // `secondary` is the heading register only. Dimming is not a hierarchy
    // tool here; size, weight, tracking and placement are.
    static let text = Color(hex: 0xEEEEFF)
    static var secondary: Color { Color(hex: LYAppPreferences.highContrast() ? 0xD2D4E1 : 0xB6B8C6) }
    static var metadata: Color { Color(hex: LYAppPreferences.highContrast() ? 0xB6B8C6 : 0x888899) }
    static var dim: Color { metadata }
    /// OFF chrome: unlit LEDs, empty meter wells. Never text.
    static let off = Color(hex: 0x3A3A48)
    static let chrome = Color(hex: 0xDCE6FA)
    /// DrumKit's control-chrome white at its text opacity, the ceiling for
    /// light UI. Transport glyphs and M/S labels use it.
    static let chromeText = Color(hex: 0xDCE6FA).opacity(0.86)
    /// Fill behind a lit control. Faint on purpose: outline and bloom say
    /// "live", the fill only warms the cell.
    static let controlFill: Double = 0.055
    static let playhead = Color.white.opacity(0.92)

    static let teal = Color(hex: 0x33CCCC)
    static let indigo = Color(hex: 0x6666FF)
    static let purple = Color(hex: 0x9933FF)
    static let lavender = Color(hex: 0xBBA6FD)
    /// Record arm. The one colour outside the three accents: a cool, near-neon
    /// red-pink that leans toward purple so it sits with the palette instead
    /// of reading as a warning light.
    static let record = Color(hex: 0xFF3380)

    /// DrumKit's fixed track rhythm: two teal, two indigo, two purple,
    /// repeating. Position only; never derived from what a track holds.
    static func trackAccent(position: Int) -> Color {
        switch (max(position, 0) % 6) / 2 {
        case 0: return teal
        case 1: return indigo
        default: return purple
        }
    }

    // The app's three springs, shared with DrumKit so both move alike.
    static let snap = Animation.spring(response: 0.22, dampingFraction: 0.62)
    static let settle = Animation.spring(response: 0.35, dampingFraction: 0.78)
    static let glide = Animation.spring(response: 0.45, dampingFraction: 0.82)

    static func accent(_ token: LYAccent) -> Color {
        switch token {
        case .teal: return teal
        case .indigo: return indigo
        case .purple: return purple
        }
    }

    // MARK: Type scale
    //
    // Labels: three sizes only. 9 is the floor (S, metadata and sub-labels),
    // 10 is M (names, parameters), 11 is L (section headers, commands).
    // Anything asked for at 12 or more is a display size and passes through.
    // Call sites keep the size they always asked for; it snaps here, so the
    // hierarchy between them survives while the 6.5-8.5 sizes go away.
    static let labelS: CGFloat = 9
    static let labelM: CGFloat = 10
    static let labelL: CGFloat = 11

    static func scaledLabelSize(_ requested: CGFloat) -> CGFloat {
        switch requested {
        case ..<9.25: return labelS
        case ..<10.25: return labelM
        case ..<12: return labelL
        default: return requested
        }
    }

    // Values: 10 (S), 12 (M), 13 below display size; 15 and up pass through.
    static func scaledValueSize(_ requested: CGFloat) -> CGFloat {
        switch requested {
        case ..<11: return 10
        case ..<13: return 12
        case ..<15: return 13
        default: return requested
        }
    }

    static func label(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font {
        let size = scaledLabelSize(size) * LYAppPreferences.textScale()
        switch weight {
        case .ultraLight, .thin, .light:
            return .custom("Adam-Light", size: size)
        case .semibold, .bold, .heavy, .black:
            return .custom("Adam-Bold", size: size)
        default:
            return .custom("Adam-Medium", size: size)
        }
    }

    /// Reading text: sentences in Help and anywhere prose runs longer than a
    /// label. Adam is the display face for short uppercase labels; in long
    /// lowercase lines its rounded letters read as a novelty face.
    ///
    /// SF Pro, the system face. It is the same family as `value`, so prose and
    /// readouts share one supporting face; it ships with macOS, so nothing is
    /// bundled; and the system applies its own optical sizing and tracking at
    /// each point size, which a bundled face cannot do.
    static func body(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        let size = size * LYAppPreferences.textScale()
        switch weight {
        case .medium:
            return .system(size: size, weight: .medium, design: .default)
        case .semibold, .bold, .heavy, .black:
            return .system(size: size, weight: .semibold, design: .default)
        default:
            return .system(size: size, weight: .regular, design: .default)
        }
    }

    /// The single numeric-readout face used across NIGHTSHAPE products.
    /// Labels stay in Adam; reported values use the quiet, thin SF display cut
    /// with fixed-width figures so changing values never shift laterally.
    static func value(_ size: CGFloat = 12) -> Font {
        let size = scaledValueSize(size)
        // Thin holds its strokes only at display size; below 18 it breaks up,
        // so small readouts use the regular cut of the same face.
        let weight: Font.Weight = size >= 18 ? .thin : .regular
        return .system(size: size * LYAppPreferences.textScale(), weight: weight, design: .default).monospacedDigit()
    }

    static func wordmark(_ size: CGFloat) -> Font {
        .custom("NIGHTSHAPE-Bold", size: size)
    }

    static func wordmarkOutline(_ size: CGFloat) -> Font {
        .custom("NIGHTSHAPEOutline-Bold", size: size)
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

extension View {
    /// Same-colour bloom that lifts indigo and purple to read as loud as teal.
    /// Teal is already the loudest accent and is never bloomed.
    func lyBloom(_ color: Color, isOn: Bool = true, strength: Double = 1) -> some View {
        let applies = isOn && color != LYLLTHTheme.teal
        return self
            .shadow(color: applies ? color.opacity(0.9 * strength) : .clear, radius: applies ? 2.5 * strength : 0)
            .shadow(color: applies ? color.opacity(0.5 * strength) : .clear, radius: applies ? 5 * strength : 0)
    }

    /// DrumKit's selected-state light: a single-colour bloom rising from the
    /// bottom edge. Vertical and one hue; never a horizontal ramp.
    func lyRisingBloom(_ color: Color, isOn: Bool, strength: Double = 1) -> some View {
        background {
            if isOn {
                LinearGradient(
                    colors: [color.opacity(0.03 * strength), color.opacity(0.20 * strength)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
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

/// Where each menu-opening control sits in the workspace, so its menu can
/// drop down from it instead of appearing in the middle of the window.
struct LYMenuAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Marks this control as the place menu `id` drops down from, measured
    /// in `space` (the workspace unless a window has its own).
    func lyMenuAnchor(_ id: String, in space: String = LYDropdownOverlay<EmptyView>.space) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: LYMenuAnchorKey.self, value: [id: proxy.frame(in: .named(space))])
            }
        }
    }
}

/// Which floating window is in front. Opening a window or clicking anywhere
/// in one raises it, the way macOS windows behave; the workspace gives each
/// window's layer the z-index this hands out. Every window sits between
/// `base` and `menus`, so a menu or picker always opens above all of them.
@MainActor
final class LYWindowStack: ObservableObject {
    /// Back to front.
    @Published private(set) var order: [String] = []

    static let base: Double = 170
    /// Where menus, pickers and dropdowns sit: above every window.
    static let menus: Double = 240

    func raise(_ layer: String) {
        guard order.last != layer else { return }
        order.removeAll { $0 == layer }
        order.append(layer)
    }

    func zIndex(_ layer: String) -> Double {
        guard let index = order.firstIndex(of: layer) else { return Self.base }
        return Self.base + 1 + Double(index)
    }
}

private struct LYWindowStackKey: EnvironmentKey {
    static let defaultValue: LYWindowStack? = nil
}

extension EnvironmentValues {
    var lyWindowStack: LYWindowStack? {
        get { self[LYWindowStackKey.self] }
        set { self[LYWindowStackKey.self] = newValue }
    }
}

/// A window that floats over the workspace and can be dragged by its title
/// bar, like a Logic plug-in window. It remembers where it was left, per
/// kind of window, and never lets its bar go fully off screen.
struct LYFloatingWindow<Content: View>: View {
    let title: String
    let accent: Color
    let size: CGSize
    var scale: CGFloat = 1
    /// Its layer in the workspace's LYWindowStack.
    let layer: String
    let close: () -> Void
    let content: Content
    @Environment(\.lyWindowStack) private var stack
    @AppStorage private var storedX: Double
    @AppStorage private var storedY: Double
    @State private var drag: CGSize = .zero

    init(id: String, title: String, accent: Color, size: CGSize, scale: CGFloat = 1, layer: String? = nil,
         close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.layer = layer ?? id
        self.title = title
        self.accent = accent
        self.size = size
        self.scale = scale
        self.close = close
        self.content = content()
        _storedX = AppStorage(wrappedValue: 0, "lyllth.window.\(id).x")
        _storedY = AppStorage(wrappedValue: 0, "lyllth.window.\(id).y")
    }

    /// 34 pt: 11 pt clear above and below the 12 pt window buttons and the
    /// title (was 22, then 28, which still read tight under the frame).
    private static var barHeight: CGFloat { 34 }

    var body: some View {
        GeometryReader { geo in
            let width = size.width * scale
            let height = size.height * scale + Self.barHeight
            let window = CGSize(width: width, height: height)
            let resting = clamped(CGSize(width: storedX, height: storedY), window: window, in: geo.size)
            // While dragging, only an offset changes: the window moves as a
            // finished image and its contents are not laid out again.
            let live = clamped(CGSize(width: resting.width + drag.width, height: resting.height + drag.height), window: window, in: geo.size)
            VStack(spacing: 0) {
                titleBar
                    .frame(width: width, height: Self.barHeight)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag = $0.translation }
                            .onEnded { value in
                                let final = clamped(CGSize(width: resting.width + value.translation.width, height: resting.height + value.translation.height),
                                                    window: window, in: geo.size)
                                storedX = final.width
                                storedY = final.height
                                drag = .zero
                            }
                    )
                content
                    // This window glows; what it holds does not glow again.
                    .environment(\.nightshapeWindowGlowSuppressed, true)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .frame(width: width, height: size.height * scale)
            }
            // A thin purple frame around the whole window, title bar included.
            // The black shade outside makes the window's edge the darkest
            // thing on screen, so without a line of its own the edge blurs
            // into the shadow; this keeps it crisp.
            .overlay(Rectangle().strokeBorder(LYLLTHTheme.purple.opacity(0.7), lineWidth: 1))
            // Shadows from plain rectangles behind the window. A shadow on the
            // stack itself gives every control inside its own blurred shadow,
            // redrawn on every frame of a drag. The purple halo keeps the
            // window's edge from sinking into the black behind it.
            .nightshapeWindowGlow()
            // Any press in the window brings it to the front, without taking
            // the press from the control under it.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in stack?.raise(layer) })
            .position(x: geo.size.width / 2 + resting.width, y: geo.size.height / 2 + resting.height)
            .offset(x: live.width - resting.width, y: live.height - resting.height)
        }
        // A window opens in front, and so does one reopened with new contents.
        .onAppear { stack?.raise(layer) }
        .onChange(of: title) { _, _ in stack?.raise(layer) }
    }

    private var titleBar: some View {
        // Window buttons on the left, the same language as the app's own
        // window: macOS draws them there, so a right-hand X read as Windows.
        HStack(spacing: 14) {
            LYWindowControls(close: close, showsUnavailable: true)
            Rectangle().fill(accent).frame(width: 12, height: 2)
            Text(title)
                .font(LYLLTHTheme.label(8, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(LYLLTHTheme.dim)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 10)
        // The grip stays centred on the bar whatever the title's length.
        .overlay {
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { _ in Circle().fill(LYLLTHTheme.off).frame(width: 2.5, height: 2.5) }
            }
            .allowsHitTesting(false)
        }
        // Fill the whole bar BEFORE painting it. Without this the background
        // and outline wrapped only the 12 pt buttons and the bar height was
        // invisible padding outside them, which is what looked cramped.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0B0C10))
        // Only a divider under the bar. The window's purple frame is the top
        // and side edge; a second outline here doubled the top line and made
        // the space above the buttons read smaller than the space below.
        .overlay(alignment: .bottom) {
            Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { inside in if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        .help("Drag to move")
    }

    /// Keeps at least 120 pt of the title bar inside the workspace.
    private func clamped(_ offset: CGSize, window: CGSize, in area: CGSize) -> CGSize {
        let maxX = area.width / 2 + window.width / 2 - 120
        let maxY = (area.height - window.height) / 2 + window.height - Self.barHeight
        let minY = -(area.height - window.height) / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, minY), maxY))
    }
}

/// Window buttons for LYLLTH's in-app windows, panels and menus, matched to
/// how the main window's own buttons render in LYLLTH: three flat neutral
/// grey discs (#8C8C8C), 12 pt, 8 pt apart, on the left. No system red /
/// yellow / green. A button with an action shows its glyph while the pointer
/// is over the group; one without an action looks the same at rest and does
/// nothing. `showsUnavailable: false` shows the close button alone.
struct LYWindowControls: View {
    let close: () -> Void
    var minimize: (() -> Void)? = nil
    var zoom: (() -> Void)? = nil
    var showsUnavailable = false
    @State private var hovering = false

    private static let size: CGFloat = 12
    private static let disc = Color(hex: 0x8C8C8C)

    var body: some View {
        HStack(spacing: 8) {
            button(glyph: "xmark", label: "Close", action: close)
            if minimize != nil || showsUnavailable {
                button(glyph: "minus", label: "Minimize", action: minimize)
            }
            if zoom != nil || showsUnavailable {
                button(glyph: "plus", label: "Zoom", action: zoom)
            }
        }
        .onHover { hovering = $0 }
    }

    private func button(glyph: String, label: String, action: (() -> Void)?) -> some View {
        let enabled = action != nil
        return Button { action?() } label: {
            ZStack {
                Circle().fill(Self.disc)
                if enabled && hovering {
                    Image(systemName: glyph)
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that dims the disc, and the main window's buttons
        // are all one grey. An unavailable button just ignores the click.
        .allowsHitTesting(enabled)
        .accessibilityHidden(!enabled)
        .accessibilityLabel(label)
        .help(enabled ? label : "")
    }
}

/// A NIGHTSHAPE dropdown: the panel hangs just under the control that opened
/// it, left-aligned to it and kept inside the window (it opens upward when
/// there is no room below). A click anywhere else closes it. No scrim, so it
/// reads as part of the control rather than a dialog.
struct LYDropdownOverlay<Content: View>: View {
    static var space: String { "LYWorkspace" }

    let anchor: CGRect?
    let dismiss: () -> Void
    let content: Content
    @State private var size: CGSize = .zero

    init(anchor: CGRect?, dismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.dismiss = dismiss
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let frame = anchor ?? CGRect(x: geo.size.width / 2, y: geo.size.height / 3, width: 0, height: 0)
            let x = min(max(8, frame.minX), max(8, geo.size.width - size.width - 8))
            let below = frame.maxY + 6
            let opensUp = below + size.height > geo.size.height - 8 && frame.minY - size.height - 6 > 8
            let y = opensUp ? frame.minY - size.height - 6 : below
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                content
                    .fixedSize()
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { size = proxy.size }
                                .onChange(of: proxy.size) { _, value in size = value }
                        }
                    }
                    .offset(x: x, y: y)
                    .opacity(size == .zero ? 0 : 1)
                    .transition(.scale(scale: 0.96, anchor: opensUp ? .bottomLeading : .topLeading).combined(with: .opacity))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

struct LYNightshapeMenuHeader: View {
    let eyebrow: String
    let title: String
    var accent = LYLLTHTheme.teal
    var close: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                // Top-left, as macOS places a panel's close button.
                LYWindowControls(close: close)
                    .offset(x: -6, y: -8)
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
            // One layer, one shadow: without it every row casts its own.
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.48), radius: 9, x: 0, y: 3)
    }
}

extension View {
    func lyNightshapeMenuChrome(accent: Color = LYLLTHTheme.teal) -> some View {
        modifier(LYNightshapeMenuChrome(accent: accent))
    }
}

/// The three accent tokens a track or panel can carry.
enum LYAccent: String, Codable, CaseIterable {
    case teal
    case indigo
    case purple
}
