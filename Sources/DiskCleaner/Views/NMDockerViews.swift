import SwiftUI
import DiskCleanerCore

// ── node_modules：按项目聚合，删了重装回来就行 ──

/// 行首那一格挂的是「这份依赖是谁装的」：npm / pnpm / yarn / bun 各挂自家官方标，
/// 认不出管理器才挂 Node.js——`node_modules` 这个名字本身就足够支持这句话，
/// 所以那一格不会空着，也不会退化成整列一样的通用文件夹。
///
/// 归属 App 那一档在这里天然取不到（项目目录不是任何 App 的沙盒），所以品牌标就是首选，
/// 不是兜底。

/// 恢复这一句跟着真正的管理器走：知道是 pnpm 就别再让他敲 npm install。
private func restoreHint(_ manager: String?) -> String {
    guard let m = manager else {
        return L("Run npm install (or pnpm/yarn) in the project folder and package.json restores it exactly")
    }
    return LF("Run %@ in the project folder and package.json restores it exactly", "\(m) install")
}

struct NMView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: NMModel
    @State private var confirm = false
    @State private var err: String? = nil
    @State private var result: LegacyOperationResult?
    /// 删除飞行：起点（勾中的行）与落点（CleanBar 那颗按钮）都在这里面收着。
    @StateObject private var flight = TrashFlightController()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "shippingbox", title: L("node_modules"),
                           subtitle: L("Dependencies reinstall themselves — take the space back"),
                           variant: .display, scope: L("Home folder only"))
                ControlStrip {
                    if model.scanning {
                        if model.items.isEmpty {
                            LoadingRow(text: L("Looking through your projects for node_modules…"), progress: model.progress)
                        } else {
                            LoadingRow(text: LF("%1$@ measured, %2$@ so far — still looking…",
                                                cnt(model.items.count, "projects"),
                                                uiHuman(model.totalBytes)),
                                       progress: model.progress)
                        }
                    } else if model.stoppedEarly {
                        if model.items.isEmpty {
                            Text(L("Stopped before any project finished measuring"))
                        } else {
                            Text(LF("Stopped before this pass finished: %1$@ measured, %2$@ so far",
                                    cnt(model.items.count, "projects"), uiHuman(model.totalBytes)))
                        }
                    } else {
                        Text(LF("%1$@, %2$@ in total", cnt(model.items.count, "projects"), uiHuman(model.totalBytes)))
                    }
                    // 这一页**不挂范围徽章**。别处那几枚（大文件/很久没动/重复）都是跟着用户
                    // 手上那个「整盘 ↔ 用户区」开关走的，徽章说的是**这一刻选了什么**；
                    // 这一页的范围是写死的 `ScanScope.user`（理由见 `findNodeModules`），
                    // 一枚永远只会说同一句话的徽章不是信息，是装饰——而且这一屏就它一个人挂，
                    // 读起来像「这一页另有一个可以调的档却找不到」。
                    // 「这页只看用户区」这件事由别处说：加载那行写的是「翻**项目目录**找
                    // node_modules」，而项目只长在家目录里。
                } trailing: {
                    ScanControl(scanning: model.scanning,
                                rescan: { model.scan() }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            if model.scanning && model.items.isEmpty {
                ScanChecklist(progress: model.progress)
            } else if !model.scanning && model.items.isEmpty {
                EmptyState(symbol: "shippingbox",
                           title: model.stoppedEarly ? L("This pass didn't finish") : L("No node_modules found"),
                           hint: model.stoppedEarly ? L("Stopped too early — rescan and let it finish")
                                                    : L("No matching items in the scanned scope"))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.items.count), detail: uiHuman(model.totalBytes), symbol: "shippingbox"),
                    .init(title: L("Selected"), value: uiHuman(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
                List($model.items) { $it in
                    ItemRow(selected: $it.selected,
                            icon: .path(URL(fileURLWithPath: it.project)),
                            brand: it.manager ?? "nodedotjs",
                            name: URL(fileURLWithPath: it.project).lastPathComponent,
                            sub: nmSub(it),
                            sizeText: shown[it.id] ?? uiHuman(it.size),
                            fraction: Double(it.size) / Double(maxSize),
                            badge: it.partial ? ItemBadge(text: L("Partial"), tone: .warn) : nil,
                            showRule: model.items.first?.id != it.id) {
                        ExplainLine(key: L("What it is"), value: L("The dependency folder of a Node.js project — only used while developing it"))
                        ExplainLine(key: L("What breaks"), value: L("The project won't run until you reinstall; source and package.json are untouched"))
                        ExplainLine(key: L("How to recover"), value: restoreHint(it.manager))
                        PathLine(path: it.project)
                    }
                    // 只有勾上的行才报起点：这一页上百行，全挂 GeometryReader 是白量。
                    .heroAnchorGlobal(TrashFlightController.rowAnchor(it.project),
                                      enabled: it.selected)
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)   // 清理条钉在窗口下沿，见 `CleanBar`

            if let err { ListNote(text: err) }
            SelectionActionBar(count: model.selected.count, bytes: uiHuman(model.selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) { confirm = true }

        }
        .frame(maxWidth: .infinity)
        .flightField(flights: $flight.flights, anchors: $flight.anchors)
        .onChange(of: flight.anchors) { _ in fireSnapshotFlightIfAsked() }
        // 页刚进来时 `anchors` 只出现过一次（那时还没扫出项目来），光靠它这一次钩子会早退；
        // 行数从 0 变成 N 是「扫完了」的信号，补在这里，钩子才有第二次机会。
        .onChange(of: model.items.count) { _ in fireSnapshotFlightIfAsked() }
        .onAppear { if !model.started { model.scan() } }
        .confirmTrash(isPresented: $confirm,
                      text: LF("Move the dependencies of %1$@ (%2$@) to the Trash.",
                               cnt(model.selected.count, "projects"),
                               uiHuman(model.selectedBytes, inRulerOf: model.totalBytes))
                          + "\n\n" + model.selected.map { $0.project + "/node_modules" }.joined(separator: "\n")) {
            doClean()
        }
        .sheet(item: $result) { result in LegacyOperationResultSheet(result: result).themed(theme) }
    }

    private var maxSize: Int64 { max(1, model.items.map(\.size).max() ?? 1) }

    /// 整列统一到页头那个总数的单位再分摊：这几行**印出来**加起来就是页头那句。
    private var shown: [UUID: String] {
        sizeColumn(model.items.map { (key: $0.id, bytes: $0.size) })
    }

    /// 这一页只有一档：列出来的每个 `node_modules` 都能重装回来，本工具全都清得动。
    private var tiers: [LedgerTier] {
        [LedgerTier(label: L("Ours to clean"), bytes: model.totalBytes, tone: .hot)]
    }

    private var ledgerNote: String? {
        LF(" The header's “%@ in total” is this very column — every row on this page is on screen.", uiHuman(model.totalBytes))
    }

    /// 副标题只报**有信息量**的那几样。
    ///
    /// 原来每行都印「N 个包」，可那个数数的是项目里有几处 `node_modules`（monorepo 才会大于 1），
    /// 不是依赖包的数量——118 行里 117 行都是「1 个包」，一行重复到底就等于没有信息。
    /// 现在只在真有多处时才说，其余留日期。
    private func nmSub(_ it: NMProject) -> String {
        var parts: [String] = []
        if it.nmCount > 1 { parts.append(cnt(it.nmCount, "node_modules folders")) }
        parts.append(it.date)
        if it.partial { parts.append(L("Partially counted")) }
        return parts.joined(separator: " · ")
    }

    /// 截图钩子：`DISKWISE_FLIGHT=<0~1>` 时把这一页的飞行钉住拍一张（见 `TrashFlightController`）。
    private func fireSnapshotFlightIfAsked() {
        let open = Array(model.items.prefix(2))
        guard let first = open.first else { return }
        flight.fireSnapshotIfAsked(candidates: open.map { (key: $0.project, bytes: $0.size) },
                                   selected: first.selected) {
            for p in open.map(\.project) {
                if let i = model.items.firstIndex(where: { $0.project == p }) {
                    model.items[i].selected = true
                }
            }
        }
    }

    private func doClean() {
        err = nil
        let targets = model.selected
        // 起点终点都在清选区**之前**取：行一不勾就不再报锚点，按钮一禁用落点也跟着变。
        flight.launch(rows: targets.map { (key: $0.project, bytes: $0.size) },
                      animate: TrashFlightController.canAnimate(reduceMotion: reduceMotion))
        var ok = 0
        var movedRows: [String] = []
        var errs: [String] = []
        // 删项目下的 node_modules（可能多个）
        for it in targets {
            let projName = URL(fileURLWithPath: it.project).lastPathComponent
            let nmURL = URL(fileURLWithPath: it.project).appendingPathComponent("node_modules")
            let targets = (try? FileManager.default.contentsOfDirectory(atPath: it.project)
                .filter { $0 == "node_modules" }
                .map { URL(fileURLWithPath: it.project).appendingPathComponent($0) }) ?? [nmURL]
            for t in targets {
                guard FileManager.default.fileExists(atPath: t.path) else { continue }
                do {
                    let dst = try trashItem(t)
                    store.record(TrashRecord(original: t, inTrash: dst, size: it.size,
                                             displayName: "\(projName)/node_modules"))
                    movedRows.append(projName + "/node_modules · " + t.path)
                    ok += 1
                } catch { errs.append(failLine(it.project, error)) }
            }
        }
        // 就地收尾：整个依赖目录都没了的项目从列表里消失，不必重扫全盘
        model.items.removeAll { !FileManager.default.fileExists(
            atPath: ($0.project as NSString).appendingPathComponent("node_modules")) }
        for i in model.items.indices { model.items[i].selected = false }
        if !errs.isEmpty { err = errList(errs) }
        store.notice = trashedNotice(ok, "node_modules folders", failed: errs.count)
        result = LegacyOperationResult(moved: movedRows, failed: errs)
    }
}

// ── Docker：只读明细，不代删，只指路 ──

/// Core 只给分类标识，措辞全在这里
///
/// 品牌名不翻译：这两家在两种语言里都叫这个名字。认不出是谁家（CLI 不是这两家之一、
/// 或商店版沙盒里问不到）才用那句通用说法。
private func runtimeName(_ r: DockerRuntime?) -> String {
    switch r {
    case .orbstack:      return "OrbStack"
    case .dockerDesktop: return "Docker Desktop"
    case .podman:        return "Podman"
    case .colima:        return "colima"
    case nil:            return L("the container engine")
    }
}

private func dockerHead(_ it: DockerItem) -> String {
    switch it.kind {
    case .runtime:       return LF("%@ data", runtimeName(it.runtime))
    case .dfImages:      return L("Images · Total")
    case .dfContainers:  return L("Containers · Total")
    case .dfVolumes:     return L("Volumes · Total")
    case .dfCache:       return L("Build cache · Total")
    case .image:         return it.title
    case .danglingImage: return LF("Dangling image (%@)", it.title)
    case .other:         return LF("%@ · Total", it.title)
    }
}

private func dockerNote(_ it: DockerItem) -> String {
    let name = runtimeName(it.runtime)
    switch it.kind {
    case .runtime:
        // 磁盘那一行是本页唯一进展式的数，所以它必须自己说清量的是什么。
        guard it.path != nil else {
            return L("This runtime's data folder isn't on this machine, so this row adds up what the engine reports")
        }
        return LF("%@ keeps its images, containers and volumes in one virtual disk. This row is what that disk actually occupies on this Mac", name)
    case .dfImages, .dfContainers, .dfVolumes, .dfCache, .other:
        return LF("This segment is %@'s own figure — the engine's logical size, not extra bytes on this disk", name)
    case .image, .danglingImage:
        return LF("%@'s images all live inside that virtual disk", name)
    }
}

/// 行内副标题：运行时那行说自己量的是什么，段报它的组成，明细就地标明它不进展式——
/// 一屏列得下四段却列不下几十行镜像，对账那句在卡底下，滚到中间就看不到了。
private func dockerSub(_ it: DockerItem) -> String {
    switch it.kind {
    case .runtime:
        return it.path != nil ? L("Actually on disk") : L("The engine's own total")
    case .dfImages, .dfContainers, .dfVolumes, .dfCache, .other:
        // 「可回收」这三个字在本工具里专指「我们替你搬得走的」，而这一页一项都动不了，
        // 所以引擎报的那个数必须带上它自己的主语——而且主语得是真在跑的那一家。
        var s = LF("%1$@ total, %2$@ active", it.total ?? "?", it.active ?? "?")
        guard let can = it.reclaimable, can > 0 else { return s }
        let name = runtimeName(it.runtime)
        if let share = it.reclaimableShare {
            s += LF(", and %1$@ can free %2$@ (%3$@)", name,
                    uiHuman(can, inRulerOf: it.size), share)
        } else {
            s += LF(", and %1$@ can free %2$@", name, uiHuman(can, inRulerOf: it.size))
        }
        return s
    case .image, .danglingImage:
        return L("Image detail — already counted in the “Images · Total” segment above")
    }
}

/// 明细行摊开后要说的一句：它的字节不进展式。计算属性，语言切换后才跟着换。
///
/// 不只镜像明细不进展式——`docker system df` 那四段同样不进，它们和磁盘实占那行
/// 说的是同一批字节的两种算法（本机实测：四段相加 38.4 GB，那块磁盘实占 22.8 GB）。
private var dockerDetailNote: String {
    L("This row stays out of the total: it's the engine's figure for the same disk, not extra bytes on it")
}

/// 行首那一格。运行时那一行挂着数据目录，所以挂得上那一家的真 App 图标；
/// `docker system df` 那几段背后没有路径可对——虚拟盘里没有一个文件给图标服务读——
/// 只能按类别挂符号，那是诚实的写法，不是偷懒的兜底。
private func dockerIcon(_ it: DockerItem) -> RowIcon {
    if let p = it.path { return .path(p) }
    let symbol: String
    switch it.kind {
    case .runtime:                   symbol = "cube"
    case .dfContainers:              symbol = "play.rectangle"
    case .dfVolumes:                 symbol = "externaldrive"
    case .dfCache:                   symbol = "bolt.horizontal"
    case .dfImages, .image, .danglingImage: symbol = "shippingbox"
    case .other:                     symbol = "circle.grid.cross"
    }
    return .symbol(symbol)
}

private func dockerHowTo(_ it: DockerItem) -> String {
    let name = runtimeName(it.runtime)
    switch it.kind {
    case .runtime:
        guard it.path != nil else { return L("This tool won't delete it — clean up in whichever runtime is running") }
        switch it.runtime {
        // 「删完会自动收缩」不是安慰话，是 OrbStack 自家 README 里写的机制。
        case .orbstack: return L("Clean it inside OrbStack: its docker commands work (docker system prune -a drops unused images and build cache), and that disk shrinks by itself afterwards")
        case .colima:   return L("colima's way out is deleting the whole VM (colima delete); this tool won't do it for you")
        case .podman:   return L("Clean it with podman's own command (podman system prune); this tool won't do it for you")
        default:        return LF("Open the matching page in %@ and delete there; this tool won't do it for you (there are no separate paths inside one virtual disk)", name)
        }
    case .image, .danglingImage:
        return LF("Delete this image in %@ (docker rmi on the command line)", name)
    case .dfImages, .dfContainers, .dfVolumes, .dfCache, .other:
        return LF("Open the matching page in %@ and delete there; this tool won't do it for you (there are no separate paths inside one virtual disk)", name)
    }
}

struct DockerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: DockerModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "cube", title: L("Docker Usage"),
                           subtitle: L("Read-only — each container runtime deletes differently; open the row for the route"),
                           variant: .display, scope: L("Container runtimes on this Mac"))
                ControlStrip {
                    if model.scanning {
                        LoadingRow(text: L("Counting what your containers take…"))
                    } else {
                        Text(LF("%@ total", uiHuman(model.totalBytes)))
                    }
                    ThemeBadge(text: L("No delete button here"), tone: .neutral)
                } trailing: {
                    ScanControl(scanning: model.scanning,
                                rescan: { model.scan() }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            if model.scanning && model.items.isEmpty {
                ScanChecklist(progress: model.progress)
            } else if !model.scanning && model.items.isEmpty {
                EmptyState(symbol: "cube", title: L("No container runtime found"),
                           hint: L("There's no data folder here for Docker Desktop, OrbStack, Podman or colima"))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Docker Usage"), value: uiHuman(model.totalBytes), detail: L("Actually on disk"), symbol: "cube"),
                    .init(title: L("Listed items"), value: String(model.items.count), detail: L("Read-only"), symbol: "list.bullet")
                ]).pagePadding().padding(.bottom, 12)
                if let note = ledgerNote { ListNote(text: note) }
                List(model.items) { it in
                    ItemRow(selected: .constant(false),
                            icon: dockerIcon(it),
                            appID: it.runtime?.bundleID,
                            name: dockerHead(it),
                            sub: dockerSub(it),
                            sizeText: shown[it.id] ?? uiHuman(it.size),
                            fraction: Double(it.size) / Double(maxSize),
                            selectable: false,
                            showRule: model.items.first?.id != it.id) {
                        ExplainLine(key: L("What it is"), value: dockerNote(it))
                        if !it.countsInTotal {
                            ExplainLine(key: L("How this row is counted"), value: dockerDetailNote)
                        }
                        ExplainLine(key: L("How to clean"), value: dockerHowTo(it))
                        if let p = it.path { PathLine(path: p.path) }
                    }
                }
                .ledgerCard()
            }
            ToolFooter(text: L("Read-only — each container runtime deletes differently; open the row for the route")) {
                Button(L("Refresh")) { model.scan() }.disabled(model.scanning)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if !model.started { model.scan() } }
    }

    private var maxSize: Int64 { max(1, model.items.map(\.size).max() ?? 1) }

    /// 进加式的那几行（一行一个运行时）**当场要加得起来**：页头那个数就是它们的和，
    /// 各行独立四舍五入会飘出 41.3 而页头写着 41.2（2026-09-26 实拍）。引擎报的账和
    /// 镜像明细不进加式，只跟着同一把尺，保证能和上面那些行横向比大小。
    private var shown: [UUID: String] {
        var out: [UUID: String] = [:]
        let sections = model.items.filter(\.countsInTotal)
        for (it, s) in zip(sections, uiAddableHumanColumn(sections.map(\.size),
                                                        total: model.totalBytes)) {
            out[it.id] = s
        }
        for it in model.items where !it.countsInTotal {
            out[it.id] = uiHuman(it.size, inRulerOf: model.totalBytes)
        }
        return out
    }

    /// 这一页一个字节的决定都不替用户做，所以只有「本工具不碰」这一档，整块条子是灰的。
    private var tiers: [LedgerTier] {
        [LedgerTier(label: L("Not ours to touch"), bytes: model.totalBytes, tone: .cold)]
    }

    /// 原来这句还要重述一遍「N 段相加 X 就是页头那个数」——那是 `ListNote` 唯一的活，
    /// 现在这件事由上面那块账替它说，同屏留两遍同样的两个数就是两本账。
    private var ledgerNote: String? {
        var s = L("Nothing on this page is ours to move, so no row lights up.")
        if model.detailCount > 0 {
            s += LF(" The %d rows below are the engine's own figures for that same disk — not counted again.",
                    model.detailCount)
        }
        return s
    }
}
