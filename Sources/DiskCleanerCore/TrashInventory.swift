import Foundation

// ── V2-TRASH: what is in the Trash, per volume (docs/plan-v2.md §6.5 / §7) ──
//
// Read-only listing of the user's Trash folders: `~/.Trash` (boot volume) and
// `<volume>/.Trashes/<uid>` on other mounted volumes. Batch history is not used as the inventory
// (it does not prove a file is still there); it only supplies the original path of items this
// app moved itself. Emptying stays with Finder (`emptyTrashViaFinder`): CleanPilot has no
// permanent-delete path.

public enum TrashVolumeState: Equatable, Sendable {
    case readable
    /// The folder exists but cannot be listed (Full Disk Access / sandbox).
    case noPermission
    /// No Trash folder on this volume (never used, or unmounted meanwhile).
    case missing
    case error(String)
}

public struct TrashEntry: Identifiable, Equatable, Sendable {
    /// Full path inside the Trash (stable while the item stays there).
    public let id: String
    public let name: String
    public let isDirectory: Bool
    /// Allocated bytes; nil = could not be measured (unreadable folder).
    public let bytes: Int64?
    /// When it was put in the Trash (`addedToDirectoryDate`); nil when the system has no record.
    public let trashedAt: Date?
    /// Where it came from, only when this app moved it (from batch history, same inode); else nil.
    public let originalPath: String?
    /// The system reports it as an iCloud item (`isUbiquitousItem`); nil = not reported.
    public let isCloudItem: Bool?
}

public struct TrashVolume: Identifiable, Equatable, Sendable {
    /// The Trash folder path.
    public let id: String
    /// Display name of the volume ("Macintosh HD", "Backup"…).
    public let volumeName: String
    public let volumePath: String
    public let state: TrashVolumeState
    public let entries: [TrashEntry]
    /// Sum of measured entries; nil when not readable or when some entry could not be measured.
    public var bytes: Int64? {
        guard state == .readable, !entries.contains(where: { $0.bytes == nil }) else { return nil }
        return entries.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
}

/// The Trash folders to list: (volume path, Trash folder). Home Trash first.
public func trashLocations(home: URL = homeDir(), volumesDir: String = "/Volumes", uid: uid_t = getuid())
    -> [(volume: String, trash: String)] {
    var out = [(volume: "/", trash: home.appendingPathComponent(".Trash").path)]
    let fm = FileManager.default
    for v in ((try? fm.contentsOfDirectory(atPath: volumesDir)) ?? []).sorted() {
        let vp = (volumesDir as NSString).appendingPathComponent(v)
        // The boot volume appears in /Volumes as a symlink to "/": its Trash is the home one.
        if (try? fm.destinationOfSymbolicLink(atPath: vp)) == "/" { continue }
        out.append((volume: vp, trash: "\(vp)/.Trashes/\(uid)"))
    }
    return out
}

/// `inTrash path → original path` for items this app moved and has not restored.
public func trashOriginals(from batches: [TrashBatch]) -> [String: (original: String, ino: UInt64)] {
    var map: [String: (String, UInt64)] = [:]
    for b in batches {
        for e in b.moved {
            if case .restored = e.restore { continue }
            if case .moved(let inTrash, _, let ino) = e.outcome { map[inTrash] = (e.item.path, ino) }
        }
    }
    return map
}

/// Lists one Trash folder. Folder sizes are measured (st_blocks), cancellable between items.
public func listTrash(volume: String, trash: String, volumeName: String? = nil,
                      originals: [String: (original: String, ino: UInt64)] = [:]) async -> TrashVolume {
    let fm = FileManager.default
    let name = volumeName ?? (volume == "/"
        ? (fm.displayName(atPath: "/"))
        : fm.displayName(atPath: volume))
    var st = stat()
    guard lstat(trash, &st) == 0 else {
        return TrashVolume(id: trash, volumeName: name, volumePath: volume, state: .missing, entries: [])
    }
    let names: [String]
    do {
        names = try fm.contentsOfDirectory(atPath: trash)
    } catch {
        let code = (error as NSError).userInfo[NSUnderlyingErrorKey].flatMap { ($0 as? NSError)?.code }
        let state: TrashVolumeState = (code == Int(EPERM) || code == Int(EACCES)
            || (error as NSError).code == NSFileReadNoPermissionError) ? .noPermission
            : .error(error.localizedDescription)
        return TrashVolume(id: trash, volumeName: name, volumePath: volume, state: state, entries: [])
    }
    var entries: [TrashEntry] = []
    for n in names.sorted() where n != ".DS_Store" && n != ".localized" {
        if Task.isCancelled { break }
        let u = URL(fileURLWithPath: trash).appendingPathComponent(n)
        var s = stat()
        guard lstat(u.path, &s) == 0 else { continue }
        let isDir = (s.st_mode & S_IFMT) == S_IFDIR
        var bytes: Int64? = Int64(s.st_blocks) * 512
        if isDir {
            let r = await dirSizeReport(u)
            // Partly unreadable folder: the size is unknown, not the readable part.
            bytes = r.needFullDiskAccess.isEmpty && r.needAdmin.isEmpty ? r.bytes : nil
        }
        let values = try? u.resourceValues(forKeys: [.addedToDirectoryDateKey, .isUbiquitousItemKey])
        var original: String? = nil
        if let o = originals[u.path], o.ino == UInt64(s.st_ino) { original = o.original }
        entries.append(TrashEntry(id: u.path, name: n, isDirectory: isDir, bytes: bytes,
                                  trashedAt: values?.addedToDirectoryDate, originalPath: original,
                                  isCloudItem: values?.isUbiquitousItem))
    }
    entries.sort { ($0.bytes ?? -1, $1.name) > ($1.bytes ?? -1, $0.name) }
    return TrashVolume(id: trash, volumeName: name, volumePath: volume, state: .readable, entries: entries)
}

/// Every Trash folder of `trashLocations()`; volumes without a Trash folder are left out
/// except the home one (shown as missing so "empty" is never claimed for an unreadable Trash).
public func trashInventory(batches: [TrashBatch] = []) async -> [TrashVolume] {
    let originals = trashOriginals(from: batches)
    var out: [TrashVolume] = []
    for loc in trashLocations() {
        if Task.isCancelled { break }
        let v = await listTrash(volume: loc.volume, trash: loc.trash, originals: originals)
        if v.state == .missing && loc.volume != "/" { continue }
        out.append(v)
    }
    return out
}
