import SwiftUI
import NightshapeAudioEngine

@main
struct LYLLTHApp: App {
    @StateObject private var audio = AudioEngineController()
    @StateObject private var plugins = AudioUnitCatalog()

    init() {
        LYChannelMap.configureEngine()
        // A Mac has frames to spare: meters, visualizers and FX windows
        // move at display rate instead of the phone's battery-saving rates.
        FXAnimation.frameInterval = 1.0 / 120.0
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        DocumentGroup(newDocument: LYLLTHSessionDocument()) { configuration in
            WorkspaceView(document: configuration.$document)
                .environmentObject(audio)
                .environmentObject(plugins)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LYProjectCommands()
            CommandGroup(after: .toolbar) {
                Button(audio.isPlaying ? "Stop" : "Play") {
                    audio.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}

/// What the front song window can do from the menu bar.
struct LYWorkspaceActions {
    var showSequencer: () -> Void
    var showArrangement: () -> Void
    var openDrumKitProject: () -> Void
    var saveDrumKitProject: () -> Void
    var exportSong: () -> Void
    var toggleMusicalTyping: () -> Void
}

private struct LYWorkspaceActionsKey: FocusedValueKey {
    typealias Value = LYWorkspaceActions
}

extension FocusedValues {
    var lyWorkspace: LYWorkspaceActions? {
        get { self[LYWorkspaceActionsKey.self] }
        set { self[LYWorkspaceActionsKey.self] = newValue }
    }
}

struct LYProjectCommands: Commands {
    @FocusedValue(\.lyWorkspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open DrumKit Project (.fkit)…") { workspace?.openDrumKitProject() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Save as DrumKit Project (.fkit)…") { workspace?.saveDrumKitProject() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Export Song (WAV)…") { workspace?.exportSong() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(workspace == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Sequencer") { workspace?.showSequencer() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(workspace == nil)
            Button("Arrangement") { workspace?.showArrangement() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(workspace == nil)
            Button("Musical Typing") { workspace?.toggleMusicalTyping() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(workspace == nil)
            Divider()
        }
    }
}
