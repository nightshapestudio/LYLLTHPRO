import AppKit
import SwiftUI

/// LUNATK's container app. macOS installs the Audio Unit from inside it;
/// the window says where to find it.
@main
struct LUNATKApp: App {
    init() { FontRegistrar.registerBundledFonts() }

    var body: some Scene {
        WindowGroup("LUNATK") {
            VStack(alignment: .leading, spacing: 14) {
                Text("LUNATK")
                    .font(LYLLTHTheme.label(28, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(LYLLTHTheme.teal)
                Text("NIGHTSHAPE WAVETABLE SYNTH  ·  AUDIO UNIT INSTRUMENT")
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(LYLLTHTheme.dim)
                Rectangle().fill(LYLLTHTheme.lineStrong).frame(height: 1)
                Text("LUNATK IS INSTALLED. IN LOGIC PRO, GARAGEBAND, ABLETON LIVE OR ANY AUDIO UNIT HOST, ADD A SOFTWARE INSTRUMENT AND CHOOSE NIGHTSHAPE › LUNATK.")
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("KEEP THIS APP IN YOUR APPLICATIONS FOLDER. OPEN IT ONCE AFTER AN UPDATE SO HOSTS SEE THE NEW VERSION.")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(width: 520, alignment: .leading)
            .background(Color(hex: 0x06070B))
        }
        .windowResizability(.contentSize)
    }
}
