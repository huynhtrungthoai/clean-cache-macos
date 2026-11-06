import SwiftUI
import DiskCleanerCore

/// Batch entries retain the original outcome even after a restore.
struct BatchEntryView: View {
    @Environment(\.theme) private var theme
    var entry: TrashBatchEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.item.name).fontWeight(.medium)
                Spacer(minLength: 8)
                Text(uiHuman(entry.item.bytes)).monospacedDigit()
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
        .foregroundStyle(theme.palette.ink)
        .background(theme.palette.paper)
    }
}

