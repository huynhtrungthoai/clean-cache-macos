import Foundation

// ── C1 + C2: confirmed trash plans, preflight, batch history and safe restore ──
//
// One execution path for every page (docs/enhance-feat.md §11):
//   view shows `[TrashPlanItem]` → user confirms → `executeTrashPlan` re-checks each item
//   (`preflight`), moves it with `trashItem` (deletion gate included) and returns a
//   `TrashBatch` with a per-item outcome → the batch is persisted → `restoreBatch` undoes it.
// Nothing here deletes permanently.

/// What the scan saw for a regular file: allocated bytes (`st_blocks * 512`, the same unit as
/// `FileRow.size`) and whole-second modification time. Directories carry no snapshot.
public struct FileSnapshot: Codable, Hashable, Sendable {
    public var allocatedBytes: Int64
    public var mtimeSeconds: Int64

    public init(allocatedBytes: Int64, mtime: Date) {
        self.allocatedBytes = allocatedBytes
        self.mtimeSeconds = Int64(mtime.timeIntervalSince1970)
    }
}

/// One confirmed item of a plan. Exactly what the review sheet shows is what gets executed.
public struct TrashPlanItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    /// Measured size the scan reported; used for accounting only.
    public let bytes: Int64
    /// When set, the file must still match it (size + mtime) or the item is skipped.
    public var expected: FileSnapshot?
    /// Duplicates: the copy being kept must still exist with identical content.
    public var keptCopy: String?
    /// When a critical item is not moved, every later item of the plan is skipped
    /// (uninstall: never move an app's data when its bundle stayed behind).
    public var critical: Bool

    public init(url: URL, name: String? = nil, bytes: Int64, expected: FileSnapshot? = nil,
                keptCopy: URL? = nil, critical: Bool = false) {
        self.path = url.path
        self.name = name ?? url.lastPathComponent
        self.bytes = bytes
        self.expected = expected
        self.keptCopy = keptCopy?.path
        self.critical = critical
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Why an item was not moved although nothing failed.
public enum TrashSkipReason: String, Codable, Sendable {
    case missing                    // gone since the scan
    case changedSinceScan           // size or modification time differs from the scan
    case keptCopyMissingOrChanged   // duplicates: the copy we keep no longer matches
    case protected                  // deletion gate: protected location / sensitive tree
    case outsideAllowed             // deletion gate: outside the allowed scope
    case coveredByEarlierItem       // inside a folder this batch already moved
    case prerequisiteFailed         // an earlier critical item was not moved

    /// English source text, look it up with `L()` in the UI.
    public var reasonKey: String {
        switch self {
        case .missing: return "No longer exists"
        case .changedSinceScan: return "Changed since the scan; scan again"
        case .keptCopyMissingOrChanged: return "The kept copy is missing or changed; scan again"
        case .protected: return "Protected location"
        case .outsideAllowed: return "Outside the locations this app may clean"
        case .coveredByEarlierItem: return "Already moved with its parent folder"
        case .prerequisiteFailed: return "Not moved because the app itself was not moved"
        }
    }
}

public enum TrashOutcome: Codable, Sendable, Equatable {
    case moved(inTrash: String, dev: UInt64, ino: UInt64)
    case skipped(TrashSkipReason)
    /// `reasonKey` is English source text for `L()`; `detail` is the system's own message.
    case failed(reasonKey: String, detail: String)
}

public enum RestoreOutcome: Codable, Sendable, Equatable {
    case restored(at: String)       // may differ from the original when a same-named item exists
    case goneFromTrash              // emptied or moved by the user
    case changedInTrash             // the item in the Trash is not the one we moved
    case refused                    // record failed validation (not in a Trash, or target not allowed)
    case failed(detail: String)

    public var reasonKey: String {
        switch self {
        case .restored: return "Restored"
        case .goneFromTrash: return "No longer in the Trash"
        case .changedInTrash: return "The item in the Trash has changed"
        case .refused: return "This history entry can't be restored"
        case .failed: return "Restore failed"
        }
    }
}

public struct TrashBatchEntry: Codable, Sendable, Identifiable {
    public var id: String { item.path }
    public let item: TrashPlanItem
    public var outcome: TrashOutcome
    public var restore: RestoreOutcome?

    public init(item: TrashPlanItem, outcome: TrashOutcome, restore: RestoreOutcome? = nil) {
        self.item = item
        self.outcome = outcome
        self.restore = restore
    }
}

public struct TrashBatch: Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    /// Module that produced the plan: "caches", "big-files", "old-files", "duplicates",
    /// "leftovers", "uninstall", …
    public let source: String
    public var entries: [TrashBatchEntry]
    public var undoneAt: Date?

    public var moved: [TrashBatchEntry] {
        entries.filter { if case .moved = $0.outcome { return true }; return false }
    }
    public var skipped: [TrashBatchEntry] {
        entries.filter { if case .skipped = $0.outcome { return true }; return false }
    }
    public var failed: [TrashBatchEntry] {
        entries.filter { if case .failed = $0.outcome { return true }; return false }
    }
    /// Bytes moved into the Trash. Not "freed": space returns only when the Trash is emptied.
    public var movedBytes: Int64 { moved.reduce(0) { $0 + $1.item.bytes } }
    /// Moved entries that have not been restored yet.
    public var restorable: [TrashBatchEntry] {
        moved.filter { e in if case .restored = e.restore { return false }; return true }
    }
}

// MARK: - Preflight

/// Re-check one item right before it is moved. nil = go ahead.
public func preflight(_ item: TrashPlanItem) -> TrashSkipReason? {
    var st = stat()
    guard lstat(item.path, &st) == 0 else { return .missing }
    switch deletionGate(item.url) {
    case .protected?: return .protected
    case .outsideAllowed?: return .outsideAllowed
    case nil: break
    }
    if let e = item.expected {
        if Int64(st.st_blocks) * 512 != e.allocatedBytes || Int64(st.st_mtimespec.tv_sec) != e.mtimeSeconds {
            return .changedSinceScan
        }
    }
    if let kept = item.keptCopy,
       !duplicateStillMatches(kept: URL(fileURLWithPath: kept), extra: item.url) {
        return .keptCopyMissingOrChanged
    }
    return nil
}

// MARK: - Execute

/// Runs a confirmed plan in order. Never throws: every item ends as moved / skipped / failed.
/// Synchronous and blocking; call it off the main thread (`AppStore.runTrash` does).
public func executeTrashPlan(_ items: [TrashPlanItem], source: String, now: Date = Date(),
                             trash: (URL) throws -> URL = trashItem) -> TrashBatch {
    var entries: [TrashBatchEntry] = []
    var movedRoots: [String] = []
    var seen = Set<String>()
    var abortRest = false
    for item in items {
        let key = item.url.standardizedFileURL.path
        guard seen.insert(key).inserted else { continue }
        func add(_ o: TrashOutcome) { entries.append(TrashBatchEntry(item: item, outcome: o, restore: nil)) }
        if abortRest { add(.skipped(.prerequisiteFailed)); continue }
        if movedRoots.contains(where: { key.hasPrefix($0 + "/") }) { add(.skipped(.coveredByEarlierItem)); continue }
        if let reason = preflight(item) {
            add(.skipped(reason))
            if item.critical { abortRest = true }
            continue
        }
        var st = stat()
        _ = lstat(item.path, &st)
        do {
            let inTrash = try trash(item.url)
            add(.moved(inTrash: inTrash.path, dev: UInt64(st.st_dev), ino: UInt64(st.st_ino)))
            movedRoots.append(key)
        } catch let e as TrashError {
            add(.failed(reasonKey: e.reasonKey, detail: e.detail))
            if item.critical { abortRest = true }
        } catch {
            add(.failed(reasonKey: TrashError.failed("").reasonKey, detail: error.localizedDescription))
            if item.critical { abortRest = true }
        }
    }
    return TrashBatch(id: UUID(), createdAt: now, source: source, entries: entries, undoneAt: nil)
}

// MARK: - Restore

/// Folders a moved item may legitimately be restored from: the home Trash and the per-user
/// `.Trashes/<uid>` of the boot volume and mounted volumes.
public func trashRoots() -> [String] {
    let uid = getuid()
    var roots = [homeDir().appendingPathComponent(".Trash").path, "/.Trashes/\(uid)"]
    if let vols = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
        roots += vols.map { "/Volumes/\($0)/.Trashes/\(uid)" }
    }
    return roots
}

/// Is `path` strictly inside one of the Trash folders (symlinks and case resolved)?
public func isInsideTrash(_ path: String) -> Bool {
    let p = foldPath(safetyCanonicalPath(URL(fileURLWithPath: path)))
    return trashRoots().contains { root in
        let r = foldPath(realpathString(root) ?? root)
        return p.hasPrefix(r + "/")
    }
}

/// `original`, or "name (1).ext", "name (2).ext"… — never overwrite what is there now.
public func nonClobberingDestination(for original: URL) -> URL {
    let fm = FileManager.default
    guard fm.fileExists(atPath: original.path) else { return original }
    let ext = original.pathExtension
    let base = original.deletingPathExtension().lastPathComponent
    var k = 1
    while true {
        let name = ext.isEmpty ? "\(base) (\(k))" : "\(base) (\(k)).\(ext)"
        let candidate = original.deletingLastPathComponent().appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        k += 1
    }
}

/// Restores every moved, not yet restored entry of `batch`. A history record is never trusted
/// to move arbitrary files: the source must be inside a Trash folder and still be the inode we
/// moved, and the destination must pass the deletion gate's scope check.
public func restoreBatch(_ batch: TrashBatch, now: Date = Date(),
                         move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) })
    -> TrashBatch {
    var b = batch
    for i in b.entries.indices {
        guard case let .moved(inTrash, dev, ino) = b.entries[i].outcome else { continue }
        if case .restored = b.entries[i].restore { continue }
        let original = b.entries[i].item.url
        guard isInsideTrash(inTrash), deletionGate(original) == nil else {
            b.entries[i].restore = .refused
            continue
        }
        var st = stat()
        guard lstat(inTrash, &st) == 0 else { b.entries[i].restore = .goneFromTrash; continue }
        guard UInt64(st.st_dev) == dev, UInt64(st.st_ino) == ino else {
            b.entries[i].restore = .changedInTrash
            continue
        }
        let dst = nonClobberingDestination(for: original)
        do {
            try move(URL(fileURLWithPath: inTrash), dst)
            b.entries[i].restore = .restored(at: dst.path)
        } catch {
            b.entries[i].restore = .failed(detail: error.localizedDescription)
        }
    }
    if b.restorable.isEmpty && !b.moved.isEmpty { b.undoneAt = now }
    return b
}

// MARK: - Persistence

/// Batch history on disk: newest first, owner-only permissions, atomic writes.
/// A damaged file is ignored (history is a convenience; restore re-validates every record).
public final class TrashBatchStore: @unchecked Sendable {
    public let url: URL
    public let maxBatches: Int

    public static func defaultURL() -> URL {
        homeDir().appendingPathComponent("Library/Application Support/CleanPilot/trash-batches.json")
    }

    public init(url: URL = TrashBatchStore.defaultURL(), maxBatches: Int = 200) {
        self.url = url
        self.maxBatches = maxBatches
    }

    public func load() -> [TrashBatch] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([TrashBatch].self, from: data)) ?? []
    }

    public func save(_ batches: [TrashBatch]) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(Array(batches.prefix(maxBatches)))
        try data.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
