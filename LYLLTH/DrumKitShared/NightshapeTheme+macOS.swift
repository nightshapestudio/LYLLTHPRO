// macOS stand-in for DrumKit's Theme/NightshapeTheme.swift, which imports
// UIKit. Generated from that file: same tokens, NSFont in place of UIFont.
// LYLLTH compiles DrumKit's FX windows from the sibling checkout against this,
// so if DrumKit changes a theme token, regenerate this file rather than
// editing it by hand (tools/sync-drumkit-theme.sh).
import SwiftUI
import AppKit
import CoreText
import os

enum NightshapeTheme {
    static let background = Color(hex: 0x0C0C0E)
    static let panel = Color(hex: 0x0F0F13)
    static let panelSecondary = Color(hex: 0x09090C)

    /// The deck every FX panel sits on.
    ///
    /// There were four of these. 0x07080D in finale/chorus/void gate, 0x070A0D
    /// in pump/reverb, 0x05060B in compressor/tape delay/track envelope, and
    /// `panel` (0x0F0F13) in tape saturation/flanger — which is light enough
    /// next to the others to read as a different surface. Opening two effects in
    /// a row should not feel like two different apps, so they share this.
    static let fxDeck = Color(hex: 0x07080D)
    static let border = Color.white.opacity(0.10)
    static let graphite = Color(hex: 0x141418)
    // Two visible tiers of secondary text. Both must remain readable
    // against the panel background — never push them below ~0x808090
    // or any usage opacity below ~0.78.
    static let metadata = Color(hex: 0x9898A8)
    static let metaDim   = Color(hex: 0x9090A0)

    // MARK: Text tiers (solid tokens — do NOT stack opacity on these)
    //
    // The app reads "grayed down" when text sits in a low-opacity white wash
    // (e.g. Color.white.opacity(0.3–0.5)) on tiny type — it composites to a
    // muddy mid-gray that barely clears the background. Use these solid tokens
    // instead: pick a tier, don't dim it further. `textFloor` is the darkest a
    // *readable* label may go (~5:1 on the panel). Anything meant to be OFF /
    // inactive chrome uses 0x3A3A48, which is below the readable floor by design.
    static let textPrimary   = Color(hex: 0xEEEEFF)   // near-white — primary copy
    static let textSecondary = Color(hex: 0xB6B8C6)   // lit secondary
    static let textFloor     = Color(hex: 0x888899)   // dim floor — still legible
    static let textOff       = Color(hex: 0x3A3A48)   // OFF / inactive chrome only

    /// Page and section headings. Deliberately one tier below `textPrimary`:
    /// near-white headers read as too stark against the dark page, while the
    /// chrome gray (`textOff`) is below the readable floor and turns a heading
    /// into a smudge. Its own token rather than a `textSecondary` reference so
    /// heading weight can be tuned without moving body copy with it.
    static let textHeader    = Color(hex: 0xB6B8C6)

    /// The cool light gray used for physical chrome — sequencer command-row
    /// buttons, the HELP/HOME nav, the landing card titles, and the piano roll's
    /// white keys. It is a *surface* tone, not a text tier: anything that should
    /// read as a real control face rather than a label uses this.
    ///
    /// The blue bias is load-bearing, not decoration. This sits among accents
    /// measuring roughly +100 to +135 blue-minus-red; at the old 0xE4E7F0 (+12)
    /// it was low-chroma enough that simultaneous contrast made it read cream
    /// against them — the eye adapts its white point to the surrounding field
    /// and a near-neutral turns warm. 0xDCE6FA is +30 at effectively the same
    /// luminance (229 vs 231): cooled, not dimmed.
    static let controlChrome = Color(hex: 0xDCE6FA)
    /// The opacity `controlChrome` is set at whenever it carries type or a
    /// glyph — command-row labels, the HELP/HOME/settings icons, the landing
    /// card titles. Held here rather than per-view so those surfaces cannot
    /// drift a few percent apart from each other.
    static let controlChromeTextOpacity: Double = 0.86
    /// `controlChrome` already at its text opacity. Use this for chrome type
    /// instead of re-applying the opacity at the call site.
    static var controlChromeText: Color {
        controlChrome.opacity(controlChromeTextOpacity)
    }

    /// Fill behind a selected, active or lit control.
    ///
    /// Deliberately faint. The label has to read as text sitting on the panel,
    /// not as text on a coloured plate — at the 0.10-0.28 these controls were
    /// using, an accent-coloured label was competing with its own background.
    /// Outline and bloom carry the "this one is live" signal; the fill only
    /// warms the cell.
    static let controlFill: Double = 0.055
    /// Same fill while a control is held. Enough to acknowledge the touch.
    static let controlFillPressed: Double = 0.13

    static let accentTeal = Color(hex: 0x33CCCC)
    static let accentIndigo = Color(hex: 0x6666FF)
    static let accentPurple = Color(hex: 0x9933FF)
    static let accentHotTeal = Color(hex: 0x00E5D4)
    static let accentHotPurple = Color(hex: 0xA855F7)
    /// Soft light lavender — a 50/50 blend of indigo/pink-violet lifted with the
    /// cool white. Used for the tempo readout and the pattern-selector label.
    /// The fixed frame every FX panel loads into.
    ///
    /// The chassis does not change colour when you swap effects. Each panel used
    /// to draw its own outer border -- 0x123F44 in pump, 0x43475C in finale,
    /// 0x262B7A in chorus, 0x2A1C4D in void gate, indigo in tape saturation,
    /// purple in signal bloom -- so opening a different effect repainted the
    /// whole enclosure and nothing felt fixed. This is the EQ panel's frame,
    /// which is the one that reads as hardware: a constant value, not modulated
    /// by whether the effect is engaged.
    // MARK: - Motion

    /// The app's three springs. Every animated interaction uses one of these.
    ///
    /// Before this the app had 27 animations, all `easeOut` or `easeInOut`, and
    /// 37 transitions that were plain `.opacity`. Ease curves read as correct;
    /// springs read as alive, because a spring overshoots and settles the way a
    /// physical control does. Three is deliberate: enough to separate a tap from
    /// a panel from something that travels, few enough that the whole app moves
    /// like one object.
    ///
    /// All of them animate only `opacity`, `scale`, `offset` and `rotation`,
    /// which the GPU composites for free. Nothing here animates a shadow radius
    /// or a blur -- those re-rasterise every frame and are exactly what would
    /// put audio glitching back.

    /// A tap acknowledging itself. Fast, barely overshoots.
    static let snap = Animation.spring(response: 0.22, dampingFraction: 0.62)
    /// A panel or a value coming to rest. The default for anything that settles.
    static let settle = Animation.spring(response: 0.35, dampingFraction: 0.78)
    /// Something moving from one place to another. Long enough to be followed.
    static let glide = Animation.spring(response: 0.45, dampingFraction: 0.82)

    static let fxPanelBorder = accentTeal.opacity(0.80)
    /// The two shadows the EQ frame carries. Far more restrained than the
    /// 0.10-at-radius-8 blooms the other panels were using.
    static let fxPanelGlowNear = accentTeal.opacity(0.11)
    static let fxPanelGlowFar  = accentTeal.opacity(0.05)

    /// FINALE's colour: deliberately NOT one of the accents.
    ///
    /// Everything upstream is a coloured stage doing something to the signal.
    /// FINALE is the master limiter at the end of the chain, so it reads neutral
    /// and the path resolves to chrome rather than ending on another accent.
    ///
    /// This is exactly `controlChromeText` -- the same value as the type on the
    /// command strip (FX, KITS, PERFORM, MUTE, SOLO). That is the ceiling for
    /// light UI in this app. It was briefly 0xE6ECF5, which is both brighter and
    /// warmer than the command strip, and it glared against everything around
    /// it. Nothing in the chrome should out-light those buttons.
    static var accentNeutral: Color { controlChromeText }

    static let accentLavender = Color(hex: 0xBBA6FD)

    static let ledOff = Color.white.opacity(0.04)
    static let playhead = Color.white.opacity(0.92)

    /// The app's meta face. Adam, not the rounded system design — nothing in
    /// DRUMKIT is meant to read as rounded. Adam ships Light / Medium / Bold,
    /// so the SF weight scale collapses onto those three; callers keep passing
    /// the weight they always did and get the nearest Adam cut. All three are
    /// registered at launch by `FontRegistrar` (PostScript names Adam-Light,
    /// Adam-Medium, Adam-Bold).
    static func metaFont(weight: Font.Weight = .regular, size: CGFloat = 10) -> Font {
        switch weight {
        case .ultraLight, .thin, .light:
            return Font.custom("Adam-Light", size: size)
        case .semibold, .bold, .heavy, .black:
            return Font.custom("Adam-Bold", size: size)
        default:
            return Font.custom("Adam-Medium", size: size)
        }
    }

    static func nightshapeBold(size: CGFloat) -> Font {
        Font.custom("NIGHTSHAPE-Bold", size: size)
    }

    static func nightshapeUIBold(size: CGFloat) -> Font {
        Font.custom("NIGHTSHAPE-Bold", size: size)
    }

    /// Downward nudge that optically centers NIGHTSHAPE-Bold in a fixed-height
    /// container.
    ///
    /// The face is all-caps with no descenders, but its line box still reserves
    /// descent space (ascent 788, descent 217, upm 1024). Ink therefore spans
    /// only 0.090…0.770 of the box while the box centers at 0.491 — leaving the
    /// glyphs sitting 0.061 × size above where they look centered. Any label in a
    /// `.frame(height:)` needs this or it reads high.
    static func nightshapeOpticalDrop(size: CGFloat) -> CGFloat {
        size * 0.061
    }

    /// Outline display face. Reserved EXCLUSIVELY for the audio-panel
    /// visualizer page numbers (1 / 2) — do not use elsewhere.
    static func nightshapeOutline(size: CGFloat) -> Font {
        Font.custom("NIGHTSHAPEOutline-Bold", size: size)
    }

    static func adamMedium(size: CGFloat) -> Font {
        Font.custom("Adam-Medium", size: size)
    }

    /// Adam's light weight. Wide and airy — it wants generous tracking and
    /// enough size to hold its thin strokes, so it suits titles rather than the
    /// small tracked labels `adamMedium` carries.
    static func adamLight(size: CGFloat) -> Font {
        Font.custom("Adam-Light", size: size)
    }

    /// DM-80 (light) — a segmented digital-display face. Used for the KITS
    /// digital readout screen (kit index + kit name).
    static func dm80Light(size: CGFloat) -> Font {
        Font.custom("DM-80-Light", size: size)
    }

    static func bpmValue(size: CGFloat) -> Font {
        // Thin, modern SF display face — the tempo is secondary info so it stays
        // a fine-lined number that reads without shouting. Size carries the
        // legibility; the thin weight keeps it quiet in the hierarchy.
        .system(size: size, weight: .thin, design: .default)
    }

    /// The one face for numeric readouts, app-wide.
    ///
    /// This is the BPM face — the thin SF display cut above — with fixed-width
    /// figures. Every number the app reports as a VALUE uses it: FX parameters,
    /// meters, counters, durations, percentages. Labels stay Adam; digits are
    /// this. One face for numbers means a reading is recognisable as a reading
    /// wherever it appears, instead of each panel inventing its own.
    ///
    /// Before this existed the same parameter readout was drawn six different
    /// ways across the FX panels — `metaFont` at 9.5 and at 11, bold monospaced
    /// at 10 and semibold monospaced at 11, `nightshapeUIBold` at 15, and
    /// `adamMedium` at 8.5 — so identical controls did not look related.
    ///
    /// `monospacedDigit` matters more than it looks: these values change under a
    /// drag, and proportional figures make the number shuffle sideways while the
    /// user is trying to read it. Same typeface, stable column.
    static func numericValue(size: CGFloat) -> Font {
        bpmValue(size: size).monospacedDigit()
    }

    /// How far a string's first glyph sits inside its own text box — the left
    /// side bearing of that specific glyph at that specific size.
    ///
    /// SwiftUI aligns text boxes, not ink, so a column of `.leading` labels is
    /// only optically flush if every string happens to start with a glyph
    /// carrying the same bearing. On the landing cards they do not: in Adam
    /// Light at 21pt "S" starts 0.84pt in while "I", "P" and "K" start ~2.1-2.3pt
    /// in, so SYNTHESIZE, IMPORT AUDIO and KITS drew a ragged left edge — and
    /// the subtitles, set in a different face, sat left of all of them.
    ///
    /// Feed this to `.alignmentGuide(.leading)` to align on the ink instead.
    static func leftInkBearing(_ string: String, fontName: String, size: CGFloat) -> CGFloat {
        let key = "\(fontName)|\(size)|\(string)"
        if let cached = bearingCache.withLock({ $0[key] }) { return cached }
        guard let font = NSFont(name: fontName, size: size) else { return 0 }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        // Image bounds are the drawn ink; origin.x is the gap before it.
        let bearing = CTLineGetImageBounds(line, nil).origin.x
        let value = bearing.isFinite ? bearing : 0
        bearingCache.withLock { $0[key] = value }
        return value
    }

    /// Bearings are pure functions of font + size + string, so they are computed
    /// once and reused rather than re-measured on every body evaluation.
    private static let bearingCache = OSAllocatedUnfairLock(initialState: [String: CGFloat]())

    static func neonPanelStroke(_ color: Color) -> some View {
        Rectangle()
            .stroke(color.opacity(0.86), lineWidth: 1.4)
    }
}

extension View {
    /// Standard NIGHTSHAPE premium panel treatment.
    /// Intentionally square and restrained: dark panel, subtle edge,
    /// and a very low-level ambient lift.
    func nightshapePremiumPanelChrome() -> some View {
        self
            .background(NightshapeTheme.panel)
            .overlay {
                Rectangle()
                    .strokeBorder(
                        NightshapeTheme.border,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 6,
                x: 0,
                y: 2
            )
    }
}

enum WorkstationModuleMetrics {
    static let panelHeight: CGFloat = 160
}

