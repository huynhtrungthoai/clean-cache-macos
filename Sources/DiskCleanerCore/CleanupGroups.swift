import Foundation

// ── V2-CLEANUP: semantic cleanup groups over cache rows (docs/plan-v2.md §7, enhance-feat.md §11) ──
//
// The cache page groups rows the way a person thinks about them ("app caches", "logs", "developer
// caches") instead of by knowledge-base `grp`. Groups are presentation only: they never change
// which rows exist, what a row may be selected for, or what a plan moves. The group checkbox goes
// through `cleanupGroupToggle`, which only turns on rows a bulk "select all" may take.

/// Stable group IDs (persist them, compare them; never show the raw value).
public enum CleanupGroupID: String, CaseIterable, Sendable, Codable {
    /// Per-app folders in `~/Library/Caches` (knowledge base + C9 discovery).
    case appCaches = "app_caches"
    /// Caches inside `~/Library/Containers` / `~/Library/Group Containers` (sandboxed apps).
    case containerCaches = "container_caches"
    /// Log folders (`Logs`, `log`, `logs` path component).
    case logs
    /// Knowledge-base group `dev` (package managers, Xcode, AI tools…).
    case developer
    /// Everything else the knowledge base knows (caches kept in Application Support etc.).
    case otherAppData = "other_app_data"

    /// English source text; the UI shows `L(titleKey)`.
    public var titleKey: String {
        switch self {
        case .appCaches: return "App caches"
        case .containerCaches: return "Sandboxed app caches"
        case .logs: return "Log files"
        case .developer: return "Developer caches"
        case .otherAppData: return "Other app data"
        }
    }
}

/// Why a row is not part of a bulk/group selection. A user may still tick `needsReview` rows
/// one by one; the others cannot be selected at all yet.
public enum CleanupEligibility: Equatable, Sendable {
    case eligible
    case measuring
    /// Nothing could be read (permissions): "could not measure", never "0 B".
    case unmeasurable
    /// Measured and empty.
    case empty
    /// Deleting it costs a re-download (`redo`) or loses data (`risky`): the user decides per row.
    case needsReview(VerdictTier)
    /// No path of the row may be taken by a bulk selection (`isBulkSelectable`).
    case notBulkSelectable

    public var isEligible: Bool { self == .eligible }

    /// English source text for `L()`; nil when eligible.
    public var reasonKey: String? {
        switch self {
        case .eligible: return nil
        case .measuring: return "Still measuring"
        case .unmeasurable: return "Couldn't measure (needs access)"
        case .empty: return "Empty"
        case .needsReview(.redo): return "Needs a re-download afterwards; choose it yourself"
        case .needsReview: return "May lose data; choose it yourself"
        case .notBulkSelectable: return "Choose it yourself"
        }
    }
}

/// Tri-state of a group checkbox.
public enum GroupSelection: Equatable, Sendable {
    case none, some, all
}

/// One group as the cache page's left column shows it.
public struct CleanupGroupSummary: Identifiable, Equatable, Sendable {
    public let id: CleanupGroupID
    /// Rows in the group (all of them, eligible or not).
    public let count: Int
    /// Bytes on disk of the group, nested paths counted once. nil = some row is still measuring
    /// (unknown is not zero). Rows that could not be read add nothing; see `unmeasurableCount`.
    public let measuredBytes: Int64?
    /// What is measured so far (lower bound while `measuredBytes == nil`).
    public let knownBytes: Int64
    public let unmeasurableCount: Int
    public let selectedCount: Int
    /// Selected rows' bytes, nested paths counted once.
    public let selectedBytes: Int64
    /// Rows the group checkbox may turn on.
    public let eligibleCount: Int
    public let selection: GroupSelection
}

private func isUnder(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
}

/// The semantic group of a cache row. Pure: decided from the knowledge-base group and paths only.
public func cleanupGroupID(for item: CacheItem, home: String = homePath()) -> CleanupGroupID {
    if item.groupKey == "dev" { return .developer }
    let paths = item.resolvedPaths.isEmpty
        ? [expandHome(item.entry.path)]
        : item.resolvedPaths.map { $0.standardizedFileURL.path }
    let logNames: Set<String> = ["logs", "log"]
    if paths.contains(where: { p in
        p.split(separator: "/").contains { logNames.contains($0.lowercased()) }
    }) { return .logs }
    let lib = home + "/Library"
    if paths.allSatisfy({ isUnder($0, lib + "/Caches") }) { return .appCaches }
    if paths.allSatisfy({ isUnder($0, lib + "/Containers") || isUnder($0, lib + "/Group Containers") }) {
        return .containerCaches
    }
    return .otherAppData
}

/// May a group checkbox (or "select all") turn this row on? Same policy as `cacheLit` + bulk.
public func cleanupEligibility(_ item: CacheItem,
                               bulkSelectable: (URL) -> Bool = isBulkSelectable) -> CleanupEligibility {
    switch cacheRowState(item) {
    case .measuring: return .measuring
    case .unmeasurable: return .unmeasurable
    case .measured(let b) where b <= 0: return .empty
    case .measured: break
    }
    let tier = item.entry.tier
    guard tier == .safe else { return .needsReview(tier) }
    guard item.resolvedPaths.contains(where: bulkSelectable) else { return .notBulkSelectable }
    return .eligible
}

private func unionBytes(_ items: [CacheItem]) -> Int64 {
    contentsUnionSize(items.flatMap { it in it.pathSizes.map { (path: $0.key, bytes: $0.value) } })
}

/// One summary per group that has rows, in `CleanupGroupID.allCases` order.
public func cleanupGroupSummaries(_ items: [CacheItem], home: String = homePath(),
                                  bulkSelectable: (URL) -> Bool = isBulkSelectable) -> [CleanupGroupSummary] {
    var byGroup: [CleanupGroupID: [CacheItem]] = [:]
    for it in items { byGroup[cleanupGroupID(for: it, home: home), default: []].append(it) }
    return CleanupGroupID.allCases.compactMap { id in
        guard let rows = byGroup[id], !rows.isEmpty else { return nil }
        let states = rows.map(cacheRowState)
        let measuring = states.contains(.measuring)
        let known = unionBytes(rows)
        let selected = rows.filter { $0.selected && $0.size != nil }
        let eligible = rows.filter { cleanupEligibility($0, bulkSelectable: bulkSelectable).isEligible }
        let selection: GroupSelection
        if selected.isEmpty {
            selection = .none
        } else if !eligible.isEmpty && eligible.allSatisfy(\.selected) && selected.count == eligible.count {
            selection = .all
        } else {
            selection = .some
        }
        return CleanupGroupSummary(
            id: id, count: rows.count,
            measuredBytes: measuring ? nil : known, knownBytes: known,
            unmeasurableCount: states.filter { $0 == .unmeasurable }.count,
            selectedCount: selected.count, selectedBytes: unionBytes(selected),
            eligibleCount: eligible.count, selection: selection)
    }
}

/// Indices to change when the group checkbox is clicked, and the value to set.
/// - Turning on (state `.none` / `.some`): only eligible rows of the group are selected.
/// - Turning off (state `.all`): every selected row of the group is cleared; clearing is always
///   allowed, and leaving a hand-picked row behind would keep the checkbox in `.some` forever.
public func cleanupGroupToggle(_ items: [CacheItem], group: CleanupGroupID, home: String = homePath(),
                               bulkSelectable: (URL) -> Bool = isBulkSelectable) -> (indices: [Int], on: Bool) {
    let inGroup = items.indices.filter { cleanupGroupID(for: items[$0], home: home) == group }
    let eligible = inGroup.filter { cleanupEligibility(items[$0], bulkSelectable: bulkSelectable).isEligible }
    let allOn = !eligible.isEmpty && eligible.allSatisfy { items[$0].selected }
    if allOn { return (inGroup.filter { items[$0].selected }, false) }
    return (eligible.filter { !items[$0].selected }, true)
}
