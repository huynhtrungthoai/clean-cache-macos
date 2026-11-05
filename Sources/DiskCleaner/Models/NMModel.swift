import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class NMModel: ObservableObject {
    @Published var items: [NMProject] = []
    @Published var scanning = false
    /// 上一轮是被**按停**的：列里只有量完的那几行，页头要说清这不是全貌。
    @Published var stoppedEarly = false
    @Published private(set) var started = false
    /// 现场读数。这一趟数的是**目录项**不是文件：整棵家目录翻下来一个 node_modules
    /// 都可能没撞上，但「正在看 ~/Projects/foo/src」那句是真的在往前走的证据。
    private(set) var progress = ScanProgress(counted: .entries)
    private var task: Task<Void, Never>? = nil
    /// 一轮一个号。按停后立刻重扫时，上一轮的尾巴批次还在路上，靠它挡住——
    /// 否则两轮的行会混进同一列，而那一列看着像「这台机器的依赖」。
    private var gen = 0

    var selected: [NMProject] { items.filter { $0.selected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    var selectAll: SelectAll? {
        guard !items.isEmpty else { return nil }
        return SelectAll(allSelected: items.allSatisfy(\.selected), unselectable: 0) { on in
            for i in self.items.indices { self.items[i].selected = on }
        }
    }

    func scan() {
        task?.cancel()
        gen += 1
        scanning = true
        started = true
        stoppedEarly = false
        items = []
        progress = ScanProgress(counted: .entries)
        let mine = gen
        task = Task {
            let list = await findNodeModules(progress: self.progress) { batch in
                Task { @MainActor in if self.gen == mine { self.merge(batch) } }
            }
            if !Task.isCancelled {
                if self.gen == mine { self.merge(list) }
                self.scanning = false
            }
        }
    }

    func stop() {
        task?.cancel()
        guard scanning else { return }
        scanning = false
        stoppedEarly = true
    }

    /// 只合进**没见过的路径**，且按容量降序插位：行是同一批对象（`id` 不变，勾选不掉），
    /// 扫描途中也只是往下长，不整列重排。
    ///
    /// 一批一次赋值（而不是每行一次通知）：验收那句「刷新节流」按一次 diff 算，
    /// 125 行 39 批就是 39 次重画而不是 125 次。实测这条不影响耗时，也没能消掉 AppKit
    /// 那两条 `reentrant operation in its NSTableView delegate`（见 proofs 里的对照组）。
    private func merge(_ batch: [NMProject]) {
        guard !batch.isEmpty else { return }
        var seen = Set(items.map(\.project))
        var next = items
        for p in batch where !seen.contains(p.project) {
            seen.insert(p.project)
            next.insert(p, at: next.firstIndex { $0.size < p.size } ?? next.endIndex)
        }
        if next.count != items.count { items = next }
    }
}
