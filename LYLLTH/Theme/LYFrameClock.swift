import AppKit
import QuartzCore

/// One display-synced tick for everything that polls the engine to draw:
/// meters, the synth's readouts. A Timer drifts against the display and
/// drops or doubles frames, which reads as stutter; this fires exactly once
/// per screen refresh (60 or 120 Hz) on the main thread.
@MainActor
final class LYFrameClock: NSObject {
    static let shared = LYFrameClock()

    private var link: CADisplayLink?
    private var listeners: [UUID: () -> Void] = [:]

    /// Calls `tick` every frame until the returned token is cancelled.
    func add(_ tick: @escaping () -> Void) -> LYFrameToken {
        let id = UUID()
        listeners[id] = tick
        startIfNeeded()
        return LYFrameToken { [weak self] in
            MainActor.assumeIsolated {
                self?.listeners[id] = nil
                if self?.listeners.isEmpty == true { self?.stop() }
            }
        }
    }

    private func startIfNeeded() {
        guard link == nil else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        for tick in listeners.values { tick() }
    }
}

/// Stops the ticks when cancelled or released.
final class LYFrameToken {
    private var cancelAction: (() -> Void)?
    init(_ cancel: @escaping () -> Void) { cancelAction = cancel }
    func cancel() { cancelAction?(); cancelAction = nil }
    deinit { cancelAction?() }
}
