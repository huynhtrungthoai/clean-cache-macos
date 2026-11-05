import SwiftUI
import AppKit
import DiskCleanerCore

@MainActor
final class FolderDrillModel: ObservableObject {
    /// Path of the current level.
    @Published private(set) var path: String = ""
    /// Breadcrumb cells for this path, all clickable. The last one is `path`.
    ///
    /// **Excludes the leftmost "Overview" cell**: the view always places that first (rules in `crumbChain`).
    @Published private(set) var crumbs: [String] = []
    @Published private(set) var level: DirLevel? = nil
    @Published private(set) var busy = false
    /// What this pass is measuring. During the "measuring" seconds, not saying where reads like "it broke".
    @Published private(set) var pendingPath: String = ""
    @Published var selected: Set<String> = []

    /// Live readout. This level is slow because it **measures each subfolder** (dozens per level, each a subtree),
    /// so it must say not just "measuring ~/Library" but also "which of those 40+ dirs we're on".
    private(set) var progress = ScanProgress()

    /// Max file rows listed. **Files only**: `/Applications`-style levels have hundreds of entries;
    /// nobody scans them all, the rest fold into the tail line. Folders are exempt: on this page
    /// a missing folder is a missing path downward, and "going down" is why it exists.
    static let fileCap = 200

    private var cache: [String: DirLevel] = [:]
    private var task: Task<Void, Never>? = nil
    /// Screenshot pipeline only (`DISKWISE_DRILL_INTO=1`): after the first level is measured, auto-drill once
    /// to capture the "breadcrumb + one level deeper" screen.
    private var autoDescended = false
    /// The auto-drill is handed to the outside. Entering a level is a navigation and must be recorded in history;
    /// calling `open` directly in the model would make Back unable to return from the captured screen, a false testimony.
    var onAutoDescend: ((String) -> Void)?

    var rows: [ChildEntry] { level?.entries ?? [] }
    var selectedEntries: [ChildEntry] { rows.filter { selected.contains($0.path) } }
    var selectedBytes: Int64 { selectedEntries.reduce(Int64(0)) { $0 + $1.size } }

    /// Whether we can go up. **Not "is there a parent dir"**: above top levels like `/Applications`, `/Library`
    /// is the Overview; disk root `/` is not a stop (reason in `drillParent`).
    /// So once any folder was entered, this button has somewhere to go; the target is computed by `drillParent`.
    var canGoUp: Bool { !path.isEmpty }

    /// Enter a folder. Clicking the same one again doesn't re-measure (cache refills directly).
    ///
    /// Which level the page shows is decided by `store.folderDrillPath`, so only the view's `start()`
    /// should call this; row clicks, breadcrumbs and "Up" all land on that field first.
    func open(_ target: String) {
        guard !target.isEmpty else { return }
        if target == path, level != nil, !busy { return }
        path = target
        rebuildCrumbs()
        selected.removeAll()
        load(target)
    }

    /// A rescan invalidates the whole cache: the disk ledger drifts, and keeping old numbers across a pass
    /// means deciding today with last time's ledger.
    func invalidate() {
        task?.cancel()
        cache = [:]
        level = nil
        if !path.isEmpty { load(path) }
    }

    /// Re-measure this level after deleting: rows and totals changed; pruning rows in place would mismatch the tail line.
    func reload() {
        cache[path] = nil
        if !path.isEmpty { load(path) }
    }

    private func load(_ target: String) {
        task?.cancel()
        if let hit = cache[target] {
            level = hit
            busy = false
            return
        }
        level = nil
        // One level per pass, readout and list reset too: the previous level's ledger on this level is a different ledger.
        progress = ScanProgress()
        busy = true
        pendingPath = target
        let limit = Self.fileCap
        let prog = progress
        task = Task { [weak self] in
            let lv = await dirLevel(URL(fileURLWithPath: target), includeFiles: true,
                                    fileLimit: limit, progress: prog)
            guard !Task.isCancelled, let self, self.path == target else { return }
            self.cache[target] = lv
            self.level = lv
            self.busy = false
            if SnapshotMode.drillAutoDescend, !self.autoDescended,
               let first = lv.entries.first(where: { $0.isDir }) {
                self.autoDescended = true
                self.onAutoDescend?(first.path)
            }
        }
    }

    /// This strip is fully defined by `crumbChain` (it lives in Core and is self-checked); here we only handle
    /// "don't show an empty strip before entering any folder". Rules are documented there: each cell is that level itself,
    /// the home folder collapses to `~`, and the leftmost "Overview" cell isn't in this array.
    private func rebuildCrumbs() {
        crumbs = path.isEmpty ? [] : crumbChain(for: path)
    }
}
