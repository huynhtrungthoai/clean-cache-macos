import SwiftUI
import DiskCleanerCore

/// Measured areas come entirely from Core; the list and map share selection.
struct FolderTreemap: View {
    @Environment(\.theme) private var theme
    var level: DirLevel
    var selected: Set<String>
    var sizeLabels: [String: String]
    var select: (ChildEntry) -> Void
    var open: (ChildEntry) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let tiles = level.rootErrno == 0 ? squarifiedLayout(treemapNodes(for: level), in: bounds) : []
            let rows = Dictionary(level.entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.id) { tile in
                    if let row = rows[tile.id], tile.id != treemapUnlistedID {
                        rowTile(row, rect: tile.rect)
                            .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
                    } else if tile.id == treemapUnlistedID {
                        tileLabel(name: L("Unlisted files"), size: uiHuman(tile.bytes), unreadable: false, rect: tile.rect)
                            .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4))
                            .background(theme.palette.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.inkSecondary, style: StrokeStyle(dash: [2, 3])))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(L("Unlisted files") + " · " + uiHuman(tile.bytes))
                            .help(L("Unlisted files"))
                            .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
                    }
                }
                if tiles.isEmpty && level.rootErrno == 0 {
                    Text(L("No measured space to map"))
                        .font(theme.bodyFont(.callout)).foregroundStyle(theme.palette.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rowTile(_ row: ChildEntry, rect: CGRect) -> some View {
        let isSelected = selected.contains(row.path)
        let fill: Color = isSelected ? theme.palette.tintSoft : theme.palette.surfaceAlt
        let border: Color = isSelected ? theme.palette.tint : theme.palette.separator
        let style = StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: row.unreadable ? [4, 3] : [])
        return Button { select(row) } label: {
            tileLabel(name: row.name, size: sizeLabels[row.id] ?? uiHuman(row.size), unreadable: row.unreadable, rect: rect)
                .frame(width: max(0, rect.width - 4), height: max(0, rect.height - 4))
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, style: style))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if row.isDir { open(row) } })
        .accessibilityLabel(row.name + " · " + uiHuman(row.size) + (row.unreadable ? " · " + L("Partially counted") : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L("Select in either view; double-click a folder to open it."))
        .accessibilityAction(named: Text(L("Open this folder"))) { if row.isDir { open(row) } }
        .help(row.path + (row.unreadable ? " · " + L("has unreadable parts") : ""))
    }

    private func tileLabel(name: String, size: String, unreadable: Bool, rect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if unreadable {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.palette.warnFG)
            }
            if rect.width > 70 && rect.height > 42 {
                Text(name).font(theme.bodyFont(.caption).weight(.medium)).lineLimit(1)
                Text(size).font(theme.bodyFont(.caption2)).monospacedDigit().lineLimit(1)
                if unreadable && rect.height > 70 {
                    Text(L("Partially counted")).font(theme.bodyFont(.caption2)).lineLimit(1)
                }
            }
        }
        .padding(6)
        .foregroundStyle(theme.palette.ink)
        .clipped()
    }
}
