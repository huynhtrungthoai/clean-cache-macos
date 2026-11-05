# CleanPilot — instructions for Claude

Personal macOS disk-cleaner project of **huynhtrungthoai**. Two AI tools work in parallel:
**Claude builds features/core logic, Codex builds UI** (see `AGENTS.md`). The plan is
`docs/enhance-feat.md`; the interface between the two sides is its **§11 Contract**.

## Ownership (do not edit outside it)

Claude owns:
- `Sources/DiskCleanerCore/**`
- `Sources/DiskCleaner/Models/**` (ObservableObject models, after contract C0 moves them there)
- Store/state parts of `Sources/DiskCleaner/DiskCleanerApp.swift`: `ScanStore`, `AppStore` and their
  types. Navigation (`AppPanel`, `ContentView`, sidebar) belongs to Codex.
- `Sources/SelfTest/**`, `Sources/DiskWiseCLI/**`, `build_app/**`, `Package.swift`
- `docs/TODO.md`, `docs/enhance-feat.md` §11 Contract (proposes; the owner approves changes)

Codex owns `Sources/DiskCleaner/Views/**`, `Sources/DiskCleaner/Theme/**`,
`Sources/DiskCleaner/Resources/skins.json`. Claude does not edit those; if a feature needs UI,
expose it through the contract and leave a note in the PR.

Shared, with rules:
- `Sources/DiskCleaner/Resources/*.lproj/Localizable.strings`: whoever adds `L("…")` adds the key
  to **all 9 tables** (en, vi, ja, ko, de, es, fr, ru, pt-BR), **appended at the end of the file**.
  Keys are English source text. No Chinese anywhere.
- `docs/enhance-feat.md` outside §11: edit only the checklist lines of your own items.

## Git workflow

- Work only in the worktree/branch for the task, e.g. `../CleanPilot-worktrees/claude-p0` on
  `feat/claude-p0`. Never commit to `main` directly, never commit another tool's uncommitted work,
  never force-push.
- One logical change per commit. The owner merges to `main`.
- Before starting work: `git fetch && git rebase origin/main` (after C0 is merged, Codex rebases on it).

## Safety rules (non-negotiable)

- Every deletion goes through `trashItem` → `deletionGate` (Models.swift). Never call
  `FileManager.removeItem` on user data, never add a permanent-delete path.
- Do not widen `isDeletable`, `protectedPaths`, `sensitiveTreeRelRoots` or the agent refusal rules
  without the owner's explicit approval.
- `DISKWISE_*` env hooks only work in debug / `DEV_HOOKS=1` builds (`devHooksEnabled`); keep it so.
- Signing: only the personal account (`SIGN_ACCOUNT_ID=HN2G8HJ96Q`, huynhtrungthoai@gmail.com).
  Never use any other certificate in the keychain.
- No network access from the app.

## Verify before handing over

```sh
swift build
swift run SelfTest                 # must print ALL PASS
swift build_app/l10n_tool.swift check .
bash build_app/build.sh            # full gate: l10n, release SelfTest, signing, DMG
```

Add SelfTest cases for every core change (protected paths, parent/child overlap, file changed
after scan, missing kept copy, tampered history, restore conflicts, partial failure).
