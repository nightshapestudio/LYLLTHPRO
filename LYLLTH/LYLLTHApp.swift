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
        // A new song is blank; DEMO SONG in the song menu asks for the demo.
        DocumentGroup(newDocument: LYLLTHSessionDocument(session: LYNewSong.take())) { configuration in
            LYDocumentWorkspace(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            LYProjectCommands()
            LYHelpCommands()
        }

        Window("LYLLTH Help", id: "lyllth-help") {
            LYHelpCenterView()
        }
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            LYSettingsView()
        }
    }
}

/// What the next new song window starts as. NEW is always blank; DEMO SONG
/// sets `demo` just before asking for a new window.
@MainActor
enum LYNewSong {
    static var demo = false

    static func take() -> LYLLTHSession {
        defer { demo = false }
        guard !demo else { return .demoSong() }
        var session = LYLLTHSession.blank()
        LYAppPreferences.applyNewProjectDefaults(to: &session)
        return session
    }

    static func openDemo() {
        demo = true
        NSDocumentController.shared.newDocument(nil)
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
    @AppStorage(LYPreferenceKey.interfaceTextScale) private var textScale = 1.0
    @AppStorage(LYPreferenceKey.highContrast) private var highContrast = false

    init(document: Binding<LYLLTHSessionDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        _audio = StateObject(wrappedValue: AudioEngineController())
    }

    var body: some View {
        // A text size or contrast change redraws the song view from scratch.
        // Only the view: the engine, plug-ins and document live out here, and
        // the shutdown hook stays outside so a redraw never stops the audio.
        WorkspaceView(document: $document, fileURL: fileURL)
            .id("\(textScale)-\(highContrast)")
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
    var addTrack: () -> Void = {}
    var openDrumSynth: () -> Void = {}
    var openKits: () -> Void = {}
    var openLUNATK: () -> Void = {}
    /// Previous (−1) / next (+1) sound on the selected track.
    var stepSound: (Int) -> Void = { _ in }
    /// The selected drum track's sound, printed to audio at the cursor.
    var printSound: () -> Void = {}
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
        CommandMenu("Track") {
            Button("New Track…") { workspace?.addTrack() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(workspace == nil)
            Divider()
            Button("Drum Synth") { workspace?.openDrumSynth() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("Kits") { workspace?.openKits() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Button("LUNATK") { workspace?.openLUNATK() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            Divider()
            Button("Previous Sound") { workspace?.stepSound(-1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(workspace == nil)
            Button("Next Sound") { workspace?.stepSound(1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(workspace == nil)
            Divider()
            Button("Print Sound as Sample") { workspace?.printSound() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Play / Stop") { workspace?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(workspace == nil)
        }
    }
}

struct LYHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("LYLLTH Help") { openWindow(id: "lyllth-help") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

