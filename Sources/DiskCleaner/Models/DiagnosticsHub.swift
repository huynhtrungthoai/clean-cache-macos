import DiskCleanerCore
import SwiftUI

/// 一次类别发现的三页数据 + 选择状态，由 `ScanStore` 持有。
/// 扫描结果必须是 App 级状态：侧栏切分支、页面视图随导航销毁，模型跟着视图走就会
/// 每切一次重跑一遍定向遍历（`DiskCleanerApp` 对全部八页的同一条教训）。
@MainActor
final class DiagnosticsHub: ObservableObject, ScanStatusReporting {
    @Published private(set) var hits: [CategoryHit] = []
    @Published private(set) var reports: [ReportFile] = []
    @Published private(set) var observation: [ObservationItem] = []
    @Published private(set) var scanning = false
    @Published private(set) var started = false
    /// C2/C5. `issues` stays empty: category discovery skips what it cannot read.
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    /// 流速徽标按 entryKey 挂在行上；异常粘滞到增长回落（评审 §2.1c）。
    @Published private(set) var velocity: [String: VelocityReport] = [:]
    /// 内容归属按 entryKey 挂在行上；探针关闭时恒为空（不装结论）。
    @Published private(set) var attribution: [String: AttributionOutcome] = [:]
    /// 本轮没有任何可比的基线：首扫或历史全在 10 分钟内，页头提一句「下次起可对比」。
    @Published private(set) var baselinePending = false
    @Published var hitSelection = Set<String>()
    @Published var reportSelection = Set<String>()
    private var task: Task<Void, Never>? = nil
    /// 快照库。库坏了静默降级——快照是增益不是地基， velocities 为空即没有流速可看。
    private lazy var snapshots: SnapshotStore = SnapshotStore(path: SnapshotStore.defaultPath())

    /// 侧栏「诊断与转储」分组出现的判据：两页都空就不占位（设计稿屏①：无命中整组不出现）。
    var hasFindings: Bool { !hits.isEmpty || !reports.isEmpty }

    var totalBytes: Int64 { hits.reduce(0) { $0 + $1.bytes } }
    var selectedHits: [CategoryHit] { hits.filter { hitSelection.contains($0.id) } }
    var selectedBytes: Int64 { selectedHits.reduce(0) { $0 + $1.bytes } }

    var reportBytes: Int64 { reports.reduce(0) { $0 + $1.size } }
    var selectedReports: [ReportFile] { reports.filter { reportSelection.contains($0.id) } }
    var selectedReportBytes: Int64 { selectedReports.reduce(0) { $0 + $1.size } }

    var hitSelectAll: SelectAll? {
        guard !hits.isEmpty else { return nil }
        return SelectAll(allSelected: hits.allSatisfy { hitSelection.contains($0.id) },
                         unselectable: 0) { on in
            if on { self.hitSelection = Set(self.hits.map(\.id)) } else { self.hitSelection = [] }
        }
    }

    var reportSelectAll: SelectAll? {
        guard !reports.isEmpty else { return nil }
        return SelectAll(allSelected: reports.allSatisfy { reportSelection.contains($0.id) },
                         unselectable: 0) { on in
            if on { self.reportSelection = Set(self.reports.map(\.id)) } else { self.reportSelection = [] }
        }
    }

    /// 定向遍历。`force` 供页内那颗重扫用；启动后首次调用由 `ContentView` 触发——
    /// 类别发现挂的是启动节奏，不是哪一页的懒扫描（评审 §2.2：侧栏计数不能鸡生蛋）。
    func discover(force: Bool = false) {
        guard force || !started else { return }
        task?.cancel()
        scanning = true
        scanState = .scanning
        started = true
        let home = homeDir()
        task = Task {
            let report = await discoverDiagnosticCategories(home: home)
            guard !Task.isCancelled else { return }
            hits = report.hits
            reports = report.userReports
            observation = report.observation
            hitSelection.formIntersection(Set(hits.map(\.id)))
            reportSelection.formIntersection(Set(reports.map(\.id)))
            self.applyVelocity(for: report.hits)
            self.applyAttribution(for: report.hits)
            scanning = false
            scanState = .completed
            scannedAt = Date()
        }
    }

    func stop() {
        task?.cancel()
        guard scanning else { return }
        scanning = false
        scanState = .stopped
        scannedAt = Date()
    }

    /// 本轮扫描的流速结算：算两档徽标、写快照。
    /// 基线是距今 ≥10 分钟的上一次扫描——连扫两次不换基线；Δ≤0 才撤徽标（粘滞）。
    private func applyVelocity(for hits: [CategoryHit]) {
        let scanID = UUID().uuidString
        let now = Date()
        let snaps = hits.map {
            ScanSnapshot(entryKey: $0.path, scanID: scanID, wallTime: now,
                         bytes: $0.bytes, fileCount: $0.files, newestMtime: $0.newest)
        }
        var next: [String: VelocityReport] = [:]
        var usedBaseline = false
        for s in snaps {
            if let base = snapshots.baseline(entryKey: s.entryKey, now: now, currentScanID: scanID) {
                usedBaseline = true
                let r = VelocityReport.compute(current: s, baseline: base)
                if r.tier != nil {
                    next[s.entryKey] = r
                } else if let prev = velocity[s.entryKey], r.deltaFiles > 0 || r.deltaBytes > 0 {
                    // 仍在涨但够不着阈值：保留上一轮的异常；回落（Δ≤0）自然落空
                    next[s.entryKey] = prev
                }
            }
        }
        snapshots.record(scanID: scanID, wallTime: now, snapshots: snaps)
        velocity = next
        baselinePending = !snaps.isEmpty && !usedBaseline
    }

    /// 内容归属：探针开着才做（默认关，评审 §2.3 的隐私边界）。
    /// 每条目抽 5 个样本，样本全一致才出「内容归属」，不一致标混合。
    private func applyAttribution(for hits: [CategoryHit]) {
        guard diagnosticProbeEnabled() else {
            attribution = [:]
            return
        }
        let probe = CrashpadProbe()
        var next: [String: AttributionOutcome] = [:]
        for hit in hits {
            let dirs = CategoryRule.crashDumps.safeDeleteSpec?.cleanTargets(under: URL(fileURLWithPath: hit.path)) ?? []
            let samples = probeSampleFiles(under: dirs)
            let results = samples.map { probe.probe($0) }
            next[hit.id] = resolveAttribution(directoryOwner: hit.host, results: results)
        }
        attribution = next
    }

    /// 清理后收行。行是先转淡再收的账本语义：搬走的立刻从这页消失。
    func removeHits(_ ids: Set<String>) {
        hits.removeAll { ids.contains($0.id) }
        hitSelection.subtract(ids)
    }

    func removeReports(_ ids: Set<String>) {
        reports.removeAll { ids.contains($0.id) }
        reportSelection.subtract(ids)
    }

    // MARK: 修剪三步流（PR-4）

    enum TrimState: Equatable {
        case preview(hitPath: String, plan: TrimPlan)
        case running(done: Int, total: Int)
        case done(bytes: Int64, skipped: Int, batchID: String)
    }

    @Published var trim: TrimState? = nil

    /// 第一步：纯算出终稿。预览数字即执行数字，确认后不重算。
    func prepareTrim(for hit: CategoryHit) {
        guard let retention = crashRetention() else { return }
        let dirs = CategoryRule.crashDumps.safeDeleteSpec?.cleanTargets(under: URL(fileURLWithPath: hit.path)) ?? []
        trim = .preview(hitPath: hit.path, plan: trimPlan(under: dirs, retention: retention))
    }

    /// 第二步：执行。逐项复核 dev/ino，与预览不一致的跳过（防偷换）；
    /// 全部走 trashItem 唯一删除路径，整批入账可撤销。
    func runTrim() {
        guard case .preview(let hitPath, let plan) = trim else { return }
        trim = .running(done: 0, total: plan.remove.count)
        let store = snapshots
        Task { @MainActor in
            let fm = FileManager.default
            var moved: [(original: URL, trash: URL, bytes: Int64)] = []
            var skipped = 0
            for (i, f) in plan.remove.enumerated() {
                var st = stat()
                if lstat(f.url.path, &st) != 0 || Int(st.st_dev) != f.dev || Int(st.st_ino) != f.ino {
                    skipped += 1
                } else if let dst = try? trashItem(f.url) {
                    moved.append((f.url, dst, f.size))
                } else {
                    skipped += 1
                }
                if i % 200 == 0 { self.trim = .running(done: i + 1, total: plan.remove.count) }
            }
            let batchID = UUID().uuidString
            store.recordTrim(batchID: batchID, at: Date(), entryKey: hitPath, items: moved)
            self.trim = .done(bytes: moved.reduce(0) { $0 + $1.bytes }, skipped: skipped, batchID: batchID)
            self.discover(force: true)
        }
    }

    /// 第三步的「撤销整批」：废纸篓里的原路搬回。反馈就是行回来了——
    /// discover(force:) 重算后列表自己会说话。
    func undoTrim(batchID: String) {
        _ = snapshots.undoTrim(batchID: batchID)
        trim = nil
        discover(force: true)
    }
}
