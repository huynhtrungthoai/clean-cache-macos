import Foundation

// ── Safety knowledge base (safety_db.json; same source as the Python version, kept in sync) ──

public struct SafetyEntry: Decodable {
    public var name: String
    public var what: String
    public var whatif: String
    public var rec: String
    public var path: String
    public var level: String          // safe | warn
    /// **What it costs to delete** this entry. Only written on `warn`; `safe` never has it:
    ///
    /// - `redo`: source data isn't lost; re-download or reinstall brings it back (model weights, dependency repos, simulator runtime images)
    /// - `data`: gone once deleted; re-downloading won't bring it back (app data in simulators, chat images, session logs)
    ///
    /// This split exists because `warn` mixes two completely different things: one just costs time to re-download,
    /// the other really loses something. Lumped into one tier, users don't dare delete what they safely could,
    /// and don't notice what deserves a closer look first; wrong both ways.
    ///
    /// **Missing values default to `data`**: better to overstate "re-download" than understate "data loss". Entries lacking it
    /// are flagged by the self-test rather than slipping through.
    public var cost: String?
    public var grp: String?
    public var docs: String?
    /// Bundle ID of the owning app. Only for entries where "the path doesn't reveal a bundle ID but it does belong to an app"
    /// (like `~/Library/Developer/Xcode/**`); the row's leading cell uses it to show the app icon.
    /// Store-signed apps with a team prefix (like DingTalk) are left blank: if it doesn't match, don't guess; better no icon.
    public var app: String?
    /// Cross-group tags (e.g. ai_models): grp is the caches page display group, tags is
    /// the query basis for "grouping the same kind of thing across grp"; CLI/MCP --category filters on it.
    /// Old entries lack it; decoding uses the default, no impact on the existing knowledge base.
    public var tags: [String]?
    /// File name (without extension) of the official brand mark.
    ///
    /// For tools with **no .app to look up**: `~/.ollama/models`, `~/.cache/uv` and the like are CLI-only;
    /// LaunchServices has no bundle ID for them, so the real-icon tier never finds anything. Entries with `app` may also set this:
    /// the real icon wins, but on a machine where "Xcode is uninstalled but simulators remain" the mark steps in, more recognizable than a generic folder.
    public var icon: String?

    /// Memberwise init: used by SignatureScan to synthesize entries (once a custom init(from:) is defined
    /// the compiler no longer synthesizes the memberwise init; added explicitly here, semantics identical to the decode path).
    public init(name: String, what: String, whatif: String, rec: String, path: String,
                level: String, cost: String?, grp: String?, docs: String?, app: String?,
                tags: [String]?, icon: String?) {
        self.name = name
        self.what = what
        self.whatif = whatif
        self.rec = rec
        self.path = path
        self.level = level
        self.cost = cost
        self.grp = grp
        self.docs = docs
        self.app = app
        self.tags = tags
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case name, what, whatif, rec, path, level, cost, grp, docs, app, icon, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        what = try c.decode(String.self, forKey: .what)
        whatif = try c.decode(String.self, forKey: .whatif)
        rec = try c.decode(String.self, forKey: .rec)
        path = (try? c.decode(String.self, forKey: .path)) ?? ""
        level = (try? c.decode(String.self, forKey: .level)) ?? "safe"
        cost = try? c.decode(String.self, forKey: .cost)
        grp = try? c.decode(String.self, forKey: .grp)
        docs = try? c.decode(String.self, forKey: .docs)
        app = try? c.decode(String.self, forKey: .app)
        icon = try? c.decode(String.self, forKey: .icon)
        tags = try? c.decode([String].self, forKey: .tags)
    }
}

public struct SafetyDB: Decodable {
    public var entries: [SafetyEntry]
}

// ── Home directory: defined in HomeAccess.swift (in the sandbox it uses the real home + an authorization bookmark) ──

public func homePath() -> String { homeDir().path }

/// Whether the home dir has been swapped for a fake demo tree (see build_app/make_demo_home.sh)
public var homeIsDemo: Bool { !envString("DISKWISE_HOME_SHIM").isEmpty }

/// Read env vars via libc, not `ProcessInfo.processInfo.environment`.
///
/// The latter copies the whole process environment into a dictionary on every key read (dozens to hundreds of entries, with allocations). These switches
/// aren't "glanced at occasionally": they sit in a check that **every candidate path** goes through
/// (`isDeletable` → `homePath` → `homeDir`); one cache re-tally can read them thousands of times.
/// After the swap, `setenv` still takes effect immediately; the self-test does `setenv` then asserts (SelfTest:62,
/// SelfTest:1214 comment the order explicitly), so **caching the value** would read wrong; swapping only the API won't.
func envString(_ key: String) -> String {
    // Release builds ignore every developer hook: `DISKWISE_HOME_SHIM` alone would move the
    // deletion boundary (isDeletable/protectedPaths are home-relative).
    guard devHooksEnabled || !key.hasPrefix("DISKWISE_") else { return "" }
    return key.withCString { c in getenv(c).map { String(cString: $0) } ?? "" }
}

// ── Developer hooks (`DISKWISE_*` env: screenshots, perf probes, demo home shim) ──
//
// Compiled in for debug builds (`swift run`, SelfTest) and for `DEV_HOOKS=1 build.sh`
// (README screenshots). A normal release build ignores them all: several of these hooks
// trash real files without a confirm, and the home shim redefines what is deletable.
#if DEBUG || DISKWISE_DEV_HOOKS
private let devHooksCompiledIn = true
#else
private let devHooksCompiledIn = false
#endif

/// Set only by the SelfTest binary (build.sh runs it from the *release* build, and its
/// fixtures rely on `DISKWISE_HOME_SHIM`). Only in-process code can flip it — an environment
/// variable cannot — so the env-based attack this gate exists for stays closed.
private var devHooksForcedByTestHarness = false

public func enableDevHooksForSelfTest() { devHooksForcedByTestHarness = true }

public var devHooksEnabled: Bool { devHooksCompiledIn || devHooksForcedByTestHarness }

/// Remove every `DISKWISE_*` variable from the process environment when developer hooks are
/// compiled out. Call it first thing in each entry point (app `init`, CLI top level) so the
/// many direct `ProcessInfo.environment["DISKWISE_…"]` reads in the UI layer see nothing.
public func scrubDevEnvironment() {
    guard !devHooksEnabled else { return }
    for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("DISKWISE_") {
        unsetenv(key)
    }
}

/// App Store product-page screenshot mode. The demo banner protects whoever picks screenshots (from reporting fake data as real measurements),
/// and real users never set `DISKWISE_HOME_SHIM`, so they never see it; hence for store screenshots
/// it's hidden so the screen looks like what users actually see. README screenshots and daily use are unaffected.
public var storeShotMode: Bool { envString("DISKWISE_STORE_SHOTS") == "1" }

/// Whether the UI should announce "this screen is demo data".
public var demoDisclosed: Bool { homeIsDemo && !storeShotMode }

/// Directory where apps are installed. In demo mode it moves into the fake tree too: the real /Applications has hundreds of thousands of files,
/// scans slowly, and would expose the author's installed apps in the README.
public func applicationsDir() -> String {
    homeIsDemo ? homePath() + "/Applications" : "/Applications"
}

// ── Portable path expansion: ~ / $HOME / /Users/<someone else>/ all map to the current user's home ──

public func expandHome(_ raw: String) -> String {
    let home = homePath()
    var s = raw
    if s.hasPrefix("~") {
        s = home + s.dropFirst()
    }
    if s.contains("$HOME") || s.contains("${HOME}") {
        s = s.replacingOccurrences(of: "${HOME}", with: home)
        s = s.replacingOccurrences(of: "$HOME", with: home)
    }
    if s.hasPrefix("/Users/") {
        let rest = s.dropFirst("/Users/".count)
        if let slash = rest.firstIndex(of: "/") {
            s = home + rest[slash...]
        }
    }
    return s
}

/// Breadcrumbs for a path: **every level of the path itself**, each cell a real ancestor you can click back to.
///
/// **Excludes the volume root `/`**: the leftmost cell is always "Space Overview", which is where this page came from, and whole-disk accounting
/// is that page's job already; a separate `/` cell would say the same thing twice. More importantly, it would send
/// "up one level" to a page with nothing to do (all "not touched by this tool", not a byte cleanable).
///
/// Nor does it start from "the scan root containing it": `/Library` and `/Applications` are themselves scan roots;
/// starting at the root would leave just one lonely cell with nothing above, and people look at this exactly when they've "gone too deep and
/// want to back out".
///
/// The two home segments (`Users` + yourself) merge into one `~` cell: the whole app writes it as `~`;
/// splitting it into two cells just says the same thing twice.
public func crumbChain(for path: String, home: String = homePath()) -> [String] {
    let std = URL(fileURLWithPath: path).standardizedFileURL.path
    let homeStd = URL(fileURLWithPath: home).standardizedFileURL.path
    let me = (homeStd as NSString).lastPathComponent
    var out: [String] = []
    var cur = ""
    for part in std.split(separator: "/").map(String.init) {
        if cur == "/Users", part == me {
            // Drop the `/Users` just added: it refers to the same place as `~`.
            out.removeLast()
            cur = homeStd
        } else {
            cur += "/" + part
        }
        out.append(cur)
    }
    return out
}

/// Where "up one level" lands on the drill-down page: the parent directory. `nil` = already at top; above is the leftmost breadcrumb, "Space Overview".
///
/// The volume root `/` **is not a stop**: backing out of top-level dirs like `/Applications` or `/Library` lands directly on
/// Space Overview, not `/`. Same reason as `crumbChain`: whole-disk accounting is Space Overview's job,
/// and the `/` report can't clean a single byte.
public func drillParent(of path: String) -> String? {
    guard !path.isEmpty else { return nil }
    let up = (path as NSString).deletingLastPathComponent
    // `up.isEmpty` covers relative paths: a single-segment one backs out to empty, also treated as top;
    // callers must not get an empty string as the next stop.
    if up.isEmpty || up == path || up == "/" { return nil }
    return up
}

// ── Cache entry (UI model) ──

public struct CacheItem: Identifiable {
    public let id = UUID()
    public var entry: SafetyEntry
    public var resolvedPaths: [URL] = []
    public var size: Int64? = nil      // nil = measuring
    /// Size of each resolved path. `size` is their sum, enough for the caches page row but not for the overview:
    /// the overview attributes this entry to different arcs of the ring, which "3.7 GB total" alone can't do.
    public var pathSizes: [String: Int64] = [:]
    /// File count and latest modification under this entry, for the expanded row.
    ///
    /// With bytes only, 13 GB of scattered cache and a single 13 GB image look identical in the UI,
    /// yet the former can be judged item by item and the latter can't. Count and date are two more facts about "what's actually in here".
    public var files: Int = 0
    public var newest: Date? = nil
    public var selected = false
    /// Directories under this entry that could not be read (missing Full Disk Access / admin only).
    /// With `size == 0` this means "could not measure", which must never be shown as 0 B (C3).
    public var unreadablePaths: [String] = []

    public init(entry: SafetyEntry, resolvedPaths: [URL] = [], size: Int64? = nil, selected: Bool = false) {
        self.entry = entry
        self.resolvedPaths = resolvedPaths
        self.size = size
        self.selected = selected
    }

    /// Group identifier, not copy: sorting uses it; the table is consulted only before display
    public var groupKey: String { entry.grp ?? "general" }
    public var isSafe: Bool { entry.level != "warn" }
}

// ── C3: cache-page accounting (pure functions, covered by SelfTest) ──

/// What a cache row can honestly show.
public enum CacheRowState: Equatable {
    case measuring
    case measured(Int64)
    /// Nothing could be read (permissions). Never render this as "0 B".
    case unmeasurable
}

public func cacheRowState(_ item: CacheItem) -> CacheRowState {
    guard let size = item.size else { return .measuring }
    if size == 0 && !item.unreadablePaths.isEmpty { return .unmeasurable }
    return .measured(size)
}

/// The exact list of paths a "move selected caches to Trash" action touches, with the bytes each
/// one accounts for. Paths nested inside another selected path are dropped (trashing the parent
/// already takes them), so nothing is trashed or counted twice, and every path carries its own
/// measured size instead of a re-stat of the directory inode.
public func cacheTrashPlan(_ selected: [CacheItem]) -> [(url: URL, bytes: Int64)] {
    var byPath: [String: (url: URL, bytes: Int64)] = [:]
    var order: [String] = []
    for item in selected {
        for url in item.resolvedPaths {
            let key = url.standardizedFileURL.path
            guard byPath[key] == nil else { continue }
            byPath[key] = (url, item.pathSizes[url.path] ?? item.pathSizes[key] ?? 0)
            order.append(key)
        }
    }
    let outer = Set(dropNested(order))
    return order.filter(outer.contains).compactMap { byPath[$0] }
}

// ── C8: Smart Scan one-click clean (owner decision 2026-11-06) ──
//
// After a Smart Scan the user presses one "Clean" button and confirms one summary; no row-by-row
// picking. The set is deliberately narrow: app caches only (dev caches stay on their own page),
// only the knowledge base's no-impact tier, only paths a bulk "select all" may take, and nothing
// that belongs to an app that is running right now. It never widens what a user could select.

/// Knowledge-base groups the one-click clean may take. `dev` is excluded by owner decision.
public let smartCleanGroups: Set<String> = ["general", "cn_app"]

/// One entry the one-click clean left alone because its app is running.
public struct SmartCleanHeldBack: Equatable, Sendable {
    public let name: String
    public let bundleID: String
}

/// Bundle IDs an entry's data belongs to: the entry's `app`, plus the folder after
/// `Library/Containers/` or `Library/Caches/` in any resolved path (lowercased).
public func cacheOwnerBundleIDs(_ item: CacheItem) -> Set<String> {
    var ids = Set<String>()
    if let a = item.entry.app, !a.isEmpty { ids.insert(a.lowercased()) }
    for url in item.resolvedPaths {
        let parts = url.standardizedFileURL.pathComponents
        for i in parts.indices.dropLast() where parts[i] == "Containers" || parts[i] == "Caches" {
            guard i > 0, parts[i - 1] == "Library" else { continue }
            let next = parts[i + 1]
            if next.contains(".") { ids.insert(next.lowercased()) }   // bundle-ID shaped only
        }
    }
    return ids
}

/// Picks what the one-click clean takes from a finished Smart Scan.
///
/// - Kept: group in `smartCleanGroups`, tier `.safe`, measured size > 0.
/// - Each entry keeps only its paths that pass `bulkSelectable` (hidden folders and direct
///   children of `~/Library`, e.g. `~/Library/Logs`, are never swept by one click).
/// - Entries whose owner app is in `runningBundleIDs` are held back and reported.
/// The returned items feed `cacheTrashPlan`, which drops nested paths.
public func smartCleanSelection(_ items: [CacheItem], runningBundleIDs: Set<String>,
                                bulkSelectable: (URL) -> Bool = isBulkSelectable)
    -> (picked: [CacheItem], heldBack: [SmartCleanHeldBack]) {
    let running = Set(runningBundleIDs.map { $0.lowercased() })
    var picked: [CacheItem] = []
    var held: [SmartCleanHeldBack] = []
    for item in items {
        guard smartCleanGroups.contains(item.groupKey), item.entry.tier == .safe,
              (item.size ?? 0) > 0 else { continue }
        var kept = item
        kept.resolvedPaths = item.resolvedPaths.filter {
            bulkSelectable($0) && (item.pathSizes[$0.path] ?? item.pathSizes[$0.standardizedFileURL.path] ?? 0) > 0
        }
        guard !kept.resolvedPaths.isEmpty else { continue }
        if let owner = cacheOwnerBundleIDs(item).sorted().first(where: running.contains) {
            held.append(SmartCleanHeldBack(name: item.entry.name, bundleID: owner))
            continue
        }
        picked.append(kept)
    }
    return (picked, held)
}

/// Indices of items whose paths were affected by trashing `paths` (equal, inside, or containing),
/// so their sizes can be re-measured instead of staying stale or stuck in "measuring".
public func cacheItemsTouched(_ items: [CacheItem], by paths: [String]) -> [Int] {
    let touched = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    func related(_ a: String, _ b: String) -> Bool { a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") }
    return items.indices.filter { i in
        items[i].resolvedPaths.contains { url in
            let p = url.standardizedFileURL.path
            return touched.contains { related(p, $0) }
        }
    }
}

// ── Size formatting: decimal (1 GB = 10⁹ B), same basis as Finder "Get Info", "About This Mac", diskutil ──
//
// We once computed in base 1024 yet labeled it GB: the same 494.4 GB disk was reported as 460.4 GB, 7% below the system UI.
// Users compare our number with "About This Mac"; a mismatch is the tool's fault. Numbers may be small; units must not be wrong.

public func human(_ bytes: Int64) -> String {
    if bytes < 1000 { return "\(bytes) B" }
    let units = ["KB", "MB", "GB", "TB", "PB"]
    var v = Double(bytes) / 1000.0
    var u = 0
    while v >= 1000 && u < units.count - 1 {
        v /= 1000
        u += 1
    }
    return String(format: "%.1f %@", v, units[u])
}

/// Decimal unit constants: every "how many GB" threshold in the UI uses these; don't hand-write 1024 cubed again.
public let kB: Int64 = 1_000
public let MB: Int64 = 1_000 * kB
public let GB: Int64 = 1_000 * MB
public let TB: Int64 = 1_000 * GB

private let hUnits = ["KB", "MB", "GB", "TB", "PB"]
private let hScales: [Int64] = [kB, MB, GB, TB, 1_000 * TB]

/// Which unit this number should be printed in: same steps as `human()`; the two must change together.
private func hUnitIndex(_ v: Int64) -> Int {
    var u = 0
    while u < hUnits.count - 1 && v >= 1000 * hScales[u] { u += 1 }
    return u
}

/// Whether `parts` can really be collected into "a column that adds up": non-empty, no negatives, and summing byte-for-byte
/// exactly to `total`. The last one is crucial: if it doesn't, the caller didn't pass the same set,
/// and patching the difference would be making numbers up.
private func partsAddUp(_ parts: [Int64], _ total: Int64) -> Bool {
    total > 0 && parts.contains(where: { $0 > 0 })
        && parts.allSatisfy { $0 >= 0 } && parts.reduce(Int64(0), +) == total
}

/// Largest remainder method: floor each row to 0.1 unit, then hand the missing ticks back by descending remainder.
/// Each row stays within 0.1 unit of the true value, yet the column adds up. Callers run `partsAddUp` first.
private func apportionTenths(_ parts: [Int64], _ total: Int64, unit u: Int) -> [String] {
    let div = Double(hScales[u]) / 10.0          // one tick = 0.1 unit
    let exact = parts.map { Double($0) / div }
    var cells = exact.map { Int($0.rounded(.down)) }
    let short = Int((Double(total) / div).rounded()) - cells.reduce(0, +)
    if short > 0 {
        let order = exact.indices.sorted { a, b in
            let ra = exact[a] - Double(cells[a]), rb = exact[b] - Double(cells[b])
            return ra == rb ? a < b : ra > rb
        }
        for i in order.prefix(short) { cells[i] += 1 }
    }
    let suffix = " " + hUnits[u]
    return cells.map { String(format: "%.1f%@", Double($0) / 10.0, suffix) }
}

/// A set of bytes that "must add up to the total", printed in one unit with one decimal, and **the printed rows
/// sum exactly to the printed total**.
///
/// Why not `human()` each: rounding each row independently drifts upward. We captured a screen showing
/// "12.0 + 6.3 + 4.2 = 22.5" while the center said 22.4; two ledgers on one screen is the first thing users catch.
///
/// Three cases fall back to per-row `human()` entirely; better each say its own than fabricate a number:
/// 1. Rows don't sum to `total`: the caller didn't pass the same set; patching the difference is making numbers up;
/// 2. Any row falls in another unit (total in GB, this row in MB): that column can't be added anyway;
/// 3. There are no rows.
public func addableHuman(_ parts: [Int64], total: Int64) -> [String] {
    let plain = parts.map(human)
    guard partsAddUp(parts, total) else { return plain }
    let u = hUnitIndex(total)
    let suffix = " " + hUnits[u]
    guard parts.allSatisfy({ $0 == 0 || human($0).hasSuffix(suffix) }) else { return plain }
    return apportionTenths(parts, total, unit: u)
}

/// Same as `addableHuman`, but **forces the whole column into the total's unit**: that one allows a row
/// to fall in MB (since it doesn't add), this one doesn't; the screen explicitly says "sum of segments",
/// so it must really add up, and with a 501.6 MB row mixed in `addableHuman` falls back to per-row rounding for the whole column.
/// That's exactly what a real device showed on 2026-09-25: the column printed summed to 494.5 while the right said 494.4.
///
/// A row apportioned 0 ticks (takes space but less than one minimum tick) prints `< 0.1`: it really does occupy disk;
/// printing `0.0` would make the row vanish from the column and users couldn't add it back by rows.
/// Only falls back to per-row `human()` when "the rows aren't the same ledger at all" (see `partsAddUp`).
public func addableHumanColumn(_ parts: [Int64], total: Int64) -> [String] {
    addableHumanColumn(parts, total: total, inRulerOf: total)
}

/// Same as above, but the column's **unit is set by another number on screen**.
///
/// The Trash operation log is an example: the largest row is only 20 MB, while the "moved this time" card at top right prints
/// in GB based on the whole Trash. Each picking its own unit means two rulers on one screen; the `ruler` passed
/// to this column is that card's number, so the column sum **exactly matches the card's text**.
public func addableHumanColumn(_ parts: [Int64], total: Int64, inRulerOf ruler: Int64) -> [String] {
    let plain = parts.map(human)
    guard partsAddUp(parts, total) else { return plain }
    let u = hUnitIndex(max(1, ruler))
    let out = apportionTenths(parts, total, unit: u)
    let zero = "0.0 " + hUnits[u]
    return zip(parts, out).map { byte, shown in
        byte > 0 && shown == zero ? belowTickle(u) : shown
    }
}

private let hUnitScale: [String: Double] = ["B": 1, "KB": 1e3, "MB": 1e6,
                                            "GB": 1e9, "TB": 1e12, "PB": 1e15]

/// Bytes behind a string printed by `human()`; returns nil if unrecognized (not "number space unit").
private func shownBytes(_ s: String) -> Int64? {
    let p = s.split(separator: " ")
    guard p.count == 2, let v = Double(p[0]), let sc = hUnitScale[String(p[1])]
    else { return nil }
    return Int64((v * sc).rounded())
}

/// Add up the **already-printed strings** on screen and print their sum; returns nil if none are recognized.
///
/// Why not add bytes and then round: the 2026-09-25 center capture showed "available 14.2",
/// "reclaimable 18.6", "available after clearing all 32.7"; each true value was rounded down (14.1x + 18.5x = 32.7x),
/// the byte addition was correct; the problem is the three **printed numbers** didn't add up. People check the three strings on screen;
/// the missing 0.1 belongs to "each item was rounded separately", not to two different bases.
public func sumShown(_ shown: [String]) -> String? {
    var t = Int64(0)
    for s in shown {
        guard let b = shownBytes(s) else { return nil }
        t += b
    }
    return human(t)
}

/// Same as above, subtraction version: "whole disk 494.4 − available 14.2" must print "used" as 480.2,
/// not a number from rounding each byte count separately (the two can differ by 0.1).
public func diffShown(_ whole: String, _ part: String) -> String? {
    guard let a = shownBytes(whole), let b = shownBytes(part), a >= b else { return nil }
    return human(a - b)
}

/// The threshold that would print as `0.0`: under half a minimum tick.
private func roundsToZero(_ v: Int64, unit u: Int) -> Bool {
    Double(v) < Double(hScales[u]) * 0.05
}

/// What to print when a row takes space but less than the column's minimum tick.
///
/// Can't print `0.0`: the row vanishes from the column on the spot, users can't add it back by rows, and "0.0 GB"
/// reads like "nothing measured here". `< 0.1` says the same thing but admits it occupies space.
private func belowTickle(_ u: Int) -> String { "< 0.1 " + hUnits[u] }

/// Print a number in unit tier `u`: exactly 0 prints `0.0` (truly nothing),
/// nonzero but below the minimum tick prints `< 0.1`, otherwise one decimal.
private func printAt(_ v: Int64, unit u: Int) -> String {
    let suffix = " " + hUnits[u]
    if v == 0 { return String(format: "0.0%@", suffix) }
    if roundsToZero(v, unit: u) { return belowTickle(u) }
    return String(format: "%.1f%@", Double(v) / Double(hScales[u]), suffix)
}

/// Print a set of numbers **in one unit**, one decimal each, but **without apportioning**.
///
/// Used where "this set isn't a ledger that adds up": Docker image details are already counted in
/// the "· total" segment above, and the two Trash cards' "moved this time" sits inside the "now" number.
/// They can't be added, but printed side by side they need one ruler; 25.7 GB next to 501.6 MB can't be compared.
public func unifiedHuman(_ values: [Int64]) -> [String] {
    let u = hUnitIndex(values.max() ?? 0)
    return values.map { printAt($0, unit: u) }
}

/// Print a single number on the same ruler as "the column whose total is `total`".
///
/// The bottom clean bar's "selected X" is the same quantity as the column above in another form: a column of all GB with
/// a 400.0 MB below forces mental math to know whether you picked the bulk or the crumbs.
/// The unit step is taken from `total` (same `hUnitIndex` call as `addableHumanColumn`),
/// so the `total` passed in is the column's total above.
public func human(_ bytes: Int64, inRulerOf total: Int64) -> String {
    printAt(max(0, bytes), unit: hUnitIndex(max(1, total)))
}

// ── Protected paths: may not be moved to Trash as a whole (children may) ──

/// Shared temp areas we may act on (plus their real `/private` locations, see `isDeletable`).
///
/// Listed here to give "these two directories themselves may not be moved" a single source: `protectedPaths` includes them,
/// while `isDeletable` only accepts items **beneath** them.
let sharedTempRoots = ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp"]

public func protectedPaths() -> Set<String> {
    let home = homePath()
    let subs = ["", "/Library", "/Documents", "/Desktop", "/Downloads",
                "/Pictures", "/Movies", "/Music", "/Applications",
                "/Public", "/.Trash"]
    var set = Set(subs.map { home + $0 })
    set.insert("/")
    set.formUnion(["/Applications", "/System", "/Library", "/usr",
                   "/bin", "/sbin", "/etc", "/var", "/opt"])
    // **Contents** of temp areas may be touched, but moving these two directories themselves would wipe the system's temp space
    set.formUnion(sharedTempRoots)
    return set
}

public func isProtected(_ url: URL) -> Bool {
    let p = foldPath(url.standardizedFileURL.path)
    return protectedPaths().contains { foldPath($0) == p }
}

// ── Deletion gate: canonical (on-disk) comparison ──
//
// APFS is case-insensitive and Unicode-normalization-insensitive by default, while
// `standardizedFileURL` is purely lexical and does not resolve symlinks. Without this layer:
//   · `~/DOCUMENTS` is the same directory as `~/Documents` yet missed the protected set;
//   · `~/link/Documents` (with `~/link -> ~`) passed the lexical check and `trashItem`
//     followed the parent symlink to the real `~/Documents`.
// Everything that actually moves files (`trashItem`, `agentPipeline`) must go through
// `deletionGate`; `isProtected`/`isDeletable` stay cheap for list rendering.

/// Fold a path the way the default APFS volume compares names (NFC + case-insensitive).
/// On a case-sensitive volume this over-protects, which is the safe direction.
func foldPath(_ p: String) -> String {
    p.precomposedStringWithCanonicalMapping.lowercased()
}

/// `realpath(3)` as a String; nil if the path does not exist / cannot be resolved.
/// Darwin's realpath returns the on-disk case of each component and resolves symlinks.
func realpathString(_ p: String) -> String? {
    guard let r = realpath(p, nil) else { return nil }
    defer { free(r) }
    return String(cString: r)
}

/// The location a filesystem operation on `url` would actually act on:
/// every **parent** component resolved (symlinks + on-disk case) through the deepest
/// existing ancestor, the not-yet-existing remainder appended lexically, and the **last**
/// component left unresolved — trashing a symlink moves the link, not its target.
public func safetyCanonicalPath(_ url: URL) -> String {
    let std = url.standardizedFileURL.path
    guard std != "/" else { return "/" }
    let last = (std as NSString).lastPathComponent
    var head = (std as NSString).deletingLastPathComponent
    var missing: [String] = []
    while true {
        if let resolved = realpathString(head) {
            var out = resolved
            for c in missing.reversed() { out = (out as NSString).appendingPathComponent(c) }
            return (out as NSString).appendingPathComponent(last)
        }
        if head == "/" || head.isEmpty { return std }
        missing.append((head as NSString).lastPathComponent)
        head = (head as NSString).deletingLastPathComponent
    }
}

// ── Sensitive trees: nothing inside is ever trashed by this tool ──
//
// `protectedPaths` only blocks a handful of folders **as a whole**; everything below them is
// fair game. That is right for `~/Documents/x.iso`, wrong for credentials, keychains and
// synced/app databases, where removing one inner file is already the damage:
//   · keys & tokens (`~/.ssh`, `~/.gnupg`, cloud CLIs) — lost access, not lost space;
//   · `~/Library/Keychains` — every saved password;
//   · `~/Library/Mobile Documents` — iCloud Drive: trashing here deletes on every device;
//   · Mail / Messages / Contacts / Calendars / Photos libraries — databases plus their blobs,
//     an inner deletion corrupts the library rather than freeing space safely.
// None of these appear in safety_db.json, so no cleaning feature loses anything.

/// Home-relative roots of sensitive trees. The root itself and everything under it is off-limits.
let sensitiveTreeRelRoots = [
    ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".config/gcloud", ".config/gh",
    ".password-store",
    "Library/Keychains",
    "Library/Mobile Documents",
    "Library/Mail",
    "Library/Messages",
    "Library/Accounts",
    "Library/Cookies",
    "Library/Calendars",
    "Library/Application Support/AddressBook",
    "Library/Application Support/MobileSync",   // iPhone/iPad backups
]

/// Package suffixes that are libraries, not folders: never trash them or anything inside.
let sensitivePackageSuffixes = [".photoslibrary", ".musiclibrary", ".tvlibrary"]

/// Is `path` a sensitive tree root, inside one, or inside a protected library package?
/// Lexical + case/Unicode-folded; `deletionGate` also runs it on the canonical path.
public func isInSensitiveTree(_ path: String) -> Bool {
    isInSensitiveTree(path, homes: [homePath()])
}

func isInSensitiveTree(_ path: String, homes: [String]) -> Bool {
    let p = foldPath(URL(fileURLWithPath: path).standardizedFileURL.path)
    for h in homes {
        let fh = foldPath(h)
        for rel in sensitiveTreeRelRoots {
            let root = foldPath(rel)
            let r = fh.hasSuffix("/") ? fh + root : fh + "/" + root
            if p == r || p.hasPrefix(r + "/") { return true }
        }
    }
    for comp in p.split(separator: "/") where sensitivePackageSuffixes.contains(where: { comp.hasSuffix($0) }) {
        return true
    }
    return false
}

public enum DeletionGateRefusal: Equatable {
    case protected
    case outsideAllowed
}

/// The single gate every deletion passes: lexical checks first, then the same checks
/// on the canonical location (see `safetyCanonicalPath`), both case/Unicode-folded.
/// nil = allowed.
public func deletionGate(_ url: URL) -> DeletionGateRefusal? {
    if isProtected(url) { return .protected }
    if !isDeletable(url) { return .outsideAllowed }
    if isInSensitiveTree(url.path) { return .protected }

    let canonRaw = safetyCanonicalPath(url)
    let home = homePath()
    if isInSensitiveTree(canonRaw, homes: [home] + [realpathString(home)].compactMap { $0 }) {
        return .protected
    }
    let canon = foldPath(canonRaw)
    // Protected set in both spellings: as written, and as resolved on disk
    // (`/var` → `/private/var`, a shim home under `/var/folders` → `/private/var/folders`…).
    for p in protectedPaths() {
        if foldPath(p) == canon { return .protected }
        if let r = realpathString(p), foldPath(r) == canon { return .protected }
    }

    func under(_ root: String, orEqual: Bool) -> Bool {
        let f = foldPath(root)
        let base = f.hasSuffix("/") ? String(f.dropLast()) : f
        return (orEqual && canon == base) || canon.hasPrefix(base + "/")
    }
    var roots = [homePath(), applicationsDir()]
    roots += roots.compactMap(realpathString)
    if roots.contains(where: { under($0, orEqual: true) }) { return nil }
    if sharedTempRoots.contains(where: { under($0, orEqual: false) }) { return nil }
    return .outsideAllowed
}

/// Our actionable scope: home, /Applications (inside the fake tree in demo mode), and two shared temp areas.
///
/// A whole-disk scan also lists big files in system areas; that's accounting, not work: those locations are either admin-writable only,
/// or Homebrew / Xcode territory whose own cleanup commands beat this button. So such rows are display-only,
/// checkboxes locked; the only deletion path is still `trashItem`.
///
/// `/tmp` and `/var/tmp` are **the only two allowed places outside home**: "temp" is in their name;
/// they're meant for disposable stuff. A whole-disk scan walks into `/private` and lists what's under them
/// (build leftovers, demo trees, half-extracted archives, often tens of GB) as-is; without allowing deletion
/// users could only watch the tool report a number they can't act on.
///
/// Two details:
/// - Only items **beneath** count. `/tmp` itself may not be deleted (that would wipe the system's temp space),
///   so this compares the `root + "/"` prefix and `p == root` doesn't match; `protectedPaths` is a second guard.
/// - `/tmp` and `/var/tmp` are symlinks into `/private`, and `standardizedFileURL`
///   **doesn't resolve symlinks**: the same place shows up as both `/tmp/x` and `/private/tmp/x`
///   (drilling from `/` gives the former, a whole-disk scan of `/private` the latter). Accept only one and the same thing
///   would be deletable from one entry point but not another.
public func isDeletable(_ url: URL) -> Bool {
    let p = url.standardizedFileURL.path
    let home = homePath()
    let apps = applicationsDir()
    if p == home || p.hasPrefix(home + "/") { return true }
    if p == apps || p.hasPrefix(apps + "/") { return true }
    return sharedTempRoots.contains { p.hasPrefix($0 + "/") }
}

/// Whether this location can be moved to Trash **as a whole**: `isDeletable` says "this location is ours to manage",
/// `isProtected` says "this location may not be touched as a whole"; both must pass.
///
/// The criteria must match `trashItem`, or the UI writes empty promises: `~/Library` is inside home,
/// checking only `isDeletable` marks it "deletable", but actually clicking makes `trashItem` refuse.
/// The ring's "click me, reclaimable" highlight reads exactly this; mark it wrong once and that cell baits a click.
public func isReclaimableWhole(_ url: URL) -> Bool {
    isDeletable(url) && !isProtected(url) && !isInSensitiveTree(url.path)
}

/// Rows a bulk "select all" may tick. Stricter than `isReclaimableWhole`: hidden entries
/// (dotfiles/dot-dirs: shell config, tool state, credentials) and the direct children of
/// `~/Library` (each one is an app's or the system's whole state) must be ticked one by one,
/// never swept up by a single click.
public func isBulkSelectable(_ url: URL) -> Bool {
    guard isReclaimableWhole(url) else { return false }
    if url.lastPathComponent.hasPrefix(".") { return false }
    let parent = foldPath(url.standardizedFileURL.deletingLastPathComponent().path)
    return parent != foldPath(homePath() + "/Library")
}

// ── Target set for the ring's "reclaimable" ledger ──
//
// When the ring only accepted whole movable segments, one machine reported "6.3 GB of 96 GB actionable", while the same app's
// caches page could clear 22 GB. The hero number is the product's promise; under-reporting 3x is as bad as being wrong.
// So reclaimable must land on **concrete individual** targets, not "this whole segment".

/// A named thing that can be moved: path + how much it occupies right now.
public struct ReclaimTarget: Equatable, Hashable {
    public let path: String
    public let size: Int64

    public init(path: String, size: Int64) {
        self.path = path
        self.size = size
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Attribution key for the "other" bucket: reclaimable locations not belonging to any named arc go under it.
///
/// It lives in Core rather than the UI because it and `reclaimBucket` are a paired contract; the self-test must pin
/// "where the nil-returning ones end up", and SelfTest depends only on Core, not the App target.
/// Uses a string that can't be a path: no real directory will ever collide with it.
public let reclaimRestKey = "__rest__"

/// Collapse to a non-nested set: once a parent is counted, its children must not be added again.
///
/// Knowledge-base entries are nested by nature (`~/Library/Caches` and `~/Library/Caches/Homebrew` beneath it
/// are the same bytes). The caches page avoids this via "unchecked isn't summed"; the ring must sum, so it de-nests first.
public func dropNested(_ paths: [String]) -> [String] {
    let sorted = Set(paths).sorted()
    return sorted.filter { p in
        !sorted.contains { q in
            q != p && (p == q || p.hasPrefix(q + "/"))
        }
    }
}

/// How many bytes a batch of paths **actually** occupies: nested ones keep only the outermost.
///
/// Each `bytes` is the whole subtree of that path; the parent already includes the child, adding the child again counts it twice.
/// So de-nest first, then sum only what remains. The caches page's select-all total goes through here;
/// don't sum entries' own `size`: `~/Library/Caches` and `Caches/Home` beneath it are the same bytes.
public func contentsUnionSize(_ sizes: [(path: String, bytes: Int64)]) -> Int64 {
    let byPath = Dictionary(sizes.map { ($0.path, $0.bytes) }, uniquingKeysWith: { a, _ in a })
    return dropNested(Array(byPath.keys)).reduce(Int64(0)) { $0 + (byPath[$1] ?? 0) }
}

// ── A child within one level: subdirectory or file (for the folder drill-down page) ──

/// Identity of a row on the drill-down page. Unlike caches-page "explained entries", there's no knowledge base or four-part explanation here:
/// it's just "this directory has such a thing, taking this much". Whether it's actionable comes from `isDeletable`,
/// not a knowledge-base whitelist: this page lists **any** level, and most locations aren't in the knowledge base at all.
public struct ChildEntry: Identifiable, Hashable {
    public let path: String
    public let name: String
    public let size: Int64
    /// Directories can be drilled into, files can't; this decides whether the row ends with "Open".
    public let isDir: Bool
    /// File count in this subtree (file rows always 1). With bytes only, 10 GB of scattered cache and
    /// a single 10 GB image look the same in the UI, yet the former can be judged item by item and the latter can't.
    public let files: Int
    /// Latest modification. `nil` = not read (permissions, or everything failed along the way).
    public let newest: Date?
    /// Whether this subtree has unreadable directories (errno EPERM/EACCES).
    ///
    /// When true, `size` is only **the readable part**, not the real disk usage. The UI must distinguish two cases:
    /// `size == 0` means the whole tree was unreadable; that 0 can't be trusted at all and must not be written as `0 B`;
    /// `size > 0` means only a piece is missing; show the number, but say it's a lower bound.
    public let unreadable: Bool

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, name: String, size: Int64, isDir: Bool,
                files: Int = 0, newest: Date? = nil, unreadable: Bool = false) {
        self.path = path
        self.name = name
        self.size = size
        self.isDir = isDir
        self.files = files
        self.newest = newest
        self.unreadable = unreadable
    }
}

/// The complete breakdown of **this level** of a directory.
///
/// `entries` are the rows listed one by one (dirs and files mixed, sorted by size descending); `total` is the sum of
/// **all** children at this level. The difference is the trailing "N more items, totaling X"; so the listed rows
/// plus that trailing line equal `total` exactly, and this screen's ledger adds up.
///
/// There's only one "next level" implementation in the whole app: expanding a row on the overview and listing a level on folder details both use the same
/// `dirLevel` (the latter also wants files). If the two differed by even one cell, opening the same level on the same machine
/// would show two different lists.
public struct DirLevel {
    public var entries: [ChildEntry]
    public var total: Int64
    public var unlistedCount: Int
    public var unlistedBytes: Int64
    public var dirCount: Int
    public var fileCount: Int
    /// errno when the level's own folder could not be listed (EPERM = Full Disk Access,
    /// EACCES = admin only, ENOENT = gone); 0 when it was listed. A non-zero level has no
    /// entries and must not be shown as "empty".
    public var rootErrno: Int32 = 0

    /// Subfolders that could only be partly measured (their size is a lower bound).
    public var unreadableChildren: [String] { entries.filter(\.unreadable).map(\.path) }

    public init(entries: [ChildEntry] = [], total: Int64 = 0, unlistedCount: Int = 0,
                unlistedBytes: Int64 = 0, dirCount: Int = 0, fileCount: Int = 0,
                rootErrno: Int32 = 0) {
        self.rootErrno = rootErrno
        self.entries = entries
        self.total = total
        self.unlistedCount = unlistedCount
        self.unlistedBytes = unlistedBytes
        self.dirCount = dirCount
        self.fileCount = fileCount
    }
}

/// Among bucket paths, the closest one wins: find the **longest** ancestor prefix for `path`.
///
/// Longest rather than first, because the ring has parent/child buckets like `~/Library` and `~/Library/Developer`;
/// attributing to the parent would count the child segment twice.
public func reclaimBucket(of path: String, in buckets: [String]) -> String? {
    var best: String? = nil
    for b in buckets where path == b || path.hasPrefix(b + "/") {
        if best == nil || b.count > best!.count { best = b }
    }
    return best
}
