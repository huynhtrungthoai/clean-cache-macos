import SwiftUI
import DiskCleanerCore

//

//

//

func cacheGroupLabel(_ key: String) -> String {
    switch key {
    case "general": return L("Everyday caches")
    case "cn_app":  return L("Chinese apps")
    case "dev":     return L("Dev tools")
    default:        return key
    }
}

///

enum CachesPage {
    case app, dev, smart

    var groupKeys: Set<String> {
        self == .smart ? ["general", "cn_app", "dev"] : (self == .dev ? ["dev"] : ["general", "cn_app"])
    }
    var symbol: String { self == .dev ? "hammer" : "sparkles" }
    var titleKey: String { self == .smart ? "Scan Results" : (self == .dev ? "Dev Caches" : "App Caches") }
    var subtitleKey: String {
        if self == .smart { return "Review the results and choose what to clean" }
        return self == .dev ? "Only tools you've actually installed show up here; delete one and it re-downloads the next time you need it"
                     : "Every entry says what it is. Check what you recognize, leave the rest."
    }

    var emptyTitleKey: String {
        self != .app ? "No known caches found" : "The knowledge base didn't load"
    }
    var emptyHintKey: String {
        self == .smart ? "No known caches were found. You can scan again later."
            : self == .dev ? "Install Xcode, npm, Gradle or Ollama, then rescan here"
                     : "Hit Rescan in the top right; if it persists, open an Issue"
    }

    var showsGroupLabel: Bool { self == .app }
}

private func cacheRowSub(_ item: CacheItem, showsGroup: Bool) -> String? {
    guard let first = item.resolvedPaths.first else { return nil }
    var parts: [String] = []
    if showsGroup && item.groupKey != "general" { parts.append(cacheGroupLabel(item.groupKey)) }
    parts.append(displayPath(first))
    if item.resolvedPaths.count > 1 {
        parts.append(LF("%d paths", item.resolvedPaths.count))
    }
    return parts.joined(separator: " · ")
}

///

private func simulatorDevicesDir(_ item: CacheItem) -> URL? {
    item.resolvedPaths.first { $0.lastPathComponent == "Devices" && $0.path.contains("CoreSimulator") }
}

///

///

struct SimDeviceRows: View {
    @Environment(\.theme) private var theme
    var dir: URL
    @State private var rows: [SimDevice]? = nil

    var body: some View {
        Group {
            if rows == nil {
                ExplainLine(key: L("By device"), value: L("Measuring each device…"))
            } else {
                ForEach(rows ?? []) { d in row(d) }
            }
        }
        .task { rows = await scanSimulators(under: dir) }
    }

    private func row(_ d: SimDevice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(d.os.isEmpty ? d.name : "\(d.name) · \(d.os)")
                .font(theme.bodyFont(.caption).weight(.semibold))
                .foregroundStyle(theme.palette.inkTertiary)
                .lineLimit(1)
                .frame(width: 236, alignment: .leading)
            Text(uiHuman(d.size))
                .font(theme.bodyFont(.caption).monospacedDigit())
                .foregroundStyle(theme.palette.inkSecondary)
                .frame(width: 74, alignment: .trailing)
            Text(booted(d))
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func booted(_ d: SimDevice) -> String {
        guard let when = d.lastBooted else { return L("Never booted") }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return LF("Last booted %@", f.string(from: when))
    }
}

struct CachesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: CachesModel
    var page: CachesPage = .app
    @State private var review: TrashReviewPlan?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(symbol: page.symbol, title: L(page.titleKey),
                           subtitle: L(page.subtitleKey), variant: .display,
                           scope: L("Known cache locations in the home folder"))
                ControlStrip {
                    if model.scanning {

                        LoadingRow(text: LF("Digging through your cache folders — %1$d of %2$d measured",
                                            measuredCount, model.items.count),
                                   progress: model.progress)
                    } else {
                        Text(LF("Entries listed: %d", model.items.count))
                        if page == .smart, model.selectAll != nil {
                            Button(L("Select Recommended")) { model.selectAll?.toggle(true) }
                                .buttonStyle(.borderless)
                        }
                    }
                } trailing: {
                    ScanControl(scanning: model.scanning,
                                rescan: { model.load(force: true) }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.load(force: true) })

            if !model.scanning && !model.items.isEmpty {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.items.count), detail: L("Known cache locations in the home folder"), symbol: "list.bullet"),
                    .init(title: L("Bulk selection"), value: uiHuman(model.selectableBytes), detail: L("Only eligible items are included"), symbol: "checklist"),
                    .init(title: L("Selected"), value: uiHuman(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 12)
            }

            if model.scanning && model.items.isEmpty {
                ScanSkeleton()
            } else if !model.scanning && model.items.isEmpty {
                EmptyState(symbol: page.symbol, title: L("No matching items in the scanned scope"),
                           hint: L("Review the scan scope or scan again."))
                    .frame(maxHeight: .infinity)
            } else {
                if let note = ledgerNote { ListNote(text: note) }
                List($model.items) { $item in
                    ItemRow(selected: $item.selected,
                            icon: rowIcon(item.resolvedPaths, "sparkles"),
                            appID: item.entry.app,
                            brand: item.entry.icon,
                            name: L(item.entry.name),
                            sub: cacheRowSub(item, showsGroup: page.showsGroupLabel),
                            sizeText: cacheSize(item),
                            fraction: Double(item.size ?? 0) / Double(maxSize),
                            badge: verdictBadge(item.entry.tier),
                            selectable: (item.size ?? 0) > 0,
                            lit: cacheLit(item),
                            showRule: model.items.first?.id != item.id,
                            preopen: (SnapshotMode.expandFirstRow
                                && model.items.first?.id == item.id)
                                || SnapshotMode.expandsRow(L(item.entry.name), item.entry.name)) {
                        ExplainLine(key: L("What it is"), value: L(item.entry.what))
                        ExplainLine(key: L("What breaks"), value: L(item.entry.whatif))
                        ExplainLine(key: L("How to recover"), value: L(item.entry.rec))
                        if let what = contentsLine(item.files, item.newest) {
                            ExplainLine(key: L("Contents"), value: what)
                        }
                        if let devDir = simulatorDevicesDir(item) {
                            SimDeviceRows(dir: devDir)
                        }
                        ForEach(item.resolvedPaths, id: \.self) { p in
                            PathLine(path: p.path)
                        }
                    }
                }
                .ledgerCard()
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: model.selected.count, bytes: uiHuman(model.selectedBytes),
                               selection: model.selectAll, busy: model.scanning || store.isTrashing) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)

        .onAppear { model.load() }
        .trashWorkflow(review: $review, currentPlan: { model.trashPlan() },
                       perform: { await model.trash(using: store) })
    }

    private func cacheSize(_ item: CacheItem) -> String {
        switch model.rowState(item.id) {
        case .measuring: return L("Counting…")
        case .measured(let bytes): return shown[item.id] ?? uiHuman(bytes)
        case .unmeasurable: return L("Cannot measure (access required)")
        }
    }

    private var maxSize: Int64 { max(1, model.items.compactMap(\.size).max() ?? 1) }

    private var measuredCount: Int { model.items.filter { $0.size != nil }.count }

    ///

    private var measured: [(id: UUID, bytes: Int64, tier: VerdictTier)] {
        model.items.compactMap { it in
            guard let sz = it.size, sz > 0 else { return nil }
            return (id: it.id, bytes: sz, tier: it.entry.tier)
        }
    }

    private var listedTotal: Int64 { measured.reduce(Int64(0)) { $0 + $1.bytes } }

    private var shown: [UUID: String] {
        sizeColumn(measured.map { (key: $0.id, bytes: $0.bytes) })
    }

    ///

    ///

    ///

    private var tiers: [LedgerTier] {
        var hot = Int64(0), redo = Int64(0), risk = Int64(0)
        for row in measured {
            switch row.tier {

            case .safe, .unknown: hot += row.bytes
            case .redo:           redo += row.bytes
            case .risky:          risk += row.bytes
            }
        }
        return [LedgerTier(label: L("No impact"), bytes: hot, tone: .hot),
                LedgerTier(label: L("Needs re-download"), bytes: redo, tone: .warn),
                LedgerTier(label: L("Loses data"), bytes: risk, tone: .risk)]
    }

    private var ledgerNote: String? {

        model.overlapCount > 0
            ? LF(" %1$d of these paths sit inside another entry, so Select all actually takes %2$@ — not whatever this column adds up to.",
                 model.overlapCount, uiHuman(model.selectableBytes))
            : nil
    }

    private var barHint: String? {
        model.overlapCount > 0
            ? LF("%1$d paths sit inside others; the total counts the outermost only", model.overlapCount)
            : L("The total adds each entry's own size")
    }

}
