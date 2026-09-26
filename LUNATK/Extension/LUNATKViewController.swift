import AppKit
import CoreAudioKit
import SwiftUI

/// The extension's entry point: makes the Audio Unit and shows LUNATK's
/// editor in the host's plug-in window. The window can be any size; the
/// editor scales to fit it.
@objc(LUNATKViewController)
public final class LUNATKViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: LUNATKAudioUnit?
    private var hosting: NSHostingView<LUNATKPluginEditor>?
    private let model = LUNATKEditorModel()

    public override func loadView() {
        LUNATKFonts.registerOnce()
        view = NSView(frame: NSRect(origin: .zero, size: LUNATKPluginEditor.designSize))
        preferredContentSize = LUNATKPluginEditor.designSize
        let hosting = NSHostingView(rootView: LUNATKPluginEditor(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])
        self.hosting = hosting
        if let audioUnit { model.connect(audioUnit) }
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try LUNATKAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        DispatchQueue.main.async { [model] in model.connect(unit) }
        return unit
    }
}

/// The editor's view of the Audio Unit, on the main thread.
@MainActor
final class LUNATKEditorModel: ObservableObject {
    @Published var patch: LYSynthPatch = .initPatch
    @Published private(set) var instrument: LYSynthInstrument?
    private weak var unit: LUNATKAudioUnit?

    nonisolated init() {}

    func connect(_ unit: LUNATKAudioUnit) {
        guard self.unit !== unit else { return }
        self.unit = unit
        patch = unit.patch
        instrument = unit.instrument
        unit.onPatchChange = { [weak self] next in
            MainActor.assumeIsolated { self?.patch = next }
        }
        unit.onInstrumentChange = { [weak self] next in
            MainActor.assumeIsolated { self?.instrument = next }
        }
    }

    func edit(_ next: LYSynthPatch) {
        patch = next
        unit?.setPatchFromEditor(next)
    }
}

/// LYLLTH's LUNATK editor, scaled to whatever size the host gives it.
struct LUNATKPluginEditor: View {
    static let designSize = NSSize(width: 1180, height: 720)
    @ObservedObject var model: LUNATKEditorModel

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.designSize.width, geo.size.height / Self.designSize.height)
            LYSynthEditor(
                patch: Binding(get: { model.patch }, set: { model.edit($0) }),
                trackName: "LUNATK",
                instrument: model.instrument,
                close: {}
            )
            .id(model.instrument.map { ObjectIdentifier($0) })
            .frame(width: Self.designSize.width, height: Self.designSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color(hex: 0x06070B))
    }
}

enum LUNATKFonts {
    private static var done = false
    static func registerOnce() {
        guard !done else { return }
        done = true
        FontRegistrar.registerBundledFonts()
    }
}
