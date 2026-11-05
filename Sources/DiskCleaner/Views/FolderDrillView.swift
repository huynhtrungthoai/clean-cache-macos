import SwiftUI
import AppKit
import DiskCleanerCore

// ── Folder detail (level-by-level drill-down) ──────────────────────────────────────────
//
// The "Large files" page only gives a TOP list, mostly undeletable system items; the Overview ledger expands only one level.
// So "what's actually inside that Desktop folder" had nowhere to go. This page fills that gap:
// enter any folder, each level lists **subfolders and files mixed**, click a folder to go deeper.
//
// Two deliberate boundaries:
//   1. Deletability always goes through `isDeletable` (same as Large files), no separate rules. Places this tool won't touch are still listed,
//      but **can be drilled into**, which is exactly why this page exists.
//   2. Measure one level per entry (`dirLevel`), no upfront recursion of the whole tree: ~/Library has 40+ top-level dirs,
//      and recursing upfront would decide for the user "which branch is worth looking at".
//
// This level's numbers pass through `addableHumanColumn` as a whole column, so "listed rows + the tail line"
// exactly equal this level's total; two ledgers on one screen is the shape of every past collapse of this app.

@MainActor
final class FolderDrillModel: ObservableObject {
    /// Path of the current level.
    @Published private(set) var path: String = ""
    /// Breadcrumb cells for this path, all clickable. The last one is `path`.
    ///
    /// **Excludes the leftmost "Overview" cell**: the view always places that first (rules in `crumbChain`).
    @Published private(set) var crumbs: [String] = []
    @Published private(set) var level: DirLevel? = nil
    @Published private(set) var busy = false
    /// What this pass is measuring. During the "measuring" seconds, not saying where reads like "it broke".
    @Published private(set) var pendingPath: String = ""
    @Published var selected: Set<String> = []

    /// Live readout. This level is slow because it **measures each subfolder** (dozens per level, each a subtree),
    /// so it must say not just "measuring ~/Library" but also "which of those 40+ dirs we're on".
    private(set) var progress = ScanProgress()

    /// Max file rows listed. **Files only**: `/Applications`-style levels have hundreds of entries;
    /// nobody scans them all, the rest fold into the tail line. Folders are exempt: on this page
    /// a missing folder is a missing path downward, and "going down" is why it exists.
    static let fileCap = 200

    private var cache: [String: DirLevel] = [:]
    private var task: Task<Void, Never>? = nil
    /// Screenshot pipeline only (`DISKWISE_DRILL_INTO=1`): after the first level is measured, auto-drill once
    /// to capture the "breadcrumb + one level deeper" screen.
    private var autoDescended = false
    /// The auto-drill is handed to the outside. Entering a level is a navigation and must be recorded in history;
    /// calling `open` directly in the model would make Back unable to return from the captured screen, a false testimony.
    var onAutoDescend: ((String) -> Void)?

    var rows: [ChildEntry] { level?.entries ?? [] }
    var selectedEntries: [ChildEntry] { rows.filter { selected.contains($0.path) } }
    var selectedBytes: Int64 { selectedEntries.reduce(Int64(0)) { $0 + $1.size } }

    /// Whether we can go up. **Not "is there a parent dir"**: above top levels like `/Applications`, `/Library`
    /// is the Overview; disk root `/` is not a stop (reason in `drillParent`).
    /// So once any folder was entered, this button has somewhere to go; the target is computed by `drillParent`.
    var canGoUp: Bool { !path.isEmpty }

    /// Enter a folder. Clicking the same one again doesn't re-measure (cache refills directly).
    ///
    /// Which level the page shows is decided by `store.folderDrillPath`, so only the view's `start()`
    /// should call this; row clicks, breadcrumbs and "Up" all land on that field first.
    func open(_ target: String) {
        guard !target.isEmpty else { return }
        if target == path, level != nil, !busy { return }
        path = target
        rebuildCrumbs()
        selected.removeAll()
        load(target)
    }

    /// A rescan invalidates the whole cache: the disk ledger drifts, and keeping old numbers across a pass
    /// means deciding today with last time's ledger.
    func invalidate() {
        task?.cancel()
        cache = [:]
        level = nil
        if !path.isEmpty { load(path) }
    }

    /// Re-measure this level after deleting: rows and totals changed; pruning rows in place would mismatch the tail line.
    func reload() {
        cache[path] = nil
        if !path.isEmpty { load(path) }
    }

    private func load(_ target: String) {
        task?.cancel()
        if let hit = cache[target] {
            level = hit
            busy = false
            return
        }
        level = nil
        // One level per pass, readout and list reset too: the previous level's ledger on this level is a different ledger.
        progress = ScanProgress()
        busy = true
        pendingPath = target
        let limit = Self.fileCap
        let prog = progress
        task = Task { [weak self] in
            let lv = await dirLevel(URL(fileURLWithPath: target), includeFiles: true,
                                    fileLimit: limit, progress: prog)
            guard !Task.isCancelled, let self, self.path == target else { return }
            self.cache[target] = lv
            self.level = lv
            self.busy = false
            if SnapshotMode.drillAutoDescend, !self.autoDescended,
               let first = lv.entries.first(where: { $0.isDir }) {
                self.autoDescended = true
                self.onAutoDescend?(first.path)
            }
        }
    }

    /// This strip is fully defined by `crumbChain` (it lives in Core and is self-checked); here we only handle
    /// "don't show an empty strip before entering any folder". Rules are documented there: each cell is that level itself,
    /// the home folder collapses to `~`, and the leftmost "Overview" cell isn't in this array.
    private func rebuildCrumbs() {
        crumbs = path.isEmpty ? [] : crumbChain(for: path)
    }
}

struct FolderDrillView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: FolderDrillModel
    @State private var confirm = false
    @State private var err: String? = nil

    /// Deletion flight: both origin (checked rows) and destination (the CleanBar button) are collected here.
    @StateObject private var flight = TrashFlightController()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "folder", title: L("Folder details"),
                           subtitle: L("Go deeper level by level and see how much each folder and file takes up"),
                           variant: .display) {
                    // "Find large files in this tree" goes from here: Overview no longer shows two side-by-side "go down"
                    // buttons (click name to enter this level + dig into Large files); one step only: enter to see this level first,
                    // then press this to find large files. Two actions on two levels, each with a clear place.
                    ThemeButton(kind: .compact, symbol: "scope",
                                title: L("Dig in"),
                                isDisabled: model.path.isEmpty) {
                        store.deepDive(into: model.path)
                    }
                    .help(LF("Scan only %@ and list its largest files on the Large Files page", model.path))
                    // Besides breadcrumbs we need a persistent button: a dozen levels deep, "up one level" is
                    // the only action on this page you can press without first working out where you are.
                    //
                    // "Up", like breadcrumbs, is a **navigation** and must be recorded in the outer history,
                    // so the target is computed in the store (`goUpFromDrill`), not via a direct `open` here
                    // bypassing that ledger; bypassing it would make Back return to "before this page" instead of the parent folder.
                    ThemeButton(kind: .compact, symbol: "arrow.up",
                                title: L("Up one level"),
                                isDisabled: !model.canGoUp) {
                        store.goUpFromDrill()
                    }
                    .help(goUpHint)
                }
                crumbsBar
                ControlStrip {
                    if model.busy {
                        LoadingRow(text: LF("Measuring “%@”", shortLabel(model.pendingPath)),
                                   progress: model.progress)
                    } else if let lv = model.level {
                        Text(LF("This level: %@", human(lv.total)))
                        ThemeBadge(text: LF("%1$@ · %2$@",
                                            cnt(lv.dirCount, "folders"),
                                            cnt(lv.fileCount, "files")),
                                   tone: .neutral, symbol: "folder")
                    } else {
                        Text(L("Open a folder to start drilling down level by level"))
                    }
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            content

            Spacer(minLength: 0)   // clean bar pinned to the window bottom, see `CleanBar`

            CleanBar(count: model.selected.count, bytes: model.selectedBytes,
                     bytesText: human(model.selectedBytes, inRulerOf: model.level?.total ?? 0),
                     errorText: err, selection: selectAll,
                     flightTarget: true) { confirm = true }
        }
        .frame(maxWidth: .infinity)
        .flightField(flights: $flight.flights, anchors: $flight.anchors)
        .onChange(of: flight.anchors) { _ in fireSnapshotFlightIfAsked() }
        // When the page first appears `anchors` fires once (this level not yet measured), so the hook would bail early;
        // row count going from 0 to N signals "measured", added here to give the hook a second chance.
        .onChange(of: model.rows.count) { _ in fireSnapshotFlightIfAsked() }
        .onAppear {
            // The screenshot pipeline's auto-drill also goes outside: only the same history recognizes it.
            model.onAutoDescend = { store.drill(into: $0) }
            start()
        }
        .onChange(of: store.folderDrillPath) { _ in start() }
        // On Back the target may **happen to equal** the origin (the middle segment was trimmed);
        // an unchanged value won't fire the observer above and the UI would stay on the old subfolder, so reconcile every step.
        .onChange(of: store.navPulse) { _ in start() }
        // Overview pressed "Rescan": every level visited here is now last pass's ledger; invalidate all.
        // Without this: going back still shows old numbers, and this tool's whole reason to exist is that numbers are true.
        // Conversely, **except for this**, visited levels stay cached; that's caching, not a missed scan.
        .onChange(of: store.rescanPulse) { _ in model.invalidate() }
        .confirmTrash(isPresented: $confirm,
                      text: LF("Move %1$@ (%2$@) to the Trash.",
                               cnt(model.selectedEntries.count, "items"),
                               human(model.selectedBytes, inRulerOf: model.level?.total ?? 0))
                          + confirmNames(model.selectedEntries)) {
            doClean()
        }
    }

    // MARK: Body

    /// Help text for the "Up" button. A top-level dir's parent is the Overview, not a folder,
    /// so the help must say Overview; otherwise hovering says one thing and pressing goes elsewhere.
    /// Uses the existing "Back to "%@"" string (also used by the global back button), no new copy.
    private var goUpHint: String {
        drillParent(of: model.path) == nil
            ? LF("Back to “%@”", L("Overview"))
            : L("Go up to the parent folder")
    }

    @ViewBuilder private var content: some View {
        if model.path.isEmpty {
            EmptyState(symbol: "folder", title: L("No folder selected yet"),
                       hint: L("Go back to Overview and click a folder's name to enter; or use “Open containing folder” on the Large Files page."))
                .frame(maxHeight: .infinity)
        } else if model.busy && model.rows.isEmpty {
            ScanChecklist(progress: model.progress)
        } else if !model.busy && model.rows.isEmpty {
            EmptyState(symbol: "folder", title: L("Nothing readable at this level"),
                       hint: L("It may be empty, or it may need Full Disk Access to read."))
                .frame(maxHeight: .infinity)
        } else {
            PageLedger(tiers: tiers, rows: model.rows.count, note: nil)
            List(model.rows) { r in
                ItemRow(selected: selection(r),
                        icon: .path(r.url),
                        name: r.name,
                        sub: subLine(r),
                        hint: verdictHint(for: r.path),
                        sizeText: sizeCell(r),
                        fraction: Double(r.size) / Double(maxSize),
                        badge: isReclaimableWhole(r.url) ? nil : ItemBadge(text: L("Not ours to touch"), tone: .neutral),
                        badge2: rowBadge(r),
                        selectable: isReclaimableWhole(r.url),
                        lit: isReclaimableWhole(r.url),
                        lockedHint: isReclaimableWhole(r.url) ? nil : outsideScopeHint,
                        onOpen: r.isDir ? { store.drill(into: r.path) } : nil,
                        onReveal: { reveal(r.path) },
                        // A file row's path is only visible when expanded, and batch screenshots can't click to expand,
                        // so the view sets it itself; it changes the same `expanded`, not a separately drawn expanded state.
                        preopen: SnapshotMode.expandsRow(r.name)) {
                    PathLine(path: r.path)
                }
                // Deleted rows fade first so chips fly from them; row removal is left to `reload` after the flight.
                .opacity(flight.leaving.contains(r.path) ? 0.30 : 1)
                // Only checked rows report origins: this level may have hundreds of rows; GeometryReader on all is wasted measuring.
                .heroAnchorGlobal(TrashFlightController.rowAnchor(r.path),
                                  enabled: model.selected.contains(r.path))
            }
            .ledgerCard()
            ListNote(text: tailNote)
            if let vn = verdictNote {
                ListNote(text: vn)
            }
        }
    }

    // MARK: Verdicts (knowledge base)

    /// This row's verdict. No match means no badge; **don't say "unknown" on the row**:
    /// ninety of ninety-odd rows would carry that word, making it background noise rather than information,
    /// and the real message ("not in this knowledge base") is per-level anyway, see `verdictNote`.
    ///
    /// The badge itself is `SharedViews.verdictBadge`, shared with Caches and Overview;
    /// this page only decides "which rows don't get one".
    private func rowBadge(_ r: ChildEntry) -> ItemBadge? {
        verdictBadge(VerdictIndex.shared.verdict(for: r.path).tier)
    }

    /// This level's verdict tally: of the places the knowledge base recognizes, how many **name a regeneration path**.
    ///
    /// This is this page's positive answer to "what's safe to delete"; the rest not in the knowledge base must be stated too,
    /// and clearly as "not listed != deletable"; reporting only the recognized ones would launder unknowns as safe.
    ///
    /// "Re-download after deleting" and "deleting loses data" are counted and stated separately. They used to share one "look first" line,
    /// so 40 GB of model weights and 3 simulators' data got the same sentence at the page bottom, and the user couldn't decide
    /// which to touch first; helping make that decision is this page's only job.
    private var verdictNote: String? {
        guard !model.rows.isEmpty else { return nil }
        var safe = 0, redo = 0, risky = 0, unknown = 0
        var safeBytes = Int64(0)
        for r in model.rows {
            switch VerdictIndex.shared.verdict(for: r.path).tier {
            case .safe:    safe += 1; safeBytes += r.size
            case .redo:    redo += 1
            case .risky:   risky += 1
            case .unknown: unknown += 1
            }
        }
        var parts: [String] = []
        if safe > 0 {
            parts.append(LF("%1$@ with no impact, %2$@ in total",
                            cnt(safe, "items"), human(safeBytes, inRulerOf: model.level?.total ?? 0)))
        }
        if redo > 0 {
            parts.append(LF("%1$@ need re-downloading", cnt(redo, "items")))
        }
        if risky > 0 {
            parts.append(LF("%1$@ would lose data if deleted", cnt(risky, "items")))
        }
        if unknown > 0 {
            parts.append(LF("Another %1$@ aren't in the knowledge base: not listed doesn't mean safe to delete, so check the path before ticking it",
                            cnt(unknown, "items")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + "。"
    }

    private var crumbsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                crumb(L("Overview"), active: false) { store.resetNav(to: .overview) }
                ForEach(Array(model.crumbs.enumerated()), id: \.element) { i, p in
                    Text("›")
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.inkTertiary)
                    crumb(shortLabel(p), active: i == model.crumbs.count - 1) {
                        store.drill(into: p)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func crumb(_ text: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text)
                .font(theme.bodyFont(.caption).weight(active ? .semibold : .regular))
                .foregroundStyle(active ? theme.palette.ink : theme.palette.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.controlShape().fill(active ? theme.palette.surfaceAlt : Color.clear))
                .contentShape(theme.controlShape())
        }
        .buttonStyle(.plain)
        .disabled(active)
        .help(text)
    }

    // MARK: Numbers

    /// This level's ledger: split into "this tool can clean / won't touch", same basis as Large files.
    private var tiers: [LedgerTier] {
        let sp = listedSplitOf(model.rows, bytes: { $0.size }, lit: { isReclaimableWhole($0.url) })
        return [LedgerTier(label: L("Ours to clean"), bytes: sp.reclaimable, tone: .hot),
                LedgerTier(label: L("Not ours to touch"), bytes: sp.viewOnly, tone: .cold)]
    }

    private var maxSize: Int64 { max(1, model.rows.map(\.size).max() ?? 1) }

    /// The whole column plus tail line goes through unified rounding, pinned to this level's total: printed rows
    /// plus the tail line exactly equal the header's "measured at this level".
    private var shown: [String: String] {
        guard let lv = model.level else { return [:] }
        let rest = lv.unlistedBytes
        let texts = addableHumanColumn(model.rows.map(\.size) + [rest], total: lv.total)
        var out: [String: String] = [:]
        for (r, s) in zip(model.rows, texts) { out[r.id] = s }
        return out
    }

    /// This row's number. Rows **entirely unreadable** get a dash, not `0 B`: their 0 means "not measured",
    /// not "nothing"; writing 0 would vouch that the system's dozens of GB are "empty here".
    /// Rows only **partly** unreadable (a protected chunk in the subtree, yet dozens of GB measured outside) still show a number;
    /// the gap is explained by the subtitle: showing `Application Support` as a dash would just trade one error
    /// for another.
    private func sizeCell(_ r: ChildEntry) -> String {
        if r.unreadable && r.size == 0 { return "—" }
        return shown[r.id] ?? human(r.size)
    }

    /// Tail line: entries not listed row by row. **Can't be omitted**: otherwise users add up the column against the header,
    /// fail to match, and conclude the numbers are made up.
    private var tailNote: String {
        guard let lv = model.level else { return "" }
        var parts = [LF("This level: %@", human(lv.total))]
        if lv.unlistedCount > 0 {
            parts.append(LF("%1$@ more (%2$@) not listed one by one",
                            cnt(lv.unlistedCount, "items"), human(lv.unlistedBytes)))
        }
        // Unreadable chunks never entered total; without a note here the header number is an undercount,
        // and in this app undercounting is more dangerous than overcounting: it says "nothing to see here".
        // Count two kinds separately: "not measurable at all" and "partly measured" affect the total differently.
        let stuck = model.rows.filter { $0.unreadable && $0.size == 0 }.count
        if stuck > 0 {
            parts.append(LF("%1$@ can't be read and aren't in this level's total", cnt(stuck, "folders")))
        }
        let partial = model.rows.filter { $0.unreadable && $0.size > 0 }.count
        if partial > 0 {
            parts.append(LF("%1$@ measured only in part", cnt(partial, "folders")))
        }
        return parts.joined(separator: " · ") + "。"
    }

    /// Row subtitle: folders show "N files + last modified", files show "last modified".
    /// With bytes alone, 10 GB of scattered cache bits looks the same as a single 10 GB image,
    /// yet the former can be judged item by item and the latter can't.
    private func subLine(_ r: ChildEntry) -> String? {
        if r.unreadable && r.size == 0 { return L("Can't be read, so it's not in the totals") }
        var line: String?
        if r.isDir {
            line = contentsLine(r.files, r.newest)
        } else if let n = r.newest {
            line = LF("Last changed %@", shortDate(n))
        }
        if r.unreadable {
            line = [line, L("has unreadable parts")].compactMap { $0 }.joined(separator: " · ")
        }
        return line
    }

    private func selection(_ r: ChildEntry) -> Binding<Bool> {
        Binding(get: { model.selected.contains(r.path) },
                set: { on in
                    if on { model.selected.insert(r.path) } else { model.selected.remove(r.path) }
                })
    }

    /// "Select all" only affects checkable rows: untouchable rows can't be deleted, so cleaning after select-all would just yield an error screen.
    /// P0-7: select-all also skips dotfiles and direct children of ~/Library
    /// (`isBulkSelectable`) — those can still be ticked one by one, never in one sweep.
    private var selectAll: SelectAll? {
        let open = model.rows.filter { isBulkSelectable($0.url) }
        guard !open.isEmpty else { return nil }
        return SelectAll(allSelected: open.allSatisfy { model.selected.contains($0.path) },
                         unselectable: model.rows.count - open.count) { on in
            if on {
                model.selected = Set(open.map(\.path))
            } else {
                model.selected.removeAll()
            }
        }
    }

    /// Names of what is about to be trashed, shown in the confirm alert so a single
    /// generic "N items" never hides `.ssh` or `Application Support` among them.
    private func confirmNames(_ entries: [ChildEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let shown = entries.prefix(10).map { $0.name }
        let more = entries.count > shown.count ? "\n…(+\(entries.count - shown.count))" : ""
        return "\n\n" + shown.joined(separator: "\n") + more + "\n\n"
    }

    // MARK: Actions

    private func start() {
        guard let p = store.folderDrillPath else { return }
        // If this exact level is already being measured, don't interrupt: `open` cancels the running task and restarts,
        // and the two onChange handlers above may each fire on the same level.
        if p == model.path && model.busy { return }
        model.open(p)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func doClean() {
        err = nil
        let targets = model.selectedEntries
        let rows = targets.map { (key: $0.path, bytes: $0.size) }
        // Grab origin and destination **before** clearing the selection: unchecked rows stop reporting anchors, and a disabled button moves the target.
        // No flight under "Reduce motion" or snapshot mode: appearing from nowhere and vanishing is harder to explain, and results are shown in full anyway.
        // Removing rows here requires rescanning this level, not immediate, hence `fade`: fade first, remove after chips land.
        let fly = flight.launch(rows: rows,
                                animate: TrashFlightController.canAnimate(reduceMotion: reduceMotion),
                                fade: true)
        model.selected.removeAll()

        var ok = 0
        var errs: [String] = []
        for r in targets {
            do {
                let t = try trashItem(r.url)
                store.record(TrashRecord(original: r.url, inTrash: t, size: r.size, displayName: r.name))
                ok += 1
            } catch { errs.append(failLine(r.name, error)) }
        }

        if !errs.isEmpty { err = errList(errs) }
        store.notice = trashedNotice(ok, "items", failed: errs.count)

        // Fade rows, then reload after chips finish flying; otherwise chips are mid-air while rows are gone, wasting the trip.
        let gone = Set(targets.map(\.path))
        DispatchQueue.main.asyncAfter(deadline: .now() + TrashFlightController.settleDelay(fly)) {
            [weak model, weak flight] in
            model?.reload()
            flight?.settle(gone)
        }
    }

    /// Screenshot hook: with `DISKWISE_FLIGHT=<0~1>`, pin this page's flight too and capture it.
    ///
    /// Candidate rows are only those this tool can clean (the hook writes no real ledger, but origins must be rows that would really fly);
    /// how they get checked and chips fired is in `TrashFlightController.fireSnapshotIfAsked`.
    private func fireSnapshotFlightIfAsked() {
        guard let lv = model.level, !model.busy, !lv.entries.isEmpty else { return }
        let open = Array(model.rows.filter { isReclaimableWhole($0.url) }.prefix(2))
        guard let first = open.first else { return }
        flight.fireSnapshotIfAsked(candidates: open.map { (key: $0.path, bytes: $0.size) },
                                   selected: model.selected.contains(first.path)) {
            model.selected = Set(open.map(\.path))
        }
    }
}

/// The short name in breadcrumbs/status line: home folder shortens to `~`, others use the last component.
/// **Disk root not special-cased**: `/` is no longer a breadcrumb cell; it only appears in the "measuring" line,
/// where the last component is `/` anyway.
private func shortLabel(_ path: String) -> String {
    if path.isEmpty { return "" }
    if path == homePath() { return "~" }
    let last = (path as NSString).lastPathComponent
    return last.isEmpty ? path : last
}
