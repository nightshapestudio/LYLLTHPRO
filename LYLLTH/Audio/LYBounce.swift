import AppKit
import Foundation
import NightshapeAudioEngine

/// Bounces the song to a 24-bit WAV by playing it once, from bar 1 to the
/// end of the last region, and recording the main mix. Real time, so what is
/// written is exactly what plays: every track, LYLLTH SYNTH, audio events,
/// all FX, MAIN. A tail after the last bar keeps reverbs and releases.
@MainActor
final class LYBounce: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(elapsed: Double, total: Double)
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var timer: Timer?
    private var startedAt = Date()
    private var restore: (() -> Void)?
    static let tailSeconds = 3.0

    func start(url: URL, songSeconds: Double, audio: AudioEngineController, prepare: () -> Void, restore: @escaping () -> Void) {
        guard case .idle = phase else { return }
        audio.stop()
        prepare()
        self.restore = restore
        do {
            try audio.engine.beginOutputCapture(to: url, format: .wav)
        } catch {
            restore()
            phase = .failed(error.localizedDescription.uppercased())
            return
        }
        audio.togglePlayback()
        startedAt = Date()
        let total = songSeconds + Self.tailSeconds
        phase = .running(elapsed: 0, total: total)
        var transportStopped = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self, weak audio] _ in
            MainActor.assumeIsolated {
                guard let self, let audio else { return }
                let elapsed = Date().timeIntervalSince(self.startedAt)
                self.phase = .running(elapsed: min(elapsed, total), total: total)
                // Stop the transport at the end of the song so it does not
                // come round again, then keep recording the tail.
                if !transportStopped && elapsed >= songSeconds + 0.05 {
                    transportStopped = true
                    audio.stopTransportKeepingTails()
                }
                if elapsed >= total + 0.05 { self.finish(url: url, audio: audio) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel(audio: AudioEngineController) {
        timer?.invalidate()
        timer = nil
        audio.engine.cancelOutputCapture()
        audio.stop()
        restore?()
        restore = nil
        phase = .idle
    }

    func dismiss() { phase = .idle }

    private func finish(url: URL, audio: AudioEngineController) {
        timer?.invalidate()
        timer = nil
        audio.engine.endOutputCapture { [weak self] result in
            guard let self else { return }
            audio.stop()
            self.restore?()
            self.restore = nil
            switch result {
            case .success: self.phase = .finished(url)
            case .failure(let error): self.phase = .failed(error.localizedDescription.uppercased())
            }
        }
    }
}
