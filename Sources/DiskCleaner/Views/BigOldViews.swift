import SwiftUI
import DiskCleanerCore

///

///

private func fileVerdictNote(_ rows: [FileRow], ruler: Int64) -> String? {
    guard !rows.isEmpty else { return nil }
    var safe = 0, redo = 0, risky = 0, unknown = 0
    var safeBytes = Int64(0)
    for r in rows {
        switch VerdictIndex.shared.verdict(for: r.url.path).tier {
        case .safe:    safe += 1; safeBytes += r.size
        case .redo:    redo += 1
        case .risky:   risky += 1
        case .unknown: unknown += 1
        }
    }
    var parts: [String] = []
    if safe > 0 {
        parts.append(LF("%1$@ with no impact, %2$@ in total",
                        cnt(safe, "items"), uiHuman(safeBytes, inRulerOf: ruler)))
    }
    if redo > 0 { parts.append(LF("%1$@ need re-downloading", cnt(redo, "items"))) }
    if risky > 0 { parts.append(LF("%1$@ would lose data if deleted", cnt(risky, "items"))) }
    if unknown > 0 {
        parts.append(LF("Another %1$@ aren't in the knowledge base: not listed doesn't mean safe to delete, so check the path before ticking it",
                        cnt(unknown, "items")))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ") + "."
}

struct BigFilesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: BigFilesModel
    @State private var review: TrashReviewPlan?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: "doc.on.doc", title: L("Large Files"),
                           subtitle: L("Sorted by size, largest first"),
                           variant: .display, scope: model.scopeNote ?? model.scope.uiName)
                ControlStrip {
                    if model.scanning {
                        LoadingRow(text: L("Going through your folders…"), progress: model.progress)
                    } else {
                        Text(LF("Found %@", cnt(model.count, "files")))
                    }
                    if let note = model.scopeNote {

                        ThemeBadge(text: LF("Only %@", note), tone: .tint, symbol: "scope")
                        ThemeButton(kind: .compact, title: L("Show all folders")) {
                            model.scan(scope: store.scope)
                        }
                    } else {
                        ThemeBadge(text: LF("Scope: %@", model.scope.uiName),
                                   tone: .neutral, symbol: "scope")
                    }
                } trailing: {

                    ThemeSwitch(label: L("Skip dev folders"), isOn: $model.skipDev) {
                        model.rescan(scope: store.scope)
                    }
                    ThemeStepper(label: L("Top"), value: $model.limit, range: 10...200, step: 10) {
                        model.applyLimit()
                    }
                    ScanControl(scanning: model.scanning,
                                rescan: { model.rescan(scope: store.scope) },
                                stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.rescan(scope: store.scope) })

            if model.scanning && model.rows.isEmpty {
                ScanChecklist(progress: model.progress, scope: model.scope.uiName)
            } else if !model.scanning && model.rows.isEmpty {
                EmptyState(symbol: "doc", title: L("No matching items in the scanned scope"),
                           hint: L("Review the scan scope or scan again."))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.rows.count), detail: uiHuman(listedTotal), symbol: "doc.on.doc"),
                    .init(title: L("Selected"), value: uiHuman(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
                if let note = ledgerNote { ListNote(text: note) }
                List($model.rows) { $r in
                    ItemRow(selected: $r.selected,
                            icon: .path(r.url),
                            name: r.name,
                            sub: displayPath(r.url.deletingLastPathComponent()) + " · " + r.dateStr,

                            hint: verdictHint(for: r.url.path),
                            sizeText: shown[r.id] ?? uiHuman(r.size),
                            fraction: Double(r.size) / Double(maxSize),
                            badge: r.deletable ? nil : ItemBadge(text: L("Not ours to touch"), tone: .neutral),

                            badge2: verdictBadge(VerdictIndex.shared.verdict(for: r.url.path).tier),
                            selectable: r.deletable,
                            lit: r.deletable,
                            showRule: model.rows.first?.id != r.id,
                            lockedHint: r.deletable ? nil : outsideScopeHint) {
                        VStack(alignment: .leading, spacing: 7) {
                            PathLine(path: r.url.path)

                            ThemeButton(kind: .compact, symbol: "folder",
                                        title: L("Open containing folder")) {
                                store.drill(into: r.url.deletingLastPathComponent().path)
                            }
                        }
                    }
                }
                .ledgerCard()

                if let vn = verdictNote { ListNote(text: vn) }
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: model.selected.count, bytes: uiHuman(model.selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)

        .onAppear {

            if let dir = store.bigScanDir {
                store.bigScanDir = nil
                model.scan(scope: store.scope, dirs: [dir], note: dir.lastPathComponent)
            } else if !model.started {
                model.scan(scope: store.scope)
            }
        }
        .trashWorkflow(review: $review, currentPlan: { model.trashPlan() },
                       perform: { await model.trash(using: store) })
    }

    private var maxSize: Int64 { max(1, model.rows.map(\.size).max() ?? 1) }

    private var listedTotal: Int64 { model.rows.reduce(Int64(0)) { $0 + $1.size } }

    private var shown: [UUID: String] {
        sizeColumn(model.rows.map { (key: $0.id, bytes: $0.size) })
    }

    private var tiers: [LedgerTier] {
        let sp = listedSplitOf(model.rows, bytes: { $0.size }, lit: { $0.deletable })
        return [LedgerTier(label: L("Ours to clean"), bytes: sp.reclaimable, tone: .hot),
                LedgerTier(label: L("Not ours to touch"), bytes: sp.viewOnly, tone: .cold)]
    }

    private var ledgerNote: String? {
        model.count > model.rows.count
            ? LF(" Showing the %2$d largest of the %1$@ found — the rest are smaller than the smallest row here.",
                 String(model.count), model.rows.count)
            : nil
    }

    private var verdictNote: String? { fileVerdictNote(model.rows, ruler: listedTotal) }

}

struct OldFilesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: OldFilesModel
    @State private var review: TrashReviewPlan?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {

                PageHeader(symbol: "clock", title: L("Files not modified recently"),
                           subtitle: L("Modification dates do not indicate whether a file is still used."),
                           variant: .display,
                           wrapsControls: true, scope: model.scope.uiName) {
                    ThemeBadge(text: LF("Scope: %@", model.scope.uiName),
                               tone: .neutral, symbol: "scope")
                    ThemeSwitch(label: L("Skip dev folders"), isOn: $model.skipDev) {
                        model.scan(scope: store.scope)
                    }
                    ThemeStepper(label: L("Older than"), unit: L("days"),
                                 value: $model.days, range: 30...365, step: 30) {
                        model.scan(scope: store.scope)
                    }
                    ScanControl(scanning: model.scanning,
                                rescan: { model.scan(scope: store.scope) },
                                stop: { model.stop() })
                }

                Group {
                    if model.scanning {
                        LoadingRow(text: L("Looking for files that gathered dust…"), progress: model.progress,
                                   fillsRow: true)
                    } else {
                        Text(LF("%1$@, %2$@ in total", cnt(model.rows.count, "files"),
                                uiHuman(model.totalBytes)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(theme.bodyFont(.callout))
                .foregroundStyle(theme.palette.inkSecondary)
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.scan(scope: store.scope) })

            if model.scanning && model.rows.isEmpty {
                ScanChecklist(progress: model.progress, scope: model.scope.uiName)
            } else if !model.scanning && model.rows.isEmpty {
                EmptyState(symbol: "sparkle", title: L("No matching items in the scanned scope"),
                           hint: L("Modification dates do not indicate whether a file is still used."))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.rows.count), detail: uiHuman(model.totalBytes), symbol: "doc.on.doc"),
                    .init(title: L("Selected"), value: uiHuman(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
                if let note = ledgerNote { ListNote(text: note) }
                List($model.rows) { $r in
                    ItemRow(selected: $r.selected,
                            icon: .path(r.url),
                            name: r.name,
                            sub: displayPath(r.url.deletingLastPathComponent()) + " · " + r.dateStr,

                            hint: verdictHint(for: r.url.path),
                            sizeText: shown[r.id] ?? uiHuman(r.size),
                            fraction: Double(r.size) / Double(maxSize),
                            badge: r.deletable ? nil : ItemBadge(text: L("Not ours to touch"), tone: .neutral),

                            badge2: verdictBadge(VerdictIndex.shared.verdict(for: r.url.path).tier),
                            selectable: r.deletable,
                            lit: r.deletable,
                            showRule: model.rows.first?.id != r.id,
                            lockedHint: r.deletable ? nil : outsideScopeHint) {
                        VStack(alignment: .leading, spacing: 7) {
                            PathLine(path: r.url.path)

                            ThemeButton(kind: .compact, symbol: "folder",
                                        title: L("Open containing folder")) {
                                store.drill(into: r.url.deletingLastPathComponent().path)
                            }
                        }
                    }
                }
                .ledgerCard()

                if let vn = verdictNote { ListNote(text: vn) }
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: model.selected.count, bytes: uiHuman(model.selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)

        .onAppear { if !model.started { model.scan(scope: store.scope) } }
        .trashWorkflow(review: $review, currentPlan: { model.trashPlan() },
                       perform: { await model.trash(using: store) })
    }

    private var maxSize: Int64 { max(1, model.rows.map(\.size).max() ?? 1) }

    private var shown: [UUID: String] {
        sizeColumn(model.rows.map { (key: $0.id, bytes: $0.size) })
    }

    private var tiers: [LedgerTier] {
        let sp = listedSplitOf(model.rows, bytes: { $0.size }, lit: { $0.deletable })
        return [LedgerTier(label: L("Ours to clean"), bytes: sp.reclaimable, tone: .hot),
                LedgerTier(label: L("Not ours to touch"), bytes: sp.viewOnly, tone: .cold)]
    }

    private var ledgerNote: String? {
        if model.count > model.rows.count {
            return LF(" Showing the %2$d largest of the %1$@ found — the rest are smaller than the smallest row here.",
                      String(model.count), model.rows.count)
        }
        return L(" Every row on this page is on screen: add this column and you land on the header's number.")
    }

    private var verdictNote: String? { fileVerdictNote(model.rows, ruler: model.totalBytes) }

}
