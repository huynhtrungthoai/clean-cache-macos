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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: CachesModel
    var page: CachesPage = .app
    @State private var query = ""
    @State private var selectedGroup: CleanupGroupID?
    @State private var review: TrashReviewPlan?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(symbol: page.symbol, title: L(page.titleKey),
                           subtitle: L(page.subtitleKey), variant: .compact,
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
                    ScanControl(scanning: model.scanning, kind: .compact,
                                rescan: { model.load(force: true) }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.load(force: true) })

            if !model.scanning && !model.items.isEmpty {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.items.count), detail: L("Known cache locations in the home folder"), symbol: "list.bullet"),
                    .init(title: L("Bulk selection"), value: uiHuman(model.selectableBytes), detail: L("Only eligible items are included"), symbol: "checklist"),
                    .init(title: L("Selected"), value: uiHuman(model.selectedBytes), detail: LF("%d items selected", model.selected.count), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 6)
            }

            if model.scanning && model.items.isEmpty {
                ScanSkeleton()
            } else if !model.scanning && model.items.isEmpty {
                EmptyState(symbol: page.symbol, title: L("No matching items in the scanned scope"),
                           hint: L("Review the scan scope or scan again."))
                    .frame(maxHeight: .infinity)
            } else {
                if let note = ledgerNote { ListNote(text: note) }
                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: 14) {
                        if proxy.size.width >= 760 { groupPicker.frame(width: 190) }
                        VStack(spacing: 8) {
                            if proxy.size.width < 760 {
                                Picker(L("All caches"), selection: $selectedGroup) {
                                    Text(L("All caches")).tag(CleanupGroupID?.none)
                                    ForEach(model.groupSummaries()) { g in
                                        Text(L(g.id.titleKey)).tag(Optional(g.id))
                                    }
                                }.pickerStyle(.menu).labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                                TextField(L("Search caches"), text: $query)
                                    .textFieldStyle(.plain)
                                    .accessibilityLabel(L("Search caches"))
                                if !query.isEmpty {
                                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain).accessibilityLabel(L("Clear search"))
                                }
                            }
                            .font(theme.prose(size: 13))
                            .foregroundStyle(theme.palette.inkSecondary)
                            .padding(10)
                            .background(theme.controlShape().fill(theme.palette.surface))
                            resultList
                        }
                    }
                }
                .pagePadding()

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

    private var groupPicker: some View {
        let sums = model.groupSummaries()
        return VStack(alignment: .leading, spacing: 6) {
            groupButton(title: L("All caches"), summary: nil, all: sums)
            ForEach(sums) { g in groupButton(title: L(g.id.titleKey), summary: g, all: sums) }
            Text(L("Filters keep your selection"))
                .font(theme.prose(size: 11))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.top, 10)
        }
        .padding(8)
        .background(theme.cardShape().fill(theme.palette.surface.opacity(reduceTransparency ? 1 : 0.65)))
    }

    /// V2-CLEANUP: one semantic group (nil = all) with real bytes and a tri-state checkbox.
    private func groupButton(title: String, summary: CleanupGroupSummary?, all: [CleanupGroupSummary]) -> some View {
        let key = summary?.id
        let bytes: String = {
            if let g = summary { return g.measuredBytes.map(uiHuman) ?? L("Counting…") }
            return all.contains { $0.measuredBytes == nil } ? L("Counting…")
                : uiHuman(contentsUnionSize(pathSizes(of: model.items)))
        }()
        return HStack(alignment: .top, spacing: 8) {
            if let g = summary {
                TriStateCheck(state: g.selection, label: title,
                              disabled: model.scanning || store.isTrashing || (g.eligibleCount == 0 && g.selection == .none)) {
                    model.toggleGroup(g.id)
                }
                .padding(.top, 2)
                .help(g.eligibleCount == 0 ? L("Choose items in this group yourself") : "")
            }
            Button { selectedGroup = key } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(theme.prose(size: 12, weight: .medium))
                        Spacer(minLength: 4)
                        if selectedGroup == key {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                    }
                    Text(model.scanning ? L("Counting…") : bytes)
                        .font(theme.prose(size: 16, weight: .semibold)).monospacedDigit()
                    if let g = summary {
                        Text(g.selectedCount > 0 ? LF("%1$d of %2$d selected", g.selectedCount, g.count) : LF("%d items", g.count))
                            .font(theme.prose(size: 10)).foregroundStyle(theme.palette.inkSecondary)
                    }
                }
                .foregroundStyle(theme.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedGroup == key ? .isSelected : [])
        }
        .padding(8)
        .background(theme.controlShape().fill(selectedGroup == key ? theme.palette.tintSoft : .clear))
    }

    private func matches(_ item: CacheItem) -> Bool {
        (selectedGroup == nil || selectedGroup == cleanupGroupID(for: item)) &&
        (query.isEmpty || L(item.entry.name).localizedCaseInsensitiveContains(query) ||
         item.resolvedPaths.contains { $0.path.localizedCaseInsensitiveContains(query) })
    }

    private var resultList: some View {
        List($model.items) { $item in
            if matches(item) {
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
        }
        .ledgerCard(horizontalInset: 0)
        .overlay {
            if !model.items.contains(where: matches) {
                Text(L("No matching items in the scanned scope"))
                    .font(theme.prose(size: 13))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .padding()
            }
        }
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
