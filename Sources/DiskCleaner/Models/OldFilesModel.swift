import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class OldFilesModel: ObservableObject, ScanStatusReporting {
    @Published var rows: [FileRow] = []
    @Published var scanning = false
    @Published var days = 90
    @Published var skipDev = true
    /// 本轮实际用的范围，页头贴标签用；范围变了没重扫时不能顶着旧标签说真话
    @Published private(set) var scope: ScanScope = .user
    @Published private(set) var started = false
    /// 现场读数：「很久没动」换到整盘范围要重走每一棵树，等几分钟得说清在等什么。
    private(set) var progress = ScanProgress()
    private var task: Task<Void, Never>? = nil
    /// 满足条件的文件总数（`rows` 只是它最大的那 300 个）；删掉几条就跟着减几条
    @Published private(set) var count = 0
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []

    var selected: [FileRow] { rows.filter { $0.selected } }

    // MARK: - V2-FILES (docs/enhance-feat.md §11)

    /// Search/kind filter over the rows shown. Selection is kept on the rows themselves.
    func filtered(query: String = "", kinds: Set<FileKind> = []) -> [FileRow] {
        filterFileRows(rows, query: query, kinds: kinds)
    }

    /// Kind chips with counts over the rows shown.
    var kindCounts: [(kind: FileKind, count: Int, bytes: Int64)] { fileKindCounts(rows) }

    /// The scan matched more files than are listed: filters apply to the listed (largest) ones
    /// only. The UI says "Filtering the N largest of M found".
    var rowsAreTruncated: Bool { count > rows.count }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { rows.reduce(0) { $0 + $1.size } }

    /// 列表被就地删短之后，「扫到多少个」这个总数得跟着减，否则对账句会一直
    /// 说「只列了前 300 个」——而那时候屏幕上可能只剩 40 行，全都列出来了。
    func lose(_ n: Int) { count = max(rows.count, count - n) }

    var selectAll: SelectAll? {
        let open = rows.filter { isBulkSelectable($0.url) }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy(\.selected),
                         unselectable: rows.count - open.count) { on in
            for i in self.rows.indices where isBulkSelectable(self.rows[i].url) {
                self.rows[i].selected = on
            }
        }
    }

    func scan(scope: ScanScope) {
        task?.cancel()
        scanning = true
        started = true
        scanState = .scanning
        issues = []
        rows = []
        self.scope = scope
        progress = ScanProgress()
        let d = days
        let skip: Set<String> = skipDev ? ["node_modules", ".git", "Caches"] : []
        let targets = defaultScanDirs(scope: scope)
        task = Task {
            let cutoff = Date().addingTimeInterval(Double(-d) * 86400)
            let r = await walkFiles(dirs: targets, olderThan: cutoff, top: 300, skipNames: skip,
                                      progress: self.progress)
            if !Task.isCancelled {
                self.count = r.matched
                self.rows = r.rows
                self.issues = walkIssues(r)
                self.scanning = false
                self.scanState = .completed
                self.scannedAt = Date()
            }
        }
    }

    func stop() {
        task?.cancel()
        if scanning { scanState = .stopped; scannedAt = Date() }
        scanning = false
    }

    // MARK: - C1/C2 trash API (docs/enhance-feat.md §11)

    /// Selected rows the tool may touch, as a confirmed plan. Each file must still have the size and
    /// modification time the scan saw, otherwise it is skipped as "changed since the scan".
    func trashPlan() -> [TrashPlanItem] {
        selected.filter { isReclaimableWhole($0.url) }.map {
            TrashPlanItem(url: $0.url, bytes: $0.size,
                          expected: FileSnapshot(allocatedBytes: $0.size, mtime: $0.mtime))
        }
    }

    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "old-files") else { return nil }
        apply(batch)
        return batch
    }

    /// Deselects everything and drops rows whose file is gone; the total shrinks with them.
    func apply(_ batch: TrashBatch) {
        let before = rows.count
        rows.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        for i in rows.indices { rows[i].selected = false }
        lose(before - rows.count)
    }
}
