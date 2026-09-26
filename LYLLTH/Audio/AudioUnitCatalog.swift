import AudioToolbox
import AVFoundation
import Foundation
import SwiftUI
import AppKit
import CoreAudioKit
import NightshapeAudioEngine

struct LYAudioUnitDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let type: OSType
    let subtype: OSType
    let manufacturerCode: OSType
    let isInstrument: Bool

    var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: type,
            componentSubType: subtype,
            componentManufacturer: manufacturerCode,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
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
            let instrumentTypes: Set<OSType> = [kAudioUnitType_MusicDevice]
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

private final class LYHostedAudioUnitInstrument: NightshapeTrackInstrument {
    let unit: AVAudioUnit
    var sourceNode: AVAudioNode { unit }

    init(unit: AVAudioUnit) { self.unit = unit }

    func noteOn(_ note: UInt8, velocity: UInt8, atHostTime hostTime: UInt64, cutoff: Float, resonance: Float) {
        send([0x90, note, velocity], atHostTime: hostTime)
    }

    func noteOff(_ note: UInt8, atHostTime hostTime: UInt64) {
        send([0x80, note, 0], atHostTime: hostTime)
    }

    func allNotesOff() { send([0xB0, 123, 0], atHostTime: 0) }

    private func send(_ message: [UInt8], atHostTime hostTime: UInt64) {
        guard let block = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        let eventTime: AUEventSampleTime = {
            guard hostTime != 0,
                  let render = unit.lastRenderTime,
                  render.isHostTimeValid,
                  render.isSampleTimeValid,
                  render.sampleRate > 0 else { return AUEventSampleTimeImmediate }
            let seconds = hostTime >= render.hostTime
                ? AVAudioTime.seconds(forHostTime: hostTime - render.hostTime)
                : -AVAudioTime.seconds(forHostTime: render.hostTime - hostTime)
            return AUEventSampleTime((Double(render.sampleTime) + seconds * render.sampleRate).rounded())
        }()
        message.withUnsafeBytes { bytes in
            guard let address = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            block(eventTime, 0, message.count, address)
        }
    }
}

@MainActor
final class LYAudioUnitHost: ObservableObject {
    @Published private(set) var validationMessage: String?
    @Published var editor: Editor?
    @Published private(set) var stateRevision = 0

    struct Editor: Identifiable {
        var id: UUID
        var title: String
        var controller: NSViewController
    }

    private var units: [UUID: AVAudioUnit] = [:]
    private var instruments: [UUID: LYHostedAudioUnitInstrument] = [:]
    private var observers: [UUID: AUParameterObserverToken] = [:]
    private var stateWork: DispatchWorkItem?

    func install(
        _ descriptor: LYAudioUnitDescriptor,
        on trackID: UUID,
        in source: LYLLTHSession,
        engine: NightshapeAudioEngine
    ) async throws -> LYLLTHSession {
        var session = source
        guard let trackIndex = session.tracks.firstIndex(where: { $0.id == trackID }),
              let channel = LYChannelMap.channels(in: session).first(where: { $0.trackID == trackID })?.index else {
            throw NSError(domain: "LYLLTH.AudioUnitHost", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Select a compatible track first."])
        }
        if descriptor.isInstrument, session.tracks[trackIndex].kind != .instrument {
            throw NSError(domain: "LYLLTH.AudioUnitHost", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Audio Unit instruments require an instrument track."])
        }
        let unit = try await instantiate(descriptor.componentDescription)
        var slot = LYPluginSlot(
            format: .audioUnit,
            identifier: descriptor.id,
            name: descriptor.name,
            manufacturer: descriptor.manufacturer,
            componentType: descriptor.type,
            componentSubType: descriptor.subtype,
            componentManufacturer: descriptor.manufacturerCode
        )
        slot.reportedLatencySeconds = unit.auAudioUnit.latency
        slot.state = Self.encodeState(unit.auAudioUnit.fullStateForDocument ?? unit.auAudioUnit.fullState)
        units[slot.id] = unit
        observeParameters(of: unit, slotID: slot.id)

        if descriptor.isInstrument {
            session.tracks[trackIndex].instrumentPlugin = slot
            let adapter = LYHostedAudioUnitInstrument(unit: unit)
            instruments[slot.id] = adapter
            engine.setTrackInstrument(trackIndex: channel, instrument: adapter)
        } else {
            session.tracks[trackIndex].inserts.append(slot)
            try applyEffects(for: session.tracks[trackIndex], channel: channel, engine: engine)
        }
        applyDelayCompensation(session: session, engine: engine)
        validationMessage = nil
        return session
    }

    /// Restores every saved AU before transport starts. Missing or rejected
    /// components stay in the document with a validation error instead of
    /// silently disappearing from the mix.
    func restore(_ source: LYLLTHSession, engine: NightshapeAudioEngine) async -> LYLLTHSession {
        var session = source
        for trackIndex in session.tracks.indices {
            guard let channel = LYChannelMap.channels(in: session).first(where: { $0.trackID == session.tracks[trackIndex].id })?.index else { continue }
            if var slot = session.tracks[trackIndex].instrumentPlugin {
                do {
                    let unit = try await instantiate(Self.description(for: slot))
                    Self.apply(slot.state, to: unit)
                    slot.validationError = nil
                    slot.reportedLatencySeconds = unit.auAudioUnit.latency
                    units[slot.id] = unit
                    observeParameters(of: unit, slotID: slot.id)
                    let adapter = LYHostedAudioUnitInstrument(unit: unit)
                    instruments[slot.id] = adapter
                    engine.setTrackInstrument(trackIndex: channel, instrument: adapter)
                } catch {
                    slot.validationError = error.localizedDescription
                    validationMessage = "\(slot.name): \(error.localizedDescription)"
                }
                session.tracks[trackIndex].instrumentPlugin = slot
            }
            for slotIndex in session.tracks[trackIndex].inserts.indices
            where session.tracks[trackIndex].inserts[slotIndex].format == .audioUnit {
                var slot = session.tracks[trackIndex].inserts[slotIndex]
                do {
                    let unit = try await instantiate(Self.description(for: slot))
                    Self.apply(slot.state, to: unit)
                    slot.validationError = nil
                    slot.reportedLatencySeconds = unit.auAudioUnit.latency
                    units[slot.id] = unit
                    observeParameters(of: unit, slotID: slot.id)
                } catch {
                    slot.validationError = error.localizedDescription
                    validationMessage = "\(slot.name): \(error.localizedDescription)"
                }
                session.tracks[trackIndex].inserts[slotIndex] = slot
            }
            try? applyEffects(for: session.tracks[trackIndex], channel: channel, engine: engine)
        }
        applyDelayCompensation(session: session, engine: engine)
        return session
    }

    func captureStates(in source: LYLLTHSession, engine: NightshapeAudioEngine? = nil) -> LYLLTHSession {
        var session = source
        for trackIndex in session.tracks.indices {
            if var slot = session.tracks[trackIndex].instrumentPlugin, let unit = units[slot.id] {
                slot.state = Self.encodeState(unit.auAudioUnit.fullStateForDocument ?? unit.auAudioUnit.fullState)
                slot.reportedLatencySeconds = unit.auAudioUnit.latency
                session.tracks[trackIndex].instrumentPlugin = slot
            }
            for slotIndex in session.tracks[trackIndex].inserts.indices {
                let id = session.tracks[trackIndex].inserts[slotIndex].id
                guard let unit = units[id] else { continue }
                session.tracks[trackIndex].inserts[slotIndex].state = Self.encodeState(
                    unit.auAudioUnit.fullStateForDocument ?? unit.auAudioUnit.fullState
                )
                session.tracks[trackIndex].inserts[slotIndex].reportedLatencySeconds = unit.auAudioUnit.latency
            }
        }
        if let engine { applyDelayCompensation(session: session, engine: engine) }
        return session
    }

    func openEditor(slotID: UUID, title: String) {
        guard let unit = units[slotID] else { return }
        unit.auAudioUnit.requestViewController { [weak self] controller in
            Task { @MainActor in
                guard let self else { return }
                self.editor = controller.map { Editor(id: slotID, title: title, controller: $0) }
            }
        }
    }

    private func applyEffects(for track: LYTrack, channel: Int, engine: NightshapeAudioEngine) throws {
        let chain = track.inserts.compactMap { slot -> AVAudioUnit? in
            guard slot.format == .audioUnit, slot.isBypassed == false else { return nil }
            return units[slot.id]
        }
        try engine.setTrackHostedEffects(trackIndex: channel, effects: chain)
    }

    private func observeParameters(of unit: AVAudioUnit, slotID: UUID) {
        guard let tree = unit.auAudioUnit.parameterTree else { return }
        if let old = observers[slotID] { tree.removeParameterObserver(old) }
        observers[slotID] = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleStateCapture() }
        })
    }

    private func scheduleStateCapture() {
        stateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stateRevision &+= 1 }
        stateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func applyDelayCompensation(session: LYLLTHSession, engine: NightshapeAudioEngine) {
        var totals: [Int: Double] = [:]
        for entry in LYChannelMap.channels(in: session) {
            guard let track = session.tracks.first(where: { $0.id == entry.trackID }) else { continue }
            let instrument = track.instrumentPlugin?.reportedLatencySeconds ?? 0
            let effects = track.inserts.filter { $0.format == .audioUnit && !$0.isBypassed }
                .compactMap(\.reportedLatencySeconds).reduce(0, +)
            totals[entry.index] = instrument + effects
        }
        engine.applyPluginDelayCompensation(secondsByTrack: totals)
    }

    private func instantiate(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: [.loadOutOfProcess]) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? NSError(
                    domain: "LYLLTH.AudioUnitHost", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "The Audio Unit could not be loaded."]
                )) }
            }
        }
    }

    private static func description(for slot: LYPluginSlot) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: slot.componentType ?? 0,
            componentSubType: slot.componentSubType ?? 0,
            componentManufacturer: slot.componentManufacturer ?? 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    private static func encodeState(_ state: [String: Any]?) -> Data? {
        guard let state, PropertyListSerialization.propertyList(state, isValidFor: .binary) else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }

    private static func apply(_ data: Data?, to unit: AVAudioUnit) {
        guard let data,
              let state = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        unit.auAudioUnit.fullState = state
    }
}

struct LYAudioUnitEditorView: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
