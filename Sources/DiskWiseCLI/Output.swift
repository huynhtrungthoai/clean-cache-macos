import DiskCleanerCore
import Foundation

// Output layer: tables for humans / JSON for programs (--json); stdout carries only results.
// Human output is English: the CLI's primary audience is developers and agents, and this directory is not in the l10n catalog.

var stderrHandle = FileHandle.standardError

func errLog(_ msg: String) {
    stderrHandle.write(Data(("diskwise: " + msg + "\n").utf8))
}

func failUsage(_ msg: String) -> Never {
    stderrHandle.write(Data(("diskwise: " + msg + "\nTry 'diskwise --help'.\n").utf8))
    exit(Exit.usage.rawValue)
}

/// Uniform --json style: pretty + sorted keys, stable for human debugging and machine parsing;
/// slashes not escaped (the default \/ lands mid-path and makes JSON pure noise to read).
func encodeJSON<T: Encodable>(_ value: T) -> String {
    let enc = JSONEncoder.agentAPI
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = (try? enc.encode(value)) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
}

// MARK: - Tables

/// Path display: home directory shown as ~ (absolute paths make a human scan half a line in the terminal).
func displayPath(_ path: String) -> String {
    let home = homePath()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

private func padded(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}

private func mayFlag(_ item: AgentItem) -> String {
    item.agentMayTrash ? "yes" : (item.humanMayTrash ? "human" : "no")
}

/// Generic listing table: size / verdict / actionable / path. A refusal gets its own line outside the table:
/// the table stays narrow, with the reason following the refused item.
func printItemsTable(_ items: [AgentItem], totalLabel: String) {
    if items.isEmpty {
        print("Nothing to show.")
        return
    }
    let total = contentsUnionSize(items.map { ($0.path, $0.bytes) })
    print("\(items.count) \(totalLabel), \(human(total)) total (nested paths counted once)")
    print()
    print("\(padded("SIZE", 10)) \(padded("TIER", 8)) \(padded("TRASH", 6)) PATH")
    for it in items {
        let tier = it.exact ? it.tier : "\(it.tier)~"   // ~ = matched a parent entry, not the item itself
        print("\(padded(human(it.bytes), 10)) \(padded(tier, 8)) \(padded(mayFlag(it), 6)) \(displayPath(it.path))")
        if let r = it.refusal {
            print("\(padded("", 10)) \(padded("", 8)) \(padded("", 6)) refusal: \(r.rawValue)")
        }
    }
}

func printExplainBlock(_ item: AgentItem) {
    print("\(displayPath(item.path)) · \(human(item.bytes)) on disk")
    if let n = item.name { print("  what        : \(n)") }
    if let w = item.what { print("              \(w)") }
    if let d = item.ifDeleted { print("  if deleted  : \(d)") }
    if let r = item.howToRestore { print("  how to undo : \(r)") }
    print("  tier        : \(item.tier)\(item.exact ? "" : " (inside a known location, not the location itself)")")
    print("  agent may trash : \(item.agentMayTrash ? "yes" : "no")"
          + (item.agentMayTrash ? "" : " (refusal: \(item.refusal?.rawValue ?? "?"))"))
    print("  human may trash: \(item.humanMayTrash ? "yes" : "no")")
}

func printPlanBlock(_ plan: AgentPlan) {
    let mins = Int(plan.expiresAt.timeIntervalSince(Date()) / 60)
    print("Plan \(plan.planId)")
    print("  valid for ~\(max(0, mins)) min · execute with: diskwise trash --plan \(plan.planId)")
    print()
    printItemsTable(plan.items, totalLabel: "items to move to Trash")
    if !plan.refused.isEmpty {
        print()
        print("\(plan.refused.count) refused (will NOT be touched):")
        for it in plan.refused {
            print("  \(displayPath(it.path)) — \(it.refusal?.rawValue ?? "?")")
        }
    }
}

func printResultBlock(_ result: AgentResult) {
    if !result.trashed.isEmpty {
        print("Moved \(result.trashed.count) item(s), \(human(result.totalBytes)) to the Trash.")
        print("Undo with: diskwise undo\(result.operationId.isEmpty ? "" : " \(result.operationId)")")
    } else {
        print("Nothing was moved.")
    }
    for f in result.failed {
        print("  refused: \(displayPath(f.path)) — \(f.reason)" + (f.detail.map { " (\($0))" } ?? ""))
    }
}

func printUndoBlock(_ statuses: [AgentUndoStatus]) {
    for s in statuses {
        switch s.status {
        case "restored": print("restored : \(displayPath(s.path))")
        case "gone_from_trash": print("skipped  : \(displayPath(s.path)) — already gone from the Trash")
        default: print("FAILED   : \(displayPath(s.path)) — \(s.detail ?? "unknown error")")
        }
    }
}

func printHistoryBlock(_ ops: [AgentOperation]) {
    if ops.isEmpty {
        print("No operations yet.")
        return
    }
    // Chronological order (ledger reading order); the newest is the last line
    print("\(ops.count) operation(s), oldest first:")
    for op in ops {
        let bytes = op.items.reduce(Int64(0)) { $0 + $1.bytes }
        let df = ISO8601DateFormatter()
        print("  \(op.id) · \(df.string(from: op.at)) · \(op.client ?? "unknown") · \(op.items.count) item(s) · \(human(bytes))"
              + (op.undoneAt == nil ? "" : " · undone"))
    }
}
