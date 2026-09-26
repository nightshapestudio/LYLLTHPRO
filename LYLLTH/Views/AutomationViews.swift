import SwiftUI
import AppKit

// MARK: - Lane

/// One automation lane under a track: the line, its points, and the value
/// the song is at. Click to add a point, drag one to move it, double-click
/// one to remove it. Shift-drag moves only up and down.
struct LYAutomationLaneView: View {
    @Binding var lane: LYAutomationLane
    let accent: Color
    let beatWidth: CGFloat
    let snap: (Double) -> Double
    /// The song beat being heard, or nil.
    let songBeat: () -> Double?
    let isPlaying: Bool

    @State private var dragging: UUID?
    @State private var readout: (x: CGFloat, text: String)?

    private let inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(&context, size: size) }
                if isPlaying {
                    TimelineView(.animation) { _ in
                        if let beat = songBeat(), let value = lane.value(at: beat), lane.isActive {
                            Circle()
                                .fill(accent)
                                .frame(width: 7, height: 7)
                                .lyBloom(accent, strength: 0.5)
                                .position(x: CGFloat(beat) * beatWidth, y: y(value, height: size.height))
                        }
                    }
                    .allowsHitTesting(false)
                }
                if let readout {
                    Text(readout.text)
                        .font(LYLLTHTheme.value(9))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LYLLTHTheme.panel.opacity(0.95))
                        .overlay(Rectangle().stroke(accent.opacity(0.6), lineWidth: 1))
                        .position(x: readout.x + 34, y: 11)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(size: size))
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                if let point = hit(tap.location, size: size) {
                    lane.points.removeAll { $0.id == point.id }
                }
            })
        }
    }

    // MARK: Geometry

    private var range: ClosedRange<Double> { lane.target.range }

    private func y(_ value: Double, height: CGFloat) -> CGFloat {
        let unit = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1e-9)
        return inset + (1 - CGFloat(unit)) * (height - inset * 2)
    }

    private func value(atY py: CGFloat, height: CGFloat) -> Double {
        let unit = 1 - Double((py - inset) / max(height - inset * 2, 1))
        return min(max(range.lowerBound + unit * (range.upperBound - range.lowerBound), range.lowerBound), range.upperBound)
    }

    private func hit(_ location: CGPoint, size: CGSize) -> LYAutomationPoint? {
        lane.points.min { a, b in
            hypot(CGFloat(a.beat) * beatWidth - location.x, y(a.value, height: size.height) - location.y)
                < hypot(CGFloat(b.beat) * beatWidth - location.x, y(b.value, height: size.height) - location.y)
        }.flatMap { point in
            hypot(CGFloat(point.beat) * beatWidth - location.x, y(point.value, height: size.height) - location.y) < 8 ? point : nil
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let alpha = lane.isBypassed == true ? 0.35 : 1.0
        // Centre line for pan and other bipolar targets.
        if range.lowerBound < 0 && range.upperBound > 0 && lane.target != .volume {
            let zero = y(0, height: size.height)
            context.fill(Path(CGRect(x: 0, y: zero, width: size.width, height: 1)), with: .color(Color.white.opacity(0.06)))
        }
        guard let first = lane.points.first else {
            let flat = y(lane.target.range.lowerBound + (range.upperBound - range.lowerBound) / 2, height: size.height)
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: flat)); $0.addLine(to: CGPoint(x: size.width, y: flat)) },
                           with: .color(accent.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            return
        }
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y(first.value, height: size.height)))
        for point in lane.points {
            line.addLine(to: CGPoint(x: CGFloat(point.beat) * beatWidth, y: y(point.value, height: size.height)))
        }
        line.addLine(to: CGPoint(x: size.width, y: y(lane.points.last!.value, height: size.height)))
        var fill = line
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()
        context.fill(fill, with: .color(accent.opacity(0.07 * alpha)))
        context.stroke(line, with: .color(accent.opacity(0.9 * alpha)), lineWidth: 1.5)
        for point in lane.points {
            let center = CGPoint(x: CGFloat(point.beat) * beatWidth, y: y(point.value, height: size.height))
            let rect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: rect), with: .color(dragging == point.id ? LYLLTHTheme.text : Color(hex: 0x0B0C10)))
            context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(alpha)), lineWidth: 1.5)
        }
    }

    // MARK: Editing

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragging == nil {
                    if let point = hit(drag.startLocation, size: size) {
                        dragging = point.id
                    } else {
                        let beat = max(0, snap(Double(drag.startLocation.x / max(beatWidth, 1))))
                        let point = LYAutomationPoint(beat: beat, value: value(atY: drag.startLocation.y, height: size.height))
                        lane.points.append(point)
                        lane.sortPoints()
                        dragging = point.id
                    }
                }
                guard let id = dragging, let index = lane.points.firstIndex(where: { $0.id == id }) else { return }
                let verticalOnly = NSEvent.modifierFlags.contains(.shift)
                if !verticalOnly {
                    lane.points[index].beat = max(0, snap(Double(drag.location.x / max(beatWidth, 1))))
                }
                lane.points[index].value = value(atY: drag.location.y, height: size.height)
                let point = lane.points[index]
                readout = (CGFloat(point.beat) * beatWidth, lane.target.format(point.value))
                lane.sortPoints()
            }
            .onEnded { _ in
                dragging = nil
                readout = nil
            }
    }
}

// MARK: - Lane header

struct LYAutomationLaneHeader: View {
    let title: String
    let accent: Color
    let anchor: String
    @Binding var isBypassed: Bool
    let pickTarget: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(accent.opacity(0.7)).frame(width: 2)
            Button(action: pickTarget) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(LYLLTHTheme.label(8, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(isBypassed ? LYLLTHTheme.dim : LYLLTHTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .lyMenuAnchor(anchor)
            .help("Choose what this lane moves")
            LYTrackToggle(title: "ON", isOn: Binding(get: { !isBypassed }, set: { isBypassed = !$0 }), tint: accent)
                .help("Turn the lane off to hold the control where it is set")
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LYLLTHTheme.chromeText)
                    .frame(width: 19, height: 19)
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this lane")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Target picker

/// What a lane can move on a track, NIGHTSHAPE dropdown style.
struct LYAutomationTargetPanel: View {
    let track: LYTrack
    let session: LYLLTHSession
    let current: LYAutomationTarget?
    /// Targets that already have a lane on this track.
    let taken: Set<LYAutomationTarget>
    let choose: (LYAutomationTarget) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LYNightshapeMenuHeader(eyebrow: track.name, title: current == nil ? "ADD AUTOMATION" : "AUTOMATE", accent: LYLLTHTheme.indigo, close: close)
            LYNightshapeMenuDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("CHANNEL", targets: [.volume, .pan])
                    let buses = LYChannelMap.buses(for: track, in: session)
                    if track.kind != .auxiliary && !buses.isEmpty {
                        section("SENDS", targets: buses.map { .send($0.id) })
                    }
                    section("NIGHTSHAPE FX", targets: LYFXAutomation.all.map { .fx($0.key) }, detail: fxDetail)
                    if track.synth != nil {
                        ForEach(LYSynthAutomation.groups, id: \.title) { group in
                            section("LUNATK · " + group.title, targets: group.keys.map { .synth($0) })
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 340)
        .lyNightshapeMenuChrome(accent: LYLLTHTheme.indigo)
    }

    private func fxDetail(_ target: LYAutomationTarget) -> String? {
        guard case .fx(let key) = target, let parameter = LYFXAutomation.byKey[key], parameter.kind != .reverb else { return nil }
        let chain = (track.fx ?? LYFXRack()).chain(isMain: false)
        return chain.contains(parameter.kind) ? nil : "NOT IN THIS CHAIN"
    }

    private func section(_ title: String, targets: [LYAutomationTarget], detail: ((LYAutomationTarget) -> String?)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LYLLTHTheme.label(7.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(LYLLTHTheme.indigo)
                .padding(.bottom, 2)
            ForEach(targets, id: \.self) { target in
                let used = taken.contains(target) && target != current
                Button { choose(target) } label: {
                    HStack(spacing: 8) {
                        Text(target.title(in: session).replacingOccurrences(of: "LUNATK · ", with: ""))
                            .font(LYLLTHTheme.label(9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(used ? LYLLTHTheme.dim : LYLLTHTheme.text)
                        Spacer(minLength: 4)
                        if let note = used ? "HAS A LANE" : detail?(target) {
                            Text(note)
                                .font(LYLLTHTheme.label(6.5, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(LYLLTHTheme.dim)
                        }
                        if target == current { LYLED(color: LYLLTHTheme.indigo, size: 5) }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(target == current ? LYLLTHTheme.indigo.opacity(0.08) : LYLLTHTheme.panelRaised)
                    .overlay(alignment: .leading) { Rectangle().fill(LYLLTHTheme.indigo.opacity(target == current ? 0.9 : 0.4)).frame(width: 2) }
                    .overlay(Rectangle().stroke(LYLLTHTheme.lineStrong.opacity(0.9), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(used)
            }
        }
    }
}
