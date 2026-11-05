import SwiftUI
import AppKit
import DiskCleanerCore

@MainActor
final class UninstallModel: ObservableObject, ScanStatusReporting {
    /// 可卸载的那几份，按名字排好。系统目录里的与链接形态的不在这里。
    @Published private(set) var apps: [InstalledApp] = []
    /// 盘点到几份（含搬不动的），页头那句「对过 N 个应用」用它
    @Published private(set) var scanned = 0
    @Published private(set) var scanning = false
    @Published private(set) var started = false
    @Published var query = ""
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []

    /// 右边这一栏此刻说的是谁
    @Published private(set) var current: InstalledApp? = nil
    @Published var items: [AppDataItem] = []
    @Published private(set) var bundleBytes: Int64? = nil
    /// 两个以上 App 都认领、因此谁都不删的那几处（只用来解释「为什么这一处没算给你」）
    @Published private(set) var sharedPaths: [URL] = []
    @Published private(set) var planning = false

    /// 全量盘点。**匹配用它，不只用 `apps`**：共用目录的另一位主人可能是个系统 App。
    private(set) var inventory: AppInventory? = nil
    private(set) var progress = ScanProgress()
    private(set) var planProgress = ScanProgress()

    private var scanTask: Task<Void, Never>? = nil
    private var planTask: Task<Void, Never>? = nil

    var shown: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.contains(q) }
    }

    var selectedBytes: Int64 { items.reduce(0) { $0 + ($1.selected ? ($1.size ?? 0) : 0) } }
    /// 这一趟要搬走多少：本体 + 勾上的数据
    var totalBytes: Int64 { (bundleBytes ?? 0) + selectedBytes }
    var moveCount: Int { 1 + items.filter(\.selected).count }

    /// 本工具自己那几份：包名跟正在跑的这份一致就是自己，不论装在哪、是哪一版。
    /// 商店版在 /Applications、手上跑的是开发版，两个包路径不同但同一个身份。
    /// 包名不同的副本（旧 key 签的、复制的另一版）是另一件事，照常可卸。
    static var ownBundleID: String { (Bundle.main.bundleIdentifier ?? "").lowercased() }

    func isSelf(_ app: InstalledApp) -> Bool {
        !Self.ownBundleID.isEmpty && app.bundleID.lowercased() == Self.ownBundleID
    }

    /// 这一页真正动得了的份数。页头那句「其中 N 个可以卸载」用它——
    /// 自己那一行还列着（置灰），但不该算进「可以卸载」。
    var uninstallableCount: Int { apps.filter { !isSelf($0) }.count }

    func scan() {
        scanTask?.cancel()
        planTask?.cancel()
        scanning = true
        started = true
        scanState = .scanning
        issues = []
        apps = []
        scanned = 0
        inventory = nil
        clearPlan()
        progress = ScanProgress()
        let p = progress
        scanTask = Task {
            let inv = await inventoryApps(progress: p)
            if Task.isCancelled { return }
            self.inventory = inv
            // 沙盒渠道（商店版）只列家目录里的：`/Applications` 搬不动，列出来按了必失败。
            // 页头那个数跟着同一把尺子，否则会出现「盘点了 100 个，其中 0 个可以卸载」。
            let inScope = inv.apps.filter { isInUninstallScope($0.path) }
            self.scanned = inScope.count
            // 自己那一份留在列表里、置灰，不删掉这一行：列表少一行没人说得清是为什么，
            // 而「这一行动不了」本身就是要说清楚的事。判据是包名——商店版装在 /Applications、
            // 手上跑的是开发版，两个包不同路径但同一个身份，都算「自己」。
            // 包名不同的副本（旧 key 签的、复制的另一版）是另一件事，照常可卸。
            self.apps = inScope.filter(\.canUninstall)
            self.scanning = false
            self.scanState = .completed
            self.scannedAt = Date()
        }
    }

    func stop() {
        scanTask?.cancel()
        planTask?.cancel()
        if scanning { scanState = .stopped; scannedAt = Date() }
        scanning = false
        planning = false
    }

    /// 点了左边某一行：量它的本体，再逐处认领它的数据。
    ///
    /// 一次只量一个 App——Xcode 那种本体上百万个文件，列表里若为显示体积先全量一遍，
    /// 点开这一页要先等几分钟。
    func choose(_ app: InstalledApp?) {
        planTask?.cancel()
        guard let app, !isSelf(app), let inv = inventory else { clearPlan(); return }
        current = app
        items = []
        bundleBytes = nil
        sharedPaths = []
        planning = true
        planProgress = ScanProgress()
        let p = planProgress
        planTask = Task {
            let plan = await scanUninstall(app, inventory: inv, progress: p)
            if Task.isCancelled { return }
            self.items = plan.items
            self.bundleBytes = plan.bundleBytes
            self.sharedPaths = plan.sharedPaths
            self.planning = false
        }
    }

    /// 卸完一份：它从列表里消失，右边回到「选一个」那一屏。
    func drop(_ app: InstalledApp) {
        apps.removeAll { $0.id == app.id }
        if current?.id == app.id { clearPlan() }
    }

    // MARK: - C4: running apps (docs/enhance-feat.md §11, owner decision 05/11/2026)

    enum AppRunState: Equatable {
        case notRunning
        case running(pids: [pid_t])
    }

    enum QuitResult: Equatable {
        case quit
        /// The quit request could not be delivered or the app/user declined it.
        case refused
        /// Still running after the wait (often an unsaved-document dialog). Never force-quit.
        case timedOut
    }

    func runState(of app: InstalledApp) -> AppRunState {
        let pids = runningInstances(of: app).map(\.processIdentifier)
        return pids.isEmpty ? .notRunning : .running(pids: pids)
    }

    /// Asks the app to quit normally (like Cmd-Q) and waits up to `timeout` seconds.
    /// The view calls this only after the user chose "Quit and uninstall".
    func requestQuit(_ app: InstalledApp, timeout: TimeInterval = 10) async -> QuitResult {
        let running = runningInstances(of: app)
        guard !running.isEmpty else { return .quit }
        guard running.allSatisfy({ $0.terminate() }) else { return .refused }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningInstances(of: app).isEmpty { return .quit }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return runningInstances(of: app).isEmpty ? .quit : .timedOut
    }

    private func runningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        let target = app.path.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { r in
            (!app.bundleID.isEmpty && r.bundleIdentifier?.lowercased() == app.bundleID.lowercased())
                || r.bundleURL?.standardizedFileURL.path == target
        }
    }

    // MARK: - C1/C2 trash API

    /// The app bundle first (critical: if it is not moved, its data is left alone), then the
    /// selected data locations. Empty for CleanPilot itself or when nothing is planned.
    func trashPlan() -> [TrashPlanItem] {
        guard let app = current, !isSelf(app) else { return [] }
        var plan = [TrashPlanItem(url: app.path, name: app.name, bytes: bundleBytes ?? 0, critical: true)]
        plan += items.filter { $0.selected && isReclaimableWhole($0.path) }
            .map { TrashPlanItem(url: $0.path, name: $0.name, bytes: $0.size ?? 0) }
        return plan
    }

    enum UninstallOutcome {
        case done(TrashBatch)
        /// Ask the user "Quit and uninstall / Cancel", then `requestQuit`, then call again.
        case appRunning(AppRunState)
        /// Another trash run is in progress.
        case busy
        /// No app chosen, plan still being prepared, or the app is CleanPilot itself.
        case nothingToDo
    }

    /// Uninstalls the chosen app with its selected data. Refuses while the app is running.
    func uninstall(using store: AppStore) async -> UninstallOutcome {
        guard let app = current, !isSelf(app), !planning else { return .nothingToDo }
        let state = runState(of: app)
        if case .running = state { return .appRunning(state) }
        guard let batch = await store.runTrash(trashPlan(), source: "uninstall") else { return .busy }
        apply(batch, app: app)
        return .done(batch)
    }

    /// Bundle moved → the app leaves the list. Otherwise only moved data rows disappear.
    func apply(_ batch: TrashBatch, app: InstalledApp) {
        let movedPaths = Set(batch.moved.map(\.item.path))
        if movedPaths.contains(app.path.path) {
            drop(app)
        } else {
            items.removeAll { movedPaths.contains($0.path.path) }
        }
    }

    private func clearPlan() {
        current = nil
        items = []
        bundleBytes = nil
        sharedPaths = []
        planning = false
    }
}
