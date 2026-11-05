import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class CachesModel: ObservableObject, ScanStatusReporting {
    /// 这台只管知识库里的那几组（见 `CachesPage`）。
    let groupKeys: Set<String>
    init(groupKeys: Set<String> = ["general", "cn_app"]) { self.groupKeys = groupKeys }

    @Published var items: [CacheItem] = []
    @Published var scanning = false
    @Published private(set) var started = false
    @Published private(set) var completed = false
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// 现场读数：这一页慢在逐个缓存目录量体积，27 条能走一两分钟。
    private(set) var progress = ScanProgress()
    private var task: Task<Void, Never>? = nil

    var selected: [CacheItem] { items.filter { $0.selected && $0.size != nil } }

    /// 勾了的这些条目**实际**占多少：路径互相套着的只数最外面那层。
    ///
    /// 按条目各自的 `size` 相加会虚高 —— 演示树上全选打印过 38.6 GB，
    /// 而真实能腾出的是 33.1 GB，差的 5.5 GB 全是同一份字节被数了两遍。
    var selectedBytes: Int64 { contentsUnionSize(pathSizes(of: selected)) }

    /// 「全选」这一按到底能带走多少，给卡下面那句对账话用。
    var selectableBytes: Int64 { contentsUnionSize(pathSizes(of: openItems)) }

    /// 全选只管「勾得动又不催你自己判」的那批，也就是「删了没影响」那一档：另两档
    /// （要重新下载 / 会丢数据）都要用户自己过目，一键把它带走等于替用户拍了他该拍的板。
    /// 体积没量出来的也不能选——选了也不知道能腾出多少，确认框里会写成一个假数。
    private var openItems: [CacheItem] { items.filter(cacheLit) }

    var selectAll: SelectAll? {
        let open = openItems
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy(\.selected),
                         unselectable: items.count - open.count) { on in
            let ids = Set(open.map(\.id))
            for i in self.items.indices where ids.contains(self.items[i].id) {
                self.items[i].selected = on
            }
        }
    }

    /// 有几条目的路径正套在别的条目底下。0 就不说，非 0 必须说：
    /// 那一列相加比底部那个数大，用户第一个怀疑的就是数字是编的。
    var overlapCount: Int {
        let kept = Set(dropNested(pathSizes(of: items).map(\.path)))
        return items.filter { !$0.pathSizes.keys.allSatisfy(kept.contains) }.count
    }

    func load(force: Bool = false) {
        if started && !force { return }
        task?.cancel()
        started = true
        completed = false
        scanning = true
        scanState = .scanning
        issues = []
        progress = ScanProgress()
        task = Task {
            let entries = loadSafetyEntries(from: safetyDBFileURL())
                .filter { groupKeys.contains($0.grp ?? "general") }
            var list: [CacheItem] = []
            for e in entries {
                if Task.isCancelled { break }
                let paths = globExpand(e.path.isEmpty ? "~/.nonexistent-\(UUID().uuidString)" : e.path)
                if paths.isEmpty { continue }   // 没装的 App 不显示
                list.append(CacheItem(entry: e, resolvedPaths: paths))
            }
            // 常规缓存排前面
            list.sort { ($0.groupKey != "general" ? 1 : 0, $0.entry.name) < ($1.groupKey != "general" ? 1 : 0, $1.entry.name) }
            self.items = list
            // 并行统计大小。逐路径记账而不只留一个和：总览那条环形要把同一条目的
            // 几处缓存拆到不同的弧上去归账，只有一个总数就拆不开。
            await withTaskGroup(of: (UUID, [String: DirScan]).self) { group in
                for it in list {
                    group.addTask {
                        var per: [String: DirScan] = [:]
                        for p in it.resolvedPaths {
                            if Task.isCancelled { break }
                            per[p.path] = await pathStat(p, progress: self.progress)
                        }
                        return (it.id, per)
                    }
                }
                for await (id, per) in group {
                    if Task.isCancelled { break }
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[i].pathSizes = per.mapValues(\.bytes)
                        self.items[i].size = per.values.reduce(Int64(0)) { $0 + $1.bytes }
                        self.items[i].files = per.values.reduce(0) { $0 + $1.files }
                        self.items[i].newest = per.values.compactMap(\.newest).max()
                        self.items[i].unreadablePaths = per.values.flatMap { $0.needFullDiskAccess + $0.needAdmin }
                    }
                }
            }
            // 有体积的排前面
            self.items.sort {
                let a = $0.size ?? -1, b = $1.size ?? -1
                if a != b { return a > b }
                return $0.groupKey < $1.groupKey
            }
            // 量到 0 字节的行不留：勾不动、也不进任何账，留着只会让页头那句「N 项可查」
            // 跟台账上的「· M 项」对不上（2026-09-28 本机实拍 16 vs 14，差的是空的 iOS
            // 备份目录和空的 AVD 目录）。size 为 nil = 还没量完，不删。
            // Rows that could not be read stay (C3: "could not measure" is not "empty").
            if !Task.isCancelled { self.items.removeAll { $0.size == 0 && $0.unreadablePaths.isEmpty } }
            if !Task.isCancelled {
                self.completed = true
                self.scanning = false
                self.scanState = .completed
                self.scannedAt = Date()
                self.issues = permissionIssues(self.items.flatMap(\.unreadablePaths))
            }
        }
    }

    func stop() {
        task?.cancel()
        if scanning { scanState = .stopped; scannedAt = Date() }
        scanning = false
    }

    // MARK: - C3 API (docs/enhance-feat.md §11)

    /// What the row may show: measuring / measured bytes / could not measure (never "0 B").
    func rowState(_ id: UUID) -> CacheRowState {
        guard let it = items.first(where: { $0.id == id }) else { return .unmeasurable }
        return cacheRowState(it)
    }

    /// The exact items a "Move to Trash" of the current selection executes (review sheet shows
    /// this list). Nested selections collapse into the outermost path; sizes are measured ones.
    func trashPlan() -> [TrashPlanItem] {
        var names: [String: String] = [:]
        for it in selected {
            for u in it.resolvedPaths where names[u.standardizedFileURL.path] == nil {
                names[u.standardizedFileURL.path] = L(it.entry.name)
            }
        }
        return cacheTrashPlan(selected).map {
            TrashPlanItem(url: $0.url, name: names[$0.url.standardizedFileURL.path], bytes: $0.bytes)
        }
    }

    /// Runs the plan through `AppStore.runTrash` (preflight, off main thread, batch history),
    /// then updates the rows. nil = another run in progress or nothing selected.
    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "caches") else { return nil }
        apply(batch)
        return batch
    }

    /// Clears the selection and re-measures every row touched by the batch.
    func apply(_ batch: TrashBatch) {
        for i in items.indices { items[i].selected = false }
        refresh(after: batch.entries.map(\.item.path))
    }

    private var remeasureTasks: [UUID: Task<Void, Never>] = [:]

    /// Re-resolve and re-measure every row touched by trashing `paths`.
    private func refresh(after paths: [String]) {
        for i in cacheItemsTouched(items, by: paths) {
            let left = items[i].resolvedPaths.filter { FileManager.default.fileExists(atPath: $0.path) }
            items[i].resolvedPaths = left
            items[i].unreadablePaths = []
            if left.isEmpty {
                items[i].size = 0
                items[i].pathSizes = [:]
                items[i].files = 0
                continue
            }
            items[i].size = nil
            let id = items[i].id
            remeasureTasks[id]?.cancel()
            remeasureTasks[id] = Task { [weak self] in
                var per: [String: DirScan] = [:]
                for p in left {
                    if Task.isCancelled { return }
                    per[p.path] = await pathStat(p)
                }
                guard let self, !Task.isCancelled,
                      let j = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[j].pathSizes = per.mapValues(\.bytes)
                self.items[j].size = per.values.reduce(Int64(0)) { $0 + $1.bytes }
                self.items[j].files = per.values.reduce(0) { $0 + $1.files }
                self.items[j].newest = per.values.compactMap(\.newest).max()
                self.items[j].unreadablePaths = per.values.flatMap { $0.needFullDiskAccess + $0.needAdmin }
                self.remeasureTasks[id] = nil
            }
        }
    }
}

/// 这一行亮不亮「删了没影响」那一档。体积还没量出来的不亮（那是「还不知道」，
/// 不是「删了没事」）；要重下和会丢数据的那两档也不亮——全选不碰它们，
/// 就不该给批量带走的暗示。判据走 `tier` 而不是 `level` 的字符串：
/// 页头那三档账也是从 `tier` 加出来的，两处同源才不会出现「行里不亮、账里算进没影响」。
func cacheLit(_ it: CacheItem) -> Bool {
    (it.size ?? 0) > 0 && it.entry.tier == .safe
}

/// 一组条目名下所有解析路径各自的字节（父目录那个数本来就含着它下面的子目录）。
func pathSizes(of items: [CacheItem]) -> [(path: String, bytes: Int64)] {
    items.flatMap { $0.pathSizes.map { (path: $0.key, bytes: $0.value) } }
}
