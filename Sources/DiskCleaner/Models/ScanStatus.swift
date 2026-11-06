import Foundation
import DiskCleanerCore

// ── C2 / C5: how a scan ended, when, and what it could not read (docs/enhance-feat.md §11) ──

/// Lifecycle of one scan. `stopped` means the user cancelled: results on screen are incomplete.
enum ScanState: Equatable {
    case idle
    case scanning
    case completed
    case stopped
}

/// A location the scan could not fully read. Shown so "nothing found" is never mistaken for
/// "nothing there".
struct ScanIssue: Identifiable, Equatable {
    enum Kind: Equatable {
        case noPermission       // missing Full Disk Access / admin only
        case notFound
        case error(String)
    }
    let id = UUID()
    let root: String
    let kind: Kind
}

/// Adopted by every scanning model so the UI can render §6 states the same way everywhere.
@MainActor
protocol ScanStatusReporting: AnyObject {
    var scanState: ScanState { get }
    /// When the results on screen were produced (set on completion and on stop).
    var scannedAt: Date? { get }
    var issues: [ScanIssue] { get }
}

extension ScanStatusReporting {
    /// Finished, but some locations could not be read or the user stopped early.
    var isPartial: Bool {
        scanState == .stopped || (scanState == .completed && !issues.isEmpty)
    }

    /// Results may no longer match the disk: something was moved or restored after this scan
    /// (pass `AppStore.lastTrashAt`), or the scan is older than `maxAge`. The UI offers
    /// "Scan again"; it never rescans by itself.
    func isStale(lastTrashAt: Date?, maxAge: TimeInterval = 600, now: Date = Date()) -> Bool {
        guard let at = scannedAt, scanState == .completed || scanState == .stopped else { return false }
        if let t = lastTrashAt, t > at { return true }
        return now.timeIntervalSince(at) > maxAge
    }
}

/// Issues from paths that could not be read (DirScan.needFullDiskAccess / needAdmin).
func permissionIssues(_ paths: [String]) -> [ScanIssue] {
    Array(Set(paths)).sorted().map { ScanIssue(root: $0, kind: .noPermission) }
}

/// Issues of a `walkFiles` pass: unreadable folders (sorted) then missing roots.
func walkIssues(_ r: WalkResult) -> [ScanIssue] {
    permissionIssues(r.needFullDiskAccess + r.needAdmin)
        + Array(Set(r.missingRoots)).sorted().map { ScanIssue(root: $0, kind: .notFound) }
}
