import SwiftUI
import AppKit
import Combine
import DiskCleanerCore

@main
struct DiskCleanerApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        // Release builds: drop every DISKWISE_* developer hook before anything reads it
        // (screenshot hooks can trash files without a confirm; the home shim moves the
        // deletion boundary). @StateObject initialisers run later, so this is first.
        scrubDevEnvironment()
        // 截图模式自己 exit，不会回到这里往下走
        if let outDir = SnapshotMode.requestedDir { SnapshotMode.run(outDir: outDir) }
        // 沙盒版：先把上次的家目录授权续上，晚一步就会有页面拿容器路径去扫描
        HomeAccess.restore()
        // Introduce the simpler local workflow once; later language choices remain respected.
        if !UserDefaults.standard.bool(forKey: "diskcleaner.simpleUI.v1") {
            L10n.setChoice(.vi)
            L10n.apply(.vi)
            Prefs.shared.finishFirstRun()
            Prefs.shared.finishGuide()
            UserDefaults.standard.set(true, forKey: "diskcleaner.simpleUI.v1")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(themeManager)
                // 皮肤走 Environment：换肤只改色，不重建子树、不重跑扫描
                .themed(themeManager.effective)
                .preferredColorScheme(themeManager.effectiveScheme)
                .tint(themeManager.effective.palette.tint)
                // 初始尺寸要写死在这里：macOS 13 的窗口拿内容的「理想尺寸」当初始尺寸，
                // 而 ScrollView/List 把整列内容的完整高度报成理想尺寸——不钉这一行的话，
                // 打开总览是 1040×979，点进 Docker 变成 900×620，每切一页窗口跳一次。
                //
                // `minWidth` 900 → 1000：这一屏报上来的理想宽比 1000 还小，于是开窗宽整个
                // 塌在 `minWidth` 那一档上，**默认打开的就是最小窗**（2026-09-28 实拍：
                // 清空存档后 fresh launch 仍是 900x700）。900 那一档英雄区只剩 avail 628，
                // 环被右边那本账挤到 248，掉在弧上标签与盘心两行口径的闸门（260，
                // `Components.swift` 的 `arcLabel`）以下——招牌屏一打开就是一个没数的小饼。
                // 1000 这档环 348，标签和盘心都在。最小窗仍是 1000：1280 宽的屏放得下。
                .frame(minWidth: 1000, idealWidth: 1080, minHeight: 560, idealHeight: 700)
        }
        // 系统那条 unified 标题栏我们一个字都不用：它会把窗口标题再画一遍，
        // 而每一页页头本来就有标题——两行同义反复叠在一起就是重影。
        // 隐藏标题栏后内容顶到窗口边，红绿灯那一条改由我们自己让（见 ChromeStrip）。
        .windowStyle(.hiddenTitleBar)
        // ⌘, 是 macOS 用户找设置的落点，稿子①的判据就是「按 ⌘, 真能打开这一屏」。
        // 不换窗口、不开第二个壳：这一屏本来就在侧栏里，按了就把它带到那一行。
        // 一个窗口都没有时先把 App 激活，落点存着不丢，下一扇窗开起来时接住
        // （见 `ContentView.onAppear` 那条 drain）。
        //
        // 样稿那张 ⌘K 命令面板**不搬**（2026-10-22 判定，理由留在这儿免得下次重推）：
        // 面板列的九条里六条已经有直达键、且就在当前这一屏——⌘? 清理说明、⌘, 设置、
        // ⌘R 重新扫描（`SharedViews` 那颗钮带着 `shortcut`）、⌘↵ 移进废纸篓、空格预演、
        // Esc 退出。「切菜单取色 ⌘M」和 G-F/G-N/G-T 跳页是样稿讲环时的演示，产品里侧栏
        // 常驻，不该再拿一个面板当目录。唯一确实没接的是撤销：它属于刚清完那一屏和废纸篓
        // 页那一行，给一个只在"有上一步可回"时才成立的动作挂全局键，等于在其余时间里
        // 留一颗按下去只会响一声的键。
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L("Settings")) {
                    // 和点侧栏同一条：换目的地，顺手把导航历史压成只有这一站。
                    store.resetNav(to: .menuLaunch)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // 稿子②那句「? 打开清理说明」。系统那条「DiskWise 帮助」是死路：这个包里没有
            // help book，按下去只会响一声。所以把「帮助」这一整组换成我们自己那一屏——
            // 用户按 ⌘? 或打开「帮助」菜单，落点都是「这一版哪几处和上一版不一样」。
            // 键写在菜单上而不是裸 `?`：裸 `?` 会先进菜单键等价这一层，把反馈邮箱里那个
            // 问号吃掉（稿子的 `?` 是无修饰键，网页里不会跟输入框抢，原生窗口里会）。
            CommandGroup(replacing: .help) {
                Button(L("How cleaning works")) {
                    Prefs.shared.reopenGuide()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

// 扫描结果是 App 级状态：页面视图随导航销毁，模型不能跟着一起销毁，
// 否则每切一次 tab 就重走一遍全盘——切来切去卡的就是这个。
@MainActor
final class ScanStore: ObservableObject {
    let smart = CachesModel(groupKeys: ["general", "cn_app", "dev"])
    let overview = OverviewModel()
    let big = BigFilesModel()
    let old = OldFilesModel()
    let dup = DupModel()
    let nodemodules = NMModel()
    let docker = DockerModel()
    let caches = CachesModel(groupKeys: ["general", "cn_app"])
    let devcache = CachesModel(groupKeys: ["dev"])
    let orphans = OrphansModel()
    /// 卸载 App。同上：盘点结果要留住——切走再回来不该重扫一遍 99 个 App。
    let uninstall = UninstallModel()
    /// 文件夹下钻。由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁——
    /// 从某个文件夹跳去总览看一眼再回来，不该把刚量好的那一层白扔。
    let folderDrill = FolderDrillModel()
    /// 诊断与转储三页共用一个数据源：一次定向遍历喂崩溃转储、诊断报告与观察区，
    /// 分三页各取各的。挂在 ScanStore 而不是各页自己的 @StateObject，理由同上。
    let diagnostics = DiagnosticsHub()
    /// Trash page (C1 Request): measuring, open in Finder, empty after confirmation.
    let trash = TrashModel()
    /// V2-DEV: Dev Cleanup center over `devcache` + `nodemodules` (no scan or selection of its own).
    let dev: DevCleanupModel
    /// V2-DEV layer 2: per-project build output / venvs (listed, ticked by hand).
    let devArtifacts = DevArtifactsModel()

    init() {
        dev = DevCleanupModel(caches: devcache, nodeModules: nodemodules, artifacts: devArtifacts)
        // 总览那个「还能腾出多少」要报真数，而真数的来源是缓存知识库量出来的那些处。
        // 两个模型都由这里持有，所以接线放在这一层，不让 OverviewModel 去摸 store。
        overview.bind(caches: [caches, devcache])
        forward(smart)
        // 侧栏那几格容量要跟着各页变，而各页的模型是 8 个独立的 ObservableObject：
        // 把它们的 willChange 转发上来，持有 ScanStore 的那一层才重画。
        forward(overview); forward(big); forward(old); forward(dup)
        forward(nodemodules); forward(docker); forward(caches); forward(orphans)
        forward(devcache)
        forward(folderDrill)
        forward(uninstall)
        forward(diagnostics)
        forward(trash)
    }

    private var bag = Set<AnyCancellable>()

    private func forward<T: ObservableObject>(_ model: T) {
        model.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }
}

/// 历史里的一站。
///
/// 两截：去了哪一页，以及**页内落在哪一层**。下钻页里往里进一层也是一次跳转，
/// 只记页名的话退回来会落在这棵树的入口，而不是刚才站着的那一层。
struct NavStop: Equatable {
    var panel: AppPanel
    var drillPath: String? = nil
}

// 全 App 共享：废纸篓历史（撤销用）+ 顶部提示条 + 跨页跳转
@MainActor
final class AppStore: ObservableObject {
    @Published var trashHistory: [TrashRecord] = []
    @Published var notice: String? = nil
    @Published var jumpTo: AppPanel? = nil
    @Published var bigScanDir: URL? = nil   // 总览跳过来的定向扫描目录
    /// 「进这个文件夹往下看」——文件夹下钻页要落到哪一层。
    ///
    /// 跟 `jumpTo` 分工：这个只说「看哪儿」，切页由 `arrive(_:)` / `resetNav(to:)` 一起做。
    /// 分开是因为从总览、大文件、下钻页三处都能发起下钻，而「跳页」这件事只有一处该管。
    @Published var folderDrillPath: String? = nil
    /// 走到过的地方。**栈顶就是此刻这一屏**，这是「返回」的全部依据。
    ///
    /// `jumpTo` 是消费一次就清空的命令，答不了「我从哪儿来」，所以来源得单独记一本。
    /// 两种入口分得很清楚：侧栏点页与面包屑首格是「根」入口，走 `resetNav(to:)`
    /// 把历史压成只有那一站；内容里每一次跳转（深挖、点文件夹名、下钻页里进/退）
    /// 都走 `arrive(_:)`。这条界线就是「返回」的边界——重新挑目的地，
    /// 不该还能倒着走回去。
    ///
    /// 去重和截断的规则在 `NavStack` 里，由自检钉住；这里只管把它接到界面上。
    private var nav = NavStack<NavStop>(first: NavStop(panel: .smart))
    /// 第一站只认第一次 `seedNav`：窗重新出现时不能把走过的历史清掉。
    private var navSeeded = false
    /// 每走一步 +1。下钻页据此重新对账自己在哪一层。
    ///
    /// 光听 `folderDrillPath` 不够：后退时落点可能和来处**恰好是同一个值**
    /// （比如从 A 进到 A/B 再退回来，中间那一段被截掉了），
    /// 值没变 onChange 就不响，界面会停在子目录上不动。
    @Published private(set) var navPulse = 0
    /// 让总览页就地摊开某个名字的那一行，读完即清空。
    /// 现在只有截图链路会写它（`DISKWISE_DRILL`）：摊开出来的下级要点下去才看得见，
    /// 而批量拍图这一路没有键鼠。走的仍是行上那颗箭头调的同一个方法，不是另画的假界面。
    @Published var overviewDrill: String? = nil
    /// 让总览页把某一格就地摊开：`rest` = 「其他已统计」那一格（`restnote` 是它的旧名，两者同指此处），
    /// `gap` = 「没量到」那一格，其余值当作某个目录的完整路径，摊开它的下一级。
    /// 同样只有截图链路会写（`DISKWISE_JUMP`），走的仍是行首那颗 `▸` 调的同一个方法（`openDrill`），
    /// 所以拍出来的那一张连带是下钻态：环收成参照盘。
    @Published var overviewJump: String? = nil
    /// 让画面上那一页按一次底部清理条的「全选 / 取消全选」：每 +1 就按一次。
    /// 只有截图链路会写（`DISKWISE_PICK`），因为批量拍图这一路没有键鼠，
    /// 而「勾上 170 项之后撤得回来」这件事只有真按一次才照得出来。
    /// 按下的就是那颗按钮自己的 action，不是另画的假界面。
    @Published var selectAllPulse = 0
    /// 让画面上那一页把「不参与比对的组」那份名单弹出来：每 +1 就点一次页顶那句。
    /// 同样只有截图链路会写（`DISKWISE_SHEET`）。名单只在点开后才存在，而这一路没有键鼠，
    /// 按的仍是那句 `EnvCopiesClause` 自己的 action。
    @Published var envListPulse = 0
    /// 「整盘重扫了一轮」的脉冲：每 +1 表示总览那颗按钮刚被按下。
    ///
    /// 总览自己会就地作废它摊开出来的下一级（`dropChildren`），但**别的页**手里那些
    /// 「进过的层」还挂着上一轮的数——文件夹详情就是一个，它进过的每一层都存在自己
    /// 那个 `cache` 里。盘的账已经变了，隔着一轮扫描还拿旧数当今天的账看，
    /// 正是「手动重扫」这个动作要消灭的东西。各页自己监听这个数去作废各自的缓存，
    /// 谁也不必认识谁。
    @Published var rescanPulse = 0
    /// 把总览那一屏当前摊开的明细收回去。行首那颗 `▸` 的收起路径就是再点一次同一行，
    /// 截图这一路点不到它，所以每 +1 让视图自己走一遍同一颗 `setDrill(nil)`。
    @Published var overviewCollapsePulse = 0
    /// 让总览页对环上某一条弧**真点一下**：`arm` = 挑一条动得了的弧（上膛或搬走，
    /// 取决于它此刻是否已经上膛），`refuse` = 挑一条动不了的弧看它怎么解释自己。
    /// 只有截图链路会写（`DISKWISE_RING`），走的仍是弧上 `onTapGesture` 那个
    /// `tapArc`——两段式确认、3.2 秒自动解除、真 `trashItem` 全都在链路上，
    /// 不是另画一张「看起来像上膛了」的假界面。
    /// 值 `rescan` 是另一个用途：重跑一趟扫描，好拍「扫描途中」那一帧（光束钉在
    /// 量到的边界上这件事，只有那一帧能证明）。
    @Published var overviewRing: String? = nil
    /// 首次清理流程的截图口令：`open` / `confirm` / `run` / `undo` / `close`。
    /// 只有截图链路会写（`DISKWISE_CLEAN`），走的仍是页面上那几颗按钮自己的方法，
    /// 不另画一条「看起来像确认页」的假路。
    @Published var overviewClean: String? = nil
    /// 扫描范围。界面上没有开关：两档的账画在同一屏，人就会拿用户区的环形去对整盘的列表，
    /// 对不上就直接不信这屏的数（实测过）。所以永远走这一版能扫到的最大范围，
    /// 沙盒版给 `.disk` 只会扫一堆读不到的路径，那才是真的扫不动。
    var scope: ScanScope { ScanScope.effective }
    /// 用户选的界面语言。改它 = 让整棵树重画，所以切语言不用重启（商店版也不能自己重启）。
    /// 初值要把 `DISKWISE_LANG` 那次覆盖折进来，否则截图模式下词表被环境变量换掉了、
    /// 选择器还指着存盘那一格，图里就是「界面英文、选中中文」。跟随系统的 Auto 不参与这条覆盖。
    @Published private(set) var languageChoice: AppLanguage = SnapshotMode.requestedLang ?? L10n.choice

    func setLanguage(_ lang: AppLanguage) {
        guard lang != languageChoice else { return }
        L10n.apply(lang)          // 先换词表，再让视图重画
        L10n.setChoice(lang)      // 记住选择，下次启动系统级也对得上
        languageChoice = lang
    }

    var trashedBytes: Int64 { trashHistory.reduce(0) { $0 + $1.size } }

    // MARK: - C1/C2: confirmed trash plans and batch history (docs/enhance-feat.md §11)

    private let batchStore = TrashBatchStore()
    /// Persisted batch history, newest first; survives relaunch.
    @Published private(set) var batches: [TrashBatch] = TrashBatchStore().load()
    /// True while a plan or a restore is running. UI disables trash/undo buttons meanwhile;
    /// `runTrash` / `undo` also refuse to start a second run.
    @Published private(set) var isTrashing = false
    /// Last time anything was moved or restored. Scan models compare it with their `scannedAt`
    /// to tell the user a result may be stale.
    @Published private(set) var lastTrashAt: Date? = nil

    /// Executes a confirmed plan off the main thread: every item is re-checked (`preflight`),
    /// moved with `trashItem` and reported as moved / skipped / failed. The batch is persisted
    /// and mirrored into `trashHistory` for the pages that still use it.
    /// Returns nil when another run is in progress or the plan is empty.
    /// The running `runTrash` job, so `cancelTrash()` can stop it.
    private var trashJob: Task<TrashBatch, Never>? = nil

    /// Stops the running batch between items (or inside a long duplicate compare). Items
    /// already moved stay moved and are in the returned batch; the rest are
    /// `.skipped(.cancelled)`. No-op when nothing is running. Undo is not cancellable.
    func cancelTrash() { trashJob?.cancel() }

    func runTrash(_ items: [TrashPlanItem], source: String) async -> TrashBatch? {
        guard !isTrashing, !items.isEmpty else { return nil }
        isTrashing = true
        defer { isTrashing = false }
        let job = Task.detached(priority: .userInitiated) {
            executeTrashPlan(items, source: source)
        }
        trashJob = job
        let batch = await job.value
        trashJob = nil
        batches.insert(batch, at: 0)
        for e in batch.moved {
            if case let .moved(inTrash, _, _) = e.outcome {
                trashHistory.append(TrashRecord(original: e.item.url, inTrash: URL(fileURLWithPath: inTrash),
                                                size: e.item.bytes, displayName: e.item.name))
            }
        }
        lastTrashAt = Date()
        persistBatches()
        return batch
    }

    /// Restores every moved, not yet restored item of a batch. Each record is validated
    /// (inside a Trash, same inode, target in scope); results are per item in `entries[].restore`.
    func undo(batchID: UUID) async -> TrashBatch? {
        guard !isTrashing, let idx = batches.firstIndex(where: { $0.id == batchID }) else { return nil }
        isTrashing = true
        defer { isTrashing = false }
        let original = batches[idx]
        let updated = await Task.detached(priority: .userInitiated) { restoreBatch(original) }.value
        if let i = batches.firstIndex(where: { $0.id == batchID }) { batches[i] = updated }
        let restoredSources = Set(updated.entries.compactMap { e -> String? in
            guard case .restored = e.restore, case let .moved(inTrash, _, _) = e.outcome else { return nil }
            return inTrash
        })
        trashHistory.removeAll { restoredSources.contains($0.inTrash.path) }
        lastTrashAt = Date()
        persistBatches()
        return updated
    }

    /// Whether the batch still has items that were moved and not restored. A cheap check that
    /// does not touch the disk; `undo` reports per item if something is no longer in the Trash.
    func canUndo(batchID: UUID) -> Bool {
        !isTrashing && (batches.first { $0.id == batchID }?.restorable.isEmpty == false)
    }

    private func persistBatches() {
        do { try batchStore.save(batches) } catch {
            notice = LF("Could not save the history: %@", error.localizedDescription)
        }
    }

    var canGoBack: Bool { nav.canGoBack }

    /// 后退一步。栈空时什么都不做——那颗按钮本来就只在有上一站时才画出来。
    func goBack() {
        guard let top = nav.pop() else { return }
        folderDrillPath = top.drillPath
        jumpTo = top.panel
        navPulse += 1
    }

    /// 内容里的一次跳转：落到 `stop`，并记进历史。
    /// 去重与截断的规则在 `NavStack.arrive`，这里只管把它接上界面。
    func arrive(_ stop: NavStop) {
        nav.arrive(stop)
        folderDrillPath = stop.drillPath
        jumpTo = stop.panel
        navPulse += 1
    }

    /// 「根」入口：侧栏点页、面包屑首格。历史压成只有这一站，返回按钮随即消失。
    /// 点侧栏是在重新挑目的地，不是往下走一步——把这一幕也记进历史的话，
    /// 人会在缓存页按返回跳到大文件页，谁都不想要这个。
    func resetNav(to panel: AppPanel) {
        if panel != .folderDrill { folderDrillPath = nil }
        nav.reset(to: NavStop(panel: panel, drillPath: folderDrillPath))
        jumpTo = panel
        navPulse += 1
    }

    /// 开机时把第一站放进历史，不导航——窗已经开在那一页上了。
    /// 少了这一步，第一跳之后栈底是空的，会退到一个没有页面的地方。
    func seedNav(_ panel: AppPanel) {
        guard !navSeeded else { return }
        navSeeded = true
        nav.reset(to: NavStop(panel: panel, drillPath: folderDrillPath))
    }

    /// 进某个文件夹往下看。四个入口（总览的账目行与明细行、大文件页的行、
    /// 下钻页的面包屑与「上一级」）都收在这一条上：先写落点、再切页，
    /// 顺序反了会先看见上一处的残留内容再跳。
    func drill(into path: String) {
        guard !path.isEmpty else { return }
        arrive(NavStop(panel: .folderDrill, drillPath: path))
    }

    /// 深挖：去大文件页，只扫这一棵。总览的账目行与明细行两处共用。
    /// 落点在切页之前写好，大文件页的 `onAppear` 才能一次就消费到。
    func deepDive(into path: String) {
        guard !path.isEmpty else { return }
        bigScanDir = URL(fileURLWithPath: path)
        arrive(NavStop(panel: .big))
    }

    /// 下钻页的「上一级」。顶层目录（`/Applications`、`/Library` 这类）再往上是
    /// **空间总览**：盘顶 `/` 不算一站，理由见 `drillParent`。它跟面包屑第一格
    /// 走的是同一条路，所以两边必须由同一条规则算落点——分开写迟早会一处分折、一处不折。
    func goUpFromDrill() {
        guard let p = folderDrillPath, !p.isEmpty else { return }
        if let up = drillParent(of: p) {
            drill(into: up)
        } else {
            resetNav(to: .overview)
        }
    }

    /// 返回按钮那行说明里要写的名字：上一站是个目录就写目录名，否则写页名。
    var backTargetLabel: String {
        guard let top = nav.previous else { return "" }
        if top.panel == .folderDrill, let p = top.drillPath {
            return (p as NSString).lastPathComponent
        }
        return top.panel.title
    }

    /// Start of this app session. The notice bar's Undo only reaches batches made since then,
    /// like the in-memory history it replaced.
    private let sessionStart = Date()

    /// Newest batch from this session that still has items to put back (notice bar Undo).
    var lastUndoableBatchID: UUID? {
        batches.first { $0.createdAt >= sessionStart && !$0.restorable.isEmpty }?.id
    }

    /// Notice bar Undo: restores the newest undoable batch of this session through
    /// `undo(batchID:)` (same validation as the Trash page) and returns the message to show.
    func undoLastBatch() async -> String {
        guard !isTrashing, let id = lastUndoableBatchID,
              let before = batches.first(where: { $0.id == id }) else { return L("Nothing to undo") }
        let tried = Set(before.restorable.map(\.id))
        guard let after = await undo(batchID: id) else { return L("Nothing to undo") }
        let attempted = after.entries.filter { tried.contains($0.id) }
        let restored = attempted.filter { if case .restored = $0.restore { return true }; return false }
        let failed = attempted.filter { e in
            guard let r = e.restore else { return false }
            if case .restored = r { return false }
            return true
        }
        if let first = failed.first?.restore {
            return LF("Still couldn't restore %1$d locations: %2$@", failed.count, L(first.reasonKey))
        }
        return LF("Undid this move; restored %d locations", restored.count)
    }

    func clearHistory() {
        trashHistory.removeAll()
    }
}

enum AppPanel: Hashable, CaseIterable {

    case smart, overview, big, old, dup, nodemodules, docker, devcache, caches, orphans, uninstall, trash, crashDumps, diagReports, observation, appearance, feedback, folderDrill, menuLaunch, agent

    var symbol: String {
        switch self {
        case .smart: return "sparkle.magnifyingglass"
        case .overview: return "internaldrive"
        case .big: return "doc.on.doc"
        case .old: return "clock"
        case .dup: return "square.on.square"
        case .nodemodules: return "shippingbox"
        case .docker: return "cube"
        case .devcache: return "hammer"
        case .caches: return "sparkles"
        case .orphans: return "app.badge"
        case .uninstall: return "trash.slash"
        case .trash: return "trash"
        case .crashDumps: return "ladybug"
        case .diagReports: return "stethoscope"
        case .observation: return "eye"
        case .appearance: return "paintpalette"
        case .feedback: return "text.bubble"
        case .folderDrill: return "folder"
        case .menuLaunch: return "gearshape.2"
        case .agent: return "cpu"
        }
    }

    var titleKey: String {
        switch self {
        case .smart: return "Smart Scan"
        case .overview: return "Overview"
        case .big: return "Large Files"
        case .old: return "Files not modified recently"
        case .dup: return "Duplicates"
        case .nodemodules: return "node_modules"
        case .docker: return "Docker Usage"
        case .devcache: return "Dev Caches"
        case .caches: return "App Caches"
        case .orphans: return "Leftovers"
        case .uninstall: return "Uninstall Apps"
        case .trash: return "Trash"
        case .crashDumps: return "Crash dumps"
        case .diagReports: return "System diagnostics reports"
        case .observation: return "Observation"
        case .appearance: return "Skins"
        case .feedback: return "Feedback"
        case .folderDrill: return "Folder details"
        case .menuLaunch: return "Menu Bar & Launch"
        case .agent: return "AI Agent"
        }
    }

    var title: String { L(titleKey) }

    var workspaceTone: WorkspaceTone {
        switch self {
        case .smart: return .smart
        case .caches: return .cleanup
        case .trash: return .trash
        case .uninstall, .orphans: return .applications
        case .overview, .big, .old, .dup, .folderDrill: return .files
        default: return .advanced
        }
    }

    var sidebarGroup: Int {
        switch self {
        case .smart: return 0
        case .overview, .big, .old, .dup, .folderDrill: return 0
        case .nodemodules, .docker, .devcache: return 1
        case .caches, .orphans, .uninstall, .trash: return 2
        case .agent: return 3
        case .appearance, .feedback, .menuLaunch: return 4
        case .crashDumps, .diagReports: return 5
        case .observation: return 6
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var grant = HomeGrant.shared
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var scans = ScanStore()
    @State private var advancedExpanded = false
    @State private var selection: AppPanel? = SnapshotMode.requestedPanel ?? .smart
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var workspaceTheme: Theme {
        (selection ?? .smart).workspaceTone.theme(from: theme,
            scheme: themeManager.forcedScheme ?? theme.scheme ?? colorScheme)
    }

    @ViewBuilder private func inTitlebar<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .environmentObject(store)
            .environmentObject(themeManager)
            .themed(workspaceTheme)
            .tint(workspaceTheme.palette.tint)
    }

    var body: some View {
        NavigationSplitView {

            sidebar
                .navigationSplitViewColumnWidth(min: 232, ideal: 244, max: 248)
        } detail: {
            detail
        }

        .themed(workspaceTheme)
        .tint(workspaceTheme.palette.tint)
        .toolbar {
            ToolbarItem(placement: .navigation) { inTitlebar { BackButton() } }
            if !prefs.showsFirstRun {
                ToolbarItem(placement: .navigation) {

                    inTitlebar {
                        VolumeChip(showsFree: (selection ?? .overview) != .overview)
                    }
                    .background(ToolbarItemUnbordered())
                }
            }
        }

        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(TitlebarAccessory(attribute: .trailing) {

            if !prefs.showsFirstRun {
                inTitlebar {
                    HStack(spacing: 14) {

                        if selection == .overview { GaugeFreshness() }

                        if selection == .overview {
                        ScanControl(scanning: scans.overview.scanning,
                                    kind: .compact,
                                    showsShortcut: (selection ?? .overview) == .overview,
                                    rescan: {

                                        store.rescanPulse += 1
                                        scans.overview.refresh(scope: store.scope)
                                    },
                                    stop: { scans.overview.stop() })
                        }
                        SoundToggle()
                        GuideButton()
                    }

                    .padding(.trailing, 16)

                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        })

        .overlay {
            if prefs.showsFirstRun {
                FirstRunView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : theme.animation, value: prefs.showsFirstRun)

        .overlay {
            if !prefs.showsFirstRun && prefs.showsGuide {
                CleanupGuide(startPage: SnapshotMode.guidePage) {
                    Prefs.shared.finishGuide()
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : theme.animation, value: prefs.showsGuide)
        .onChange(of: store.jumpTo) { target in
            guard let target else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = target }
            store.jumpTo = nil
        }
        .onAppear {

            if let target = store.jumpTo {
                selection = target
                store.jumpTo = nil
            }

            store.seedNav(selection ?? .smart)
            MenuBar.readout.apply(shows: prefs.menuBarEnabled)

            PerfProbe.shared.start(store: store, overview: scans.overview, on: selection ?? .overview)

            PerfProbe.watchCostLedger(scans.overview)

            Sound.shared.prepare(enabled: prefs.soundEnabled)

            if !grant.needsGrant { scans.diagnostics.discover() }
        }
        .onChange(of: grant.needsGrant) { needed in
            if !needed { scans.diagnostics.discover() }
        }
        .background(WindowContentUnderTitleBar())

        .background(EscapeTap { scans.overview.disarm() })
    }

    private var sidebarTheme: Theme { workspaceTheme }

    private var sidebar: some View {
        SidebarScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    BrandLogo(size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Product.name).font(sidebarTheme.prose(size: 19, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text(L("A little care for your Mac")).font(sidebarTheme.prose(size: 11))
                            .foregroundStyle(sidebarTheme.palette.inkSecondary)
                    }
                }
                .foregroundStyle(sidebarTheme.palette.ink)
                .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 20)
                sideSection("", [.smart])
                sideSection(L("Clean up"), [.caches, .trash])
                sideSection(L("Applications"), [.uninstall, .orphans])
                sideSection(L("Files & Storage"), [.overview, .big, .old, .dup])
                DisclosureGroup(isExpanded: $advancedExpanded) {
                    sideSection("", [.devcache, .nodemodules, .docker,
                                     .crashDumps, .diagReports, .observation])
                    if !Channel.isAppStore { sideSection("", [.agent]) }
                } label: {
                    Text(L("Advanced tools"))
                        .font(sidebarTheme.prose(size: 12, weight: .medium))
                        .foregroundStyle(sidebarTheme.palette.inkSecondary)
                }
                .padding(.horizontal, 8).padding(.top, 18)
                .onChange(of: selection) { target in
                    if let target, target.workspaceTone == .advanced,
                       ![AppPanel.menuLaunch, .appearance, .feedback].contains(target) {
                        advancedExpanded = true
                    }
                }
                .onAppear {
                    if let selection, selection.workspaceTone == .advanced,
                       ![AppPanel.menuLaunch, .appearance, .feedback].contains(selection) {
                        advancedExpanded = true
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .themed(workspaceTheme)
            .environment(\.colorScheme, colorScheme)
        }
        .background(SidebarMaterial().ignoresSafeArea())
        .disabled(grant.needsGrant)
        .opacity(grant.needsGrant ? 0.4 : 1)
        .safeAreaInset(edge: .top, spacing: 0) {
            ChromeStrip(leading: Chrome.trafficLightInset).background(SidebarMaterial())
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
        .themed(workspaceTheme)
    }

    private func sideSection(_ title: String, _ panels: [AppPanel]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty { sideHeader(title).padding(.bottom, 2) }
            ForEach(panels, id: \.self) { panel in

                SidebarRow(panel: panel,
                           showsNew: panel == .agent && prefs.agentPageIsNew,
                           isSelected: selection == panel) {

                    store.arrive(NavStop(panel: panel))
                }
            }
        }
        .padding(.top, 8)
    }

    private func sideHeader(_ text: String) -> some View {
        Text(text)
            .accessibilityAddTraits(.isHeader)
            .font(sidebarTheme.bodyFont(.caption2).weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(sidebarTheme.palette.inkSecondary)
            .padding(.leading, 8)
            .padding(.top, 10)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            Divider().overlay(sidebarTheme.palette.separator).padding(.horizontal, 12)
            sideSection("", [.menuLaunch, .appearance, .feedback])
                .padding(.horizontal, 8)
            Text("\(Product.name) \(versionString)")
                .font(sidebarTheme.bodyFont(.caption2))
                .foregroundStyle(sidebarTheme.palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(SidebarMaterial().ignoresSafeArea())
    }

    ///

    static let launchedBuildStamp: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let exe = Bundle.main.executableURL,
              let date = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?
                  .contentModificationDate else { return "v\(v)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return "v\(v) · \(f.string(from: date))"
    }()

    private var versionString: String { Self.launchedBuildStamp }

    @ViewBuilder private var detail: some View {

        GeometryReader { proxy in
            VStack(spacing: 0) {
                Group {

                    if grant.needsGrant {
                        HomeGrantView()
                    } else {
                        page
                    }
                }

                .id(store.languageChoice)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

            // `.dbar{position:absolute;left:252px;right:20px;bottom:14px;z-index:50}`、

            .overlay(alignment: .bottom) {
                NoticeBar()
            }
        }
        .animation(reduceMotion ? nil : theme.animation, value: store.notice)

        .safeAreaInset(edge: .top, spacing: 0) { ChromeStrip() }
        .background(ThemedBackdrop())

        .navigationTitle(grant.needsGrant ? L("Folder access") : (selection?.title ?? L("Overview")))
    }

    @ViewBuilder private var page: some View {
        switch selection ?? .smart {
        case .smart: SmartScanView(model: scans.smart)
        case .overview: OverviewView(model: scans.overview)
        case .big: BigFilesView(model: scans.big)
        case .old: OldFilesView(model: scans.old)
        case .dup: DupView(model: scans.dup)
        case .nodemodules: NMView(model: scans.nodemodules)
        case .docker: DockerView(model: scans.docker)
        case .devcache: CachesView(model: scans.devcache, page: .dev)
        case .caches: CachesView(model: scans.caches)
        case .orphans: OrphansView(model: scans.orphans)
        case .uninstall: UninstallView(model: scans.uninstall)
        case .trash: TrashView(model: scans.trash)
        case .crashDumps: CrashDumpsView(hub: scans.diagnostics)
        case .diagReports: DiagReportsView(hub: scans.diagnostics)
        case .observation: ObservationView(hub: scans.diagnostics)
        case .appearance: AppearanceView()
        case .feedback: FeedbackView()
        case .folderDrill: FolderDrillView(model: scans.folderDrill)
        case .menuLaunch: MenuBarLaunchView()
        case .agent: AgentPageView()
        }
    }
}

///

private struct BackButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.canGoBack {
            Button {
                store.goBack()
            } label: {
                Label(L("Back"), systemImage: "chevron.backward")
            }
            .labelStyle(.titleAndIcon)
            .keyboardShortcut("[", modifiers: .command)
            .help(LF("Back to “%@”", store.backTargetLabel))
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var panel: AppPanel

    var showsNew: Bool = false
    var isSelected: Bool
    var tap: () -> Void

    @State private var hovering = false

    private var isDark: Bool {
        (theme.scheme ?? colorScheme) == .dark
    }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 10) {

                Image(systemName: panel.symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.palette.tint : theme.palette.inkSecondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(panel.title)
                    .font(theme.prose(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(theme.palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)

                if showsNew { NewBadge() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(rowBackground)
            .contentShape(theme.controlShape())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .accessibilityLabel(panel.title)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var rowBackground: some View {
        let shape = theme.controlShape()
        if isSelected {
            shape.fill(theme.palette.tintSoft)
                .overlay(alignment: .leading) {
                    Capsule().fill(theme.palette.tint).frame(width: 3, height: 18)
                }
        } else if hovering {
            shape.fill(theme.palette.surfaceAlt.opacity(0.8))
        }
    }
}

///

private struct NewBadge: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(L("New"))
            .font(theme.bodyFont(.caption2).weight(.semibold))
            .foregroundStyle(theme.palette.tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(theme.palette.surface))
            .overlay(Capsule().stroke(theme.palette.tint.opacity(0.5), lineWidth: theme.metric.stroke))
            .fixedSize()
    }
}

///

private struct SidebarMaterial: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            ThemedBackdrop()
            theme.palette.paper.opacity(reduceTransparency ? 1 : (theme.elevation == .glass ? 0.62 : 0.55))
        }
    }
}
