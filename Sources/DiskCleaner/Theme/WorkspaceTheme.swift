import SwiftUI

/// Presentation-only color families. No scan state or product rules belong here.
enum WorkspaceTone {
    case smart, cleanup, trash, applications, files, advanced

    private var hue: UInt {
        switch self {
        case .smart: return 0x695E9E
        case .cleanup: return 0x975575
        case .trash: return 0x286F76
        case .applications: return 0x386A94
        case .files: return 0x955E63
        case .advanced: return 0x5E608D
        }
    }

    private var pastel: UInt {
        switch self {
        case .smart: return 0xE5DDF6
        case .cleanup: return 0xF2DCE8
        case .trash: return 0xD4EEE8
        case .applications: return 0xDAEAF8
        case .files: return 0xF5DFD7
        case .advanced: return 0xE1E2F2
        }
    }

    func theme(from original: Theme, scheme: ColorScheme) -> Theme {
        // Custom skins retain their own visual identity and saved selection.
        guard original.id == "dawn" || original.id == "graphite" else { return original }
        let dark = scheme == .dark
        var result = original
        result.scheme = scheme
        var palette = original.palette
        palette.paper = Color(hex: dark ? 0x30365D : 0xF3F1FA)
        palette.surface = Color(hex: dark ? 0x303653 : 0xFFFFFF)
        palette.surfaceAlt = Color(hex: dark ? 0x3D4363 : 0xEEEFF7)
        palette.ink = Color(hex: dark ? 0xFFFFFF : 0x24243B)
        palette.inkSecondary = Color(hex: dark ? 0xE4E7F5 : 0x53536B)
        palette.inkTertiary = Color(hex: dark ? 0xC6CCE2 : 0x62647A)
        palette.separator = Color(hex: dark ? 0x747D9D : 0xC9CDDF, alpha: dark ? 0.5 : 0.8)
        palette.tint = Color(hex: dark ? 0x83E0F5 : 0x165A83)
        palette.onTint = Color(hex: dark ? 0x202D4F : 0xFFFFFF)
        palette.tintSoft = Color(hex: dark ? 0x40516D : 0xDCEBF6)
        result.palette = palette
        result.backdrop = .wash([Color(hex: dark ? hue : pastel), palette.paper])
        result.face = .system
        result.elevation = .soft
        result.metric.radiusCard = 18
        result.metric.radiusControl = 10
        result.metric.rowHeight = 40
        result.motion = .calm
        return result
    }
}

/// Decorative artwork made from native shapes, separate from real scan progress.
struct WorkspaceEmblem: View {
    @Environment(\.theme) private var theme
    var symbol: String
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [theme.palette.tint.opacity(0.25), theme.palette.tint.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(theme.palette.tint.opacity(0.24), lineWidth: 1)
                .padding(1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .light))
                .foregroundStyle(theme.palette.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
