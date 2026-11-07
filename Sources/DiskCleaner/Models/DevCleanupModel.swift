import SwiftUI
import Combine
import DiskCleanerCore

/// V2-DEV (docs/enhance-feat.md §11, plan-v2.md §6.7): the Dev Cleanup center over the existing
/// dev-cache model and node_modules model. Owns no scan of its own and no selection of its own:
/// every checkbox is the underlying model's, so the old Dev Caches / node_modules pages and this
/// center always agree. Held by `ScanStore`.
@MainActor
final class DevCleanupModel: ObservableObject, ScanStatusReporting {
    let caches: CachesModel
    let nodeModules: NMModel
    private var bag = Set<AnyCancellable>()

    init(caches: CachesModel, nodeModules: NMModel) {
        self.caches = caches
        self.nodeModules = nodeModules
        caches.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        nodeModules.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    // MARK: Inventory

    /// Every row, largest first (unknown sizes last).
    var items: [DevInventoryItem] {
        devInventory(caches: caches.items, projects: nodeModules.items)
            .sorted { ($0.bytes ?? -1, $1.id) > ($1.bytes ?? -1, $0.id) }
    }

    /// Rows of one kind (nil = all). Filters never change selection.
    func rows(kind: DevDataKind?, ecosystem: DevEcosystem? = nil, query: String = "") -> [DevInventoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { r in
            (kind == nil || r.kind == kind) && (ecosystem == nil || r.ecosystem == ecosystem)
                && (q.isEmpty || r.name.lowercased().contains(q) || (r.nameIsKey && L(r.name).lowercased().contains(q))
                    || r.paths.contains { $0.lowercased().contains(q) })
        }
    }

    /// Kinds that have rows, in `DevDataKind.allCases` order (left column).
    var kinds: [DevDataKind] {
        let present = Set(items.map(\.kind))
        return DevDataKind.allCases.filter(present.contains)
    }

    /// Ecosystems that have rows (filter menu).
    var ecosystems: [DevEcosystem] {
        let present = Set(items.map(\.ecosystem))
        return DevEcosystem.allCases.filter(present.contains)
    }

    var totals: DevInventoryTotals { devInventoryTotals(items) }

    func selection(of kind: DevDataKind?) -> GroupSelection { devKindSelection(items, kind: kind) }

    // MARK: Selection (forwarded to the owning model)

    func setSelected(_ id: String, _ on: Bool) {
        if id.hasPrefix("kb:") {
            let pattern = String(id.dropFirst(3))
            for i in caches.items.indices where caches.items[i].entry.path == pattern {
                // Same rule as the Dev Caches page: unmeasured rows cannot be selected.
                caches.items[i].selected = on && caches.items[i].size != nil
            }
        } else if id.hasPrefix("nm:") {
            let project = String(id.dropFirst(3))
            for i in nodeModules.items.indices
            where URL(fileURLWithPath: nodeModules.items[i].project).standardizedFileURL.path == project {
                nodeModules.items[i].selected = on
            }
        }
    }

    /// Group checkbox of a kind (nil = everything): eligible rows only; a full kind clears.
    func toggle(kind: DevDataKind?) {
        let t = devKindToggle(items, kind: kind)
        for id in t.ids { setSelected(id, t.on) }
    }

    // MARK: Scan

    /// Scans both sources. Does not restart a source that is already scanning.
    func scan() {
        if !caches.scanning { caches.load(force: true) }
        if !nodeModules.scanning { nodeModules.scan() }
    }

    func stop() {
        caches.stop()
        nodeModules.stop()
    }

    var scanning: Bool { caches.scanning || nodeModules.scanning }

    var scanState: ScanState {
        let s = [caches.scanState, nodeModules.scanState]
        if s.contains(.scanning) { return .scanning }
        if s.allSatisfy({ $0 == .idle }) { return .idle }
        if s.contains(.stopped) { return .stopped }
        // One source never scanned: the inventory is not complete.
        if s.contains(.idle) { return .stopped }
        return .completed
    }

    /// The older of the two results (staleness follows the oldest data on screen).
    var scannedAt: Date? { [caches.scannedAt, nodeModules.scannedAt].compactMap { $0 }.min() }

    var issues: [ScanIssue] { caches.issues + nodeModules.issues }

    // MARK: Plan + execute (C1/C2)

    /// What "Move to Trash" executes: both models' plans, nested paths collapsed to the outermost.
    func trashPlan() -> [TrashPlanItem] {
        let all = caches.trashPlan() + nodeModules.trashPlan()
        var byPath: [String: TrashPlanItem] = [:]
        var order: [String] = []
        for it in all {
            let k = URL(fileURLWithPath: it.path).standardizedFileURL.path
            if byPath[k] == nil { byPath[k] = it; order.append(k) }
        }
        let outer = Set(dropNested(order))
        return order.filter(outer.contains).compactMap { byPath[$0] }
    }

    /// One batch (source "dev-cleanup"), then both models update their rows.
    func trash(using store: AppStore) async -> TrashBatch? {
        guard let batch = await store.runTrash(trashPlan(), source: "dev-cleanup") else { return nil }
        caches.apply(batch)
        nodeModules.apply(batch)
        return batch
    }
}
