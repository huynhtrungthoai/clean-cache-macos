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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
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
            }
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
            List(items) { item in
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
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                ThemeButton(kind: .danger, symbol: "trash", title: L("Move to Trash"),
                            isDisabled: confirm == nil || items.isEmpty) {
                    confirm?()
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 500)
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
                if let undo { Button(L("Undo last"), action: undo) }
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
