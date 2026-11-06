import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class DupModel: ObservableObject, ScanStatusReporting {
    @Published var groups: [DupGroup] = []
    /// 被受管环境摘走的副本，按组归堆。页顶那句「不参与比对」点开的就是这份名单：
    /// 整组撤下的那些不列进主列表，但必须看得见，否则像偷偷藏东西。
    @Published private(set) var envGroups: [EnvDupGroup] = []
    @Published var scanning = false
    @Published var phase = ""
    /// 现场读数：这一页先遍历再哈希，遍历那几分钟里唯一能证明「在动」的就是它。
    private(set) var progress = ScanProgress()
    @Published var minMB = 20
    @Published var selection: Set<String> = []   // 选中待删的文件 path
    /// 本轮实际用的范围，页头贴标签用
    @Published private(set) var scope: ScanScope = .user
    @Published private(set) var started = false
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// Modification date of every listed copy (path → date), read off the main thread after the
    /// scan. The first file of each group is the newest one and is the copy that is kept.
    @Published private(set) var dates: [String: Date] = [:]
    private var task: Task<Void, Never>? = nil

    var waste: Int64 { groups.reduce(0) { $0 + $1.waste } }
    var envBytes: Int64 { envGroups.reduce(0) { $0 + $1.bytes } }
    var selectedCount: Int { selection.count }

    func scan(scope: ScanScope) {
        task?.cancel()
        scanning = true
        started = true
        self.scope = scope
        groups = []
        envGroups = []
        selection = []
        dates = [:]
        scanState = .scanning
        issues = []
        let minB = Int64(minMB) * MB
        let targets = defaultScanDirs(scope: scope)
        task = Task {
            self.phase = L("Walking files…")
            self.progress = ScanProgress()
            // 只留下我们删得动的：整盘扫描会走进 /Library、/opt 这些 root 地盘，
            // 那些重复归包管理器管，列出来只会让用户去点一个注定失败的勾选框。
            let walk = await walkFiles(dirs: targets, minSize: minB,
                                       skipNames: ["node_modules", ".git", "Caches"],
                                       progress: self.progress)
            let files = walk.rows.filter(\.deletable)
            if Task.isCancelled { return }
            self.phase = LF("Comparing contents (%@ candidates)…", String(files.count))
            // 哈希是同步重活，扔后台线程做
            let r = await Task.detached { findDupGroups(files) }.value
            if !Task.isCancelled {
                self.groups = r.groups
                self.envGroups = r.excluded
                let urls = r.groups.flatMap(\.files)
                self.dates = await Task.detached {
                    Dictionary(urls.map { ($0.path, fileDate($0)) }, uniquingKeysWith: { a, _ in a })
                }.value
                self.scanning = false
                self.phase = ""
                self.issues = walkIssues(walk)
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

    /// Selected extra copies as a plan. Each one names the kept copy (first of its group); right
    /// before moving, the kept copy must still exist with identical content or the extra is skipped.
    func trashPlan() -> [TrashPlanItem] {
        groups.flatMap { g -> [TrashPlanItem] in
            guard let kept = g.files.first else { return [] }
            return g.files.dropFirst()
                .filter { selection.contains($0.path) && isReclaimableWhole($0) }
                .map { TrashPlanItem(url: $0, bytes: g.size, keptCopy: kept) }
        }
    }

    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "duplicates") else { return nil }
        apply(batch)
        return batch
    }

    /// Clears the selection, removes copies that are gone and drops groups left with one copy.
    func apply(_ batch: TrashBatch) {
        selection = []
        for i in groups.indices {
            groups[i].files.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        }
        groups.removeAll { $0.files.count < 2 }
    }

    /// 「全选」只管多余的那几份，每组保留的那一份算在「不在全选范围内」里：
    /// 它列在同一个组里却永远勾不动，不报这个数用户只会以为漏勾了一份。
    /// 反向也必须能按——这一页动辄几百项，一次勾错没有一键撤回路可走不通。
    var selectAll: SelectAll? {
        let extras = groups.flatMap { $0.files.dropFirst() }.filter { isBulkSelectable($0) }
        guard !extras.isEmpty else { return nil }
        return SelectAll(allSelected: extras.allSatisfy { selection.contains($0.path) },
                         unselectable: groups.count) { on in
            self.selection = on ? Set(extras.map(\.path)) : []
        }
    }
}
