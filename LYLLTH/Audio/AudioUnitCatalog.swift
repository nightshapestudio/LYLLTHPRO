import AudioToolbox
import AVFoundation
import Foundation

struct LYAudioUnitDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let type: OSType
    let subtype: OSType
    let manufacturerCode: OSType
    let isInstrument: Bool
}

@MainActor
final class AudioUnitCatalog: ObservableObject {
    @Published private(set) var instruments: [LYAudioUnitDescriptor] = []
    @Published private(set) var effects: [LYAudioUnitDescriptor] = []
    @Published private(set) var isScanning = false

    func scan() {
        guard !isScanning else { return }
        isScanning = true

        let components = AVAudioUnitComponentManager.shared().components(matching: AudioComponentDescription())
        let mapped = components.compactMap { component -> LYAudioUnitDescriptor? in
            let description = component.audioComponentDescription
            let instrumentTypes: Set<OSType> = [kAudioUnitType_MusicDevice, kAudioUnitType_MusicEffect]
            let effectTypes: Set<OSType> = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect, kAudioUnitType_Panner]
            guard instrumentTypes.contains(description.componentType) || effectTypes.contains(description.componentType) else {
                return nil
            }

            return LYAudioUnitDescriptor(
                id: "\(description.componentType)-\(description.componentSubType)-\(description.componentManufacturer)",
                name: component.name,
                manufacturer: component.manufacturerName,
                type: description.componentType,
                subtype: description.componentSubType,
                manufacturerCode: description.componentManufacturer,
                isInstrument: instrumentTypes.contains(description.componentType)
            )
        }

        instruments = mapped.filter(\.isInstrument).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        effects = mapped.filter { !$0.isInstrument }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isScanning = false
    }
}
