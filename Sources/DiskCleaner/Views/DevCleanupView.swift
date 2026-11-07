import SwiftUI
import DiskCleanerCore

/// V2-DEV Dev Cleanup center (docs/plan-v2.md §6.7). Everything comes from `DevCleanupModel`:
/// rows, kinds, totals, selection and the plan. Build output, environments and records are
/// listed for a manual tick only (owner decision 07/11/2026); the group checkbox never takes them.
struct DevCleanupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: DevCleanupModel
    @State private var kind: DevDataKind?
    @State private var ecosystem: DevEcosystem?
    @State private var query = ""
    @State private var review: TrashReviewPlan?

    var body: some View {
        let items = model.items
        let totals = devInventoryTotals(items)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(symbol: "hammer", title: L("Developer Cleanup"),
                           subtitle: L("Dependencies, build output, tool caches and environments in one place"),
                           variant: .compact, scope: L("Projects in your home folder and known tool caches"))
                ControlStrip {
                    if model.scanning {
                        Label(L("Looking through projects and tool caches…"), systemImage: "arrow.triangle.2.circlepath")
                            .font(theme.prose(size: 12)).foregroundStyle(theme.palette.inkSecondary)
                    } else {
                        Text(LF("Entries listed: %d", items.count))
                    }
                    Button { store.arrive(NavStop(panel: .docker)) } label: {
                        Label(L("Docker Usage (view only)"), systemImage: "cube")
                    }.buttonStyle(.borderless).font(theme.prose(size: 12))
                } trailing: {
                    ScanControl(scanning: model.scanning, kind: .compact,
                                rescan: { model.scan() }, stop: { model.stop() })
                }
            }
            .pagePadding().padding(.top, 10).padding(.bottom, 6)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.scan() })

            if !items.isEmpty {
                SummaryCards(metrics: [
                    .init(title: L("Found"), value: totals.measuredBytes.map(uiHuman) ?? L("Counting…"),
                          detail: L("Nested folders counted once"), symbol: "shippingbox"),
                    .init(title: L("Projects and tools"), value: "\(totals.projectCount) · \(totals.toolCount)",
                          detail: L("Projects · shared tool data"), symbol: "folder"),
                    .init(title: L("Selected"), value: uiHuman(totals.selectedBytes),
                          detail: LF("%d items selected", totals.selectedCount), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 6)
            }

            if model.scanning && items.isEmpty {
                ScanSkeleton()
            } else if !model.scanning && items.isEmpty {
                EmptyState(symbol: "hammer",
                           title: model.scanState == .idle ? L("Scan to find developer data") : L("No matching items in the scanned scope"),
                           hint: L("Only data with clear evidence is listed: a project file, a Git ignore rule or a cache tag."))
                    .frame(maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    HStack(alignment: .top, spacing: 14) {
                        if proxy.size.width >= 760 { kindColumn(items).frame(width: 196) }
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                if proxy.size.width < 760 {
                                    Picker(L("Kind"), selection: $kind) {
                                        Text(L("Everything")).tag(DevDataKind?.none)
                                        ForEach(model.kinds, id: \.self) { Text(L($0.titleKey)).tag(Optional($0)) }
                                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                                }
                                Picker(L("Ecosystem"), selection: $ecosystem) {
                                    Text(L("All tools")).tag(DevEcosystem?.none)
                                    ForEach(model.ecosystems, id: \.self) { Text(L($0.titleKey)).tag(Optional($0)) }
                                }.pickerStyle(.menu).labelsHidden().fixedSize()
                                SearchBox(prompt: L("Search projects and paths"), text: $query)
                            }
                            list(items)
                        }
                    }
                }
                .pagePadding()
            }

            Spacer(minLength: 0)

            SelectionActionBar(count: totals.selectedCount, bytes: uiHuman(totals.selectedBytes),
                               selection: selectAll(items), busy: model.scanning || store.isTrashing,
                               consequence: L("Items move to the Trash and can be restored. Projects may need a reinstall or rebuild before they run again.")) {
                let plan = model.trashPlan()
                if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if model.scanState == .idle && !model.scanning { model.scan() } }
        .trashWorkflow(review: $review, currentPlan: { model.trashPlan() },
                       perform: { await model.trash(using: store) })
    }

    private func selectAll(_ items: [DevInventoryItem]) -> SelectAll? {
        let eligible = items.filter { $0.eligibility.isEligible }
        guard !eligible.isEmpty else { return nil }
        return SelectAll(allSelected: devKindSelection(items, kind: nil) == .all,
                         unselectable: items.count - eligible.count) { _ in model.toggle(kind: nil) }
    }

    private func kindColumn(_ items: [DevInventoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            kindButton(nil, items)
            ForEach(model.kinds, id: \.self) { kindButton($0, items) }
            Text(L("Build output, environments and records are never selected for you: tick them one by one."))
                .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.top, 10)
        }
        .padding(8)
        .background(theme.cardShape().fill(theme.palette.surface.opacity(reduceTransparency ? 1 : 0.65)))
    }

    private func kindButton(_ k: DevDataKind?, _ items: [DevInventoryItem]) -> some View {
        let rows = items.filter { k == nil || $0.kind == k }
        let unknown = rows.contains { $0.bytes == nil }
        let bytes = devInventoryTotals(rows).knownBytes
        let state = devKindSelection(items, kind: k)
        let canToggle = rows.contains { $0.eligibility.isEligible } || state != .none
        let title = k.map { L($0.titleKey) } ?? L("Everything")
        return HStack(alignment: .top, spacing: 8) {
            TriStateCheck(state: state, label: title, disabled: !canToggle || store.isTrashing) { model.toggle(kind: k) }
                .padding(.top, 2)
            Button { kind = k } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(theme.prose(size: 12, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if kind == k { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    }
                    Text(unknown ? L("Counting…") : uiHuman(bytes))
                        .font(theme.prose(size: 15, weight: .semibold)).monospacedDigit()
                    Text(LF("%d items", rows.count)).font(theme.prose(size: 10)).foregroundStyle(theme.palette.inkSecondary)
                }
                .foregroundStyle(theme.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(kind == k ? .isSelected : [])
        }
        .padding(8)
        .background(theme.controlShape().fill(kind == k ? theme.palette.tintSoft : .clear))
    }

    private func list(_ all: [DevInventoryItem]) -> some View {
        let rows = model.rows(kind: kind, ecosystem: ecosystem, query: query)
        let maxBytes = max(1, all.compactMap(\.bytes).max() ?? 1)
        return List(rows) { item in
            ItemRow(selected: Binding(get: { item.selected }, set: { model.setSelected(item.id, $0) }),
                    icon: rowIcon(item.paths.first.map { URL(fileURLWithPath: $0) }, "hammer"),
                    name: title(item),
                    sub: sub(item),
                    hint: item.eligibility.isEligible ? nil : item.eligibility.reasonKey.map(L),
                    sizeText: size(item),
                    fraction: Double(item.bytes ?? 0) / Double(maxBytes),
                    badge: item.nestedInOtherRow ? ItemBadge(text: L("Inside another item"), tone: .neutral) : nil,
                    badge2: verdictBadge(item.tier),
                    selectable: item.bytes != nil && item.eligibility != .empty,
                    lit: item.eligibility.isEligible,
                    showRule: rows.first?.id != item.id) {
                detail(item)
            }
        }
        .ledgerCard(horizontalInset: 0)
        .overlay {
            if rows.isEmpty {
                Text(L("No matching items in the scanned scope"))
                    .font(theme.prose(size: 13)).foregroundStyle(theme.palette.inkSecondary).padding()
            }
        }
    }

    private func title(_ item: DevInventoryItem) -> String {
        switch item.evidence {
        case .projectFiles(let type, _): return "\(item.name) · \(L(type.titleKey))"
        case .nodeModules: return "\(item.name) · node_modules"
        case .knowledgeBase: return L(item.name)
        }
    }

    private func sub(_ item: DevInventoryItem) -> String {
        var parts = [L(item.ecosystem.titleKey)]
        if let p = item.paths.first { parts.append(displayPath(URL(fileURLWithPath: p))) }
        return parts.joined(separator: " · ")
    }

    private func size(_ item: DevInventoryItem) -> String {
        guard let b = item.bytes else { return L("Counting…") }
        if item.unmeasurable { return L("Cannot measure (access required)") }
        return uiHuman(b)
    }

    @ViewBuilder private func detail(_ item: DevInventoryItem) -> some View {
        let entry = model.caches.items.first { "kb:" + $0.entry.path == item.id }?.entry
        ExplainLine(key: L("What it is"), value: entry.map { L($0.what) } ?? L(item.kind.titleKey))
        if let entry {
            ExplainLine(key: L("What breaks"), value: L(entry.whatif))
            ExplainLine(key: L("How to recover"), value: L(entry.rec))
        }
        ExplainLine(key: L("How we know"), value: evidence(item))
        if entry == nil {
            ExplainLine(key: L("To get it back"), value: item.reinstallHint.map { LF("Run %@ in the project", $0) }
                        ?? L("Rebuild or reinstall with the project's own tools"))
        }
        ExplainLine(key: L("In use"), value: L("Not verified"))
        ForEach(item.paths, id: \.self) { PathLine(path: $0) }
    }

    private func evidence(_ item: DevInventoryItem) -> String {
        switch item.evidence {
        case .knowledgeBase(let pattern): return LF("Known tool location: %@", pattern)
        case .nodeModules(let manager): return manager.map { LF("node_modules installed by %@", $0) } ?? L("node_modules folder; package manager not identified")
        case .projectFiles(_, let files): return LF("Found next to: %@", files.joined(separator: ", "))
        }
    }
}
