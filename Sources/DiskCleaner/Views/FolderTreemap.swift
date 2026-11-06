import SwiftUI
import DiskCleanerCore

/// A proportional preview of measured, listed rows. The final squarified layout
/// will come from C7; this renderer owns no scanning or file actions.
struct FolderTreemap: View {
    @Environment(\.theme) private var theme
    var rows: [ChildEntry]
    var selected: Set<String>
    var sizeLabels: [String: String]
    var select: (ChildEntry) -> Void
    var open: (ChildEntry) -> Void

    private struct Tile {
        let row: ChildEntry
        let rect: CGRect
    }

    var body: some View {
        GeometryReader { proxy in
            let tiles = tiles(in: CGRect(origin: .zero, size: proxy.size))
            Canvas { context, _ in
                for tile in tiles {
                    let rect = tile.rect.insetBy(dx: 2, dy: 2)
                    guard rect.width > 0, rect.height > 0 else { continue }
                    let isSelected = selected.contains(tile.row.path)
                    let shape = Path(roundedRect: rect, cornerRadius: 6)
                    context.fill(shape, with: .color(isSelected ? theme.palette.tintSoft : theme.palette.surfaceAlt))
                    context.stroke(shape, with: .color(isSelected ? theme.palette.tint : theme.palette.separator),
                                   lineWidth: isSelected ? 2 : 1)
                    if rect.width > 70 && rect.height > 42 {
                        var labelContext = context
                        labelContext.clip(to: Path(rect.insetBy(dx: 7, dy: 5)))
                        labelContext.draw(Text(tile.row.name).font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.palette.ink),
                            at: CGPoint(x: rect.minX + 8, y: rect.minY + 14), anchor: .leading)
                        labelContext.draw(Text(sizeLabels[tile.row.id] ?? uiHuman(tile.row.size)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.palette.inkSecondary),
                            at: CGPoint(x: rect.minX + 8, y: rect.minY + 31), anchor: .leading)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture(count: 1))
                .onEnded { value in
                    switch value {
                    case .first(let event):
                        if let tile = tiles.first(where: { $0.rect.contains(event.location) }), tile.row.isDir {
                            open(tile.row)
                        }
                    case .second(let event):
                        if let tile = tiles.first(where: { $0.rect.contains(event.location) }) {
                            select(tile.row)
                        }
                    }
                })
        }
        .overlay {
            if rows.allSatisfy({ $0.size <= 0 }) {
                Text(L("No measured space to map"))
                    .font(theme.bodyFont(.callout)).foregroundStyle(theme.palette.inkSecondary)
                    .padding(12)
            }
        }
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // The adjacent list has the same rows, selection and navigation, with
        // native controls for keyboard and VoiceOver. Do not duplicate them here.
        .accessibilityHidden(true)
    }

    private func tiles(in bounds: CGRect) -> [Tile] {
        let measured = rows.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        var remainingBytes = measured.reduce(0.0) { $0 + Double($1.size) }
        guard remainingBytes > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        var remaining = bounds
        return measured.map { row in
            let fraction = min(1, Double(row.size) / remainingBytes)
            let rect: CGRect
            if remaining.width >= remaining.height {
                let width = remaining.width * fraction
                rect = CGRect(x: remaining.minX, y: remaining.minY, width: width, height: remaining.height)
                remaining.origin.x += width
                remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = remaining.height * fraction
                rect = CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: height)
                remaining.origin.y += height
                remaining.size.height = max(0, remaining.height - height)
            }
            remainingBytes = max(0, remainingBytes - Double(row.size))
            return Tile(row: row, rect: rect)
        }
    }
}
