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

/// One issue from an errno of a folder that could not be listed.
func errnoIssue(_ path: String, _ e: Int32) -> ScanIssue {
    switch e {
    case EPERM, EACCES: return ScanIssue(root: path, kind: .noPermission)
    case ENOENT: return ScanIssue(root: path, kind: .notFound)
    default: return ScanIssue(root: path, kind: .error(String(cString: strerror(e))))
    }
}

/// Issues of a `walkFiles` pass: unreadable folders (sorted) then missing roots.
func walkIssues(_ r: WalkResult) -> [ScanIssue] {
    permissionIssues(r.needFullDiskAccess + r.needAdmin)
        + Array(Set(r.missingRoots)).sorted().map { ScanIssue(root: $0, kind: .notFound) }
}

// ── V2-SCAN: per-module status of a Smart Scan (docs/enhance-feat.md §11, plan-v2.md §7) ──
//
// Scope stays what the Smart Scan already measures (owner decision pending on a wider default,
// plan-v2.md §8.1): app caches and developer caches, from one `CachesModel` scan. A module that
// could not read something is `partial` / `permissionDenied`, never "all clear".

enum SmartScanModuleID: String, CaseIterable {
    case appCaches = "app_caches"
    case developerCaches = "developer_caches"

    /// English source text; the UI shows `L(titleKey)`.
    var titleKey: String {
        switch self {
        case .appCaches: return "App caches"
        case .developerCaches: return "Developer caches"
        }
    }
}

enum SmartScanModuleState: Equatable {
    case idle, queued, running, completed, cancelled, partial, permissionDenied, failed
}

struct SmartScanModule: Identifiable, Equatable {
    let id: SmartScanModuleID
    let state: SmartScanModuleState
    let itemCount: Int
    /// Measured bytes, nested paths counted once. Meaningful only when `state` is `completed`,
    /// `partial` or `cancelled` (then a lower bound); show "—" while idle/running.
    let bytes: Int64
    let issues: [ScanIssue]
}
