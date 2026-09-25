import AppKit
import SwiftUI

/// NIGHTSHAPE's scrollbar: a hairline track and a thin square bar that lights
/// teal while held. Replaces AppKit's rounded pill on every scroll area.
final class LYScroller: NSScroller {
    private var isDragging = false

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        10
    }

    private var isVertical: Bool { bounds.height >= bounds.width }

    override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: bounds, highlight: false)
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor.white.withAlphaComponent(0.05).setFill()
        let line = isVertical
            ? NSRect(x: slotRect.midX - 0.5, y: slotRect.minY, width: 1, height: slotRect.height)
            : NSRect(x: slotRect.minX, y: slotRect.midY - 0.5, width: slotRect.width, height: 1)
        line.fill()
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0 else { return }
        let thickness: CGFloat = isDragging ? 4 : 3
        let bar = isVertical
            ? NSRect(x: knob.midX - thickness / 2, y: knob.minY + 2, width: thickness, height: max(0, knob.height - 4))
            : NSRect(x: knob.minX + 2, y: knob.midY - thickness / 2, width: max(0, knob.width - 4), height: thickness)
        let color = isDragging
            ? NSColor(srgbRed: 0x33 / 255, green: 0xCC / 255, blue: 0xCC / 255, alpha: 1)
            : NSColor(srgbRed: 0x88 / 255, green: 0x88 / 255, blue: 0x99 / 255, alpha: 0.85)
        color.setFill()
        bar.fill()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        needsDisplay = true
        super.mouseDown(with: event)   // runs the drag loop until mouse up
        isDragging = false
        needsDisplay = true
    }
}

/// Finds the NSScrollView behind a SwiftUI ScrollView and gives it
/// NIGHTSHAPE scrollers.
private struct LYScrollerInstaller: NSViewRepresentable {
    final class Coordinator { weak var installedOn: NSScrollView? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { install(from: view, context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Runs on every redraw; only search again if the scroll view changed.
        if let scroll = context.coordinator.installedOn, scroll.verticalScroller is LYScroller { return }
        DispatchQueue.main.async { install(from: view, context.coordinator) }
    }

    private func install(from view: NSView, _ coordinator: Coordinator) {
        guard let scrollView = Self.scrollView(near: view) else { return }
        coordinator.installedOn = scrollView
        #if DEBUG
        if ProcessInfo.processInfo.environment["LYLLTH_DEBUG_SCROLLERS"] != nil { NSLog("LYScroller installed on %@", NSStringFromSize(scrollView.frame.size)) }
        #endif
        if !(scrollView.verticalScroller is LYScroller) { scrollView.verticalScroller = LYScroller() }
        if !(scrollView.horizontalScroller is LYScroller) { scrollView.horizontalScroller = LYScroller() }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
    }

    /// The installer sits in the ScrollView's background, beside its
    /// NSScrollView rather than inside it, so look for the scroll view that
    /// occupies the same rectangle.
    private static func scrollView(near view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView { return enclosing }
        guard view.window != nil else { return nil }
        let target = view.convert(view.bounds, to: nil)
        var node = view.superview
        for _ in 0..<8 {
            guard let current = node else { return nil }
            if let found = search(current, target: target) { return found }
            node = current.superview
        }
        return nil
    }

    private static func search(_ root: NSView, target: NSRect) -> NSScrollView? {
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? NSScrollView {
                let frame = scroll.convert(scroll.bounds, to: nil)
                if abs(frame.minX - target.minX) < 3, abs(frame.minY - target.minY) < 3,
                   abs(frame.width - target.width) < 3, abs(frame.height - target.height) < 3 {
                    return scroll
                }
            }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }
}

extension View {
    /// Put on a ScrollView: its scrollbars become NIGHTSHAPE's.
    func lyScrollers() -> some View {
        background(LYScrollerInstaller())
    }
}
