import Foundation

// ── V2-DEV: one inventory for the Dev Cleanup center (docs/plan-v2.md §6.7 / §7) ──
//
// Presentation layer over what already exists: knowledge-base `dev` cache rows (CachesModel) and
// per-project `node_modules` (NMModel). It classifies, explains and de-duplicates; it does not
// discover anything new, and it does not change any tier, selection policy or deletion gate.
// Build-output detectors, venvs, Docker cleanup etc. wait for the owner's policy (plan-v2 §8.8).

public enum DevEcosystem: String, CaseIterable, Sendable, Codable {
    case javascript, apple, python, jvm, go, rust, homebrew, containers, ai, other

    public var titleKey: String {
        switch self {
        case .javascript: return "JavaScript / Node.js"
        case .apple: return "Apple / Xcode"
        case .python: return "Python"
        case .jvm: return "JVM / Android"
        case .go: return "Go"
        case .rust: return "Rust"
        case .homebrew: return "Homebrew"
        case .containers: return "Containers"
        case .ai: return "AI tools"
        case .other: return "Other tools"
        }
    }
}

/// What the bytes are. Left column of the Dev Cleanup center (only kinds that have rows).
public enum DevDataKind: String, CaseIterable, Sendable, Codable {
    /// Installed dependencies of one project (`node_modules`). Reinstall brings them back.
    case dependency
    /// Download/package caches shared by every project of a tool.
    case toolCache = "tool_cache"
    /// Build output (Xcode DerivedData). Rebuilding brings it back.
    case buildOutput = "build_output"
    /// Installed components and environments: SDKs, simulators, runtimes, local models, VM disks.
    case environment
    /// Records a person may want to keep: archives, backups, session histories, snapshots.
    case records

    public var titleKey: String {
        switch self {
        case .dependency: return "Project dependencies"
        case .toolCache: return "Tool caches"
        case .buildOutput: return "Build data"
        case .environment: return "Environments & installed components"
        case .records: return "Records to keep or review"
        }
    }
}

/// Where the row's identification comes from (shown as "How we know").
public enum DevEvidence: Equatable, Sendable {
    /// A knowledge-base entry matched this path pattern (Resources/safety_db.json).
    case knowledgeBase(pattern: String)
    /// A `node_modules` folder under a project; `manager` from its internal marker or lockfile
    /// (nil = could not tell).
    case nodeModules(manager: String?)
    /// A build artifact / environment proven by these files (relative to the project root).
    case projectFiles(type: DevArtifactType, files: [String])
}

public struct DevInventoryItem: Identifiable, Equatable, Sendable {
    /// Stable: `kb:<entry path pattern>` or `nm:<project path>`.
    public let id: String
    /// Knowledge-base entry name (English source text, show `L(name)`) or the project folder name.
    public let name: String
    public let nameIsKey: Bool
    public let kind: DevDataKind
    public let ecosystem: DevEcosystem
    /// Project root for dependencies; nil for shared tool data.
    public let projectRoot: String?
    /// Package manager / tool that owns the bytes when known (`npm`, `pnpm`…); nil = unknown.
    public let tool: String?
    /// Paths a plan would move (resolved, standardized).
    public let paths: [String]
    /// nil = still measuring. With `unmeasurable` the value is a lower bound (or 0).
    public let bytes: Int64?
    public let unmeasurable: Bool
    /// Cost of removing it: safe / redo / risky (from the knowledge base; node_modules = redo).
    public let tier: VerdictTier
    public let evidence: DevEvidence
    public let eligibility: CleanupEligibility
    public let selected: Bool
    /// The row is inside another row's path and is not counted again in totals.
    public let nestedInOtherRow: Bool
    /// "In use" is not verified by any detector yet: always nil (UI shows "unknown").
    public let inUse: Bool?
    /// Reinstall/regenerate command when the tool is known (`npm install`…); nil = not stated.
    /// Text only: CleanPilot never runs it.
    public let reinstallHint: String?
}

// MARK: - Classification (pure)

private func has(_ p: String, _ needles: [String]) -> Bool { needles.contains { p.contains($0) } }

/// Ecosystem of a knowledge-base entry, from its tags and path pattern.
public func devEcosystem(of entry: SafetyEntry) -> DevEcosystem {
    let p = entry.path.lowercased()
    if (entry.tags ?? []).contains("ai_models") || has(p, ["/.claude/", "/.codex/", "/.ollama/", "huggingface", "/.cache/torch", "/.cache/whisper"]) {
        return .ai
    }
    if has(p, ["/.nvm/", "/.npm", "/.tnpm", "npminstall", "pnpm", "/yarn", "/.bun/"]) { return .javascript }
    if has(p, ["xcode", "coresimulator", "cocoapods", "swiftpm", "mobilesync", "iossimulatorruntime"]) { return .apple }
    if has(p, ["/pip", "/.conda/", "/.cache/uv"]) { return .python }
    if has(p, ["/.gradle/", "/.m2/", "jetbrains", "androidstudio", "/.android/", "/library/android/"]) { return .jvm }
    if has(p, ["/go/pkg/", "go-build"]) { return .go }
    if has(p, ["/.cargo/"]) { return .rust }
    if has(p, ["homebrew"]) { return .homebrew }
    if has(p, ["orbstack", "docker"]) { return .containers }
    return .other
}

/// Kind of a knowledge-base entry. Records (`cost: data`) are never filed as caches.
public func devKind(of entry: SafetyEntry) -> DevDataKind {
    let p = entry.path.lowercased()
    if p.hasSuffix("/deriveddata") { return .buildOutput }
    if has(p, ["devicesupport", "iossimulatorruntime", "/library/android/sdk", "/.android/avd", "orbstack",
               "codex-runtimes"]) || p.hasSuffix("coresimulator/devices") {
        return .environment
    }
    if (entry.tags ?? []).contains("ai_models"), entry.tier == .redo, has(p, ["model", "/.cache/huggingface", "llama.cpp", "diffusionbee"]) {
        return .environment
    }
    if entry.tier == .risky { return .records }
    return .toolCache
}

/// The command a known package manager reinstalls dependencies with. Text only.
public func nodeReinstallHint(manager: String?) -> String? {
    switch manager {
    case "npm": return "npm install"
    case "pnpm": return "pnpm install"
    case "yarn": return "yarn install"
    case "bun": return "bun install"
    default: return nil
    }
}

private func std(_ p: String) -> String { URL(fileURLWithPath: p).standardizedFileURL.path }

/// Builds the unified inventory. `nodeModulesURL` maps a project to the folder a plan moves.
/// Rows whose paths all lie inside another row's path are flagged `nestedInOtherRow` and
/// excluded from `devInventoryTotals`.
public func devInventory(caches: [CacheItem], projects: [NMProject], artifacts: [DevArtifact] = [],
                         bulkSelectable: (URL) -> Bool = isBulkSelectable) -> [DevInventoryItem] {
    struct Raw { var item: DevInventoryItem; var paths: [String] }
    var raws: [Raw] = []
    for c in caches where c.groupKey == "dev" {
        let paths = c.resolvedPaths.map { $0.standardizedFileURL.path }
        let state = cacheRowState(c)
        let item = DevInventoryItem(
            id: "kb:" + c.entry.path, name: c.entry.name, nameIsKey: true,
            kind: devKind(of: c.entry), ecosystem: devEcosystem(of: c.entry),
            projectRoot: nil, tool: nil, paths: paths,
            bytes: c.size, unmeasurable: state == .unmeasurable,
            tier: c.entry.tier, evidence: .knowledgeBase(pattern: c.entry.path),
            eligibility: cleanupEligibility(c, bulkSelectable: bulkSelectable),
            selected: c.selected, nestedInOtherRow: false, inUse: nil, reinstallHint: nil)
        raws.append(Raw(item: item, paths: paths))
    }
    for p in projects {
        let nm = URL(fileURLWithPath: p.project).appendingPathComponent("node_modules")
        let elig: CleanupEligibility = p.size <= 0 ? .empty : (bulkSelectable(nm) ? .eligible : .notBulkSelectable)
        let item = DevInventoryItem(
            id: "nm:" + std(p.project), name: URL(fileURLWithPath: p.project).lastPathComponent, nameIsKey: false,
            kind: .dependency, ecosystem: .javascript, projectRoot: std(p.project), tool: p.manager,
            paths: [nm.standardizedFileURL.path], bytes: p.size, unmeasurable: false,
            tier: .redo, evidence: .nodeModules(manager: p.manager),
            eligibility: elig, selected: p.selected, nestedInOtherRow: false, inUse: nil,
            reinstallHint: nodeReinstallHint(manager: p.manager))
        raws.append(Raw(item: item, paths: [nm.standardizedFileURL.path]))
    }
    for a in artifacts {
        // Owner decision 07/11/2026: listed, ticked by hand. Never part of a group/bulk selection.
        let item = DevInventoryItem(
            id: "ba:" + std(a.path), name: URL(fileURLWithPath: a.projectRoot).lastPathComponent, nameIsKey: false,
            kind: a.type.kind, ecosystem: a.type.ecosystem, projectRoot: std(a.projectRoot), tool: nil,
            paths: [std(a.path)], bytes: a.bytes, unmeasurable: false, tier: .redo,
            evidence: .projectFiles(type: a.type, files: a.evidence),
            eligibility: a.bytes == nil ? .measuring : .needsReview(.redo),
            selected: a.selected, nestedInOtherRow: false, inUse: nil, reinstallHint: a.reinstallHint)
        raws.append(Raw(item: item, paths: [std(a.path)]))
    }
    // A row is nested when every one of its paths is strictly inside some other row's path.
    let allPaths = raws.enumerated().flatMap { (i, r) in r.paths.map { (i, $0) } }
    return raws.enumerated().map { (i, r) in
        let nested = !r.paths.isEmpty && r.paths.allSatisfy { p in
            allPaths.contains { $0.0 != i && p.hasPrefix($0.1 + "/") }
        }
        guard nested else { return r.item }
        let it = r.item
        return DevInventoryItem(id: it.id, name: it.name, nameIsKey: it.nameIsKey, kind: it.kind,
                                ecosystem: it.ecosystem, projectRoot: it.projectRoot, tool: it.tool,
                                paths: it.paths, bytes: it.bytes, unmeasurable: it.unmeasurable, tier: it.tier,
                                evidence: it.evidence, eligibility: it.eligibility, selected: it.selected,
                                nestedInOtherRow: true, inUse: it.inUse, reinstallHint: it.reinstallHint)
    }
}

public struct DevInventoryTotals: Equatable, Sendable {
    /// Measured bytes of every row, nested rows counted once. nil = something still measuring.
    public let measuredBytes: Int64?
    public let knownBytes: Int64
    public let selectedBytes: Int64
    public let selectedCount: Int
    public let projectCount: Int
    public let toolCount: Int
}

/// Totals without double counting: nested rows are skipped; overlapping paths are unioned.
public func devInventoryTotals(_ items: [DevInventoryItem]) -> DevInventoryTotals {
    func union(_ rows: [DevInventoryItem]) -> Int64 {
        // Rows carry one byte figure for all their paths; outermost rows only.
        rows.filter { !$0.nestedInOtherRow }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
    let selected = items.filter(\.selected)
    return DevInventoryTotals(
        measuredBytes: items.contains { $0.bytes == nil } ? nil : union(items),
        knownBytes: union(items),
        selectedBytes: selected.reduce(0) { acc, r in
            // A selected nested row counts only when its container is not selected too.
            let covered = r.nestedInOtherRow && selected.contains { o in
                o.id != r.id && r.paths.allSatisfy { p in o.paths.contains { p.hasPrefix($0 + "/") } }
            }
            return covered ? acc : acc + (r.bytes ?? 0)
        },
        selectedCount: selected.count,
        projectCount: Set(items.compactMap(\.projectRoot)).count,
        toolCount: items.filter { $0.projectRoot == nil }.count)
}

/// Tri-state per kind, same rule as `cleanupGroupToggle`: on → eligible rows only; a full kind clears.
public func devKindToggle(_ items: [DevInventoryItem], kind: DevDataKind?) -> (ids: [String], on: Bool) {
    let inKind = items.filter { kind == nil || $0.kind == kind }
    let eligible = inKind.filter { $0.eligibility.isEligible }
    if !eligible.isEmpty && eligible.allSatisfy(\.selected) { return (inKind.filter(\.selected).map(\.id), false) }
    return (eligible.filter { !$0.selected }.map(\.id), true)
}

public func devKindSelection(_ items: [DevInventoryItem], kind: DevDataKind?) -> GroupSelection {
    let inKind = items.filter { kind == nil || $0.kind == kind }
    let sel = inKind.filter(\.selected)
    if sel.isEmpty { return .none }
    let eligible = inKind.filter { $0.eligibility.isEligible }
    return !eligible.isEmpty && eligible.allSatisfy(\.selected) && sel.count == eligible.count ? .all : .some
}
