import SwiftUI
import NightshapeAudioEngine

/// DrumKit's drum-synth library for one drum track: pick a category, click a
/// sound to hear it, LOAD (or double-click) to put it on the track.
struct LYDrumSoundBrowser: View {
    let trackName: String
    let currentID: String?
    let audition: (DrumSynthPreset) -> Void
    let load: (DrumSynthPreset) -> Void
    let close: () -> Void

    @State private var category: DrumSynthCategory = .kick
    @State private var selected: DrumSynthPreset?
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let groups = LYDrumSounds.grouped
        let inCategory = groups.first { $0.0 == category }?.1 ?? []
        let shown = query.isEmpty
            ? inCategory
            : LYDrumSounds.presets.filter { $0.name.localizedCaseInsensitiveContains(query) }

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("DRUM SYNTH")
                    .font(LYLLTHTheme.wordmark(22))
                    .tracking(1.4)
                    .foregroundStyle(LYLLTHTheme.teal)
                Text(trackName)
                    .font(LYLLTHTheme.label(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(LYLLTHTheme.dim)
                    TextField("SEARCH ALL \(LYDrumSounds.presets.count) SOUNDS", text: $query)
                        .textFieldStyle(.plain)
                        .font(LYLLTHTheme.label(10, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.text)
                }
                .padding(.horizontal, 10)
                .frame(width: 260, height: 30)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(LYLLTHTheme.chromeText)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                ForEach(groups.map(\.0), id: \.self) { item in
                    let isOn = item == category && query.isEmpty
                    Button { category = item; query = "" } label: {
                        Text(item.displayName)
                            .font(LYLLTHTheme.label(8.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(isOn ? LYLLTHTheme.teal : LYLLTHTheme.dim)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(LYLLTHTheme.teal.opacity(isOn ? 0.1 : 0))
                            .overlay(alignment: .bottom) { Rectangle().fill(isOn ? LYLLTHTheme.teal : .clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) { LYHairline() }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(shown) { preset in
                        let isCurrent = preset.id == currentID
                        let isSelected = preset.id == selected?.id
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name)
                                .font(LYLLTHTheme.label(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(isCurrent ? LYLLTHTheme.teal : LYLLTHTheme.text)
                                .lineLimit(1)
                            Text(preset.category.displayName + (isCurrent ? "  ·  ON TRACK" : ""))
                                .font(LYLLTHTheme.label(7, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(LYLLTHTheme.dim)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(LYLLTHTheme.teal.opacity(isSelected ? 0.12 : 0.02))
                        .overlay(Rectangle().stroke(isCurrent || isSelected ? LYLLTHTheme.teal : LYLLTHTheme.lineStrong,
                                                    lineWidth: isCurrent ? 1.5 : 1))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { load(preset) }
                        .onTapGesture {
                            selected = preset
                            audition(preset)
                        }
                        .help("Click to hear it. Double-click to load it on \(trackName).")
                    }
                }
                .padding(2)
            }
            .lyScrollers()

            HStack {
                Text(selected.map { "\($0.name)  ·  CLICK TO HEAR, DOUBLE-CLICK OR LOAD TO USE" } ?? "CLICK A SOUND TO HEAR IT")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(LYLLTHTheme.dim)
                Spacer()
                Button("LOAD ON \(trackName)") { if let selected { load(selected) } }
                    .buttonStyle(LYChromeButtonStyle(active: selected != nil, compact: true))
                    .disabled(selected == nil)
            }
        }
        .padding(14)
        .background(Color(hex: 0x07080D))
        .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.6), lineWidth: 1))
        .onAppear {
            if let current = LYDrumSounds.preset(id: currentID) {
                category = current.category
                selected = current
            }
        }
    }
}
