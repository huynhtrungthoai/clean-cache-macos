import SwiftUI
import AppKit

/// Use the bundled app icon everywhere, so Dock and in-app branding cannot drift apart.
struct BrandLogo: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 38

    private static let icon: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        // Bare SwiftPM executable during development.
        return NSImage(contentsOfFile: "build_app/AppIcon.icns")
    }()

    var body: some View {
        Group {
            if let icon = Self.icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Text("C").font(.system(size: size * 0.65, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.palette.onTint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: size * 0.22).fill(theme.palette.tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Product.name)
    }
}
