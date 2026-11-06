import SwiftUI
import DiskCleanerCore

/// Presentation values only. Scan and operation state stay in the models.
struct SummaryMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var detail: String
    var symbol: String
}

struct SummaryCards: View {
    @Environment(\.theme) private var theme
    var metrics: [SummaryMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { cards }
            VStack(spacing: 12) { cards }
        }
    }

    private var cards: some View {
        ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
            ThemedCard(padding: 12, alt: index > 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(metric.title, systemImage: metric.symbol)
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.inkSecondary)
                    Text(metric.value)
                        .font(theme.prose(size: index == 0 ? 32 : 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(metric.detail)
                        .font(theme.bodyFont(.caption2))
                        .foregroundStyle(theme.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Kept outside the scrolling results so review is reachable at minimum window height.
struct SelectionActionBar: View {
    @Environment(\.theme) private var theme
    var count: Int
    var bytes: String
    var selection: SelectAll? = nil
    var busy = false
    var consequence: String = L("Items move to the Trash. Free space may not increase until it is emptied.")
    var review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    selected
                    selectionButton
                    Spacer(minLength: 8)
                    reviewButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    selected
                    HStack { selectionButton; Spacer(minLength: 8); reviewButton }
                }
            }
            Text(consequence)
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(theme.palette.surface)
        .overlay(alignment: .top) { Divider().overlay(theme.palette.separator) }
    }

    private var selected: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LF("%d items selected", count)).font(theme.bodyFont(.caption))
            Text(bytes).font(theme.prose(size: 22, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(theme.palette.ink)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var selectionButton: some View {
        if let selection {
            Button(selection.allSelected ? L("Deselect all") : L("Select all")) {
                selection.toggle(!selection.allSelected)
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .help(LF("%d items stay outside bulk selection", selection.unselectable))
        }
    }

    private var reviewButton: some View {
        ThemeButton(kind: .primary, symbol: "checklist", title: L("Review and confirm"),
                    isDisabled: count == 0 || busy,
                    shortcut: KeyboardShortcut(.return, modifiers: .command), action: review)
    }
}

struct TrashReviewItem: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var size: String
}

/// A review snapshot has no filesystem responsibilities. A model action can be supplied
/// once its contract is merged; nil leaves a readable review without performing a move.
struct TrashReviewSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var items: [TrashReviewItem]
    var bytes: String
    var consequence: String = L("Items move to the Trash. Free space may not increase until it is emptied.")
    var busy = false
    var dismissOnConfirm = true
    var confirm: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(symbol: "trash", title: L("Review and confirm"),
                       subtitle: LF("%d items selected", items.count))
            HStack {
                Text(L("Selected")).font(theme.bodyFont(.callout))
                Spacer()
                Text(bytes).font(theme.prose(size: 24, weight: .semibold)).monospacedDigit()
            }
            Text(consequence)
                .font(theme.bodyFont(.callout))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            List(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name).fontWeight(.medium)
                        Spacer()
                        Text(item.size).monospacedDigit()
                    }
                    Text(item.path)
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.inkSecondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            if confirm == nil {
                Label(L("Moving items is currently unavailable. Your files have not been changed."),
                      systemImage: "info.circle")
                    .font(theme.bodyFont(.callout))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                    .foregroundStyle(theme.palette.ink)
                Spacer()
                ThemeButton(kind: .danger, symbol: "trash", title: L("Move to Trash"),
                            isDisabled: confirm == nil || items.isEmpty || busy) {
                    confirm?()
                    if dismissOnConfirm { dismiss() }
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 500)
        .interactiveDismissDisabled(busy)
        .background(theme.palette.paper)
        .foregroundStyle(theme.palette.ink)
    }
}

/// The operation supplies all three lists and any available undo action.
/// This view never infers success from a notice or the disappearance of a row.
struct OperationResultView: View {
    @Environment(\.theme) private var theme
    var moved: [String]
    var skipped: [String]
    var failed: [String]
    var undo: (() -> Void)? = nil
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(symbol: failed.isEmpty && skipped.isEmpty ? "checkmark.circle" : "exclamationmark.circle",
                       title: L("Operation results"),
                       subtitle: L("Review moved, skipped and failed items"), variant: .display)
            SummaryCards(metrics: [
                .init(title: L("Moved to Trash"), value: String(moved.count), detail: L("Items"), symbol: "checkmark.circle"),
                .init(title: L("Skipped items"), value: String(skipped.count), detail: L("Items"), symbol: "minus.circle"),
                .init(title: L("Failed items"), value: String(failed.count), detail: L("Items"), symbol: "exclamationmark.circle")
            ])
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    resultSection(L("Moved to Trash"), moved, "checkmark.circle")
                    resultSection(L("Skipped items"), skipped, "minus.circle")
                    resultSection(L("Failed items"), failed, "exclamationmark.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L("Items move to the Trash. Free space may not increase until it is emptied."))
                .font(theme.bodyFont(.caption)).foregroundStyle(theme.palette.inkSecondary)
            HStack {
                if let undo { Button(L("Undo batch"), action: undo) }
                Spacer()
                Button(L("Close"), action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .foregroundStyle(theme.palette.ink)
        .background(theme.palette.paper)
    }

    @ViewBuilder private func resultSection(_ title: String, _ rows: [String], _ symbol: String) -> some View {
        if !rows.isEmpty {
            Label(title, systemImage: symbol).font(theme.bodyFont(.headline)).accessibilityAddTraits(.isHeader)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row).font(theme.bodyFont(.callout)).textSelection(.enabled)
            }
        }
    }
}


/// Shared presentation of the lifecycle reported by the scanning model.
struct ScanStatusView: View {
    @Environment(\.theme) private var theme
    var model: any ScanStatusReporting
    var lastTrashAt: Date?
    var rescan: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(stateText, systemImage: model.isPartial ? "exclamationmark.triangle" : "info.circle")
                    if let date = model.scannedAt {
                        Text(date, format: .dateTime.day().month().hour().minute())
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if model.scanState != .scanning && model.isStale(lastTrashAt: lastTrashAt) {
                        Text(L("Results may be out of date"))
                        Button(L("Scan again"), action: rescan)
                    } else if model.scanState == .idle || model.scanState == .stopped {
                        Button(L("Scan now"), action: rescan)
                    }
                }
                if !model.issues.isEmpty {
                    DisclosureGroup(LF("%d locations were not fully scanned", model.issues.count)) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.issues) { issue in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.root).textSelection(.enabled)
                                        Text(issueReason(issue)).foregroundStyle(theme.palette.inkSecondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }
                }
            }
            .font(theme.bodyFont(.caption))
            .foregroundStyle(theme.palette.inkSecondary)
            .padding(.horizontal, 24).padding(.bottom, 8)
        }
    }

    private var stateText: String {
        switch model.scanState {
        case .idle: return L("Not scanned yet")
        case .scanning: return L("Scanning…")
        case .stopped: return L("Scan stopped. Results are incomplete.")
        case .completed: return model.isPartial ? L("Partial scan results") : L("Scan completed")
        }
    }

    private func issueReason(_ issue: ScanIssue) -> String {
        switch issue.kind {
        case .noPermission: return L("Access denied. Grant access in System Settings > Privacy & Security > Full Disk Access, then scan again.")
        case .notFound: return L("Location not found")
        case .error(let detail): return LF("Scan failed: %@", detail)
        }
    }
}

/// Batch entries retain the original outcome even after a restore.
struct BatchEntryView: View {
    @Environment(\.theme) private var theme
    var entry: TrashBatchEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.item.name).fontWeight(.medium)
                Spacer(minLength: 8)
                Text(human(entry.item.bytes)).monospacedDigit()
            }
            Text(entry.item.path).textSelection(.enabled)
            Label(outcomeText, systemImage: outcomeSymbol)
            if let restore = entry.restore {
                Label(restoreText(restore), systemImage: "arrow.uturn.backward")
                    .textSelection(.enabled)
            }
        }
        .font(theme.bodyFont(.caption))
        .foregroundStyle(theme.palette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var outcomeText: String {
        switch entry.outcome {
        case .moved: return L("Moved to Trash")
        case .skipped(let reason): return LF("Skipped: %@", L(reason.reasonKey))
        case .failed(let key, let detail): return detail.isEmpty ? L(key) : LF("%@: %@", L(key), detail)
        }
    }

    private var outcomeSymbol: String {
        switch entry.outcome {
        case .moved: return "trash"
        case .skipped: return "minus.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private func restoreText(_ restore: RestoreOutcome) -> String {
        switch restore {
        case .restored(let path) where path != entry.item.path:
            return LF("Restored with a new name: %@", path)
        case .failed(let detail):
            return detail.isEmpty ? L(restore.reasonKey) : LF("%@: %@", L(restore.reasonKey), detail)
        default: return L(restore.reasonKey)
        }
    }
}

struct BatchResultSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var batch: TrashBatch

    private var current: TrashBatch { store.batches.first { $0.id == batch.id } ?? batch }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OperationResultView(
                moved: current.moved.map { $0.item.name + " · " + $0.item.path },
                skipped: current.skipped.map { entry in
                    if case .skipped(let reason) = entry.outcome {
                        return LF("%@: %@", entry.item.name, L(reason.reasonKey))
                    }
                    return entry.item.name
                },
                failed: current.failed.map { entry in
                    if case .failed(let key, let detail) = entry.outcome {
                        return LF("%@: %@", entry.item.name, detail.isEmpty ? L(key) : LF("%@: %@", L(key), detail))
                    }
                    return entry.item.name
                },
                undo: store.canUndo(batchID: batch.id) ? { Task { _ = await store.undo(batchID: batch.id) } } : nil,
                done: { dismiss() })
            if current.entries.contains(where: { $0.restore != nil }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Restore results")).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                        ForEach(current.entries.filter { $0.restore != nil }) { BatchEntryView(entry: $0) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 160).padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .frame(width: 680, height: 520)
        .background(theme.palette.paper)
    }
}

extension TrashReviewItem {
    init(_ item: TrashPlanItem) {
        self.init(name: item.name, path: item.path, size: human(item.bytes))
    }
}


struct TrashReviewPlan: Identifiable {
    let id = UUID()
    let items: [TrashPlanItem]
}

/// Sheet-owned state prevents an initial presentation from capturing an empty selection.
struct ConfirmedTrashSheet: View {
    @EnvironmentObject private var store: AppStore
    var plan: [TrashPlanItem]
    var currentPlan: () -> [TrashPlanItem]
    var perform: () async -> TrashBatch?
    @State private var result: TrashBatch?
    @State private var changed = false

    var body: some View {
        Group {
            if let result {
                BatchResultSheet(batch: result)
            } else {
                TrashReviewSheet(items: plan.map(TrashReviewItem.init),
                                 bytes: human(plan.reduce(0) { $0 + $1.bytes }),
                                 busy: store.isTrashing, dismissOnConfirm: false) {
                    guard plan == currentPlan() else { changed = true; return }
                    Task { result = await perform() }
                }
            }
        }
        .frame(width: 680, height: 520)
        .transaction { $0.animation = nil }
        .alert(L("Selection changed. Review and confirm again."), isPresented: $changed) {
            Button(L("Close"), role: .cancel) { }
        }
    }
}
