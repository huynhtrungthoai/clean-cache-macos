import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class OrphansModel: ObservableObject, ScanStatusReporting {
    @Published var items: [OrphanItem] = []
    @Published var scanning = false
    @Published var appCount = 0
    @Published private(set) var started = false
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// 现场读数：这页慢在「逐个残留目录量体积」那一步，几分钟里没别的可看。
    private(set) var progress = ScanProgress()
    private var task: Task<Void, Never>? = nil

    var selected: [OrphanItem] { items.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + ($1.size ?? 0) } }
    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }

    /// 全选只扫「删了没影响」那批：这页的立脚点是宁可漏报不可误删，标「删了会丢数据」的意思是
    /// 「得你自己判」，一键把它带走等于把这页存在的理由按掉了。
    var selectAll: SelectAll? {
        let open = items.filter { $0.level != "warn" && isBulkSelectable($0.path) }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy(\.selected),
                         unselectable: items.count - open.count) { on in
            for i in self.items.indices where self.items[i].level != "warn" && isBulkSelectable(self.items[i].path) {
                self.items[i].selected = on
            }
        }
    }

    func scan() {
        task?.cancel()
        scanning = true
        started = true
        scanState = .scanning
        issues = []
        items = []
        progress = ScanProgress()
        task = Task {
            let (list, apps) = await scanOrphans(progress: self.progress)
            if !Task.isCancelled {
                self.items = list
                self.appCount = apps
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

    func trashPlan() -> [TrashPlanItem] {
        selected.filter { isReclaimableWhole($0.path) }
            .map { TrashPlanItem(url: $0.path, name: $0.name, bytes: $0.size ?? 0) }
    }

    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "leftovers") else { return nil }
        apply(batch)
        return batch
    }

    /// Deselects everything and drops leftovers that are gone.
    func apply(_ batch: TrashBatch) {
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path.path) }
        for i in items.indices { items[i].selected = false }
    }
}
