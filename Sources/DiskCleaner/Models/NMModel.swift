import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class NMModel: ObservableObject, ScanStatusReporting {
    @Published var items: [NMProject] = []
    @Published var scanning = false
    /// 上一轮是被**按停**的：列里只有量完的那几行，页头要说清这不是全貌。
    @Published var stoppedEarly = false
    @Published private(set) var started = false
    /// C2/C5. `issues` stays empty: the node_modules search does not report unreadable folders.
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// 现场读数。这一趟数的是**目录项**不是文件：整棵家目录翻下来一个 node_modules
    /// 都可能没撞上，但「正在看 ~/Projects/foo/src」那句是真的在往前走的证据。
    private(set) var progress = ScanProgress(counted: .entries)
    private var task: Task<Void, Never>? = nil
    /// 一轮一个号。按停后立刻重扫时，上一轮的尾巴批次还在路上，靠它挡住——
    /// 否则两轮的行会混进同一列，而那一列看着像「这台机器的依赖」。
    private var gen = 0

    var selected: [NMProject] { items.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    /// The folder a row stands for.
    static func nodeModulesURL(_ p: NMProject) -> URL {
        URL(fileURLWithPath: p.project).appendingPathComponent("node_modules")
    }

    /// Bulk selection follows `isBulkSelectable` on each project's node_modules folder.
    var selectAll: SelectAll? {
        let open = items.indices.filter { isBulkSelectable(Self.nodeModulesURL(items[$0])) }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy { items[$0].selected },
                         unselectable: items.count - open.count) { on in
            for i in open where i < self.items.count { self.items[i].selected = on }
            if !on { for i in self.items.indices { self.items[i].selected = false } }
        }
    }

    // MARK: - C1/C2 trash API (docs/enhance-feat.md §11)

    /// One item per selected project: its `node_modules` folder (rebuilt by the package
    /// manager). Folders are re-checked by existence and the deletion gate.
    func trashPlan() -> [TrashPlanItem] {
        selected.map { p in
            let u = Self.nodeModulesURL(p)
            return TrashPlanItem(url: u, name: URL(fileURLWithPath: p.project).lastPathComponent + "/node_modules",
                                 bytes: p.size)
        }.filter { isReclaimableWhole($0.url) }
    }

    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "node-modules") else { return nil }
        apply(batch)
        return batch
    }

    /// Drops projects whose node_modules is gone, clears the selection.
    func apply(_ batch: TrashBatch) {
        items.removeAll { !FileManager.default.fileExists(atPath: Self.nodeModulesURL($0).path) }
        for i in items.indices { items[i].selected = false }
    }

    func scan() {
        task?.cancel()
        gen += 1
        scanning = true
        started = true
        stoppedEarly = false
        scanState = .scanning
        items = []
        progress = ScanProgress(counted: .entries)
        let mine = gen
        task = Task {
            let list = await findNodeModules(progress: self.progress) { batch in
                Task { @MainActor in if self.gen == mine { self.merge(batch) } }
            }
            if !Task.isCancelled {
                if self.gen == mine { self.merge(list) }
                self.scanning = false
                self.scanState = .completed
                self.scannedAt = Date()
            }
        }
    }

    func stop() {
        task?.cancel()
        guard scanning else { return }
        scanning = false
        stoppedEarly = true
        scanState = .stopped
        scannedAt = Date()
    }

    /// 只合进**没见过的路径**，且按容量降序插位：行是同一批对象（`id` 不变，勾选不掉），
    /// 扫描途中也只是往下长，不整列重排。
    ///
    /// 一批一次赋值（而不是每行一次通知）：验收那句「刷新节流」按一次 diff 算，
    /// 125 行 39 批就是 39 次重画而不是 125 次。实测这条不影响耗时，也没能消掉 AppKit
    /// 那两条 `reentrant operation in its NSTableView delegate`（见 proofs 里的对照组）。
    private func merge(_ batch: [NMProject]) {
        guard !batch.isEmpty else { return }
        var seen = Set(items.map(\.project))
        var next = items
        for p in batch where !seen.contains(p.project) {
            seen.insert(p.project)
            next.insert(p, at: next.firstIndex { $0.size < p.size } ?? next.endIndex)
        }
        if next.count != items.count { items = next }
    }
}
