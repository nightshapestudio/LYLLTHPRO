import AVFoundation
import Foundation
import NightshapeAudioEngine

/// One recorded MIDI note, placed on the transport clock.
struct LYRecordedNote {
    var note: Int
    var velocity: Int
    /// Transport beats (quarter notes) since the transport started.
    var onBeat: Double
    var offBeat: Double?
}

/// RECORD: an optional four-beat count-in, then the transport runs while MIDI
/// from the keyboard and audio from the input are captured. Stopping hands
/// both back to the workspace to write into the song.
@MainActor
final class LYRecorder: ObservableObject {
    enum Phase: Equatable { case idle, countingIn(beatsLeft: Int), recording }

    @Published private(set) var phase: Phase = .idle
    private(set) var notes: [LYRecordedNote] = []
    private var anchor: NightshapeAudioEngine.TransportAnchor?
    private var countInTimer: Timer?
    private var recordingAudio = false
    private var transportStartHost: UInt64 = 0

    var isActive: Bool { phase != .idle }

    /// - Parameters:
    ///   - countIn: four clicks before the downbeat.
    ///   - recordAudio: capture the input for armed audio tracks.
    func start(audio: AudioEngineController, bpm: Double, countIn: Bool, recordAudio: Bool, onError: @escaping (String) -> Void) {
        guard phase == .idle else { return }
        notes = []
        anchor = nil
        audio.stop()
        let engine = audio.engine
        let beat = 60 / max(bpm, 1)
        let lead = AVAudioTime.hostTime(forSeconds: 0.12)
        let countStart = mach_absolute_time() + lead
        transportStartHost = countIn ? countStart + AVAudioTime.hostTime(forSeconds: beat * 4) : countStart

        LYMIDIInput.shared.recordHandler = { [weak self] status, data1, data2, host in
            Task { @MainActor in self?.capture(status: status, data1: data1, data2: data2, host: host) }
        }

        recordingAudio = false
        if recordAudio {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LYLLTH-Recording-\(UUID().uuidString).caf")
                try engine.beginInputRecording(to: url)
                recordingAudio = true
            } catch {
                onError("AUDIO INPUT: " + error.localizedDescription.uppercased())
            }
        }

        if countIn {
            engine.scheduleCountIn(beats: 4, beatDuration: beat, startHostTime: countStart)
            phase = .countingIn(beatsLeft: 4)
            var remaining = 4
            let timer = Timer(timeInterval: beat, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    remaining -= 1
                    if remaining <= 0 {
                        timer.invalidate()
                        self?.phase = .recording
                    } else {
                        self?.phase = .countingIn(beatsLeft: remaining)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            countInTimer = timer
        } else {
            phase = .recording
        }
        engine.startTransport(atHostTime: transportStartHost)
    }

    /// Stops recording and the transport. `finish` receives the notes and,
    /// if audio was recorded, its file and the transport beat it starts on.
    func stop(audio: AudioEngineController, finish: @escaping ([LYRecordedNote], (url: URL, startBeat: Double)?) -> Void) {
        guard phase != .idle else { return }
        countInTimer?.invalidate()
        countInTimer = nil
        LYMIDIInput.shared.recordHandler = nil
        let anchor = anchor ?? audio.engine.transportAnchor()
        let stopBeat = anchor.map { beat(at: mach_absolute_time(), anchor: $0) } ?? 0
        // Close any held notes where the recording stopped.
        let captured = notes.map { note -> LYRecordedNote in
            var closed = note
            if closed.offBeat == nil { closed.offBeat = max(stopBeat, note.onBeat + 0.25) }
            return closed
        }
        audio.stop()
        phase = .idle
        guard recordingAudio else { finish(captured, nil); return }
        recordingAudio = false
        audio.engine.endInputRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let take):
                let startBeat = anchor.map { self.beat(at: take.firstSampleHostTime, anchor: $0) } ?? 0
                finish(captured, (take.url, max(0, startBeat)))
            case .failure:
                finish(captured, nil)
            }
        }
    }

    // MARK: MIDI

    private func capture(status: UInt8, data1: UInt8, data2: UInt8, host: UInt64) {
        guard phase != .idle else { return }
        if anchor == nil { anchor = AudioEngineControllerAnchor.current() }
        guard let anchor else { return }
        let at = beat(at: host == 0 ? mach_absolute_time() : host, anchor: anchor)
        // A note a little early for the downbeat still belongs to it.
        guard at > -0.125 else { return }
        let kind = status & 0xF0
        if kind == 0x90 && data2 > 0 {
            notes.append(LYRecordedNote(note: Int(data1), velocity: Int(data2), onBeat: max(0, at), offBeat: nil))
        } else if kind == 0x80 || (kind == 0x90 && data2 == 0) {
            if let index = notes.lastIndex(where: { $0.note == Int(data1) && $0.offBeat == nil }) {
                notes[index].offBeat = max(at, notes[index].onBeat + 0.05)
            }
        }
    }

    private func beat(at host: UInt64, anchor: NightshapeAudioEngine.TransportAnchor) -> Double {
        let seconds = host >= anchor.epochHostTime
            ? AVAudioTime.seconds(forHostTime: host - anchor.epochHostTime)
            : -AVAudioTime.seconds(forHostTime: anchor.epochHostTime - host)
        return seconds / anchor.stepDuration * lyBeatsPerStep
    }
}

/// The transport anchor, read on demand so notes played before the first
/// scheduler tick still find it.
enum AudioEngineControllerAnchor {
    static func current() -> NightshapeAudioEngine.TransportAnchor? {
        NightshapeAudioEngine.shared.transportAnchor()
    }
}
