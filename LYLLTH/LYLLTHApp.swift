import SwiftUI
import NightshapeAudioEngine

@main
struct LYLLTHApp: App {
    init() {
        LYChannelMap.configureEngine()
        // A Mac has frames to spare: meters, visualizers and FX windows
        // move at display rate instead of the phone's battery-saving rates.
        FXAnimation.frameInterval = 1.0 / 120.0
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        // A new song opens on the demo song.
        DocumentGroup(newDocument: LYLLTHSessionDocument(session: .demoSong())) { configuration in
            LYDocumentWorkspace(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LYProjectCommands()
        }
    }
}

/// Owns every mutable runtime service for exactly one document window.
/// Opening a second song therefore creates a second engine, AU host, catalog,
/// undo history and recovery journal instead of sharing global state.
private struct LYDocumentWorkspace: View {
    @Binding var document: LYLLTHSessionDocument
    let fileURL: URL?
    @StateObject private var audio: AudioEngineController
    @StateObject private var plugins = AudioUnitCatalog()
    @StateObject private var audioUnits = LYAudioUnitHost()

    init(document: Binding<LYLLTHSessionDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        _audio = StateObject(wrappedValue: AudioEngineController())
    }

    var body: some View {
        WorkspaceView(document: $document, fileURL: fileURL)
            .environmentObject(audio)
            .environmentObject(plugins)
            .environmentObject(audioUnits)
            .preferredColorScheme(.dark)
            .onDisappear { audio.shutdown() }
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
    var togglePlayback: () -> Void
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
        CommandGroup(after: .toolbar) {
            Button("Play / Stop") { workspace?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(workspace == nil)
        }
    }
}
