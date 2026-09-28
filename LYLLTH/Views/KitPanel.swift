import NightshapeAudioEngine
import SwiftUI

/// KITS: swap every drum track's sound at once, keeping the patterns, levels
/// and effects. DrumKit's factory kits, plus kits you save here.
struct LYKitPanel: View {
    let session: LYLLTHSession
    /// Loads a kit into the song. Returns how many tracks changed.
    let loadKit: (LYDrumKit) -> Int
    let close: () -> Void

    @State private var userKits: [LYDrumKit] = LYDrumKitLibrary.userKits()
    @State private var saveName: String?
    @State private var deleting: UUID?
    @State private var hovered: UUID?
    @State private var status = ""
    @FocusState private var saveFocused: Bool

    private var loaded: LYDrumKit? {
        LYDrumKitLibrary.loadedKit(in: session, among: LYDrumKitLibrary.factory + userKits)
    }

    private var drumTrackCount: Int { LYDrumKitLibrary.drumTrackIndices(in: session).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KITS")
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.teal)
                Text(loaded?.name ?? (drumTrackCount == 0 ? "NO DRUM TRACKS" : "YOUR OWN MIX"))
                    .font(LYLLTHTheme.label(13, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.text)
                mixedNumericLabel("\(drumTrackCount) DRUM TRACKS  ·  PATTERNS, LEVELS AND FX STAY",
                                  labelFont: LYLLTHTheme.label(7.5, weight: .bold), numberFont: LYLLTHTheme.value(8.5))
                    .tracking(1)
                    .foregroundStyle(LYLLTHTheme.dim)
            }
            .padding(12)
            LYNightshapeMenuDivider()
            ViewThatFits(in: .vertical) {
                kitList
                ScrollView { kitList }
            }
            .frame(maxHeight: 420)
            LYNightshapeMenuDivider()
            saveArea.padding(12)
        }
        .frame(width: 340)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.teal)
    }

    /// Sized to its rows; the list only scrolls once your kits outgrow it.
    private var kitList: some View {
                VStack(alignment: .leading, spacing: 1) {
                    section("FACTORY")
                    ForEach(LYDrumKitLibrary.factory) { kitRow($0) }
                    section("YOUR KITS")
                    if userKits.isEmpty {
                        Text("Save the sounds you have now and they show up here, for every song.")
                            .font(LYLLTHTheme.body(11))
                            .foregroundStyle(LYLLTHTheme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(userKits) { kitRow($0) }
                }
                .padding(.vertical, 6)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(LYLLTHTheme.label(7, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(LYLLTHTheme.dim)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func kitRow(_ kit: LYDrumKit) -> some View {
        let isLoaded = loaded?.id == kit.id
        let isHovered = hovered == kit.id
        let sounds = kit.slots.prefix(4).compactMap { $0.preset?.name.uppercased() }.joined(separator: " · ")
        return HStack(spacing: 10) {
            Button {
                let changed = loadKit(kit)
                status = changed == 0 ? "ALREADY LOADED" : "LOADED ON \(changed) TRACK\(changed == 1 ? "" : "S")"
            } label: {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(isLoaded ? LYLLTHTheme.teal : (isHovered ? LYLLTHTheme.teal.opacity(0.6) : LYLLTHTheme.lineStrong))
                        .frame(width: 3, height: 30)
                        .shadow(color: LYLLTHTheme.teal.opacity(isLoaded ? 0.8 : 0), radius: 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kit.name)
                            .font(LYLLTHTheme.label(10.5, weight: .bold))
                            .tracking(0.9)
                            .foregroundStyle(isLoaded || isHovered ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                        Text(sounds)
                            .font(LYLLTHTheme.label(7, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(LYLLTHTheme.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isLoaded {
                        Text("LOADED")
                            .font(LYLLTHTheme.label(7, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(LYLLTHTheme.teal)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(drumTrackCount == 0)
            .help("Put \(kit.name)'s sounds on the drum tracks")
            if !kit.isFactory {
                Button {
                    if deleting == kit.id {
                        LYDrumKitLibrary.delete(kit)
                        userKits = LYDrumKitLibrary.userKits()
                        deleting = nil
                    } else {
                        deleting = kit.id
                    }
                } label: {
                    Text(deleting == kit.id ? "DELETE?" : "×")
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.record)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .overlay(Rectangle().stroke(LYLLTHTheme.record.opacity(deleting == kit.id ? 0.8 : 0.35), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(deleting == kit.id ? "Click again to delete \(kit.name)" : "Delete this kit")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(isHovered ? LYLLTHTheme.teal.opacity(0.06) : Color.clear)
        .onHover { inside in hovered = inside ? kit.id : (hovered == kit.id ? nil : hovered) }
    }

    @ViewBuilder
    private var saveArea: some View {
        if let name = saveName {
            HStack(spacing: 6) {
                TextField("KIT NAME", text: Binding(get: { name }, set: { saveName = $0 }))
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(LYLLTHTheme.deck)
                    .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.7), lineWidth: 1))
                    .focused($saveFocused)
                    .onSubmit(save)
                    .onExitCommand { saveName = nil }
                Button("SAVE", action: save)
                    .buttonStyle(LYChromeButtonStyle(active: true, tint: LYLLTHTheme.teal, compact: true))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    saveName = "MY KIT"
                    DispatchQueue.main.async { saveFocused = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 9, weight: .bold))
                        Text("SAVE CURRENT SOUNDS AS A KIT")
                    }
                }
                .buttonStyle(LYChromeButtonStyle(tint: LYLLTHTheme.teal, compact: true))
                .disabled(drumTrackCount == 0)
                if !status.isEmpty {
                    Text(status)
                        .font(LYLLTHTheme.label(7.5, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(LYLLTHTheme.dim)
                }
            }
        }
    }

    private func save() {
        guard let name = saveName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        let kit = LYDrumKitLibrary.kit(named: name, from: session)
        do {
            try LYDrumKitLibrary.save(kit)
            userKits = LYDrumKitLibrary.userKits()
            saveName = nil
            status = "SAVED \(kit.name)"
        } catch {
            status = "COULD NOT SAVE: " + error.localizedDescription.uppercased()
        }
    }
}
