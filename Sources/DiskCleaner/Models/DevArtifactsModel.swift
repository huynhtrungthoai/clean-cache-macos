import SwiftUI
import DiskCleanerCore

/// V2-DEV layer 2: per-project build output and environments (owner decision 07/11/2026:
/// listed, ticked by hand to clean). Held by `ScanStore`; shown through `DevCleanupModel`.
@MainActor
final class DevArtifactsModel: ObservableObject, ScanStatusReporting {
    @Published var items: [DevArtifact] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var scannedAt: Date? = nil
    @Published private(set) var issues: [ScanIssue] = []
    private(set) var progress = ScanProgress(counted: .entries)
    private var task: Task<Void, Never>? = nil

    var selected: [DevArtifact] { items.filter(\.selected) }

    func scan() {
        task?.cancel()
        scanning = true
        scanState = .scanning
        issues = []
        items = []
        progress = ScanProgress(counted: .entries)
        let p = progress
        task = Task {
            let r = await findDevArtifacts(progress: p)
            guard !Task.isCancelled else { return }
            self.items = r.artifacts
            self.issues = permissionIssues(r.unreadable)
            self.scanning = false
            self.scanState = .completed
            self.scannedAt = Date()
        }
    }

    func stop() {
        task?.cancel()
        if scanning { scanState = .stopped; scannedAt = Date() }
        scanning = false
    }

    /// Selected folders, re-checked against the deletion gate.
    func trashPlan() -> [TrashPlanItem] {
        selected.map { a in
            TrashPlanItem(url: URL(fileURLWithPath: a.path),
                          name: URL(fileURLWithPath: a.projectRoot).lastPathComponent + "/" + URL(fileURLWithPath: a.path).lastPathComponent,
                          bytes: a.bytes ?? 0)
        }.filter { isReclaimableWhole($0.url) }
    }

    /// Drops folders that are gone, clears the selection.
    func apply(_ batch: TrashBatch) {
        items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        for i in items.indices { items[i].selected = false }
    }
}
