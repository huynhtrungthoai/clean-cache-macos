import DiskCleanerCore
import Foundation

// diskwise: exposes "locations the knowledge base knows and deems safe" to the terminal and AI agents.
//
// Same discipline as the app: the only deletion path is Core's trashItem (Trash only), risky is never
// unlocked, and trash accepts only a plan_id, never a bare path. Forcing plan-then-trash is the same idea
// as the app UI's "click twice" confirmation. stdout carries only results (agents parse it); logs and progress
// always go to stderr.

// Release builds ignore DISKWISE_* developer hooks (an MCP client's `env` block must not be
// able to move the home directory / deletion boundary or swap the string table).
scrubDevEnvironment()

let args = Array(CommandLine.arguments.dropFirst())

/// Exit-code contract: 0 success; 1 bad arguments; 2 some items refused (partial success is also 2; the JSON
/// says which succeeded); 3 plan expired or not found. Scripts branch on these; don't change the semantics.
enum Exit: Int32 {
    case ok = 0
    case usage = 1
    case refused = 2
    case planGone = 3
}

func versionString() -> String {
    // Packaged build reads the .app's Info.plist (brew's binary symlink resolves back into the .app);
    // swift run / bare binary falls back to dev
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
}

func printHelp() {
    print("""
    diskwise \(versionString()) — let your AI agent (or you) reclaim disk space, safely.

    It never deletes anything permanently: the only removal path moves items to the
    Trash, and every operation can be undone. Agents may only touch locations the
    knowledge base knows and rates safe/redo; risky ones are never touchable.

    Usage:
      diskwise scan [--category all|dev|ai_models|apps] [--min 100MB] [--json]
          Lists knowledge-base locations plus signature-discovered engine caches
          (hub-layout model repositories, loose model weights, updater download
          caches) — each item carries a "source" field. Signature items are
          redo-tier and agent-untouchable; --i-am-human may take them.
      diskwise explain <path> [--json]
      diskwise plan <path>... [--i-am-human] [--json]
          Draw up a cleanup plan. Touches nothing. --i-am-human also admits
          unknown-to-the-KB locations (risky is still refused). Plans expire in
          10 minutes and cover at most 200 items / 200 GB.
      diskwise trash --plan <plan_id> [--json]
          Execute a plan. Takes a plan id only, never raw paths — the two-step
          confirm is deliberate, same idea as the app's double-click confirm.
          Re-validates every item at execution time.
      diskwise undo [<operation_id>] [--json]
      diskwise history [--limit 20] [--json]
      diskwise mcp
          Run as a Model Context Protocol server over stdio (for Claude Code,
          Cursor, Codex and friends).
      diskwise --version

    Exit codes: 0 ok · 1 usage error · 2 some items refused (partial success
    counts) · 3 plan expired or unknown.
    """)
}

/// AgentAPIError -> (stderr message, exit code). Messages tell the caller what to do next:
/// plan_expired is normal (the user approves a dozen minutes later), so the agent must be told to re-plan.
func mapAgentError(_ e: AgentAPIError) -> (String, Exit) {
    switch e {
    case .planExpired:
        return ("plan expired (valid 10 min) — run plan again and get a fresh id", .planGone)
    case .planNotFound:
        return ("no such plan (expired, already executed, or wrong id) — run plan again", .planGone)
    case .planTooLarge(let items, let bytes):
        return ("plan too large: \(items) items / \(human(bytes)) (limits: 200 items / 200 GB) — plan fewer paths", .refused)
    case .invalidPath:
        return ("no trashable path in the request", .usage)
    case .noUndoableOperation:
        return ("nothing to undo", .usage)
    }
}

func failAgentError(_ e: AgentAPIError) -> Never {
    let (msg, code) = mapAgentError(e)
    errLog("diskwise: \(msg)")
    exit(code.rawValue)
}

switch args.first {
case nil, "--help", "-h", "help":
    printHelp()

case "--version", "version":
    print("diskwise \(versionString())")

case "scan":
    var category = AgentCategory.all
    var minBytes: Int64 = 0
    var json = false
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--category":
            guard i + 1 < args.count, let c = AgentCategory(rawValue: args[i + 1]) else {
                failUsage("--category must be one of all|dev|ai_models|apps")
            }
            category = c; i += 2
        case "--min":
            guard i + 1 < args.count, let b = try? parseSize(args[i + 1]) else {
                failUsage("--min needs a size like 100MB, 2GB or plain bytes")
            }
            minBytes = b; i += 2
        case "--json":
            json = true; i += 1
        default:
            failUsage("scan: unknown argument \(args[i])")
        }
    }
    errLog("Scanning knowledge-base and signature-discovered locations (category \(category.rawValue))…")
    let items = await agentScan(category: category, minBytes: minBytes)
    if json {
        print(encodeJSON(items))
    } else {
        printItemsTable(items, totalLabel: "locations")
    }
    exit(Exit.ok.rawValue)

case "explain":
    guard args.count >= 2 else { failUsage("explain: a path is required") }
    let path = args[1]
    if args.dropFirst(2).contains("--json") {
        print(encodeJSON(await agentExplain(path: path)))
    } else {
        printExplainBlock(await agentExplain(path: path))
    }
    exit(Exit.ok.rawValue)

case "plan":
    var paths: [String] = []
    var human = false
    var json = false
    for a in args.dropFirst() {
        switch a {
        case "--i-am-human": human = true
        case "--json": json = true
        default:
            if a.hasPrefix("-") { failUsage("plan: unknown flag \(a)") }
            paths.append(a)
        }
    }
    guard !paths.isEmpty else { failUsage("plan: at least one path is required") }
    let plan: AgentPlan
    do {
        plan = try await agentPlan(paths: paths, humanOverride: human)
    } catch let e as AgentAPIError {
        failAgentError(e)
    } catch {
        failUsage("plan failed: \(error.localizedDescription)")
    }
    if json {
        print(encodeJSON(plan))
    } else {
        printPlanBlock(plan)
    }
    // Exit code 2 when anything was refused: the caller (script/agent) learns "not everything went this time"
    if plan.refused.isEmpty { exit(Exit.ok.rawValue) }
    exit(Exit.refused.rawValue)

case "trash":
    var planId: String? = nil
    var json = false
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--plan":
            guard i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
                failUsage("trash: --plan needs a plan id (from a previous `diskwise plan`)")
            }
            planId = args[i + 1]; i += 2
        case "--json":
            json = true; i += 1
        default:
            // Bare paths deliberately rejected: plan-then-trash is a two-step confirmation; bypassing it bypasses the safety model
            failUsage("trash: only accepts --plan <plan_id> (raw paths are refused on purpose — run `diskwise plan` first)")
        }
    }
    guard let id = planId else { failUsage("trash: --plan <plan_id> is required") }
    let result: AgentResult
    do {
        result = try agentExecute(planId: id)
    } catch let e as AgentAPIError {
        failAgentError(e)
    } catch {
        failUsage("trash failed: \(error.localizedDescription)")
    }
    if json {
        print(encodeJSON(result))
    } else {
        printResultBlock(result)
    }
    if result.failed.isEmpty { exit(Exit.ok.rawValue) }
    exit(Exit.refused.rawValue)

case "undo":
    var opId: String? = nil
    var json = false
    for a in args.dropFirst() {
        switch a {
        case "--json": json = true
        case "--plan": failUsage("undo takes an operation id (from history), not a plan id")
        default:
            if a.hasPrefix("-") { failUsage("undo: unknown flag \(a)") }
            opId = a
        }
    }
    let statuses: [AgentUndoStatus]
    do {
        statuses = try agentUndo(operationId: opId)
    } catch let e as AgentAPIError {
        failAgentError(e)
    } catch {
        failUsage("undo failed: \(error.localizedDescription)")
    }
    if json {
        print(encodeJSON(statuses))
    } else {
        printUndoBlock(statuses)
    }
    // gone_from_trash is not a failure (the item leaving the Trash was the user's own action); only failed yields 2
    if statuses.contains(where: { $0.status == "failed" }) { exit(Exit.refused.rawValue) }
    exit(Exit.ok.rawValue)

case "history":
    var limit = 20
    var json = false
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--limit":
            guard i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else {
                failUsage("history: --limit needs a positive number")
            }
            limit = n; i += 2
        case "--json":
            json = true; i += 1
        default:
            failUsage("history: unknown argument \(args[i])")
        }
    }
    let ops = agentHistory(limit: limit)
    if json {
        print(encodeJSON(ops))
    } else {
        printHistoryBlock(ops)
    }
    exit(Exit.ok.rawValue)

case "mcp":
    await MCPServer.run()

default:
    failUsage("unknown command \(args.first!)")
}
