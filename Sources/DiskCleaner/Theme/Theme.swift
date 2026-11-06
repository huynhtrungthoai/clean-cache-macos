import SwiftUI

// ── Skin engine v2 ────────────────────────────────────────────────────────────
// A skin = a whole visual skeleton, not just a palette.
//
// v1's fatal flaw: Skin only carried colors, so every skin looked like the same outfit with a different lipstick.
// v2 makes "structure" a token too: typeface design, corner radius, stroke weight, layering (material), background treatment,
// density, motion signature. Two skins must differ in skeleton, otherwise there is no reason for both to exist.
//
// Adding a skin = add an object to the skins array in Resources/skins.json; zero view changes.
// Parsing and fallbacks live in SkinCatalog.swift.
// Views may only read @Environment(\.theme); hard-coded color values are forbidden.
// Iron rule: body text is never tinted (no colored text outside ink/inkSecondary);
//       color is only for icon tiles, rings, buttons, badges.

// MARK: - Skin skeleton dimensions

enum ThemeTier: String, Hashable {
    case free
    case premium
}

/// Typeface design: three faces give three personalities, zero font files, zero size
enum FaceDesign: Hashable {
    case system      // SF Pro: native, trustworthy
    case rounded     // SF Rounded: friendly, young
    case serif       // New York: premium, slow, cultured
}

/// Layering: how a card lifts off the background
enum Elevation: Hashable {
    case flat        // stroke only (black-gold/ink-wash: the more restrained, the more premium)
    case soft        // soft shadow (native premium feel)
    case hard        // solid offset shadow (brutalist, punchy)
    case glass       // translucent material + highlight stroke (aurora)
}

/// Background treatment: a window base that isn't flat color has character
enum Backdrop: Hashable {
    case solid
    case wash([Color])                 // vertical gradient
    case aurora([Color])               // multiple radial light spots
    case fiber(tint: Color, strength: Double)   // paper-fiber texture
}

/// Motion signature: switching skins changes the feel too
enum MotionSignature: Hashable {
    case still     // barely moves (ink-wash: stillness)
    case calm      // standard easing (native)
    case springy   // springy (aurora: lively)
}

// MARK: - Palette

struct ThemePalette {
    var paper: Color          // window base
    var surface: Color        // card
    var surfaceAlt: Color     // nested layer inside cards / hover
    var ink: Color            // body text (never tinted)
    var inkSecondary: Color   // secondary text
    var inkTertiary: Color    // placeholder/caption
    var separator: Color      // separators, card strokes
    var tint: Color           // primary accent: buttons/rings/icon tiles/selection
    var onTint: Color
    var tintSoft: Color       // selected-row background
    var danger: Color
    var onDanger: Color
    var safeBG: Color
    var safeFG: Color
    var warnBG: Color
    var warnFG: Color
    var shadow: Color         // shadow color (dark skins need it darker and denser)
    var chart: [Color]        // 6-color data series, distinguishable under color-vision deficiency
}

// MARK: - Metrics

struct ThemeMetric {
    var radiusCard: CGFloat
    var radiusControl: CGFloat
    var radiusTile: CGFloat
    var stroke: CGFloat       // card stroke weight
    var rowHeight: CGFloat
    var cardPadding: CGFloat
    var sectionGap: CGFloat
}

// MARK: - Skin

struct Theme: Identifiable {
    var id: String
    var name: String
    var tagline: String
    var tier: ThemeTier
    /// The skin carries its own appearance: a dark skin shouldn't be pulled back to light by the system's light mode
    var scheme: ColorScheme?
    var palette: ThemePalette

    var face: FaceDesign
    var displayWeight: Font.Weight
    var displayTracking: Double

    /// displayTracking was tuned for Han characters: square glyphs need air, so serif skins get 0.8/1.2.
    /// The same values on Latin letters scatter into a row of ellipses, so Latin text only takes positive values;
    /// negative values (tight sans/rounded tracking) suit both scripts and pass through unchanged. Simplified and Traditional are both Han, same rule.
    var titleTracking: Double {
        min(displayTracking, 0.3)
    }

    var elevation: Elevation
    var backdrop: Backdrop
    var metric: ThemeMetric
    var motion: MotionSignature

    /// Icon tile shape: circle (soft) / continuous corners (Apple) / square (hard)
    var tileShape: TileShape = .squircle
    /// Icon tile coloring strategy
    var tileStrategy: TileStrategy = .spectrum

    /// The **ring material** on this disk: the name of the skin's own set of numbers (`RingStyle`).
    ///
    /// Why it follows the skin rather than being a separate user preference: material describes "how this bar reflects light",
    /// and it must be judged together with the skin's hue, lightness and personality: ink-wash must be still, aurora translucent.
    /// Splitting them into two settings allows combos like "still skin + orbiting highlight" that nobody tuned, though each setting is valid alone.
    ///
    /// This field is **data**, not logic: it only answers "which set of numbers"; all drawing is in
    /// `RingStyle.swift` / `RingLayers.swift`. The history and the "how many files to add a material" accounting
    /// are in the L1 decision record at the top of `RingStyle.swift`.
    /// Default `.standard` = the version live today, so older skins.json without a `ring` field are pixel-identical.
    var ring: RingLook = .standard

    /// When `Channel.showsPricing` is true this skin is shown as a product; with the switch off all skins are regular skins.
    var isPaid: Bool { Channel.showsPricing && tier == .premium }
}

enum TileShape: Hashable {
    case circle, squircle, rounded
}

/// Coloring strategy for sidebar/row icon tiles.
/// Most skins use iOS-Settings-style "one color per category", navigating by color;
/// the restrained black-gold/ink-wash skins may only alternate the tint and ink: a screen full of rainbow would ruin their calm.
enum TileStrategy: Hashable {
    case spectrum
    case duotone
}

extension Theme {
    static let fallback = Theme.builtIn
}

// MARK: - Fonts

extension Theme {
    func bodyFont(_ style: Font.TextStyle = .body) -> Font {
        switch face {
        case .system: return .system(style)
        case .rounded: return .system(style, design: .rounded)
        case .serif: return .system(style, design: .serif)
        }
    }

    func display(_ style: Font.TextStyle) -> Font {
        switch face {
        case .system: return .system(style).weight(displayWeight)
        case .rounded: return .system(style, design: .rounded).weight(displayWeight)
        case .serif: return .system(style, design: .serif).weight(displayWeight)
        }
    }

    func numeric(_ style: Font.TextStyle) -> Font {
        display(style)
    }

    /// Sets body text at the mockup's exact size, borrowing only the skin's face; weight is given explicitly.
    ///
    /// The system `.callout` is 11 pt on macOS, while the mockup's `.lede` is 15 px and `.btn` is 13 px:
    /// the hero screen's lede would be a step smaller than the body text below it, inverting the hierarchy.
    func prose(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch face {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        }
    }

    /// The big number at the ring's center: size is derived from the ring diameter, not picked from a nice-looking step.
    func numeric(size: CGFloat, weight: Font.Weight? = nil) -> Font {
        let design: Font.Design
        switch face {
        case .system: design = .default
        case .rounded: design = .rounded
        case .serif: design = .serif
        }
        return .system(size: size, weight: weight ?? displayWeight, design: design)
    }

    var animation: Animation {
        switch motion {
        case .still: return .easeOut(duration: 0.12)
        case .calm: return .easeInOut(duration: 0.22)
        case .springy: return .spring(response: 0.42, dampingFraction: 0.62)
        }
    }

    var pressAnimation: Animation {
        switch motion {
        case .still: return .linear(duration: 0.08)
        case .calm: return .easeOut(duration: 0.16)
        case .springy: return .spring(response: 0.26, dampingFraction: 0.5)
        }
    }

    /// Icon tile color: one color per category (identifies the place) or two-color alternation (identifies the skin)
    func tileColor(index: Int, dark: Bool) -> Color {
        switch tileStrategy {
        case .spectrum:
            let ramp = dark ? Theme.spectrumDark : Theme.spectrumLight
            return ramp[index % ramp.count]
        case .duotone:
            return index % 2 == 0 ? palette.tint : palette.ink
        }
    }

    /// Sidebar icons are colored by **group**: one hue per group, not a new color per row.
    ///
    /// Competitor survey (2026-10-19, 14 sidebars): the two multicolor ones spread 7 and 8 hues over 11 rows,
    /// with tools of the same kind sharing a color; none gave each row its own color. 14 colors reads as a launcher
    /// and drags the eye away from the hero ring. 7 groups / 7 colors (after adding Diagnostics & Dumps + Observe) is still
    /// within the observed ceiling.
    func groupTileColor(group: Int, dark: Bool) -> Color {
        let ramp = dark ? Theme.groupHuesDark : Theme.groupHuesLight
        return ramp[group % ramp.count]
    }

    /// Background opacity of light-wash icon tiles: dark skins need more, or the same-hue glyph won't stand out
    func tileWash(dark: Bool) -> Double { dark ? 0.22 : 0.14 }

    /// Brand spectrum: order matches sidebar entries one-to-one; dark and light variants keep dark skins from looking dull
    static let spectrumLight: [Color] = [
        Color(hex: 0x2A62D6), Color(hex: 0xE0762A), Color(hex: 0x7B4FC9),
        Color(hex: 0xC93F76), Color(hex: 0x18884F), Color(hex: 0x0E8FA8),
        Color(hex: 0xB8860B), Color(hex: 0xC8372D), Color(hex: 0x5B6472),
        Color(hex: 0x0E8F79), Color(hex: 0x6E7B2F)
    ]

    static let spectrumDark: [Color] = [
        Color(hex: 0x6C9BFF), Color(hex: 0xF2954E), Color(hex: 0xA98BE8),
        Color(hex: 0xE879A6), Color(hex: 0x4FC98A), Color(hex: 0x4FC3DD),
        Color(hex: 0xE0B84A), Color(hex: 0xFF6B60), Color(hex: 0x98A0AC),
        Color(hex: 0x3FC9AC), Color(hex: 0xB0BE63)
    ]

    /// Hues for the seven sidebar groups. Order: See space / Dev machine / Clean / AI / Settings / Diagnostics & Dumps / Observe.
    ///
    /// All desaturated: the sidebar is navigation, not a data chart. The dark variant raises lightness so the same-hue glyph
    /// holds up on the light wash (0.22 / 0.14); the light variant goes darker instead for contrast on white.
    /// From the sixth group on: Diagnostics & Dumps (brick red: that group is about "where things are going wrong") and Observe
    /// (gray: a look-but-don't-touch place shouldn't have warmth).
    static let groupHuesLight: [Color] = [
        Color(hex: 0x35507E), Color(hex: 0x2F5E63), Color(hex: 0x2F584A),
        Color(hex: 0x574A7E), Color(hex: 0x4C535E),
        Color(hex: 0x74483E), Color(hex: 0x565B62)
    ]

    static let groupHuesDark: [Color] = [
        Color(hex: 0x6B8FC9), Color(hex: 0x58A6A6), Color(hex: 0x5C9A7E),
        Color(hex: 0x9A86C9), Color(hex: 0x8A94A6),
        Color(hex: 0xC98B7D), Color(hex: 0x9AA1AB)
    ]
}

// MARK: - Environment injection
//
// v1 read skins via static Clay.*; SwiftUI didn't know to redraw, so ContentView had to hang
// .id(skin) to force-rebuild the whole subtree. Side effect: every @StateObject was rebuilt on skin change,
// so each skin switch reran the full disk scan. v2 uses Environment; switching skins only recolors and
// scan state is preserved.
//
// The default here deliberately points at builtIn, not the current skin: it's a safety value for when injection is missing;
// reading skins.json here would drag file I/O into the environment-resolution hot path. The real skin is
// injected at the root by DiskCleanerApp.

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .builtIn
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// The skin page's mini previews use this to render a whole subtree in another skin
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .environment(\.locale, Locale(identifier: L10n.active.code))
    }
}

// MARK: - Hex

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
