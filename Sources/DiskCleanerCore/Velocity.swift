import Foundation
import SQLite3

/// C's SQLITE_TRANSIENT macro isn't defined in the Swift module; mint an equivalent (-1).
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Scan snapshots & velocity (PR-2)
//
// Design: plans/design-diagnostic-dumps-velocity-provenance-2026-10-27.md §4,
// review revision plans/design-review-diagnostic-dumps-2026-10-27.md §2.1:
// · No daemon: snapshots are written inside the category discovery pass; whatever happens between scans is settled on the next scan;
// · Alert is OR (absolute amount or rate, either hits); badge has two tiers: rate hit = red "abnormal velocity",
//   absolute-only hit = yellow "significant growth". Must not become AND, or coming back after a week away to find
//   +105G would be missed because the averaged rate is low, and that is exactly the incident pattern;
// · Baseline = the previous scan ≥10 minutes ago (two scans 30 seconds apart don't reset the baseline);
//   the anomaly sticks until growth falls back (Δ≤0), so a quick rescan doesn't clear the red badge.

/// One row recorded per entry per scan.
public struct ScanSnapshot: Equatable {
    public let entryKey: String
    public let scanID: String
    public let wallTime: Date
    public let bytes: Int64
    public let fileCount: Int
    public let newestMtime: Date?

    public init(entryKey: String, scanID: String, wallTime: Date,
                bytes: Int64, fileCount: Int, newestMtime: Date?) {
        self.entryKey = entryKey
        self.scanID = scanID
        self.wallTime = wallTime
        self.bytes = bytes
        self.fileCount = fileCount
        self.newestMtime = newestMtime
    }
}

/// Velocity alert thresholds. Defaults rationale: the incident ≈ 4,760 files/minute (red tier); 500MB accumulated over a
/// weekend ≈ 0.17MB/minute (doesn't reach red; yellow or silent). Four orders of magnitude apart, so thresholds are easy to place.
public struct VelocityThresholds: Equatable {
    public var files: Int
    public var bytes: Int64
    public var filesPerMinute: Double
    public var bytesPerMinute: Int64

    public init(files: Int = 1_000, bytes: Int64 = 500 * 1_000 * 1_000,
                filesPerMinute: Double = 100, bytesPerMinute: Int64 = 50 * 1_000 * 1_000) {
        self.files = files
        self.bytes = bytes
        self.filesPerMinute = filesPerMinute
        self.bytesPerMinute = bytesPerMinute
    }

    public static let `default` = VelocityThresholds()
}

public enum VelocityTier: Equatable {
    /// Rate hit: burst growth (red)
    case red
    /// Absolute-only hit: long-interval accumulation (yellow)
    case yellow
}

public struct VelocityReport: Equatable {
    public let deltaFiles: Int
    public let deltaBytes: Int64
    public let intervalSeconds: Double
    public let tier: VelocityTier?

    public var filesPerMinute: Double {
        intervalSeconds > 0 ? Double(deltaFiles) * 60.0 / intervalSeconds : 0
    }

    public var bytesPerMinute: Int64 {
        intervalSeconds > 0 ? Int64(Double(deltaBytes) * 60.0 / intervalSeconds) : 0
    }

    /// Pure computation: diff of two snapshots → two-tier verdict. Δ≤0 (cleaned or unchanged) never alerts.
    public static func compute(current: ScanSnapshot, baseline: ScanSnapshot,
                               thresholds: VelocityThresholds = .default) -> VelocityReport {
        let interval = current.wallTime.timeIntervalSince(baseline.wallTime)
        let df = current.fileCount - baseline.fileCount
        let db = current.bytes - baseline.bytes
        guard interval > 0, df > 0 || db > 0 else {
            return VelocityReport(deltaFiles: df, deltaBytes: db, intervalSeconds: max(0, interval), tier: nil)
        }
        let rate = VelocityReport(deltaFiles: df, deltaBytes: db,
                                  intervalSeconds: interval, tier: nil)
        let rateHit = rate.filesPerMinute >= thresholds.filesPerMinute
            || rate.bytesPerMinute >= thresholds.bytesPerMinute
        if rateHit { return VelocityReport(deltaFiles: df, deltaBytes: db, intervalSeconds: interval, tier: .red) }
        let absHit = df >= thresholds.files || db >= thresholds.bytes
        let tier: VelocityTier? = absHit ? .yellow : nil
        return VelocityReport(deltaFiles: df, deltaBytes: db, intervalSeconds: interval, tier: tier)
    }
}

// MARK: - SQLite snapshot store

/// Very thin wrapper over the scan_snapshots table: system libsqlite3, no third-party dependency.
/// The DB lives in the app data directory (~/Library/Application Support/DiskWise/ under home or the sandbox container);
/// "what we write" is documented in docs/PRIVACY.md.
///
/// If the DB can't open or a statement fails, degrade silently: snapshots and velocity are an add-on, not the foundation;
/// a broken DB must not fail the discovery pass; the UI just has no velocity to show.
public final class SnapshotStore {
    var db: OpaquePointer?
    public let keepScans: Int

    public static func defaultPath() -> URL {
        let dir = homeDir().appendingPathComponent("Library/Application Support/DiskWise", isDirectory: true)
        return dir.appendingPathComponent("diagnostics.sqlite")
    }

    public init(path: URL, keepScans: Int = 30) {
        self.keepScans = keepScans
        let fm = FileManager.default
        try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            db = nil
            return
        }
        let ddl = """
        CREATE TABLE IF NOT EXISTS scan_snapshots(
          entryKey TEXT NOT NULL, scanID TEXT NOT NULL, wallTime REAL NOT NULL,
          bytes INTEGER NOT NULL, fileCount INTEGER NOT NULL, newestMtime REAL,
          PRIMARY KEY(entryKey, scanID));
        CREATE INDEX IF NOT EXISTS snap_key_time ON scan_snapshots(entryKey, wallTime);
        CREATE TABLE IF NOT EXISTS probe_cache(
          entryKey TEXT NOT NULL, mtime REAL NOT NULL, owner TEXT, mixed INTEGER NOT NULL,
          hints TEXT NOT NULL, PRIMARY KEY(entryKey, mtime));
        CREATE TABLE IF NOT EXISTS trim_batches(
          batchID TEXT PRIMARY KEY, at REAL NOT NULL, entryKey TEXT NOT NULL,
          count INTEGER NOT NULL, bytes INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS trim_items(
          batchID TEXT NOT NULL, original TEXT NOT NULL, trash TEXT NOT NULL);
        """
        exec(ddl)
    }

    deinit {
        if db != nil { sqlite3_close_v2(db) }
    }

    func exec(_ sql: String) -> Bool {
        guard db != nil else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let ok = sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK
        if err != nil { sqlite3_free(err) }
        return ok
    }

    /// Record one scan round (re-recording the same scanID = overwrite) and trim history to the latest `keepScans` rounds.
    public func record(scanID: String, wallTime: Date, snapshots: [ScanSnapshot]) {
        guard db != nil else { return }
        exec("BEGIN")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        INSERT OR REPLACE INTO scan_snapshots(entryKey, scanID, wallTime, bytes, fileCount, newestMtime)
        VALUES(?,?,?,?,?,?)
        """, -1, &stmt, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
        for s in snapshots {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, s.entryKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, s.scanID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, s.wallTime.timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 4, s.bytes)
            sqlite3_bind_int64(stmt, 5, Int64(s.fileCount))
            if let n = s.newestMtime {
                sqlite3_bind_double(stmt, 6, n.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        // Rolling retention: keep only the latest N rounds (rounds counted by distinct wallTime)
        exec("""
        DELETE FROM scan_snapshots WHERE wallTime NOT IN
        (SELECT DISTINCT wallTime FROM scan_snapshots ORDER BY wallTime DESC LIMIT \(keepScans));
        """)
        exec("COMMIT")
    }

    /// Baseline: the newest row for the same entryKey that is ≥10 minutes old and not from this round's scanID.
    /// Two scans 30 seconds apart keep the baseline; otherwise Δ≈0 and the badge would vanish instantly (review §2.1c).
    public func baseline(entryKey: String, now: Date, currentScanID: String,
                         minAge: TimeInterval = 600) -> ScanSnapshot? {
        guard db != nil else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        SELECT scanID, wallTime, bytes, fileCount, newestMtime FROM scan_snapshots
        WHERE entryKey = ? AND scanID != ? AND wallTime <= ?
        ORDER BY wallTime DESC LIMIT 1
        """, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entryKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, currentScanID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, now.addingTimeInterval(-minAge).timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToSnapshot(stmt, entryKey: entryKey)
    }

    /// Whether any snapshot predates this round (distinguishes "first scan builds baseline" from "history exists but all within 10 minutes").
    public func hasHistory(entryKey: String, before now: Date) -> Bool {
        guard db != nil else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        SELECT COUNT(*) FROM scan_snapshots WHERE entryKey = ? AND wallTime <= ?
        """, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entryKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, now.timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) > 0
    }

    /// For MCP (PR-5): each entry's diff over the last two rounds. Same baseline rule as the UI (10 minutes).
    public func latestTwo(entryKey: String, now: Date = Date(),
                          minAge: TimeInterval = 600) -> (current: ScanSnapshot, baseline: ScanSnapshot)? {
        guard db != nil else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        SELECT scanID, wallTime, bytes, fileCount, newestMtime FROM scan_snapshots
        WHERE entryKey = ? ORDER BY wallTime DESC LIMIT 1
        """, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entryKey, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let current = rowToSnapshot(stmt, entryKey: entryKey)
        guard let base = baseline(entryKey: entryKey, now: now, currentScanID: current.scanID, minAge: minAge) else {
            return nil
        }
        return (current, base)
    }

    private func rowToSnapshot(_ stmt: OpaquePointer?, entryKey: String) -> ScanSnapshot {
        let scanID = String(cString: sqlite3_column_text(stmt, 0))
        let wall = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let bytes = sqlite3_column_int64(stmt, 2)
        let files = Int(sqlite3_column_int64(stmt, 3))
        let newest = sqlite3_column_type(stmt, 4) == SQLITE_NULL
            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        return ScanSnapshot(entryKey: entryKey, scanID: scanID, wallTime: wall,
                            bytes: bytes, fileCount: files, newestMtime: newest)
    }
}
