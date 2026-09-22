import Combine
import Foundation
import NightshapeAudioEngine

@MainActor
final class AudioEngineController: ObservableObject {
    let engine = NightshapeAudioEngine.shared

    @Published private(set) var isPlaying = false
    @Published private(set) var currentStep = 0
    @Published private(set) var timecode = "00:00:00"
    @Published private(set) var startupError: String?

    private var cancellables = Set<AnyCancellable>()
    private var configuredSessionID: UUID?

    init() {
        engine.state.$isPlaying
            .removeDuplicates()
            .assign(to: &$isPlaying)
        engine.state.$currentStep
            .removeDuplicates()
            .assign(to: &$currentStep)
        engine.state.$timecodeText
            .removeDuplicates()
            .assign(to: &$timecode)
    }

    func prepare(_ session: LYLLTHSession) {
        if !engine.isReady {
            do {
                try engine.start()
                startupError = nil
            } catch {
                startupError = error.localizedDescription
            }
        }

        engine.setBPM(session.bpm)
        guard configuredSessionID != session.id else { return }
        configuredSessionID = session.id
        installStarterVoices(from: session)
    }

    func updateTempo(_ bpm: Double) {
        engine.setBPM(bpm)
    }

    func togglePlayback() {
        guard engine.isReady else { return }
        engine.toggleTransport()
    }

    func stop() {
        engine.stopTransport()
    }

    private func installStarterVoices(from session: LYLLTHSession) {
        engine.setPatternLength(16)

        let musicalTracks = session.tracks.filter { $0.kind == .drumkit || $0.kind == .instrument }
        for (trackIndex, track) in musicalTracks.prefix(2).enumerated() {
            let preset: SynthPreset = track.kind == .drumkit ? .deepMono : .junoDream
            let rootNote: UInt8 = track.kind == .drumkit ? 36 : 48
            engine.setTrackSynth(trackIndex: trackIndex, rootNote: rootNote, preset: preset)

            let sourceSteps = track.clips.first?.steps ?? []
            let steps = (0..<16).map { sourceSteps.indices.contains($0) && sourceSteps[$0] }
            engine.setPattern(trackIndex: trackIndex, steps: steps)
            engine.setStepParameters(
                trackIndex: trackIndex,
                velocities: Array(repeating: trackIndex == 0 ? 0.9 : 0.68, count: 16),
                volumes: Array(repeating: 0.82, count: 16),
                cutoffs: Array(repeating: trackIndex == 0 ? 0.54 : 0.7, count: 16),
                resonances: Array(repeating: 0.18, count: 16),
                effects: Array(repeating: 0, count: 16),
                pitches: Array(repeating: 0, count: 16),
                noteLengths: Array(repeating: trackIndex == 0 ? 1 : 4, count: 16)
            )
            engine.setTrackVolume(trackIndex: trackIndex, volume: track.volumeDB)
            engine.setTrackPan(trackIndex: trackIndex, pan: track.pan)
        }
    }
}
