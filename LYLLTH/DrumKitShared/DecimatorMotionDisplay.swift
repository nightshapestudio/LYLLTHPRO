import SwiftUI

/// DrumKit keeps this bridge inside its root view, which LYLLTH does not
/// compile; this is the same type for the shared Sonic Decimator editor. It
/// carries the glide-smoothed MOTION point being played, separate from the
/// step being edited.
@MainActor
final class DecimatorMotionDisplay: ObservableObject {
    @Published private var mainPosition: SonicDecimatorEditorModel.Position?
    @Published private var positionsByRowID: [UUID: SonicDecimatorEditorModel.Position] = [:]

    func position(for rowID: UUID?) -> SonicDecimatorEditorModel.Position? {
        if let rowID { return positionsByRowID[rowID] }
        return mainPosition
    }

    func setPosition(_ position: SonicDecimatorEditorModel.Position, for rowID: UUID?) {
        if let rowID {
            guard positionsByRowID[rowID] != position else { return }
            positionsByRowID[rowID] = position
        } else {
            guard mainPosition != position else { return }
            mainPosition = position
        }
    }

    func clearPosition(for rowID: UUID?) {
        if let rowID {
            positionsByRowID.removeValue(forKey: rowID)
        } else if mainPosition != nil {
            mainPosition = nil
        }
    }
}
