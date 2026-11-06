import SwiftUI
import DiskCleanerCore

struct DupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: DupModel
    @State private var review: TrashReviewPlan?
    @State private var envList = false

    var selectedBytes: Int64 {
        var sizeByPath: [String: Int64] = [:]
        for g in model.groups {
            for u in g.files { sizeByPath[u.path] = g.size }
        }
        return model.selection.reduce(0) { $0 + (sizeByPath[$1] ?? 0) }
    }

    private var maxWaste: Int64 { max(1, model.groups.map(\.waste).max() ?? 1) }

    private var shown: [UUID: String] {
        sizeColumn(model.groups.map { (key: $0.id, bytes: $0.waste) })
    }

    private var tiers: [LedgerTier] {
        [LedgerTier(label: L("Ours to clean"), bytes: model.waste, tone: .hot)]
    }

    private var ledgerNote: String? { L("The newest copy in each group is listed first inside it, locked — that row can't be ticked.") }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "square.on.square", title: L("Duplicates"),
                           subtitle: L("The newest copy in each group is always kept"),
                           variant: .display, scope: model.scope.uiName)
                ControlStrip {
                    if model.scanning {
                        LoadingRow(text: model.phase.isEmpty ? L("Comparing…") : model.phase,
                                       progress: model.progress)
                    } else {
                        Text(LF("Found %1$@, about %2$@ recoverable",
                                cnt(model.groups.count, "duplicate groups"), human(model.waste)))
                    }
                    ThemeBadge(text: LF("Scope: %@", model.scope.uiName),
                               tone: .neutral, symbol: "scope")
                    if !model.envGroups.isEmpty {
                        EnvCopiesClause(count: model.envGroups.count) { envList = true }
                    }
                } trailing: {
                    ThemeStepper(label: "≥", unit: "MB", value: $model.minMB,
                                 range: 5...500, step: 5) { model.scan(scope: store.scope) }
                    ScanControl(scanning: model.scanning,
                                rescan: { model.scan(scope: store.scope) }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.scan(scope: store.scope) })

            if model.scanning && model.groups.isEmpty {
                ScanChecklist(progress: model.progress, scope: model.scope.uiName)
            } else if !model.scanning && model.groups.isEmpty {
                EmptyState(symbol: "checklist", title: L("No matching items in the scanned scope"),
                           hint: LF("Everything above %1$@ has been checked; a lower threshold finds more, but runs slower",
                                    "\(model.minMB) MB"))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.groups.count), detail: human(model.waste), symbol: "square.on.square"),
                    .init(title: L("Selected"), value: human(selectedBytes), detail: LF("%d items selected", model.selectedCount), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
                if let note = ledgerNote { ListNote(text: note) }
                List(model.groups) { g in
                    dupRow(g)
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: model.selectedCount, bytes: human(selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)

        .onAppear { if !model.started { model.scan(scope: store.scope) } }

        .onChange(of: store.envListPulse) { _ in envList = !model.envGroups.isEmpty }
        .sheet(isPresented: $envList) {
            EnvCopiesSheet(groups: model.envGroups, bytes: model.envBytes)
                .themed(theme)
        }
        .sheet(item: $review) { review in
            ConfirmedTrashSheet(plan: review.items, currentPlan: { model.trashPlan() },
                                perform: { await model.trash(using: store) })
                .themed(theme)
        }
    }

    ///

    private func groupSelected(_ g: DupGroup) -> Bool {
        let extras = g.files.dropFirst()
        return !extras.isEmpty && extras.allSatisfy { model.selection.contains($0.path) }
    }

    private func dupRow(_ g: DupGroup) -> some View {
        let extras = Array(g.files.dropFirst())
        return ItemRow(
            selected: Binding(
                get: { groupSelected(g) },
                set: { on in
                    let paths = extras.map(\.path)
                    if on { model.selection.formUnion(paths) }
                    else { model.selection.subtract(paths) }
                }),
            icon: rowIcon(g.files.first, "doc.on.doc"),
            name: LF("%1$@ — %2$@",
                     g.files.first?.lastPathComponent ?? L("Duplicate group"),
                     cnt(g.files.count, "shares")),
            sub: LF("%@ each", human(g.size)),
            sizeText: shown[g.id] ?? human(g.waste),
            fraction: Double(g.waste) / Double(maxWaste),
            badge: nil,
            lit: true,
            showRule: model.groups.first?.id != g.id,
            preopen: SnapshotMode.expandFirstRow && model.groups.first?.id == g.id) {
            ForEach(Array(g.files.enumerated()), id: \.element.path) { idx, url in
                DupFileRow(url: url, isKept: idx == 0, date: model.dates[url.path], selection: $model.selection)
            }
        }
    }

}

///

private struct DupFileRow: View {
    @Environment(\.theme) private var theme
    var url: URL
    var isKept: Bool
    var date: Date?
    @Binding var selection: Set<String>

    var body: some View {
        HStack(spacing: 10) {
            if isKept {
                ThemeBadge(text: L("Kept"), tone: .safe, symbol: "lock.fill")
                    .frame(minWidth: 62, alignment: .leading)
                    .help(L("Each group keeps its newest copy: backup and export folders are dated in ascending order, so keeping the oldest would throw away the freshest backup"))
            } else {
                Toggle("", isOn: Binding(
                    get: { selection.contains(url.path) },
                    set: { on in
                        if on { selection.insert(url.path) } else { selection.remove(url.path) }
                    }
                ))
                .toggleStyle(ThemeCheckStyle(side: 16))
                .labelsHidden()
                .accessibilityLabel(LF("Select %@", url.lastPathComponent))
                .frame(minWidth: 62, alignment: .leading)
            }
            if let date {
                Text(date, format: .dateTime.day().month().year().hour().minute())
                    .font(theme.bodyFont(.caption2)).monospacedDigit()
                    .accessibilityLabel(LF("Modified: %@", date.formatted()))
            }
            Text(displayPath(url))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(isKept ? theme.palette.inkTertiary : theme.palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EnvCopiesClause: View {
    @Environment(\.theme) private var theme
    var count: Int
    var action: () -> Void

    @State private var hovering = false
    @State private var hand = false

    private var fg: Color {
        hovering ? SweepRing.lamp(theme.palette.tint) : theme.palette.inkTertiary
    }

    var body: some View {
        Button(action: action) {
            Text(LF("Plus %1$@ belonging to their own environments — not compared", cnt(count, "groups")))
                .font(theme.bodyFont(.caption))
                .foregroundStyle(fg)
                .underline(hovering, color: fg)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .onHover {
            hovering = $0
            guard hand != $0 else { return }
            hand = $0
            ($0 ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        .accessibilityAddTraits(.isLink)
    }
}

///

private struct EnvCopiesSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var groups: [EnvDupGroup]
    var bytes: Int64

    private var maxBytes: Int64 { max(1, groups.map(\.bytes).max() ?? 1) }

    private var shown: [UUID: String] {
        sizeColumn(groups.map { (key: $0.id, bytes: $0.bytes) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L("Excluded from comparison"))
                    .font(theme.display(.title3))
                    .tracking(theme.titleTracking)
                    .foregroundStyle(theme.palette.ink)
                Text(LF("%1$@ · %2$@ in total", cnt(groups.count, "groups"), human(bytes)))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkTertiary)
                    .monospacedDigit()
                Spacer(minLength: 12)
                ThemeButton(kind: .ghost, title: L("Close")) { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)


            List(groups) { g in
                ItemRow(selected: .constant(false),
                        icon: .path(g.files.first ?? URL(fileURLWithPath: "/")),
                        name: rowName(g),
                        sub: LF("%1$@ each · lives in %2$@",
                                human(g.size), cnt(g.envs.count, "environments")),
                        sizeText: shown[g.id] ?? human(g.bytes),
                        fraction: Double(g.bytes) / Double(maxBytes),
                        selectable: false,
                        lit: false,
                        showRule: groups.first?.id != g.id,
                        preopen: SnapshotMode.expandFirstRow && groups.first?.id == g.id) {
                            ExplainLine(key: L("Lives in"),
                                        value: g.envs.map { displayPath(URL(fileURLWithPath: $0)) }
                                            .joined(separator: " · "))
                            ForEach(g.files, id: \.path) { u in
                                PathLine(path: u.path)
                            }
                        }
            }
            .ledgerCard()

            ListNote(text: L("Each of these copies lives inside an environment. Delete one and that environment is missing a piece; remove the environment and the whole block goes with it."))
        }
        .frame(width: 780, height: 520)
        .background(theme.palette.paper)
    }

    private func rowName(_ g: EnvDupGroup) -> String {
        let first = g.files.first?.lastPathComponent ?? L("Duplicate group")
        return g.files.count > 1 ? LF("%1$@ — %2$@", first, cnt(g.files.count, "shares")) : first
    }
}

private func orphanWhat(_ it: OrphanItem) -> String {
    LF("Data left in %2$@ by the uninstalled app “%1$@”", L(it.guess), it.loc)
}

private func orphanRisk(_ it: OrphanItem) -> String {
    it.level == "warn"
        ? L("Reinstalling the app won't bring these settings back; other apps are unaffected")
        : L("Harmless in practice: the app rebuilds it when needed")
}

struct OrphansView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: OrphansModel
    @State private var review: TrashReviewPlan?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "app.badge", title: L("Leftovers"),
                           subtitle: L("Uninstalled apps left data behind — checked against every app still installed"),
                           variant: .display, scope: L("App data in the home folder"))
                ControlStrip {
                    if model.scanning {
                        LoadingRow(text: L("Inventorying installed apps, matching orphans…"),
                                   progress: model.progress)
                    } else {
                        Text(LF("Checked %1$@, found %2$@, %3$@ in total",
                                cnt(model.appCount, "apps"),
                                cnt(model.items.count, "suspicious spots"),
                                human(model.totalBytes)))
                    }
                    ThemeBadge(text: L("Under-reports rather than over-deletes"), tone: .neutral)
                } trailing: {
                    ScanControl(scanning: model.scanning,
                                rescan: { model.scan() }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.scan() })
            Button(L("Review installed apps")) { store.arrive(NavStop(panel: .uninstall)) }
                .buttonStyle(.link).padding(.bottom, 8)

            if model.scanning && model.items.isEmpty {
                ScanChecklist(progress: model.progress)
            } else if !model.scanning && model.items.isEmpty {
                EmptyState(symbol: "app.badge.checkmark", title: L("No matching items in the scanned scope"),
                           hint: L("Review the scan scope or scan again."))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.items.count), detail: human(model.totalBytes), symbol: "app.badge"),
                    .init(title: L("Selected"), value: human(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
                if let note = ledgerNote { ListNote(text: note) }
                List($model.items) { $it in
                    ItemRow(selected: $it.selected,
                            icon: .path(it.path),
                            name: it.name,
                            sub: it.loc,
                            sizeText: it.size == nil ? L("Unknown") : (shown[it.id] ?? human(it.size ?? 0)),
                            fraction: Double(it.size ?? 0) / Double(maxSize),
                            badge: verdictBadge(it.level == "warn" ? .risky : .safe),
                            lit: it.level != "warn",
                            showRule: model.items.first?.id != it.id,
                            preopen: SnapshotMode.expandFirstRow
                                && model.items.first?.id == it.id) {
                        ExplainLine(key: L("What it is"), value: orphanWhat(it))
                        ExplainLine(key: L("What breaks"), value: orphanRisk(it))
                        ExplainLine(key: L("How to recover"), value: L("Put it back from the Trash, or reinstall the app"))
                        if let what = contentsLine(it.files, it.newest) {
                            ExplainLine(key: L("Contents"), value: what)
                        }
                        PathLine(path: it.path.path)
                    }
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: model.selected.count, bytes: human(model.selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)

        .onAppear { if !model.started { model.scan() } }
        .sheet(item: $review) { review in
            ConfirmedTrashSheet(plan: review.items, currentPlan: { model.trashPlan() },
                                perform: { await model.trash(using: store) })
                .themed(theme)
        }
    }

    private var maxSize: Int64 { max(1, model.items.compactMap(\.size).max() ?? 1) }

    private var listedTotal: Int64 { model.items.reduce(0) { $0 + ($1.size ?? 0) } }

    private var shown: [UUID: String] {
        sizeColumn(model.items.map { (key: $0.id, bytes: $0.size ?? 0) })
    }

    private var tiers: [LedgerTier] {
        [LedgerTier(label: L("Ours to clean"), bytes: listedTotal, tone: .hot)]
    }

    private var ledgerNote: String? { L(" Rows that lose data if deleted stay out of Select all — judge them one at a time.") }

}
