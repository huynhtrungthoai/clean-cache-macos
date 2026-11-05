import Foundation
import Darwin

// ── Agent channel: expose "locations the knowledge base knows and judges safe" to CLI / MCP ──
//
// The app's entry point is a human clicking; this layer exposes the same verdicts and the same deletion path to programs,
// but tighter: an agent may only touch a known knowledge-base location **itself** (exact); risky is never allowed,
// not even for humans. Two-step confirmation turns from "click twice" in the UI into a plan file + execute re-validation:
// a plan is valid for only 10 minutes; at execute time every item re-runs the pipeline and checks its inode,
// so a path cannot be swapped for something else after the plan was generated.
//
// State dirs (plans/ and operations.jsonl) are all built from homeDir(): self-tests use
// DISKWISE_HOME_SHIM to move the whole state tree into /tmp, so never hard-code NSHomeDirectory().
//
// All agent-facing output in this file is English (agents read English most reliably); errors use reason codes, not sentences.
// Note: the l10n coverage gate scans string literals in this directory, so no Chinese copy here.

// Per-plan cap. It limits "how much one plan can take at most", not individual item size:
// without it, a persuaded agent could wipe every cache on the machine in one go.
let agentPlanTTL: TimeInterval = 600
let agentPlanMaxItems = 200
let agentPlanMaxBytes: Int64 = 200 * GB

// MARK: - Types

public enum AgentCategory: String, Codable {
    case all
    case dev
    case aiModels = "ai_models"
    case apps
}

/// Reason codes when agent_may_trash / human_may_trash is false.
/// The order is the decision pipeline's order; don't change one tier's semantics in isolation.
public enum AgentRefusal: String, Codable {
    case notFound = "not_found"
    case symlink
    case protected
    case outsideAllowed = "outside_allowed"
    case unknownToKnowledgeBase = "unknown_to_knowledge_base"
    case mayLoseData = "may_lose_data"
    /// The path lies **inside** a known location but is not itself a known location.
    /// User-created folders inside a cache dir are this tier: an agent can't name them, a human can.
    case notAKnownLocation = "not_a_known_location"
}

/// A path's full profile as seen by an agent. Human-readable explanation fields (what, etc.) are English.
public struct AgentItem: Codable {
    public let path: String            // absolute path (~ expanded, .. lexically collapsed)
    public let bytes: Int64            // measured on-disk usage (st_blocks × 512 basis)
    public let name: String?           // knowledge-base entry name (English; falls back to Chinese if missing)
    public let tier: String            // safe | redo | risky | unknown
    public let exact: Bool             // whether this is the knowledge-base entry (or its wildcard instance) itself
    public let what: String?
    public let ifDeleted: String?
    public let howToRestore: String?
    /// Whether it may enter a plan and be executed in strict mode (agent / MCP).
    public let agentMayTrash: Bool
    /// Whether it may enter a plan under --i-am-human (unknown and non-exact allowed, risky still refused).
    public let humanMayTrash: Bool
    /// Reason for refusal in strict mode; nil when allowed.
    public let refusal: AgentRefusal?
    /// Where this profile came from: knowledge_base (entry) or signature (engine-managed cache signature).
    /// Old JSON/plan files lack this field and decode to nil; display it as knowledge_base.
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case path, bytes, name, tier, exact, what
        case ifDeleted = "if_deleted"
        case howToRestore = "how_to_restore"
        case agentMayTrash = "agent_may_trash"
        case humanMayTrash = "human_may_trash"
        case refusal, source
    }

    init(path: String, bytes: Int64, name: String?, tier: String, exact: Bool,
         what: String?, ifDeleted: String?, howToRestore: String?,
         agentMayTrash: Bool, humanMayTrash: Bool, refusal: AgentRefusal?,
         source: String? = nil) {
        self.path = path
        self.bytes = bytes
        self.name = name
        self.tier = tier
        self.exact = exact
        self.what = what
        self.ifDeleted = ifDeleted
        self.howToRestore = howToRestore
        self.agentMayTrash = agentMayTrash
        self.humanMayTrash = humanMayTrash
        self.refusal = refusal
        self.source = source
    }
}

/// Return value of plan; also the display part of the plan file besides validation data.
public struct AgentPlan: Codable {
    public let planId: String
    public let createdAt: Date
    public let expiresAt: Date
    public let items: [AgentItem]       // executable items
    public let refused: [AgentItem]     // refused items (the refusal field explains why)
    /// Real reclaimable after de-nesting: nested paths count only the outermost one;
    /// summing item bytes directly overstates (select-all on the caches page once overstated by 5.5 GB).
    public let totalBytes: Int64

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case items, refused
        case totalBytes = "total_bytes"
    }
}

/// "What was moved" in an execute result. original/in_trash are the basis for undo.
public struct AgentTrashRecord: Codable {
    public let original: String
    public let inTrash: String
    public let bytes: Int64
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case original
        case inTrash = "in_trash"
        case bytes, name
    }

    public init(original: String, inTrash: String, bytes: Int64, name: String?) {
        self.original = original
        self.inTrash = inTrash
        self.bytes = bytes
        self.name = name
    }
}

/// An item refused or failed at execute time. reason is a reason code (AgentRefusal rawValue,
/// plus trash_failed / changed_since_plan / covered_by_earlier_item).
public struct AgentFailure: Codable {
    public let path: String
    public let reason: String
    public let detail: String?
}

public struct AgentResult: Codable {
    public let operationId: String
    public let trashed: [AgentTrashRecord]
    public let failed: [AgentFailure]
    public let totalBytes: Int64

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case trashed, failed
        case totalBytes = "total_bytes"
    }
}

public struct AgentUndoStatus: Codable {
    public let path: String             // original location
    /// restored | gone_from_trash | failed
    public let status: String
    public let detail: String?

    /// Public for self-tests: `agentUndoTally` consumes this stack of receipts, and SelfTest only links this module;
    /// without constructing receipts it can't verify the "how many in each of the three tiers" tally.
    public init(path: String, status: String, detail: String? = nil) {
        self.path = path
        self.status = status
        self.detail = detail
    }
}

public struct AgentOperation: Codable {
    public let id: String
    public let at: Date
    /// Who initiated this operation: the name an MCP client self-reported in initialize, or the terminal CLI.
    /// Old log lines lack this field and decode to nil; the UI must treat nil as "unknown source", not an error.
    public let client: String?
    public let items: [AgentTrashRecord]
    /// Back-filled by an appended marker line after undo; nil = not yet undone
    public let undoneAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, at, client, items
        case undoneAt = "undone_at"
    }

    public init(id: String, at: Date, client: String? = nil, items: [AgentTrashRecord], undoneAt: Date? = nil) {
        self.id = id
        self.at = at
        self.client = client
        self.items = items
        self.undoneAt = undoneAt
    }
}

/// Undo marker: append-only, never rewrite the original line. The operation log is a ledger; ledgers are not altered.
struct AgentUndoneMarker: Codable {
    let id: String
    let undoneAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case undoneAt = "undone_at"
    }
}

/// On-disk structure of a plan file. Public because it's a disk format: self-tests need to edit
/// expires_at directly to fabricate expired plans, rather than adding a test backdoor in Core.
public struct AgentPlanRecord: Codable {
    public var planId: String
    public var createdAt: Date
    public var expiresAt: Date
    /// Whether the plan was generated under --i-am-human: execute re-validation must use the same tier
    public var human: Bool
    public var items: [AgentPlanItemRecord]
    public var refused: [AgentItem]
    public var totalBytes: Int64

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case human, items, refused
        case totalBytes = "total_bytes"
    }

    public init(planId: String, createdAt: Date, expiresAt: Date, human: Bool,
                items: [AgentPlanItemRecord], refused: [AgentItem], totalBytes: Int64) {
        self.planId = planId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.human = human
        self.items = items
        self.refused = refused
        self.totalBytes = totalBytes
    }
}

/// Execution binding for a plan item: records dev/ino besides the path. After plan generation an in-place rename
/// can swap the content while path and verdict stay the same; only the inode exposes it.
public struct AgentPlanItemRecord: Codable {
    public var path: String
    public var bytes: Int64
    public var dev: UInt64
    public var ino: UInt64

    public init(path: String, bytes: Int64, dev: UInt64, ino: UInt64) {
        self.path = path
        self.bytes = bytes
        self.dev = dev
        self.ino = ino
    }
}

public enum AgentAPIError: Error, CustomStringConvertible {
    case planExpired
    case planNotFound
    case planTooLarge(items: Int, bytes: Int64)
    case invalidPath(String)
    case noUndoableOperation

    public var description: String {
        switch self {
        case .planExpired: return "plan_expired"
        case .planNotFound: return "plan_not_found"
        case .planTooLarge: return "plan_too_large"
        case .invalidPath: return "invalid_path"
        case .noUndoableOperation: return "no_undoable_operation"
        }
    }
}

// MARK: - Unified JSON format (shared by CLI and MCP; explicit key names, no automatic conversion strategy)

extension JSONEncoder {
    public static var agentAPI: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    public static var agentAPI: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Decision pipeline (shared by all entry points, fixed order)

struct AgentPathCheck {
    let url: URL               // expanded, standardized absolute path
    let tier: VerdictTier      // .unknown when entry is nil
    let exact: Bool
    let entry: SafetyEntry?
    /// Refusal reason in strict mode (agent / MCP); nil = allowed
    let refusal: AgentRefusal?
    /// Refusal reason in --i-am-human mode; nil = allowed (risky and hard pipeline refusals are refused in both modes)
    let humanRefusal: AgentRefusal?
    /// Unknown to the knowledge base but matched by a signature (engine-managed cache): tier capped at redo, exact always false.
    var signature: Bool = false
}

/// Pipeline order: expand → protect → scope → lstat → verdict.
/// Protection and scope come before lstat on purpose: when `/usr/local/x` doesn't exist,
/// the useful answer for an agent is "this can never be touched" (outside_allowed),
/// not not_found; the former closes the topic, the latter only invites the next probe.
/// Lexical collapsing happens here: `~/.npm/../Documents` collapses to `~/Documents` before entering the pipeline.
func agentPipeline(_ raw: String, index: VerdictIndex) -> AgentPathCheck {
    let url = URL(fileURLWithPath: expandHome(raw)).standardizedFileURL
    // deletionGate = lexical + canonical (case-folded, parent symlinks resolved) checks,
    // the same gate trashItem enforces, so plan/explain never promise what trash refuses.
    switch deletionGate(url) {
    case .protected?:
        return .init(url: url, tier: .unknown, exact: false, entry: nil,
                     refusal: .protected, humanRefusal: .protected)
    case .outsideAllowed?:
        return .init(url: url, tier: .unknown, exact: false, entry: nil,
                     refusal: .outsideAllowed, humanRefusal: .outsideAllowed)
    case nil:
        break
    }
    var st = stat()
    if lstat(url.path, &st) != 0 {
        return .init(url: url, tier: .unknown, exact: false, entry: nil,
                     refusal: .notFound, humanRefusal: .notFound)
    }
    // Symlinks are always refused: moving the link itself is fine, but "the location in the plan" and "the actual content"
    // would no longer match; to keep semantics simple, say no at this tier.
    if (st.st_mode & S_IFMT) == S_IFLNK {
        return .init(url: url, tier: .unknown, exact: false, entry: nil,
                     refusal: .symlink, humanRefusal: .symlink)
    }
    let v = index.verdict(for: url.path)
    // When the knowledge base doesn't know it, try signatures: engine-managed caches by layout (HF model repos, updater caches, loose weights).
    // Tier capped at redo, exact always false; the agent contract is unchanged: non-exact redo still gets
    // not_a_known_location, and a human can still take it via --i-am-human.
    if v.tier == .unknown, let sig = signatureMatch(url) {
        return .init(url: url, tier: .redo, exact: false, entry: sig.entry,
                     refusal: .notAKnownLocation, humanRefusal: nil, signature: true)
    }
    var refusal: AgentRefusal? = nil
    var humanRefusal: AgentRefusal? = nil
    switch v.tier {
    case .risky:
        // Gone once deleted: agent, --i-am-human, MCP — nobody gets it
        refusal = .mayLoseData
        humanRefusal = .mayLoseData
    case .unknown:
        refusal = .unknownToKnowledgeBase
    case .safe, .redo:
        // A subpath inside a known location is not a known location: humans may (same freedom as the drill-down page), agents may not
        if !v.exact { refusal = .notAKnownLocation }
    }
    return .init(url: url, tier: v.tier, exact: v.exact, entry: v.entry,
                 refusal: refusal, humanRefusal: humanRefusal)
}

/// Assemble the pipeline result into the public profile. Explanation fields look up the en table, falling back to the Chinese original:
/// better mixed languages than inventing an English sentence on the spot.
func agentItem(_ c: AgentPathCheck, bytes: Int64) -> AgentItem {
    func en(_ zh: String?) -> String? {
        guard let zh else { return nil }
        return enText(zh) ?? zh
    }
    return AgentItem(path: c.url.path,
                     bytes: bytes,
                     name: en(c.entry?.name),
                     tier: c.tier.rawValue,
                     exact: c.exact,
                     what: en(c.entry?.what),
                     ifDeleted: en(c.entry?.whatif),
                     howToRestore: en(c.entry?.rec),
                     agentMayTrash: c.refusal == nil,
                     humanMayTrash: c.humanRefusal == nil,
                     refusal: c.refusal,
                     source: c.signature ? "signature" : "knowledge_base")
}

// MARK: - State directory

public func agentStateDir() -> URL {
    // Based on homeDir() not NSHomeDirectory(): the latter is the container path in a sandbox,
    // and the self-test's fake home only honors the former. Public because it's the root of the disk format:
    // self-tests go into plans/ and edit plan files to fabricate expiry, rather than adding a test backdoor in Core.
    homeDir().appendingPathComponent("Library/Application Support/DiskWise/agent", isDirectory: true)
}

public func agentPlansDir() -> URL { agentStateDir().appendingPathComponent("plans", isDirectory: true) }

func agentOperationsFile() -> URL { agentStateDir().appendingPathComponent("operations.jsonl") }

func appendJSONL<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let data = try JSONEncoder.agentAPI.encode(value)
    let fh = try FileHandle(forWritingTo: url)
    try fh.seekToEnd()
    try fh.write(contentsOf: data)
    try fh.write(contentsOf: Data([0x0A]))
    try fh.close()
}

/// Read all operations and back-fill undo markers. The log is append-only: operation lines first, marker lines later;
/// merging by id yields the full history.
func readAgentOperations() -> [AgentOperation] {
    guard let text = try? String(contentsOf: agentOperationsFile(), encoding: .utf8) else { return [] }
    let dec = JSONDecoder.agentAPI
    var ops: [AgentOperation] = []
    var undone: [String: Date] = [:]
    for line in text.split(separator: "\n") where !line.isEmpty {
        let d = Data(line.utf8)
        if let op = try? dec.decode(AgentOperation.self, from: d) {
            ops.append(op)
        } else if let m = try? dec.decode(AgentUndoneMarker.self, from: d) {
            undone[m.id] = m.undoneAt
        }
        // Skip lines that decode as neither type: the log is a ledger, a bad line shouldn't topple the whole history
    }
    return ops.map { o in
        o.undoneAt == nil && undone[o.id] != nil
            // client must be carried along: if dropped, undone rows show up on the page as "unknown source",
            // while the self-reported name sits right there in the log (AgentAPI's doc for this field says
            // "only old lines should be treated as unknown source").
            ? AgentOperation(id: o.id, at: o.at, client: o.client,
                             items: o.items, undoneAt: undone[o.id])
            : o
    }
}

// MARK: - en table (read-only; located the same way as safetyDBFileURL)

private func enTableURL() -> URL? {
    // Test override: points to a resources dir (containing en.lproj/Localizable.strings)
    let dir = envString("DISKWISE_RESOURCES")   // dev/test hook; ignored in release
    if !dir.isEmpty {
        let u = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
            .appendingPathComponent("en.lproj/Localizable.strings")
        if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    // Packaged build (including brew's binary symlink; proc_pidpath resolves back to the .app):
    // name en.lproj explicitly, don't follow system language; agents always get English
    if let u = Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                               subdirectory: "en.lproj") { return u }
    // swift run fallback: cwd is the package root (same convention as safetyDBFileURL). Debug/dev-hooks only.
    guard devHooksEnabled else { return nil }
    let dev = "Sources/DiskCleaner/Resources/en.lproj/Localizable.strings"
    return FileManager.default.fileExists(atPath: dev) ? URL(fileURLWithPath: dev) : nil
}

/// The table is a machine-validated one-entry-per-line format ("source" = "translation";); take the first two string
/// literals per line, same algorithm as readTable in build_app/l10n_tool.swift.
private func loadEnTable() -> [String: String] {
    guard let url = enTableURL(), let text = try? String(contentsOf: url, encoding: .utf8) else {
        return [:]
    }
    var out: [String: String] = [:]
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("/") { continue }    // blank lines and comments
        let segs = quotedSegments(line)
        if segs.count >= 2 { out[segs[0]] = segs[1] }
    }
    return out
}

private func quotedSegments(_ line: String) -> [String] {
    var out: [String] = []
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        guard chars[i] == "\"" else { i += 1; continue }
        var body = ""
        var j = i + 1
        var closed = false
        while j < chars.count {
            if chars[j] == "\\" && j + 1 < chars.count {
                body.append(chars[j + 1] == "n" ? "\n" : String(chars[j + 1]))
                j += 2
                continue
            }
            if chars[j] == "\"" { closed = true; break }
            body.append(chars[j])
            j += 1
        }
        if closed { out.append(body) }
        i = closed ? j + 1 : chars.count
    }
    return out
}

// Lazy init of globals is thread-safe (concurrent lookups in scan's TaskGroup are fine)
private let enTable: [String: String] = loadEnTable()

/// Chinese source → English translation; returns nil when missing, caller falls back to the Chinese original.
public func enText(_ key: String) -> String? { enTable[key] }

// MARK: - Six entry points

/// Walk knowledge-base entries (same universe as the caches page) and measure each location's real disk usage.
/// Produced paths are inherently exact; rows measuring 0 are dropped, same rule as the caches page:
/// that 0 most likely means "unreadable", not "empty".
public func agentScan(category: AgentCategory = .all, minBytes: Int64 = 0,
                      index: VerdictIndex = .shared) async -> [AgentItem] {
    let entries = loadSafetyEntries(from: safetyDBFileURL()).filter { e in
        switch category {
        case .all: return true
        case .dev: return e.grp == "dev"
        case .apps: return e.grp == "general" || e.grp == "cn_app"
        case .aiModels: return e.tags?.contains("ai_models") == true
        }
    }
    var targets: [(entry: SafetyEntry, url: URL)] = []
    var seen = Set<String>()
    for e in entries where !e.path.isEmpty {
        for u in globExpand(e.path) where !seen.contains(u.path) {
            seen.insert(u.path)
            targets.append((e, u))
        }
    }
    var sizes: [String: Int64] = [:]
    await withTaskGroup(of: (String, Int64).self) { group in
        for t in targets {
            group.addTask {
                (t.url.path, await pathStat(t.url).bytes)
            }
        }
        for await (p, b) in group { sizes[p] = b }
    }
    var out: [AgentItem] = []
    for t in targets {
        let c = agentPipeline(t.url.path, index: index)
        let item = agentItem(c, bytes: sizes[t.url.path] ?? 0)
        if item.bytes > 0 && item.bytes >= minBytes { out.append(item) }
    }
    // Signature discovery fills gaps: engine-managed caches the knowledge base didn't report, matched by layout; HF model repos can live in
    // any project's var, entries can't keep up. Deduped against entry results by path: shallow paths are counted first,
    // covered deeper paths aren't reported again (~/.cache/huggingface/hub won't appear again under an entry).
    var covered = seen
    for m in await signatureScan().sorted(by: { $0.url.path.count < $1.url.path.count }) {
        let p = m.url.path
        guard !covered.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) else { continue }
        covered.insert(p)
        guard category == .all || m.categories.contains(category) else { continue }
        let c = agentPipeline(p, index: index)
        let item = agentItem(c, bytes: await pathStat(m.url).bytes)
        if item.bytes > 0 && item.bytes >= minBytes { out.append(item) }
    }
    out.sort { $0.bytes > $1.bytes }
    return out
}

/// Full profile of a single path (read-only, touches no files).
public func agentExplain(path: String, index: VerdictIndex = .shared) async -> AgentItem {
    let c = agentPipeline(path, index: index)
    return agentItem(c, bytes: await pathStat(c.url).bytes)
}

/// Generate a plan: touches no files, only writes the plan file. humanOverride corresponds to --i-am-human
/// (allows unknown and non-exact; risky still refused). Exceeding the count or byte cap throws immediately,
/// writing nothing; the cap exists so "take the whole machine at once" fails at the source.
public func agentPlan(paths: [String], humanOverride: Bool = false,
                      index: VerdictIndex = .shared) async throws -> AgentPlan {
    guard !paths.isEmpty else { throw AgentAPIError.invalidPath("no paths given") }
    var items: [AgentItem] = []
    var refused: [AgentItem] = []
    var records: [AgentPlanItemRecord] = []
    var seenPaths = Set<String>()
    for raw in paths {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        let c = agentPipeline(raw, index: index)
        if seenPaths.contains(c.url.path) { continue }
        seenPaths.insert(c.url.path)
        let bytes = await pathStat(c.url).bytes
        let item = agentItem(c, bytes: bytes)
        let allowed = c.refusal == nil || (humanOverride && c.humanRefusal == nil)
        if allowed {
            items.append(item)
            var st = stat()
            _ = lstat(c.url.path, &st)   // the pipeline just confirmed existence; this only fetches the inode for binding
            records.append(AgentPlanItemRecord(path: c.url.path, bytes: bytes,
                                               dev: UInt64(st.st_dev), ino: UInt64(st.st_ino)))
        } else {
            refused.append(item)
        }
    }
    if items.isEmpty { throw AgentAPIError.invalidPath("no trashable paths in plan") }
    if items.count > agentPlanMaxItems {
        throw AgentAPIError.planTooLarge(items: items.count, bytes: 0)
    }
    // Totals must be de-nested: the agent's list may be nested (~/Library/Caches and its children);
    // summing per item counts the same bytes twice and inflates the "will free" the user sees
    let total = contentsUnionSize(items.map { ($0.path, $0.bytes) })
    if total > agentPlanMaxBytes {
        throw AgentAPIError.planTooLarge(items: items.count, bytes: total)
    }
    let id = UUID().uuidString
    let now = Date()
    let record = AgentPlanRecord(planId: id, createdAt: now,
                                 expiresAt: now.addingTimeInterval(agentPlanTTL),
                                 human: humanOverride, items: records,
                                 refused: refused, totalBytes: total)
    let dir = agentPlansDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try JSONEncoder.agentAPI.encode(record)
        .write(to: dir.appendingPathComponent("\(id).json"))
    return AgentPlan(planId: id, createdAt: record.createdAt, expiresAt: record.expiresAt,
                     items: items, refused: refused, totalBytes: total)
}

/// Executes only a previously generated plan, re-running the pipeline and checking inode for each item. An expired or missing plan is
/// a hard failure: rejected wholesale, no file touched; a refused item is a soft failure: recorded, then continue,
/// the rest proceed (matches CLI exit code 2 "partial success").
///
/// The trash parameter defaults to Core's only deletion path, trashItem; self-tests inject a fake mover
/// so test junk doesn't land in the real Trash; the real Trash round trip is covered by manual CLI testing.
/// client is recorded in the operation log to answer "who did this": MCP passes the client's self-reported name, terminal keeps the default.
public func agentExecute(planId: String, index: VerdictIndex = .shared,
                         client: String = "diskwise-cli",
                         trash: (URL) throws -> URL = trashItem) throws -> AgentResult {
    // plan_id is a UUID we issued: anything with path separators or upward segments is treated as "not found",
    // leaving no gap for path building (removeItem below only touches plan files we issued that decode validly)
    guard !planId.isEmpty, !planId.contains("/"), !planId.contains("\\"),
          !planId.hasPrefix(".") else {
        throw AgentAPIError.planNotFound
    }
    let fileURL = agentPlansDir().appendingPathComponent("\(planId).json")
    guard let data = try? Data(contentsOf: fileURL),
          let rec = try? JSONDecoder.agentAPI.decode(AgentPlanRecord.self, from: data) else {
        throw AgentAPIError.planNotFound
    }
    guard Date() < rec.expiresAt else {
        // Delete expired plans on the spot: no execution can accept them anymore; keeping them only piles up.
        // This deletes our own bookkeeping file (JSON under agent/), not via Trash; the iron rule governs
        // user data; dumping internal state into the user's Trash would be the wrong move.
        try? FileManager.default.removeItem(at: fileURL)
        throw AgentAPIError.planExpired
    }
    var trashed: [AgentTrashRecord] = []
    var failed: [AgentFailure] = []
    var trashedPaths: [String] = []
    for item in rec.items {
        let c = agentPipeline(item.path, index: index)
        var st = stat()
        let lstatOK = lstat(c.url.path, &st) == 0
        var fail: String? = nil
        if !lstatOK {
            // A previous item already moved the parent dir: this item didn't "fail", it was carried along by the earlier one
            if let anc = trashedPaths.first(where: { item.path == $0 || item.path.hasPrefix($0 + "/") }) {
                failed.append(AgentFailure(path: item.path, reason: "covered_by_earlier_item", detail: anc))
                continue
            }
            fail = AgentRefusal.notFound.rawValue
        } else if c.refusal != nil, !(rec.human && c.humanRefusal == nil) {
            // Pipeline refusal takes precedence over inode comparison: swapped to a symlink reports symlink, swapped to risky content reports
            // may_lose_data, which tells the agent better what to do next than changed_since_plan
            fail = c.refusal!.rawValue
        } else if UInt64(st.st_dev) != item.dev || UInt64(st.st_ino) != item.ino {
            // Path still exists and verdict unchanged, but the inode changed: content was swapped in place after plan generation
            fail = "changed_since_plan"
        }
        if let fail {
            failed.append(AgentFailure(path: item.path, reason: fail, detail: nil))
            continue
        }
        do {
            let inTrash = try trash(c.url)
            trashed.append(AgentTrashRecord(original: c.url.path, inTrash: inTrash.path,
                                            bytes: item.bytes,
                                            name: (c.url.path as NSString).lastPathComponent))
            trashedPaths.append(c.url.path)
        } catch let e as TrashError {
            // Reason codes align with the pipeline; everything else is trash_failed, with the system's message in detail
            let reason: String
            switch e {
            case .protected: reason = AgentRefusal.protected.rawValue
            case .outsideAllowed: reason = AgentRefusal.outsideAllowed.rawValue
            default: reason = "trash_failed"
            }
            failed.append(AgentFailure(path: c.url.path, reason: reason, detail: e.detail))
        } catch {
            failed.append(AgentFailure(path: c.url.path, reason: "trash_failed",
                                       detail: error.localizedDescription))
        }
    }
    if !trashed.isEmpty {
        let opID = UUID().uuidString
        try appendJSONL(AgentOperation(id: opID, at: Date(), client: client, items: trashed),
                        to: agentOperationsFile())
        try? FileManager.default.removeItem(at: fileURL)   // plan consumed
        return AgentResult(operationId: opID, trashed: trashed, failed: failed,
                           totalBytes: trashed.reduce(0) { $0 + $1.bytes })
    }
    // Nothing moved: don't record an operation (nothing happened), but still delete the plan; a retry would refuse everything too
    try? FileManager.default.removeItem(at: fileURL)
    return AgentResult(operationId: "", trashed: [], failed: failed, totalBytes: 0)
}

/// Undo an operation (nil = the most recent not-yet-undone one). Uses untrash's no-overwrite-on-same-name logic;
/// items no longer in Trash report gone_from_trash; one failure doesn't abort restoring the rest.
public func agentUndo(operationId: String? = nil) throws -> [AgentUndoStatus] {
    let ops = readAgentOperations()
    let target = operationId == nil
        ? ops.last { $0.undoneAt == nil }
        : ops.last { $0.id == operationId && $0.undoneAt == nil }
    guard let op = target else { throw AgentAPIError.noUndoableOperation }
    var out: [AgentUndoStatus] = []
    for it in op.items {
        guard FileManager.default.fileExists(atPath: it.inTrash) else {
            out.append(AgentUndoStatus(path: it.original, status: "gone_from_trash", detail: nil))
            continue
        }
        do {
            try untrash(TrashRecord(original: URL(fileURLWithPath: it.original),
                                    inTrash: URL(fileURLWithPath: it.inTrash),
                                    size: it.bytes, displayName: it.name ?? ""))
            out.append(AgentUndoStatus(path: it.original, status: "restored", detail: nil))
        } catch {
            out.append(AgentUndoStatus(path: it.original, status: "failed",
                                       detail: error.localizedDescription))
        }
    }
    try appendJSONL(AgentUndoneMarker(id: op.id, undoneAt: Date()), to: agentOperationsFile())
    return out
}

/// Most recent `limit` operations (chronological; the caller decides presentation).
public func agentHistory(limit: Int = 20) -> [AgentOperation] {
    let ops = readAgentOperations()
    return Array(ops.suffix(max(0, limit)))
}
