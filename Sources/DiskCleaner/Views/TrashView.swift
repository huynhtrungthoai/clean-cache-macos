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
                       variant: .compact, scope: L("Trash contents and saved activity"))
                .pagePadding().padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        WorkspaceEmblem(symbol: "trash", size: 96)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Trash")).font(theme.prose(size: 26, weight: .semibold))
                            Text(model.measuring ? L("Counting…") : model.summary.map { uiHuman($0.bytes) } ?? L("Cannot measure"))
                                .font(theme.numeric(size: 36, weight: .light)).monospacedDigit()
                            Text(L("Review the Trash and restore recorded batches when possible"))
                                .font(theme.prose(size: 13)).foregroundStyle(theme.palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    SummaryCards(metrics: [
                        .init(title: L("Trash"), value: model.measuring ? L("Counting…") : model.summary.map { uiHuman($0.bytes) } ?? L("Cannot measure"),
                              detail: model.summary.map { LF("%d items", $0.items) } ?? L("Open Finder to inspect the current contents of the Trash."), symbol: "trash"),
                        .init(title: L("Moved to Trash"), value: uiHuman(store.batches.reduce(0) { $0 + $1.movedBytes }),
                              detail: L("Recorded batches; includes items later restored"), symbol: "clock.arrow.circlepath"),
                        .init(title: L("Restored"), value: uiHuman(restoredBytes),
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
                    if !legacyRecords.isEmpty {
                        SectionLabel(text: L("Other moves this session"), detail: L("Newest first"))
                        ThemedCard {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(legacyRecords.reversed().enumerated()), id: \.offset) { _, record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.displayName).fontWeight(.medium)
                                        Text(record.original.path).textSelection(.enabled)
                                        Text(uiHuman(record.size)).monospacedDigit()
                                    }.font(theme.bodyFont(.caption)).accessibilityElement(children: .combine)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    inventorySection
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
        .foregroundStyle(theme.palette.ink)
        .buttonStyle(.borderless)
        .onAppear { model.refresh(); model.loadInventory(batches: store.batches) }
        .onChange(of: store.lastTrashAt) { _ in model.refresh(); model.loadInventory(batches: store.batches) }
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

    /// V2-TRASH: what is in the Trash right now, per volume (read-only).
    @ViewBuilder private var inventorySection: some View {
        SectionLabel(text: L("In the Trash"), detail: L("Per volume, largest first"))
        if model.listing && model.volumes == nil {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Counting…")) }
                .font(theme.bodyFont(.callout))
        } else if let volumes = model.volumes {
            ForEach(volumes) { v in volumeCard(v) }
        }
    }

    private func volumeCard(_ v: TrashVolume) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(v.volumeName, systemImage: v.volumePath == "/" ? "internaldrive" : "externaldrive")
                        .font(theme.bodyFont(.headline))
                    Spacer()
                    Text(volumeValue(v)).font(theme.prose(size: 16, weight: .semibold)).monospacedDigit()
                }
                switch v.state {
                case .readable where v.entries.isEmpty:
                    Text(L("Empty")).font(theme.bodyFont(.callout)).foregroundStyle(theme.palette.inkSecondary)
                case .readable:
                    ForEach(v.entries.prefix(40)) { e in entryRow(e) }
                    if v.entries.count > 40 {
                        Text(LF("and %d more", v.entries.count - 40))
                            .font(theme.bodyFont(.caption)).foregroundStyle(theme.palette.inkSecondary)
                    }
                case .noPermission:
                    Text(L("CleanPilot can't read this Trash. Open it in Finder, or allow Full Disk Access."))
                        .font(theme.bodyFont(.callout)).foregroundStyle(theme.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .missing:
                    Text(L("No Trash folder on this volume")).font(theme.bodyFont(.callout))
                        .foregroundStyle(theme.palette.inkSecondary)
                case .error(let msg):
                    Text(msg).font(theme.bodyFont(.callout)).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func volumeValue(_ v: TrashVolume) -> String {
        switch v.state {
        case .readable: return v.bytes.map(uiHuman) ?? L("Unknown")
        case .noPermission: return L("Cannot measure")
        default: return "—"
        }
    }

    private func entryRow(_ e: TrashEntry) -> some View {
        HStack(spacing: 10) {
            RowIconView(icon: .path(URL(fileURLWithPath: e.id)), side: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                    if e.isCloudItem == true {
                        Image(systemName: "icloud").font(.system(size: 10)).help(L("iCloud item"))
                            .accessibilityLabel(L("iCloud item"))
                    }
                }
                Text(entrySub(e)).font(theme.bodyFont(.caption2)).foregroundStyle(theme.palette.inkTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(e.bytes.map(uiHuman) ?? L("Unknown")).monospacedDigit().font(theme.bodyFont(.callout))
            Button { model.reveal(e) } label: { Image(systemName: "magnifyingglass.circle") }
                .help(L("Show in Finder")).accessibilityLabel(L("Show in Finder"))
        }
        .accessibilityElement(children: .combine)
    }

    private func entrySub(_ e: TrashEntry) -> String {
        var parts: [String] = []
        if let o = e.originalPath { parts.append(LF("From %@", displayPath(URL(fileURLWithPath: o)))) }
        if let d = e.trashedAt { parts.append(LF("Trashed %@", shortDate(d))) }
        return parts.isEmpty ? L("Original location not recorded") : parts.joined(separator: " · ")
    }

    private var legacyRecords: [TrashRecord] {
        let recorded = Set(store.batches.flatMap(\.moved).compactMap { entry -> String? in
            if case .moved(let path, _, _) = entry.outcome { return path }
            return nil
        })
        return store.trashHistory.filter { !recorded.contains($0.inTrash.path) }
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
                Button(L("Refresh")) { model.refresh(); model.loadInventory(batches: store.batches) }.disabled(model.measuring || model.emptying)
                Spacer()
                Button(L("Open in Finder")) { model.openInFinder() }
                if model.emptying {
                    ProgressView().controlSize(.small)
                    Text(L("Emptying the Trash…")).font(theme.bodyFont(.callout))
                }
                if model.canAskFinderToEmpty {
                    Button(L("Empty Trash"), role: .destructive) { confirmEmpty = true }
                        .disabled(store.isTrashing || model.emptying || model.measuring)
                }
            }
            // Always say what happened: without Full Disk Access the Trash card reads "Cannot
            // measure", so a successful empty used to look exactly like a button that did nothing.
            .alert(model.emptyOutcome.map(outcomeTitle) ?? "",
                   isPresented: Binding(get: { model.emptyOutcome != nil },
                                        set: { if !$0 { model.emptyOutcome = nil } }),
                   presenting: model.emptyOutcome) { outcome in
                switch outcome {
                case .emptied:
                    Button(L("Close"), role: .cancel) { }
                case .failed(_, let needsPermission):
                    if needsPermission {
                        Button(L("Open System Settings")) { model.openAutomationSettings() }
                    }
                    Button(L("Open in Finder")) { model.openInFinder() }
                    Button(L("Close"), role: .cancel) { }
                }
            } message: { outcome in
                switch outcome {
                case .emptied:
                    Text(L("The Trash has been emptied."))
                case .failed(let message, let needsPermission):
                    Text(needsPermission
                         ? L("Allow CleanPilot to control Finder in System Settings › Privacy & Security › Automation, then try again.") + "\n\n" + message
                         : message)
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

    private func outcomeTitle(_ outcome: TrashModel.EmptyOutcome) -> String {
        if case .emptied = outcome { return L("Trash emptied") }
        return L("Couldn't empty the Trash")
    }

    private func sourceTitle(_ source: String) -> String {
        switch source {
        case "caches": return L("App Caches")
        case "big-files": return L("Large Files")
        case "old-files": return L("Files not modified recently")
        case "duplicates": return L("Duplicates")
        case "leftovers": return L("Leftovers")
        case "uninstall": return L("Uninstall Apps")
        case "node-modules": return L("node_modules")
        case "folder-drill": return L("Folder details")
        case "crash-dumps": return L("Crash dumps")
        case "diagnostic-reports": return L("System diagnostics reports")
        case "crash-dump-trim": return L("Trim by policy")
        case "overview": return L("Overview")
        case "smart-clean": return L("Smart Scan")
        case "dev-cleanup": return L("Developer Cleanup")
        case "first-clean": return L("Overview")
        default: return source
        }
    }
}
