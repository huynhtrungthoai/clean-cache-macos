import SwiftUI
import DiskCleanerCore

struct TrashView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: TrashModel
    @State private var confirmEmpty = false
    @State private var result: TrashBatch?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "trash", title: L("Trash and activity"),
                       subtitle: L("Review the Trash and restore recorded batches when possible"),
                       variant: .display, scope: L("Trash contents and saved activity"))
                .pagePadding().padding(.top, 14).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SummaryCards(metrics: [
                        .init(title: L("Trash"), value: model.measuring ? L("Counting…") : model.summary.map { human($0.bytes) } ?? L("Cannot measure"),
                              detail: model.summary.map { LF("%d items", $0.items) } ?? L("Open Finder to inspect the current contents of the Trash."), symbol: "trash"),
                        .init(title: L("Moved to Trash"), value: human(store.batches.reduce(0) { $0 + $1.movedBytes }),
                              detail: L("Recorded batches; includes items later restored"), symbol: "clock.arrow.circlepath"),
                        .init(title: L("Restored"), value: human(restoredBytes),
                              detail: L("Recorded restore results"), symbol: "arrow.uturn.backward")
                    ])
                    ThemedCard {
                        Text(L("Items move to the Trash. Free space may not increase until it is emptied."))
                            .font(theme.bodyFont(.callout))
                            .foregroundStyle(theme.palette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = model.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(theme.bodyFont(.callout)).textSelection(.enabled)
                    }
                    if store.batches.isEmpty {
                        EmptyState(symbol: "clock.arrow.circlepath", title: L("No recorded batches"),
                                   hint: L("Open Finder to inspect the current contents of the Trash."))
                    } else {
                        SectionLabel(text: L("Saved activity"), detail: L("Newest first"))
                        ForEach(store.batches) { batch in batchCard(batch) }
                    }
                }
                .pagePadding().padding(.bottom, 24)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(.borderless)
        .onAppear { model.refresh() }
        .onChange(of: store.lastTrashAt) { _ in model.refresh() }
        .sheet(item: $result) { batch in BatchResultSheet(batch: batch).themed(theme) }
        .alert(L("Empty the entire Trash?"), isPresented: $confirmEmpty) {
            Button(L("Cancel"), role: .cancel) { }
            Button(L("Empty Trash"), role: .destructive) {
                Task { _ = await model.emptyInFinder() }
            }.disabled(store.isTrashing || model.emptying)
        } message: {
            Text(L("All items in the Trash will be permanently deleted. This cannot be undone."))
        }
    }

    private var restoredBytes: Int64 {
        store.batches.flatMap(\.entries).reduce(0) { total, entry in
            if case .restored = entry.restore { return total + entry.item.bytes }
            return total
        }
    }

    private func batchCard(_ batch: TrashBatch) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceTitle(batch.source)).font(theme.bodyFont(.headline)).accessibilityAddTraits(.isHeader)
                        Text(batch.createdAt, format: .dateTime.day().month().year().hour().minute())
                            .font(theme.bodyFont(.caption)).foregroundStyle(theme.palette.inkSecondary)
                    }
                    Spacer()
                    Button(L("View details")) { result = batch }
                    Button(L("Undo batch")) {
                        Task { result = await store.undo(batchID: batch.id) }
                    }.disabled(!store.canUndo(batchID: batch.id) || model.emptying)
                }
                Text(LF("Moved %d items; %d items not processed", batch.moved.count, batch.skipped.count + batch.failed.count))
                    .font(theme.bodyFont(.callout))
                DisclosureGroup(LF("%d items", batch.entries.count)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(batch.id.uuidString).font(theme.bodyFont(.caption2)).textSelection(.enabled)
                        ForEach(batch.entries) { entry in
                            BatchEntryView(entry: entry)
                            Divider()
                        }
                    }.padding(.top, 8)
                }
                if !store.canUndo(batchID: batch.id) && !store.isTrashing {
                    Text(L("No items remain available to restore in this batch."))
                        .font(theme.bodyFont(.caption)).foregroundStyle(theme.palette.inkSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(L("Refresh")) { model.refresh() }.disabled(model.measuring || model.emptying)
                Spacer()
                Button(L("Open in Finder")) { model.openInFinder() }
                if model.canAskFinderToEmpty {
                    Button(L("Empty Trash"), role: .destructive) { confirmEmpty = true }
                        .disabled(store.isTrashing || model.emptying || model.measuring)
                }
            }
            Text(L("Empty the Trash in Finder after reviewing its contents. Emptying cannot be undone."))
                .font(theme.bodyFont(.caption)).foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(theme.palette.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func sourceTitle(_ source: String) -> String {
        switch source {
        case "caches": return L("App Caches")
        case "big-files": return L("Large Files")
        case "old-files": return L("Files not modified recently")
        case "duplicates": return L("Duplicates")
        case "leftovers": return L("Leftovers")
        case "uninstall": return L("Uninstall Apps")
        default: return source
        }
    }
}
