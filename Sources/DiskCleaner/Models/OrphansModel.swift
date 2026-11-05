import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class OrphansModel: ObservableObject {
    @Published var items: [OrphanItem] = []
    @Published var scanning = false
    @Published var appCount = 0
    @Published private(set) var started = false
    /// 现场读数：这页慢在「逐个残留目录量体积」那一步，几分钟里没别的可看。
    private(set) var progress = ScanProgress()
    private var task: Task<Void, Never>? = nil

    var selected: [OrphanItem] { items.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + ($1.size ?? 0) } }
    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }

    /// 全选只扫「删了没影响」那批：这页的立脚点是宁可漏报不可误删，标「删了会丢数据」的意思是
    /// 「得你自己判」，一键把它带走等于把这页存在的理由按掉了。
    var selectAll: SelectAll? {
        let open = items.filter { $0.level != "warn" }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy(\.selected),
                         unselectable: items.count - open.count) { on in
            for i in self.items.indices where self.items[i].level != "warn" {
                self.items[i].selected = on
            }
        }
    }

    func scan() {
        task?.cancel()
        scanning = true
        started = true
        items = []
        progress = ScanProgress()
        task = Task {
            let (list, apps) = await scanOrphans(progress: self.progress)
            if !Task.isCancelled {
                self.items = list
                self.appCount = apps
                self.scanning = false
            }
        }
    }

    func stop() { task?.cancel(); scanning = false }
}
