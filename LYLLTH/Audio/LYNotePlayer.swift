import AVFoundation
import Foundation
import NightshapeAudioEngine

/// Plays note clips (the piano roll) on their tracks' LUNATK, in time with
/// the NIGHTSHAPE transport. Notes are handed to the synth a little ahead,
/// each stamped with the host time it should sound, so chords, off-grid
/// timing and long notes all play exactly as drawn. A clip dragged longer
/// than its content repeats it.
@MainActor
final class LYNotePlayer {
    private let engine: NightshapeAudioEngine
    /// The LUNATK on a track, if it has one.
    var instrument: (UUID) -> LYSynthInstrument? = { _ in nil }

    private var session: LYLLTHSession?
    private var window: LYSongWindow?
    private var anchor: NightshapeAudioEngine.TransportAnchor?
    private var scheduledThroughBeat = 0.0
    private var ticker: Timer?
    private var touched: Set<UUID> = []
    private static let horizonSeconds = 0.25

    init(engine: NightshapeAudioEngine) {
        self.engine = engine
    }

    func update(session: LYLLTHSession, window: LYSongWindow) {
        let changed = self.window != window || Self.structure(session) != Self.structure(self.session)
        self.session = session
        self.window = window
        if changed, ticker != nil { resync() }
    }

    func start() {
        guard ticker == nil else { return }
        anchor = nil
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        anchor = nil
        silence()
    }

    private func silence() {
        for id in touched { instrument(id)?.allNotesOff() }
        touched = []
    }

    /// Anything already handed over was timed for the old arrangement.
    private func resync() {
        silence()
        guard let anchor else { return }
        let now = mach_absolute_time()
        let elapsed = now > anchor.epochHostTime ? AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime) : 0
        scheduledThroughBeat = (elapsed + 0.01) / anchor.stepDuration * lyBeatsPerStep
    }

    private func tick() {
        guard let latest = engine.transportAnchor() else { return }
        if latest != anchor {
            anchor = latest
            let now = mach_absolute_time()
            let elapsed = now > latest.epochHostTime ? AVAudioTime.seconds(forHostTime: now - latest.epochHostTime) : 0
            scheduledThroughBeat = max(0, (elapsed + 0.005) / latest.stepDuration * lyBeatsPerStep)
            if elapsed <= 0 { scheduledThroughBeat = 0 }
        }
        schedule(latest)
    }

    private func schedule(_ anchor: NightshapeAudioEngine.TransportAnchor) {
        guard let session, let window, window.lengthBeats > 0 else { return }
        let secondsPerBeat = anchor.stepDuration / lyBeatsPerStep
        let clock = LYTimelineClock(
            sampleRate: LYSynthInstrument.sampleRate,
            bpm: 60 / secondsPerBeat,
            startBeat: 0,
            epochHostTime: anchor.epochHostTime
        )
        let now = mach_absolute_time()
        let elapsed = now > anchor.epochHostTime ? AVAudioTime.seconds(forHostTime: now - anchor.epochHostTime) : 0
        let horizon = (elapsed + Self.horizonSeconds) / secondsPerBeat
        guard horizon > scheduledThroughBeat else { return }
        let from = scheduledThroughBeat
        let firstPass = Int(floor(from / window.lengthBeats))
        let lastPass = Int(floor(horizon / window.lengthBeats))
        for track in session.tracks where track.clips.contains(where: \.isNoteClip) {
            guard let synth = instrument(track.id) else { continue }
            for clip in track.clips where clip.isNoteClip && clip.isInSong && !clip.isMuted {
                for pass in firstPass...lastPass {
                    let passStart = Double(pass) * window.lengthBeats
                    // Song beats covered by this pass and this scheduling slice.
                    let sliceStart = max(from - passStart, 0) + window.startBeat
                    let sliceEnd = min(horizon - passStart, window.lengthBeats) + window.startBeat
                    for note in clip.songNotes(from: sliceStart, to: sliceEnd) {
                        let noteEnd = min(note.beat + note.length, window.endBeat)
                        let onBeat = passStart + (note.beat - window.startBeat)
                        let offBeat = passStart + (noteEnd - window.startBeat)
                        let pitch = UInt8(min(max(note.pitch, 0), 127))
                        let noteChannel = UInt8(min(max(
                            note.expression?.first?.channel ?? track.midiRouting?.outputChannel ?? 0,
                            0
                        ), 15))
                        let usesChannelVoice = track.midiRouting?.usesMPE == true || noteChannel != 0 || note.expression?.isEmpty == false
                        if usesChannelVoice {
                            synth.midi(
                                status: 0x90 | noteChannel,
                                data1: pitch,
                                data2: UInt8(min(max(note.velocity, 1), 127)),
                                atHostTime: clock.hostTime(atBeat: onBeat)
                            )
                            for point in note.expression ?? [] {
                                let eventBeat = onBeat + min(max(point.offset, 0), note.length)
                                let message = Self.message(for: point, fallbackChannel: noteChannel)
                                synth.midi(
                                    status: message.status,
                                    data1: message.data1,
                                    data2: message.data2,
                                    atHostTime: clock.hostTime(atBeat: eventBeat)
                                )
                            }
                            synth.midi(
                                status: 0x80 | noteChannel,
                                data1: pitch,
                                data2: 0,
                                atHostTime: clock.hostTime(atBeat: max(offBeat - 0.001, onBeat + 0.01))
                            )
                        } else {
                            synth.noteOn(pitch, velocity: UInt8(min(max(note.velocity, 1), 127)), atHostTime: clock.hostTime(atBeat: onBeat), cutoff: 1, resonance: 0)
                            synth.noteOff(pitch, atHostTime: clock.hostTime(atBeat: max(offBeat - 0.001, onBeat + 0.01)))
                        }
                        touched.insert(track.id)
                    }
                }
            }
        }
        scheduledThroughBeat = horizon
    }

    nonisolated static func message(for point: LYMIDIExpressionPoint, fallbackChannel: UInt8 = 0) -> (status: UInt8, data1: UInt8, data2: UInt8) {
        let channel = UInt8(min(max(point.channel, 0), 15))
        let resolved = point.channel == 0 ? fallbackChannel : channel
        let unit = UInt8(min(max(Int((min(max(point.value, 0), 1) * 127).rounded()), 0), 127))
        switch point.kind {
        case .pitchBend:
            let bend = min(max(Int(((min(max(point.value, -1), 1) + 1) * 8_191.5).rounded()), 0), 16_383)
            return (0xE0 | resolved, UInt8(bend & 0x7F), UInt8((bend >> 7) & 0x7F))
        case .pressure:
            return (0xD0 | resolved, unit, 0)
        case .timbre:
            return (0xB0 | resolved, 74, unit)
        case .modulation:
            return (0xB0 | resolved, 1, unit)
        case .sustain:
            return (0xB0 | resolved, 64, unit)
        case .controlChange:
            return (0xB0 | resolved, UInt8(min(max(point.controller ?? 0, 0), 127)), unit)
        }
    }

    private static func structure(_ session: LYLLTHSession?) -> [String] {
        guard let session else { return [] }
        return session.tracks.flatMap { track in
            track.clips.filter(\.isNoteClip).map { clip in
                "\(track.id)|\(clip.id)|\(clip.startBeat)|\(clip.lengthBeats)|\(clip.noteCycleBeats)|\(clip.loopOffsetBeats)|\(clip.isMuted)|\(clip.notes?.hashValue ?? 0)"
            }
        } + ["\(session.bpm)"]
    }
}
