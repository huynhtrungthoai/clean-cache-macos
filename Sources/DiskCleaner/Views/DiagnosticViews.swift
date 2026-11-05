import DiskCleanerCore
import SwiftUI

// 诊断与转储：崩溃转储 / 系统诊断报告 / 观察区三页，共用一个数据源（DiagnosticsHub）。
// 设计出处：plans/design-ui-and-interfaces-2026-10-27.md 屏①②⑦（PR-1 范围）。
// 流速徽标（PR-2）、归属抽屉（PR-3）、保留策略（PR-4）都在这份骨架上往上叠。

// MARK: - 数据源

// MARK: - 崩溃转储

struct CrashDumpsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var hub: DiagnosticsHub
    @State private var confirm = false
    @State private var err: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "ladybug", title: L("Crash dumps"),
                           subtitle: L("Records left behind by crashes — pile up long enough and they become an incident"),
                           variant: .display)
                ControlStrip {
                    if hub.scanning {
                        LoadingRow(text: L("Looking for crash dumps in application data…"))
                    } else if hub.baselinePending {
                        Text(L("Baseline saved; comparisons start on the next scan"))
                    } else {
                        Text(LF("%1$@, %2$@ in total", cnt(hub.hits.count, "apps"), human(hub.totalBytes)))
                    }
                } trailing: {
                    ScanControl(scanning: hub.scanning,
                                rescan: { hub.discover(force: true) },
                                stop: { hub.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            if !hub.hits.isEmpty {
                RetentionBanner()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            if hub.scanning && hub.hits.isEmpty {
                EmptyState(symbol: "ladybug",
                           title: L("Looking for crash dumps in application data"),
                           hint: L("Just a few levels of app data get walked; sizes and counts come back together"))
                    .frame(maxHeight: .infinity)
            } else if !hub.scanning && hub.hits.isEmpty {
                EmptyState(symbol: "ladybug",
                           title: L("No crash dumps found"),
                           hint: L("No Crashpad structure on this machine"))
                    .frame(maxHeight: .infinity)
            } else {
                List(hub.hits) { hit in
                    ItemRow(selected: hitBinding(hit),
                            icon: .path(URL(fileURLWithPath: hit.path)),
                            name: hit.host.map { "\($0) \(L("crash dumps"))" } ?? L("Crash dumps"),
                            sub: hitSub(hit),
                            sizeText: shown[hit.id] ?? human(hit.bytes),
                            fraction: Double(hit.bytes) / Double(maxBytes),
                            badge: velocityBadge(hit),
                            badge2: attributionBadge(hit)) {
                        ExplainLine(key: L("What it is"), value: L("Records left behind by crashes"))
                        ExplainLine(key: L("What breaks"), value: L("Deleting changes nothing; new crashes write new ones"))
                        ExplainLine(key: L("How to recover"), value: L("Gone once deleted — and never worth restoring"))
                        attributionLines(hit)
                        trimButton(hit)
                        PathLine(path: hit.path)
                    }
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)

            CleanBar(count: hub.selectedHits.count,
                     bytes: hub.selectedBytes,
                     bytesText: human(hub.selectedBytes, inRulerOf: hub.totalBytes),
                     errorText: err,
                     selection: hub.hitSelectAll,
                     busyHint: hub.scanning ? L("Still scanning — cleanup starts once it finishes or you stop") : nil) {
                confirm = true
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { hub.discover() }
        .sheet(isPresented: trimSheetOpen) { TrimSheet(hub: hub) }
        .confirmTrash(isPresented: $confirm,
                      text: LF("Move %1$@ (%2$@) to the Trash.",
                               cnt(hub.selectedHits.count, "apps"),
                               human(hub.selectedBytes, inRulerOf: hub.totalBytes))) {
            doClean()
        }
    }

    private var trimSheetOpen: Binding<Bool> {
        Binding(get: { hub.trim != nil }, set: { if !$0 { hub.trim = nil } })
    }

    private var maxBytes: Int64 { max(1, hub.hits.map(\.bytes).max() ?? 1) }

    /// 整列统一到页头那个总数的单位再分摊：印出来的行加起来就是页头那句。
    private var shown: [String: String] {
        sizeColumn(hub.hits.map { (key: $0.id, bytes: $0.bytes) })
    }

    private func hitBinding(_ hit: CategoryHit) -> Binding<Bool> {
        Binding(get: { hub.hitSelection.contains(hit.id) },
                set: { on in
                    if on { hub.hitSelection.insert(hit.id) } else { hub.hitSelection.remove(hit.id) }
                })
    }

    private func hitSub(_ hit: CategoryHit) -> String {
        var parts = [displayPath(URL(fileURLWithPath: hit.path))]
        parts.append(cnt(hit.files, "files"))
        if let v = hub.velocity[hit.id], v.tier != nil {
            parts.append(LF("%1$@ since last · %2$@", "+" + cnt(v.deltaFiles, "files"),
                            velocityInterval(v.intervalSeconds)))
        }
        return parts.joined(separator: " · ")
    }

    /// 两档徽标：速率命中红「流速异常」、仅绝对量命中黄「显著增长」（评审 §2.1）。
    private func velocityBadge(_ hit: CategoryHit) -> ItemBadge? {
        guard let v = hub.velocity[hit.id], let tier = v.tier else { return nil }
        switch tier {
        case .red: return ItemBadge(text: L("Growing fast"), tone: .danger)
        case .yellow: return ItemBadge(text: L("Notable growth"), tone: .warn)
        }
    }

    /// 归属徽标与流速徽标是两条轴：那枚说「长得快不快」，这枚说「是谁的」。
    /// 混合灰、跨归属黄；探针没开或没探上就不给——不撒谎。
    private func attributionBadge(_ hit: CategoryHit) -> ItemBadge? {
        guard let a = hub.attribution[hit.id], a.probed else { return nil }
        if a.mixed { return ItemBadge(text: L("Mixed sources"), tone: .neutral) }
        if a.crossAttribution { return ItemBadge(text: L("Split attribution"), tone: .warn) }
        return nil
    }

    /// 归属明细三行：目录 × 内容 × 发起源。探针关或没探上时只有「内容未探测」一句。
    @ViewBuilder private func attributionLines(_ hit: CategoryHit) -> some View {
        if let a = hub.attribution[hit.id], a.probed {
            ExplainLine(key: L("Directory owner"), value: a.directoryOwner ?? "—")
            if a.mixed {
                ExplainLine(key: L("Content owner"), value: LF("Mixed sources (%@ samples probed)", String(a.samples)))
            } else if let owner = a.contentOwner {
                let line = owner + (a.crossAttribution ? " · " + L(" · directory and content owners differ") : "")
                ExplainLine(key: L("Content owner"), value: line)
            } else {
                ExplainLine(key: L("Content owner"), value: L("Content not probed"))
            }
            if !a.redactedHints.isEmpty {
                ExplainLine(key: L("Origin"), value: a.redactedHints.joined(separator: " · "))
            }
        } else {
            ExplainLine(key: L("Content owner"), value: L("Content not probed"))
        }
    }

    private func velocityInterval(_ seconds: Double) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes >= 1440 { return cnt(minutes / 1440, "days") }
        return cnt(minutes, "minutes")
    }

    /// 处置入口：保留策略启用时才有「预览修剪」。没启用就只有底部常规清理。
    @ViewBuilder private func trimButton(_ hit: CategoryHit) -> some View {
        if crashRetention() != nil {
            HStack {
                ThemeButton(kind: .secondary, symbol: "scissors", title: L("Preview trim…")) {
                    hub.prepareTrim(for: hit)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    /// 移的是可清理面（四个子目录整目录），settings.dat 与目录骨架不动。
    /// 子目录作单位是性能约束：16 万个 dump 逐个进废纸篓就是 16 万次回收登记，
    /// 四笔才落在预算内。撤销粒度随之是「一个子目录一次」，整批撤销进 PR-4 的修剪流。
    private func doClean() {
        err = nil
        let targets = hub.selectedHits
        let spec = CategoryRule.crashDumps.safeDeleteSpec
        Task { @MainActor in
            var errs: [String] = []
            var cleaned: Set<String> = []
            for hit in targets {
                guard let spec else { continue }
                let root = URL(fileURLWithPath: hit.path)
                var moved = 0
                for dir in spec.cleanTargets(under: root) {
                    guard FileManager.default.fileExists(atPath: dir.path) else { continue }
                    do {
                        let size = await dirSize(dir)
                        let dst = try trashItem(dir)
                        store.record(TrashRecord(original: dir, inTrash: dst, size: size,
                                                 displayName: "\(hit.host ?? dir.path)/Crashpad/\(dir.lastPathComponent)"))
                        moved += 1
                    } catch {
                        errs.append(failLine(dir.lastPathComponent, error))
                    }
                }
                if moved > 0 { cleaned.insert(hit.id) }
            }
            hub.removeHits(cleaned)
            if errs.isEmpty {
                store.notice = trashedNotice(cleaned.count, "apps", failed: 0)
            } else {
                err = errList(errs)
            }
        }
    }
}

// MARK: - 系统诊断报告

struct DiagReportsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var hub: DiagnosticsHub
    @State private var confirm = false
    @State private var err: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "stethoscope", title: L("System diagnostics reports"),
                           subtitle: L("Logs the system writes to troubleshoot, kept to locate problems"),
                           variant: .display)
                ControlStrip {
                    if hub.scanning {
                        LoadingRow(text: L("Reading the diagnostics reports folder…"))
                    } else {
                        Text(LF("%1$@, %2$@ in total", cnt(hub.reports.count, "files"), human(hub.reportBytes)))
                    }
                } trailing: {
                    ScanControl(scanning: hub.scanning,
                                rescan: { hub.discover(force: true) },
                                stop: { hub.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            if hub.scanning && hub.reports.isEmpty {
                EmptyState(symbol: "stethoscope",
                           title: L("Reading the diagnostics reports folder"),
                           hint: L("Only .ips, .hang and .panic files are read"))
                    .frame(maxHeight: .infinity)
            } else if !hub.scanning && hub.reports.isEmpty {
                EmptyState(symbol: "stethoscope",
                           title: L("No diagnostics reports"),
                           hint: L("Nothing has piled up recently"))
                    .frame(maxHeight: .infinity)
            } else {
                List(hub.reports) { file in
                    ItemRow(selected: fileBinding(file),
                            icon: .path(file.url),
                            name: file.process ?? file.url.lastPathComponent,
                            sub: fileSub(file),
                            sizeText: shown[file.id] ?? human(file.size),
                            fraction: Double(file.size) / Double(maxBytes)) {
                        ExplainLine(key: L("What it is"), value: L("Log files the system writes to troubleshoot"))
                        ExplainLine(key: L("What breaks"), value: L("The system is unaffected; you just lose the evidence for troubleshooting"))
                        PathLine(path: file.url.path)
                    }
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)

            CleanBar(count: hub.selectedReports.count,
                     bytes: hub.selectedReportBytes,
                     bytesText: human(hub.selectedReportBytes, inRulerOf: hub.reportBytes),
                     errorText: err,
                     selection: hub.reportSelectAll,
                     busyHint: hub.scanning ? L("Still scanning — cleanup starts once it finishes or you stop") : nil) {
                confirm = true
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { hub.discover() }
        .confirmTrash(isPresented: $confirm,
                      text: LF("Move %1$@ (%2$@) to the Trash.",
                               cnt(hub.selectedReports.count, "files"),
                               human(hub.selectedReportBytes, inRulerOf: hub.reportBytes))) {
            doClean()
        }
    }

    private var maxBytes: Int64 { max(1, hub.reports.map(\.size).max() ?? 1) }

    private var shown: [String: String] {
        sizeColumn(hub.reports.map { (key: $0.id, bytes: $0.size) })
    }

    private func fileBinding(_ file: ReportFile) -> Binding<Bool> {
        Binding(get: { hub.reportSelection.contains(file.id) },
                set: { on in
                    if on { hub.reportSelection.insert(file.id) } else { hub.reportSelection.remove(file.id) }
                })
    }

    private func fileSub(_ file: ReportFile) -> String {
        displayPath(file.url.deletingLastPathComponent())
    }

    /// 报告是散文件：逐个进废纸篓，量小（几十到几百份），每份一条可撤销记录。
    private func doClean() {
        err = nil
        let targets = hub.selectedReports
        var errs: [String] = []
        for file in targets {
            do {
                let dst = try trashItem(file.url)
                store.record(TrashRecord(original: file.url, inTrash: dst, size: file.size,
                                         displayName: file.url.lastPathComponent))
            } catch {
                errs.append(failLine(file.url.lastPathComponent, error))
            }
        }
        hub.removeReports(Set(targets.map(\.id)))
        if errs.isEmpty {
            store.notice = trashedNotice(targets.count, "files", failed: 0)
        } else {
            err = errList(errs)
        }
    }
}

// MARK: - 观察区

/// 只读清单：能看见、动不了的东西。没有勾选框、没有清理条（设计稿屏⑦的交互红线）。
/// 原因码与 agent 通道的拒绝词同源，同一件事在两个入口叫同一个名字。
struct ObservationView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var hub: DiagnosticsHub
    @State private var asking: ObservationItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "eye", title: L("Observation"),
                           subtitle: L("Everything you can see but not delete lives here"),
                           variant: .display)
                ControlStrip {
                    if hub.scanning {
                        LoadingRow(text: L("Looking for crash dumps in application data…"))
                    } else {
                        Text(LF("%@ total", cnt(hub.observation.count, "items")))
                    }
                } trailing: {
                    ScanControl(scanning: hub.scanning,
                                rescan: { hub.discover(force: true) },
                                stop: { hub.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            List(hub.observation) { item in
                ItemRow(selected: .constant(false),
                        icon: .path(URL(fileURLWithPath: item.path)),
                        name: name(of: item),
                        sub: sub(of: item),
                        sizeText: item.bytes.map { human($0) } ?? "—",
                        fraction: 0,
                        badge: ItemBadge(text: reasonLabel(item.reason), tone: .neutral),
                        selectable: false,
                        lit: false) {
                    ExplainLine(key: L("Why can't this be deleted?"), value: reasonExplain(item.reason))
                    PathLine(path: item.path)
                }
                .contextMenu {
                    Button {
                        asking = item
                    } label: {
                        Label(L("Why can't this be deleted?"), systemImage: "questionmark.circle")
                    }
                }
            }
            .ledgerCard()

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .onAppear { hub.discover() }
        .alert(L("Why can't this be deleted?"),
               isPresented: Binding(get: { asking != nil },
                                    set: { if !$0 { asking = nil } })) {
            Button(L("Got it"), role: .cancel) {}
        } message: {
            Text(reasonExplain(asking?.reason ?? .unknownClass))
        }
    }

    private func name(of item: ObservationItem) -> String {
        let url = URL(fileURLWithPath: item.path)
        return url.lastPathComponent.isEmpty ? item.path : url.lastPathComponent
    }

    private func sub(of item: ObservationItem) -> String {
        var parts = [displayPath(URL(fileURLWithPath: item.path))]
        if let files = item.files { parts.append(cnt(files, "files")) }
        return parts.joined(separator: " · ")
    }
}

/// 原因码 → 短标签（行内那枚徽章）
func reasonLabel(_ reason: ObservationReason) -> String {
    switch reason {
    case .outsideAllowed: return L("Outside the allowed cleaning scope")
    case .blacklistedSystemDir: return L("Blacklisted system folder")
    case .unknownClass: return L("Incomplete structure, not sure enough")
    case .appDataUnattributed: return L("Data not attributed to any app")
    }
}

/// 原因码 → 整句解释（右键「为什么不能删」与行内明细共用一份，两个入口一个说法）
func reasonExplain(_ reason: ObservationReason) -> String {
    switch reason {
    case .outsideAllowed:
        return L("Outside your home folder and Applications this tool moves nothing; if you must, do it yourself in the Finder.")
    case .blacklistedSystemDir:
        return L("System folders are on the protected list; only the system itself may touch them.")
    case .unknownClass:
        return L("Named like a crash dump, but the structure is incomplete; unsure means untouched.")
    case .appDataUnattributed:
        return L("No app has been identified for this data yet; watching only for now.")
    }
}

// MARK: - 建议条与修剪三步流（PR-4）

/// 首次遇到再生类别的建议条：只出现一次，采用=写设置并落到该类全部条目，
/// 不再提示=只记账。不自动启用——自动修剪就是隐形守护进程（设计稿 §6.2）。
private struct RetentionBanner: View {
    @Environment(\.theme) private var theme
    @AppStorage("crashDumps.retentionSuggested") private var suggested = false

    var body: some View {
        if !suggested {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.palette.tint)
                Text(LF("The new “crash dumps” category regrows. Suggested policy: keep the latest %@.",
                        cnt(2_000, "个")))
                    .font(theme.bodyFont(.callout))
                Spacer()
                ThemeButton(kind: .primary, title: L("Adopt")) {
                    setCrashRetention(Retention(kind: .count(2_000)))
                    suggested = true
                }
                ThemeButton(kind: .ghost, title: L("Don't suggest again")) { suggested = true }
            }
            .padding(12)
            .background(theme.palette.tintSoft, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// 修剪三步流：预览（终稿）→ 执行（进度）→ 完成（释放量 + 整批撤销 + 渠道分支的清空提示）。
/// 沙盒版发往访达的清空事件被系统掐掉，所以商店版只给「在访达中打开废纸篓」
/// （评审 §2.4-1：事故场景在商店版必须交代清空这最后一步去哪了）。
private struct TrimSheet: View {
    @Environment(\.theme) private var theme
    @ObservedObject var hub: DiagnosticsHub

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch hub.trim {
            case .preview(_, let plan):
                Text(L("Trim by policy")).font(theme.display(.headline))
                kvLine(L("Retention policy"), LF("Latest %@", cnt(plan.keep, "个")))
                kvLine(L("Will trim"), LF("%1$@ · %2$@", cnt(plan.remove.count, "files"), human(plan.removeBytes)))
                if let oldest = plan.oldestKeptMtime {
                    kvLine(L("Oldest kept"), oldest.formatted(date: .abbreviated, time: .shortened))
                }
                Text(L("Everything goes to the Trash and can be undone as a batch; settings.dat and the folder skeleton stay. Preview numbers come from a pure calculation and are final."))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkSecondary)
                HStack {
                    Spacer()
                    ThemeButton(kind: .ghost, title: L("Cancel")) { hub.trim = nil }
                    ThemeButton(kind: .primary, title: L("Trim")) { hub.runTrim() }
                }
            case .running(let done, let total):
                Text(L("Moving to Trash…")).font(theme.display(.headline))
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text(LF("%1$@ / %2$@", String(done), String(total)))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .done(let bytes, let skipped, let batchID):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.palette.safeFG)
                    Text(LF("Trimmed · about %@ freed", human(bytes))).font(theme.display(.headline))
                }
                Text(L("settings.dat kept; the batch is in the trim ledger and can be undone as a whole."))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkSecondary)
                if skipped > 0 {
                    Text(LF("Skipped %d (changed since preview — no silent swaps)", skipped))
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.warnFG)
                }
                Text(L("Space is freed only after the Trash is emptied."))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkSecondary)
                HStack {
                    // P0-6: this used to empty the WHOLE Trash via AppleScript with no confirm
                    // (unrelated items included, errors swallowed, undo history left dangling),
                    // right next to "undo batch". Only open the Trash; emptying stays a deliberate
                    // act in Finder (or on the Trash page, which confirms and clears history).
                    ThemeButton(kind: .secondary, symbol: "folder", title: L("Open Trash in Finder")) {
                        openTrashInFinder()
                    }
                    Spacer()
                    ThemeButton(kind: .secondary, symbol: "arrow.uturn.backward", title: L("Undo batch")) {
                        hub.undoTrim(batchID: batchID)
                    }
                }
            case nil:
                EmptyView()
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }

    private func kvLine(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(theme.palette.inkSecondary)
            Spacer()
            Text(v)
        }
        .font(theme.bodyFont(.callout))
    }
}
