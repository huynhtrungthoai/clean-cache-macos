import SwiftUI
import DiskCleanerCore

/// 由 ScanStore 持有：视图随导航销毁，模型不能跟着一起销毁
@MainActor
final class DockerModel: ObservableObject {
    @Published var items: [DockerItem] = []
    @Published var scanning = false
    @Published private(set) var started = false
    /// 现场读数：这一趟要问引擎一把，再逐家量虚拟机磁盘的实占，几秒钟里得说清走到哪儿了。
    private(set) var progress = ScanProgress(counted: .entries)
    private var task: Task<Void, Never>? = nil

    /// 页头那个「共 X」：只加**段**，不加段下面的明细。
    ///
    /// 原来这里是 `items.reduce`，而 `items` 里既装着 `docker system df` 的四段合计、
    /// 又装着它们各自的镜像明细（`ScanJobs.swift` 把 `imgItems` 追加进了同一个数组），
    /// 于是同一份字节数了两遍，实拍拍出过「共 56.5 GB」而真实占用是 41.3 GB。
    /// 明细照样列出来（那是这一页唯一能报出名字的东西），只是不进加法。
    var totalBytes: Int64 { items.filter(\.countsInTotal).reduce(0) { $0 + $1.size } }
    var detailCount: Int { items.filter { !$0.countsInTotal }.count }

    func scan() {
        task?.cancel()
        scanning = true
        started = true
        items = []
        progress = ScanProgress(counted: .entries)
        let prog = progress
        // 短名在这儿取：Core 不认识 `.strings`，而这一格的短名得跟着界面语言走。
        // 它跟「一行一个运行时」那几格用的词不能撞——引擎那家自己也在运行时之列，
        // 两格都写 `orbstack` 的话，清单就答不出「现在走到的是哪一件活」。
        let engineLabel = L("The engine's own total")
        task = Task {
            let list = await Task.detached {
                await scanDocker(engineLabel: engineLabel, progress: prog)
            }.value
            if !Task.isCancelled {
                self.items = list
                self.scanning = false
            }
        }
    }

    func stop() { task?.cancel(); scanning = false }
}
