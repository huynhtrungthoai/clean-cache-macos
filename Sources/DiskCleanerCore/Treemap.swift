import Foundation
import CoreGraphics

// ── C7: treemap layout (docs/enhance-feat.md §11). Pure, no UI; Codex draws it with Canvas. ──

/// One laid-out tile. `id` is the caller's id, unchanged; `bytes` is the value it was given.
public struct TreemapTile: Equatable, Sendable {
    public let id: String
    public let bytes: Int64
    public let rect: CGRect
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000). Tiles fill `rect` exactly, each tile's
/// area is proportional to its bytes, and rows are chosen to keep tiles close to square.
///
/// - Nodes with `bytes <= 0` are left out (nothing to draw), so are duplicate ids after the first.
/// - Order: largest first, ties by id, so the same input always gives the same picture.
/// - Empty input or an empty rect → `[]`.
public func squarifiedLayout(_ nodes: [(id: String, bytes: Int64)], in rect: CGRect) -> [TreemapTile] {
    guard rect.width > 0, rect.height > 0 else { return [] }
    var seen = Set<String>()
    let items = nodes
        .filter { $0.bytes > 0 && seen.insert($0.id).inserted }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
    guard !items.isEmpty else { return [] }
    let total = items.reduce(0.0) { $0 + Double($1.bytes) }
    let scale = Double(rect.width * rect.height) / total
    let areas = items.map { Double($0.bytes) * scale }

    // Worst aspect ratio of a row with sum `s`, extremes `lo`/`hi`, laid along a side of length `w`.
    func worst(_ s: Double, _ lo: Double, _ hi: Double, _ w: Double) -> Double {
        let w2 = w * w, s2 = s * s
        return max(w2 * hi / s2, s2 / (w2 * lo))
    }

    var out: [TreemapTile] = []
    out.reserveCapacity(items.count)
    var free = rect
    var i = 0
    while i < items.count {
        let side = Double(min(free.width, free.height))
        // Grow the row while it does not make its worst tile worse.
        var end = i + 1
        var sum = areas[i], lo = areas[i], hi = areas[i]
        while end < items.count {
            let a = areas[end]
            let nSum = sum + a, nLo = min(lo, a), nHi = max(hi, a)
            if worst(nSum, nLo, nHi, side) > worst(sum, lo, hi, side) { break }
            sum = nSum; lo = nLo; hi = nHi; end += 1
        }
        let isLastRow = end == items.count
        if free.width >= free.height {
            // Column on the left, tiles stacked top to bottom.
            let w = isLastRow ? free.width : CGFloat(sum / Double(free.height))
            var y = free.minY
            for k in i..<end {
                let h = k == end - 1 ? free.maxY - y : CGFloat(areas[k] / Double(w))
                out.append(TreemapTile(id: items[k].id, bytes: items[k].bytes,
                                       rect: CGRect(x: free.minX, y: y, width: w, height: h)))
                y += h
            }
            free = CGRect(x: free.minX + w, y: free.minY, width: max(0, free.width - w), height: free.height)
        } else {
            // Row on top, tiles left to right.
            let h = isLastRow ? free.height : CGFloat(sum / Double(free.width))
            var x = free.minX
            for k in i..<end {
                let w = k == end - 1 ? free.maxX - x : CGFloat(areas[k] / Double(h))
                out.append(TreemapTile(id: items[k].id, bytes: items[k].bytes,
                                       rect: CGRect(x: x, y: free.minY, width: w, height: h)))
                x += w
            }
            free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: max(0, free.height - h))
        }
        i = end
    }
    return out
}

/// Id of the tile that stands for files measured but not listed (`DirLevel.unlistedBytes`,
/// beyond the file cap). It is real, measured space — but not one selectable row.
public let treemapUnlistedID = "\u{0}unlisted"

/// Treemap input for one Folder Drill level: every listed entry by path, plus one
/// `treemapUnlistedID` tile for unlisted files. Unreadable space is never invented: an entry
/// with `unreadable == true` keeps the bytes that could be measured (a lower bound); the UI
/// marks it, it does not grow it.
public func treemapNodes(for level: DirLevel) -> [(id: String, bytes: Int64)] {
    var nodes = level.entries.map { (id: $0.path, bytes: $0.size) }
    if level.unlistedBytes > 0 { nodes.append((id: treemapUnlistedID, bytes: level.unlistedBytes)) }
    return nodes
}
