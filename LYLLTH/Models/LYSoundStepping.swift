import Foundation
import NightshapeAudioEngine

/// Previous / next sound for a track, within the kind of sound it has now:
/// a kick steps through kicks, a LUNATK pad through pads. What the ‹ › on a
/// track and ⌘[ / ⌘] do.
enum LYSoundStepping {
    /// The drum sound `step` places from the track's, wrapping round its
    /// category. Your own sounds of that kind come first, then the library.
    static func drum(from track: LYTrack, step: Int, userPresets: [DrumSynthPreset] = LYDrumUserPresets.all()) -> DrumSynthPreset? {
        guard let current = LYDrumSounds.preset(for: track) else { return nil }
        let library = LYDrumSounds.grouped.first { $0.0 == current.category }?.1 ?? []
        let list = userPresets.filter { $0.category == current.category } + library
        guard !list.isEmpty else { return nil }
        // An edited copy steps from the sound it was made from.
        let baseID = current.id.components(separatedBy: "_edit_").first ?? current.id
        let index = list.firstIndex { $0.id == current.id } ?? list.firstIndex { $0.id == baseID } ?? -1
        let next = ((index + step) % list.count + list.count) % list.count
        return list[index < 0 && step < 0 ? list.count - 1 : next]
    }

    /// The LUNATK patch `step` places from `patch`, within its category;
    /// your own patches step among your own.
    static func synth(from patch: LYSynthPatch, step: Int, userPatches: [LYSynthPatch]) -> LYSynthPatch? {
        let list: [LYSynthPatch]
        if userPatches.contains(where: { $0.name == patch.name }) {
            list = userPatches
        } else if let category = LYSynthPatch.factory.first(where: { $0.name == patch.name })?.category {
            list = LYSynthPatch.factory.filter { $0.category == category }
        } else {
            list = LYSynthPatch.factory
        }
        guard !list.isEmpty else { return nil }
        let index = list.firstIndex { $0.name == patch.name } ?? -1
        return list[((index + step) % list.count + list.count) % list.count]
    }
}
