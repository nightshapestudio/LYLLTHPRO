import SwiftUI

/// DrumKit defines this beside its sequencer grid, which LYLLTH does not
/// compile. Same shape: the playhead step that FX windows with step displays
/// (FRACTURE, PUMP, DELAY) observe without re-rendering the workstation.
final class TransportDisplayState: ObservableObject {
    @Published private(set) var currentStep = 0

    func update(step: Int) {
        guard currentStep != step else { return }
        currentStep = step
    }
}
