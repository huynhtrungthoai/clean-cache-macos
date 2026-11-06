import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class BigFilesModel: ObservableObject, ScanStatusReporting {
    @Published var rows: [FileRow] = []
    @Published var scanning = false
    @Published var limit = 30
    @Published var skipDev = true
    @Published var scopeNote: String? = nil
    /// 本轮实际用的范围，页头拿它贴标签：范围变了但没重扫时不能继续顶着旧标签说真话
    @Published private(set) var scope: ScanScope = .user
    /// 本次会话里扫过没有——区分「还没扫」和「扫了但没有」
    @Published private(set) var started = false
    /// 满足条件的文件总数（`all` 只是它最大的那 200 个，`rows` 又是 `all` 的前缀）
    @Published private(set) var count = 0
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// 现场读数：整盘范围一趟几分钟，这段时间里它是唯一能证明「在动」的东西。
    private(set) var progress = ScanProgress()
    private var task: Task<Void, Never>? = nil
    /// 遍历有界保留的候选集（最多 200 条）；rows 只是它的前 limit 条
    private var all: [FileRow] = []
    private var customDirs: [URL]? = nil

    var selected: [FileRow] { rows.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size } }

    /// 「全选」只管勾得动的那几行：本工具不碰的行选上也删不掉，全选后按清理只会换一屏报错。
    /// 一行都勾不动时返回 nil，按钮不画——画一颗点了没反应的按钮比没有更糟。
    var selectAll: SelectAll? {
        let open = rows.filter { isBulkSelectable($0.url) }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy(\.selected),
                         unselectable: rows.count - open.count) { on in
            for i in self.rows.indices where isBulkSelectable(self.rows[i].url) {
                self.rows[i].selected = on
            }
            self.syncBack()
        }
    }

    /// 总览跳过来的定向扫描；dirs == nil 回到默认范围
    func scan(scope: ScanScope, dirs: [URL]? = nil, note: String? = nil) {
        task?.cancel()
        scanning = true
        started = true
        scanState = .scanning
        issues = []
        rows = []
        all = []
        customDirs = dirs
        scopeNote = note
        self.scope = scope
        progress = ScanProgress()
        let skip: Set<String> = skipDev ? ["node_modules", ".git", "Caches"] : []
        let targets = dirs ?? defaultScanDirs(scope: scope)
        task = Task {
            let r = await walkFiles(dirs: targets, top: 200, skipNames: skip,
                                      progress: self.progress)
            if !Task.isCancelled {
                self.count = r.matched
                self.all = r.rows
                self.applyLimit()
                self.issues = walkIssues(r)
                self.scanning = false
                self.scanState = .completed
                self.scannedAt = Date()
            }
        }
    }

    func rescan(scope: ScanScope) { scan(scope: scope, dirs: customDirs, note: scopeNote) }

    func stop() {
        task?.cancel()
        if scanning { scanState = .stopped; scannedAt = Date() }
        scanning = false
    }

    /// 改「前 N」不重扫：勾选同步回候选集，再切一刀
    func applyLimit() {
        syncBack()
        rows = Array(all.prefix(limit))
    }

    /// 删完就地把没了的条目剔掉，不值得为此重走一遍全盘
    func pruneMissing() {
        syncBack()
        let before = all.count
        all.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        // 「扫到多少个」跟着减，否则对账句会一直说只列了前 N 个，而那时已经列全了
        count = max(all.count, count - (before - all.count))
        rows = Array(all.prefix(limit))
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
        guard let batch = await store.runTrash(trashPlan(), source: "big-files") else { return nil }
        apply(batch)
        return batch
    }

    /// Deselects everything and drops rows whose file is gone (moved or missing).
    func apply(_ batch: TrashBatch) {
        for i in rows.indices { rows[i].selected = false }
        pruneMissing()
    }

    /// rows 永远是 all 的前缀，按下标对齐写回
    private func syncBack() {
        for i in rows.indices where i < all.count { all[i] = rows[i] }
    }
}
