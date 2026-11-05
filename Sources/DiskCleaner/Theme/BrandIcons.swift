import SwiftUI
import AppKit

// MARK: - Command-line-only tools with no .app on this machine: show each vendor's official brand mark at row start
//
// Why not "skip if unavailable": dirs like `~/.ollama/models`, `~/.cache/uv`, 12 rows of node_modules
// get the generic blue system folder (measured: byte-identical PNG to an empty dir), so the column would be a row of
// identical folders, less recognizable than nothing. Yet each tool already has a widely recognized mark,
// and the mark doesn't depend on what's installed: CLI tools are often installed via brew / npm, with no .app to look up.
//
// Source: each vendor's official monochrome SVG, rasterized to 32/64 PNGs shipped in the bundle (26 tools, 64 KB total).
// Layout follows the established `IconTile(muted: true)` rule: light wash of the same hue, no solid color blocks;
// a column of solid blocks would overpower the numbers column on the right and clash with the primary button's shape.
enum BrandIcons {
    /// slug -> official color from each vendor's brand / press page (checked one by one against simple-icons `_data/simple-icons.json`)
    ///
    /// This table is the manifest itself: every slug in `Resources/BrandIcons/` must have ` slug.png` and
    /// `slug@2x.png`, and vice versa; shipping extra marks just wastes bundle size on others' trademarks.
    static let colors: [String: String] = [
        "ollama":       "000000",   // ~/.ollama/models
        "openai":       "412991",   // Codex CLI, Whisper model cache
        "uv":           "DE5FE9",   // ~/.cache/uv
        "gradle":       "02303A",   // ~/.gradle/caches, wrapper
        "huggingface":  "FFD21E",   // ~/.cache/huggingface
        "rust":         "000000",   // ~/.cargo/registry
        "npm":          "CB3837",   // ~/.npm, projects with package-lock.json
        "pnpm":         "F69220",   // pnpm store, projects with pnpm-lock.yaml
        "yarn":         "2C8EBB",   // ~/Library/Caches/Yarn
        "bun":          "000000",   // ~/.bun/install/cache
        "nodedotjs":    "5FA04E",   // node_modules (when the project has no lockfile)
        "apachemaven":  "C71A36",   // ~/.m2/repository
        "googlechrome": "4285F4",   // ~/.cache/chrome-devtools-mcp
        "homebrew":     "FBB040",   // ~/Library/Caches/Homebrew
        "go":           "00ADD8",   // ~/go/pkg/mod, ~/Library/Caches/go-build
        "anaconda":     "44A833",   // ~/.conda/pkgs
        "python":       "3776AB",   // ~/Library/Caches/pip
        "nvm":          "F4DD4B",   // ~/.nvm/.cache
        "xcode":        "147EFB",   // CoreSimulator/Devices
        "swift":        "F05138",   // ~/Library/Caches/org.swift.swiftpm
        "cocoapods":    "EE3322",   // ~/Library/Caches/CocoaPods
        "intellijidea": "000000",   // ~/Library/Caches/JetBrains/IntelliJIdea*
        "pycharm":      "000000",   // ~/Library/Caches/JetBrains/PyCharm*
        "androidstudio": "3DDC84",  // ~/Library/Caches/Google/AndroidStudio*, ~/.android/avd, Android SDK
    ]

    private static let cache = NSCache<NSString, NSImage>()

    /// Loads a mark. Packaged builds use `Contents/Resources/BrandIcons`; `swift run` falls back to the source tree,
    /// same as safety_db: deliberately avoids `Bundle.module`, which fatalErrors when the .bundle is missing
    /// and whose fallback path is the build machine's absolute path.
    static func image(_ slug: String) -> NSImage? {
        let key = slug as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "BrandIcons")
            ?? Bundle.main.url(forResource: slug, withExtension: "png")
            ?? {
                let p = "Sources/DiskCleaner/Resources/BrandIcons/\(slug).png"
                return FileManager.default.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
            }()
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true   // color is decided by skin and light/dark; the mark only supplies the shape
        cache.setObject(img, forKey: key)
        return img
    }

    // MARK: Colors

    private static func components(_ hex: String) -> (Double, Double, Double) {
        let v = UInt32(hex, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
    }

    private static func mix(_ c: (Double, Double, Double), toward t: Double, by k: Double) -> Color {
        let f = { (v: Double) in min(max(v + (t - v) * k, 0), 1) }
        return Color(.sRGB, red: f(c.0), green: f(c.1), blue: f(c.2), opacity: 1)
    }

    /// Whether the official color is visible on this skin. Ollama, Rust and IntelliJ's official marks are pure black,
    /// invisible on dark; Hugging Face's yellow and uv's pink conversely wash out on light.
    /// So only adjust toward "visible": lighten on dark, darken on light, stopping once that lightness is reached;
    /// hue and saturation are kept as-is (changing hue would make it no longer their mark).
    static func tint(_ slug: String, dark: Bool) -> Color {
        guard let hex = colors[slug] else { return .primary }
        let c = components(hex)
        let lum = luminance(c)
        if dark {
            guard lum < 0.30 else { return mix(c, toward: 1, by: 0) }
            return mix(c, toward: 1, by: (0.62 - lum) / max(0.001, 1 - lum))
        }
        guard lum > 0.60 else { return mix(c, toward: 0, by: 0) }
        return mix(c, toward: 0, by: 1 - 0.34 / max(0.001, lum))
    }
}

/// The official-mark variant for the row-start cell. Same layout as `IconTile(muted: true)`; change both together.
struct BrandTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var slug: String
    var side: CGFloat = 26

    var body: some View {
        let isDark = (theme.scheme ?? colorScheme) == .dark
        let color = BrandIcons.tint(slug, dark: isDark)
        ZStack {
            theme.tileShape(side).fill(color.opacity(theme.tileWash(dark: isDark)))
            if let img = BrandIcons.image(slug) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundStyle(color)
                    .frame(width: side * 0.62, height: side * 0.62)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
