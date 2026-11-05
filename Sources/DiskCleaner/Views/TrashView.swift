import SwiftUI
import DiskCleanerCore

// ── 废纸篓面板：体积 + 撤销 + 交给访达清空 ──
// 清空这一步永远由访达执行，本工具不自己删。

struct TrashView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @State private var info: (items: Int, bytes: Int64)? = nil
    @State private var measuring = false
    @State private var measureTask: Task<Void, Never>? = nil
    @State private var confirmEmpty = false
    @State private var message: String? = nil
    /// 上一次失败到底是不是「系统没放行自动化」——只有是的时候才摆授权入口
    @State private var automationGate = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "trash", title: L("Trash"),
                       subtitle: L("Everything waits here, fully reversible — emptying is the point of no return"),
                       variant: .display)
                .pagePadding()
                .padding(.top, 14)
                .padding(.bottom, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        ThemedCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Trash right now"))
                                    .font(theme.bodyFont(.caption))
                                    .foregroundStyle(theme.palette.inkTertiary)
                                SizeNumber(shown: sizeText, size: 34)
                                Text(footLine)
                                    .font(theme.bodyFont(.caption2))
                                    .foregroundStyle(theme.palette.inkTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // 二级数：白底 34pt 旁边这张是灰底 17pt（规矩 ②）。
                        // 原先两张卡两个 largeTitle 并排，一屏里最大的数有两颗，
                        // 谁才是「这一屏的答案」得靠读字；而右边那颗在没往里移东西时拍的是一枚零。
                        ThemedCard(alt: true) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Moved this session"))
                                    .font(theme.bodyFont(.caption))
                                    .foregroundStyle(theme.palette.inkTertiary)
                                SizeNumber(shown: sized(store.trashedBytes), size: 17,
                                           color: theme.palette.inkSecondary)
                                Text(LF("Undo available for %@", cnt(store.trashHistory.count, "items")))
                                    .font(theme.bodyFont(.caption2))
                                    .foregroundStyle(theme.palette.inkTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ThemedCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "shield.checkerboard")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.palette.tint)
                            Text(L("Every “delete” here only moves items to the Trash. Freeing space for real means emptying it — a step Finder carries out, and Finder makes you confirm first."))
                                .font(theme.bodyFont(.callout))
                                .foregroundStyle(theme.palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        ThemeButton(kind: .secondary, symbol: "folder",
                                    title: L("Open in Finder")) { openTrashInFinder() }
                        ThemeButton(kind: .secondary, symbol: "arrow.clockwise",
                                    title: L("Recount")) { refresh() }
                        ThemeButton(kind: .secondary, symbol: "arrow.uturn.backward",
                                    title: L("Undo last"),
                                    isDisabled: store.trashHistory.isEmpty) {
                            Sound.shared.play(.undo)
                            message = store.undoLast()
                            refresh()
                        }
                        Spacer()
                        if canCommandFinder {
                            ThemeButton(kind: .danger, symbol: "flame",
                                        title: L("Empty Trash"),
                                        isDisabled: info?.items == 0) { confirmEmpty = true }
                        } else {
                            ThemeButton(kind: .danger, symbol: "flame",
                                        title: L("Empty in Finder"),
                                        isDisabled: info?.items == 0) { emptyInFinder() }
                        }
                    }

                    if let m = message {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(m)
                                .font(theme.bodyFont(.callout))
                                .foregroundStyle(theme.palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if automationGate {
                                ThemeButton(kind: .compact, symbol: "lock.open",
                                            title: L("Open Automation settings")) {
                                    openAutomationPane()
                                }
                            }
                        }
                    }

                    if !store.trashHistory.isEmpty {
                        SectionLabel(text: L("This session"), detail: L("Newest first"))
                        historyList
                        Text(historyNote)
                            .font(theme.bodyFont(.caption))
                            .foregroundStyle(theme.palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 9)
                    }
                }
                .pagePadding()
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refresh() }
        .onDisappear { measureTask?.cancel() }
        .alert(L("Empty the Trash?"), isPresented: $confirmEmpty) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Empty via Finder"), role: .destructive) { empty() }
        } message: {
            Text(L("Finder carries this step out — this app never deletes anything permanently on its own. Emptying cannot be undone."))
        }
    }

    /// 操作记录 = 一块账本：行自己不带盒子，格与格之间靠顶上那道 1px 分段线分开（规矩 ③）。
    ///
    /// 原先每条记录一张描边卡，十步撤销就是十个盒子，读出来是「十件不相干的东西」
    /// 而不是「一张表」；数还是单档 13pt、单位跟数字一样大，一列比不出大小。
    private var historyList: some View {
        let recs = Array(store.trashHistory.reversed())
        let shown = addableHumanColumn(recs.map(\.size), total: store.trashedBytes,
                                       inRulerOf: rulerTotal)
        return VStack(spacing: 0) {
            ForEach(Array(recs.enumerated()), id: \.offset) { idx, rec in
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.palette.inkTertiary)
                    Text(rec.displayName)
                        .font(theme.bodyFont(.callout))
                        .foregroundStyle(theme.palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 10)
                    SizeNumber(shown: shown[idx], size: 17, color: theme.palette.inkSecondary)
                        .fixedSize()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    if idx > 0 {
                        Rectangle().fill(theme.palette.separator.opacity(0.7))
                            .frame(height: 1).padding(.horizontal, 8)
                    }
                }
            }
        }
        .background(theme.cardShape().fill(theme.palette.surface))
        .overlay(theme.cardShape().stroke(theme.palette.separator, lineWidth: theme.metric.stroke))
    }

    /// 这一列与右上那张卡是同一笔账：印出来的那几串字相加就是卡上那个数
    /// （整列按卡的单位分摊过，不各说各的）。
    private var historyNote: String {
        LF("These %1$d rows add up to %2$@ — the number under “Moved this session” above.",
           store.trashHistory.count, sized(store.trashedBytes))
    }

    private var sizeText: String {
        if measuring { return L("Counting…") }
        guard let info else { return L("Unknown") }
        return sized(info.bytes)
    }

    /// 两张卡的数走同一把尺：现在印 GB、本次移入印 MB，并排就没法比大小。
    private var rulerTotal: Int64 { max(info?.bytes ?? 0, store.trashedBytes) }

    /// 两边都是 0 时不硬撑单位——「0 B」比「0.0 KB」诚实，那是真的空着。
    private func sized(_ bytes: Int64) -> String {
        rulerTotal > 0 ? human(bytes, inRulerOf: rulerTotal) : human(bytes)
    }

    /// 主数下面那行小字。「本次没往里移东西」这句是给右边那张灰底卡作的说明：
    /// 那颗零是真的零，不是没量到。
    private var footLine: String {
        if measuring { return L("Counting every item…") }
        guard let info else { return L("Not readable here — Finder has the real number") }
        var s = cnt(info.items, "items")
        if store.trashedBytes == 0 { s += " · " + L("nothing moved this session") }
        return s
    }

    /// 沙盒版实测（macOS 26.6）：发往访达的事件被 appleeventsd 直接掐掉
    /// （`deny appleevent-send com.apple.finder`），连授权框都不弹，TCC 全程没被问过。
    /// 所以商店版不该摆一颗永远点不亮的「交给访达清空」。
    private var canCommandFinder: Bool { !HomeAccess.runsSandboxed }

    private func emptyInFinder() {
        automationGate = false
        message = L("The Trash is open in Finder — press ⌘⇧⌫ and Finder will ask you to confirm before it empties.")
        openTrashInFinder()
    }

    private func refresh() {
        measureTask?.cancel()
        measuring = true
        info = nil
        measureTask = Task {
            let r = await trashInfo()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                info = r
                measuring = false
            }
        }
    }

    private func empty() {
        automationGate = false
        message = L("Asking Finder to empty it…")
        // 清空这一步要同步等访达的事件回执：它可能先弹自己的确认框，清空一个大
        // 废纸篓也能持续好几秒。搁主线程上点完就冻住，看着就是「按了没反应」。
        Task {
            let job: (free: Int64?, result: Result<Void, Error>) = await Task.detached(priority: .userInitiated) {
                let before = volumeUsage()?.free
                return (before, Result { try emptyTrashViaFinder() })
            }.value
            await MainActor.run { finishEmpty(job) }
        }
    }

    private func finishEmpty(_ job: (free: Int64?, result: Result<Void, Error>)) {
        switch job.result {
        case .success:
            // 访达是异步清空的，等 2 秒再读，报告真实释放量
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let before = job.free ?? 0
                let after = volumeUsage()?.free ?? before
                await MainActor.run {
                    message = LF("Asked Finder to empty it — roughly %@ actually freed (count it once Finder finishes).", human(max(0, after - before)))
                    store.clearHistory()
                    refresh()
                }
            }
        case .failure(let error):
            // 报访达的原话 + 错误号，而不是 Swift 自动生成的「错误 N」——
            // 那个数字既不告诉用户下一步，也让我们远程排查时什么都问不出来。
            let why = failReason(error)
            if let t = error as? TrashError {
                switch t {
                case .automationDenied:
                    automationGate = true
                    message = LF("Emptying failed: %@. macOS hasn't let this app drive Finder — tick Finder under Privacy & Security → Automation, then relaunch CleanPilot and try again.", why)
                case .finderUnreachable:
                    // 指令压根没送到访达，报「访达拒绝执行」是错怪它。沙盒版就是这样：
                    // 系统不让本工具联系访达，「去勾自动化」也是死路，只能在访达里清。
                    message = LF("Emptying failed: %@. This step has to happen in Finder — the Trash is now open there: press ⌘⇧⌫ and Finder will ask you to confirm first.", why)
                    openTrashInFinder()
                case .finderCanceled:
                    message = LF("%@. Nothing was emptied — the items are still in the Trash.", why)
                default:
                    message = LF("Emptying failed: %@. You can also empty it by hand: hit “Open in Finder” above, then press ⌘⇧⌫ in the Finder window.", why)
                }
            } else {
                message = LF("Emptying failed: %@.", why)
            }
            refresh()
        }
    }

    private func openAutomationPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
