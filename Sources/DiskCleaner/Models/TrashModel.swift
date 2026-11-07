import AppKit
import DiskCleanerCore

/// Trash page state (Request "Thùng rác", docs/enhance-feat.md §11). Measures the Trash,
/// opens it in Finder and — only after the view has asked the user — asks Finder to empty it.
/// Moving and restoring items is `AppStore.runTrash` / `AppStore.undo` (batch history).
@MainActor
final class TrashModel: ObservableObject {
    struct Summary: Equatable {
        var items: Int
        var bytes: Int64
    }

    /// nil = not measured yet or not readable (the sandboxed build cannot read ~/.Trash).
    @Published private(set) var summary: Summary? = nil
    @Published private(set) var measuring = false
    @Published private(set) var emptying = false
    /// Localised reason from the last failed empty request; nil after success.
    @Published private(set) var lastError: String? = nil
    /// Outcome of the last empty request, for a visible result even when the Trash cannot be
    /// measured (no Full Disk Access): before this, success and failure both looked like nothing.
    @Published var emptyOutcome: EmptyOutcome? = nil

    enum EmptyOutcome: Identifiable {
        case emptied
        case failed(message: String, needsPermission: Bool)
        var id: String {
            switch self { case .emptied: return "ok"; case .failed(let m, _): return m }
        }
    }
    private var task: Task<Void, Never>? = nil

    /// Finder can be told to empty the Trash only outside the sandbox (App Store build:
    /// open the Trash window instead).
    var canAskFinderToEmpty: Bool { !HomeAccess.runsSandboxed }

    func refresh() {
        task?.cancel()
        measuring = true
        task = Task {
            let r = await trashInfo()
            guard !Task.isCancelled else { return }
            self.summary = r.map { Summary(items: $0.items, bytes: $0.bytes) }
            self.measuring = false
        }
    }

    func openInFinder() { openTrashInFinder() }

    // MARK: - V2-TRASH inventory (docs/enhance-feat.md §11)

    /// Trash folders per volume with their entries; nil = not listed yet. Read-only.
    @Published private(set) var volumes: [TrashVolume]? = nil
    @Published private(set) var listing = false
    private var listTask: Task<Void, Never>? = nil

    /// Lists every Trash folder. `batches` (store.batches) only adds original paths of items this
    /// app moved; it is never used as the list itself.
    func loadInventory(batches: [TrashBatch] = []) {
        listTask?.cancel()
        listing = true
        listTask = Task {
            let v = await trashInventory(batches: batches)
            guard !Task.isCancelled else { return }
            self.volumes = v
            self.listing = false
        }
    }

    func cancelInventory() {
        listTask?.cancel()
        listing = false
    }

    /// Reveals one Trash entry in Finder (selection only; nothing is moved or deleted).
    func reveal(_ entry: TrashEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.id)])
    }

    /// Permanently empties the WHOLE Trash through Finder. Call only after an explicit
    /// confirmation in the view ("cannot be undone"). Clears the batch history's undo ability
    /// implicitly: restores will report `goneFromTrash`.
    /// Returns true on success; on failure `lastError` holds the reason.
    @discardableResult
    func emptyInFinder() async -> Bool {
        guard canAskFinderToEmpty, !emptying else { return false }
        emptying = true
        defer { emptying = false }
        // NSAppleScript is not thread-safe: run it on the main actor, it only waits for Finder.
        do {
            try emptyTrashViaFinder()
            lastError = nil
            emptyOutcome = .emptied
            refresh()
            if volumes != nil { loadInventory() }
            return true
        } catch let e as TrashError {
            if case .finderCanceled = e { lastError = nil; return false }   // the user said no in Finder
            lastError = e.detail.isEmpty ? L(e.reasonKey) : LF("%@: %@", L(e.reasonKey), e.detail)
            var permission = false
            if case .automationDenied = e { permission = true }
            emptyOutcome = .failed(message: lastError ?? "", needsPermission: permission)
        } catch {
            lastError = error.localizedDescription
            emptyOutcome = .failed(message: lastError ?? "", needsPermission: false)
        }
        return false
    }

    /// System Settings › Privacy & Security › Automation, where "CleanPilot → Finder" is allowed.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
