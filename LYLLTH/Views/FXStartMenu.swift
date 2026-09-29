import SwiftUI

/// The channel strip's + menu: folders of effects that open beside it, like
/// Logic's plug-in menu. Hovering a folder opens it; clicking an effect adds
/// it to the channel and opens its window. Effects already on the channel
/// are marked and can be taken off from here.
/// A filled insert slot in a channel strip, which its ▾ menu can clear or
/// fill with something else.
enum LYFXSlotRef: Equatable {
    case effect(FXKind)
    case audioUnit(UUID)

    /// The slot's menu anchor, unique per strip.
    func anchorID(isMain: Bool) -> String {
        let strip = isMain ? "main" : "track"
        switch self {
        case .effect(let kind): return "fxSlot.\(strip).\(kind.rawValue)"
        case .audioUnit(let id): return "fxSlot.\(strip).\(id.uuidString)"
        }
    }
}

struct LYFXStartMenu: View {
    let targetName: String
    let target: FXTarget
    /// The channel's current chain.
    let chain: [FXKind]
    /// Audio Unit effects, for tracks. Empty on MAIN.
    let audioUnits: [LYAudioUnitDescriptor]
    let add: (FXKind) -> Void
    let open: (FXKind) -> Void
    let remove: (FXKind) -> Void
    let addAudioUnit: (LYAudioUnitDescriptor) -> Void
    let close: () -> Void
    /// A folder to show open when the menu appears.
    var initialCategory: FXKind.Category? = nil
    /// Opened from a filled slot: the effect in it. Choosing an effect puts
    /// it in that slot instead, and NO EFFECT empties it (Logic's slot menu).
    var replacing: String? = nil
    var clearSlot: (() -> Void)? = nil

    private enum Folder: Hashable {
        case category(FXKind.Category)
        case audioUnits
    }

    @State private var folder: Folder?
    @State private var manufacturer: String?
    @State private var query = ""
    @State private var hoveredRow: String?
    @FocusState private var searchFocused: Bool

    private let rootWidth: CGFloat = 228
    private let columnWidth: CGFloat = 268

    private var available: [FXKind] {
        FXKind.controlDeckCases.filter { $0.isAvailable(for: target) }
    }

    private func effects(in category: FXKind.Category) -> [FXKind] {
        available.filter { $0.category == category }
    }

    private var manufacturers: [String] {
        Array(Set(audioUnits.map { $0.manufacturer.uppercased() })).sorted()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            rootColumn
            if !query.isEmpty {
                searchColumn
            } else if case .category(let category) = folder {
                effectColumn(category)
            } else if folder == .audioUnits {
                manufacturerColumn
                if let manufacturer { audioUnitColumn(manufacturer) }
            }
        }
        .onExitCommand(perform: close)
        .onAppear {
            if let initialCategory { folder = .category(initialCategory) }
            DispatchQueue.main.async { searchFocused = true }
        }
        .animation(LYLLTHTheme.snap, value: folder)
        .animation(LYLLTHTheme.snap, value: manufacturer)
    }

    // MARK: Columns

    private var rootColumn: some View {
        column(width: rootWidth, accent: LYLLTHTheme.teal) {
            VStack(alignment: .leading, spacing: 3) {
                Text(replacing == nil ? "ADD EFFECT" : "SLOT  ·  " + targetName.uppercased())
                    .font(LYLLTHTheme.label(8, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(LYLLTHTheme.teal)
                    .lineLimit(1)
                Text((replacing ?? targetName).uppercased())
                    .font(LYLLTHTheme.label(11.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(LYLLTHTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(query.isEmpty ? LYLLTHTheme.dim : LYLLTHTheme.teal)
                TextField("SEARCH", text: $query)
                    .textFieldStyle(.plain)
                    .font(LYLLTHTheme.label(9.5, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.text)
                    .focused($searchFocused)
                    .onSubmit(addFirstMatch)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(LYLLTHTheme.deck)
            .overlay(Rectangle().stroke(searchFocused ? LYLLTHTheme.teal.opacity(0.7) : LYLLTHTheme.lineStrong, lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            LYNightshapeMenuDivider()

            if let clearSlot {
                noEffectRow(clearSlot)
                LYNightshapeMenuDivider()
            }

            VStack(spacing: 1) {
                ForEach(FXKind.Category.allCases) { category in
                    let count = effects(in: category).count
                    if count > 0 {
                        folderRow(title: category.title, icon: Self.icon(for: category), count: count,
                                  isOpen: folder == .category(category)) {
                            folder = .category(category)
                            manufacturer = nil
                        }
                    }
                }
                if !audioUnits.isEmpty {
                    LYNightshapeMenuDivider().padding(.vertical, 3)
                    folderRow(title: "AUDIO UNITS", icon: "square.stack.3d.up", count: audioUnits.count,
                              isOpen: folder == .audioUnits, accent: LYLLTHTheme.indigo) {
                        folder = .audioUnits
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func effectColumn(_ category: FXKind.Category) -> some View {
        column(width: columnWidth, accent: LYLLTHTheme.teal) {
            columnHeader(category.title)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(effects(in: category), id: \.self) { effectRow($0) }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 420)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var manufacturerColumn: some View {
        column(width: 210, accent: LYLLTHTheme.indigo) {
            columnHeader("AUDIO UNITS")
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(manufacturers, id: \.self) { name in
                        folderRow(title: name, icon: nil, count: audioUnits.filter { $0.manufacturer.uppercased() == name }.count,
                                  isOpen: manufacturer == name, accent: LYLLTHTheme.indigo) {
                            manufacturer = name
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 420)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func audioUnitColumn(_ name: String) -> some View {
        column(width: columnWidth, accent: LYLLTHTheme.indigo) {
            columnHeader(name)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(audioUnits.filter { $0.manufacturer.uppercased() == name }) { unitRow($0) }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 420)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    /// Typing searches every folder at once.
    private var searchColumn: some View {
        let kinds = searchKinds
        let units = searchUnits
        return column(width: columnWidth, accent: LYLLTHTheme.teal) {
            columnHeader(kinds.isEmpty && units.isEmpty ? "NO MATCH" : "RESULTS")
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(kinds, id: \.self) { effectRow($0) }
                    if !units.isEmpty {
                        LYNightshapeMenuDivider().padding(.vertical, 3)
                        ForEach(units) { unitRow($0) }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 420)
        }
    }

    private var searchKinds: [FXKind] {
        available.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.subtitle(for: target) ?? "").localizedCaseInsensitiveContains(query)
                || $0.category.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var searchUnits: [LYAudioUnitDescriptor] {
        audioUnits.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.manufacturer.localizedCaseInsensitiveContains(query) }
    }

    private func addFirstMatch() {
        if let kind = searchKinds.first { choose(kind) }
        else if let unit = searchUnits.first { addAudioUnit(unit); close() }
    }

    // MARK: Rows

    private func choose(_ kind: FXKind) {
        if replacing != nil || !chain.contains(kind) { add(kind) } else { open(kind) }
        close()
    }

    /// Empties the slot: Logic's "No Plug-in".
    private func noEffectRow(_ clear: @escaping () -> Void) -> some View {
        let hovered = hoveredRow == "none"
        return Button {
            clear()
            close()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle.slash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(LYLLTHTheme.purple)
                    .frame(width: 16)
                Text("NO EFFECT")
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(hovered ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(hovered ? LYLLTHTheme.purple.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredRow = inside ? "none" : (hoveredRow == "none" ? nil : hoveredRow)
            if inside { folder = nil }
        }
        .padding(.vertical, 4)
        .help("Take \(replacing ?? "this effect") off the channel")
    }

    private func folderRow(title: String, icon: String?, count: Int, isOpen: Bool,
                           accent: Color = LYLLTHTheme.teal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isOpen ? accent : LYLLTHTheme.secondary)
                        .frame(width: 16)
                }
                Text(title)
                    .font(LYLLTHTheme.label(10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(isOpen ? LYLLTHTheme.text : LYLLTHTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(LYLLTHTheme.value(9.5))
                    .foregroundStyle(LYLLTHTheme.dim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isOpen ? accent : LYLLTHTheme.dim)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isOpen ? accent.opacity(0.10) : (hoveredRow == title ? Color.white.opacity(0.03) : Color.clear))
            .overlay(alignment: .leading) { Rectangle().fill(isOpen ? accent : Color.clear).frame(width: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredRow = inside ? title : (hoveredRow == title ? nil : hoveredRow)
            // Folders open on hover, the way a start menu does.
            if inside { action() }
        }
    }

    private func effectRow(_ kind: FXKind) -> some View {
        let isOn = chain.contains(kind)
        let key = "fx." + kind.rawValue
        let hovered = hoveredRow == key
        return HStack(spacing: 0) {
            Button { choose(kind) } label: {
                HStack(spacing: 11) {
                    Rectangle()
                        .fill(kind.accent)
                        .frame(width: 3, height: 26)
                        .shadow(color: kind.accent.opacity(hovered ? 0.8 : 0), radius: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(LYLLTHTheme.label(10.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(LYLLTHTheme.text)
                            .lineLimit(1)
                        if let subtitle = kind.subtitle(for: target) {
                            mixedNumericLabel(subtitle.replacingOccurrences(of: "·", with: " · "),
                                              labelFont: LYLLTHTheme.label(7.5, weight: .bold), numberFont: LYLLTHTheme.value(8.5))
                                .tracking(0.8)
                                .foregroundStyle(LYLLTHTheme.dim)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    if isOn {
                        Text("ON")
                            .font(LYLLTHTheme.label(7.5, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(LYLLTHTheme.teal)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .overlay(Rectangle().stroke(LYLLTHTheme.teal.opacity(0.7), lineWidth: 1))
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hovered ? kind.accent : LYLLTHTheme.dim)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, isOn ? 6 : 12)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOn ? "Open \(kind.title)" : "Add \(kind.title) and open it")
            if isOn {
                Button { remove(kind) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LYLLTHTheme.purple)
                        .frame(width: 22, height: 17)
                        .overlay(Rectangle().stroke(LYLLTHTheme.purple.opacity(0.6), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .help("Take \(kind.title) off this channel")
            }
        }
        .background(hovered ? kind.accent.opacity(0.08) : Color.clear)
        .onHover { inside in hoveredRow = inside ? key : (hoveredRow == key ? nil : hoveredRow) }
    }

    private func unitRow(_ unit: LYAudioUnitDescriptor) -> some View {
        let key = "au." + unit.id
        let hovered = hoveredRow == key
        return Button {
            addAudioUnit(unit)
            close()
        } label: {
            HStack(spacing: 11) {
                Rectangle().fill(LYLLTHTheme.indigo).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.name.uppercased())
                        .font(LYLLTHTheme.label(10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(LYLLTHTheme.text)
                        .lineLimit(1)
                    Text(unit.manufacturer.uppercased())
                        .font(LYLLTHTheme.label(7.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(LYLLTHTheme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovered ? LYLLTHTheme.indigo : LYLLTHTheme.dim)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(hovered ? LYLLTHTheme.indigo.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredRow = inside ? key : (hoveredRow == key ? nil : hoveredRow) }
        .help("Load \(unit.name) on this track")
    }

    // MARK: Pieces

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(LYLLTHTheme.label(8, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(LYLLTHTheme.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(alignment: .bottom) { LYHairline() }
    }

    private func column<Content: View>(width: CGFloat, accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(width: width, alignment: .leading)
            .lyNightshapeMenuChrome(accent: accent)
    }

    static func icon(for category: FXKind.Category) -> String {
        switch category {
        case .tone: return "dial.medium"
        case .dynamics: return "gauge.with.needle"
        case .space: return "circle.dotted.circle"
        case .motion: return "wave.3.right"
        case .destruction: return "bolt"
        case .output: return "speaker.wave.2"
        }
    }
}
