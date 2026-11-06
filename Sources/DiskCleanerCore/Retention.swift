import Foundation

// MARK: - Retention policy & pruning (PR-4)
//
// Design: plans/design-diagnostic-dumps-velocity-provenance-2026-10-27.md §6,
// review revision §3.1: preview numbers come from pure computation and are final; before executing, each item's dev/ino is re-checked,
// and items that differ from the preview are skipped and reported (following the agent channel's execute precedent).
// No automatic pruning: "retention policy + automatic execution" is a hidden daemon, breaking the no-daemon promise.

/// Retention policy for regenerable categories. nil = disabled (default).
public struct Retention: Equatable {
    public enum Kind: Equatable {
        case count(Int)
        case bytes(Int64)
    }
    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}

/// One row of the prune list. dev/ino re-checked at execution: the file may be swapped between preview and execution.
public struct TrimFile: Equatable {
    public let url: URL
    public let size: Int64
    public let dev: Int
    public let ino: Int

    public init(url: URL, size: Int64, dev: Int, ino: Int) {
        self.url = url
        self.size = size
        self.dev = dev
        self.ino = ino
    }
}

/// Prune plan from pure computation: the preview is final; not recomputed after confirmation.
public struct TrimPlan: Equatable {
    public let keep: Int
    public let remove: [TrimFile]
    public let oldestKeptMtime: Date?

    public var removeBytes: Int64 { remove.reduce(0) { $0 + $1.size } }

    public init(keep: Int, remove: [TrimFile], oldestKeptMtime: Date?) {
        self.keep = keep
        self.remove = remove
        self.oldestKeptMtime = oldestKeptMtime
    }
}

/// Enumerate .dmp files in the cleanable surface, keep the newest by mtime, put the rest on the prune list.
/// Looks only at structure, never contents; the executor re-checks dev/ino.
public func trimPlan(under dirs: [URL], retention: Retention) -> TrimPlan {
    let fm = FileManager.default
    struct Meta { let url: URL; let size: Int64; let mtime: Date; let dev: Int; let ino: Int }
    var metas: [Meta] = []
    for d in dirs {
        guard let names = try? fm.contentsOfDirectory(atPath: d.path) else { continue }
        for n in names where (n as NSString).pathExtension.lowercased() == "dmp" {
            let u = d.appendingPathComponent(n)
            var st = stat()
            guard lstat(u.path, &st) == 0 else { continue }
            metas.append(Meta(url: u, size: Int64(clamping: st.st_size),
                              mtime: Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec)),
                              dev: Int(st.st_dev), ino: Int(st.st_ino)))
        }
    }
    metas.sort { $0.mtime > $1.mtime }   // newest first
    func keptCount() -> Int {
        switch retention.kind {
        case .count(let n): return min(max(n, 0), metas.count)
        case .bytes(let cap):
            var acc: Int64 = 0
            var c = 0
            for m in metas where acc < cap {
                acc += m.size
                c += 1
            }
            return c
        }
    }
    let keepCount = keptCount()
    let kept = metas.prefix(keepCount)
    let drop = metas.dropFirst(keepCount)
    return TrimPlan(keep: keepCount,
                    remove: drop.map { TrimFile(url: $0.url, size: $0.size, dev: $0.dev, ino: $0.ino) },
                    oldestKeptMtime: kept.last?.mtime)
}

// MARK: - Retention policy storage (two UserDefaults keys: enabled + count)

public func crashRetention() -> Retention? {
    let d = UserDefaults.standard
    guard d.bool(forKey: "retention.crash-dumps.enabled") else { return nil }
    let n = d.integer(forKey: "retention.crash-dumps.count")
    return Retention(kind: .count(n > 0 ? n : 2_000))
}

public func setCrashRetention(_ r: Retention?) {
    let d = UserDefaults.standard
    guard let r, case .count(let n) = r.kind else {
        d.set(false, forKey: "retention.crash-dumps.enabled")
        return
    }
    d.set(true, forKey: "retention.crash-dumps.enabled")
    d.set(n, forKey: "retention.crash-dumps.count")
}
