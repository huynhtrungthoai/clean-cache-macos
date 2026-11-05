import Foundation
import SQLite3

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

// MARK: - Prune ledger (for whole-batch undo; stored in the snapshot DB)

extension SnapshotStore {
    /// Record a prune batch. original/trash recorded in pairs; undo moves each pair back.
    public func recordTrim(batchID: String, at: Date, entryKey: String,
                    items: [(original: URL, trash: URL, bytes: Int64)]) {
        guard db != nil else { return }
        exec("BEGIN")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO trim_batches VALUES(?,?,?,?,?)",
                                 -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
        sqlite3_bind_text(stmt, 1, batchID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, at.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, entryKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, Int64(items.count))
        sqlite3_bind_int64(stmt, 5, items.reduce(0) { $0 + $1.bytes })
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard sqlite3_prepare_v2(db, "INSERT INTO trim_items VALUES(?,?,?)",
                                 -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
        for it in items {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, batchID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, it.original.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, it.trash.path, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        exec("COMMIT")
    }

    /// Undo a whole batch: move items from the Trash back to their original paths. Those that can't be (user emptied Trash) are skipped and counted.
    /// Returns (restored, missing).
    public func undoTrim(batchID: String) -> (restored: Int, missing: Int) {
        guard db != nil else { return (0, 0) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT original, trash FROM trim_items WHERE batchID = ?",
                                 -1, &stmt, nil) == SQLITE_OK else { return (0, 0) }
        sqlite3_bind_text(stmt, 1, batchID, -1, SQLITE_TRANSIENT)
        var pairs: [(URL, URL)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            pairs.append((URL(fileURLWithPath: String(cString: sqlite3_column_text(stmt, 0))),
                          URL(fileURLWithPath: String(cString: sqlite3_column_text(stmt, 1)))))
        }
        sqlite3_finalize(stmt)
        let fm = FileManager.default
        var restored = 0
        var missing = 0
        for (original, trash) in pairs {
            guard fm.fileExists(atPath: trash.path) else { missing += 1; continue }
            try? fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: trash, to: original)) != nil {
                restored += 1
            } else {
                missing += 1
            }
        }
        if restored > 0 || missing >= pairs.count {
            exec("DELETE FROM trim_items WHERE batchID = '\(batchID)'")
            exec("DELETE FROM trim_batches WHERE batchID = '\(batchID)'")
        }
        return (restored, missing)
    }
}
