# DiskWise for AI agents: CLI and MCP safety model

`diskwise` is the command-line form of DiskWise (bundled with the direct-download app; not in the sandboxed App Store build).
It exposes the app's cleanup abilities to terminals and AI agents (Claude Code, Cursor, Codex...),
with the same safety model, and **stricter** for agents:

> **It cannot `rm -rf`.** The only deletion path is moving items to the Trash, and every operation can be undone as a whole.

## Safety model

**Four verdict tiers** (same knowledge base as the app, `safety_db.json`, currently 80 entries):

| tier | Meaning | Agent may act? | With `--i-am-human`? |
|---|---|---|---|
| `safe` | No impact; rebuilt automatically (DerivedData, pip cache...) | ✅ | ✅ |
| `redo` | Known; must be re-downloaded after deletion (model weights, dependency repos...) | ✅ (user must approve the plan) | ✅ |
| `risky` | Gone for good once deleted (simulator devices, chat history...) | ❌ | ❌ (nobody) |
| `unknown` | Not in the knowledge base (no match != safe) | ❌ | ✅ |

**Three extra gates for agents** (not applied to humans using the app):

1. **Only the known location itself**: a path named by an agent must be a knowledge-base entry (or a wildcard instance of one).
   User-created subfolders inside a cache directory are rejected (`not_a_known_location`). A human may touch them
   (same freedom as the app's drill-down page); an agent may not.
2. **Two-step confirmation**: `plan` writes a plan file (**valid 10 minutes**, at most **200 items / 200 GB**);
   `trash` accepts only a plan_id, never raw paths. At execution, **each item re-runs the verdict pipeline and the inode is checked**:
   a path replaced by a symlink (`symlink`) or with contents swapped in place (`changed_since_plan`) after planning
   is blocked on the spot.
3. **Persistent audit trail**: each execution appends one line to `operations.jsonl` (append-only, never rewritten);
   `undo` restores a whole operation from the log. Items already emptied from the Trash report `gone_from_trash` without affecting the rest.

Verdict pipeline (shared by all entry points, fixed order): path expansion -> protected paths (`~/Documents`, `/`...)
-> scope (nothing outside home, `/Applications`, `/tmp`, `/var/tmp`) -> lstat (missing /
symlink rejected) -> knowledge-base verdict -> allow. `--i-am-human` **does not exist** in MCP mode.

## Commands

```
diskwise scan [--category all|dev|ai_models|apps] [--min 100MB] [--json]
diskwise explain <path> [--json]
diskwise plan <path>... [--i-am-human] [--json]
diskwise trash --plan <plan_id> [--json]     # plan_id only
diskwise undo [<operation_id>] [--json]
diskwise history [--limit 20] [--json]
diskwise mcp                                 # stdio MCP server
diskwise --version
```

- stdout carries only results (agents parse it); logs go to stderr. `--json` keys are snake_case, times ISO8601.
- Exit codes: `0` success · `1` bad arguments · `2` some items rejected (partial success is also 2; details in output) · `3` plan expired or missing.
- Size arguments are decimal (`500MB`, `2GB`, plain bytes), same as the app.

`scan` merges two sources: **knowledge-base entries** (human-written safety knowledge) plus **signature discovery** (engine-managed caches recognized by
layout: HuggingFace-layout model repos, loose model weights, updater download caches, whether in home or in some
project's var, including a relocated `HF_HOME`). Each item has a `source` field (`knowledge_base` |
`signature`). Signature items are capped at tier redo and `agent_may_trash` is always false; the agent contract is unchanged,
and `--i-am-human` can remove them.

State directory: `~/Library/Application Support/DiskWise/agent/` (`plans/` plan files,
`operations.jsonl` operation log). Each operation line records the **source client**: for MCP, the `clientInfo.name`
self-reported in initialize (e.g. claude-code); for the terminal, `diskwise-cli` by default. Older log lines without the field
are treated as unknown source. The CLI assumes a single writer: only one write operation at a time.

## Connecting your AI tool

`diskwise mcp` is a standard stdio MCP server; any client that can attach a **local stdio server** works.
Only two things are constant: the binary's **absolute path** and the argument **`mcp`**; the config dialect varies. So the sections below are per client;
don't paste one client's syntax into another. Paths assume the default install location; if installed elsewhere, replace the whole path.

Clients not listed are also supported: the local stdio transport follows the MCP standard, and the server side has been tested
message by message (`initialize` / `tools/list` / `tools/call`, newline-delimited JSON). So **connection failures are treated as client-side
issues**. Issues and PRs are welcome; include the client name and version, the exact config you wrote, and the output from running
`"<path>" mcp` directly.

| Client | Where | Tested locally (2026-10-10) |
|---|---|---|
| Claude Code | One terminal command | ✔ Connected |
| Qoder | One CLI command, or paste JSON in IDE settings | ✓ Connected |
| OpenCode | `opencode.json` | ✓ connected |
| Codex CLI | One terminal command, or `~/.codex/config.toml` | Registered (list does not handshake) |
| Cursor | `~/.cursor/mcp.json` | Not installed; per official docs |
| Zed | `context_servers` in `~/.config/zed/settings.json` | Not installed; per official docs |
| ZCode | `mcp.servers` in `~/.zcode/cli/config.json` | Not installed; per official docs |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | Not installed; per official docs |

### Claude Code

```sh
claude mcp add diskwise -- "/Applications/DiskWise.app/Contents/MacOS/diskwise" mcp
```

When added at project scope (`--scope project`), you must also run `claude` once in that directory to approve it before the server actually starts.
In testing, right after add in a new directory, `claude mcp list` reports "⏸ Pending approval".

### Codex CLI

```sh
codex mcp add diskwise -- "/Applications/DiskWise.app/Contents/MacOS/diskwise" mcp
```

Or edit `~/.codex/config.toml` directly:

```toml
[mcp_servers.diskwise]
command = "/Applications/DiskWise.app/Contents/MacOS/diskwise"
args = ["mcp"]
```

`codex mcp list` reports registration only and does not handshake, so it can't tell you whether it connects; run a session to check.

### Qoder

CLI (applies to the current directory by default; `--scope project` writes to the project's `.mcp.json`):

```sh
qoder mcp add diskwise -- "/Applications/DiskWise.app/Contents/MacOS/diskwise" mcp
```

Or in the IDE: `⌘⇧,` -> Qoder Settings -> MCP -> My Servers -> + Add, and paste:

```json
{
  "mcpServers": {
    "diskwise": {
      "command": "/Applications/DiskWise.app/Contents/MacOS/diskwise",
      "args": ["mcp"]
    }
  }
}
```

### Cursor

`~/.cursor/mcp.json` (or `.cursor/mcp.json` in the project):

```json
{
  "mcpServers": {
    "diskwise": {
      "type": "stdio",
      "command": "/Applications/DiskWise.app/Contents/MacOS/diskwise",
      "args": ["mcp"]
    }
  }
}
```

The official field table requires `type`, though its own example snippet omits it; writing it out as above is safe. `command` must be
a full path or a program on the system PATH.

### OpenCode

`~/.config/opencode/opencode.json` (or `opencode.json` at the project root):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "diskwise": {
      "type": "local",
      "command": ["/Applications/DiskWise.app/Contents/MacOS/diskwise", "mcp"],
      "enabled": true
    }
  }
}
```

Three differences from other clients, and copying their syntax won't start: `type` must be `"local"`, `command` is an **array**
(program and arguments in one bracket), and the environment key is `environment`, not `env`.

### Zed

`~/.config/zed/settings.json`:

```json
{
  "context_servers": {
    "diskwise": {
      "command": "/Applications/DiskWise.app/Contents/MacOS/diskwise",
      "args": ["mcp"]
    }
  }
}
```

It is `context_servers`, not `agent_servers`; the latter is for external coding agents, and MCP servers placed there won't work.

### ZCode

`~/.zcode/cli/config.json` (project level is `<project root>/.zcode/config.json`; the directory depths differ):

```json
{
  "mcp": {
    "servers": {
      "diskwise": {
        "command": "/Applications/DiskWise.app/Contents/MacOS/diskwise",
        "args": ["mcp"]
      }
    }
  }
}
```

Its settings can also import existing Claude Code / Codex / OpenCode configs. Note that by default it ignores the system
`HTTP_PROXY`; keep that in mind on machines behind a proxy.

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "diskwise": {
      "command": "/Applications/DiskWise.app/Contents/MacOS/diskwise",
      "args": ["mcp"]
    }
  }
}
```

After editing, **fully quit** and reopen (not just close the window). Newer versions prefer `.mcpb` extension bundles; hand-written config is still supported.

Homebrew users: the cask provides the `diskwise` command (once a release adds the `binary` line);
all paths above can then be replaced with `/opt/homebrew/bin/diskwise`.

## MCP tools

| Tool | Description |
|---|---|
| `scan_disk(category?, min_bytes?)` | Read-only: scan known locations and measure sizes |
| `explain_path(path)` | Read-only: full profile of a path and rejection reasons |
| `plan_cleanup(paths[])` | Read-only: build a plan. **The description requires the model to show the summary to the user and get consent before executing** |
| `execute_cleanup(plan_id)` | Move to Trash per plan (undoable, `destructiveHint: false`) |
| `undo_cleanup(operation_id?)` | Restore a whole operation |
| `cleanup_history(limit?)` | Read-only: recent operations |
| `diag_coverage()` | Read-only: targeted discovery of diagnostic dumps: hit list + observed locations that can't be touched (reason codes share the rejection vocabulary) |
| `diag_velocity()` | Read-only: per crash-dump entry growth "this run vs previous"; `tier: fast` (burst) / `growth` (long-term accumulation) |
| `diag_probe(path)` | Read-only: content attribution of a crash-dump directory (reads the first 64 KB of sample files; fingerprints always redacted). Refused when the local "content probe" toggle is off |

Business errors (rejected, expired, over limit) return as results with `isError: true` plus a next-step hint
(e.g. `plan_expired` -> run `plan_cleanup` again).

Scope of the three diag tools: **read-only, no deletion or pruning**. One-off cleanup still goes through the two-step `plan_cleanup` / `execute_cleanup`
chain; "prune by retention policy" is a manual action in the app and is not exposed to agents.
An agent can report growth; a human does the acting.

## A real conversation (Claude Code + diskwise MCP)

> **Me**: See what can be cleaned on my Mac
>
> **assistant** (calls `scan_disk`):
> Scan results (category=dev, min_bytes=100000000):
> - 30 locations total; the agent may act on 23, about 57.7 GB combined;
> - Top three: OrbStack VM disk 19.7 GB (`may_lose_data`, off limits),
>   Ollama models 17.7 GB (`redo`, removable and undoable), iOS simulator runtimes 16.6 GB
>   (system area, `outside_allowed`).
> Which ones should I clean?
>
> **Me**: Clear the Ollama and oMLX models
>
> **assistant** (calls `plan_cleanup`):
> Plan ready: two items, 31.4 GB total, going to the Trash (undoable anytime):
> `~/.ollama/models` 17.7 GB · `~/.omlx/models` 13.7 GB. Proceed?
>
> **Me**: Yes
>
> **assistant** (calls `execute_cleanup`):
> Moved to Trash, 31.4 GB freed. If you change your mind, say so and I'll restore them with undo_cleanup.

## Maintenance notes

- Direct-download packaging: `build_app/build.sh` builds the CLI into `Contents/MacOS/diskwise`,
  **signs the nested binary first, then the whole bundle** (in both signing branches), and smoke-tests
  `diskwise --version` after signing; the App Store branch does not copy the CLI.
- On the next release the cask needs one line: `binary "#{appdir}/DiskWise.app/Contents/MacOS/diskwise"`
  (update version / sha256 together; not added yet because the last published DMG lacks this binary).
- Vocabulary: agent-facing explanation fields in CLI/MCP are looked up in `en.lproj/Localizable.strings`,
  falling back to the source text if missing; the `DISKWISE_RESOURCES` env var overrides the resource directory (for tests).
