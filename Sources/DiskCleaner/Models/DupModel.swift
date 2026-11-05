import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class DupModel: ObservableObject {
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
        let minB = Int64(minMB) * MB
        let targets = defaultScanDirs(scope: scope)
        task = Task {
            self.phase = L("Walking files…")
            self.progress = ScanProgress()
            // 只留下我们删得动的：整盘扫描会走进 /Library、/opt 这些 root 地盘，
            // 那些重复归包管理器管，列出来只会让用户去点一个注定失败的勾选框。
            let files = await walkFiles(dirs: targets, minSize: minB,
                                        skipNames: ["node_modules", ".git", "Caches"],
                                        progress: self.progress)
                .rows.filter(\.deletable)
            if Task.isCancelled { return }
            self.phase = LF("Comparing contents (%@ candidates)…", String(files.count))
            // 哈希是同步重活，扔后台线程做
            let r = await Task.detached { findDupGroups(files) }.value
            if !Task.isCancelled {
                self.groups = r.groups
                self.envGroups = r.excluded
                self.scanning = false
                self.phase = ""
            }
        }
    }

    func stop() { task?.cancel(); scanning = false }

    /// 「全选」只管多余的那几份，每组保留的那一份算在「不在全选范围内」里：
    /// 它列在同一个组里却永远勾不动，不报这个数用户只会以为漏勾了一份。
    /// 反向也必须能按——这一页动辄几百项，一次勾错没有一键撤回路可走不通。
    var selectAll: SelectAll? {
        let extras = groups.flatMap { $0.files.dropFirst() }
        guard !extras.isEmpty else { return nil }
        return SelectAll(allSelected: extras.allSatisfy { selection.contains($0.path) },
                         unselectable: groups.count) { on in
            self.selection = on ? Set(extras.map(\.path)) : []
        }
    }
}
