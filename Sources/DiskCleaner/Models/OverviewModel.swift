import SwiftUI
import Combine
import DiskCleanerCore
import AppKit

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class OverviewModel: ObservableObject, ScanStatusReporting {
    @Published var usage: VolumeUsage? = nil
    @Published var hotspots: [(name: String, path: String, size: Int64)] = []
    /// 排在列表封顶之后、但确实量到了的目录。列表不画满一屏，点开设的那行全在里面。
    @Published private(set) var restHotspots: [(name: String, path: String, size: Int64)] = []
    /// 一行都没摊到的那部分：单项低于下限的目录数与合计。没有这两个数，
    /// 「其他已统计」那块弧就有一截是账外之地——环形加起来等于盘，列表却对不上。
    @Published private(set) var unlistedCount = 0
    @Published private(set) var unlistedBytes: Int64 = 0
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    @Published var scanning = false
    /// 已经量完的目录数。环形要等全部量完才谈得上「未扫描」，所以这个数得露出来。
    @Published private(set) var done = 0
    @Published private(set) var pending = 0
    /// 扫过的目录合计占多少。环形的「未扫描」= 已用 − 这个数，整张图的口径全靠它。
    @Published private(set) var covered: Int64 = 0
    /// 这趟扫描里打不开的目录，按「缺哪种权限」分开。合并进一块就说不清哪块能要回来。
    @Published private(set) var needFDA: [String] = []
    @Published private(set) var needAdmin: [String] = []
    /// 正在量的目录名。列表必须「动起来」：一趟整盘扫描里最慢的根能跑几分钟，
    /// 只在有目录量完时才刷新，画面就会长时间一片空白，看着像点了没反应。
    @Published private(set) var measuring: [String] = []
    /// 这一轮要量的全部位置，按排队顺序。账目列靠它把「排队中」逐个换成「已量完」——
    /// 只报 `measuring` 的话，队列里还没轮到的那几百处在这一屏上根本不存在。
    @Published private(set) var scanTargets: [(name: String, path: String)] = []
    /// 量完一处记一笔（路径 → 字节）。它是账目列判断「这一处轮到没有」的账本：
    /// 量到 0 字节的也记（`nil` 才是「还没轮到」）。
    @Published private(set) var measuredTargets: [String: Int64] = [:]
    /// 这个进程实测有没有「完全磁盘访问权限」。授权是在系统设置里点的，macOS 要 App
    /// 退出重开才落到进程上，所以「扫描里报了几处 EPERM」不能当授权状态用——
    /// 那样会对着已经勾过的人说「点这个按钮去开」。每轮扫描开始时重测一次。
    @Published private(set) var hasFDA = false
    /// 整块盘按 APFS 卷拆开的账。nil = 这台机器拆不出（演示树、非 APFS），
    /// 那时「没量到的地方」只能整体归成一块，不硬编明细。
    @Published private(set) var split: VolumeSplit? = nil
    @Published private(set) var started = false
    /// 环上「动得了多少」这本账落地的节拍：`settleCaches()` 每结算一次加一。
    /// 读的人只有总览那一屏的截图定帧钩子——水珠的判据是「这条弧 reclaim > 0」，
    /// 而 reclaim 比弧本身晚到（缓存体积要一台一台量回来）。
    @Published private(set) var reclaimPulse = 0
    /// 行内摊开的下一级，按父路径缓存。行视图会随滚动和导航重建，不缓存的话
    /// 每次滚回来都要重走一遍几十 G 的子树——那看着就像 App 卡死了。
    @Published private(set) var childRows: [String: [ChildEntry]] = [:]
    /// 此刻摊开在哪一段账上（值是 `GaugeSegment.armKey`）。nil = 没下钻，环画满幅。
    ///
    /// **放在模型里，不放视图的 `@State`。** 侧栏是 `switch` 切分支，页面视图随导航销毁：
    /// 摊开状态要是住在 `@State` 里，切走再回来它就没了，人看到的是「刚摊开的那一行
    /// 自己收起来了，得重新点一遍」——而下一级的账明明还在 `childRows` 里躺着。
    /// 白量一趟的错觉就是这么来的，代价是每次切页都要把那几下重新点回去。
    ///
    /// 跟 `armedPath` 同一条纪律：跨页要留的状态一律不放 `@State`（那边记着理由）。
    /// 一次性的是**量**这件事（`childRows` 认缓存），不是「摊开着」这个状态。
    @Published var drillKey: String? = nil
    @Published private(set) var childBusy: Set<String> = []
    private var childTasks: [String: Task<Void, Never>] = [:]
    private var task: Task<Void, Never>? = nil

    /// 扫描期回填的缓冲。窗口内量完几处只改这里，窗口到了才一次性写进上面那串
    /// `@Published`。为什么要攒：几百处目标就是几百轮整页重绘，而一次整页变更在这台
    /// Intel 上值 60–100 ms（见 `PerfProbe` 的底价）；扫描那几分钟主线程该留给量盘。
    /// 窗口取 0.2 秒：环上的弧仍看得出在长（每秒五拍），又不至于每量完一处就重画整页。
    /// 2026-10-22 在同一棵合成家目录（200 个一级目录 / 6 万个文件）上配对量：
    ///   每处当场发  15 s 里 >33.4 207 次、p99 89.7 ms、主线程 79.5%
    ///   0.2 s 窗口  >33.4   9 次、p99 14.9/17.7 ms、主线程 11.4/11.7%（两次跑）
    /// 还剩下的 4 次 >100 ms 全在起跑后 1.3 s 内，是首屏铺开那一笔，不在回填途中。
    private final class ScanBackfill {
        var done = 0
        var pending = 0
        var total: Int64 = 0
        var sized: [(name: String, path: String, size: Int64)] = []
        var measured: [String: Int64] = [:]
        var blame = DirScan()
        var measuring: [String] = []
        var measuringSet = Set<String>()
        var progressDirty = false
        var measuringDirty = false
    }

    private static let scanFillWindow: TimeInterval = 0.2
    private var backfill: ScanBackfill?
    private var backfillJob: DispatchWorkItem?

    /// 小于这个数不进列表：家目录一级有上百个点目录，绝大多数是几 KB 的配置夹。
    static let sizeFloor: Int64 = 100 * MB
    /// 列表封顶。再长就没人逐行扫了，多出来的体积并进环形的「其他已统计」。
    static let listCap = 20

    // MARK: 环上的「本次移入废纸篓」账

    /// 被本工具搬进废纸篓、还没让位的那些字节（源路径 + 当时量到的大小）。
    /// 由视图从 `store.trashHistory` 整串推进来：模型摸不到 store，而这条账环形每帧都要读。
    /// 它是 @Published：删一刀之后环要跟着挪账，靠别的字段顺带重画是靠不住的。
    @Published private(set) var moved: [(original: String, bytes: Int64)] = []

    /// 每条弧的**水位线**：`[路径: 量完它那一刻已有几笔记录]`。序号在水位线之前的那些
    /// 已经作废（新尺寸本来就不含它们），之后的照常扣。用集合记「量过了」会把**量完之后**
    /// 新搬走的那些一起作废掉——清完一轮再点重新扫描，环上就再也长不出废纸篓那条弧。
    private var voidedUpTo: [String: Int] = [:]

    /// 这一轮量过的全部路径，含没进列表的那些（低于 `sizeFloor` 的也算「量到过」）。
    /// 归位要靠它：不传全，从一个小目录里清掉的几百 G 就归不进任何弧。
    private var targetPaths: [String] = []

    private var cachedLedger: RingLedger?

    /// 删完一刀（`store.record` 之后）、撤销一次、或清空废纸篓之后，把整条历史重新推一遍。
    /// 不增量记账：撤销链本来就是「历史短了」，重新归一次位弧就自己回滚，
    /// 模型里不会留下第二本跟 store 对不上的账。
    /// 内容没变就不发变更：这一串是每帧对照着推的，回回都发布会让整页白重画一次。
    func setMoved(_ records: [(original: String, bytes: Int64)]) {
        let same = records.count == moved.count && zip(records, moved).allSatisfy {
            $0.original == $1.original && $0.bytes == $1.bytes
        }
        guard !same else { return }
        moved = records
        // 撤销/清空历史会让整串变短，水位线得跟着退：不退的话，下一笔新记录（序号落在
        // 旧水位线之后）会被当成「量过了」而凭空作废。
        for key in voidedUpTo.keys { voidedUpTo[key] = min(voidedUpTo[key]!, records.count) }
        cachedLedger = nil
        // 搬走之后重归一次缓存账：已经不在原处的那几处不许再算进「还能腾出」，
        // 不然主按钮上的数会比它真能搬走的大，第二下按下去才发现差了一截。
        rebuildCacheTargets()
    }

    /// 那条「本次移入废纸篓」的弧有多大、每条热点弧被搬走了多少。
    ///
    /// 缓存是为了每帧重算的环形：一趟重复文件清理能留下几百条记录，每帧拿它们
    /// 跟几十个路径重比一遍是白烧 CPU。列表一变（扫描中名次会重排）就作废。
    var movedLedger: RingLedger {
        if let cachedLedger { return cachedLedger }
        let l = ringMoveLedger(records: moved,
                               topPaths: Array(hotspots.prefix(3)).map { $0.path },
                               otherPaths: targetPaths,
                               voidedUpTo: voidedUpTo)
        cachedLedger = l
        return l
    }

    /// 交给环形的两条扣减，钳在对应那条弧此刻的体积以内。
    ///
    /// 为什么会超：一轮扫描跑到一半被停掉，有的弧已经重新量过（搬走的字节早就不在里面了），
    /// 账本却还记着那一笔。不钳就是 Core 那道守卫直接不拆——「其他已统计」和「没量到」
    /// 两条弧当场消失，环形画成一张缺角的图，那比数字偏一点严重得多。
    var ringDeduction: (top: Int64, rest: Int64) {
        let led = movedLedger
        let topSum = Array(hotspots.prefix(3)).reduce(Int64(0)) { $0 + $1.size }
        return (min(led.topOut, topSum), min(led.restOut, max(0, covered - topSum)))
    }

    /// 某条热点弧此刻画多大：量到的减去已经从这条弧上搬走的。
    /// 搬走不等于腾出——磁盘「已用」一个字节都没少，所以这些字节只能在弧之间挪家。
    func arcSize(of path: String) -> Int64 {
        let size = (hotspots + restHotspots).first { $0.path == path }?.size ?? 0
        return max(0, size - movedLedger.out(of: path))
    }

    /// 没进列表的那些小目录，此刻还在原处的合计。
    ///
    /// 尾巴那句对账用它而不是 `unlistedBytes`：后者是这一轮量到的原始数，而
    /// 「其他已统计」那条弧已经减掉了搬走的部分——从一个小目录里清掉几百 G 时，
    /// 按原始数加就会加出一个比弧还大的三段。
    var unlistedNet: Int64 {
        let listed = Set((hotspots + restHotspots).map { $0.path })
        var gone: Int64 = 0
        for (path, bytes) in movedLedger.perOther where !listed.contains(path) { gone += bytes }
        return max(0, unlistedBytes - gone)
    }

    /// 这一行底下被搬走了多少。行上那句「已移入废纸篓 X」用它，跟弧上减掉的是同一个数。
    func movedOut(of path: String) -> Int64 { movedLedger.out(of: path) }

    /// 这条弧动得了多少 = 它名下**知识库点名为安全、且此刻还在原处**的那几处缓存。
    ///
    /// 只认知识库这一条来源，不认「这目录没进保护名单所以整段算能清」。后者在真机上量出来是：
    /// 家目录 161 项里 151 项通过，招牌画面于是许诺「125.9 GB 动得了」，而那一按下去搬的是
    /// 27 GB 的私人备份、`~/.qoder`、几个正在跑的工程目录。**行上给不给删除键**和
    /// **工具替不替你点齐**是两件事：前者是人一个个挑，后者是产品许的诺，只能按白名单许。
    /// 少报的代价是这一屏再补几轮知识库；错报的代价是用户的东西没了。
    func reclaimable(of path: String) -> Int64 {
        min(arcSize(of: path), cacheTargets[path]?.reduce(Int64(0)) { $0 + $1.size } ?? 0)
    }

    /// 某一处**子目录**名下动得了多少：把每一桶里落在它名下的那几处加起来。
    ///
    /// `reclaimable(of:)` 的键只有列表里那几行（弧对应的目录），而 `~/Library/Caches`
    /// 住在 `~/Library` 那一桶里。直接拿它去查会得到 0，于是父行写着「12.0 GB 可回收」、
    /// 它名下每一行都写着「只能看」——2026-09-26 实拍摊开的 `~/Library` 那一屏到的正是这个。
    /// 桶里的目标过 `dropNested`（父项已计就不重复加子项），跨桶相加因此不会双算。
    func reclaimableUnder(_ path: String) -> Int64 {
        var sum: Int64 = 0
        for ts in cacheTargets.values {
            for t in ts where t.path == path || t.path.hasPrefix(path + "/") { sum += t.size }
        }
        return sum
    }

    /// 这条弧上点名要搬走的那几处。`take` 只搬这里列出来的，一处不多。
    func reclaimTargets(of path: String) -> [ReclaimTarget] {
        cacheTargets[path] ?? []
    }

    // MARK: 缓存可回收账（来自缓存页那本知识库，同一趟体积统计）

    /// 「其他已统计」那条弧的归账键。它不对应某一个目录，所以不能用路径当键。
    /// 值住在 Core（`reclaimRestKey`）：它和 `reclaimBucket` 是一对约定，自检要钉得住。
    static let restBucketKey = reclaimRestKey

    /// 按弧归好的缓存可回收目标。键是弧对应的目录路径，`restBucketKey` 收其余的。
    private(set) var cacheTargets: [String: [ReclaimTarget]] = [:]

    /// 「其他已统计」那条弧名下、列表里真的有一行的那些行（第 4 名往后）。
    private var restRows: [String] {
        Array(hotspots.dropFirst(3).map { $0.path } + restHotspots.map { $0.path })
    }

    /// 那条弧上点名要搬走的每一处：列表里第 4 名往后的每一行名下知识库判安全的那几处，
    /// 加上没落进任何一行的那几处（`__rest__` 桶）。
    ///
    /// 这里曾有过第二条来源——「整段就能搬走的行记那一行本身」。它在演示树上看着对
    /// （`~/.npm`、`~/.m2` 确实能整段搬），搬到真机上就把用户的备份工程一并计进了承诺，
    /// 所以删掉：这条弧的数与下面列表尾巴那句「本工具动得了」现在同源于知识库，一处不多。
    func restReclaimTargets() -> [ReclaimTarget] {
        var t: [ReclaimTarget] = []
        for p in restRows { t.append(contentsOf: cacheTargets[p] ?? []) }
        t.append(contentsOf: cacheTargets[Self.restBucketKey] ?? [])
        return t
    }

    /// 那条弧动得了多少：点名要搬的合计，钳在弧此刻的体积以内（理由同 `reclaimable(of:)`）。
    func restReclaimable(_ arc: Int64) -> Int64 {
        min(max(0, arc), restReclaimTargets().reduce(0) { $0 + $1.size })
    }

    /// 代价读法那两行勾选框名下的候选：`零代价` = 池里的 `safe`，`需重下` = `redo`。
    /// 池子本来就只收这两档，所以这两行加起来正好是主按钮许的诺；
    /// `不可逆` 从不进一键路径，它那一行因此没有框。
    func poolTargets(_ tier: VerdictTier) -> [ReclaimTarget] {
        cleanPool.filter { $0.tier == tier }
            .map { ReclaimTarget(path: $0.path, size: $0.size) }
    }

    /// 应用缓存与开发缓存两台模型。环形认的是「知识库里量出来的那几处」，
    /// 不分页——少接一台，一键腾出的数就会少掉整个开发工具那一坨。
    /// 强引用不成环：两台模型都不回头指总览，而三方都由 `ScanStore` 持有。
    private var cachesModels: [CachesModel] = []
    private var cachesSubs: [AnyCancellable] = []

    /// 由 `ScanStore` 在构造时接线：缓存页每落地一处体积，这边重归一次账。
    /// 订阅而不是轮询：体积是一条条异步量完的，靠定时刷会出现「弧上刚亮起来、数还是旧的」。
    ///
    /// 但「订阅」不等于「逐条响应」。缓存页一趟扫描能连发上百条变更，而每一条都要在
    /// **主线程**上把全部候选路径 stat 一遍、判一遍可删/受保（`rebuildCacheTargets`
    /// 接着 `rebuildCleanCandidates`）。实测扫描期这样能把主线程一口气压住 1.4 秒：
    /// 环还在转，整页却冻住。所以变更只立个记号，攒到结算点统一算一遍。
    func bind(caches: [CachesModel]) {
        cachesModels = caches
        cachesSubs = caches.map { model in
            model.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.cachesChanged() }
        }
    }

    /// 结算窗口：一个窗口最多算一遍。取 0.12 秒——远大于一帧（不至于每帧都在重算整本账），
    /// 又短到数换过去时人看不出延迟。
    private static let cachesSettleWindow: TimeInterval = 0.12
    private var cachesPending = false
    private var cachesSettle: DispatchWorkItem?

    private func cachesChanged() {
        cachesPending = true
        guard cachesSettle == nil else { return }   // 本轮窗口里已经排上了，不用再排
        // 结算排在窗口末尾、不跟着新变更往后挪。扫描期变更能连续几分钟，挪成「静默了才算」
        // 就变成环形一直停在旧数上——那正是这层订阅当初要防的事。
        let job = DispatchWorkItem { [weak self] in self?.settleCaches() }
        cachesSettle = job
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cachesSettleWindow, execute: job)
    }

    private func settleCaches() {
        cachesSettle = nil
        guard cachesPending else { return }
        cachesPending = false
        // `cacheTargets` 没挂 `@Published`（它只在被读时用到），所以这一条得手动发：
        // 不发，环形和主按钮不会跟着重画。
        objectWillChange.send()
        rebuildCacheTargets()
        reclaimPulse += 1
    }

    /// 重新归一次缓存可回收账。扫描收尾、缓存体积落地、真搬走过东西，都要重跑这一趟。
    ///
    /// 三条规矩：
    /// 1. 只认知识库标 `safe` 的条目。`warn` 那些（整机备份、Docker 数据、废纸篓本身）
    ///    留给缓存页逐条勾着清，不进这颗一键按钮——那一按要搬十几处，不能拿它们赌。
    /// 2. 父项已计入就不重复加子项（`~/Library/Caches` 套着 `Homebrew` 是同一段字节）。
    /// 3. 按**列表里每一行**归，不只按前三名归——不然列表尾巴那句「能进废纸篓 / 只能看」
    ///    只能按「整处搬不搬得走」算，跟圆心上那个数当场打架。没落进任何一行的归到
    ///    `restBucketKey`，仍然算在「其他已统计」那条弧头上，一分不丢。
    func rebuildCacheTargets() {
        let fm = FileManager.default
        let rows = (hotspots + restHotspots).map { $0.path }
        let gone = movedBytesByKey
        var sizeOf: [String: Int64] = [:]
        for it in cachesModels.flatMap(\.items) {
            guard it.entry.level != "warn" else { continue }
            for (p, measured) in it.pathSizes {
                let sz = cacheBytesNow(p, measured: measured, gone: gone)
                guard sz > 0 else { continue }
                guard isDeletable(URL(fileURLWithPath: p)) else { continue }
                guard fm.fileExists(atPath: p) else { continue }   // 已经搬走的不许再报
                // 同一条路径被两处知识库命中时留第一次那个数（原来取 `hits.first`）。
                if sizeOf[p] == nil { sizeOf[p] = sz }
            }
        }
        var map: [String: [ReclaimTarget]] = [:]
        for p in dropNested(Array(sizeOf.keys)) {
            let key = reclaimBucket(of: p, in: rows) ?? Self.restBucketKey
            map[key, default: []].append(ReclaimTarget(path: p, size: sizeOf[p] ?? 0))
        }
        cacheTargets = map
        rebuildCleanCandidates()
    }

    /// 本工具已经搬走的那几处，路径先标准化好、按字节带着。
    ///
    /// 循环外算一次是有原因的：`cacheBytesNow` 要对**每个候选路径**扫一遍整条搬走历史，
    /// 历史几百条 × 候选几百处，放在函数里就是几十万趟 `URL` 构造。一趟重归账只标准化一次。
    private var movedBytesByKey: [(path: String, bytes: Int64)] {
        moved.map { (URL(fileURLWithPath: $0.original).standardizedFileURL.path, $0.bytes) }
    }

    /// 一处缓存此刻还在原处的字节：缓存页量到的那笔，减去已经被本工具搬走的。
    ///
    /// `pathSizes` 是缓存页那一趟量出来的快照。`~/Library/Caches` 这类父项的
    /// 安全子项被搬走之后，目录本身还在，旧数里却仍含着已经不在原处的字节——
    /// 不扣，结果页就会报出一笔「还剩」的假账（实测：搬完 7 处后仍挂着 1.9 GB）。
    /// 只减不重测：重扫之前宁可少报，不许错报。
    private func cacheBytesNow(_ path: String, measured: Int64,
                               gone: [(path: String, bytes: Int64)]) -> Int64 {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = p + "/"
        var sum: Int64 = 0
        for m in gone where m.path == p || m.path.hasPrefix(prefix) { sum += m.bytes }
        return max(0, measured - sum)
    }

    // MARK: 首次清理：候选池、选择、执行

    /// 首次清理走到哪一步。nil = 还在总览。
    @Published private(set) var cleanStage: CleanStage? = nil
    /// 可以逐条勾选的缓存。和 `cacheTargets` **不是同一批**：那边只收 `safe`，
    /// 这里还要把 `redo` 摆出来让人自己决定——只报一半，用户会在缓存页看见
    /// 另一批能清的东西，却在这条「首次清理」的路上找不到它们。
    ///
    /// `didSet` 只做一件事：作废那份勾选索引。清单里每一行的勾和总览主按钮
    /// 读的是同一份账，这份账一变，两边必须跟着变，不能让两处各存一份状态。
    ///
    /// 它**不是 `@Published`**：清单里勾一行只该重画那一行和主按钮，不该把整棵视图树重建一遍。
    /// 代价是改池子的入口要自己发一次整页变更，漏一处的症状是「清单页按了没反应」，
    /// 所以下面那几处（清单勾选、重建、撤销回填）都留了指回这里的注释。
    private var poolBacking: [CleanCandidate] = [] {
        didSet { selectedFlagsCache = nil }
    }
    var cleanPool: [CleanCandidate] { poolBacking }
    /// 四类代价账的前三类。跟 `poolBacking` 一样**不是** `@Published`：
    /// 它在同一趟重建里算完，搭那次 `poolChanged()` 一起发，不许再立第二条变更线。
    private var costSumsBacking = CostSums()
    /// 悬停那条通知线。住在模型里而不是视图的 `@State` 里，只为一件事：
    /// 探针要能按手指走的那条路去指一行（见 `applyHoverToken`）。
    let hoverSignal = LedgerHoverSignal()
    /// 池子被勾选以外的途径改了：清单页的勾、知识库重建、搬完/撤销后回填。
    private func poolChanged() { objectWillChange.send() }
    @Published private(set) var cleanBusy = false
    @Published private(set) var cleanRun: CleanRun? = nil

    var cleanSelected: [CleanCandidate] { cleanPool.filter(\.selected) }
    var cleanPoolBytes: Int64 {
        contentsUnionSize(cleanPool.map { (path: $0.path, bytes: $0.size) })
    }
    var cleanSelectedBytes: Int64 {
        contentsUnionSize(cleanSelected.map { (path: $0.path, bytes: $0.size) })
    }
    var cleanScanning: Bool { cachesModels.contains { $0.scanning } }

    // MARK: 「这一笔」的合计（选哪几处在清理清单里做）

    /// 候选池里每一处此刻勾没勾、多大。懒算一份索引，池子一变就作废（见 `poolBacking`）：
    /// 总览那一列每屏要查七八行 × 每行几十处，逐行现扫整池就是几百趟重复比对。
    private var selectedFlagsCache: [String: (on: Bool, bytes: Int64)]?
    private var selectedFlags: [String: (on: Bool, bytes: Int64)] {
        if let c = selectedFlagsCache { return c }
        // 同一路径不该在池里出现两次（按路径归并且 `dropNested` 过），但字典不许赌：
        // `uniqueKeysWithValues` 撞上就 trap，这里留第一条。
        let c = Dictionary(cleanPool.map { ($0.path, ($0.selected, $0.size)) },
                           uniquingKeysWith: { a, _ in a })
        selectedFlagsCache = c
        return c
    }

    /// 「这一笔」此刻的合计：候选池里真勾着的那几处。
    ///
    /// 账本行首不再有勾选框（2026-10-22，按他的要求撤掉）：改选择只有清理清单一个入口。
    /// 这里仍要现读池子，因为清单里取消过的项关掉再回来还得算数；池里一处都找不到的段
    /// 按全额算——它本来就不由选择说话，剔掉会让按钮比同一屏的导语少一截。
    ///
    /// `all` = 池里每一处都还勾着，按钮照旧报「可回收的 n 处」；有人取消过就改报
    /// 「选中的 n 处」，免得同一屏两个数对不上。
    func pickedTotals(of segs: [GaugeSegment]) -> (bytes: Int64, places: Int, all: Bool) {
        var bytes: Int64 = 0, places = 0
        var all = true
        let flags = selectedFlags
        for seg in segs where seg.reclaim > 0 {
            var inPool = 0, on = 0
            var onBytes: Int64 = 0
            for p in seg.targets.map(\.path) {
                guard let f = flags[p] else { continue }
                inPool += 1
                if f.on { on += 1; onBytes += f.bytes }
            }
            if inPool == 0 {
                bytes += seg.reclaim
                places += seg.targets.count
            } else {
                bytes += min(seg.reclaim, onBytes)
                places += on
                if on != inPool { all = false }
            }
        }
        return (bytes, places, all)
    }

    /// 探针悬停用的那几段。只记「指着它会亮」的段：跟账本行 `onHover` 的闸门
    /// （`seg.value > 0`）同一道，不然探针会去指一行屏上根本没有悬停反应的行。
    private(set) var hoverLabels: [String] = []
    private var hoverCursor = -1
    func recordHoverLabels(_ labels: [String]) {
        hoverLabels = labels.filter { !$0.isEmpty }
    }

    /// 口令指一下某一段。探针走这里，落点和行/弧的 `onHover` 是同一个 `hoverSignal.set`：
    /// 探针不另置一份悬停状态，也不绕 `AppStore`——那一发会让每一页都重绘，
    /// 量到的就不是悬停的账了。
    ///
    /// `cycle` 按人手的节奏来：进一行、出一行，每一拍在两件事之间交替。只进不出
    /// 量的是「一直有人停着」，跟手扫过一列的真样子不是一回事。
    @discardableResult
    func applyHoverToken(_ token: String) -> Bool {
        let labels = hoverLabels
        guard !labels.isEmpty else { return false }
        switch token {
        case "none":
            hoverSignal.set(nil)
        case "cycle":
            if hoverSignal.label != nil {
                hoverSignal.set(nil)
            } else {
                hoverCursor = (hoverCursor + 1) % labels.count
                hoverSignal.set(labels[hoverCursor])
            }
        default:
            guard let i = Int(token), labels.indices.contains(i) else { return false }
            hoverSignal.set(labels[i])
        }
        return true
    }

    func openFirstClean() {
        disarm()
        cleanRun = nil
        cleanBatchID = nil
        rebuildCleanCandidates()
        cleanStage = .candidates
    }

    func closeFirstClean() {
        cleanStage = nil
        cleanRun = nil
        cleanBatchID = nil
        cleanBusy = false
    }

    func setCleanSelected(path: String, _ on: Bool) {
        guard let i = poolBacking.firstIndex(where: { $0.path == path }) else { return }
        poolBacking[i].selected = on
        // 清单页每一行那颗勾读的就是这一处，要的是整页变更（见 `poolBacking` 那条注释）。
        poolChanged()
    }

    func setAllCleanSelected(_ on: Bool) {
        for i in poolBacking.indices { poolBacking[i].selected = on }
        poolChanged()
    }

    /// 「只勾没影响的」：把 `redo` 全部撤掉，`safe` 全部勾上。
    /// 这不是「全选」的别名——两个按钮挨着放，做的事必须分得开。
    func selectCleanSafeOnly() {
        for i in poolBacking.indices { poolBacking[i].selected = poolBacking[i].tier == .safe }
        poolChanged()
    }

    func advanceToConfirm() {
        guard !cleanSelected.isEmpty else { return }
        cleanStage = .confirm
    }

    func backToCandidates() {
        cleanStage = .candidates
    }

    /// 逐条重归候选池与四类代价账。扫描收尾、缓存体积落地、真搬走过东西都走这里。
    ///
    /// 去重的口径比 `cacheTargets` 多一层：`safe` 和 `redo` 各自去嵌套之后，
    /// 还要把「`redo` 是某个 `safe` 候选的祖先或后代」的那些剔掉。`~/Library/Caches`
    /// 是 `redo`，它底下躺着几个 `safe`——不剔的话整条 `Caches` 会把那几处吞掉，
    /// 而按整条搬又比按处搬危险，正好和这条路径「一处一处看代价」的承诺相反。
    func rebuildCleanCandidates() {
        let fm = FileManager.default
        let rows = (hotspots + restHotspots).map { $0.path }
        let gone = movedBytesByKey
        var raw: [(path: String, size: Int64, item: CacheItem)] = []
        // 代价账要把 `risky` 也数进来：池子只摆 `safe`/`redo`，而「不可逆」那一类
        // 只在 `warn+data` 上——不收它，四类里的第三类永远是零。
        // 过筛与池子同一条（存在、可删、不受保、扣掉已搬走的），两本账才是同一块盘。
        var costItems: [CostItem] = []
        for it in cachesModels.flatMap(\.items) {
            let tier = it.entry.tier
            for (p, measured) in it.pathSizes {
                let sz = cacheBytesNow(p, measured: measured, gone: gone)
                guard sz > 0 else { continue }
                let url = URL(fileURLWithPath: p)
                guard fm.fileExists(atPath: p), isDeletable(url), !isProtected(url) else { continue }
                costItems.append(CostItem(path: p, bytes: sz, tier: tier))
                guard tier == .safe || tier == .redo else { continue }
                raw.append((p, sz, it))
            }
        }
        // 同一条路径被两条知识库条目命中时 `safe` 优先：保守的那一档是给人看的判词。
        var byPath: [String: (size: Int64, item: CacheItem)] = [:]
        for r in raw {
            if let prev = byPath[r.path] {
                if prev.item.entry.tier != .safe, r.item.entry.tier == .safe {
                    byPath[r.path] = (r.size, r.item)
                }
            } else {
                byPath[r.path] = (r.size, r.item)
            }
        }
        let safePaths = dropNested(byPath.filter { $0.value.item.entry.tier == .safe }.map(\.key))
        let safeSet = Set(safePaths)
        let redoPaths = dropNested(byPath.filter { $0.value.item.entry.tier == .redo }.map(\.key))
            .filter { rp in
                !safeSet.contains { sp in
                    sp == rp || sp.hasPrefix(rp + "/") || rp.hasPrefix(sp + "/")
                }
            }

        let previous = Dictionary(cleanPool.map { ($0.path, $0.selected) },
                                  uniquingKeysWith: { a, _ in a })
        var out: [CleanCandidate] = []
        for p in safePaths + redoPaths {
            guard let hit = byPath[p] else { continue }
            let entry = hit.item.entry
            let bucket = reclaimBucket(of: p, in: rows) ?? reclaimRestKey
            out.append(CleanCandidate(
                // `name`/`whatif`/`rec` 存的是 safety_db 里的中文原文，那同时就是本地化 key。
                // 缓存页取这三样时过了 `L()`（CachesView.swift:300），这一列没过的后果是
                // 英文界面下整张候选清单的条目名蹦回中文——2026-10-19 实拍英文候选页命中。
                // 在这里过一次而不是在各渲染处过：`CleanReceipt`/`CleanFailure` 抄的就是
                // 这个字段，结果页和失败行也得是本地化后的那一份。
                path: p, name: L(entry.name), size: hit.size, tier: entry.tier,
                bucket: bucket,
                bucketLabel: bucket == reclaimRestKey
                    ? L("Other counted") : displayPath(URL(fileURLWithPath: bucket)),
                whatif: L(entry.whatif), rec: L(entry.rec),
                appID: entry.app, brand: entry.icon,
                selected: previous[p] ?? (entry.tier == .safe)))
        }
        let order = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1, $0) })
        out.sort {
            let a = order[$0.bucket] ?? Int.max
            let b = order[$1.bucket] ?? Int.max
            if a != b { return a < b }
            if ($0.tier == .safe) != ($1.tier == .safe) { return $0.tier == .safe }
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.path < $1.path
        }
        let sums = costSums(of: costItems)
        if out != poolBacking || sums != costSumsBacking {
            costSumsBacking = sums
            poolBacking = out
            poolChanged()
        }
    }

    /// 四类代价账。O(1)：归账在重建那趟里已经算完，这里只把整盘容量配上去。
    /// 不许把这个计算挪进哪个 `body`——那是每帧几十上百次 stat。
    var costLedger: CostLedger? {
        usage.map { CostLedger(sums: costSumsBacking, total: $0.total) }
    }

    /// Legacy (main thread, no preflight, old history): replaced by `trashClean(using:)`.
    /// Removed once the Overview UI calls the batch API.
    /// 真搬。一条一条走 `trashItem`，失败留在 `failures` 里点名。
    ///
    /// 搬走的当场从候选池里去掉；失败的那些留在池里，用户可以再试一次。
    /// 记录由调用方写进 `AppStore`（模型摸不到 store），所以这里收一个闭包。
    func performFirstClean(record: (TrashRecord) -> Void) -> CleanRun {
        let before = usage?.available ?? 0
        var records: [TrashRecord] = []
        var receipts: [CleanReceipt] = []
        var failures: [CleanFailure] = []
        var bytes: Int64 = 0
        cleanBusy = true
        defer { cleanBusy = false }
        for c in cleanSelected {
            do {
                let t = try trashItem(c.url)
                let r = TrashRecord(original: c.url, inTrash: t, size: c.size,
                                    displayName: c.url.lastPathComponent)
                record(r)
                records.append(r)
                receipts.append(CleanReceipt(path: c.path, name: c.name, size: c.size,
                                             tier: c.tier, appID: c.appID, brand: c.brand))
                bytes += c.size
            } catch {
                failures.append(CleanFailure(path: c.path, name: c.name,
                                             reason: error.localizedDescription))
            }
        }
        return CleanRun(records: records, receipts: receipts, failures: failures,
                        bytes: bytes, beforeAvailable: before)
    }

    func finishFirstClean(_ run: CleanRun) {
        cleanRun = run
        cleanBusy = false
        cleanStage = .result
        rebuildCleanCandidates()
    }

    /// 一处都没搬成：留在确认页，把原因摆在按钮旁边。不切结果页——
    /// 结果页只该在真的搬走之后出现。
    func noteFirstCleanFailure(_ run: CleanRun) {
        cleanRun = run
        cleanBusy = false
        rebuildCleanCandidates()
    }

    // MARK: C1/C2: first clean through the shared batch executor (docs/enhance-feat.md §11)

    /// Batch of the last first-clean run, for undo. nil before a run and after a full undo.
    @Published private(set) var cleanBatchID: UUID? = nil

    /// The confirmed plan for the confirm screen: exactly the selected candidates. The pool is
    /// already free of parent/child overlap (`rebuildCleanCandidates`), so nothing is moved twice.
    func cleanTrashPlan() -> [TrashPlanItem] {
        cleanSelected.map { TrashPlanItem(url: $0.url, name: $0.name, bytes: $0.size) }
    }

    /// Runs the plan through `AppStore.runTrash`: every item re-checked (`preflight`), off the
    /// main thread, cancellable with `store.cancelTrash()`, recorded as one batch.
    /// Afterwards `cleanRun` is the receipt (built from the batch), `cleanBatchID` is set, the
    /// moved ledger, pool and free space are updated. Stage: `.result` if anything moved,
    /// otherwise stays on `.confirm` with `cleanRun.failures` saying why.
    /// nil = not on the confirm screen, nothing selected, or another run in progress.
    func trashClean(using store: AppStore) async -> TrashBatch? {
        guard cleanStage == .confirm, !cleanBusy else { return nil }
        let plan = cleanTrashPlan()
        guard !plan.isEmpty else { return nil }
        let before = usage?.available ?? 0
        let picked = Dictionary(cleanSelected.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        cleanBusy = true
        defer { cleanBusy = false }
        guard let batch = await store.runTrash(plan, source: "first-clean") else { return nil }

        var records: [TrashRecord] = []
        var receipts: [CleanReceipt] = []
        var failures: [CleanFailure] = []
        for e in batch.entries {
            let c = picked[e.item.path]
            switch e.outcome {
            case let .moved(inTrash, _, _):
                records.append(TrashRecord(original: e.item.url, inTrash: URL(fileURLWithPath: inTrash),
                                           size: e.item.bytes, displayName: e.item.name))
                receipts.append(CleanReceipt(path: e.item.path, name: e.item.name, size: e.item.bytes,
                                             tier: c?.tier ?? .safe, appID: c?.appID, brand: c?.brand))
            case let .skipped(reason):
                failures.append(CleanFailure(path: e.item.path, name: e.item.name, reason: L(reason.reasonKey)))
            case let .failed(reasonKey, detail):
                failures.append(CleanFailure(path: e.item.path, name: e.item.name,
                                             reason: detail.isEmpty ? L(reasonKey) : "\(L(reasonKey)): \(detail)"))
            }
        }
        cleanRun = CleanRun(records: records, receipts: receipts, failures: failures,
                            bytes: batch.movedBytes, beforeAvailable: before)
        cleanBatchID = records.isEmpty ? nil : batch.id
        syncMoved(from: store)
        rebuildCleanCandidates()
        if !records.isEmpty { cleanStage = .result }
        refreshUsage()
        return batch
    }

    /// True when the last first-clean batch still has items to put back.
    func canUndoClean(using store: AppStore) -> Bool {
        cleanBatchID.map { store.canUndo(batchID: $0) } ?? false
    }

    /// Undo of the last first-clean batch through `store.undo(batchID:)` (each item validated:
    /// still in the Trash, same inode, target in scope; a same-named item gets a new name).
    /// If anything came back: back to the candidates with those re-selected. If nothing did:
    /// stays on the result; the returned batch's `entries[].restore` says why per item.
    func undoClean(using store: AppStore) async -> TrashBatch? {
        guard let id = cleanBatchID, store.canUndo(batchID: id),
              let batch = await store.undo(batchID: id) else { return nil }
        let restored = Set(batch.entries.compactMap { e -> String? in
            if case .restored = e.restore { return e.item.path }
            return nil
        })
        syncMoved(from: store)
        if !restored.isEmpty {
            if batch.restorable.isEmpty { cleanBatchID = nil }
            reopenCandidatesAfterUndo(restored)
        }
        refreshUsage()
        return batch
    }

    /// The moved ledger (ring, "already moved" deductions) follows the store's history.
    private func syncMoved(from store: AppStore) {
        setMoved(store.trashHistory.map { ($0.original.path, $0.size) })
    }

    /// 撤销之后回到候选页，并把刚放回原处的那几处重新勾上。
    /// 不留在结果页：文件已经回来了，还挂着一张「已移入废纸篓」的账单就是假账。
    func reopenCandidatesAfterUndo(_ restored: Set<String>) {
        cleanRun = nil
        rebuildCleanCandidates()
        for i in poolBacking.indices where restored.contains(poolBacking[i].path) {
            poolBacking[i].selected = true
        }
        poolChanged()
        cleanStage = .candidates
    }

    func reopenCandidates() {
        cleanRun = nil
        rebuildCleanCandidates()
        cleanStage = .candidates
    }

    // MARK: 两段式确认（第一下上膛，第二下才真搬）

    /// 上了膛的那条弧，nil = 没上膛。状态在模型而不在视图的 @State：
    /// 挂在视图上，人切走一趟再回来计时器就蒸发了，弧上却还亮着亮沿假装「等你确认」。
    @Published private(set) var armedPath: String?

    private var armTask: Task<Void, Never>?

    /// 第一下：给这条弧上膛，并起 3.2 秒倒计时。换弧上膛先解除旧的。
    func arm(_ path: String) {
        disarm()
        armedPath = path
        armTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.disarm()
        }
    }

    /// 解除上膛：第二下搬完、点了别处、3.2 秒到点、重扫、切页都走这里。
    /// 顺带收掉预演（`previewing`）——离开「要动刀」这一档的两句话一起说才收得干净：
    /// 预演那个数是**还没发生的**，收不干净就是把它留在招牌上当成今天的可用空间。
    func disarm() {
        // 没上膛也没预演就不发变更：写在一个 `@Published` 上等于**再来一次整页
        // 重绘**，而点一条动不了的弧也会经过这里——它本来不该有「把整屏重画一遍」这个副作用。
        guard armedPath != nil || armTask != nil || previewing else { return }
        armTask?.cancel()
        armTask = nil
        armedPath = nil
        previewSignal.set(false)
    }

    // MARK: 预演（按住空格）

    /// 此刻正在看「全部清空之后」那一档。**状态仍旧只有一份、仍旧住在模型里**（同 `armedPath`
    /// 那条纪律：切走一趟再回来，这一档要么跟着蒸发、要么还亮着，两种都是假状态），
    /// 变的只是它**不走 `@Published`**：这一档要改的画面有五处，挂进整页那本账就是
    /// 一发空格重算一遍整页，实测数据记在 `PreviewSignal` 上面那段。
    /// 读的人照旧读 `model.previewing`，写的人只走下面那两个方法。
    ///
    /// 这是**整屏唯一一处还没发生的数**，所以每一条离开这一屏的路都要收掉它。收法与
    /// 卸膛合成一个动作（见 `disarm`）：预演与上膛本来就互斥——「全部清空后」和
    /// 「再点一次搬这一段」不能同时说，`beginPreview` 与 `arm` 各自进门都先卸对方。
    let previewSignal = PreviewSignal()
    var previewing: Bool { previewSignal.on }

    /// 进预演。能不能进由页面判（那本账在视图里算），这里只接结论。
    func beginPreview() {
        guard !previewing else { return }
        disarm()
        previewSignal.set(true)
    }

    /// 松开空格：只把预演收掉。
    ///
    /// 与 `disarm()` 分开的理由就一条：松手是**这一档自己的退路**，不该顺手把别的
    /// 状态一起清掉。极端情形是按住空格的同时用鼠标点了某一条弧（`arm` 会把预演顶掉，
    /// 于是此刻是「上了膛」而不是「在预演」），这一松手要是走 `disarm()`，那一发刚
    /// 上好的膛会跟着没——人看见的是「我按了个空格，你把我的确认取消了」。
    func endPreview() {
        guard previewing else { return }
        previewSignal.set(false)
    }

    /// 只刷磁盘余量——可用空间随时在变，进页面就该是新的；
    /// 热点体积要遍历整棵家目录，不能跟着一起重跑。
    func refreshUsage() { readVolume() }

    /// 盘容量和卷账一起读：环形用的是容器数，明细用的是分卷数，
    /// 两者不同源就会对不上账（自检卡的正是「五块加起来等于已用」）。
    /// 卷账走 `usedPhysical`：diskutil 报的是每个卷此刻真占掉的格子，
    /// 而界面上的「已用」是系统口径（可清除算可用），拿后者去减卷账会凭空少 10 GB。
    private func readVolume() {
        let u = volumeUsage()
        usage = u
        split = u.flatMap { volumeSplit(diskUsed: $0.usedPhysical) }
    }

    func refresh(scope: ScanScope) {
        task?.cancel()
        backfillJob?.cancel()
        backfillJob = nil
        // 旧一轮可能还有正在收尾的子任务：换掉 session 之后，它们对 `enterMeasuring`
        // / `exitMeasuring` 的调用会因为对不上号而作废，不会污染这一轮的在量名单。
        backfill = nil
        dropChildren()
        disarm()
        readVolume()
        scanning = true
        scanState = .scanning
        issues = []
        Prefs.shared.setGaugeRunning(true)
        started = true
        hasFDA = fullDiskAccessGranted()
        hotspots = []
        restHotspots = []
        // 水位线**不清零**：新一轮开跑那一刻，每条弧上最可信的尺寸仍然是上一次量到的那个，
        // 而它已经把旧账扣干净了。当场抹掉水位线等于让那些旧账复活，扫描途中那一截
        // 字节会被扣两遍（弧画小、废纸篓弧画大）。每条弧量完自己刷新自己的。
        cachedLedger = nil
        unlistedCount = 0
        unlistedBytes = 0
        covered = 0
        done = 0
        measuring = []
        needFDA = []
        needAdmin = []
        let targets = hotspotTargets(scope)
        scanTargets = targets.map { (name: $0.name, path: $0.path) }
        measuredTargets = [:]
        pending = targets.count
        let session = ScanBackfill()
        session.pending = targets.count
        backfill = session
        task = Task {
            targetPaths = targets.map { $0.path }
            await withTaskGroup(of: (Int, DirScan).self) { group in
                for (i, t) in targets.enumerated() {
                    group.addTask {
                        await self.enterMeasuring(t.name, in: session)
                        let r = await dirSizeReport(URL(fileURLWithPath: t.path))
                        await self.exitMeasuring(t.name, in: session)
                        return (i, r)
                    }
                }
                // 组按完成顺序回，不是提交顺序——所以子任务必须把下标带回来。
                for await (i, r) in group {
                    if Task.isCancelled { break }
                    let t = targets[i]
                    guard backfill === session, let b = backfill else { break }
                    b.pending -= 1
                    b.done += 1
                    b.total += r.bytes
                    b.measured[t.path] = r.bytes
                    // 这一处的账现在是新量的了：量之前就已经搬走的那些当场作废，否则同一截
                    // 字节要扣两遍；量完之后新搬走的仍然要扣（见 Core 的 `voidedUpTo`）。
                    voidedUpTo[t.path] = moved.count
                    cachedLedger = nil
                    // 不设上限：这两串只被数个数拿去报「多少处读不动」。
                    // 掐到 60 条就等于对着 187 处说「有 60 处」，是个假数。
                    b.blame.merge(r)
                    if r.bytes > Self.sizeFloor {
                        b.sized.append((t.name, t.path, r.bytes))
                        b.sized.sort { $0.size > $1.size }
                    }
                    b.progressDirty = true
                    // 一处量完只登记，不发布：窗口到了由 `flushScanBackfill()` 一次写出去。
                    // 列表仍然「动」——每 0.2 秒一拍，环上的弧看得出在长。
                    scheduleScanFlush()
                    // 截图模式：热缓存下一趟整扫描不到半秒，「量到一半」那一帧根本截不到。
                    // 这里只把**回填的节拍**拉开，数字一个都不改——弧该长多大还长多大，
                    // 光该照在哪一格还照在哪一格，只是慢到快门跟得上。平时这个开关永远是关的。
                    if SnapshotMode.slowScanFill {
                        try? await Task.sleep(nanoseconds: 260_000_000)
                    }
                }
            }
            guard !Task.isCancelled, backfill === session else { return }
            // 收尾这一拍不再等窗口：把攒着的最后一处当场发出去，再把总账补齐。
            flushScanBackfill()
            let sizedBytes = session.sized.reduce(Int64(0)) { $0 + $1.size }
            let sizedCount = session.sized.count
            backfillJob?.cancel()
            backfillJob = nil
            backfill = nil
            scanning = false
            measuring = []
            scanState = .completed
            scannedAt = Date()
            issues = permissionIssues(needFDA + needAdmin)
            // 走到这一行的唯一路径是上面那道 `!Task.isCancelled` 的守卫：这一轮是走完的，
            // 不是按停的。顶栏那句「量完 · …」只在这种时刻盖戳（见 `Prefs.noteGaugeFinished`）。
            Prefs.shared.noteGaugeFinished()
            // 环形加起来等于整块盘，列表这一头也必须能对上：摊到几行、剩下多少，
            // 当场说清。不然「其他已统计」那块弧里就有一截是谁都没报过的数。
            unlistedBytes = max(0, session.total - sizedBytes)
            unlistedCount = max(0, targets.count - sizedCount)
            // 「还能腾出多少」这个数不能只靠整段可搬：一台真机上大头在缓存里。
            // 量体积走的是缓存页同一本知识库、同一趟统计（`load` 自带只跑一次的闸），
            // 一处一处量回来之后，环形那道金弧和主按钮的数才有凭据。
            rebuildCacheTargets()
            cachesModels.forEach { $0.load() }
        }
    }

    func stop() {
        task?.cancel()
        if scanning {
            scanState = .stopped
            scannedAt = Date()
            issues = permissionIssues(needFDA + needAdmin)
        }
        // 停在窗口里的那几处不补发：账本来就不完整，留下最后一拍的数就够了。
        backfillJob?.cancel()
        backfillJob = nil
        backfill = nil
        scanning = false
        measuring = []
        // 按停的那一趟不盖「量完」的戳（见上面那道 `!Task.isCancelled` 守卫），
        // 但「还在跑」必须先撤——不然顶栏那一格再也没有落回来的时候。
        Prefs.shared.setGaugeRunning(false)
    }

    private func enterMeasuring(_ name: String, in session: ScanBackfill) {
        guard backfill === session, session.measuringSet.insert(name).inserted else { return }
        session.measuring.append(name)
        session.measuringDirty = true
        scheduleScanFlush()
    }

    private func exitMeasuring(_ name: String, in session: ScanBackfill) {
        guard backfill === session, session.measuringSet.remove(name) != nil else { return }
        session.measuring.removeAll { $0 == name }
        session.measuringDirty = true
        scheduleScanFlush()
    }

    /// 攒到窗口末尾再发布。跟缓存账的 `cachesSettleWindow` 同一条纪律：窗口**不跟着
    /// 新变更往后挪**——扫描能连续几分钟，挪成「静默了才算」就变成界面一直停在旧数上。
    private func scheduleScanFlush() {
        guard backfillJob == nil, let session = backfill else { return }
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.backfill === session else { return }
            self.backfillJob = nil
            self.flushScanBackfill()
        }
        backfillJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanFillWindow, execute: job)
    }

    /// 把缓冲一次性写进 `@Published`。只写这一拍真变过的那几组，少发几条无用的变更。
    private func flushScanBackfill() {
        guard let b = backfill else { return }
        if b.progressDirty {
            pending = b.pending
            done = b.done
            covered = b.total
            measuredTargets = b.measured
            needFDA = b.blame.needFullDiskAccess
            needAdmin = b.blame.needAdmin
            hotspots = Array(b.sized.prefix(Self.listCap))
            restHotspots = Array(b.sized.dropFirst(Self.listCap))
            b.progressDirty = false
        }
        if b.measuringDirty {
            measuring = b.measuring
            b.measuringDirty = false
        }
    }

    // MARK: 量下一级

    /// 量某一行的下一级。量过就直接回缓存，反复点不会重走子树。
    ///
    /// 走 `dirLevel` 的「只要目录」那一档，和文件夹详情页同一份实现。别在这里另写一份
    /// 「只列子目录、掐掉 0」的简化版：量到 0 在这些位置上几乎都是「读不动」，
    /// 一掐就会出现「总览里怎么点都看不见、详情页里却躺着」的目录。
    func measureChildren(of path: String) {
        guard childRows[path] == nil, childBusy.insert(path).inserted else { return }
        childTasks[path] = Task { [weak self] in
            let rows = await dirLevel(URL(fileURLWithPath: path),
                                      includeFiles: false, fileLimit: 0).entries
            // 中途重扫过：这趟是被掐断的，只量到几格，不能当成完整答案挂上去。
            guard !Task.isCancelled, let self else { return }
            self.childRows[path] = rows
            self.childBusy.remove(path)
            self.childTasks[path] = nil
        }
    }

    /// 重扫把摊开的下级一起作废：盘的账会走样，隔着一轮扫描还挂着旧数字，
    /// 等于让人拿上一次的账做今天的决定。
    private func dropChildren() {
        childTasks.values.forEach { $0.cancel() }
        childTasks = [:]
        childRows = [:]
        childBusy = []
    }

    /// 整盘比用户区多扫的那几处，用显示名（演示树会剥掉假家目录前缀）。
    var extraScanRoots: [String] {
        systemScanRoots().filter { $0.lastPathComponent != "Applications" }
            .map { systemRootName($0) }
    }

    /// 扫描对象 = 家目录一级（点目录算在内）+ /Applications + 范围内的系统根。
    ///
    /// 点目录必须算：开发机上最能吃盘的往往就是 ~/.omlx、~/.ollama 这类模型仓库，
    /// 只扫可见目录等于把整机最大的一块藏起来——实测一台机器上因此少报了 42GB，
    /// 而当时列表第一名只有 39.7GB。
    ///
    /// 顺序是「便宜的排前面」，不是随手写的：并发跑的是系统自己那几条工作线程，
    /// 谁先提交谁先占住一条。/Library、/private 这种整棵系统目录一跑就是几分钟，
    /// 放在队首会把线程全占满，家目录里几百毫秒就完事的小目录反而排不上，
    /// 实测整盘档因此出现「已量完 0 / 163」卡两分钟、列表一片空白。
    ///
    /// 去重按 `seen` 走，先到先得：演示树把 /Applications 挂在假家目录底下，
    /// 同一个 path 进两遍不是重复一行那么简单——列表以 path 作 ForEach 的 id，
    /// 第二条会占住行高却什么都不画，环形还会把它算两遍。
    private func hotspotTargets(_ scope: ScanScope) -> [(name: String, path: String)] {
        var out: [(name: String, path: String)] = []
        var seen = Set<String>()
        func add(_ name: String, _ path: String) {
            guard seen.insert(URL(fileURLWithPath: path).standardizedFileURL.path).inserted
            else { return }
            out.append((name, path))
        }
        let home = homePath()
        if let kids = try? FileManager.default.contentsOfDirectory(atPath: home) {
            for k in kids.sorted() {
                // 废纸篓不进热点列表，跟别的扫描任务同一套规矩（见 ScanJobs）：
                // 环形上它搬走的字节有自己那条弧，列表里再量它一次就是把同一块字节记两遍。
                if k == ".Trash" { continue }
                let p = (home as NSString).appendingPathComponent(k)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                    add("~/\(k)", p)
                }
            }
        }
        add("/Applications", applicationsDir())
        if scope == .disk {
            for r in systemScanRoots() where r.lastPathComponent != "Applications" {
                add(systemRootName(r), r.path)
            }
        }
        return out
    }

    /// 系统根的显示名用真实路径。演示树里 `<假家目录>/Library` 要显示成 `/Library`，
    /// 截图里的名字才跟真机一致。
    private func systemRootName(_ url: URL) -> String {
        guard homeIsDemo else { return url.path }
        let home = homePath()
        guard url.path.hasPrefix(home + "/") else { return url.path }
        return String(url.path.dropFirst(home.count))
    }
}
