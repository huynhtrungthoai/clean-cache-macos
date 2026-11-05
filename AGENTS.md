# CleanPilot — instructions for Codex (and other coding agents)

Personal macOS disk-cleaner project of **huynhtrungthoai**. Two AI tools work in parallel:
**Codex builds UI, Claude builds features/core logic** (see `CLAUDE.md`). The plan is
`docs/enhance-feat.md`; the interface between the two sides is its **§11 Contract**.

## Ownership (do not edit outside it)

Codex owns:
- `Sources/DiskCleaner/Views/**` (SwiftUI views only)
- `Sources/DiskCleaner/Theme/**`, `Sources/DiskCleaner/Resources/skins.json`
- Navigation in `Sources/DiskCleaner/DiskCleanerApp.swift`: `AppPanel`, `ContentView`, sidebar.
  `ScanStore` / `AppStore` and their types belong to Claude.

Codex does NOT edit: `Sources/DiskCleanerCore/**`, `Sources/DiskCleaner/Models/**`,
`Sources/SelfTest/**`, `Sources/DiskWiseCLI/**`, `build_app/**`, `Package.swift`, `docs/TODO.md`,
`CLAUDE.md`, this file. If the UI needs data or an action that does not exist yet, use the API
listed in the Contract; if it is missing, write a request in the PR / `docs/enhance-feat.md` §11
"Requests" instead of adding logic in a view.

Until contract **C0** is merged, ObservableObject model classes still live inside view files
(`CachesModel` in CachesView.swift, `DupModel`, `UninstallModel`, …). Do not change those classes;
edit only the `View` structs in those files.

Shared, with rules:
- `Sources/DiskCleaner/Resources/*.lproj/Localizable.strings`: whoever adds `L("…")` adds the key
  to **all 9 tables** (en, vi, ja, ko, de, es, fr, ru, pt-BR), **appended at the end of the file**.
  Keys are English source text. No Chinese anywhere.

## Git workflow

- Work only in your own worktree/branch, e.g. `../CleanPilot-worktrees/codex-ui-p1` on
  `feat/codex-ui-p1` (`git worktree add ../CleanPilot-worktrees/codex-ui-p1 -b feat/codex-ui-p1 origin/main`).
- Never commit or push to `main`, never commit files you did not change, never force-push.
  The owner merges branches to `main`.
- `git fetch && git rebase origin/main` before starting and before opening a PR.

## UI rules

- Follow `docs/enhance-feat.md` §4 (navigation, screen layout, visual system) and §6 (states/copy).
- Destructive actions: every trash action keeps a confirm step that names what will be moved;
  "select all" only selects rows the model marks bulk-selectable; never empty the Trash from a
  one-click button.
- Never call `trashItem`, `FileManager`, `Process` or AppleScript from a view; call model/store APIs.
- Respect Reduce Motion, keyboard navigation, VoiceOver labels, light/dark, window min 1000×560.

## Verify before handing over

```sh
swift build
swift run SelfTest                 # must print ALL PASS
swift build_app/l10n_tool.swift check .
```
