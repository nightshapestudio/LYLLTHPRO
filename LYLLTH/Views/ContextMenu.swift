import AppKit
import SwiftUI

// NIGHTSHAPE right-click menus. Never an AppKit or SwiftUI system menu:
// the menu is drawn here, in the app's own chrome, and placed at the cursor.

/// One line in a right-click menu.
struct LYMenuEntry: Identifiable {
    enum Kind {
        case action(() -> Void)
        case submenu([LYMenuEntry])
        case section
        case divider
    }

    var id: String
    var title: String
    var icon: String? = nil
    /// Key hint shown on the right, e.g. "⌘D" or "S".
    var shortcut: String? = nil
    var isEnabled = true
    /// A toggle that is currently on shows a lit dot.
    var isOn: Bool? = nil
    /// Delete and the like, in the record pink.
    var isDestructive = false
    var kind: Kind

    static func action(_ title: String, icon: String? = nil, shortcut: String? = nil, enabled: Bool = true,
                       on: Bool? = nil, destructive: Bool = false, _ run: @escaping () -> Void) -> LYMenuEntry {
        LYMenuEntry(id: title, title: title, icon: icon, shortcut: shortcut, isEnabled: enabled, isOn: on,
                    isDestructive: destructive, kind: .action(run))
    }

    static func submenu(_ title: String, icon: String? = nil, enabled: Bool = true, _ entries: [LYMenuEntry]) -> LYMenuEntry {
        LYMenuEntry(id: title, title: title, icon: icon, isEnabled: enabled, kind: .submenu(entries))
    }

    static func section(_ title: String) -> LYMenuEntry {
        LYMenuEntry(id: "section." + title, title: title, kind: .section)
    }

    static func divider(_ id: String) -> LYMenuEntry {
        LYMenuEntry(id: "divider." + id, title: "", kind: .divider)
    }

    var height: CGFloat {
        switch kind {
        case .section: return 22
        case .divider: return 9
        default: return 28
        }
    }
}

/// The menu: a header naming what was clicked, then its entries. Submenus
/// open beside their row on hover.
struct LYContextMenuView: View {
    let title: String
    var subtitle: String? = nil
    let accent: Color
    let entries: [LYMenuEntry]
    let close: () -> Void
    /// A submenu to show open at first.
    var initialSubmenu: String? = nil

    @State private var hovered: String?
    @State private var openSubmenu: String?
    @State private var submenuHovered: String?

    private let width: CGFloat = 236
    private let submenuWidth: CGFloat = 196
    private let headerHeight: CGFloat = 46

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            column(width: width) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(LYLLTHTheme.label(10.5, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle.uppercased())
                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: headerHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { LYHairline() }
                VStack(spacing: 0) {
                    ForEach(entries) { entry in row(entry, inSubmenu: false) }
                }
                .padding(.vertical, 4)
            }
            if let openSubmenu, let entry = entries.first(where: { $0.id == openSubmenu }), case .submenu(let children) = entry.kind {
                column(width: submenuWidth) {
                    VStack(spacing: 0) {
                        ForEach(children) { child in row(child, inSubmenu: true) }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.top, submenuOffset(for: openSubmenu))
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(LYLLTHTheme.snap, value: openSubmenu)
        .onExitCommand(perform: close)
        .onAppear { if let initialSubmenu { openSubmenu = initialSubmenu } }
    }

    /// Lines the submenu up with the row that opened it.
    private func submenuOffset(for id: String) -> CGFloat {
        var y = headerHeight + 4
        for entry in entries {
            if entry.id == id { return max(0, y - 4) }
            y += entry.height
        }
        return 0
    }

    @ViewBuilder
    private func row(_ entry: LYMenuEntry, inSubmenu: Bool) -> some View {
        switch entry.kind {
        case .section:
            Text(entry.title)
                .font(LYLLTHTheme.label(7, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(LYLLTHTheme.dim)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: entry.height, alignment: .bottomLeading)
                .padding(.bottom, 2)
        case .divider:
            Rectangle().fill(LYLLTHTheme.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
        case .action(let run):
            itemButton(entry, inSubmenu: inSubmenu) {
                run()
                close()
            }
        case .submenu:
            itemButton(entry, inSubmenu: inSubmenu) { openSubmenu = entry.id }
        }
    }

    private func itemButton(_ entry: LYMenuEntry, inSubmenu: Bool, action: @escaping () -> Void) -> some View {
        let key = (inSubmenu ? "sub." : "") + entry.id
        let isHovered = (inSubmenu ? submenuHovered : hovered) == key
        let isOpen = !inSubmenu && openSubmenu == entry.id
        let lit = entry.isEnabled && (isHovered || isOpen)
        let tint = entry.isDestructive ? LYLLTHTheme.record : accent
        return Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if let icon = entry.icon {
                        Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 14)
                .foregroundStyle(lit ? tint : LYLLTHTheme.dim)
                Text(entry.title)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(entry.isDestructive ? LYLLTHTheme.record : (lit ? LYLLTHTheme.text : LYLLTHTheme.secondary))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let isOn = entry.isOn {
                    Circle()
                        .fill(isOn ? tint : Color.clear)
                        .overlay(Circle().stroke(isOn ? tint : LYLLTHTheme.lineStrong, lineWidth: 1))
                        .frame(width: 6, height: 6)
                        .shadow(color: isOn ? tint.opacity(0.8) : .clear, radius: 4)
                }
                if let shortcut = entry.shortcut {
                    mixedNumericLabel(shortcut, labelFont: LYLLTHTheme.label(8, weight: .bold), numberFont: LYLLTHTheme.value(9))
                        .foregroundStyle(LYLLTHTheme.dim)
                }
                if case .submenu = entry.kind {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(isOpen ? accent : LYLLTHTheme.dim)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: entry.height)
            .background(lit ? tint.opacity(0.10) : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(lit ? tint : Color.clear).frame(width: 2) }
            .contentShape(Rectangle())
            .opacity(entry.isEnabled ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!entry.isEnabled)
        .onHover { inside in
            if inSubmenu {
                submenuHovered = inside ? key : (submenuHovered == key ? nil : submenuHovered)
            } else {
                hovered = inside ? key : (hovered == key ? nil : hovered)
                guard inside else { return }
                // A submenu opens on hover; any other row closes it.
                if case .submenu = entry.kind, entry.isEnabled { openSubmenu = entry.id } else { openSubmenu = nil }
            }
        }
    }

    private func column<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(width: width, alignment: .leading)
            .lyNightshapeMenuChrome(accent: accent)
    }
}

/// Catches a right-click (or control-click) inside the view it backs,
/// reporting the point in that view's own coordinates (top-left origin).
/// Nothing AppKit draws: no system menu appears.
struct LYRightClickArea: NSViewRepresentable {
    let action: (CGPoint) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.action = action
    }

    final class MonitorView: NSView {
        var action: (CGPoint) -> Bool = { _ in false }
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let isSecondary = event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
                guard isSecondary else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point), self.visibleRect.contains(point) else { return event }
                return self.action(point) ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
