import SwiftUI

@main
struct LYLLTHApp: App {
    @StateObject private var audio = AudioEngineController()
    @StateObject private var plugins = AudioUnitCatalog()

    init() {
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
            CommandGroup(after: .toolbar) {
                Button(audio.isPlaying ? "Stop" : "Play") {
                    audio.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}
